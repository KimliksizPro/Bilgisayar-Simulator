extends Node
## Geliştirici aracı: `-- --uishot` HUD, yönetim paneli ve gün sonu ekranı görüntüleri alır.

func _ready() -> void:
	var main = get_parent()
	var p = Game.player
	Game.save_path = "user://test_save.json"
	await get_tree().create_timer(1.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.3).timeout
	Game.clock = 14.42
	Game.rep = 4.0
	Game.change_rep(0.0)
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -22, "ui_counter0")
	Game.add_money(3000)
	for id in ["sign", "coffee", "cert", "wholesale"]:
		Game.buy_upgrade(id)
	Game.hud.pop_money(250)
	await _shot(p, Vector3(-0.8, 0, 0.5), 180, -18, "ui_counter1")
	await _shot(p, Vector3(2.0, 0, 1.2), -60, 5, "ui_cert")
	await _shot(p, Vector3(-2.2, 0, 1.0), 180, 10, "ui_sign")
	await _shot(p, Vector3(-2.6, 0, -0.9), 90, -15, "ui_shelf")
	Game.hud.open_upgrades()
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_upgrades")
	Game.hud.close_upgrades()
	Game.income_today = 640
	Game.parts_today = 215
	Game.jobs_today = 4
	Game.rep = 3.4
	Game.end_day()
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_summary")
	get_tree().quit()


func _shot(p, pos: Vector3, yaw: float, pitch: float, name: String) -> void:
	p.global_position = pos
	p.rotation_degrees.y = yaw
	p.cam.rotation_degrees.x = pitch
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/shot_%s.png" % name)
	print("shot ", name)
