extends Node3D
## Low-poly müşteri: yürür, konuşur, tıklanınca iş yöneticisine haber verir.

const MU := preload("res://scripts/mesh_util.gd")

var speech: Label3D
var waypoints: Array = []
var on_arrive: Callable
var speed := 1.3
var face_angle := PI
var legs: Array = []
var arms: Array = []
var _t := 0.0


const FEMALE := ["Ayşe", "Zeynep", "Elif", "Fatma", "Selin"]


## `who` müşterinin adıdır ("Ayşe Teyze", "Hasan Amca"...): görünüm (yaş, cinsiyet) buna göre seçilir.
func build(hint_fn: Callable, action: Callable, who := "", uniform := Color(0, 0, 0, 0)) -> void:
	var female := false
	for f in FEMALE:
		if who.begins_with(f):
			female = true
	var old := who.ends_with("Teyze") or who.ends_with("Amca")
	var shirt := Color.from_hsv(randf(), randf_range(0.35, 0.75), randf_range(0.4, 0.8))
	var pants: Color = [Color(0.13, 0.18, 0.32), Color(0.1, 0.1, 0.11), Color(0.32, 0.26, 0.19), Color(0.22, 0.24, 0.27)].pick_random()
	var skin: Color = [Color(0.94, 0.77, 0.64), Color(0.84, 0.64, 0.49), Color(0.68, 0.48, 0.34)].pick_random()
	var hair: Color = [Color(0.08, 0.06, 0.05), Color(0.28, 0.17, 0.08), Color(0.5, 0.32, 0.15), Color(0.75, 0.58, 0.32)].pick_random()
	if old:
		hair = [Color(0.72, 0.72, 0.72), Color(0.86, 0.85, 0.83), Color(0.42, 0.4, 0.38)].pick_random()
	if uniform.a > 0.0:
		shirt = uniform
		old = false
	var style: int = randi() % 3   # 0 tişört, 1 düğmeli gömlek, 2 kapüşonlu
	var shirt_m := MU.mat(shirt, 0, 0.85)
	var trim_m := MU.mat(shirt.darkened(0.3), 0, 0.85)
	var pants_m := MU.mat(pants, 0, 0.9)
	var skin_m := MU.mat(skin, 0, 0.55)
	var hair_m := MU.mat(hair, 0, 0.75)
	var shoe_col: Color = [Color(0.08, 0.07, 0.06), Color(0.9, 0.9, 0.88), Color(0.35, 0.2, 0.12)].pick_random()
	var shoe_m := MU.mat(shoe_col, 0, 0.45)
	var sole_m := MU.mat(Color(0.92, 0.9, 0.86) if shoe_col.v < 0.5 else Color(0.2, 0.2, 0.2), 0, 0.8)
	# --- bacaklar (kalça ekleminden sallanır)
	var leg_prof := PackedVector2Array([Vector2(0, -0.84), Vector2(0.05, -0.84), Vector2(0.056, -0.78), Vector2(0.058, -0.6),
		Vector2(0.066, -0.44), Vector2(0.078, -0.24), Vector2(0.088, -0.06), Vector2(0.08, 0.0), Vector2(0, 0.02)])
	for x in [-0.095, 0.095]:
		var piv := Node3D.new()
		piv.position = Vector3(x, 0.9, 0)
		add_child(piv)
		MU.lathe(piv, leg_prof, Vector3.ZERO, pants_m, 14)
		MU.slab(piv, Vector3(0.105, 0.07, 0.25), Vector3(0, -0.85, 0.035), shoe_m, 0.048, 0.024)
		MU.slab(piv, Vector3(0.11, 0.018, 0.255), Vector3(0, -0.89, 0.035), sole_m, 0.05, 0.006)
		legs.append(MU.no_merge(piv))
	# --- kalça, kemer, gövde
	MU.slab(self, Vector3(0.37, 0.17, 0.235), Vector3(0, 0.9, 0), pants_m, 0.1, 0.05)
	MU.slab(self, Vector3(0.355, 0.032, 0.228), Vector3(0, 0.975, 0), MU.mat(Color(0.12, 0.08, 0.05), 0, 0.5), 0.1, 0.008)
	MU.slab(self, Vector3(0.04, 0.026, 0.006), Vector3(0, 0.975, 0.114), MU.mat(Color(0.8, 0.7, 0.4), 0.9, 0.3), 0.005, 0.002, Vector3(90, 0, 0))
	var torso_prof := PackedVector2Array([Vector2(0, 0), Vector2(0.168, 0), Vector2(0.172, 0.06), Vector2(0.168, 0.2),
		Vector2(0.182, 0.36), Vector2(0.2, 0.45), Vector2(0.198, 0.51), Vector2(0.165, 0.565), Vector2(0.09, 0.6), Vector2(0, 0.61)])
	var torso := MU.lathe(self, torso_prof, Vector3(0, 0.93, 0), shirt_m, 20)
	torso.scale = Vector3(1.0, 1.0, 0.62)
	if female:
		torso.scale = Vector3(0.92, 1.0, 0.64)
	match style:
		0:  # tişört: göğüste şerit
			var band := MU.lathe(self, PackedVector2Array([Vector2(0.1835, 0.37), Vector2(0.192, 0.41)]), Vector3(0, 0.93, 0), trim_m, 20)
			band.scale = torso.scale * Vector3(1.01, 1, 1.01)
			MU.torus(self, 0.05, 0.068, Vector3(0, 1.535, 0.0), trim_m)
		1:  # gömlek: yaka + düğmeler
			for sx in [-1, 1]:
				MU.slab(self, Vector3(0.06, 0.008, 0.07), Vector3(sx * 0.035, 1.505, 0.075), trim_m, 0.012, 0.003, Vector3(-62, sx * 28, sx * 18))
			var bz := [0.124, 0.119, 0.111, 0.106]
			for i in 4:
				MU.cyl(self, 0.006, 0.004, Vector3(0, 1.44 - i * 0.1, bz[i]), MU.mat(Color(0.95, 0.95, 0.92), 0, 0.3), Vector3(90, 0, 0), 8)
		2:  # kapüşonlu: arkada kapüşon rulosu, ipler, kanguru cebi
			MU.torus(self, 0.06, 0.115, Vector3(0, 1.53, -0.035), shirt_m, Vector3(-20, 0, 0))
			for sx in [-0.03, 0.03]:
				MU.cyl(self, 0.004, 0.12, Vector3(sx, 1.45, 0.122), MU.mat(Color(0.95, 0.95, 0.95), 0, 0.6), Vector3.ZERO, 6)
			MU.slab(self, Vector3(0.22, 0.012, 0.11), Vector3(0, 1.06, 0.105), trim_m, 0.03, 0.005, Vector3(90, 0, 0))
	# --- kollar (omuzdan sallanır), hafif dışa açık
	var long_sleeve := style != 0 or randf() < 0.3
	for sx in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.position = Vector3(sx * 0.2, 1.415, 0)
		add_child(piv)
		var arm := Node3D.new()
		arm.rotation_degrees.z = sx * 4.0
		piv.add_child(arm)
		MU.sphere(arm, 0.055, Vector3(0, 0, 0), shirt_m, Vector3(1.0, 0.9, 1.0))
		MU.capsule(arm, 0.05, 0.34, Vector3(0, -0.15, 0), shirt_m)
		MU.capsule(arm, 0.045, 0.3, Vector3(0, -0.42, 0.015), shirt_m if long_sleeve else skin_m, Vector3(-6, 0, 0))
		if not long_sleeve:
			MU.lathe(arm, PackedVector2Array([Vector2(0.058, -0.29), Vector2(0.062, -0.27), Vector2(0.06, -0.25)]), Vector3.ZERO, trim_m, 14)
		else:
			MU.lathe(arm, PackedVector2Array([Vector2(0.044, -0.56), Vector2(0.05, -0.55), Vector2(0.05, -0.53)]), Vector3(0, 0, 0.03), trim_m, 14)
		# el: avuç + başparmak
		MU.sphere(arm, 0.042, Vector3(0, -0.615, 0.03), skin_m, Vector3(0.7, 1.25, 0.5))
		MU.capsule(arm, 0.013, 0.06, Vector3(-sx * 0.012, -0.6, 0.055), skin_m, Vector3(-25, 0, sx * 20))
		arms.append(MU.no_merge(piv))
	# --- boyun, kafa
	MU.cyl(self, 0.048, 0.12, Vector3(0, 1.555, 0), skin_m, Vector3.ZERO, 14)
	var head := MU.lathe(self, PackedVector2Array([Vector2(0, -0.118), Vector2(0.035, -0.115), Vector2(0.066, -0.098),
		Vector2(0.086, -0.064), Vector2(0.097, -0.022), Vector2(0.106, 0.025), Vector2(0.11, 0.06), Vector2(0.104, 0.1),
		Vector2(0.085, 0.127), Vector2(0.05, 0.142), Vector2(0, 0.147)]), Vector3(0, 1.68, 0), skin_m, 32)
	head.scale = Vector3(0.9, 1.0, 1.0)
	for x in [-0.096, 0.096]:
		MU.sphere(self, 0.026, Vector3(x, 1.678, -0.006), skin_m, Vector3(0.42, 1.0, 0.72))
	# burun
	MU.sphere(self, 0.013, Vector3(0, 1.672, 0.096), skin_m, Vector3(0.75, 1.6, 0.9))
	MU.sphere(self, 0.0125, Vector3(0, 1.655, 0.101), skin_m, Vector3(1.05, 0.85, 0.95))
	# gözler: beyaz + renkli iris + bebek
	var iris: Color = [Color(0.3, 0.18, 0.08), Color(0.2, 0.35, 0.55), Color(0.25, 0.4, 0.2), Color(0.12, 0.08, 0.05)].pick_random()
	for x in [-0.039, 0.039]:
		MU.sphere(self, 0.016, Vector3(x, 1.695, 0.086), MU.mat(Color(0.96, 0.95, 0.93), 0, 0.15), Vector3(1.0, 0.72, 0.65))
		MU.sphere(self, 0.0092, Vector3(x, 1.695, 0.0955), MU.mat(iris, 0, 0.2), Vector3(1, 1, 0.4))
		MU.sphere(self, 0.0046, Vector3(x, 1.695, 0.0993), MU.mat(Color(0.02, 0.02, 0.02), 0, 0.1), Vector3(1, 1, 0.4))
		MU.slab(self, Vector3(0.034, 0.006, 0.01), Vector3(x, 1.721, 0.098), hair_m if not old else MU.mat(hair.darkened(0.3), 0, 0.8), 0.004, 0.002, Vector3(0, 0, -sign(x) * 8.0))
	# ağız
	MU.slab(self, Vector3(0.038, 0.008, 0.01), Vector3(0, 1.618, 0.084), MU.mat(skin.darkened(0.25).lerp(Color(0.6, 0.25, 0.25), 0.35), 0, 0.45), 0.004, 0.003)
	# saç (kurye ise şapka)
	if uniform.a > 0.0:
		MU.sphere(self, 0.135, Vector3(0, 1.76, -0.01), shirt_m, Vector3(1.04, 0.72, 1.04))
		MU.rbox(self, Vector3(0.2, 0.015, 0.12), Vector3(0, 1.78, 0.12), shirt_m, 0.006)
	elif old and not female and randf() < 0.6:
		# kel + yanlarda saç
		MU.sphere(self, 0.112, Vector3(0, 1.69, -0.016), hair_m, Vector3(0.88, 0.45, 0.95), 28)
	else:
		MU.sphere(self, 0.122, Vector3(0, 1.758, -0.014), hair_m, Vector3(0.92, 0.8, 1.0), 28)
		# alın perçemi
		MU.sphere(self, 0.075, Vector3(0.012, 1.792, 0.068), hair_m, Vector3(1.1, 0.38, 0.56), 24)
	if female:
		if old:
			MU.sphere(self, 0.052, Vector3(0, 1.81, -0.1), hair_m)   # topuz
		else:
			MU.sphere(self, 0.12, Vector3(0, 1.58, -0.07), hair_m, Vector3(1.05, 1.7, 0.55), 24)   # uzun saç
	elif old:
		MU.slab(self, Vector3(0.062, 0.014, 0.018), Vector3(0, 1.636, 0.092), hair_m, 0.007, 0.005)   # bıyık
	elif randf() < 0.3:
		MU.sphere(self, 0.094, Vector3(0, 1.625, 0.004), MU.mat(skin.lerp(hair, 0.6), 0, 0.9), Vector3(0.86, 0.66, 0.94), 28)   # kısa sakal
		MU.slab(self, Vector3(0.038, 0.008, 0.01), Vector3(0, 1.618, 0.091), MU.mat(skin.darkened(0.25).lerp(Color(0.6, 0.25, 0.25), 0.35), 0, 0.45), 0.004, 0.003)
	# gözlük
	if old or randf() < 0.25:
		var gl := MU.mat(Color(0.1, 0.1, 0.1) if randf() < 0.5 else Color(0.6, 0.5, 0.3), 0.6, 0.3)
		for x in [-0.04, 0.04]:
			MU.torus(self, 0.019, 0.023, Vector3(x, 1.695, 0.106), gl, Vector3(90, 0, 0))
		MU.box(self, Vector3(0.022, 0.003, 0.003), Vector3(0, 1.7, 0.107), gl)
		for x in [-0.062, 0.062]:
			MU.box(self, Vector3(0.003, 0.003, 0.1), Vector3(x * 1.5, 1.7, 0.056), gl)
	for limb in legs + arms:
		MU.merge_static(limb)
	MU.merge_static(self)
	MU.interactable(self, Vector3(0.55, 1.8, 0.45), Vector3(0, 0.9, 0), hint_fn, action)
	speech = Label3D.new()
	speech.position = Vector3(0, 2.08, 0)
	speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	speech.font_size = 44
	speech.pixel_size = 0.0016
	speech.outline_size = 22
	speech.outline_modulate = Color(0.02, 0.02, 0.05, 1.0)
	speech.modulate = Color(1.4, 1.4, 1.3)
	speech.no_depth_test = true
	speech.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	speech.render_priority = 10
	speech.outline_render_priority = 9
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech.width = 650
	add_child(speech)


func say(text: String, angry := false) -> void:
	speech.text = text
	speech.modulate = Color(1.5, 0.7, 0.6) if angry else Color(1.4, 1.4, 1.3)


func walk(points: Array, cb := Callable()) -> void:
	waypoints = points.duplicate()
	on_arrive = cb


func _process(delta: float) -> void:
	_t += delta
	if waypoints.size() > 0:
		var tgt: Vector3 = waypoints[0]
		var d := tgt - position
		d.y = 0
		if d.length() < 0.05:
			waypoints.pop_front()
			if waypoints.is_empty() and on_arrive.is_valid():
				on_arrive.call()
		else:
			position += d.normalized() * min(speed * delta, d.length())
			face_angle = atan2(d.x, d.z)
		var swing := sin(_t * 8.0) * 0.5
		legs[0].rotation.x = swing
		legs[1].rotation.x = -swing
		arms[0].rotation.x = -swing * 0.7
		arms[1].rotation.x = swing * 0.7
	else:
		for n in legs + arms:
			n.rotation.x = lerp(n.rotation.x, 0.0, delta * 8.0)
		arms[1].rotation.z = sin(_t * 1.7) * 0.05
	rotation.y = lerp_angle(rotation.y, face_angle, delta * 8.0)
