extends RefCounted
## Dükkândaki detaylı eşyaların prosedürel modelleri: klavye, fare, laptop, telefon, monitör,
## masa lambası, kupa, tornavida, yazar kasa, CRT monitör.
## Hepsi sabit nesnelerdir; sonradan `MU.merge_static` ile birkaç draw call'a indirilir.
## Kurallar: "kanonik" yön = kullanıcı +Z tarafında durur, cihazın önü +Z'ye bakar.

const MU := preload("res://scripts/mesh_util.gd")


# ---------------------------------------------------------------- malzemeler

static func _plastic(c: Color, rough := 0.45) -> Material: return MU.mat(c, 0.0, rough)
static func _metal(c: Color, rough := 0.3) -> Material: return MU.mat(c, 0.9, rough)
static func _gloss_black() -> Material: return MU.mat(Color(0.015, 0.015, 0.018), 0.2, 0.06)


## İki nokta arasında silindir (çubuk, kol, kablo parçası).
static func rod(parent: Node, a: Vector3, b: Vector3, r: float, m: Material, sides := 12) -> MeshInstance3D:
	var mi := MU.cyl(parent, r, a.distance_to(b), (a + b) / 2.0, m, Vector3.ZERO, sides)
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	mi.basis = Basis(x, y, x.cross(y))
	return mi


# ---------------------------------------------------------------- MASAÜSTÜ KLAVYE

## Mekanik klavye: alüminyum kasa, Q düzeni harfli eğimli tuş kapakları, kablo çıkışı.
static func keyboard(parent: Node, pos: Vector3, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw, 0)
	parent.add_child(n)
	var tilt := Node3D.new()
	tilt.rotation_degrees.x = 3.5   # arka taraf (−Z) yükseltilmiş
	tilt.position.y = 0.006
	n.add_child(tilt)
	var u := 0.0232
	var size := Vector2(15 * u, 6 * u)
	var case_m := _metal(Color(0.16, 0.165, 0.18), 0.38)
	MU.slab(tilt, Vector3(size.x + 0.018, 0.02, size.y + 0.018), Vector3(0, 0.0, 0), case_m, 0.008, 0.0035)
	# tuş plakası (çukur)
	MU.slab(tilt, Vector3(size.x + 0.004, 0.002, size.y + 0.004), Vector3(0, 0.0095, 0), _plastic(Color(0.04, 0.04, 0.045), 0.7), 0.003, 0.0008)
	MU.keycaps(tilt, MU.KB_ROWS, Vector3(0, 0.0105, 0), u, 0.0085, Color(0.13, 0.135, 0.15), Color(0.88, 0.9, 0.95), 0.16, 0.07, 20, 0.5)
	# vurgu tuşu: Esc ve Enter rengi (ayrı küçük kapaklar yerine şerit LED)
	MU.box(tilt, Vector3(size.x * 0.9, 0.0015, 0.003), Vector3(0, -0.006, size.y / 2 + 0.0085), MU.mat(Color(0.3, 0.6, 1.0), 0, 0.4, 1.4))
	# kauçuk ayaklar
	for x in [-size.x / 2 + 0.01, size.x / 2 - 0.01]:
		MU.box(tilt, Vector3(0.02, 0.006, 0.008), Vector3(x, -0.012, -size.y / 2 + 0.004), _plastic(Color(0.03, 0.03, 0.03), 0.9))
	# kablo (arkadan monitöre doğru kıvrılır)
	var cable: Array[Vector3] = [Vector3(0.05, 0.003, -size.y / 2 - 0.009), Vector3(0.055, 0.0, -size.y / 2 - 0.05),
		Vector3(0.03, -0.012, -size.y / 2 - 0.12), Vector3(-0.02, -0.015, -size.y / 2 - 0.22)]
	MU.tube(tilt, cable, 0.0022, _plastic(Color(0.05, 0.05, 0.055), 0.6), 6)
	return n


# ---------------------------------------------------------------- FARE + MOUSEPAD

static func mouse(parent: Node, pos: Vector3, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw, 0)
	parent.add_child(n)
	var shell := _plastic(Color(0.08, 0.08, 0.09), 0.55)
	# kubbe gövde: daire profil, sonra elips forma ölçeklenir (arka taraf daha yüksek)
	var prof := PackedVector2Array([Vector2(0, 0), Vector2(1.0, 0), Vector2(1.0, 0.12), Vector2(0.96, 0.32), Vector2(0.86, 0.56),
		Vector2(0.68, 0.79), Vector2(0.42, 0.95), Vector2(0, 1.0)])
	var body := MU.lathe(n, prof, Vector3(0, 0.001, 0.008), shell, 28)
	body.scale = Vector3(0.031, 0.036, 0.058)
	# alt kızak + düğme ayrımı + tekerlek
	MU.slab(n, Vector3(0.06, 0.003, 0.11), Vector3(0, 0.0015, 0.008), _plastic(Color(0.02, 0.02, 0.02), 0.8), 0.028, 0.001)
	# tekerlek yuvası + tekerlek, arkada logo LED'i
	MU.slab(n, Vector3(0.011, 0.004, 0.024), Vector3(0, 0.0315, -0.02), _plastic(Color(0.01, 0.01, 0.01), 0.9), 0.004, 0.0015, Vector3(-14, 0, 0))
	MU.cyl(n, 0.0072, 0.0058, Vector3(0, 0.0315, -0.02), _plastic(Color(0.22, 0.22, 0.24), 0.75), Vector3(0, 0, 90), 16)
	MU.sphere(n, 0.0045, Vector3(0, 0.0352, 0.03), MU.mat(Color(0.2, 0.6, 1.0), 0, 0.4, 2.0), Vector3(1, 0.3, 1.4))
	return n


static func mousepad(parent: Node, pos: Vector3, size := Vector2(0.27, 0.22)) -> void:
	MU.slab(parent, Vector3(size.x, 0.003, size.y), pos + Vector3(0, 0.0015, 0), MU.mat(Color(0.06, 0.065, 0.08), 0, 0.92), 0.014, 0.0012)


# ---------------------------------------------------------------- LAPTOP

## Açık laptop. Ekranda pişirilmiş bir yönetim paneli görüntüsü vardır. `screen_build` 2D içerik kurar.
static func laptop(parent: Node, pos: Vector3, yaw := 0.0, screen_build := Callable()) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw, 0)
	parent.add_child(n)
	var alu := _metal(Color(0.55, 0.56, 0.6), 0.32)
	var size := Vector3(0.33, 0.016, 0.23)
	MU.slab(n, size, Vector3(0, size.y / 2, 0), alu, 0.012, 0.0045)
	# klavye yuvası + chiclet tuşlar
	var u := 0.0188
	MU.slab(n, Vector3(15 * u + 0.006, 0.002, 6 * u + 0.006), Vector3(0, size.y - 0.0004, -0.037), _plastic(Color(0.06, 0.06, 0.07), 0.8), 0.004, 0.0008)
	MU.keycaps(n, MU.KB_ROWS, Vector3(0, size.y - 0.0002, -0.037), u, 0.0016, Color(0.08, 0.08, 0.09), Color(0.82, 0.84, 0.88), 0.0, 0.16, 18, 0.55)
	# hoparlör ızgaraları
	for x in [-0.152, 0.152]:
		for i in 9:
			MU.box(n, Vector3(0.006, 0.0006, 0.0012), Vector3(x, size.y + 0.0001, -0.085 + i * 0.012), _plastic(Color(0.12, 0.12, 0.13), 0.9))
	# dokunmatik yüzey
	MU.slab(n, Vector3(0.115, 0.0008, 0.068), Vector3(0, size.y + 0.0002, 0.068), _metal(Color(0.48, 0.49, 0.53), 0.22), 0.006, 0.0004)
	# ön parmak çentiği
	MU.slab(n, Vector3(0.06, 0.004, 0.006), Vector3(0, size.y - 0.001, size.z / 2), _metal(Color(0.45, 0.46, 0.5), 0.3), 0.003, 0.0015)
	# menteşe
	MU.cyl(n, 0.0055, 0.24, Vector3(0, size.y, -size.z / 2 + 0.006), _metal(Color(0.2, 0.2, 0.22), 0.35), Vector3(0, 0, 90), 14)
	# kapak (ekran): menteşeden yukarı, hafif geriye yatık
	var lid := Node3D.new()
	lid.position = Vector3(0, size.y + 0.001, -size.z / 2 + 0.006)
	lid.rotation_degrees.x = -14.0
	n.add_child(lid)
	var lh := 0.222
	MU.slab(lid, Vector3(size.x, 0.006, lh), Vector3(0, lh / 2, 0), alu, 0.011, 0.0025, Vector3(90, 0, 0))
	MU.slab(lid, Vector3(size.x - 0.006, 0.0008, lh - 0.006), Vector3(0, lh / 2, 0.0032), _gloss_black(), 0.009, 0.0004, Vector3(90, 0, 0))
	# kamera
	MU.cyl(lid, 0.0018, 0.0006, Vector3(0, lh - 0.0075, 0.0037), _gloss_black(), Vector3(90, 0, 0), 10)
	MU.cyl(lid, 0.0008, 0.0007, Vector3(0, lh - 0.0075, 0.0038), MU.mat(Color(0.15, 0.2, 0.4), 0.5, 0.1), Vector3(90, 0, 0), 8)
	# arka logo
	MU.cyl(lid, 0.016, 0.0006, Vector3(0, lh / 2, -0.0031), _metal(Color(0.8, 0.82, 0.86), 0.12), Vector3(90, 0, 0), 24)
	# ekran
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var q := QuadMesh.new()
	q.size = Vector2(0.302, 0.19)
	var scr := MeshInstance3D.new()
	scr.mesh = q
	scr.material_override = sm
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scr.position = Vector3(0, lh / 2 + 0.002, 0.0038)
	lid.add_child(scr)
	if screen_build.is_valid():
		MU.bake_2d(n, Vector2i(640, 402), sm, screen_build)
	else:
		sm.albedo_color = Color(0.02, 0.02, 0.025)
	return n


# ---------------------------------------------------------------- AKILLI TELEFON

## Masada yatan telefon. face_up: ekran üstte (açık kilit ekranı), değilse sırt üstte (kamera modülü).
static func phone(parent: Node, pos: Vector3, yaw := 0.0, body_col := Color(0.2, 0.22, 0.3), face_up := true, clock_text := "10:24") -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw, 0)
	parent.add_child(n)
	var size := Vector3(0.072, 0.0082, 0.152)
	var frame := _metal(body_col.lightened(0.35), 0.25)
	var back := MU.mat(body_col, 0.15, 0.18)
	# çerçeve + arka cam (görünen yüz her zaman üsttedir)
	MU.slab(n, size, Vector3(0, size.y / 2, 0), frame, 0.0105, 0.0028)
	MU.slab(n, Vector3(size.x - 0.002, 0.0006, size.z - 0.002), Vector3(0, 0.0002 if face_up else size.y - 0.0002, 0), back, 0.0095, 0.0003)
	# yan tuşlar
	MU.slab(n, Vector3(0.0012, 0.0028, 0.022), Vector3(size.x / 2 + 0.0003, size.y / 2, -0.03), frame, 0.0006, 0.0005)
	MU.slab(n, Vector3(0.0012, 0.0028, 0.012), Vector3(-size.x / 2 - 0.0003, size.y / 2, -0.038), frame, 0.0006, 0.0005)
	MU.slab(n, Vector3(0.0012, 0.0028, 0.012), Vector3(-size.x / 2 - 0.0003, size.y / 2, -0.022), frame, 0.0006, 0.0005)
	var top_y := size.y + 0.0001
	if face_up:
		MU.slab(n, Vector3(size.x - 0.0016, 0.0005, size.z - 0.0016), Vector3(0, top_y - 0.0002, 0), _gloss_black(), 0.0098, 0.0002)
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var q := QuadMesh.new()
		q.size = Vector2(size.x - 0.0055, size.z - 0.0055)
		var scr := MeshInstance3D.new()
		scr.mesh = q
		scr.material_override = sm
		scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scr.rotation_degrees.x = -90
		scr.position = Vector3(0, top_y + 0.0001, 0)
		n.add_child(scr)
		MU.bake_2d(n, Vector2i(300, 632), sm, func(root: Control): _lock_screen(root, body_col, clock_text))
		# ön kamera adası
		MU.slab(n, Vector3(0.017, 0.0003, 0.0048), Vector3(0, top_y + 0.0003, -size.z / 2 + 0.0085), _gloss_black(), 0.0024, 0.0001)
	else:
		# kamera modülü (sırt üstte)
		MU.slab(n, Vector3(0.03, 0.0018, 0.031), Vector3(-0.017, top_y + 0.0009, -0.052), MU.mat(body_col.darkened(0.15), 0.2, 0.15), 0.0075, 0.0008)
		var ly := top_y + 0.0018
		for lp in [Vector2(-0.0245, -0.06), Vector2(-0.0245, -0.044), Vector2(-0.0095, -0.052)]:
			MU.lathe(n, PackedVector2Array([Vector2(0, 0), Vector2(0.0058, 0), Vector2(0.0058, 0.0016), Vector2(0.0046, 0.0019),
				Vector2(0.0042, 0.0012), Vector2(0, 0.0012)]), Vector3(lp.x, ly, lp.y), _metal(Color(0.35, 0.36, 0.4), 0.2), 18)
			MU.cyl(n, 0.0036, 0.0004, Vector3(lp.x, ly + 0.0013, lp.y), MU.mat(Color(0.05, 0.07, 0.12), 0.6, 0.04), Vector3.ZERO, 14)
		MU.cyl(n, 0.0018, 0.0004, Vector3(-0.0095, ly + 0.0001, -0.0405), MU.mat(Color(1.0, 0.9, 0.7), 0, 0.3), Vector3.ZERO, 10)
		# logo
		MU.cyl(n, 0.007, 0.0002, Vector3(0, top_y + 0.0001, 0.005), _metal(body_col.lightened(0.5), 0.15), Vector3.ZERO, 20)
	return n


static func _lock_screen(root: Control, tint: Color, clock_text: String) -> void:
	var grad := Gradient.new()
	grad.set_color(0, tint.lightened(0.25))
	grad.set_color(1, Color(0.08, 0.05, 0.18))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.3, 0.75)
	gt.fill_to = Vector2(1.2, 0.0)
	var wall := TextureRect.new()
	wall.texture = gt
	wall.size = root.size
	wall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wall.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(wall)
	var t := Label.new()
	t.text = clock_text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(0, 96)
	t.size = Vector2(root.size.x, 110)
	t.add_theme_font_size_override("font_size", 92)
	root.add_child(t)
	var d := Label.new()
	d.text = "Cuma, 14 Kasım"
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.position = Vector2(0, 66)
	d.size = Vector2(root.size.x, 30)
	d.add_theme_font_size_override("font_size", 22)
	d.modulate = Color(1, 1, 1, 0.85)
	root.add_child(d)
	var notes := [["Müşteri", "Usta, bilgisayar hazır mı? 🙏"], ["Banka", "Hesabınıza 450,00 TL yattı"]]
	for i in notes.size():
		var p := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.22)
		sb.set_corner_radius_all(18)
		p.add_theme_stylebox_override("panel", sb)
		p.position = Vector2(18, 330 + i * 84)
		p.size = Vector2(root.size.x - 36, 72)
		root.add_child(p)
		var a := Label.new()
		a.text = notes[i][0]
		a.position = Vector2(16, 8)
		a.add_theme_font_size_override("font_size", 17)
		p.add_child(a)
		var b := Label.new()
		b.text = notes[i][1]
		b.position = Vector2(16, 34)
		b.add_theme_font_size_override("font_size", 16)
		b.modulate = Color(1, 1, 1, 0.85)
		p.add_child(b)
	var bar := Panel.new()
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(1, 1, 1, 0.85)
	sb2.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("panel", sb2)
	bar.position = Vector2(root.size.x / 2 - 60, root.size.y - 22)
	bar.size = Vector2(120, 7)
	root.add_child(bar)


# ---------------------------------------------------------------- MONİTÖR GÖVDESİ

## Monitör kasası (ekran görüntüsü monitor.gd'deki SubViewport'tan gelir). Ekran merkezi: (0, 0.435, 0.0128).
static func monitor_shell(n: Node3D) -> void:
	var dark := MU.mat(Color(0.05, 0.05, 0.058), 0.35, 0.42)
	var stand := _metal(Color(0.22, 0.22, 0.24), 0.32)
	# ayak: yumuşak hatlı oval taban + eğik boyun
	MU.slab(n, Vector3(0.26, 0.012, 0.18), Vector3(0, 0.006, -0.01), stand, 0.075, 0.005)
	MU.slab(n, Vector3(0.05, 0.024, 0.3), Vector3(0, 0.16, -0.045), stand, 0.012, 0.006, Vector3(80, 0, 0))
	# panel: ince çerçeve + arka tümsek
	MU.slab(n, Vector3(0.62, 0.022, 0.368), Vector3(0, 0.435, 0.0), dark, 0.008, 0.004, Vector3(90, 0, 0))
	MU.slab(n, Vector3(0.44, 0.035, 0.26), Vector3(0, 0.42, -0.018), dark, 0.05, 0.014, Vector3(90, 0, 0))
	MU.slab(n, Vector3(0.6, 0.002, 0.342), Vector3(0, 0.436, 0.0112), _gloss_black(), 0.005, 0.0008, Vector3(90, 0, 0))
	# alt çene + logo ve güç LED'i
	MU.slab(n, Vector3(0.62, 0.024, 0.016), Vector3(0, 0.257, 0.0), MU.mat(Color(0.1, 0.1, 0.11), 0.6, 0.3), 0.004, 0.003)
	MU.sphere(n, 0.0028, Vector3(0.285, 0.256, 0.012), MU.mat(Color(0.3, 0.6, 1.0), 0, 0.5, 4.0))
	# arka havalandırma yarıkları
	for i in 7:
		MU.box(n, Vector3(0.22, 0.003, 0.001), Vector3(0, 0.48 + i * 0.008, -0.0356), MU.mat(Color(0.02, 0.02, 0.02), 0, 0.9))


# ---------------------------------------------------------------- MASA LAMBASI

## Mimar lambası: ağır taban, iki eklemli kol, tornalanmış başlık. Işık yönü `dir`, ampul `bulb`.
static func desk_lamp(parent: Node, base: Vector3, bulb: Vector3, dir: Vector3, col: Color) -> void:
	var paint := MU.mat(col, 0.35, 0.35)
	var steel := _metal(Color(0.75, 0.76, 0.78), 0.25)
	var dark := _metal(Color(0.12, 0.12, 0.13), 0.4)
	MU.lathe(parent, PackedVector2Array([Vector2(0, 0), Vector2(0.075, 0), Vector2(0.078, 0.004), Vector2(0.075, 0.016),
		Vector2(0.06, 0.022), Vector2(0.025, 0.026), Vector2(0.018, 0.034), Vector2(0, 0.034)]), base, paint, 32)
	var head := bulb - dir * 0.05
	var j0 := base + Vector3(0, 0.036, 0)
	var flat := Vector3(head.x - base.x, 0, head.z - base.z)
	var elbow := base + Vector3(0, 0.26, 0) - flat.normalized() * 0.1
	for p in [j0, elbow]:
		MU.cyl(parent, 0.011, 0.024, p, dark, Vector3(0, 0, 90), 14)
	rod(parent, j0 + Vector3(0.008, 0, 0), elbow + Vector3(0.008, 0, 0), 0.0045, steel)
	rod(parent, j0 - Vector3(0.008, 0, 0), elbow - Vector3(0.008, 0, 0), 0.0045, steel)
	rod(parent, elbow, head, 0.0055, steel)
	# yay
	var spring: Array[Vector3] = []
	for i in 25:
		var t := i / 24.0
		var c := j0.lerp(elbow, 0.2 + t * 0.45)
		spring.append(c + Vector3(-0.018, cos(t * TAU * 6) * 0.003, sin(t * TAU * 6) * 0.003))
	MU.tube(parent, spring, 0.0009, steel, 4)
	# başlık: kalın kabuk profil (dış yüz → ağız → iç yüz)
	var hn := Node3D.new()
	hn.position = head
	parent.add_child(hn)
	hn.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	MU.cyl(hn, 0.012, 0.03, Vector3(0, 0, 0.005), dark, Vector3(90, 0, 0), 14)
	var shade := PackedVector2Array([Vector2(0, -0.022), Vector2(0.018, -0.021), Vector2(0.026, -0.012), Vector2(0.03, 0.006),
		Vector2(0.058, 0.07), Vector2(0.062, 0.078), Vector2(0.062, 0.078), Vector2(0.058, 0.078), Vector2(0.055, 0.071),
		Vector2(0.027, 0.008), Vector2(0.02, -0.01), Vector2(0, -0.012)])
	MU.lathe(hn, shade, Vector3.ZERO, paint, 32, Vector3(-90, 0, 0))
	MU.lathe(hn, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0215, 0.0), Vector2(0.0225, 0.004)]), Vector3(0, 0, -0.012), MU.mat(Color(0.9, 0.88, 0.82), 0.5, 0.3), 24, Vector3(-90, 0, 0))
	MU.sphere(hn, 0.02, Vector3(0, 0, -0.045), MU.mat(Color(1.0, 0.92, 0.75), 0, 0.5, 7.0), Vector3(1, 1, 1.15))
	MU.cyl(hn, 0.011, 0.016, Vector3(0, 0, -0.02), steel, Vector3(90, 0, 0), 12)


# ---------------------------------------------------------------- KUPA, TORNAVİDA

static func mug(parent: Node, pos: Vector3, col: Color, yaw := 0.0) -> void:
	var m := MU.mat(col, 0, 0.18)
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees.y = yaw
	parent.add_child(n)
	MU.lathe(n, PackedVector2Array([Vector2(0, 0), Vector2(0.034, 0), Vector2(0.037, 0.004), Vector2(0.039, 0.02), Vector2(0.041, 0.096),
		Vector2(0.0395, 0.1), Vector2(0.037, 0.099), Vector2(0.0355, 0.09), Vector2(0.034, 0.012), Vector2(0, 0.01)]), Vector3.ZERO, m, 28)
	MU.lathe(n, PackedVector2Array([Vector2(0, 0.074), Vector2(0.0352, 0.074)]), Vector3.ZERO, MU.mat(Color(0.2, 0.09, 0.03), 0, 0.08), 28)
	MU.torus(n, 0.018, 0.027, Vector3(0.044, 0.052, 0), m, Vector3(90, 0, 0))
	# kupa üzerinde baskı şeridi
	MU.lathe(n, PackedVector2Array([Vector2(0.0397, 0.045), Vector2(0.0405, 0.07)]), Vector3.ZERO, MU.mat(Color(0.75, 0.15, 0.15), 0, 0.3), 28)


## Yatay yıldız tornavida: sap +X'te, uç −X'te. `pos` sapın ön (metal tarafı) ucudur.
static func screwdriver(parent: Node, pos: Vector3, yaw := 0.0, col := Color(0.85, 0.15, 0.12)) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw, 0)
	parent.add_child(n)
	var handle := Node3D.new()
	handle.rotation_degrees.z = 90   # +Y ekseni → −X
	n.add_child(handle)
	MU.lathe(handle, PackedVector2Array([Vector2(0, 0), Vector2(0.009, 0), Vector2(0.0118, 0.006), Vector2(0.0125, 0.03),
		Vector2(0.011, 0.07), Vector2(0.0115, 0.082), Vector2(0.008, 0.09), Vector2(0.0055, 0.094), Vector2(0, 0.094)]),
		Vector3(0, -0.094, 0), MU.mat(col, 0, 0.3), 16)
	MU.lathe(handle, PackedVector2Array([Vector2(0.0127, 0.0), Vector2(0.013, 0.022)]), Vector3(0, -0.07, 0), MU.mat(Color(0.08, 0.08, 0.08), 0, 0.85), 16)
	var steel := _metal(Color(0.8, 0.81, 0.84), 0.22)
	MU.cyl(n, 0.0028, 0.1, Vector3(-0.05, 0, 0), steel, Vector3(0, 0, 90), 10)
	MU.cyl(n, 0.0028, 0.012, Vector3(-0.106, 0, 0), steel, Vector3(0, 0, 90), 4, 0.0004)


# ---------------------------------------------------------------- YAZAR KASA

static func register(parent: Node, pos: Vector3, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw, 0)
	parent.add_child(n)
	var body := _plastic(Color(0.16, 0.16, 0.18), 0.4)
	# para çekmecesi + gövde
	MU.slab(n, Vector3(0.38, 0.09, 0.36), Vector3(0, 0.045, 0), body, 0.014, 0.006)
	MU.box(n, Vector3(0.36, 0.002, 0.002), Vector3(0, 0.06, 0.181), MU.mat(Color(0.02, 0.02, 0.02), 0, 0.9))
	MU.slab(n, Vector3(0.08, 0.008, 0.012), Vector3(0, 0.035, 0.18), _metal(Color(0.6, 0.6, 0.63)), 0.003, 0.002)
	# eğimli tuş paneli
	var pad := Node3D.new()
	pad.position = Vector3(0.04, 0.09, 0.07)
	pad.rotation_degrees.x = 12
	n.add_child(pad)
	MU.slab(pad, Vector3(0.2, 0.02, 0.15), Vector3(0, 0.0, 0), body, 0.01, 0.005)
	MU.keycaps(pad, MU.NUMPAD_ROWS, Vector3(-0.012, 0.0095, 0.008), 0.031, 0.007, Color(0.88, 0.88, 0.84), Color(0.1, 0.1, 0.12), 0.18, 0.1, 22, 0.45)
	for i in 3:
		MU.slab(pad, Vector3(0.03, 0.009, 0.026), Vector3(0.078, 0.013, -0.042 + i * 0.034), MU.mat([Color(0.8, 0.2, 0.15), Color(0.95, 0.75, 0.2), Color(0.2, 0.65, 0.3)][i], 0, 0.4), 0.004, 0.0025)
	# kasiyer ekranı
	var disp := Node3D.new()
	disp.position = Vector3(-0.08, 0.09, -0.06)
	disp.rotation_degrees.x = -22
	n.add_child(disp)
	MU.slab(disp, Vector3(0.2, 0.014, 0.13), Vector3(0, 0.065, 0), body, 0.008, 0.004, Vector3(90, 0, 0))
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.11)
	var scr := MeshInstance3D.new()
	scr.mesh = q
	scr.material_override = sm
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scr.position = Vector3(0, 0.065, 0.0075)
	disp.add_child(scr)
	MU.bake_2d(n, Vector2i(360, 220), sm, func(root: Control):
		var bg := ColorRect.new()
		bg.color = Color(0.03, 0.12, 0.08)
		bg.size = root.size
		root.add_child(bg)
		var lines := [["SATIŞ", 22, Color(0.5, 1.0, 0.7)], ["Termal macun      45,00", 18, Color(0.75, 0.95, 0.8)],
			["Servis ücreti    150,00", 18, Color(0.75, 0.95, 0.8)], ["TOPLAM  195,00 ₺", 30, Color(0.6, 1.0, 0.75)]]
		var y := 14
		for l in lines:
			var lb := Label.new()
			lb.text = l[0]
			lb.position = Vector2(16, y)
			lb.add_theme_font_size_override("font_size", l[1])
			lb.add_theme_color_override("font_color", l[2])
			root.add_child(lb)
			y += l[1] + 22
	)
	MU.cyl(disp, 0.018, 0.04, Vector3(0, 0.0, -0.01), body, Vector3.ZERO, 14)
	# fiş yazıcı + kağıt
	MU.slab(n, Vector3(0.1, 0.05, 0.09), Vector3(0.12, 0.115, -0.11), body, 0.012, 0.006)
	MU.box(n, Vector3(0.06, 0.03, 0.001), Vector3(0.12, 0.15, -0.075), MU.mat(Color(0.97, 0.97, 0.95), 0, 0.7), Vector3(-12, 0, 0))
	return n


# ---------------------------------------------------------------- CRT MONİTÖR (süs)

static func crt(parent: Node, pos: Vector3, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw, 0)
	parent.add_child(n)
	var beige := _plastic(Color(0.83, 0.8, 0.7), 0.55)
	# ön çerçeve
	MU.slab(n, Vector3(0.4, 0.08, 0.36), Vector3(0, 0.2, 0.12), beige, 0.03, 0.012, Vector3(90, 0, 0))
	# arka tüp kısmı: kesik piramit
	var piv := Node3D.new()
	piv.position = Vector3(0, 0.2, -0.04)
	piv.rotation_degrees.x = -90
	n.add_child(piv)
	piv.scale = Vector3(1.08, 1.0, 0.9)
	MU.cyl(piv, 0.255, 0.26, Vector3.ZERO, beige, Vector3(0, 45, 0), 4, 0.14)
	# havalandırma yarıkları (üst)
	for i in 6:
		MU.box(n, Vector3(0.18, 0.002, 0.008), Vector3(0, 0.335 - i * 0.006, -0.02 - i * 0.022), MU.mat(Color(0.25, 0.24, 0.22), 0, 0.9))
	# kavisli cam
	MU.slab(n, Vector3(0.33, 0.01, 0.27), Vector3(0, 0.205, 0.161), MU.mat(Color(0.12, 0.12, 0.11), 0, 0.6), 0.02, 0.004, Vector3(90, 0, 0))
	MU.sphere(n, 0.2, Vector3(0, 0.205, 0.158), MU.mat(Color(0.09, 0.12, 0.11), 0.0, 0.45), Vector3(0.78, 0.62, 0.07), 32)
	# alt şerit: marka, düğme, LED
	MU.box(n, Vector3(0.05, 0.008, 0.002), Vector3(-0.12, 0.04, 0.161), MU.mat(Color(0.45, 0.43, 0.38), 0, 0.5))
	MU.cyl(n, 0.009, 0.006, Vector3(0.14, 0.04, 0.162), beige, Vector3(90, 0, 0), 14)
	MU.sphere(n, 0.003, Vector3(0.115, 0.04, 0.161), MU.mat(Color(0.3, 1.0, 0.4), 0, 0.4, 3.0))
	# döner ayak
	MU.slab(n, Vector3(0.24, 0.02, 0.22), Vector3(0, 0.01, 0.0), beige, 0.06, 0.008)
	return n
