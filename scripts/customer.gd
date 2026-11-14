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


func build(hint_fn: Callable, action: Callable) -> void:
	var shirt := Color.from_hsv(randf(), randf_range(0.4, 0.8), randf_range(0.45, 0.85))
	var pants: Color = [Color(0.15, 0.2, 0.35), Color(0.12, 0.12, 0.13), Color(0.35, 0.28, 0.2)].pick_random()
	var skin: Color = [Color(0.95, 0.78, 0.64), Color(0.82, 0.62, 0.46), Color(0.6, 0.42, 0.3)].pick_random()
	var hair: Color = [Color(0.1, 0.07, 0.05), Color(0.35, 0.22, 0.1), Color(0.7, 0.7, 0.7), Color(0.85, 0.65, 0.3)].pick_random()
	var shirt_m := MU.mat(shirt, 0, 0.8)
	for x in [-0.1, 0.1]:
		var piv := Node3D.new()
		piv.position = Vector3(x, 0.88, 0)
		add_child(piv)
		MU.box(piv, Vector3(0.14, 0.84, 0.16), Vector3(0, -0.42, 0), MU.mat(pants, 0, 0.8))
		MU.box(piv, Vector3(0.15, 0.06, 0.24), Vector3(0, -0.85, 0.04), MU.mat(Color(0.1, 0.08, 0.07)))
		legs.append(piv)
	MU.box(self, Vector3(0.42, 0.6, 0.24), Vector3(0, 1.18, 0), shirt_m)
	for x in [-0.27, 0.27]:
		var piv := Node3D.new()
		piv.position = Vector3(x, 1.44, 0)
		add_child(piv)
		MU.box(piv, Vector3(0.11, 0.5, 0.13), Vector3(0, -0.25, 0), shirt_m)
		MU.box(piv, Vector3(0.09, 0.1, 0.1), Vector3(0, -0.55, 0), MU.mat(skin, 0, 0.7))
		arms.append(piv)
	MU.box(self, Vector3(0.12, 0.08, 0.12), Vector3(0, 1.51, 0), MU.mat(skin, 0, 0.7))
	MU.sphere(self, 0.14, Vector3(0, 1.66, 0), MU.mat(skin, 0, 0.7), Vector3(1, 1.08, 1))
	MU.sphere(self, 0.145, Vector3(0, 1.72, -0.015), MU.mat(hair, 0, 0.9), Vector3(1.02, 0.75, 1.02))
	var eye := MU.mat(Color(0.05, 0.05, 0.05))
	for x in [-0.05, 0.05]:
		MU.sphere(self, 0.018, Vector3(x, 1.68, 0.128), eye)
	MU.box(self, Vector3(0.06, 0.012, 0.01), Vector3(0, 1.6, 0.135), MU.mat(Color(0.5, 0.25, 0.2)))
	MU.interactable(self, Vector3(0.55, 1.8, 0.45), Vector3(0, 0.9, 0), hint_fn, action)
	speech = Label3D.new()
	speech.position = Vector3(0, 2.08, 0)
	speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	speech.font_size = 44
	speech.pixel_size = 0.0016
	speech.outline_size = 14
	speech.outline_modulate = Color(0, 0, 0, 0.85)
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech.width = 650
	add_child(speech)


func say(text: String) -> void:
	speech.text = text


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
