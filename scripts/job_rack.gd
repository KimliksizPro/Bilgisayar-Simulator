extends Node3D
## Bekleyen işler rafı: sağ duvarın önünde 2 katlı, 6 gözlü raf. Müşterinin bıraktığı ve bitmiş cihazlar burada durur.
## Her gözün altında numara ve durum ışığı (kehribar = bekliyor, yeşil = hazır, kırmızı = gecikti) vardır;
## `Game.max_active_jobs()` kadar göz açıktır, gerisi kilitli. Cihazların üstündeki fiş etiketi job_store.gd'de.
## Yerel eksenler: +Z raf önü (odaya bakar), X boyunca üç sütun, Y yukarı.

const MU := preload("res://scripts/mesh_util.gd")
const ST := preload("res://scripts/job_store.gd")

const SLOTS := 6
const COLS := 3
const COL_W := 0.52
const DEPTH := 0.42
const LEVELS := [0.9, 0.4]         # üst sıra gözler 0-2, alt sıra 3-5
const TOP := 1.4
const POS := Vector3(3.985, 0.0, -0.42)
const YAW := -90.0

var lights: Array = []             # göz başına durum ışığı malzemesi
var _locks: Array = []             # göz başına "KİLİTLİ" etiketi
var occ: Array = []                # göz -> iş fiş no'su (0 = boş)


func build() -> Node3D:
	position = POS
	rotation_degrees.y = YAW
	name = "JobRack"
	var wood := MU.pbr("laminate", 1.0)
	var back := MU.pbr("wall", 0.5, Color(0.88, 0.9, 0.93), 0.3)
	var w := COLS * COL_W + 0.06
	var h := TOP + 0.1
	MU.box(self, Vector3(w, h - 0.28, 0.015), Vector3(0, 0.28 + (h - 0.28) / 2, 0.0075), back)
	for sx in [-1, 1]:
		var x: float = sx * (w / 2 - 0.0125)
		MU.static_box(self, Vector3(0.025, h - 0.28, DEPTH), Vector3(x, 0.28 + (h - 0.28) / 2, DEPTH / 2), null)
		MU.rbox(self, Vector3(0.025, h - 0.28, DEPTH), Vector3(x, 0.28 + (h - 0.28) / 2, DEPTH / 2), wood, 0.006)
	# ayaklar (alt gözün altı açık, ayaklar ve süpürgelik)
	for sx in [-1, 1]:
		MU.rbox(self, Vector3(0.05, 0.28, 0.05), Vector3(sx * (w / 2 - 0.0125), 0.14, DEPTH - 0.04), wood, 0.008)
	for y in LEVELS + [TOP]:
		MU.static_box(self, Vector3(w, 0.03, DEPTH), Vector3(0, y - 0.015, DEPTH / 2), null)
		MU.rbox(self, Vector3(w, 0.03, DEPTH), Vector3(0, y - 0.015, DEPTH / 2), wood, 0.006)
		MU.box(self, Vector3(w - 0.08, 0.004, 0.01), Vector3(0, y - 0.032, DEPTH - 0.03), MU.mat(Color(1.0, 0.95, 0.85), 0, 0.5, 3.0))
	var sl := OmniLight3D.new()
	sl.position = Vector3(0, 1.0, 0.45)
	sl.omni_range = 1.6
	sl.light_energy = 0.6
	sl.light_color = Color(1.0, 0.95, 0.88)
	add_child(sl)
	# tabela
	MU.rbox(self, Vector3(1.0, 0.13, 0.02), Vector3(0, TOP + 0.085, 0.14), MU.mat(Color(0.7, 0.18, 0.12), 0, 0.5), 0.008)
	var title := MU.label(self, "BEKLEYEN İŞLER", Vector3(0, TOP + 0.085, 0.152), 56, Color(1, 1, 1), Vector3.ZERO, 0.0014)
	title.double_sided = false
	occ.resize(SLOTS)
	occ.fill(0)
	for i in SLOTS:
		_build_slot(i)
	return self


func slot_xz(i: int) -> Vector2:
	return Vector2((i % COLS - 1) * COL_W, DEPTH * 0.5)


func slot_y(i: int) -> float:
	return LEVELS[i / COLS]


func _build_slot(i: int) -> void:
	var xz := slot_xz(i)
	var y := slot_y(i)
	# numara plakası + durum ışığı rafın ön kenarında
	var plate := MU.box(self, Vector3(0.1, 0.04, 0.004), Vector3(xz.x - 0.17, y - 0.015, DEPTH + 0.002), MU.mat(Color(0.12, 0.13, 0.16), 0, 0.5))
	MU.no_merge(plate)
	var num := MU.label(self, str(i + 1), Vector3(xz.x - 0.17, y - 0.015, DEPTH + 0.0045), 40, Color(1, 1, 1), Vector3.ZERO, 0.0009)
	num.double_sided = false
	var lm := MU.new_mat(Color(0.15, 0.15, 0.15), 0, 0.3, 0.0)
	var lamp := MU.sphere(self, 0.014, Vector3(xz.x + 0.17, y - 0.015, DEPTH + 0.008), lm, Vector3(1, 1, 0.5))
	MU.no_merge(lamp)
	lights.append(lm)
	var lk := MU.label(self, "KİLİTLİ", Vector3(xz.x, y + 0.2, DEPTH - 0.06), 48, Color(0.75, 0.2, 0.15), Vector3.ZERO, 0.0014)
	lk.double_sided = false
	_locks.append(lk)
	# etkileşim kutusu: boş göze koy / dolu gözdeki cihazı al
	MU.interactable(self, Vector3(COL_W - 0.04, 0.47, DEPTH - 0.02), Vector3(xz.x, y + 0.235, DEPTH / 2),
		func(p): return Game.job_mgr.rack_hint(i, p) if Game.job_mgr else "",
		func(p): if Game.job_mgr: Game.job_mgr.rack_use(i, p))


## Cihazın göz içindeki yerel dönüşümü: kasa camı öne bakar (-90°), laptop/telefon düz.
func slot_transform(i: int, dev) -> Transform3D:
	var xz := slot_xz(i)
	var y := slot_y(i) + 0.002
	if dev.has_method("slot_open"):
		return Transform3D(Basis.IDENTITY, Vector3(xz.x, y + dev.LIFT, xz.y))
	return Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(-90), 0)), Vector3(xz.x, y, xz.y))


func free_slot() -> int:
	for i in mini(Game.max_active_jobs(), SLOTS):
		if occ[i] == 0:
			return i
	return -1


func slot_of(ticket: int) -> int:
	return occ.find(ticket)


## Cihazı gözün içine koyar (düğüm rafın çocuğu olur).
func put(i: int, dev, ticket: int) -> void:
	occ[i] = ticket
	if dev.get_parent() != self:
		if dev.get_parent():
			dev.reparent(self, false)
		else:
			add_child(dev)
	dev.transform = slot_transform(i, dev)


## Göz dolu işaretlenir (düğümü çağıran yerleştirir).
func occupy(i: int, ticket: int) -> void:
	occ[i] = ticket


func clear_slot(ticket: int) -> void:
	var i := occ.find(ticket)
	if i >= 0:
		occ[i] = 0


## Işıkları ve kilit etiketlerini günceller (jobs: fiş no -> iş kaydı).
func refresh(now: float, recs: Dictionary) -> void:
	var cap: int = Game.max_active_jobs()
	for i in SLOTS:
		_locks[i].visible = i >= cap
		var t: int = occ[i]
		var lm: StandardMaterial3D = lights[i]
		if t != 0 and recs.has(t):
			var c := ST.status_color(recs[t], now)
			lm.albedo_color = c
			lm.emission_enabled = true
			lm.emission = c
			lm.emission_energy_multiplier = 3.0
		else:
			lm.albedo_color = Color(0.15, 0.15, 0.15)
			lm.emission_enabled = false
