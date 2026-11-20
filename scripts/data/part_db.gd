extends RefCounted
## Parça tanımları (data/parts.json): PartDef kayıtları, tür (kategori) ve kasa form faktörü bilgisi.
## Yeni parça = JSON'a bir kayıt eklemek (bkz. ROADMAP Faz 1/2).

const PATH := "res://data/parts.json"
const DEVICES := ["pc", "laptop", "phone"]

var _defs := {}            # id -> PartDef
var _order: Array = []     # JSON sırasıyla PartDef'ler
var _legacy_map := {}      # legacy_id ("tür:seviye") -> id
var _by_key := {}          # "tür:seviye" -> ilk eşleşen id (yedek)
var _cats := {}            # tür -> {name, size, center, shelf_row, shelf_tilt, hold}
var _cases := {}           # case_id -> {id, name, form_factors, max_gpu_mm, max_cooler_mm, max_rad_mm, size, fan_slots}
var _hold_default := [Vector3(15, -35, 0), Vector3.ZERO]


func load_all() -> void:
	_defs = {}
	_order = []
	_legacy_map = {}
	_by_key = {}
	_cats = {}
	_cases = {}
	var data = DB.read_json(PATH, {})
	if typeof(data) != TYPE_DICTIONARY:
		push_error("PartDB: parts.json kök öğesi sözlük olmalı")
		return
	var hd = data.get("hold_default", {})
	if typeof(hd) == TYPE_DICTIONARY and hd.has("euler"):
		_hold_default = [PartDef.vec3(hd.euler), PartDef.vec3(hd.get("offset", [0, 0, 0]))]
	var cases_data = data.get("cases", {})
	if typeof(cases_data) == TYPE_DICTIONARY:
		for k in cases_data:
			_add_case(str(k), cases_data[k])
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


func _add_case(k: String, c: Dictionary) -> void:
	_cases[k] = {
		"id": k,
		"name": str(c.get("name", k)),
		"form_factors": c.get("form_factors", ["ATX", "mATX", "ITX"]),
		"max_gpu_mm": int(c.get("max_gpu_mm", 330)),
		"max_cooler_mm": int(c.get("max_cooler_mm", 165)),
		"max_rad_mm": int(c.get("max_rad_mm", 240)),
		"size": PartDef.vec3(c.get("size", [0.22, 0.46, 0.44])),
		"fan_slots": int(c.get("fan_slots", 2)),
	}


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
	if not p.legacy_id.is_empty():
		if _legacy_map.has(p.legacy_id):
			push_error("PartDB: yinelenen legacy_id: " + p.legacy_id)
			return
		_legacy_map[p.legacy_id] = p.id
	var key := "%s:%d" % [p.category, p.tier]
	if not _by_key.has(key):
		_by_key[key] = p.id
	_defs[p.id] = p
	_order.append(p)


# ---------------------------------------------------------------- sorgular

## SKU kimliğini veya eski "tür:seviye" anahtarını kanonik SKU kimliğine çevirir.
func resolve_id(id_or_legacy: String) -> String:
	if _defs.has(id_or_legacy):
		return id_or_legacy
	if _legacy_map.has(id_or_legacy):
		return _legacy_map[id_or_legacy]
	if _by_key.has(id_or_legacy):
		return _by_key[id_or_legacy]
	return id_or_legacy


func has_def(id: String) -> bool:
	return _defs.has(resolve_id(id))


## Tanım; yoksa null. Eski "tür:seviye" anahtarını da çözer.
func get_def(id: String) -> PartDef:
	return _defs.get(resolve_id(id), null)


## (tür, seviye) -> SKU. Önce legacy_id eşleşmesine, yoksa ilk eşleşen kayda bakar.
func id_for(category: String, tier: int) -> String:
	var key := "%s:%d" % [category, tier]
	if _legacy_map.has(key):
		return _legacy_map[key]
	return _by_key.get(key, "")


## (tür, seviye) için tanım; yoksa null.
func def_for(category: String, tier: int) -> PartDef:
	return _defs.get(id_for(category, tier), null)


func all() -> Array:
	return _order


func by_category(cat: String) -> Array:
	return _order.filter(func(p): return p.category == cat)


## Kategori (boşsa tümü) içinde koşulu sağlayan PartDef'ler.
func filter_parts(cat: String, pred: Callable) -> Array:
	var src := _order if cat.is_empty() else by_category(cat)
	return src.filter(pred)


## ParçaNet'te satılanlar.
func catalog() -> Array:
	return _order.filter(func(p): return p.catalog)


## ParçaNet'te satılanların SKU kimlikleri (JSON sırası).
func catalog_ids() -> Array:
	var out := []
	for p in catalog():
		out.append(p.id)
	return out


## Eski biçimde katalog: [[tür, seviye], ...] (sıra JSON sırasıdır).
func catalog_pairs() -> Array:
	var out := []
	for p in catalog():
		out.append([p.category, p.tier])
	return out


## Rafta gösterilenler. devices boş değilse yalnızca o cihaz türleri.
func shelf_items(devices: Array = []) -> Array:
	return _order.filter(func(p): return p.shelf and (devices.is_empty() or devices.has(p.device)))


## Yeni oyun başlangıç stoğu: {sku: adet} (yalnızca > 0 olanlar).
func start_stock() -> Dictionary:
	var out := {}
	for p in _order:
		if p.start_stock > 0:
			out[p.id] = p.start_stock
	return out


## Kasa form faktörü tanımı; yoksa boş sözlük.
func case_def(id: String) -> Dictionary:
	return _cases.get(id, {})


func cases() -> Dictionary:
	return _cases


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


## Elde tutuş (SKU kimliğine göre): [dönüş (derece), kaydırma]. Önce SKU ezmesi, sonra tür, sonra varsayılan.
func hold_pose_id(sku: String) -> Array:
	var d := get_def(sku)
	if d:
		if not d.hold.is_empty():
			return [d.hold.euler, d.hold.offset]
		var c: Dictionary = _cats.get(d.category, {})
		if c.get("hold") != null:
			return c.hold
		return _hold_default
	var fc: Dictionary = _cats.get(sku, {})
	if fc.get("hold") != null:
		return fc.hold
	return _hold_default


## Elde tutuş: [dönüş (derece), kaydırma]. Önce SKU ezmesi, sonra tür, sonra varsayılan.
func hold_pose(cat: String, tier: int) -> Array:
	var id := id_for(cat, tier)
	if not id.is_empty():
		return hold_pose_id(id)
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
