extends Area3D
## Kasa içindeki parça yuvası (CPU soketi, RAM yuvası, PCIe vb.).

const PM := preload("res://scripts/part_models.gd")
const MU := preload("res://scripts/mesh_util.gd")

var accepts := ""
var part = null
var pc = null
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var bench_tint := Color(0, 0, 0, 0)  # tezgâh modu yuva ışığı (yeşil/kırmızı); a = 0 kapalı
const GHOST_COL := Color(0.2, 0.9, 1.0, 0.25)


func setup(type: String, owner_pc):
	accepts = type
	pc = owner_pc
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	var info: Dictionary = PM.info(type)
	MU.add_box_shape(self, info.size * 1.08, info.center)
	var gm := MU.new_mat(GHOST_COL, 0, 0.5, 1.0)
	gm.no_depth_test = false
	ghost_mat = gm
	ghost = MU.box(self, info.size, info.center, gm)
	ghost.visible = false
	return self


func _process(_delta: float) -> void:
	var p = Game.player
	var lit: bool = part == null and p != null and p.held != null \
		and not p.held.is_tool() and p.held.part_type == accepts and pc.panel_open
	ghost.visible = lit or _bench_glow()


## Tezgâh modunda yuva rengi: boş yuvada tint görünür, normal ipucu rengine döner.
func _bench_glow() -> bool:
	var on := bench_tint.a > 0.0 and part == null
	var c := bench_tint if on else GHOST_COL
	if ghost_mat.albedo_color != c:
		ghost_mat.albedo_color = c
		ghost_mat.emission = Color(c.r, c.g, c.b)
	return on


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
	return "Boş yuva: %s" % PM.type_name(accepts)


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
