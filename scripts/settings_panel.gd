extends Control
## Ayarlar ekranı: Grafik / Ses / Kontroller / Oyun sekmeleri. Ana menü ve duraklatma menüsünde kullanılır.

const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")

signal back

var _root: Control
var _panel: Control
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _refreshers: Array[Callable] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := K.modal(self, 900, 0.62)
	_root = m[0]
	_panel = m[1]
	var vb: VBoxContainer = m[2]
	K.title(vb, "Ayarlar")
	# sekmeler
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	vb.add_child(tabs)
	var group := ButtonGroup.new()
	var names := ["Grafik", "Ses", "Kontroller", "Oyun"]
	for i in names.size():
		var b := K.button(tabs, names[i], func(): _show_page(i), "TabButton", 20, Vector2(0, 42))
		b.toggle_mode = true
		b.button_group = group
		_tabs.append(b)
	K.hsep(vb)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 410)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sc)
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(holder)
	for i in 4:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 14)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.visible = false
		holder.add_child(page)
		_pages.append(page)
	_build_graphics(_pages[0])
	_build_audio(_pages[1])
	_build_controls(_pages[2])
	_build_game(_pages[3])
	K.hsep(vb)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	vb.add_child(foot)
	K.button(foot, "Varsayılanlara Dön", func():
		Settings.reset_defaults()
		refresh(), "", 18, Vector2(0, 46))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	K.button(foot, "Geri", func(): back.emit(), "PrimaryButton", 20, Vector2(150, 46))
	Settings.changed.connect(func(_k): refresh())
	_show_page(0)


func is_open() -> bool:
	return _root != null and _root.visible


func open() -> void:
	refresh()
	_show_page(0)
	_tabs[0].button_pressed = true
	K.open(_root, _panel)
	_tabs[0].grab_focus()


func close() -> void:
	K.close(_root, _panel)


func _show_page(i: int) -> void:
	for j in _pages.size():
		_pages[j].visible = j == i
		if j < _tabs.size():
			_tabs[j].set_pressed_no_signal(j == i)


func refresh() -> void:
	for r in _refreshers:
		r.call()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		Game.sfx.ui_back()
		back.emit()
		get_viewport().set_input_as_handled()


# --- Satır yardımcıları ---
func _row(page: Control, text: String, desc := "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	page.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_theme_constant_override("separation", 0)
	h.add_child(left)
	K.label(left, text, 19, T.TEXT, "BoldLabel")
	if desc != "":
		var d := K.label(left, desc, 15, T.MUTED, "MutedLabel")
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(300, 0)
	return h


func _slider(page: Control, text: String, key: String, lo: float, hi: float, step: float, fmt: Callable, desc := "", test_sfx := false) -> HSlider:
	var h := _row(page, text, desc)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(400, 0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(box)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(290, 30)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	box.add_child(s)
	var v := K.label(box, "", 18, T.ACCENT_HI, "BoldLabel")
	v.custom_minimum_size = Vector2(64, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value = float(Settings.get(key))
	v.text = fmt.call(s.value)
	s.value_changed.connect(func(x: float):
		v.text = fmt.call(x)
		if absf(float(Settings.get(key)) - x) > 0.0001:
			Settings.set_opt(key, x))
	if test_sfx:
		s.drag_ended.connect(func(_c): Game.sfx.ui_click())
	_refreshers.append(func():
		s.set_value_no_signal(float(Settings.get(key)))
		v.text = fmt.call(s.value))
	return s


func _seg(page: Control, text: String, key: String, labels: Array, values: Array, desc := "") -> void:
	var h := _row(page, text, desc)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(box)
	var group := ButtonGroup.new()
	var btns: Array[Button] = []
	for i in labels.size():
		var b := K.button(box, labels[i], func(): Settings.set_opt(key, values[i]), "SegButton", 17, Vector2(0, 38))
		b.toggle_mode = true
		b.button_group = group
		btns.append(b)
	var sync := func():
		var cur = Settings.get(key)
		for i in btns.size():
			btns[i].set_pressed_no_signal(values[i] == cur)
	sync.call()
	_refreshers.append(sync)


func _toggle(page: Control, text: String, key: String, desc := "") -> void:
	var h := _row(page, text, desc)
	var cb := CheckButton.new()
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cb.focus_mode = Control.FOCUS_ALL
	cb.button_pressed = bool(Settings.get(key))
	cb.toggled.connect(func(on: bool):
		Game.sfx.ui_click()
		if bool(Settings.get(key)) != on:
			Settings.set_opt(key, on))
	cb.mouse_entered.connect(func(): Game.sfx.ui_hover())
	h.add_child(cb)
	_refreshers.append(func(): cb.set_pressed_no_signal(bool(Settings.get(key))))


func _pct(x: float) -> String:
	return "%d%%" % roundi(x * 100.0)


# --- Sayfalar ---
func _build_graphics(p: Control) -> void:
	_seg(p, "Grafik kalitesi", "quality", Settings.QUALITY_NAMES, [0, 1, 2],
		"Yüksek: SDFGI, SSIL, SSR, sis.  Orta: SSAO + SSR.  Düşük: hepsi kapalı.")
	_seg(p, "Pencere modu", "window_mode", Settings.WINDOW_NAMES, [0, 1, 2])
	_toggle(p, "Dikey senkron (VSync)", "vsync", "Görüntü yırtılmasını önler.")
	_seg(p, "FPS sınırı", "fps_cap", ["Sınırsız", "30", "60", "120", "144"], Settings.FPS_CAPS)
	_slider(p, "Çözünürlük ölçeği", "res_scale", 0.5, 1.0, 0.05, _pct, "3B görüntünün çözünürlüğü. Düşürmek akıcılığı artırır.")
	_toggle(p, "FSR 1.0 yükseltme", "fsr", "Ölçek %100'ün altındayken görüntüyü keskinleştirir.")
	_slider(p, "Görüş alanı (FOV)", "fov", 60.0, 100.0, 1.0, func(x): return "%d°" % int(x))


func _build_audio(p: Control) -> void:
	_slider(p, "Ana ses", "master", 0.0, 1.0, 0.05, _pct, "", true)
	_slider(p, "Efekt sesleri", "sfx", 0.0, 1.0, 0.05, _pct, "Tıklamalar, bip sesleri, kasa, fan.", true)
	_slider(p, "Müzik", "music", 0.0, 1.0, 0.05, _pct, "Dükkânın fon müziği.")


func _build_controls(p: Control) -> void:
	_slider(p, "Fare hassasiyeti", "sensitivity", 0.25, 3.0, 0.05, func(x): return "%.2fx" % x)
	_toggle(p, "Y eksenini ters çevir", "invert_y", "Fareyi yukarı itince aşağı bakar.")
	K.hsep(p)
	K.label(p, "Tuşlar", 22, T.ACCENT, "BoldLabel")
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 28)
	g.add_theme_constant_override("v_separation", 8)
	p.add_child(g)
	var keys := [["WASD", "Yürü"], ["Shift", "Koş"], ["E / Sol tık", "Etkileşim (al, tak, sök, konuş)"],
		["G / Sağ tık", "Elindekini bırak"], ["Esc", "Duraklat / menü"], ["F2", "Grafik kalitesini değiştir"], ["F3", "FPS sayacı"],
		["H", "Öğretici ipucunu gizle"]]
	for k in keys:
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(190, 0)
		g.add_child(cell)
		K.keycap(cell, k[0], 16)
		K.label(g, k[1], 18, T.MUTED, "MutedLabel")


func _build_game(p: Control) -> void:
	_toggle(p, "FPS sayacını göster", "show_fps", "Sol üstte FPS ve çizim sayısı (F3).")
	_toggle(p, "İpuçlarını göster", "show_hints", "İlk günlerde kısa öğretici ipuçları çıkar.")
	var h := _row(p, "Öğretici ipuçları", "Daha önce gördüğün ipuçları bir daha çıkmaz.")
	K.button(h, "İpuçlarını sıfırla", func():
		Settings.reset_tips()
		Game.msg("İpuçları sıfırlandı.", Color(0.6, 0.9, 1.0)), "", 17, Vector2(0, 40))
