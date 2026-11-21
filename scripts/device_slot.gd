extends "res://scripts/slot.gd"
## Laptop / telefon yuvası. Kasa yuvasından farkı: açık olup olmadığını cihaz yuva yuva söyler
## (pc.slot_open). Kapalı yuva ve içindeki parça ışın almaz; arkadaki etkileşimleri kapatmasın.


func _process(_delta: float) -> void:
	var open: bool = pc.slot_open(self)
	collision_layer = 2 if open else 0
	if part and part.slot == self:
		part.collision_layer = 2 if open else 0
	var p = Game.player
	var lit: bool = open and part == null and p != null and p.held != null \
		and not p.held.is_tool() and p.held.part_type == accepts
	ghost.visible = lit or _bench_glow()


func get_hint(player) -> String:
	if not pc.slot_open(self):
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
	if not pc.slot_open(self):
		return
	if player.held and player.held.is_tool():
		pc.tool_use(player, player.held, self)
		return
	if part and player.held == null:
		if part.has_method("mark_pulled_from"):
			part.mark_pulled_from(pc)
		player.pick_up(part)
	elif part == null and player.held and player.held.part_type == accepts:
		install(player.release_held())
		Game.sfx.click()
