extends Node
## `-- --inventorytest`: kartlar, arama, stok/uyum filtreleri, alma/iade ve modal akışı.


func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	Game.new_game()
	var main = get_parent()
	var inv = main.inv_panel
	inv.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(inv.is_open() and Game.ui_modal, "envanter açılmadı")
	assert(inv._cards.size() == 34, "34 PC parça kartı olmalı")
	assert(inv._panel.size.y < 900, "envanter ekran dışına uzadı")
	inv._set_category("ram")
	for card in inv._cards.values():
		assert(card.panel.visible == (card.def.category == "ram"), "kategori filtresi")
	inv._search.text = "bulunmayan_parça"
	inv.refresh()
	assert(inv._empty_l.visible and inv._selected_sku == "" and inv._detail_orig.disabled, "boş sonuç durumu")
	inv._search.text = "DDR4"
	inv.refresh()
	assert(not inv._empty_l.visible, "teknik özelliğe göre arama")
	inv._search.text = ""
	inv._set_category("all")
	inv._stock_only = true
	inv.refresh()
	for card in inv._cards.values():
		assert(card.panel.visible == (int(card.count) > 0), "stok filtresi")
	var before := Game.stock_of_sku("ram_ddr4_8g")
	inv._select("ram_ddr4_8g")
	assert(not inv._detail_orig.disabled and inv._detail_cheap.disabled, "orijinal/muadil düğmeleri")
	inv._detail_orig.pressed.emit()
	assert(Game.player.held != null and Game.stock_of_sku("ram_ddr4_8g") == before - 1, "karttan orijinal alma")
	await get_tree().create_timer(0.2).timeout
	assert(not inv.is_open(), "parça alınca dolap kapanmalı")
	inv.open()
	assert(inv._return_btn.visible and inv._detail_orig.disabled, "elde parça varken iade ve alma kilidi")
	inv._return_btn.pressed.emit()
	assert(Game.player.held == null and Game.stock_of_sku("ram_ddr4_8g") == before, "karttan iade")
	Game.add_stock_cheap_sku("ram_ddr4_8g", 1)
	inv._select("ram_ddr4_8g")
	assert(not inv._detail_cheap.disabled, "muadil stok açılmadı")
	inv._detail_cheap.pressed.emit()
	assert(Game.player.held != null and Game.player.held.cheap, "karttan muadil alma")
	await get_tree().create_timer(0.2).timeout
	inv.open()
	inv._return_btn.pressed.emit()
	assert(Game.player.held == null and Game.stock_cheap_of_sku("ram_ddr4_8g") == 1, "muadil iade")
	inv.close()
	await get_tree().create_timer(0.2).timeout
	Game.job_mgr.dev_bench_job(Game.job_mgr._make_job_of("repair_gpu"))
	inv.open()
	assert(inv._compat_only_btn.visible, "tezgâh PC filtresi açılmadı")
	inv._stock_only = false
	inv._compat_only = true
	inv.refresh()
	for card in inv._cards.values():
		if card.panel.visible:
			assert(Compatibility.check_catalog_part(card.def, inv._bench_pc_state()).severity != "block", "uyumlu filtresinde uyumsuz parça")
	inv._search.grab_focus()
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().create_timer(0.2).timeout
	assert(inv._root.visible == false, "aramaya odaklıyken Esc dolabı kapatmadı")
	if DisplayServer.get_name() != "headless":
		assert(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "kapatınca fare oyuna dönmedi")
	print("INVENTORYTEST OK")
	get_tree().quit()
