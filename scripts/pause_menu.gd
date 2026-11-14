extends CanvasLayer
## Duraklatma menüsü: bulanık/karartılmış arka plan, oyun (get_tree().paused) gerçekten durur.

const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")
const SETTINGS := preload("res://scripts/settings_panel.gd")
const HOWTO := preload("res://scripts/howto_panel.gd")

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 2.6).rgb;
	float vig = smoothstep(0.3, 1.1, length(SCREEN_UV - 0.5));
	c = mix(c, vec3(0.03, 0.045, 0.1), 0.55 + vig * 0.25);
	COLOR = vec4(c, 1.0);
}
"""

var _root: Control
var _panel: Control
var _status: Label
var _buttons: Array[Button] = []
var _settings: Control
var _howto: Control
var _last_btn: Button
var open_now := false


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	var blur := ColorRect.new()
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	blur.material = mat
	_root.add_child(blur)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(cc)
	_panel = K.panel(cc, "ModalPanel")
	_panel.custom_minimum_size = Vector2(460, 0)
	_panel.resized.connect(func(): _panel.pivot_offset = _panel.size * 0.5)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_panel.add_child(vb)
	var title := K.label(vb, "DURAKLATILDI", 38, T.ACCENT, "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status = K.label(vb, "", 18, T.MUTED, "MutedLabel")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K.spacer(vb, 6)
	_buttons.append(K.button(vb, "Devam Et", close, "PrimaryButton", 22, Vector2(0, 54)))
	_buttons.append(K.button(vb, "Ayarlar", func(): _open_screen(_settings), "", 21, Vector2(0, 50)))
	_buttons.append(K.button(vb, "Nasıl Oynanır", func(): _open_screen(_howto), "", 21, Vector2(0, 50)))
	_buttons.append(K.button(vb, "Ana Menüye Dön", _to_menu, "", 21, Vector2(0, 50)))
	_buttons.append(K.button(vb, "Oyundan Çık", _quit, "DangerButton", 21, Vector2(0, 50)))
	var note := K.label(vb, "Ana menüye dönerken oyun otomatik kaydedilir.", 14, Color(1, 1, 1, 0.4), "MutedLabel")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings = SETTINGS.new()
	_settings.back.connect(func(): _close_screen(_settings))
	add_child(_settings)
	_howto = HOWTO.new()
	_howto.back.connect(func(): _close_screen(_howto))
	add_child(_howto)


func open() -> void:
	if open_now:
		return
	open_now = true
	Game.paused = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = "Gün %d  ·  %s  ·  %s TL" % [Game.day, Game.clock_text(), K.money(Game.money)]
	K.open(_root, _panel)
	_buttons[0].grab_focus()
	Game.sfx.ui_back()


func close() -> void:
	if not open_now:
		return
	open_now = false
	Game.paused = false
	get_tree().paused = false
	K.close(_root, _panel)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_focusable(on: bool) -> void:
	for b in _buttons:
		b.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE


func _open_screen(screen: Control) -> void:
	_last_btn = get_viewport().gui_get_focus_owner() as Button
	_set_focusable(false)
	screen.open()


func _close_screen(screen: Control) -> void:
	screen.close()
	_set_focusable(true)
	if _last_btn and is_instance_valid(_last_btn):
		_last_btn.grab_focus()


func _to_menu() -> void:
	open_now = false
	Game.return_to_menu()


func _quit() -> void:
	if Game.started and (Game.phase == "day" or Game.phase == "summary"):
		Game.save_game()
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if open_now and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
