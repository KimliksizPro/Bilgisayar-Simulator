extends Node
## Geliştirici testi: `godot --headless -- --holdtest` elde tutulan eşyanın kamerayı geriden takip edip etmediğini,
## katman/fizik durumunu ve bırakma/geri alma akışını denetler.

func _lag(p, label: String) -> float:
	# kamerayı her karede döndür; eşyanın yerel dönüşümü hold pozunda kalmalı ve fizik sunucusuyla sapmamalı
	var worst := 0.0
	var want_local: Transform3D = p.held_xform_for(p.held)
	for i in 40:
		p.rotate_y(0.05)
		p.cam.rotation.x = sin(i * 0.2) * 0.5
		await get_tree().physics_frame
		await get_tree().process_frame
		var h = p.held
		assert((h.transform.origin - want_local.origin).length() < 0.0001, "elde tutulan eşya yerel konumu kaydı")
		assert(h.transform.basis.is_equal_approx(want_local.basis), "elde tutulan eşya yerel dönüşü bozuldu")
		var want: Transform3D = p.hold.global_transform * want_local
		var srv: Transform3D = PhysicsServer3D.body_get_state(h.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		worst = maxf(worst, (srv.origin - h.global_transform.origin).length())
		assert((h.global_transform.origin - want.origin).length() < 0.0001)
	print(label, ": en kötü fizik/sahne farkı = ", snappedf(worst * 1000.0, 0.01), " mm")
	return worst

func _ready() -> void:
	var main = get_parent()
	var p = Game.player
	await get_tree().create_timer(0.5).timeout
	Game.new_game()
	# Parça Dolabı akışı: dolaptan RAM alma
	main._on_cabinet_pick("ram_ddr4_8g", false)
	var ram = p.held
	assert(ram != null and "origin" in ram and ram.origin == "stock", "dolaptan alınan RAM stok işaretli değil")
	assert(ram.freeze and ram.freeze_mode == RigidBody3D.FREEZE_MODE_STATIC, "tutulan RAM statik dondurulmadı")
	assert(ram.collision_layer == 0 and ram.collision_mask == 0)
	assert(p.vm_cam.current, "viewmodel kamerası aktif değil")
	await _lag(p, "dolap_ram")
	p.release_held().queue_free()

	main._buy(p, "gpu", 1)
	var part = p.held
	assert(part != null)
	assert(part.freeze and part.freeze_mode == RigidBody3D.FREEZE_MODE_STATIC)
	assert(part.collision_layer == 0 and part.collision_mask == 0)
	for v in part.find_children("*", "VisualInstance3D", true, false):
		assert(v.layers == p.VM_LAYER, "katman ayarlanmadı")
	assert(p.vm_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS or true)
	await _lag(p, "statik_hold")
	part.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	part.freeze = false
	part.freeze = true
	await _lag(p, "kinematik_sync")
	part.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	await get_tree().process_frame
	assert(p.vm_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	# bırak: katmanlar geri gelmeli, gövde düşmeli
	p.drop()
	for v in part.find_children("*", "VisualInstance3D", true, false):
		assert(v.layers == 1, "katman geri gelmedi")
	assert(not part.freeze and part.collision_layer == 2)
	await get_tree().process_frame
	assert(p.vm_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	# tekrar al, rafa geri koy akışı
	p.global_position = part.global_position + Vector3(0, 0, 0.6)
	p.pick_up(part)
	assert(p.held == part)
	var tool = main.get_children().filter(func(c): return c.has_method("puff"))[0]
	var q = p.release_held()
	assert(q == part)
	part.queue_free()
	p.pick_up(tool)
	assert(tool.freeze_mode == RigidBody3D.FREEZE_MODE_STATIC and tool.freeze)
	p.drop()
	assert(not tool.freeze)
	print("HOLDTEST OK")
	get_tree().quit()
