extends Node
## `-- --inventoryshot`: dolap ekranını, kategori / iade / boş sonuç hâllerini çeker.


func _ready() -> void:
	# Pencere yöneticisinden bağımsız, tekrar üretilebilir UI çözünürlüğü.
	get_viewport().content_scale_size = Vector2i(1600, 900)
	get_viewport().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_viewport().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await get_tree().create_timer(0.5).timeout
	Game.new_game()
	Game.hud.visible = false
	var p = Game.player
	p.global_position = Vector3(-1.65, 0, 0.15)
	p.rotation_degrees.y = 65
	p.cam.rotation_degrees.x = -8
	var inv = get_parent().inv_panel
	inv.open()
	await get_tree().create_timer(3.5).timeout
	await _shot("inventory_all")
	inv._set_category("gpu")
	inv._select("gpu_gamer_12g")
	await _shot("inventory_gpu")
	inv._set_category("all")
	inv._stock_only = true
	inv.refresh()
	await _shot("inventory_stock")
	get_parent()._on_cabinet_pick("ram_ddr4_8g", false)
	inv.refresh()
	await _shot("inventory_held")
	get_parent()._on_cabinet_return()
	inv._search.text = "bulunmayan_parça"
	inv.refresh()
	await _shot("inventory_empty")
	inv._search.text = ""
	inv._stock_only = false
	inv._set_category("all")
	get_viewport().content_scale_size = Vector2i(1100, 800)
	await _shot("inventory_compact")
	inv.close()
	get_tree().quit()


func _shot(name: String) -> void:
	await get_tree().create_timer(0.5).timeout
	var inv = get_parent().inv_panel
	assert(inv._panel.size.y < 900, "envanter yüksekliği ekran dışına uzadı")
	assert(inv._panel.position.x >= 0 and inv._panel.position.y >= 0, "envanter ekran dışında")
	var rect: Rect2 = inv._panel.get_global_rect()
	assert(rect.end.x <= inv._root.size.x + 1 and rect.end.y <= inv._root.size.y + 1, "envanter ekrana sığmıyor")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/shot_%s.png" % name)
	print("shot ", name)
