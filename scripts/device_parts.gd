extends RefCounted
## Laptop ve telefon parçalarının prosedürel modelleri.
## part_models.gd bu dosyaya yönlendirir. Modeller düz yatar: kalınlık Y ekseninde, merkez orijinde,
## ekranlarda görüntü yüzü +Y, kablolu/konnektörlü kenar +Z tarafındadır.

const MU := preload("res://scripts/mesh_util.gd")

static var _crack_tex: Texture2D


## Model oluşturucu: builder = parça türü; etiketler model parametrelerinden (m) gelir.
## Ad, fiyat ve tür bilgisi artık data/parts.json'da (PM.display_name / PM.price).
static func build(out: Dictionary, builder: String, m: Dictionary) -> void:
	match builder:
		"lap_ram": _lap_ram(out.node, m)
		"lap_ssd": _lap_ssd(out.node, m)
		"lap_bat": _lap_bat(out.node, m)
		"lap_scr": _lap_scr(out.node, m)
		"tel_bat": _tel_bat(out.node, m)
		"tel_scr": _tel_scr(out.node)
		"tel_port": _tel_port(out.node)


# ---------------------------------------------------------------- ortak

static func _gold() -> Material: return MU.mat(Color(0.95, 0.75, 0.3), 1.0, 0.22)
static func _chip() -> Material: return MU.mat(Color(0.03, 0.03, 0.035), 0.1, 0.35)
static func _steel() -> Material: return MU.mat(Color(0.72, 0.73, 0.76), 0.9, 0.3)


static func _text(n: Node3D, txt: String, pos: Vector3, size: int, color: Color, px := 0.0002, rot := Vector3(-90, 0, 0)) -> void:
	var l := MU.label(n, txt, pos, size, color, rot, px)
	l.double_sided = false


# ---------------------------------------------------------------- LAPTOP RAM (SO-DIMM)

static func _lap_ram(n: Node3D, m: Dictionary) -> void:
	MU.box(n, Vector3(0.0675, 0.0012, 0.03), Vector3.ZERO, MU.tex_mat(MU.pcb_texture(Color(0.05, 0.25, 0.12)), Vector3(1, 1, 1), 0.5))
	# altın kontaklar (çentikli, -Z kenarı)
	MU.box(n, Vector3(0.036, 0.0014, 0.003), Vector3(-0.012, 0, -0.0135), _gold())
	MU.box(n, Vector3(0.026, 0.0014, 0.003), Vector3(0.019, 0, -0.0135), _gold())
	# bellek çipleri (iki sıra) + etiket
	for i in 4:
		MU.box(n, Vector3(0.011, 0.0012, 0.009), Vector3(-0.024 + i * 0.016, 0.0011, -0.002), _chip())
		MU.box(n, Vector3(0.011, 0.0012, 0.009), Vector3(-0.024 + i * 0.016, -0.0011, -0.002), _chip())
	MU.box(n, Vector3(0.05, 0.0003, 0.007), Vector3(0, 0.0007, 0.0095), MU.mat(Color(0.93, 0.93, 0.9), 0, 0.6))
	_text(n, m.get("label", "8GB DDR4 SO-DIMM"), Vector3(0, 0.0009, 0.0095), 22, Color(0.1, 0.1, 0.1), 0.00016)
	# yan kilit çentikleri
	for x in [-0.0338, 0.0338]:
		MU.box(n, Vector3(0.0012, 0.0013, 0.004), Vector3(x, 0, 0.004), MU.mat(Color(0.6, 0.6, 0.6), 0.6, 0.4))


# ---------------------------------------------------------------- M.2 SSD

static func _lap_ssd(n: Node3D, m: Dictionary) -> void:
	MU.box(n, Vector3(0.08, 0.0012, 0.022), Vector3.ZERO, MU.tex_mat(MU.pcb_texture(Color(0.05, 0.05, 0.06)), Vector3(1, 1, 1), 0.5))
	# M-key altın konnektör (-X ucu) + vida yarımı (+X ucu)
	MU.box(n, Vector3(0.004, 0.0014, 0.017), Vector3(-0.038, 0, 0.0015), _gold())
	MU.box(n, Vector3(0.0045, 0.0015, 0.002), Vector3(-0.0378, 0, -0.0055), MU.mat(Color(0.05, 0.05, 0.06)))
	MU.cyl(n, 0.0028, 0.0014, Vector3(0.039, 0, 0), _gold(), Vector3.ZERO, 12)
	# denetleyici + NAND çipleri
	MU.rbox(n, Vector3(0.012, 0.0014, 0.012), Vector3(-0.022, 0.0012, 0), _chip(), 0.0005)
	for x in [-0.003, 0.017]:
		MU.rbox(n, Vector3(0.016, 0.0014, 0.014), Vector3(x, 0.0012, 0), _chip(), 0.0005)
	# etiket
	MU.box(n, Vector3(0.055, 0.0003, 0.018), Vector3(0.006, 0.0021, 0), MU.mat(Color(0.12, 0.35, 0.8), 0, 0.45))
	_text(n, m.get("label", "BİLGİ NVMe\n512 GB"), Vector3(0.006, 0.0024, 0), 26, Color.WHITE, 0.00017)


# ---------------------------------------------------------------- LAPTOP BATARYASI

static func _lap_bat(n: Node3D, m: Dictionary) -> void:
	var wrap := MU.mat(Color(0.1, 0.1, 0.11), 0.2, 0.45)
	MU.rbox(n, Vector3(0.22, 0.0075, 0.07), Vector3.ZERO, wrap, 0.002)
	# üç yassı hücre (hafif kabartma)
	var cell := MU.mat(Color(0.14, 0.14, 0.15), 0.3, 0.35)
	for i in 3:
		MU.rbox(n, Vector3(0.066, 0.0012, 0.062), Vector3(-0.072 + i * 0.072, 0.0038, -0.001), cell, 0.002)
	# etiket
	MU.box(n, Vector3(0.11, 0.0004, 0.04), Vector3(0.0, 0.0046, 0.0), MU.mat(Color(0.93, 0.93, 0.9), 0, 0.6))
	MU.box(n, Vector3(0.11, 0.00045, 0.008), Vector3(0.0, 0.0047, -0.016), MU.mat(Color(0.85, 0.15, 0.12), 0, 0.5))
	_text(n, m.get("label", "Li-ion 11.4V  56Wh"), Vector3(0, 0.0052, -0.016), 26, Color.WHITE, 0.00018)
	_text(n, "UYARI: Delmeyin, ateşe atmayın!\nŞişerse kullanmayın.", Vector3(0, 0.0052, 0.006), 22, Color(0.15, 0.15, 0.15), 0.00017)
	# kablo + konnektör (+Z kenarı)
	var red := MU.mat(Color(0.75, 0.1, 0.1), 0, 0.6)
	var blk := MU.mat(Color(0.04, 0.04, 0.045), 0, 0.6)
	for i in 4:
		MU.box(n, Vector3(0.0015, 0.0012, 0.016), Vector3(0.07 + i * 0.002, 0.001, 0.042), red if i < 2 else blk)
	MU.rbox(n, Vector3(0.012, 0.003, 0.005), Vector3(0.073, 0.001, 0.052), MU.mat(Color(0.92, 0.92, 0.88), 0, 0.5), 0.0006)


# ---------------------------------------------------------------- LAPTOP EKRANI

static func _lap_scr(n: Node3D, m: Dictionary) -> void:
	# arka metal kasa + ön cam (görüntü yüzü +Y)
	MU.rbox(n, Vector3(0.31, 0.0025, 0.19), Vector3(0, -0.0008, 0), MU.mat(Color(0.6, 0.62, 0.65), 0.85, 0.35), 0.0015)
	MU.rbox(n, Vector3(0.306, 0.0015, 0.186), Vector3(0, 0.0012, 0), MU.mat(Color(0.015, 0.015, 0.02), 0.0, 0.3), 0.001)
	# görüntü konnektörü (eDP) şeridi: alt kenar (+Z)
	MU.box(n, Vector3(0.03, 0.0005, 0.012), Vector3(0.06, -0.0021, 0.085), MU.mat(Color(0.85, 0.5, 0.1), 0, 0.5))
	MU.box(n, Vector3(0.012, 0.0012, 0.006), Vector3(0.06, -0.0026, 0.091), MU.mat(Color(0.1, 0.1, 0.1)))
	_text(n, m.get("label", "15.6\" FHD IPS  eDP 30pin"), Vector3(-0.05, -0.0022, 0.0), 40, Color(0.12, 0.12, 0.12), 0.0003, Vector3(90, 0, 0))
	MU.box(n, Vector3(0.12, 0.0003, 0.03), Vector3(-0.05, -0.0021, 0.0), MU.mat(Color(0.93, 0.93, 0.9), 0, 0.6))


# ---------------------------------------------------------------- TELEFON BATARYASI

static func _tel_bat(n: Node3D, m: Dictionary) -> void:
	MU.rbox(n, Vector3(0.05, 0.0038, 0.08), Vector3.ZERO, MU.mat(Color(0.12, 0.12, 0.13), 0.4, 0.35), 0.0015)
	MU.box(n, Vector3(0.044, 0.0004, 0.05), Vector3(0, 0.002, -0.006), MU.mat(Color(0.93, 0.93, 0.9), 0, 0.6))
	_text(n, m.get("label", "Li-ion\n4500 mAh\n3.85V"), Vector3(0, 0.0023, -0.006), 26, Color(0.12, 0.12, 0.12), 0.00019)
	# esnek konnektör (+Z üst ucu)
	MU.box(n, Vector3(0.008, 0.0004, 0.012), Vector3(0.012, 0.0015, 0.044), MU.mat(Color(0.85, 0.5, 0.1), 0, 0.5))
	MU.rbox(n, Vector3(0.01, 0.0015, 0.005), Vector3(0.012, 0.0018, 0.05), MU.mat(Color(0.08, 0.08, 0.09)), 0.0004)
	# çekme bandı
	MU.box(n, Vector3(0.006, 0.0003, 0.02), Vector3(-0.016, 0.0021, 0.03), MU.mat(Color(0.2, 0.2, 0.22), 0, 0.5))


# ---------------------------------------------------------------- TELEFON EKRANI

static func _tel_scr(n: Node3D) -> void:
	MU.rbox(n, Vector3(0.072, 0.0028, 0.152), Vector3.ZERO, MU.mat(Color(0.015, 0.015, 0.02), 0.0, 0.3), 0.004)
	# ön kamera deliği (üst = -Z)
	MU.cyl(n, 0.0022, 0.0004, Vector3(0, 0.0014, -0.068), MU.mat(Color(0.0, 0.0, 0.0), 0.1, 0.2), Vector3.ZERO, 12)
	# ahize ızgarası
	MU.box(n, Vector3(0.012, 0.0003, 0.0012), Vector3(0, 0.0014, -0.0735), MU.mat(Color(0.2, 0.2, 0.22), 0.6, 0.4))
	# arka yüz: esnek kablo
	MU.box(n, Vector3(0.012, 0.0004, 0.03), Vector3(0.018, -0.0016, 0.05), MU.mat(Color(0.85, 0.5, 0.1), 0, 0.5))
	MU.rbox(n, Vector3(0.014, 0.0012, 0.006), Vector3(0.018, -0.0019, 0.064), MU.mat(Color(0.08, 0.08, 0.09)), 0.0004)


# ---------------------------------------------------------------- ŞARJ SOKETİ

static func _tel_port(n: Node3D) -> void:
	# esnek devre (sarımsı poliimid) + alt kart
	MU.rbox(n, Vector3(0.05, 0.0008, 0.012), Vector3.ZERO, MU.mat(Color(0.82, 0.52, 0.12), 0.1, 0.45), 0.001)
	MU.box(n, Vector3(0.034, 0.0006, 0.008), Vector3(-0.004, 0.0006, -0.001), MU.tex_mat(MU.pcb_texture(Color(0.05, 0.2, 0.1))))
	# USB-C soketi (+Z kenarı)
	MU.rbox(n, Vector3(0.009, 0.0032, 0.007), Vector3(0, 0.0012, 0.004), _steel(), 0.0013)
	MU.rbox(n, Vector3(0.0068, 0.0016, 0.0074), Vector3(0, 0.0012, 0.0042), MU.mat(Color(0.03, 0.03, 0.03)), 0.0007)
	# mikrofon + titreşim motoru + konnektör
	MU.cyl(n, 0.0018, 0.0014, Vector3(0.014, 0.0008, 0.0), _steel(), Vector3.ZERO, 10)
	MU.rbox(n, Vector3(0.009, 0.0026, 0.007), Vector3(-0.017, 0.0013, 0.0), MU.mat(Color(0.6, 0.62, 0.65), 0.8, 0.35), 0.001)
	MU.rbox(n, Vector3(0.008, 0.0012, 0.004), Vector3(0.019, 0.0006, -0.004), MU.mat(Color(0.08, 0.08, 0.09)), 0.0004)


# ---------------------------------------------------------------- arıza görünümleri

## Bozuk parçaya görünür arıza ekler: şişmiş batarya, çatlak ekran, paslı soket.
## Parça (part.gd) kurulduktan sonra çağrılır; model zaten birleştirildiği için ayrı mesh olarak eklenir.
static func add_damage(part: Node3D, type: String) -> void:
	match type:
		"lap_bat":
			var puff := MU.mat(Color(0.16, 0.16, 0.17), 0.35, 0.22)
			MU.sphere(part, 0.5, Vector3(0.0, 0.0035, 0.0), puff, Vector3(0.2, 0.012, 0.064))
			MU.sphere(part, 0.5, Vector3(-0.072, 0.0032, 0.0), puff, Vector3(0.062, 0.009, 0.058))
		"tel_bat":
			MU.sphere(part, 0.5, Vector3(0.0, 0.0018, 0.0), MU.mat(Color(0.16, 0.16, 0.17), 0.35, 0.22), Vector3(0.046, 0.008, 0.074))
		"lap_scr":
			_crack(part, Vector2(0.304, 0.184), 0.0024)
		"tel_scr":
			_crack(part, Vector2(0.07, 0.15), 0.0018)
		"tel_port":
			var green := MU.mat(Color(0.35, 0.6, 0.35), 0.2, 0.8)
			var brown := MU.mat(Color(0.25, 0.15, 0.06), 0.1, 0.9)
			for p in [Vector3(-0.002, 0.003, 0.006), Vector3(0.003, 0.0028, 0.002), Vector3(0.012, 0.0015, -0.002), Vector3(-0.012, 0.0012, 0.003)]:
				MU.sphere(part, 0.0018, p, green, Vector3(1.2, 0.5, 1.0))
			MU.sphere(part, 0.003, Vector3(0.006, 0.0008, -0.002), brown, Vector3(1.4, 0.3, 1.0))


## Çatlak ekran: yarı saydam çatlak dokusu, görüntü quad'ının da üstünde durur.
static func _crack(part: Node3D, size: Vector2, y: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = crack_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.92, 0.95, 1.0, 0.95)
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.name = "Crack"
	mi.mesh = q
	mi.material_override = m
	mi.position = Vector3(0, y, 0)
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.add_child(mi)


## Örümcek ağı çatlak dokusu (çarpma noktasından ışınsal çizgiler + kırık halkalar).
static func crack_texture() -> Texture2D:
	if _crack_tex:
		return _crack_tex
	var s := 256
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var c := Vector2(s * 0.62, s * 0.36)
	var rays := []
	for i in 15:
		var a := TAU * i / 15.0 + rng.randf_range(-0.18, 0.18)
		var p := c
		var pts := [p]
		var step := 0
		while p.x > -10 and p.x < s + 10 and p.y > -10 and p.y < s + 10 and step < 40:
			a += rng.randf_range(-0.25, 0.25)
			p += Vector2(cos(a), sin(a)) * rng.randf_range(9, 18)
			pts.append(p)
			step += 1
		rays.append(pts)
		for k in pts.size() - 1:
			_line(img, pts[k], pts[k + 1], 0.9 if k < 3 else 0.7)
	# halkalar: komşu ışınların noktalarını birleştir
	for ring in [1, 3, 6]:
		for i in rays.size():
			var r1: Array = rays[i]
			var r2: Array = rays[(i + 1) % rays.size()]
			if ring < r1.size() and ring < r2.size() and rng.randf() < 0.8:
				_line(img, r1[ring], r2[ring], 0.6)
	# çarpma noktası: beyazlaşmış ufalanma
	for i in 60:
		var q := c + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9))
		if q.x >= 0 and q.y >= 0 and q.x < s and q.y < s:
			img.set_pixelv(Vector2i(q), Color(1, 1, 1, 0.85))
	img.generate_mipmaps()
	_crack_tex = ImageTexture.create_from_image(img)
	return _crack_tex


static func _line(img: Image, a: Vector2, b: Vector2, alpha: float) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	var w := img.get_width()
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		for o: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
			var q := Vector2i(p) + o
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < w:
				img.set_pixelv(q, Color(1, 1, 1, alpha))
