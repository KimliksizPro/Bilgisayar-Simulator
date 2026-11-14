extends Node
## Geliştirici aracı: `-- --menushot` ana menüyü (menü açık başlar) ve alt ekranlarını görüntüler.

const MENU := preload("res://scripts/menu.gd")


func _ready() -> void:
	var main = get_parent()
	# örnek kayıt: "Devam Et" düğmesi görünsün
	Game.save_path = "user://test_save.json"
	var f := FileAccess.open(Game.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"day": 4, "money": 1250, "rep": 3.4, "upgrades": [], "stats": {}}))
	f.close()
	if main.menu:
		main.menu.queue_free()
	await get_tree().process_frame
	main._start_menu()
	await get_tree().create_timer(3.0).timeout
	await _shot("ui_menu")
	var m = main.menu
	m._open_screen(m._settings)
	await get_tree().create_timer(0.6).timeout
	await _shot("ui_menu_settings")
	m._close_screen(m._settings)
	m._open_screen(m._credits[0], m._credits[1])
	await get_tree().create_timer(0.6).timeout
	await _shot("ui_menu_credits")
	m._close_screen(m._credits[0], m._credits[1])
	m._on_new()
	await get_tree().create_timer(0.6).timeout
	await _shot("ui_menu_confirm")
	DirAccess.remove_absolute(Game.save_path)
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/shot_%s.png" % name)
	print("shot ", name)
