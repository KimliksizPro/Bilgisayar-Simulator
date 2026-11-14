extends RefCounted
## Parça tanımları (data/parts.json): PartDef kayıtları + tür (kategori) bilgisi.
## Yeni parça = JSON'a bir kayıt eklemek (bkz. ROADMAP Faz 1/2).

const PATH := "res://data/parts.json"
const DEVICES := ["pc", "laptop", "phone"]

var _defs := {}            # id -> PartDef
var _order: Array = []     # JSON sırasıyla PartDef'ler
var _by_key := {}          # "tür:seviye" -> id
var _cats := {}            # tür -> {name, size, center, shelf_row, shelf_tilt, hold}
var _hold_default := [Vector3(15, -35, 0), Vector3.ZERO]


func load_all() -> void:
	_defs = {}
	_order = []
	_by_key = {}
	_cats = {}
	var data = DB.read_json(PATH, {})
	if typeof(data) != TYPE_DICTIONARY:
		push_error("PartDB: parts.json kök öğesi sözlük olmalı")
		return
	var hd = data.get("hold_default", {})
	if typeof(hd) == TYPE_DICTIONARY and hd.has("euler"):
		_hold_default = [PartDef.vec3(hd.euler), PartDef.vec3(hd.get("offset", [0, 0, 0]))]
	var cats = data.get("categories", {})
	for k in cats:
		_add_category(str(k), cats[k])
	var parts = data.get("parts", [])
	if typeof(parts) != TYPE_ARRAY:
		push_error("PartDB: 'parts' dizi olmalı")
		return
	for i in parts.size():
		if typeof(parts[i]) != TYPE_DICTIONARY:
			push_error("PartDB: parts[%d] sözlük değil" % i)
			continue
		_add_part(parts[i], i)


func _add_category(k: String, c: Dictionary) -> void:
	for f in ["name", "size", "center"]:
		if not c.has(f):
			push_error("PartDB: kategori '%s' alanı eksik: %s" % [k, f])
			return
	var info := {
		"name": str(c.name),
		"size": PartDef.vec3(c.size),
		"center": PartDef.vec3(c.center),
		"shelf_row": int(c.get("shelf_row", -1)),   # rafta tercih edilen sıra (0 = en üst), -1 = fark etmez
		"shelf_tilt": float(c.get("shelf_tilt", 0.0)),
		"hold": null,
	}
	var h = c.get("hold", null)
	if typeof(h) == TYPE_DICTIONARY and h.has("euler"):
		info.hold = [PartDef.vec3(h.euler), PartDef.vec3(h.get("offset", [0, 0, 0]))]
	_cats[k] = info


func _add_part(d: Dictionary, idx: int) -> void:
	for f in ["id", "category", "tier", "name", "price"]:
		if not d.has(f):
			push_error("PartDB: parts[%d] alanı eksik: %s" % [idx, f])
			return
	var p := PartDef.from_dict(d)
	if _defs.has(p.id):
		push_error("PartDB: yinelenen id: " + p.id)
		return
	if not _cats.has(p.category):
		push_error("PartDB: '%s' bilinmeyen kategori: %s" % [p.id, p.category])
		return
	if not DEVICES.has(p.device):
		push_error("PartDB: '%s' bilinmeyen cihaz: %s" % [p.id, p.device])
		return
	if not p.model.has("builder"):
		push_error("PartDB: '%s' model.builder eksik" % p.id)
		return
	var key := "%s:%d" % [p.category, p.tier]
	if _by_key.has(key):
		push_error("PartDB: '%s' ile '%s' aynı (kategori, seviye) çiftini kullanıyor: %s" % [p.id, _by_key[key], key])
		return
	_by_key[key] = p.id
	_defs[p.id] = p
	_order.append(p)


# ---------------------------------------------------------------- sorgular

func has_def(id: String) -> bool:
	return _defs.has(id)


## Tanım; yoksa null.
func get_def(id: String) -> PartDef:
	return _defs.get(id, null)


## (tür, seviye) -> SKU. Eski parçalarda "tür:seviye"; tanım yoksa boş metin.
func id_for(category: String, tier: int) -> String:
	return _by_key.get("%s:%d" % [category, tier], "")


## (tür, seviye) için tanım; yoksa null.
func def_for(category: String, tier: int) -> PartDef:
	return _defs.get(id_for(category, tier), null)


func all() -> Array:
	return _order


func by_category(cat: String) -> Array:
	return _order.filter(func(p): return p.category == cat)


## ParçaNet'te satılanlar.
func catalog() -> Array:
	return _order.filter(func(p): return p.catalog)


## Eski biçimde katalog: [[tür, seviye], ...] (sıra JSON sırasıdır).
func catalog_pairs() -> Array:
	var out := []
	for p in catalog():
		out.append([p.category, p.tier])
	return out


## Rafta gösterilenler. devices boş değilse yalnızca o cihaz türleri.
func shelf_items(devices: Array = []) -> Array:
	return _order.filter(func(p): return p.shelf and (devices.is_empty() or devices.has(p.device)))


## Yeni oyun başlangıç stoğu: {"tür:seviye": adet} (yalnızca > 0 olanlar).
func start_stock() -> Dictionary:
	var out := {}
	for p in _order:
		if p.start_stock > 0:
			out[p.id] = p.start_stock
	return out


## Tür bilgisi: {name, size, center, shelf_row, shelf_tilt, hold}; bilinmeyen türde boş sözlük.
func category_info(cat: String) -> Dictionary:
	return _cats.get(cat, {})


func has_category(cat: String) -> bool:
	return _cats.has(cat)


func categories() -> Array:
	return _cats.keys()


## Türün Türkçe adı; bilinmeyen türde türün kendisi.
func type_name(cat: String) -> String:
	return _cats[cat].name if _cats.has(cat) else cat


## Elde tutuş: [dönüş (derece), kaydırma]. Önce SKU ezmesi, sonra tür, sonra varsayılan.
func hold_pose(cat: String, tier: int) -> Array:
	var d := def_for(cat, tier)
	if d and not d.hold.is_empty():
		return [d.hold.euler, d.hold.offset]
	var c: Dictionary = _cats.get(cat, {})
	if c.get("hold") != null:
		return c.hold
	return _hold_default


# ---------------------------------------------------------------- raf yerleşimi

## Parçaları satırlara dizer (raf yerleşimi). entries: [{"def": PartDef, "w": genişlik}].
## Her tür kendi tercih ettiği sıraya (shelf_row) konur; sığmazsa sonraki sıraya taşar.
## Dönüş: row_count uzunlukta satırlar: {"items": [{"def", "w", "c"}], "width": toplam},
## "c" = öğenin satır başından merkez uzaklığı.
static func flow_rows(entries: Array, max_w: float, row_count: int) -> Array:
	var rows := []
	for i in row_count:
		rows.append({"items": [], "width": 0.0})
	for e in entries:
		var info: Dictionary = DB.parts.category_info(e.def.category)
		var pref := int(info.get("shelf_row", -1))
		var r := clampi(pref, 0, row_count - 1) if pref >= 0 else 0
		while r < row_count - 1 and rows[r].width + e.w > max_w:
			r += 1
		if rows[r].width + e.w > max_w:
			push_warning("PartDB: raf dolu, '%s' sığmıyor (taşıyor)" % e.def.id)
		rows[r].items.append({"def": e.def, "w": e.w, "c": rows[r].width + e.w * 0.5})
		rows[r].width += e.w
	return rows
