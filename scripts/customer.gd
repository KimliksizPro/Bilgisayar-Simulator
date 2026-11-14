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


func build(hint_fn: Callable, action: Callable, uniform := Color(0, 0, 0, 0)) -> void:
	var shirt := Color.from_hsv(randf(), randf_range(0.4, 0.8), randf_range(0.45, 0.85))
	if uniform.a > 0.0:
		shirt = uniform
	var pants: Color = [Color(0.15, 0.2, 0.35), Color(0.12, 0.12, 0.13), Color(0.35, 0.28, 0.2)].pick_random()
	var skin: Color = [Color(0.95, 0.78, 0.64), Color(0.82, 0.62, 0.46), Color(0.6, 0.42, 0.3)].pick_random()
	var hair: Color = [Color(0.1, 0.07, 0.05), Color(0.35, 0.22, 0.1), Color(0.7, 0.7, 0.7), Color(0.85, 0.65, 0.3)].pick_random()
	var shirt_m := MU.mat(shirt, 0, 0.85)
	var pants_m := MU.mat(pants, 0, 0.85)
	var skin_m := MU.mat(skin, 0, 0.55)
	var shoe_m := MU.mat(Color(0.09, 0.08, 0.07), 0, 0.4)
	for x in [-0.1, 0.1]:
		var piv := Node3D.new()
		piv.position = Vector3(x, 0.88, 0)
		add_child(piv)
		MU.capsule(piv, 0.075, 0.86, Vector3(0, -0.42, 0), pants_m)
		MU.rbox(piv, Vector3(0.12, 0.07, 0.25), Vector3(0, -0.85, 0.04), shoe_m, 0.03)
		legs.append(MU.no_merge(piv))
	MU.rbox(self, Vector3(0.42, 0.62, 0.24), Vector3(0, 1.16, 0), shirt_m, 0.09)
	MU.rbox(self, Vector3(0.4, 0.12, 0.23), Vector3(0, 0.88, 0), pants_m, 0.05)
	for x in [-0.26, 0.26]:
		var piv := Node3D.new()
		piv.position = Vector3(x, 1.4, 0)
		add_child(piv)
		MU.capsule(piv, 0.058, 0.5, Vector3(0, -0.22, 0), shirt_m)
		MU.sphere(piv, 0.05, Vector3(0, -0.52, 0), skin_m, Vector3(0.9, 1.2, 0.8))
		arms.append(MU.no_merge(piv))
	MU.cyl(self, 0.05, 0.1, Vector3(0, 1.5, 0), skin_m, Vector3.ZERO, 12)
	MU.sphere(self, 0.125, Vector3(0, 1.66, 0), skin_m, Vector3(1, 1.15, 1.02))
	if uniform.a > 0.0:
		# kurye şapkası
		MU.sphere(self, 0.135, Vector3(0, 1.73, -0.01), shirt_m, Vector3(1.04, 0.72, 1.04))
		MU.rbox(self, Vector3(0.2, 0.015, 0.12), Vector3(0, 1.74, 0.12), shirt_m, 0.006)
	else:
		MU.sphere(self, 0.13, Vector3(0, 1.72, -0.02), MU.mat(hair, 0, 0.8), Vector3(1.04, 0.8, 1.04))
	for x in [-0.125, 0.125]:
		MU.sphere(self, 0.025, Vector3(x, 1.65, 0), skin_m, Vector3(0.6, 1, 1))
	var eye_w := MU.mat(Color(0.95, 0.95, 0.95), 0, 0.3)
	var eye := MU.mat(Color(0.05, 0.05, 0.05), 0, 0.2)
	for x in [-0.045, 0.045]:
		MU.sphere(self, 0.02, Vector3(x, 1.68, 0.11), eye_w)
		MU.sphere(self, 0.011, Vector3(x, 1.68, 0.126), eye)
		MU.rbox(self, Vector3(0.04, 0.008, 0.01), Vector3(x, 1.715, 0.118), MU.mat(hair, 0, 0.8), 0.003)
	MU.sphere(self, 0.018, Vector3(0, 1.645, 0.128), skin_m, Vector3(0.8, 1.1, 1))
	MU.rbox(self, Vector3(0.05, 0.01, 0.01), Vector3(0, 1.6, 0.118), MU.mat(Color(0.55, 0.28, 0.25), 0, 0.5), 0.004)
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
