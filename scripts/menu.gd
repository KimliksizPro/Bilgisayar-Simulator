extends CanvasLayer
## Ana menü: gerçek dükkânın üzerinde, solda başlık ve düğmeler. Yeni oyun / devam / ayarlar / yardım / emeği geçenler / çıkış.

const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")
const SETTINGS := preload("res://scripts/settings_panel.gd")
const HOWTO := preload("res://scripts/howto_panel.gd")

signal start_game(continue_game: bool)

const SHADER := """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV;
	float left = smoothstep(0.78, 0.0, uv.x);
	float vig = smoothstep(0.45, 1.05, length((uv - 0.5) * vec2(1.25, 1.0)));
	float bottom = smoothstep(0.7, 1.0, uv.y) * 0.45;
	float a = clamp(left * 0.94 + vig * 0.5 + bottom, 0.0, 0.97);
	COLOR = vec4(vec3(0.03, 0.045, 0.1), a);
}
"""

var _root: Control
var _column: VBoxContainer
var _buttons: Array[Button] = []
var _settings: Control
var _howto: Control
var _credits: Array
var _confirm: Array
var _busy := false
var _last_btn: Button


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	bg.material = mat
	_root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)
	_column = VBoxContainer.new()
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_column.custom_minimum_size = Vector2(580, 0)
	_column.add_theme_constant_override("separation", 12)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_column)

	# --- başlık ---
	var tag := HBoxContainer.new()
	tag.add_theme_constant_override("separation", 12)
	_column.add_child(tag)
	var bar := ColorRect.new()
	bar.color = T.ACCENT
	bar.custom_minimum_size = Vector2(40, 4)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_child(bar)
	K.label(tag, "MAHALLE TAMİRHANESİ", 17, T.ACCENT, "SmallCaps").add_theme_color_override("font_color", T.ACCENT)
	var t1 := K.label(_column, "BİLGİSAYARCI", 76, Color.WHITE, "TitleLabel")
	var t2 := K.label(_column, "SİMÜLATÖR", 76, T.ACCENT, "TitleLabel")
	for t in [t1, t2]:
		t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		t.add_theme_constant_override("shadow_offset_x", 0)
		t.add_theme_constant_override("shadow_offset_y", 5)
		t.add_theme_constant_override("line_spacing", -12)
	_column.add_child(_gap(0))
	var sub := K.label(_column, "Mahallenin bilgisayarcısı sensin. Müşterinin derdini dinle,\narızayı bul, parçayı değiştir, parayı kap!", 20, T.MUTED, "MutedLabel")
	sub.custom_minimum_size = Vector2(540, 0)
	_column.add_child(_gap(18))

	# --- düğmeler ---
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 10)
	holder.custom_minimum_size = Vector2(400, 0)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(holder)
	var save := Game.peek_save()
	if not save.is_empty():
		var b := _menu_button(holder, "Devam Et", _on_continue)
		var info := K.label(b, "Gün %d  ·  %s TL" % [save.day, K.money(save.money)], 16, T.MUTED, "MutedLabel")
		info.set_anchors_preset(Control.PRESET_FULL_RECT)
		info.offset_right = -22
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_button(holder, "Yeni Oyun", _on_new)
	_menu_button(holder, "Ayarlar", func(): _open_screen(_settings))
	_menu_button(holder, "Nasıl Oynanır", func(): _open_screen(_howto))
	_menu_button(holder, "Emeği Geçenler", func(): _open_screen(_credits[0], _credits[1]))
	_menu_button(holder, "Çıkış", func(): get_tree().quit(), "DangerButton")

	# --- alt bilgi ---
	var ver := K.label(_root, "v1.0  ·  Godot 4.4  ·  GDScript", 15, Color(1, 1, 1, 0.4), "MutedLabel")
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(96, -40)
	var nav := K.label(_root, "Yön tuşları / fare: gezin   ·   Enter: seç", 15, Color(1, 1, 1, 0.4), "MutedLabel")
	nav.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	nav.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	nav.position = Vector2(-40, -40)

	# --- alt ekranlar ---
	_settings = SETTINGS.new()
	_settings.back.connect(func(): _close_screen(_settings))
	add_child(_settings)
	_howto = HOWTO.new()
	_howto.back.connect(func(): _close_screen(_howto))
	add_child(_howto)
	_build_credits()
	_build_confirm()

	if _buttons.size() > 0:
		_buttons[0].grab_focus()
	_intro()


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _menu_button(parent: Control, text: String, cb: Callable, variation := "BigMenuButton") -> Button:
	var b := K.button(parent, text, cb, variation, 24, Vector2(0, 56))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_buttons.append(b)
	return b


## Giriş animasyonu: öğeler soldan kayarak belirir.
func _intro() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var items: Array = _column.get_children().slice(0, 5)
	items.append_array(_buttons)
	var i := 0
	for c in items:
		if not is_instance_valid(c) or not c is Control:
			continue
		var target: float = c.position.x
		c.position.x = target - 60.0
		c.modulate.a = 0.0
		var tw: Tween = c.create_tween().set_parallel(true)
		tw.tween_property(c, "position:x", target, 0.5).set_delay(0.08 * i).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate:a", 1.0, 0.4).set_delay(0.08 * i)
		i += 1


func _set_main_focusable(on: bool) -> void:
	for b in _buttons:
		b.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE


func _open_screen(screen, pnl = null) -> void:
	_last_btn = get_viewport().gui_get_focus_owner() as Button
	_set_main_focusable(false)
	if screen is Control and screen.has_method("open"):
		screen.open()
	else:
		K.open(screen, pnl)
		K.focus_first(screen)


func _close_screen(screen, pnl = null) -> void:
	if screen is Control and screen.has_method("close"):
		screen.close()
	else:
		K.close(screen, pnl)
	_set_main_focusable(true)
	if _last_btn and is_instance_valid(_last_btn):
		_last_btn.grab_focus()


func _on_continue() -> void:
	if _busy:
		return
	_busy = true
	start_game.emit(true)


func _on_new() -> void:
	if _busy:
		return
	if Game.has_save():
		var s := Game.peek_save()
		(_confirm[3] as Label).text = "Kayıtlı oyunun (Gün %d, %s TL) silinecek ve en baştan başlayacaksın. Emin misin?" % [s.day, K.money(s.money)]
		_open_screen(_confirm[0], _confirm[1])
	else:
		_busy = true
		start_game.emit(false)


func _build_confirm() -> void:
	var m := K.modal(self, 560, 0.7)
	_confirm = [m[0], m[1], m[2]]
	var vb: VBoxContainer = m[2]
	K.label(vb, "Yeni oyun başlat?", 32, T.ACCENT, "TitleLabel")
	var l := K.label(vb, "", 19, T.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(480, 0)
	_confirm.append(l)
	K.spacer(vb, 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	K.button(row, "Vazgeç", func(): _close_screen(m[0], m[1]), "", 20, Vector2(0, 50)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	K.button(row, "Evet, sıfırla", func():
		_busy = true
		K.close(m[0], m[1])
		start_game.emit(false), "DangerButton", 20, Vector2(0, 50)).size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _build_credits() -> void:
	var m := K.modal(self, 760, 0.7)
	_credits = [m[0], m[1]]
	var vb: VBoxContainer = m[2]
	K.label(vb, "Emeği Geçenler", 34, T.ACCENT, "TitleLabel")
	K.hsep(vb)
	var items := [
		["Oyun", "Bilgisayarcı Simülatör - Godot 4.4 ile, tamamen GDScript ve kodla üretilmiş 3B modellerle yapıldı."],
		["Oyun motoru", "Godot Engine (MIT lisansı) - godotengine.org"],
		["Doku ve HDRI", "Poly Haven (CC0 / kamu malı): zemin, duvar, tuğla, ahşap, laminat, kaldırım, asfalt dokuları ve şehir HDRI'si - polyhaven.com"],
		["Yazı tipi", "Exo 2 - The Exo 2 Project Authors (SIL Open Font License 1.1) - assets/fonts/OFL.txt"],
		["Ses ve müzik", "Tüm sesler ve fon müziği oyun içinde kodla üretilir."],
	]
	for it in items:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 18)
		vb.add_child(h)
		var a := K.label(h, it[0], 18, T.ACCENT_HI, "BoldLabel")
		a.custom_minimum_size = Vector2(130, 0)
		a.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var b := K.label(h, it[1], 18, T.TEXT)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(540, 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	K.spacer(vb, 6)
	var row := HBoxContainer.new()
	vb.add_child(row)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	K.button(row, "Geri", func(): _close_screen(m[0], m[1]), "PrimaryButton", 20, Vector2(150, 46))


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	for s in [_credits, _confirm]:
		if s[0].visible:
			Game.sfx.ui_back()
			_close_screen(s[0], s[1])
			get_viewport().set_input_as_handled()
			return
