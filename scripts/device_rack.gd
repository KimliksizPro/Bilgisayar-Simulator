extends RefCounted
## Arka duvarda küçük "MOBİL PARÇA" rafı: laptop ve telefon parçaları.
## Ana stok rafıyla aynı davranır (main._shelf_hint / _shelf_use, raf etiketleri main._price_labels).

const MU := preload("res://scripts/mesh_util.gd")
const PM := preload("res://scripts/part_models.gd")

const POS := Vector3(-2.35, 0.0, -2.955)   # arka duvar önü (raf arkası)
const WIDTH := 1.2
const DEPTH := 0.26
const LEVELS := [1.02, 1.32, 1.62]
const K := 1.25                             # raftaki model büyütmesi (küçük parçalar daha büyük)
const K_SMALL := 1.7

## [raf, x, tür, eğim(derece, X ekseni)]
const ITEMS := [
	[0, -0.38, "lap_bat", 0.0], [0, 0.02, "tel_bat", 0.0], [0, 0.34, "tel_port", 0.0],
	[1, -0.36, "lap_ram", 0.0], [1, 0.0, "lap_ssd", 0.0], [1, 0.36, "tel_scr", 62.0],
	[2, -0.2, "lap_scr", 62.0],
]


static func build(main: Node3D) -> void:
	var root := Node3D.new()
	root.name = "DeviceRack"
	root.position = POS
	main.add_child(root)
	var wood := MU.pbr("laminate", 1.0)
	var back := MU.pbr("wall", 0.5, Color(0.88, 0.9, 0.93), 0.3)
	var top: float = LEVELS[-1] + 0.36
	var mid_y: float = (LEVELS[0] - 0.06 + top) / 2.0
	var h: float = top - (LEVELS[0] - 0.06)
	# arka pano + yan paneller
	MU.box(root, Vector3(WIDTH, h, 0.015), Vector3(0, mid_y, 0.0075), back)
	for i in 7:
		for j in 9:
			MU.cyl(root, 0.003, 0.002, Vector3(-0.54 + i * 0.18, LEVELS[0] + 0.12 + j * 0.08, 0.016), MU.mat(Color(0.6, 0.62, 0.66)), Vector3(90, 0, 0), 8)
	for sx in [-1, 1]:
		MU.static_box(root, Vector3(0.025, h, DEPTH), Vector3(sx * (WIDTH / 2 + 0.0125), mid_y, DEPTH / 2), null)
		MU.rbox(root, Vector3(0.025, h, DEPTH), Vector3(sx * (WIDTH / 2 + 0.0125), mid_y, DEPTH / 2), wood, 0.006)
	MU.rbox(root, Vector3(WIDTH + 0.05, 0.025, DEPTH), Vector3(0, top, DEPTH / 2), wood, 0.006)
	for y in LEVELS:
		MU.static_box(root, Vector3(WIDTH, 0.02, DEPTH), Vector3(0, y - 0.01, DEPTH / 2), null)
		MU.rbox(root, Vector3(WIDTH, 0.02, DEPTH), Vector3(0, y - 0.01, DEPTH / 2), wood, 0.005)
		MU.box(root, Vector3(WIDTH - 0.06, 0.004, 0.01), Vector3(0, y - 0.022, DEPTH - 0.03), MU.mat(Color(1.0, 0.95, 0.85), 0, 0.5, 3.0))
	var sl := OmniLight3D.new()
	sl.position = Vector3(0, 1.35, 0.35)
	sl.omni_range = 1.3
	sl.light_energy = 0.5
	sl.light_color = Color(1.0, 0.95, 0.88)
	root.add_child(sl)
	# tabela
	MU.rbox(root, Vector3(0.62, 0.1, 0.012), Vector3(0, top + 0.08, 0.02), MU.mat(Color(0.12, 0.3, 0.55), 0, 0.5), 0.006)
	var title := MU.label(root, "LAPTOP & TELEFON", Vector3(0, top + 0.08, 0.027), 56, Color(1, 1, 1), Vector3.ZERO, 0.0012)
	title.double_sided = false
	for it in ITEMS:
		_item(main, root, LEVELS[it[0]], it[1], it[2], it[3])


static func _item(main: Node3D, root: Node3D, shelf_y: float, x: float, type: String, tilt: float) -> void:
	var info: Dictionary = PM.INFO[type]
	var built := PM.build(type, 1)
	var n: Node3D = built.node
	var sz: Vector3 = info.size
	var k := K_SMALL if sz.x < 0.1 and tilt == 0.0 else K
	n.scale = Vector3.ONE * k
	n.rotation_degrees.x = tilt
	# eğik duranlar (ekranlar) arka panoya yaslanır
	var z := DEPTH * 0.45 if tilt == 0.0 else 0.03 + sz.z * k * 0.5 * cos(deg_to_rad(tilt))
	var y := sz.y * k * 0.5 if tilt == 0.0 else sz.z * k * 0.5 * sin(deg_to_rad(tilt)) + 0.004
	n.position = Vector3(x, shelf_y + y, z)
	root.add_child(n)
	MU.no_merge(n)  # stok bitince gizlenebilsin
	var dname := PM.display_name(type, 1)
	var box := Vector3(maxf(sz.x * k, 0.12), maxf(y * 2.0, 0.06) + 0.04, DEPTH - 0.02)
	MU.interactable(root, box, Vector3(x, shelf_y + box.y / 2, DEPTH / 2),
		func(p): return main._shelf_hint(p, type, 1, dname),
		func(p): main._shelf_use(p, type, 1))
	# fiyat etiketi: rafın ön kenarından sarkar
	var tag := MU.box(root, Vector3(0.3, 0.054, 0.002), Vector3(x, shelf_y - 0.037, DEPTH + 0.002), MU.mat(Color(1.0, 0.92, 0.4)))
	tag.name = "PriceTag"
	var l := MU.label(root, "", Vector3(x, shelf_y - 0.037, DEPTH + 0.0035), 21, Color(0.1, 0.1, 0.1), Vector3.ZERO, 0.001)
	l.double_sided = false
	main._price_labels.append([l, dname, type, 1, n])
