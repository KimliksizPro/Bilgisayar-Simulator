extends RefCounted
## Ortak arayüz teması: renk paleti, font ve stiller. `build()` tüm oyunun temasını üretir
## (assets/ui/theme.tres bu fonksiyonla dev/make_theme.gd tarafından oluşturulur).

const BG := Color("0a0f1e")
const PANEL := Color("111a30")
const PANEL2 := Color("1a2544")
const PANEL3 := Color("26345e")
const BORDER := Color("2f3e6b")
const ACCENT := Color("ffb52e")
const ACCENT_HI := Color("ffcc66")
const ACCENT_LO := Color("d98f10")
const TEXT := Color("e9eefb")
const MUTED := Color("93a0c4")
const GOOD := Color("62e38c")
const BAD := Color("ff6b5e")
const INFO := Color("5cc8ff")

const FONT_PATH := "res://assets/fonts/Exo2.ttf"
const WGHT_TAG := 2003265652   # "wght" OpenType ekseni


static func font(weight: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load(FONT_PATH)
	fv.variation_opentype = {WGHT_TAG: weight}
	return fv


static func flat(bg: Color, radius := 10, border := Color(0, 0, 0, 0), bw := 0, pad := Vector2(16, 10), shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(bw)
	s.border_color = border
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	if shadow > 0:
		s.shadow_size = shadow
		s.shadow_color = Color(0, 0, 0, 0.42)
		s.shadow_offset = Vector2(0, shadow * 0.35)
	s.anti_aliasing = true
	return s


static func _alpha(d: float) -> float:
	return clampf(0.5 - d, 0.0, 1.0)


## Yuvarlak sürgü topuzu (beyaz dış halka + amber çekirdek).
static func _knob_tex(d: int, outer: Color, inner: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := _alpha(dist - (d * 0.5 - 1.0))
			var core := _alpha(dist - (d * 0.5 - 5.0))
			var col := outer.lerp(inner, core)
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Açma/kapama anahtarı (hap şeklinde).
static func _switch_tex(on: bool, disabled := false) -> ImageTexture:
	var w := 52
	var h := 28
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := ACCENT if on else PANEL3
	var edge := ACCENT_HI if on else BORDER
	if disabled:
		track = track.darkened(0.5)
	var r := h * 0.5
	var knob_c := Vector2(w - r, r) if on else Vector2(r, r)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# kapsül mesafesi
			var cx := clampf(p.x, r, w - r)
			var dist := p.distance_to(Vector2(cx, r)) - (r - 1.0)
			var a := _alpha(dist)
			var col := edge.lerp(track, _alpha(dist + 2.0))
			var kd := p.distance_to(knob_c) - (r - 5.0)
			col = col.lerp(Color(0.97, 0.98, 1.0) if not disabled else Color(0.6, 0.62, 0.7), _alpha(kd))
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func build() -> Theme:
	var t := Theme.new()
	var regular := font(500)
	var bold := font(700)
	var heavy := font(800)
	t.default_font = regular
	t.default_font_size = 18

	# --- Label ---
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("line_spacing", "Label", 2)
	for pair in [["BoldLabel", bold, TEXT], ["TitleLabel", heavy, TEXT], ["MutedLabel", regular, MUTED],
			["AccentLabel", bold, ACCENT], ["SmallCaps", bold, MUTED]]:
		t.set_type_variation(pair[0], "Label")
		t.set_font("font", pair[0], pair[1])
		t.set_color("font_color", pair[0], pair[2])

	# --- Paneller ---
	t.set_stylebox("panel", "PanelContainer", flat(PANEL, 14, BORDER, 1, Vector2(18, 14), 14))
	t.set_stylebox("panel", "Panel", flat(PANEL, 14, BORDER, 1))
	t.set_type_variation("HudCard", "PanelContainer")
	t.set_stylebox("panel", "HudCard", flat(Color(0.035, 0.055, 0.11, 0.8), 14, Color(1, 1, 1, 0.09), 1, Vector2(16, 12), 12))
	t.set_type_variation("ModalPanel", "PanelContainer")
	t.set_stylebox("panel", "ModalPanel", flat(Color(0.063, 0.094, 0.18, 0.98), 22, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45), 2, Vector2(30, 26), 40))
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", flat(Color(0, 0, 0, 0.26), 12, Color(1, 1, 1, 0.05), 1, Vector2(16, 12)))
	t.set_type_variation("KeyCap", "PanelContainer")
	var kc := flat(PANEL3, 8, Color(0.55, 0.62, 0.85, 0.55), 2, Vector2(10, 3))
	kc.border_width_bottom = 5
	kc.border_color = Color(0.45, 0.52, 0.78, 0.7)
	t.set_stylebox("panel", "KeyCap", kc)
	t.set_type_variation("Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", flat(Color(0.38, 0.89, 0.55, 0.16), 20, Color(0.38, 0.89, 0.55, 0.5), 1, Vector2(12, 3)))
	t.set_type_variation("Toast", "PanelContainer")
	t.set_stylebox("panel", "Toast", flat(Color(0.035, 0.055, 0.11, 0.9), 14, Color(1, 1, 1, 0.1), 1, Vector2(12, 9), 10))

	# --- Düğmeler ---
	var bt := "Button"
	t.set_stylebox("normal", bt, flat(PANEL2, 12, BORDER, 1, Vector2(22, 10)))
	t.set_stylebox("hover", bt, flat(PANEL3, 12, ACCENT_LO, 2, Vector2(22, 10)))
	t.set_stylebox("pressed", bt, flat(Color("101834"), 12, ACCENT, 2, Vector2(22, 10)))
	t.set_stylebox("hover_pressed", bt, flat(Color("101834"), 12, ACCENT, 2, Vector2(22, 10)))
	t.set_stylebox("disabled", bt, flat(Color(0.08, 0.11, 0.2, 0.8), 12, Color(1, 1, 1, 0.05), 1, Vector2(22, 10)))
	var focus := flat(Color(0, 0, 0, 0), 12, ACCENT, 2, Vector2(22, 10))
	focus.set_expand_margin_all(2)
	t.set_stylebox("focus", bt, focus)
	t.set_font("font", bt, bold)
	t.set_font_size("font_size", bt, 20)
	t.set_color("font_color", bt, TEXT)
	t.set_color("font_hover_color", bt, Color.WHITE)
	t.set_color("font_focus_color", bt, Color.WHITE)
	t.set_color("font_pressed_color", bt, ACCENT_HI)
	t.set_color("font_hover_pressed_color", bt, ACCENT_HI)
	t.set_color("font_disabled_color", bt, Color(0.5, 0.55, 0.68, 0.8))
	t.set_constant("h_separation", bt, 10)

	# Ana eylem düğmesi (amber dolgulu)
	t.set_type_variation("PrimaryButton", bt)
	t.set_stylebox("normal", "PrimaryButton", flat(ACCENT, 12, ACCENT_HI, 1, Vector2(26, 10), 8))
	t.set_stylebox("hover", "PrimaryButton", flat(ACCENT_HI, 12, Color.WHITE, 2, Vector2(26, 10), 12))
	t.set_stylebox("pressed", "PrimaryButton", flat(ACCENT_LO, 12, ACCENT_HI, 2, Vector2(26, 10)))
	t.set_stylebox("hover_pressed", "PrimaryButton", flat(ACCENT_LO, 12, ACCENT_HI, 2, Vector2(26, 10)))
	t.set_stylebox("disabled", "PrimaryButton", flat(Color(0.25, 0.27, 0.34, 0.9), 12, Color(1, 1, 1, 0.06), 1, Vector2(26, 10)))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "PrimaryButton", Color("1a1204"))
	t.set_color("font_disabled_color", "PrimaryButton", Color(0.6, 0.63, 0.72, 0.8))

	# Tehlikeli eylem
	t.set_type_variation("DangerButton", bt)
	t.set_stylebox("normal", "DangerButton", flat(Color("3a1620"), 12, Color(BAD.r, BAD.g, BAD.b, 0.5), 1, Vector2(22, 10)))
	t.set_stylebox("hover", "DangerButton", flat(Color("5a1d2a"), 12, BAD, 2, Vector2(22, 10)))
	t.set_stylebox("pressed", "DangerButton", flat(Color("2a0f17"), 12, BAD, 2, Vector2(22, 10)))
	t.set_color("font_color", "DangerButton", Color("ffd2cc"))

	# Ana menü büyük düğmesi
	t.set_type_variation("BigMenuButton", bt)
	t.set_stylebox("normal", "BigMenuButton", flat(Color(0.05, 0.08, 0.16, 0.72), 14, Color(1, 1, 1, 0.1), 1, Vector2(26, 12), 10))
	t.set_stylebox("hover", "BigMenuButton", flat(Color(0.2, 0.15, 0.06, 0.92), 14, ACCENT, 2, Vector2(26, 12), 14))
	t.set_stylebox("pressed", "BigMenuButton", flat(Color(0.12, 0.09, 0.04, 0.95), 14, ACCENT, 2, Vector2(26, 12)))
	t.set_stylebox("disabled", "BigMenuButton", flat(Color(0.05, 0.08, 0.16, 0.5), 14, Color(1, 1, 1, 0.05), 1, Vector2(26, 12)))
	t.set_font_size("font_size", "BigMenuButton", 24)
	t.set_color("font_hover_color", "BigMenuButton", ACCENT_HI)
	t.set_color("font_focus_color", "BigMenuButton", ACCENT_HI)

	# Sekme düğmesi
	t.set_type_variation("TabButton", bt)
	t.set_stylebox("normal", "TabButton", flat(Color(0, 0, 0, 0), 10, Color(0, 0, 0, 0), 0, Vector2(22, 9)))
	t.set_stylebox("hover", "TabButton", flat(PANEL2, 10, Color(0, 0, 0, 0), 0, Vector2(22, 9)))
	var tab_on := flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16), 10, Color(0, 0, 0, 0), 0, Vector2(22, 9))
	tab_on.border_width_bottom = 3
	tab_on.border_color = ACCENT
	t.set_stylebox("pressed", "TabButton", tab_on)
	t.set_stylebox("hover_pressed", "TabButton", tab_on)
	t.set_color("font_color", "TabButton", MUTED)
	t.set_color("font_pressed_color", "TabButton", ACCENT_HI)
	t.set_color("font_hover_pressed_color", "TabButton", ACCENT_HI)

	# Seçenek (segment) düğmesi
	t.set_type_variation("SegButton", bt)
	t.set_stylebox("normal", "SegButton", flat(PANEL2, 9, BORDER, 1, Vector2(16, 7)))
	t.set_stylebox("hover", "SegButton", flat(PANEL3, 9, ACCENT_LO, 1, Vector2(16, 7)))
	t.set_stylebox("pressed", "SegButton", flat(ACCENT, 9, ACCENT_HI, 1, Vector2(16, 7)))
	t.set_stylebox("hover_pressed", "SegButton", flat(ACCENT_HI, 9, Color.WHITE, 1, Vector2(16, 7)))
	for c in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "SegButton", Color("1a1204"))
	t.set_font_size("font_size", "SegButton", 17)

	# --- CheckButton (açma/kapama anahtarı) ---
	var cb := "CheckButton"
	var none := StyleBoxEmpty.new()
	for st in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
		t.set_stylebox(st, cb, none)
	var cf := flat(Color(0, 0, 0, 0), 14, ACCENT, 2, Vector2(4, 4))
	t.set_stylebox("focus", cb, cf)
	t.set_icon("checked", cb, _switch_tex(true))
	t.set_icon("unchecked", cb, _switch_tex(false))
	t.set_icon("checked_disabled", cb, _switch_tex(true, true))
	t.set_icon("unchecked_disabled", cb, _switch_tex(false, true))
	t.set_icon("checked_mirrored", cb, _switch_tex(true))
	t.set_icon("unchecked_mirrored", cb, _switch_tex(false))
	t.set_color("font_color", cb, TEXT)

	# --- Sürgü ---
	var track := flat(Color(0, 0, 0, 0.45), 6, Color(1, 1, 1, 0.08), 1, Vector2(0, 5))
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", flat(ACCENT_LO, 6, Color(0, 0, 0, 0), 0, Vector2(0, 5)))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(ACCENT, 6, Color(0, 0, 0, 0), 0, Vector2(0, 5)))
	var knob := _knob_tex(26, Color(0.97, 0.98, 1.0), ACCENT)
	var knob_hi := _knob_tex(26, Color.WHITE, ACCENT_HI)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob_hi)
	t.set_icon("grabber_disabled", "HSlider", knob)
	t.set_constant("center_grabber", "HSlider", 0)

	# --- İlerleme çubuğu ---
	t.set_stylebox("background", "ProgressBar", flat(Color(0, 0, 0, 0.5), 6, Color(1, 1, 1, 0.07), 1, Vector2(0, 0)))
	t.set_stylebox("fill", "ProgressBar", flat(ACCENT, 6, Color(0, 0, 0, 0), 0, Vector2(0, 0)))

	# --- Kaydırma çubuğu ---
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, flat(Color(0, 0, 0, 0.25), 5, Color(0, 0, 0, 0), 0, Vector2(4, 4)))
		t.set_stylebox("grabber", sb, flat(Color(0.55, 0.62, 0.85, 0.5), 5, Color(0, 0, 0, 0), 0, Vector2(4, 4)))
		t.set_stylebox("grabber_highlight", sb, flat(ACCENT_LO, 5, Color(0, 0, 0, 0), 0, Vector2(4, 4)))
		t.set_stylebox("grabber_pressed", sb, flat(ACCENT, 5, Color(0, 0, 0, 0), 0, Vector2(4, 4)))

	# --- Ayırıcı ---
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.09)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 14)
	return t
