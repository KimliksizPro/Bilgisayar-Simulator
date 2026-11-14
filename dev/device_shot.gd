extends RefCounted
## Geliştirici aracı: `-- --uishot --devshot` laptop, telefon ve mobil parça rafı görüntüleri (shot_dev_*.png).

const DJ := preload("res://scripts/device_jobs.gd")


static func run(shot) -> void:
	var main = shot.get_parent()
	var jobs = Game.job_mgr
	var p = Game.player
	Game.save_path = "user://test_save_dev.json"
	Settings.tips_seen = []
	await shot.get_tree().create_timer(1.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.new_game()
	await shot.get_tree().create_timer(0.3).timeout
	jobs.arrivals_enabled = false  # müşteri gelmesin
	p.cam.fov = 40.0  # yakın çekim
	var lap = _device(main, jobs, "laptop", "scr")
	await shot._shot(p, Vector3(0.45, 0, -1.8), 0, -42, "dev_laptop_cracked", 0.8)
	if "--rackonly" in OS.get_cmdline_user_args():
		p.cam.fov = Settings.fov
		await shot._shot(p, Vector3(-2.35, 0, -1.75), 0, -18, "dev_rack", 0.5)
		shot.get_tree().quit()
		return
	lap.power_button()
	await shot._shot(p, Vector3(0.45, 0, -1.8), 0, -42, "dev_laptop_glitch", 0.8)
	lap.queue_free()
	lap = _device(main, jobs, "laptop", "ram")
	lap.power_button()
	await shot._shot(p, Vector3(0.45, 0, -1.8), 0, -42, "dev_laptop_bsod", 2.0)
	lap.power_off()
	lap.queue_free()
	lap = _device(main, jobs, "laptop", "bat")
	lap.toggle_panel()
	await shot._shot(p, Vector3(0.35, 0, -1.85), 0, -55, "dev_laptop_open", 2.2)
	await shot._shot(p, Vector3(0.0, 0, -2.1), -20, -62, "dev_laptop_open2", 0.3)
	lap.toggle_panel()
	await shot._shot(p, Vector3(0.45, 0, -1.8), 0, -42, "dev_laptop_closed", 2.0)
	lap.queue_free()
	p.cam.fov = 22.0
	var ph = _device(main, jobs, "phone", "bat")
	await shot._shot(p, Vector3(0.45, 0, -1.95), 0, -54, "dev_phone_swollen", 0.6)
	ph.queue_free()
	ph = _device(main, jobs, "phone", "port")
	ph.power_button()
	await shot._shot(p, Vector3(0.45, 0, -1.95), 0, -54, "dev_phone_port", 1.6)
	ph.power_off()
	ph.toggle_panel()
	await shot._shot(p, Vector3(0.42, 0, -1.95), 4, -54, "dev_phone_open", 1.0)
	ph.queue_free()
	ph = _device(main, jobs, "phone", "scr")
	await shot._shot(p, Vector3(0.45, 0, -1.95), 0, -54, "dev_phone_cracked", 0.6)
	ph.queue_free()
	p.cam.fov = Settings.fov
	await shot._shot(p, Vector3(-2.35, 0, -1.75), 0, -18, "dev_rack", 0.5)
	Game.hud.open_upgrades(0)
	await shot._shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "dev_shop", 0.7)
	Game.hud.office._show_page(0)
	await shot.get_tree().create_timer(0.2).timeout
	for sc in Game.hud.office.find_children("*", "ScrollContainer", true, false):
		sc.scroll_vertical = 1000
	await shot._shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "dev_shop2", 0.5)
	Game.hud.close_upgrades()
	DirAccess.remove_absolute(Game.save_path)
	shot.get_tree().quit()


static func _device(main, jobs, dev: String, broken: String):
	var j := DJ.make({"name": "Test"}, dev)
	while j.broken != broken:
		j = DJ.make({"name": "Test"}, dev)
	var d = DJ.new_device(j)
	d.transform = DJ.spot(d, jobs.pc_spot)
	main.add_child(d)
	d.fill(j.parts)
	return d
