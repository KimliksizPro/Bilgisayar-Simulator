extends RefCounted
## Dükkânın ahşap / mavi-gri paletinde açık raflı malzeme dolabı.
## Kutular kategori dekorudur; gerçek stok ve parça seçimi inventory_panel.gd'dedir.
## Yerel +Z ön, X genişlik; sol duvarda +90° döndürülür.

const MU := preload("res://scripts/mesh_util.gd")
const PM := preload("res://scripts/part_models.gd")
const SIGN_FONT := preload("res://assets/fonts/Bungee.ttf")

const WIDTH := 1.86
const DEPTH := 0.52
const HEIGHT := 2.12
const POS := Vector3(-3.97, 0.0, -0.85)
const YAW := 90.0

const INK := Color(0.15, 0.21, 0.24)
const PAPER := Color(0.91, 0.88, 0.79)
const BLUE := Color(0.28, 0.38, 0.43)
const RUST := Color(0.55, 0.24, 0.17)


static func build(parent: Node3D) -> Node3D:
	var n := Node3D.new()
	n.name = "PartsCabinet"
	n.position = POS
	n.rotation_degrees.y = YAW
	parent.add_child(n)
	var body := MU.mat(BLUE, 0.15, 0.75)
	var edge := MU.mat(Color(0.20, 0.28, 0.32), 0.2, 0.7)
	var dark := MU.mat(Color(0.10, 0.14, 0.16), 0.1, 0.85)
	var wood := MU.pbr("wood", 0.8)  # tezgâh ve bankoyla aynı ahşap
	var back := MU.mat(Color(0.65, 0.66, 0.60), 0.0, 0.9)
	var metal := MU.mat(Color(0.61, 0.64, 0.62), 0.65, 0.5)
	MU.static_box(n, Vector3(WIDTH, HEIGHT, DEPTH), Vector3(0, HEIGHT * 0.5, DEPTH * 0.5), null)

	# Zeminden az yükseltilmiş, gölgeli baza ve ayak pabuçları.
	for x in [-0.83, 0.83]:
		for z in [0.08, 0.44]:
			MU.rbox(n, Vector3(0.065, 0.08, 0.065), Vector3(x, 0.04, z), dark, 0.008)
	MU.rbox(n, Vector3(WIDTH - 0.06, 0.10, DEPTH - 0.05), Vector3(0, 0.12, 0.25), dark, 0.006)
	MU.rbox(n, Vector3(WIDTH, 0.72, DEPTH - 0.015), Vector3(0, 0.52, 0.26), edge, 0.01)

	# İki kapak ve üstlerinde sığ sarf / yedek parça çekmeceleri.
	for side in [-1.0, 1.0]:
		var x: float = side * 0.456
		MU.rbox(n, Vector3(0.888, 0.505, 0.025), Vector3(x, 0.426, 0.519), body, 0.006)
		MU.rbox(n, Vector3(0.79, 0.395, 0.007), Vector3(x, 0.426, 0.535), body, 0.004)
		# İnce havalandırma yarıkları ve kapak menteşeleri.
		for row in 3:
			MU.rbox(n, Vector3(0.25, 0.006, 0.003), Vector3(x, 0.25 + row * 0.018, 0.54), dark, 0.002)
		for y in [0.28, 0.58]:
			MU.rbox(n, Vector3(0.015, 0.044, 0.014), Vector3(side * 0.885, y, 0.536), metal, 0.003)
		_pull(n, Vector3(side * 0.075, 0.555, 0.54), metal, true)
		MU.rbox(n, Vector3(0.888, 0.165, 0.026), Vector3(x, 0.782, 0.52), body, 0.005)
		_pull(n, Vector3(x, 0.822, 0.541), metal)
		_tag(n, "YEDEK PARÇALAR" if side < 0 else "SARF MALZEME", Vector3(x, 0.753, 0.536), 0.25, 0.035, 25)
	# Dolap kilidi (gösterişsiz, küçük bir metal rozet).
	MU.cyl(n, 0.009, 0.006, Vector3(0.05, 0.64, 0.54), metal, Vector3(90, 0, 0), 12)
	MU.box(n, Vector3(0.002, 0.008, 0.002), Vector3(0.05, 0.64, 0.544), dark)
	MU.rbox(n, Vector3(WIDTH + 0.07, 0.045, DEPTH + 0.06), Vector3(0, 0.9025, 0.27), wood, 0.009)

	# Sığ üstlük: açık raflar, mat arkalık, ayarlanabilir metal raf dikmeleri.
	MU.box(n, Vector3(WIDTH - 0.045, 1.16, 0.018), Vector3(0, 1.505, 0.023), back)
	for x in [-0.916, 0.916]:
		MU.rbox(n, Vector3(0.028, 1.195, 0.39), Vector3(x, 1.5225, 0.20), body, 0.005)
		MU.box(n, Vector3(0.016, 1.10, 0.008), Vector3(x * 0.94, 1.5, 0.037), edge)
		for row in 15:
			MU.box(n, Vector3(0.005, 0.014, 0.002), Vector3(x * 0.94, 0.99 + row * 0.07, 0.042), dark)
	for y in [1.32, 1.71]:
		MU.rbox(n, Vector3(WIDTH - 0.055, 0.028, 0.36), Vector3(0, y, 0.215), wood, 0.004)
		MU.rbox(n, Vector3(WIDTH - 0.07, 0.026, 0.012), Vector3(0, y - 0.009, 0.397), edge, 0.003)
	MU.rbox(n, Vector3(WIDTH + 0.025, 0.035, 0.42), Vector3(0, HEIGHT - 0.0175, 0.21), wood, 0.006)

	# Raf başlığı küçük, basılı bir tabela; cam, neon ve vitrin spotu yok.
	MU.rbox(n, Vector3(WIDTH - 0.035, 0.108, 0.023), Vector3(0, 2.048, 0.393), MU.mat(PAPER, 0.05, 0.8), 0.004)
	MU.box(n, Vector3(0.115, 0.108, 0.026), Vector3(-0.84, 2.048, 0.395), MU.mat(RUST, 0.0, 0.8))
	_text(n, "01", Vector3(-0.84, 2.048, 0.41), 34, PAPER, 0.0011)
	var title := _text(n, "PARÇA DOLABI", Vector3(0.04, 2.05, 0.407), 52, INK, 0.00125)
	title.font = SIGN_FONT
	for x in [-0.89, 0.89]:
		MU.cyl(n, 0.0035, 0.003, Vector3(x, 2.048, 0.407), metal, Vector3(90, 0, 0), 8)

	# Büyük parçalar kutulu, küçükler etiketli gözlerde; hiçbiri havada durmaz.
	_carton(n, Vector3(-0.64, 0.925, 0.20), Vector3(0.36, 0.315, 0.27), "ANAKART", "AM4 / AM5", BLUE, -3.0)
	_carton(n, Vector3(-0.385, 0.925, 0.18), Vector3(0.105, 0.285, 0.245), "PC", "ATX", RUST, 1.5)
	_carton(n, Vector3(0.0, 0.925, 0.22), Vector3(0.48, 0.105, 0.285), "EKRAN KARTI", "PCI EXPRESS", BLUE)
	_carton(n, Vector3(-0.015, 1.03, 0.21), Vector3(0.40, 0.075, 0.245), "EKRAN KARTI", "", RUST, 3.0)
	_carton(n, Vector3(0.60, 0.925, 0.21), Vector3(0.285, 0.255, 0.285), "GÜÇ KAYNAĞI", "550 W / ATX", BLUE, -2.0)
	_organizer(n, Vector3(-0.47, 1.334, 0.07))
	_parts_bin(n, Vector3(0.49, 1.334, 0.21))
	_carton(n, Vector3(-0.57, 1.724, 0.20), Vector3(0.46, 0.065, 0.245), "SOĞUTMA", "", BLUE)
	_carton(n, Vector3(-0.55, 1.789, 0.19), Vector3(0.39, 0.06, 0.225), "FAN / 120 mm", "", RUST, -4.0)
	_carton(n, Vector3(-0.04, 1.724, 0.18), Vector3(0.17, 0.19, 0.23), "SSD", "SATA III", BLUE, -3.0)
	_carton(n, Vector3(0.16, 1.724, 0.17), Vector3(0.135, 0.175, 0.215), "HDD", "3.5 inç", RUST, 2.0)
	_carton(n, Vector3(0.56, 1.724, 0.19), Vector3(0.36, 0.20, 0.265), "KABLO / ADAPTÖR", "BAĞLANTI ELEMANLARI", BLUE)

	# Ufak kâğıt not: steril showroom değil, kullanılan bir mahalle atölyesi.
	var note := Node3D.new()
	note.position = Vector3(0.68, 1.25, 0.401)
	note.rotation_degrees.z = -5.0
	n.add_child(note)
	MU.box(note, Vector3(0.14, 0.105, 0.002), Vector3.ZERO, MU.mat(Color(0.85, 0.74, 0.45), 0, 0.95))
	MU.box(note, Vector3(0.065, 0.018, 0.003), Vector3(0, 0.052, 0.002), MU.mat(Color(0.78, 0.72, 0.56), 0, 0.9))
	var handwriting := _text(note, "Önce\ntest et!", Vector3(0, -0.003, 0.003), 32, INK, 0.00085)
	handwriting.font = preload("res://assets/fonts/Caveat.ttf")
	return n


static func _text(n: Node3D, text: String, pos: Vector3, size: int, color := INK, pixel := 0.001) -> Label3D:
	var l := MU.label(n, text, pos, size, color, Vector3.ZERO, pixel)
	l.double_sided = false
	l.shaded = true
	return l


static func _tag(n: Node3D, text: String, pos: Vector3, w: float, h: float, size := 26) -> void:
	MU.rbox(n, Vector3(w + 0.012, h + 0.01, 0.004), pos, MU.mat(INK, 0.25, 0.7), 0.002)
	MU.box(n, Vector3(w, h, 0.002), pos + Vector3(0, 0, 0.003), MU.mat(PAPER, 0, 0.95))
	_text(n, text, pos + Vector3(0, 0, 0.0045), size, INK, 0.00085)


static func _pull(n: Node3D, pos: Vector3, material: Material, vertical := false) -> void:
	var span := Vector3(0, 0.041, 0) if vertical else Vector3(0.062, 0, 0)
	for side in [-1.0, 1.0]:
		MU.rbox(n, Vector3(0.012, 0.012, 0.018), pos + span * side, material, 0.003)
	MU.rbox(n, Vector3(0.012, 0.095, 0.012) if vertical else Vector3(0.14, 0.012, 0.012), pos + Vector3(0, 0, 0.015), material, 0.004)


static func _carton(n: Node3D, pos: Vector3, size: Vector3, title: String, sub: String, color: Color, yaw := 0.0) -> void:
	var box := Node3D.new()
	box.position = pos + Vector3(0, size.y * 0.5, 0)
	box.rotation_degrees.y = yaw
	n.add_child(box)
	var kraft := MU.mat(Color(0.58, 0.45, 0.30), 0, 0.94)
	MU.rbox(box, size, Vector3.ZERO, kraft, 0.003)
	# Mat baskılı ön yüz, kapak kat izi ve dar renkli kategori şeridi.
	var z := size.z * 0.5 + 0.001
	MU.box(box, Vector3(size.x - 0.012, size.y - 0.012, 0.002), Vector3(0, 0, z), MU.mat(PAPER, 0, 0.92))
	MU.box(box, Vector3(0.017, size.y - 0.012, 0.003), Vector3(-size.x * 0.5 + 0.014, 0, z + 0.001), MU.mat(color, 0, 0.85))
	MU.box(box, Vector3(size.x - 0.006, 0.002, size.z - 0.006), Vector3(0, size.y * 0.5 - 0.008, 0), MU.mat(Color(0.43, 0.34, 0.24), 0, 1))
	var pixel := minf(0.001, (size.x - 0.055) / maxf(title.length() * 19.0, 1.0))
	_text(box, title, Vector3(0.006, size.y * 0.12, z + 0.0025), 32, INK, pixel)
	if sub != "":
		_text(box, sub, Vector3(0.006, -size.y * 0.16, z + 0.0025), 22, INK, pixel * 0.9)
	# Küçük barkod; doku ve şeffaf yüzey maliyeti yok.
	if size.y > 0.12:
		for i in 10:
			MU.box(box, Vector3(0.0015 if i % 3 == 0 else 0.0008, 0.018, 0.001), Vector3(size.x * 0.5 - 0.052 + i * 0.003, -size.y * 0.5 + 0.027, z + 0.002), MU.mat(INK, 0, 0.9))


static func _organizer(n: Node3D, pos: Vector3) -> void:
	var rack := Node3D.new()
	rack.position = pos
	n.add_child(rack)
	var dark := MU.mat(INK, 0.1, 0.85)
	var front := MU.mat(Color(0.58, 0.64, 0.63), 0.05, 0.85)
	MU.rbox(rack, Vector3(0.73, 0.267, 0.26), Vector3(0, 0.1335, 0.13), dark, 0.005)
	var labels := ["CPU", "RAM", "SSD", "M.2", "PİL", "VİDA"]
	for i in 6:
		var p := Vector3((i % 3 - 1) * 0.239, 0.197 - int(i / 3) * 0.127, 0.267)
		MU.rbox(rack, Vector3(0.226, 0.113, 0.012), p, front, 0.004)
		MU.rbox(rack, Vector3(0.055, 0.012, 0.009), p + Vector3(0, 0.029, 0.009), dark, 0.003)
		_tag(rack, labels[i], p + Vector3(0, -0.016, 0.008), 0.12, 0.033, 28)


static func _parts_bin(n: Node3D, pos: Vector3) -> void:
	var bin := Node3D.new()
	bin.position = pos
	n.add_child(bin)
	var plastic := MU.mat(Color(0.33, 0.39, 0.39), 0, 0.9)
	MU.rbox(bin, Vector3(0.59, 0.012, 0.27), Vector3(0, 0.006, 0), plastic, 0.004)
	MU.box(bin, Vector3(0.59, 0.14, 0.012), Vector3(0, 0.07, -0.129), plastic)
	for side in [-1.0, 1.0]:
		MU.rbox(bin, Vector3(0.013, 0.14, 0.27), Vector3(side * 0.288, 0.07, 0), plastic, 0.004)
	MU.rbox(bin, Vector3(0.59, 0.065, 0.014), Vector3(0, 0.0325, 0.133), plastic, 0.004)
	_tag(bin, "KABLO / BAĞLANTI", Vector3(0, 0.033, 0.142), 0.27, 0.033, 25)
	var cable := MU.mat(Color(0.07, 0.08, 0.075), 0, 0.9)
	for i in 3:
		MU.torus(bin, 0.032, 0.042, Vector3(-0.17 + i * 0.065, 0.026 + i * 0.008, 0), cable, Vector3(8, i * 21, 12))
	# Yedek fan dik durur, yüzü dolabın önüne bakar (PC modelinin normali +X).
	var fan: Node3D = PM.build_sku("fan_120_std").node
	fan.position = Vector3(0.17, 0.075, 0.005)
	fan.rotation_degrees.y = -90.0
	bin.add_child(fan)
