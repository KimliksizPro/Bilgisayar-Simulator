extends Node
## Geliştirici aracı: `-- --jobshot` Bekleyen İşler rafının, cihaz taşımanın ve HUD iş listesinin görüntülerini alır (shot_jobs_*.png).


func _ready() -> void:
	var p = Game.player
	Game.save_path = "user://test_save_jobshot.json"
	Settings.tips_seen = []
	await get_tree().create_timer(1.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var jobs = Game.job_mgr
	jobs.arrivals_enabled = false
	jobs.force_express = 0
	Game.new_game()
	await get_tree().create_timer(0.3).timeout
	Game.clock = 14.0
	Game.rep = 4.0
	for id in ["repair_gpu", "device_laptop", "device_phone", "repair_psu"]:
		var rec: Dictionary = jobs.drop_off(jobs._make_job_of(id))
		if rec.is_empty():
			continue
	Game.hud.tip("ticket", "İş rafa kondu. Sağ duvardaki Bekleyen İşler rafında cihazın fişine bakıp E'ye bas.")
	# 1. iş hazır (yeşil), 2. iş gecikmiş (kırmızı)
	var r1: Dictionary = Game.jobs_active[0]
	r1.status = "ready"
	Game.jobs_active[1].due_abs = Game.now_abs() - 2.0
	# 3. iş tezgâhta
	jobs.dev_to_bench(Game.jobs_active[2])
	await _shot(p, Vector3(2.0, 0, -0.45), -90, -8, "jobs_rack", 1.0)
	await _shot(p, Vector3(2.6, 0, -0.1), -75, -22, "jobs_rack_close", 0.5)
	await _shot(p, Vector3(1.0, 0, -0.6), -100, -12, "jobs_overview", 0.5)
	# tezgâh
	await _shot(p, Vector3(0.45, 0, -1.7), 0, -30, "jobs_bench", 0.5)
	# taşıma
	jobs.pick_up_device(Game.jobs_active[0], p)
	await _shot(p, Vector3(2.0, 0, -0.45), -90, -15, "jobs_carry_pc", 0.8)
	jobs.return_carried()
	await get_tree().create_timer(0.5).timeout
	jobs.pick_up_device(Game.jobs_active[1], p)
	await _shot(p, Vector3(2.0, 0, -0.45), -90, -15, "jobs_carry_laptop", 0.8)
	jobs.return_carried()
	await get_tree().create_timer(0.5).timeout
	# müşteri sırası
	jobs.force_jobs = [jobs._make_job_of("repair_cpu"), jobs._make_job_of("repair_ram")]
	jobs._enqueue("pickup", Game.jobs_active[0], Game.jobs_active[0])
	jobs._spawn_arrival()
	await get_tree().create_timer(9.0).timeout
	await _shot(p, Vector3(-0.3, 0, 0.45), 180, -8, "jobs_queue", 0.3)
	await _shot(p, Vector3(0.3, 0, 0.6), 160, -30, "jobs_hud", 0.3)
	DirAccess.remove_absolute(Game.save_path)
	get_tree().quit()


func _shot(p, pos: Vector3, yaw: float, pitch: float, name: String, wait := 0.7) -> void:
	p.global_position = pos
	p.rotation_degrees.y = yaw
	p.cam.rotation_degrees.x = pitch
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/shot_%s.png" % name)
	print("shot ", name)
