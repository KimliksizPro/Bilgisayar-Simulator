extends Area3D
## Kasa içindeki parça yuvası (anakart, CPU, soğutucu, RAM, PCIe, depolama, fan, CMOS).

const PM := preload("res://scripts/part_models.gd")
const MU := preload("res://scripts/mesh_util.gd")

var accepts := ""
var accepts_extra: Array = []
var slot_index: int = 0
var part = null
var pc = null
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var bench_tint := Color(0, 0, 0, 0)  # tezgâh modu yuva ışığı (yeşil/kehribar/kırmızı); a = 0 kapalı

const GHOST_COL := Color(0.2, 0.9, 1.0, 0.25)
const GHOST_OK := Color(0.2, 0.95, 0.4, 0.28)
const GHOST_WARN := Color(1.0, 0.72, 0.15, 0.30)
const GHOST_BLOCK := Color(1.0, 0.2, 0.15, 0.30)


func setup(type: String, owner_pc, extra: Array = [], idx: int = 0):
	accepts = type
	accepts_extra = extra.duplicate()
	slot_index = idx
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


## Bu yuvanın kabul ettiği kategori mi (ana tür veya accepts_extra).
func accepts_category(cat: String) -> bool:
	return cat == accepts or accepts_extra.has(cat)


## Eldeki parçanın bu yuvaya uyumluluğunu denetler.
func compat_check(p) -> Dictionary:
	if p == null or pc == null:
		return {"ok": false, "reason": "Geçersiz parça", "code": "invalid_part", "severity": "block"}
	var pdef: PartDef = p.def() if p.has_method("def") else DB.parts.def_for(p.part_type, p.tier)
	return Compatibility.check(self, pdef, Compatibility.case_state_of(pc))


func _process(_delta: float) -> void:
	if _bench_glow():
		ghost.visible = true
		return
	var p = Game.player
	var lit: bool = part == null and p != null and p.held != null \
		and not p.held.is_tool() and accepts_category(p.held.part_type) and pc.panel_open
	if lit:
		var res := compat_check(p.held)
		var col := GHOST_OK
		if res.severity == "block":
			col = GHOST_BLOCK
		elif res.severity == "warn":
			col = GHOST_WARN
		_set_ghost_color(col)
	ghost.visible = lit


func _set_ghost_color(c: Color) -> void:
	if ghost_mat.albedo_color != c:
		ghost_mat.albedo_color = c
		ghost_mat.emission = Color(c.r, c.g, c.b)


## Tezgâh modunda yuva rengi: boş yuvada tint görünür, normal ipucu rengine döner.
func _bench_glow() -> bool:
	var on := bench_tint.a > 0.0 and part == null
	if on:
		_set_ghost_color(bench_tint)
	return on


func get_hint(player) -> String:
	if not pc.panel_open:
		return ""
	if player.held and player.held.is_tool():
		return pc.tool_hint(player.held, self)
	if part:
		if not part.seated:
			return "RAM tam oturmamış — yerine it  [E]"
		if player.held == null:
			var blk: String = str(pc.can_remove_reason(name)) if pc.has_method("can_remove_reason") else ""
			if blk != "":
				return "%s  (%s)" % [part.display_name, blk]
			return "Sök: %s  [E]" % part.display_name
		return part.display_name
	if player.held and not player.held.is_tool() and accepts_category(player.held.part_type):
		var res := compat_check(player.held)
		if res.severity == "block":
			return "Uyumsuz: %s" % res.reason
		if res.severity == "warn":
			return "Tak: %s  [E] (Uyarı: %s)" % [player.held.display_name, res.reason]
		return "Tak: %s  [E]" % player.held.display_name
	if accepts_extra.has("hdd"):
		return "Boş yuva: SSD / HDD"
	return "Boş yuva: %s" % PM.type_name(accepts)


func interact(player) -> void:
	if not pc.panel_open:
		return
	if player.held and player.held.is_tool():
		pc.tool_use(player, player.held, self)
		return
	if part and not part.seated:
		part.seated = true
		part.transform = Transform3D.IDENTITY
		Game.sfx.click()
		pc.on_parts_changed()
		Game.msg("RAM yuvaya tam oturtuldu!", Color(0.5, 1.0, 0.5))
		return
	if part and player.held == null:
		var blk: String = str(pc.can_remove_reason(name)) if pc.has_method("can_remove_reason") else ""
		if blk != "":
			Game.sfx.error()
			Game.msg(blk, Color(1.0, 0.75, 0.35))
			return
		if part.has_method("mark_pulled_from"):
			part.mark_pulled_from(pc)
		player.pick_up(part)
	elif part == null and player.held and not player.held.is_tool() and accepts_category(player.held.part_type):
		var res := compat_check(player.held)
		if res.severity == "block":
			Game.sfx.error()
			Game.msg(res.reason, Color(1.0, 0.35, 0.3))
			return
		if res.severity == "warn":
			Game.msg("Uyarı: " + res.reason, Color(1.0, 0.8, 0.3))
		install(player.release_held())
		Game.sfx.click()


func install(p) -> void:
	part = p
	p.install_into(self)
	if "seated" in p and not p.seated:
		p.position = Vector3(0.008, 0.0, 0.0)
		p.rotation_degrees = Vector3(0.0, 0.0, -7.0)
	if accepts == "cpu":
		pc.cpu_installed(p)
	if pc.has_method("on_slot_installed"):
		pc.on_slot_installed(name)
	pc.on_parts_changed()


func detach() -> void:
	if part:
		part.slot = null
		part = null
		if accepts == "cpu":
			pc.socket_paste = false
		pc.on_parts_changed()
