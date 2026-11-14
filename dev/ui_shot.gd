extends Node
## Geliştirici aracı: `-- --uishot` HUD, ipucu/bildirim, yönetim paneli, gün sonu, duraklatma,
## ayarlar ve nasıl oynanır ekranlarının görüntülerini alır.

func _ready() -> void:
	var p = Game.player
	Game.save_path = "user://test_save.json"
	Settings.tips_seen = []
	await get_tree().create_timer(1.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.3).timeout
	Game.clock = 14.42
	Game.rep = 4.0
	Game.change_rep(0.0)
	Game.hud.set_job("Ahmet — 250 TL", "Arızalı parçayı bul ve değiştir.\n\nBitince müşteriyle konuş [E]")
	Game.hud.set_patience(0.62)
	Game.hud.tip("talk", "Müşteriyle konuşmak için ona bakıp E'ye bas.")
	Game.msg("Bir müşteri geldi!", Color(0.6, 0.9, 1.0))
	Game.msg("Tek kısa bip... Bilgisayar açıldı ama fanlar çok yüksek sesle dönüyor.", Color(1, 0.85, 0.5))
	Game.msg("+250 TL kazandın!  (hızlı servis, itibar arttı)", Color(0.5, 1, 0.5))
	Game.add_money(250)
	Game.hud.pop_money(250)
	await _shot(p, Vector3(0.3, 0, 0.55), 180, -34, "ui_hud", 0.9)
	await _shot(p, Vector3(2.0, 0, 1.2), -60, 5, "ui_cert")
	await _shot(p, Vector3(-2.6, 0, -0.9), 90, -15, "ui_shelf")
	Game.add_money(3000)
	for id in ["sign", "coffee"]:
		Game.buy_upgrade(id)
	Game.hud.open_upgrades()
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_upgrades")
	Game.hud.close_upgrades()
	Game.income_today = 640
	Game.parts_today = 215
	Game.jobs_today = 4
	Game.rep = 3.4
	Game.end_day()
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_summary")
	Game.hud.summary_btn.pressed.emit()
	await get_tree().create_timer(0.5).timeout
	Game.hud.open_pause()
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_pause")
	Game.hud.pause._open_screen(Game.hud.pause._settings)
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_settings_grafik")
	Game.hud.pause._settings._show_page(1)
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_settings_ses")
	Game.hud.pause._settings._show_page(2)
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_settings_kontrol")
	Game.hud.pause._close_screen(Game.hud.pause._settings)
	Game.hud.pause._open_screen(Game.hud.pause._howto)
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_howto")
	Game.hud.pause._howto._scroll.scroll_vertical = 460
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_howto2")
	Game.hud.pause._close_screen(Game.hud.pause._howto)
	Game.hud.pause.close()
	Game.hud._on_game_over({"day": 5, "money": -320})
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_over")
	get_tree().quit()


func _shot(p, pos: Vector3, yaw: float, pitch: float, name: String, wait := 0.7) -> void:
	p.global_position = pos
	p.rotation_degrees.y = yaw
	p.cam.rotation_degrees.x = pitch
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/shot_%s.png" % name)
	print("shot ", name)
