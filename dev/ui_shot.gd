extends Node
## Geliştirici aracı: `-- --uishot` HUD, ipucu/bildirim, yönetim paneli, gün sonu, duraklatma,
## ayarlar ve nasıl oynanır ekranlarının görüntülerini alır.

func _ready() -> void:
	if "--devshot" in OS.get_cmdline_user_args():  # laptop / telefon görüntüleri
		await load("res://dev/device_shot.gd").run(self)
		return
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
	# ParçaNet: sepette ürünler
	Game.market_prev = 1.0
	Game.market = 1.06
	Game.hud.open_upgrades(0)
	var o = Game.hud.office
	o._cart = {"gpu:2": 1, "ram:2": 5, "ssd:1": 2}
	o._express = true
	o.refresh()
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_shop")
	# muadil kalite seçimi + ikinci el sekmesi (eco_* görüntüleri)
	o._cheap = true
	o._cart["cpu:1:c"] = 2
	o.refresh()
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "eco_shop")
	o._cheap = false
	o._show_page(4)
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "eco_used")
	o._show_page(0)
	o._order()
	Game.place_order({"cpu:1": 2}, false)
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_cargo")
	o._show_page(2)
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_upgrades")
	o._show_page(3)
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_stats")
	# PERSONEL: bir tezgahtar + bir teknisyen işe al, sekmeyi ve dükkândaki hâllerini çek
	Game.roll_staff_candidates()
	Game.hire_staff(int(Game.staff_candidates[0].id))
	Game.hire_staff(int(Game.staff_candidates[0].id))
	o._show_page(4)
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "staff_tab")
	Game.hud.close_upgrades()
	var sm = Game.staff_mgr
	for e in sm.npcs.values():
		e.position = e.home
		e.waypoints = []
		sm._go_idle(e)
		e.rotation.y = e.home_face
	sm.npcs.values()[0].say_for("Hoş geldiniz! Bilgisayarı hemen ustamın masasına alıyorum.", 10.0)
	sm.npcs.values()[1].say_for("Tamir ediliyor... %45", 10.0)
	await _shot(p, Vector3(-1.9, 0, 2.6), -12, -12, "staff_shop", 1.0)
	await _shot(p, Vector3(0.6, 0, 0.2), 50, -14, "staff_back", 0.6)
	Game.fire_staff(int(Game.staff[0].id))
	Game.fire_staff(int(Game.staff[0].id))
	# kurye koliyi bırakır
	Game.clock += 0.6
	get_parent().delivery._send_courier()
	await get_tree().create_timer(4.5).timeout
	await _shot(p, Vector3(0.2, 0, 0.6), 160, -22, "ui_delivery", 0.3)
	await _shot(p, Vector3(-2.7, 0, -0.3), 90, -12, "ui_stockshelf", 0.3)
	Game.income_today = 640
	Game.parts_today = 215
	Game.jobs_today = 4
	Game.rep = 3.4
	Game.warranty_list.append({"due": Game.day + 1, "name": "Ahmet Abi", "type": "psu", "tier": 1})
	Game.end_day()
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "ui_summary")
	await _shot(p, Vector3(-0.2, 0, 0.5), 180, -10, "eco_zreport", 0.2)
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
