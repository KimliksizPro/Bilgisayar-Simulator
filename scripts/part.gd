extends RigidBody3D
## Alınıp takılabilen bilgisayar parçası.

const PM := preload("res://scripts/part_models.gd")
const MU := preload("res://scripts/mesh_util.gd")

var part_type := ""
var tier := 1
var broken := false
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
	mass = 0.5
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 2
	collision_mask = 1
	return self


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
