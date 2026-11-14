extends RigidBody3D
## Alınıp takılabilen bilgisayar parçası.

const PM := preload("res://scripts/part_models.gd")
const MU := preload("res://scripts/mesh_util.gd")

var part_type := ""
var tier := 1
var broken := false
var paste_ok := true  # CPU için: termal macun sağlam mı
var display_name := ""
var slot = null
var rotors: Array = []
var rgb_mats: Array = []


func setup(type: String, t := 1, is_broken := false):
	part_type = type
	tier = t
	broken = is_broken
	display_name = PM.display_name(type, t)
	var built := PM.build(type, t)
	add_child(built.node)
	rotors = built.rotors
	rgb_mats = built.rgb
	var info: Dictionary = PM.INFO[type]
	MU.add_box_shape(self, info.size, info.center)
	if broken and (type == "psu" or type == "gpu") and randf() < 0.35:
		_burn_mark()
	mass = 0.5
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 2
	collision_mask = 1
	return self


func is_tool() -> bool:
	return false


## Elde tutulurken merkez ve dönüş (player.pick_up kullanır).
func hold_center() -> Vector3:
	return PM.INFO[part_type].center


func hold_euler() -> Vector3:
	return Vector3(15, -35, 0)


## Bazı bozuk parçalarda küçük yanık izi: ipucu ama her bozukta yok.
func _burn_mark() -> void:
	var dark := MU.mat(Color(0.03, 0.02, 0.02), 0, 0.9)
	var rim := MU.mat(Color(0.25, 0.14, 0.06), 0, 0.9)
	var p := Vector3(0.0766, -0.022, 0.035) if part_type == "psu" else Vector3(0.1085, -0.012, 0.072)
	var s := MU.sphere(self, 0.011, p, rim, Vector3(0.12, 1, 1.2))
	var d := MU.sphere(self, 0.007, p + Vector3(0.0004, 0, 0.001), dark, Vector3(0.12, 1, 1))
	s.name = "Burn"
	d.name = "BurnCore"


func get_hint(player) -> String:
	if slot:
		return slot.get_hint(player)
	if player.held == null:
		return "Al: %s  [E]" % display_name
	return ""


func interact(player) -> void:
	if slot:
		slot.interact(player)
	elif player.held == null:
		player.pick_up(self)


func install_into(s) -> void:
	slot = s
	freeze = true
	collision_layer = 2
	collision_mask = 0
	if get_parent():
		reparent(s, false)
	else:
		s.add_child(self)
	transform = Transform3D.IDENTITY


func value() -> int:
	return PM.price(part_type, tier)
