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


## Poly Haven (CC0) PBR doku seti: assets/textures/<isim>/{albedo,normal,arm}.jpg
## Dünya koordinatlı triplanar: uv_scale = metre başına tekrar sayısı.
static func pbr(tex_name: String, uv_scale := 1.0, tint := Color.WHITE, normal_strength := 1.0) -> StandardMaterial3D:
	var key := "pbr|%s|%s|%s|%s" % [tex_name, uv_scale, tint.to_html(), normal_strength]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var dir := "res://assets/textures/%s/" % tex_name
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(dir + "albedo.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(dir + "normal.jpg")
	m.normal_scale = normal_strength
	var arm: Texture2D = load(dir + "arm.jpg")
	m.roughness_texture = arm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.ao_enabled = true
	m.ao_texture = arm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[key] = m
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


static var _rbox_cache := {}


## Kenarları yuvarlatılmış kutu. Keskin kutulardan çok daha "gerçek" görünür (kenarlar ışığı yakalar).
static func rbox(parent: Node, size: Vector3, pos: Vector3, m: Material, radius := 0.01, rot := Vector3.ZERO) -> MeshInstance3D:
	var seg := 1 if radius <= 0.006 else 2
	return _add(parent, rounded_box_mesh(size, radius, seg), pos, m, rot)


static func rounded_box_mesh(size: Vector3, radius: float, seg := 3) -> ArrayMesh:
	var key := "%s|%s|%s" % [size, radius, seg]
	if _rbox_cache.has(key):
		return _rbox_cache[key]
	var h := size / 2.0
	var r: float = min(radius, h.x, h.y, h.z)
	var inner := h - Vector3(r, r, r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for a in 3:
		var b := (a + 1) % 3
		var c := (a + 2) % 3
		var cb := _round_coords(h[b], r, seg)
		var cc := _round_coords(h[c], r, seg)
		for s in [-1.0, 1.0]:
			var fn := Vector3.ZERO
			fn[a] = s
			for i in cb.size():
				for j in cc.size():
					var p := Vector3.ZERO
					p[a] = s * h[a]
					p[b] = cb[i]
					p[c] = cc[j]
					var q := p.clamp(-inner, inner)
					var d := p - q
					var n := d.normalized() if d.length() > 0.00001 else fn
					st.set_normal(n)
					st.set_uv(Vector2((cb[i] + h[b]) / size[b], (cc[j] + h[c]) / size[c]))
					st.add_vertex(q + n * r if r > 0.0 else p)
			var w := cc.size()
			for i in cb.size() - 1:
				for j in w - 1:
					var i0 := base + i * w + j
					var i1 := base + (i + 1) * w + j
					var i2 := base + (i + 1) * w + j + 1
					var i3 := base + i * w + j + 1
					# Godot: ön yüz saat yönünde. b x c = a ekseni; s>0 için ters sıra.
					if s > 0:
						st.add_index(i0); st.add_index(i2); st.add_index(i1)
						st.add_index(i0); st.add_index(i3); st.add_index(i2)
					else:
						st.add_index(i0); st.add_index(i1); st.add_index(i2)
						st.add_index(i0); st.add_index(i2); st.add_index(i3)
			base += cb.size() * w
	st.generate_tangents()
	var mesh := st.commit()
	_rbox_cache[key] = mesh
	return mesh


static func _round_coords(hh: float, r: float, seg: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var inn := hh - r
	for i in seg + 1:
		out.append(-inn - r * cos(PI / 2.0 * i / seg))
	for i in range(seg, -1, -1):
		out.append(inn + r * cos(PI / 2.0 * i / seg))
	return out


static func capsule(parent: Node, radius: float, height: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	cm.radial_segments = 16
	cm.rings = 6
	return _add(parent, cm, pos, m, rot)


static func cyl(parent: Node, radius: float, height: float, pos: Vector3, m: Material, rot := Vector3.ZERO, sides := 20, top_radius := -1.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.height = height
	cm.radial_segments = sides
	cm.rings = 1
	return _add(parent, cm, pos, m, rot)


static func sphere(parent: Node, radius: float, pos: Vector3, m: Material, scl := Vector3.ONE, segments := 16) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = segments
	sm.rings = segments / 2
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
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # yazılar gölge geçişlerinde boşuna çizilmesin
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
static func fan(parent: Node, radius: float, pos: Vector3, rot: Vector3, frame_m: Material, blade_m: Material, ring_m: Material = null, hub_m: Material = null) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees = rot
	parent.add_child(root)
	var depth := radius * 0.45
	torus(root, radius * 0.9, radius * 1.02, Vector3.ZERO, ring_m if ring_m else frame_m)
	var rotor := Node3D.new()
	no_merge(rotor)
	root.add_child(rotor)
	cyl(rotor, radius * 0.3, depth, Vector3.ZERO, frame_m, Vector3.ZERO, 14)
	if hub_m:
		cyl(rotor, radius * 0.22, depth * 0.1, Vector3(0, depth * 0.52, 0), hub_m, Vector3.ZERO, 14)
		cyl(rotor, radius * 0.22, depth * 0.1, Vector3(0, -depth * 0.52, 0), hub_m, Vector3.ZERO, 14)
	for i in 7:
		var piv := Node3D.new()
		piv.rotation.y = TAU * i / 7.0
		rotor.add_child(piv)
		box(piv, Vector3(radius * 0.6, depth * 0.12, radius * 0.34), Vector3(radius * 0.58, 0, 0), blade_m, Vector3(28, 0, 0))
	merge_static(rotor)
	return rotor


## Noktalardan geçen Catmull-Rom eğrisi boyunca düzgün bir tüp (kablo) üretir. Noktalar parent uzayındadır.
static func tube(parent: Node, points: Array[Vector3], radius: float, m: Material, sides := 6) -> MeshInstance3D:
	var path := _catmull(points, 8)
	var n := path.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t0 := (path[1] - path[0]).normalized()
	var up := Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var normal := t0.cross(up).normalized()
	for i in n:
		var t: Vector3
		if i == 0:
			t = path[1] - path[0]
		elif i == n - 1:
			t = path[n - 1] - path[n - 2]
		else:
			t = path[i + 1] - path[i - 1]
		t = t.normalized()
		normal = (normal - t * normal.dot(t)).normalized()
		var bn := t.cross(normal)
		for s in sides:
			var a := TAU * s / sides
			var dir := normal * cos(a) + bn * sin(a)
			st.set_normal(dir)
			st.set_uv(Vector2(float(s) / sides, float(i) / n))
			st.add_vertex(path[i] + dir * radius)
	for i in n - 1:
		for s in sides:
			var a := i * sides + s
			var b := i * sides + (s + 1) % sides
			var c := (i + 1) * sides + s
			var d := (i + 1) * sides + (s + 1) % sides
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	parent.add_child(mi)
	return mi


static func _catmull(pts: Array[Vector3], sub: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in pts.size() - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, pts.size() - 1)]
		for k in sub:
			var t := float(k) / sub
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[pts.size() - 1])
	return out


# ---------------------------------------------------------------- optimizasyon

## Bu düğüm (ve altı) birleştirilmez: hareket eden/dönen/görünürlüğü değişen şeyler için.
static func no_merge(n: Node) -> Node:
	n.set_meta("no_merge", true)
	return n


## Static batching: root altındaki sabit MeshInstance'ları malzemeye göre tek bir mesh'te birleştirir.
## Yüzlerce küçük nesne (tuşlar, kanatçıklar, vidalar) birkaç draw call'a iner.
static func merge_static(root: Node3D) -> MeshInstance3D:
	var tools := {}
	var order := []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.visible:
			continue
		var mat: Material = mi.material_override
		if mat == null or (mat is BaseMaterial3D and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
			continue
		var rel: Transform3D = mi.transform
		var p: Node = mi
		var ok := not mi.has_meta("no_merge")
		while ok and p != root:
			p = p.get_parent()
			if p == root:
				break
			if p == null or not (p is Node3D) or p.has_meta("no_merge"):
				ok = false
			else:
				rel = p.transform * rel
		if not ok:
			continue
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
			order.append(mat)
		for si in mi.mesh.get_surface_count():
			tools[mat].append_from(mi.mesh, si, rel)
		mi.mesh = null
		# boşalan düğümü sil: sahne ağacı küçülür, dönüşüm güncellemesi ve görünürlük testi maliyeti kalmaz
		if mi.get_child_count() == 0:
			mi.get_parent().remove_child(mi)
			mi.free()
	if order.is_empty():
		return null
	var am := ArrayMesh.new()
	for mat in order:
		tools[mat].commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	var merged := MeshInstance3D.new()
	merged.name = "Merged"
	merged.mesh = am
	root.add_child(merged)
	return merged


# ---------------------------------------------------------------- dokular

static func pcb_texture(base := Color(0.04, 0.2, 0.11)) -> Texture2D:
	var key := "pcb" + base.to_html()
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create_empty(256, 256, false, Image.FORMAT_RGB8)
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
	var img := Image.create_empty(256, 256, false, Image.FORMAT_RGB8)
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
	var img := Image.create_empty(128, 128, false, Image.FORMAT_RGB8)
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


## Tüylü toz dokusu: gri, rastgele alfa lekeleri (toz katmanları için).
static func dust_texture() -> Texture2D:
	if _tex_cache.has("dust"):
		return _tex_cache["dust"]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	noise.seed = 7
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for y in 96:
		for x in 96:
			var v := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((v - 0.25) * 1.8, 0.0, 1.0) * rng.randf_range(0.8, 1.0)
			var g := rng.randf_range(0.58, 0.66)
			img.set_pixel(x, y, Color(g, g, g * 0.97, a))
	var t := ImageTexture.create_from_image(img)
	_tex_cache["dust"] = t
	return t


# ---------------------------------------------------------------- gelişmiş şekiller

## Üçgeni, köşe normallerinin ortalamasına göre doğru yöne (Godot: ön yüz saat yönü) çevirerek ekler.
static func _tri_idx(st: SurfaceTool, verts: PackedVector3Array, norms: PackedVector3Array, a: int, b: int, c: int) -> void:
	var fn := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if fn.length_squared() < 1e-14:
		return
	if fn.dot(norms[a] + norms[b] + norms[c]) > 0.0:
		st.add_index(a); st.add_index(c); st.add_index(b)
	else:
		st.add_index(a); st.add_index(b); st.add_index(c)


static func _rrect_outline(hx: float, hz: float, r: float, seg: int) -> Array:
	# merkez çevresinde yuvarlatılmış dikdörtgen: [noktalar, dış normaller]
	var pts: Array[Vector2] = []
	var nrm: Array[Vector2] = []
	var corners := [Vector2(hx - r, hz - r), Vector2(-hx + r, hz - r), Vector2(-hx + r, -hz + r), Vector2(hx - r, -hz + r)]
	for ci in 4:
		for s in seg + 1:
			var a := PI / 2.0 * ci + PI / 2.0 * s / seg
			var d := Vector2(cos(a), sin(a))
			pts.append(corners[ci] + d * r)
			nrm.append(d)
	return [pts, nrm]


static var _slab_cache := {}


## Telefon/laptop gibi gövdeler: XZ düzleminde köşeleri `corner_r` ile yuvarlatılmış, üst ve alt
## kenarları `bevel` ile pahlanmış (yumuşak) levha. Kutudan çok daha "ürün" gibi görünür.
static func slab_mesh(size: Vector3, corner_r: float, bevel: float, corner_seg := 5) -> ArrayMesh:
	var key := "%s|%s|%s|%s" % [size, corner_r, bevel, corner_seg]
	if _slab_cache.has(key):
		return _slab_cache[key]
	var h := size / 2.0
	bevel = minf(bevel, minf(h.y, minf(h.x, h.z)) * 0.99)
	corner_r = clampf(corner_r, bevel + 0.0001, minf(h.x, h.z))
	var core: Array = _rrect_outline(h.x - bevel, h.z - bevel, corner_r - bevel, corner_seg)
	var cp: Array[Vector2] = core[0]
	var cn: Array[Vector2] = core[1]
	var n := cp.size()
	var rings := [[-90.0, -1.0], [-45.0, -1.0], [0.0, -1.0], [0.0, 1.0], [45.0, 1.0], [90.0, 1.0]]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rg in rings:
		var phi := deg_to_rad(rg[0])
		var yb: float = rg[1] * (h.y - bevel)
		for i in n:
			var o := cn[i] * cos(phi)
			var p := Vector3(cp[i].x + o.x * bevel, yb + sin(phi) * bevel, cp[i].y + o.y * bevel)
			var nn := Vector3(cn[i].x * cos(phi), sin(phi), cn[i].y * cos(phi)).normalized()
			verts.append(p)
			norms.append(nn)
			st.set_normal(nn)
			st.set_uv(Vector2(p.x / size.x + 0.5, p.z / size.z + 0.5))
			st.add_vertex(p)
	for ri in rings.size() - 1:
		for i in n:
			var j := (i + 1) % n
			var a := ri * n + i
			var b := ri * n + j
			var c := (ri + 1) * n + i
			var d := (ri + 1) * n + j
			_tri_idx(st, verts, norms, a, c, b)
			_tri_idx(st, verts, norms, b, c, d)
	# kapaklar (merkezden yelpaze)
	for cap in [[-1.0, 0], [1.0, rings.size() - 1]]:
		var ci := verts.size()
		var cpos := Vector3(0, cap[0] * h.y, 0)
		var cnor := Vector3(0, cap[0], 0)
		verts.append(cpos)
		norms.append(cnor)
		st.set_normal(cnor)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(cpos)
		var base: int = cap[1] * n
		for i in n:
			_tri_idx(st, verts, norms, ci, base + i, base + (i + 1) % n)
	st.generate_tangents()
	var mesh := st.commit()
	_slab_cache[key] = mesh
	return mesh


static func slab(parent: Node, size: Vector3, pos: Vector3, m: Material, corner_r := 0.01, bevel := 0.002, rot := Vector3.ZERO) -> MeshInstance3D:
	return _add(parent, slab_mesh(size, corner_r, bevel), pos, m, rot)


static var _lathe_cache := {}


## Torna yüzeyi: (yarıçap, yükseklik) profilini Y ekseni etrafında döndürür. Kupa, lamba başlığı,
## sprey kutusu, saksı gibi yuvarlak nesneler için. Aynı nokta art arda iki kez verilirse keskin kenar olur.
static func lathe_mesh(profile: PackedVector2Array, sides := 24) -> ArrayMesh:
	var key := "%s|%s" % [profile, sides]
	if _lathe_cache.has(key):
		return _lathe_cache[key]
	var np := profile.size()
	var pn: Array[Vector2] = []
	var vlen := 0.0
	var vs: Array[float] = [0.0]
	for i in np:
		var prev := i - 1 if i > 0 and not profile[i - 1].is_equal_approx(profile[i]) else i
		var next := i + 1 if i < np - 1 and not profile[i + 1].is_equal_approx(profile[i]) else i
		var t := profile[next] - profile[prev]
		pn.append(Vector2(t.y, -t.x).normalized() if t.length() > 0.0 else Vector2.UP)
		if i > 0:
			vlen += profile[i].distance_to(profile[i - 1])
			vs.append(vlen)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in sides + 1:
		var a := TAU * s / sides
		var ca := cos(a)
		var sa := sin(a)
		for i in np:
			var p := Vector3(profile[i].x * ca, profile[i].y, profile[i].x * sa)
			var nn := Vector3(pn[i].x * ca, pn[i].y, pn[i].x * sa).normalized()
			verts.append(p)
			norms.append(nn)
			st.set_normal(nn)
			st.set_uv(Vector2(float(s) / sides, vs[i] / maxf(vlen, 0.0001)))
			st.add_vertex(p)
	for s in sides:
		for i in np - 1:
			if profile[i].is_equal_approx(profile[i + 1]):
				continue
			var a := s * np + i
			var b := (s + 1) * np + i
			_tri_idx(st, verts, norms, a, b, a + 1)
			_tri_idx(st, verts, norms, b, b + 1, a + 1)
	st.generate_tangents()
	var mesh := st.commit()
	_lathe_cache[key] = mesh
	return mesh


static func lathe(parent: Node, profile: PackedVector2Array, pos: Vector3, m: Material, sides := 24, rot := Vector3.ZERO) -> MeshInstance3D:
	return _add(parent, lathe_mesh(profile, sides), pos, m, rot)


# ---------------------------------------------------------------- klavye

## Q klavye düzeni (birim = 1 tuş genişliği). Her satır: [[etiket, genişlik], ...]; etiket "" boşluk demek.
const KB_ROWS := [
	[["Esc", 1], ["", 0.5], ["F1", 1], ["F2", 1], ["F3", 1], ["F4", 1], ["", 0.25], ["F5", 1], ["F6", 1], ["F7", 1], ["F8", 1], ["", 0.25], ["F9", 1], ["F10", 1], ["F11", 1], ["F12", 1]],
	[["\"", 1], ["1", 1], ["2", 1], ["3", 1], ["4", 1], ["5", 1], ["6", 1], ["7", 1], ["8", 1], ["9", 1], ["0", 1], ["*", 1], ["-", 1], ["⌫", 2]],
	[["Tab", 1.5], ["Q", 1], ["W", 1], ["E", 1], ["R", 1], ["T", 1], ["Y", 1], ["U", 1], ["I", 1], ["O", 1], ["P", 1], ["Ğ", 1], ["Ü", 1], [",", 1.5]],
	[["Caps", 1.75], ["A", 1], ["S", 1], ["D", 1], ["F", 1], ["G", 1], ["H", 1], ["J", 1], ["K", 1], ["L", 1], ["Ş", 1], ["İ", 1], ["Enter", 2.25]],
	[["Shift", 2.25], ["Z", 1], ["X", 1], ["C", 1], ["V", 1], ["B", 1], ["N", 1], ["M", 1], ["Ö", 1], ["Ç", 1], [".", 1], ["Shift", 1.75], ["▲", 1]],
	[["Ctrl", 1.25], ["❖", 1.25], ["Alt", 1.25], ["", 0], [" ", 6.25], ["AltGr", 1], ["Fn", 1], ["◀", 1], ["▼", 1], ["▶", 1]],
]

const NUMPAD_ROWS := [
	[["7", 1], ["8", 1], ["9", 1], ["×", 1]],
	[["4", 1], ["5", 1], ["6", 1], ["−", 1]],
	[["1", 1], ["2", 1], ["3", 1], ["+", 1]],
	[["0", 2], [".", 1], ["=", 1]],
]


## Tuş kapakları: TÜM tuşlar tek bir mesh ve tek malzemeyle çizilir (1 draw call). Harfler, klavyenin
## üstten görünüşü olarak bir kez 2D'de çizilip dokuya pişirilir; tuşların üst yüzü bu dokuya planar
## eşlenir. `u` = bir tuş birimi (metre), `h` = tuş yüksekliği, `taper` = kapak daralması (0: düz chiclet).
## Dönüş: tuş bloğunun boyutu (x genişlik, z derinlik). Blok, `pos` merkezli kurulur; tuşlar +Y'ye çıkar.
static func keycaps(parent: Node, rows: Array, pos: Vector3, u: float, h: float, cap_col: Color, legend_col: Color,
		taper := 0.12, gap := 0.1, legend_px := 22, roughness := 0.55) -> Vector2:
	var row_u := 0.0
	for row in rows:
		var w := 0.0
		for k in row:
			w += k[1]
		row_u = maxf(row_u, w)
	var size := Vector2(row_u * u, rows.size() * u)
	var keys := []  # [x0, z0, w, d, etiket] (blok sol-üst köşesine göre, metre)
	for ri in rows.size():
		var x := 0.0
		for k in rows[ri]:
			if k[0] != "":
				keys.append([x * u, ri * u, k[1] * u, u, k[0]])
			x += k[1]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = roughness
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var px_per_m := 2048.0 / maxf(size.x, size.y)
	var tex_size := Vector2i(int(size.x * px_per_m), int(size.y * px_per_m))
	bake_2d(parent, tex_size, m, func(root: Control):
		var bg := ColorRect.new()
		bg.color = cap_col
		bg.size = Vector2(tex_size)
		root.add_child(bg)
		for k in keys:
			var lab: String = k[4]
			if lab == " ":
				continue
			var l := Label.new()
			l.text = lab
			l.position = Vector2(k[0], k[1]) * px_per_m
			l.size = Vector2(k[2], k[3]) * px_per_m
			var wide: bool = k[2] >= u * 1.5 and lab.length() > 1
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if wide else HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_TOP if wide else VERTICAL_ALIGNMENT_CENTER
			if wide:
				l.position += Vector2(u * 0.2, u * 0.16) * px_per_m
			var fs := legend_px if lab.length() <= 2 else int(legend_px * 0.62)
			l.add_theme_font_size_override("font_size", int(fs * px_per_m * u / 48.0))
			l.add_theme_color_override("font_color", legend_col)
			root.add_child(l)
	)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := gap * u
	var tp := taper * u * 0.5
	var ch := minf(h * 0.25, u * 0.06)
	for k in keys:
		var x0: float = k[0] + g / 2 - size.x / 2
		var z0: float = k[1] + g / 2 - size.y / 2
		var x1: float = k[0] + k[2] - g / 2 - size.x / 2
		var z1: float = k[1] + k[3] - g / 2 - size.y / 2
		var r0 := [x0, z0, x1, z1, 0.0]
		var r1 := [x0 + tp, z0 + tp, x1 - tp, z1 - tp, h - ch]
		var r2 := [x0 + tp + ch, z0 + tp + ch, x1 - tp - ch, z1 - tp - ch, h]
		_keycap_band(st, r0, r1, size)
		_keycap_band(st, r1, r2, size)
		var c := _ring_pts(r2)
		_quad_flat(st, c[0], c[1], c[2], c[3], Vector3.UP, size)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return size


static func _ring_pts(r: Array) -> Array:
	return [Vector3(r[0], r[4], r[1]), Vector3(r[2], r[4], r[1]), Vector3(r[2], r[4], r[3]), Vector3(r[0], r[4], r[3])]


static func _keycap_band(st: SurfaceTool, ra: Array, rb: Array, size: Vector2) -> void:
	var a := _ring_pts(ra)
	var b := _ring_pts(rb)
	var outs := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	for i in 4:
		var j := (i + 1) % 4
		var n: Vector3 = (b[i] - a[i]).cross(a[j] - a[i]).normalized()
		if n.dot(outs[i]) < 0.0:
			n = -n
		_quad_flat(st, a[i], a[j], b[j], b[i], n, size)


static func _quad_flat(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, size: Vector2) -> void:
	var tris := [[p0, p1, p2], [p0, p2, p3]]
	for t in tris:
		var fn: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
		if fn.dot(n) > 0.0:
			t = [t[0], t[2], t[1]]
		for p in t:
			st.set_normal(n)
			st.set_uv(Vector2(p.x / size.x + 0.5, p.z / size.y + 0.5))
			st.add_vertex(p)


## 2D arayüzü (Label, ColorRect...) bir kez çizip malzemenin albedo dokusuna "pişirir".
## Çizimden sonra SubViewport silinir ve mipmap'li statik doku kalır: sürekli maliyeti yok.
## `emissive` true ise doku aynı zamanda ışık yayar (ekranlar için).
static func bake_2d(owner: Node, size: Vector2i, m: StandardMaterial3D, build: Callable, emissive := 0.0) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var root := Control.new()
	root.size = Vector2(size)
	vp.add_child(root)
	build.call(root)
	owner.add_child(vp)
	var vtex := vp.get_texture()
	m.albedo_texture = vtex
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission_texture = vtex
		m.emission = Color.WHITE
		m.emission_energy_multiplier = emissive
	var job := func():
		if not vp.is_inside_tree():
			await vp.tree_entered
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not is_instance_valid(vp):
			return
		var img := vp.get_texture().get_image()
		if img and not img.is_empty():
			img.generate_mipmaps()
			var t := ImageTexture.create_from_image(img)
			m.albedo_texture = t
			if m.emission_enabled:
				m.emission_texture = t
			vp.queue_free()
	job.call()
