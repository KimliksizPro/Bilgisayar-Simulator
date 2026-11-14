extends RefCounted
## Prosedürel low-poly model yardımcıları: kutu, silindir, fan, etiket, doku üretimi.

const INTERACT := preload("res://scripts/interactable.gd")

static var _mat_cache := {}
static var _tex_cache := {}


static func mat(color: Color, metallic := 0.0, roughness := 0.6, emission := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color.to_html(), metallic, roughness, emission]
	if not _mat_cache.has(key):
		_mat_cache[key] = new_mat(color, metallic, roughness, emission)
	return _mat_cache[key]


## Önbelleğe alınmayan, tek başına değiştirilebilen materyal (RGB animasyonları için).
static func new_mat(color: Color, metallic := 0.0, roughness := 0.6, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = emission
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func tex_mat(tex: Texture2D, uv_scale := Vector3.ONE, roughness := 0.7, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.roughness = roughness
	m.uv1_scale = uv_scale
	return m


static func glass() -> StandardMaterial3D:
	var m := new_mat(Color(0.55, 0.7, 0.8, 0.16), 0.3, 0.05)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _add(parent: Node, mesh: Mesh, pos: Vector3, m: Material, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


static func box(parent: Node, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _add(parent, bm, pos, m, rot)


static func cyl(parent: Node, radius: float, height: float, pos: Vector3, m: Material, rot := Vector3.ZERO, sides := 20, top_radius := -1.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.height = height
	cm.radial_segments = sides
	cm.rings = 1
	return _add(parent, cm, pos, m, rot)


static func sphere(parent: Node, radius: float, pos: Vector3, m: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	var mi := _add(parent, sm, pos, m, Vector3.ZERO)
	mi.scale = scl
	return mi


static func torus(parent: Node, inner: float, outer: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 24
	tm.ring_segments = 8
	return _add(parent, tm, pos, m, rot)


static func label(parent: Node, text: String, pos: Vector3, font_size := 32, color := Color.WHITE, rot := Vector3.ZERO, pixel := 0.001) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees = rot
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	parent.add_child(l)
	return l


static func add_box_shape(body: Node, size: Vector3, pos := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	body.add_child(cs)
	return cs


## Görünür + çarpışmalı statik kutu (duvar, masa vb.). m null ise sadece çarpışma.
static func static_box(parent: Node, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.position = pos
	b.rotation_degrees = rot
	b.collision_layer = 1
	b.collision_mask = 0
	parent.add_child(b)
	if m:
		box(b, size, Vector3.ZERO, m)
	add_box_shape(b, size)
	return b


static func interactable(parent: Node, size: Vector3, pos: Vector3, hint_fn: Callable, action: Callable):
	var b = INTERACT.new()
	b.collision_layer = 3
	b.collision_mask = 0
	b.position = pos
	b.hint_fn = hint_fn
	b.action = action
	parent.add_child(b)
	add_box_shape(b, size)
	return b


## Fan: ekseni yerel Y. Dönen kısmı (rotor) döndürür.
static func fan(parent: Node, radius: float, pos: Vector3, rot: Vector3, frame_m: Material, blade_m: Material, ring_m: Material = null) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees = rot
	parent.add_child(root)
	var depth := radius * 0.45
	torus(root, radius * 0.9, radius * 1.02, Vector3.ZERO, ring_m if ring_m else frame_m)
	var rotor := Node3D.new()
	root.add_child(rotor)
	cyl(rotor, radius * 0.3, depth, Vector3.ZERO, frame_m, Vector3.ZERO, 14)
	for i in 7:
		var piv := Node3D.new()
		piv.rotation.y = TAU * i / 7.0
		rotor.add_child(piv)
		box(piv, Vector3(radius * 0.6, depth * 0.12, radius * 0.34), Vector3(radius * 0.58, 0, 0), blade_m, Vector3(28, 0, 0))
	return rotor


# ---------------------------------------------------------------- dokular

static func pcb_texture(base := Color(0.04, 0.2, 0.11)) -> Texture2D:
	var key := "pcb" + base.to_html()
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	img.fill(base)
	var trace := base.lightened(0.25)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 110:
		var x := rng.randi_range(0, 255)
		var y := rng.randi_range(0, 255)
		var length := rng.randi_range(10, 90)
		var horiz := rng.randf() < 0.5
		for k in length:
			var px := x + k if horiz else x
			var py := y if horiz else y + k
			if px < 256 and py < 256:
				img.set_pixel(px, py, trace)
		var ex := x + length if horiz else x
		var ey := y if horiz else y + length
		for dx in 3:
			for dy in 3:
				if ex + dx < 256 and ey + dy < 256:
					img.set_pixel(ex + dx, ey + dy, Color(0.75, 0.62, 0.3))
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t


static func tile_texture() -> Texture2D:
	if _tex_cache.has("tile"):
		return _tex_cache["tile"]
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for ty in 4:
		for tx in 4:
			var c := Color(0.78, 0.76, 0.72).darkened(rng.randf_range(0.0, 0.08))
			for y in 64:
				for x in 64:
					var grout := x < 2 or y < 2
					var n := rng.randf_range(-0.015, 0.015)
					var col := Color(0.45, 0.43, 0.4) if grout else Color(c.r + n, c.g + n, c.b + n)
					img.set_pixel(tx * 64 + x, ty * 64 + y, col)
	var t := ImageTexture.create_from_image(img)
	_tex_cache["tile"] = t
	return t


static func wood_texture() -> Texture2D:
	if _tex_cache.has("wood"):
		return _tex_cache["wood"]
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for y in 128:
		var band := sin(y * 0.35 + sin(y * 0.05) * 3.0) * 0.5 + 0.5
		for x in 128:
			var n := rng.randf_range(-0.02, 0.02)
			var c := Color(0.55, 0.36, 0.2).lerp(Color(0.42, 0.26, 0.14), band)
			img.set_pixel(x, y, Color(c.r + n, c.g + n, c.b + n))
	var t := ImageTexture.create_from_image(img)
	_tex_cache["wood"] = t
	return t
