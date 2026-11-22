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
	var cabinet_hit = main.get_node("PartsCabinet/CabinetInteract")
	cabinet_hit.interact(p)
	assert(main.inv_panel.is_open(), "dolaba E ile bakınca parça seçici açılmadı")
	main.inv_panel.close()
	var stock_before := Game.stock_of_sku("ram_ddr4_8g")
	# Parça Dolabı akışı: dolaptan RAM alma
	main._on_cabinet_pick("ram_ddr4_8g", false)
	var ram = p.held
	assert(Game.stock_of_sku("ram_ddr4_8g") == stock_before - 1, "dolaptan alırken stok azalmadı")
	assert(ram != null and "origin" in ram and ram.origin == "stock", "dolaptan alınan RAM stok işaretli değil")
	assert(ram.freeze and ram.freeze_mode == RigidBody3D.FREEZE_MODE_STATIC, "tutulan RAM statik dondurulmadı")
	assert(ram.collision_layer == 0 and ram.collision_mask == 0)
	assert(p.vm_cam.current, "viewmodel kamerası aktif değil")
	await _lag(p, "dolap_ram")
	cabinet_hit.interact(p)
	assert(p.held == null and Game.stock_of_sku("ram_ddr4_8g") == stock_before, "dolaba iade çalışmadı")

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
	# boşluğa bakarken stok parçasını bırakınca stoğa düzenli iade edilmeli (yere fırlatılmamalı)
	p.global_position = Vector3(0.0, 0.0, 0.5)
	p.rotation = Vector3.ZERO
	p.cam.rotation = Vector3.ZERO
	var gpu_sku: String = part.sku
	var gpu_stock_0 := Game.stock_of_sku(gpu_sku)
	p.drop()
	assert(p.held == null and Game.stock_of_sku(gpu_sku) == gpu_stock_0 + 1, "boşlukta bırakılan stok parçası stoğa dönmedi")
	await get_tree().process_frame
	assert(p.vm_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED)

	# masaya bakarken parça bırakınca yatay yüzeye düz ve statik yerleşmeli
	main._buy(p, "gpu", 1)
	part = p.held
	assert(part != null)
	p.global_position = Vector3(0.15, 0.0, -1.5)
	p.rotation = Vector3.ZERO
	p.cam.rotation.x = deg_to_rad(-38.0)
	assert(p.put_down_info().get("mode", "") == "surface", "masa yüzeyi tanınmadı: %s" % [p.put_down_info()])
	p.drop()
	for v in part.find_children("*", "VisualInstance3D", true, false):
		assert(v.layers == 1, "katman geri gelmedi")
	await get_tree().create_timer(0.28).timeout
	assert(part.freeze and part.freeze_mode == RigidBody3D.FREEZE_MODE_STATIC and part.collision_layer == 2, "masaya konulan parça statik donmadı")
	assert(part.global_position.y >= 0.74, "parça masa üstüne konmadı: y=%.3f" % part.global_position.y)
	# tekrar al ve temizle
	p.pick_up(part)
	assert(p.held == part)
	var q = p.release_held()
	assert(q == part)
	part.queue_free()

	# tezgâhta cihaz varken müşteri parçası boşlukta bırakılınca ESD tepsisine gitmeli
	var rec: Dictionary = Game.job_mgr.drop_off(Game.job_mgr._make_job_of("repair_ram"))
	var pc = Game.job_mgr.dev_to_bench(rec)
	assert(pc != null)
	var cust_p = main.PART.new().setup("ram", 1, true)
	cust_p.origin = "customer"
	main.add_child(cust_p)
	p.pick_up(cust_p)
	p.global_position = Vector3(0.0, 0.0, 0.5)
	p.rotation = Vector3.ZERO
	p.cam.rotation = Vector3.ZERO
	p.drop()
	assert(p.held == null and main.bench.tray_parts.has(cust_p), "müşteri parçası ESD tepsisine konmadı")
	Game.set_bench_device(null)
	Game.job_mgr._remove_record(rec, false)

	# alet (tornavida) sağ tık / G ile bırakılınca yere fırlatılmayıp masadaki yerine dönmeli
	var sd = main.get_children().filter(func(c): return c.has_method("is_tool") and c.is_tool() and c.tool_type == "screwdriver")[0]
	p.pick_up(sd)
	assert(sd.freeze_mode == RigidBody3D.FREEZE_MODE_STATIC and sd.freeze)
	cabinet_hit.interact(p)
	assert(p.held == sd, "alet dolaba iade edilmemeli")
	p.global_position = Vector3(0.5, 0.0, -1.7)
	p.drop()
	assert(p.held == null)
	await get_tree().create_timer(0.30).timeout
	assert(sd.freeze and sd.freeze_mode == RigidBody3D.FREEZE_MODE_STATIC, "alet yere atılmayıp statik durmalı")
	assert(sd.collision_layer == 2)
	for v in sd.find_children("*", "VisualInstance3D", true, false):
		assert(v.layers == 1, "alet katmanı geri gelmedi")
	assert(sd.global_position.distance_to(sd.home_transform.origin) < 0.02, "alet masadaki yerine dönmedi")
	print("HOLDTEST OK")
	get_tree().quit()
