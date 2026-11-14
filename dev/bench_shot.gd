extends Node
## Geliştirici aracı: `godot --rendering-driver opengl3 -- --benchshot` tezgâh modunun ekran görüntülerini user:// altına kaydeder.

var main
var bench


func _shot(name: String) -> void:
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/bench_%s.png" % name)
	print("kaydedildi: bench_%s.png" % name)


func _screen_of(node: Node3D, off := Vector3.ZERO) -> Vector2:
	return bench.cam.unproject_position(node.global_transform * off)


func _ready() -> void:
	main = get_parent()
	bench = main.bench
	var jobs = main.get_children().filter(func(c): return c.has_method("_next_customer"))[0]
	var p = Game.player
	await get_tree().create_timer(1.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.new_game()
	p.global_position = Vector3(0.9, 0, -1.4)
	p.rotation_degrees.y = 0
	while jobs.state != "waiting":
		Game.clock = minf(Game.clock, 15.0)
		await get_tree().create_timer(0.2).timeout
	jobs.job = jobs._make_job_of("repair_ram")
	jobs._customer_talk(p)
	var pc = jobs.pc
	main._buy(p, "ram", 1)
	await get_tree().create_timer(0.3).timeout
	bench.enter()
	await get_tree().create_timer(0.6).timeout
	# 1) kapak kapalı, cam kapağın üstünde tooltip
	bench.mouse_override = _screen_of(pc, Vector3(0.108, 0.23, 0.0))
	await _shot("1_closed")
	bench.toggle_panel()
	await get_tree().create_timer(0.7).timeout
	# 2) açık, GPU üzerinde tooltip
	bench.mouse_override = _screen_of(pc.slots.gpu, Vector3(0.05, 0, 0))
	await _shot("2_open_hover")
	# 3) bozuk RAM söküldü, tepside
	var slot = pc.slots.ram1
	if pc.part_in("ram1") == null or not pc.part_in("ram1").broken:
		slot = pc.slots.ram2
	bench.remove_part(slot)
	bench.mouse_override = Vector2(900, 200)
	await _shot("3_tray")
	# 4) sağlam RAM seçili, boş RAM yuvasının üstünde (yeşil)
	bench.select_part(bench.tray_parts[0])
	bench.mouse_override = _screen_of(slot, Vector3(0.02, 0, 0))
	await _shot("4_ghost_green")
	# 5) CPU yuvasının üstünde (kırmızı)
	bench.mouse_override = _screen_of(pc.slots.cpu, Vector3(0.03, 0, 0))
	await _shot("5_ghost_red")
	# 6) imleç serbest, parça imleci izliyor
	bench.mouse_override = Vector2(700, 500)
	await _shot("6_ghost_free")
	bench.cancel_selection()
	# 7) termal macun aleti seçili
	var tools: Array = bench.available_tools()
	if not tools.is_empty():
		bench.select_tool(tools[0])
	bench.mouse_override = _screen_of(pc.slots.cpu, Vector3(0.03, 0, 0))
	await _shot("7_tool")
	bench.tool = null
	# 8) yakın plan yörünge (yaw döndür)
	bench._yaw_goal += 1.0
	bench._dist_goal = 0.5
	bench.mouse_override = Vector2(-1, -1)
	await get_tree().create_timer(0.6).timeout
	await _shot("8_orbit")
	bench.exit()
	await get_tree().create_timer(0.8).timeout
	await _shot("9_back_fp")
	# 10) laptop: ters çevrilmiş, alt kapak açık
	pc.visible = false
	Game.set_bench_device(null)
	var lj: Dictionary = jobs._make_job_of("device_laptop", "bat")
	var lap = load("res://scripts/laptop_device.gd").new()
	lap.transform = load("res://scripts/device_jobs.gd").spot(lap, jobs.pc_spot)
	main.add_child(lap)
	lap.monitor = jobs.monitor
	lap.fill(lj.parts)
	Game.set_bench_device(lap)
	await get_tree().create_timer(0.3).timeout
	bench.enter()
	await get_tree().create_timer(0.7).timeout
	bench.toggle_panel()
	await get_tree().create_timer(1.6).timeout
	bench.mouse_override = _screen_of(lap.slots.bat)
	await _shot("10_laptop")
	get_tree().quit()
