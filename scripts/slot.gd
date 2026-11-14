extends Area3D
## Kasa içindeki parça yuvası (CPU soketi, RAM yuvası, PCIe vb.).

const PM := preload("res://scripts/part_models.gd")
const MU := preload("res://scripts/mesh_util.gd")

var accepts := ""
var part = null
var pc = null
var ghost: MeshInstance3D


func setup(type: String, owner_pc):
	accepts = type
	pc = owner_pc
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	var info: Dictionary = PM.INFO[type]
	MU.add_box_shape(self, info.size * 1.08, info.center)
	var gm := MU.new_mat(Color(0.2, 0.9, 1.0, 0.25), 0, 0.5, 1.0)
	gm.no_depth_test = false
	ghost = MU.box(self, info.size, info.center, gm)
	ghost.visible = false
	return self


func _process(_delta: float) -> void:
	var p = Game.player
	ghost.visible = part == null and p != null and p.held != null \
		and not p.held.is_tool() and p.held.part_type == accepts and pc.panel_open


func get_hint(player) -> String:
	if not pc.panel_open:
		return ""
	if player.held and player.held.is_tool():
		return pc.tool_hint(player.held, self)
	if part:
		if player.held == null:
			return "Sök: %s  [E]" % part.display_name
		return part.display_name
	if player.held and player.held.part_type == accepts:
		return "Tak: %s  [E]" % player.held.display_name
	return "Boş yuva: %s" % PM.TYPE_NAMES[accepts]


func interact(player) -> void:
	if not pc.panel_open:
		return
	if player.held and player.held.is_tool():
		pc.tool_use(player, player.held, self)
		return
	if part and player.held == null:
		player.pick_up(part)
	elif part == null and player.held and player.held.part_type == accepts:
		install(player.release_held())
		Game.sfx.click()


func install(p) -> void:
	part = p
	p.install_into(self)
	if accepts == "cpu":
		pc.cpu_installed(p)
	pc.on_parts_changed()


func detach() -> void:
	if part:
		part.slot = null
		part = null
		if accepts == "cpu":
			pc.socket_paste = false
		pc.on_parts_changed()
