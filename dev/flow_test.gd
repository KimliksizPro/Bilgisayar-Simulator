extends Node
## Geliştirici testi: `godot --headless -- --flowtest` menü -> oyun -> duraklat -> ana menü akışını dener.

func _ready() -> void:
	var main = get_parent()
	Game.save_path = "user://test_save.json"
	if Game.has_meta("flow_stage"):
		# sahne yeniden yüklendi: ana menüde miyiz?
		await get_tree().create_timer(1.5).timeout
		assert(main.menu != null and not Game.started and not get_tree().paused, "ana menüye dönülmedi")
		print("OK ana menüye dönüş")
		DirAccess.remove_absolute(Game.save_path)
		print("AKIŞ TESTİ GEÇTİ")
		get_tree().quit()
		return
	await get_tree().create_timer(1.0).timeout
	assert(main.menu != null and not Game.started, "menü açık başlamalı")
	print("OK menü açıldı")
	main._begin_game(false)
	await get_tree().create_timer(2.5).timeout
	assert(Game.started and Game.phase == "day" and main.menu == null, "oyun başlamadı")
	print("OK oyun başladı")
	Game.running = true
	Game.hud.open_pause()
	await get_tree().create_timer(0.3).timeout
	assert(get_tree().paused and Game.paused and Game.ui_modal, "duraklatma")
	var c: float = Game.clock
	await get_tree().create_timer(1.0, true, false, true).timeout
	assert(is_equal_approx(Game.clock, c) and not Game.running, "saat duraklatmada ilerledi")
	print("OK duraklatma: saat durdu")
	Game.hud.pause.close()
	await get_tree().create_timer(0.3).timeout
	assert(not get_tree().paused and not Game.paused, "devam")
	print("OK devam")
	Settings.set_opt("quality", 0)
	Settings.set_opt("quality", 1)
	Settings.set_opt("quality", 2)
	Settings.set_opt("sfx", 0.5)
	assert(Settings.sfx == 0.5)
	print("OK ayarlar")
	Game.set_meta("flow_stage", 1)
	Game.return_to_menu()
