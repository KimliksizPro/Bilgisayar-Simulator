extends Node3D
## Tezgâh modu: Tab ile cihazı (PC kasası yatırılarak, kapak yana yaslanarak) yakın çekime alır;
## ESD parça tepsisi, manyetik vida tabağı, doğrudan stok çekmecesi, masa aletleri ve
## 3 bölgeli modern tamirhane arayüzü (Üst Çubuk, Sol Sekmeli Çekmece, Alt Alet Barı) sunar.

const MU := preload("res://scripts/mesh_util.gd")
const PM := preload("res://scripts/part_models.gd")
const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")
const PC_SCRIPT := preload("res://scripts/pc_case.gd")
const PART := preload("res://scripts/part.gd")
const ST := preload("res://scripts/job_store.gd")

const TRANS := 0.35          # kamera / kasa yatırma geçiş süresi (sn)
const BENCH_FOV := 55.0
const TRAY_W := 0.40
const TRAY_D := 0.34
const TRAY_TOP := 0.008
const PC_FLAT_X := 0.32
const PC_MAT_Z := -2.50

const GREEN := Color(0.2, 1.0, 0.35, 0.32)
const AMBER := Color(1.0, 0.72, 0.15, 0.35)
const RED := Color(1.0, 0.2, 0.15, 0.32)
const HL_CYAN := Color(0.36, 0.86, 1.0)

const RIM_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform vec4 rim_color : source_color = vec4(0.36, 0.86, 1.0, 1.0);
uniform float power = 2.5;
uniform float fill_alpha = 0.07;
void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), power);
	ALBEDO = rim_color.rgb;
	ALPHA = clamp(fill_alpha + f * 0.78, 0.0, 0.85) * rim_color.a;
}
"""

const STOCK_CATS := [
	{"id": "all", "label": "Tümü", "cats": []},
	{"id": "ram", "label": "RAM", "cats": ["ram"]},
	{"id": "gpu", "label": "GPU", "cats": ["gpu"]},
	{"id": "cpu", "label": "CPU", "cats": ["cpu"]},
	{"id": "disk", "label": "Disk", "cats": ["ssd", "nvme", "hdd"]},
	{"id": "psu", "label": "PSU", "cats": ["psu"]},
	{"id": "other", "label": "Diğer", "cats": ["mobo", "cooler", "fan", "cmos"]},
]

var state := "off"           # off, entering, on, leaving
var cam: Camera3D            # yörünge kamera (ve puff gibi alet çağrıları için oyuncu.cam yerine geçer)
var held = null              # yuva/alet ipuçları player.held okur; tezgâh modunda elde bir şey yok
var device = null            # bağlı tezgâh cihazı
var kind := "pc"             # pc, laptop, phone
var tray_parts: Array = []
var selected = null          # fareyle seçilen (hayalet) parça
var tool = null              # seçili alet
var hovered := {}            # fare altındaki hedef (_resolve sonucu)
var mouse_override := Vector2(-1, -1)  # >= 0 ise gerçek fare yerine bu konum (dev/test)

var _tray: Node3D
var _dish_screws: Array = []
var _hl: MeshInstance3D      # boş yuva / büyük cam kapak için köşe çerçevesi
var _hl_mat: StandardMaterial3D
var _rim_shader: Shader
var _hl_rim_mats := {}       # key -> ShaderMaterial
var _hl_meshes: Array = []

var _laid_flat := false
var _stand_xf := Transform3D.IDENTITY
var _flat_xf := Transform3D.IDENTITY
var _case_from_xf := Transform3D.IDENTITY
var _case_goal_xf := Transform3D.IDENTITY
var _case_t := 1.0

var _t := 0.0
var _from_xf := Transform3D.IDENTITY
var _from_fov := 70.0
var _yaw := 0.0
var _yaw_goal := 0.0
var _elev := 0.3
var _dist := 0.8
var _dist_goal := 0.8
var _d_min := 0.3
var _d_max := 1.5
var _pan := Vector3.ZERO
var _pan_max := 0.5
var _center := Vector3.ZERO
var _orbit_ready := false
var _excl: Array = []
var _rmb := false
var _rmb_moved := 0.0
var _mmb := false
var _touches: Dictionary = {}
var _touch_pos := Vector2(-1, -1)
var _touch_start := Vector2.ZERO
var _touch_moved := 0.0
var _touch_was_pinch := false
var _touch_pinch_dist := 0.0
var _stash_tool = null
var _tint_cur = null
var _mat_neutral: StandardMaterial3D
var _mat_ok: StandardMaterial3D
var _mat_warn: StandardMaterial3D
var _mat_bad: StandardMaterial3D
var _ever_open := false
var _ever_power := false
var _ever_removed := false
var _ever_installed := false
var _sig := ""
var _sig_t := 0.0

# 3 bölgeli tezgâh arayüzü + bilgi kartı
var _ui: CanvasLayer
var _ui_root: Control
var _top_bar: PanelContainer
var _top_hb: HBoxContainer
var _side: PanelContainer
var _side_tab_bar: HBoxContainer
var _side_scroll: ScrollContainer
var _side_vb: VBoxContainer
var _tab := 0                # 0: İş, 1: Stok, 2: Tepsi
var _stock_cat := "all"
var _dock: PanelContainer
var _dock_tools: HBoxContainer
var _dock_keys: HBoxContainer
var _tip: PanelContainer
var _tip_accent: ColorRect
var _tip_title: Label
var _tip_spec: Label
var _tip_sub: Label


func _ready() -> void:
	cam = Camera3D.new()
	cam.near = 0.01
	cam.far = 60.0
	cam.fov = BENCH_FOV
	cam.cull_mask = 0xFFFFF & ~(1 << 19)  # elde tutulan eşya katmanı (viewmodel) görünmesin
	add_child(cam)
	_build_tray()
	_build_materials()
	_build_ui()
	Game.bench_changed.connect(_on_bench_changed)
	if is_instance_valid(Game.bench_device):
		_bind(Game.bench_device)


func _exit_tree() -> void:
	_clear_hl()
	if state != "off":
		Game.bench_active = false


func is_laid_flat() -> bool:
	return _laid_flat


# ---------------------------------------------------------------- bağlama

func _on_bench_changed(d) -> void:
	if state != "off":
		_report_exit("tezgâhtaki cihaz değişti")
		exit(true)
	_release_tray()
	_bind(d if is_instance_valid(d) else null)
	if device != null and Game.hud:
		Game.hud.tip("bench_tab", "Tezgâh modu: [Tab] tuşuna basıp cihazı yakından incele; parçaları fareyle sök, tepsiden sürükleyip tak.")


func _bind(d) -> void:
	device = d
	_orbit_ready = false
	_laid_flat = false
	_case_t = 1.0
	_sig = ""
	_tab = 0
	_ever_open = false
	_ever_power = false
	_ever_removed = false
	_ever_installed = false
	_excl = []
	_tray.visible = device != null
	if device == null:
		return
	if device.get_script() == PC_SCRIPT:
		kind = "pc"
	elif "lid" in device:
		kind = "laptop"
	else:
		kind = "phone"
	for c in device.find_children("*", "CollisionObject3D", true, false):
		_excl.append(c.get_rid())
	_place_tray()
	_update_screw_dish()


## Tepsi masada cihazın hemen sağında durur (PC/telefon sağda; laptopta kapak sağa açıldığı için önde).
func _place_tray() -> void:
	var o: Vector3 = device.global_position
	var desk_y: float = float(get_parent().get("DESK_Y")) if get_parent().get("DESK_Y") != null else 0.75
	match kind:
		"pc":
			_tray.global_position = Vector3(0.80, desk_y + 0.005, -2.37)
		"laptop":
			_tray.global_position = Vector3(o.x + 0.02, desk_y + 0.005, o.z + 0.33)
		_:
			_tray.global_position = Vector3(o.x + 0.28, desk_y + 0.005, o.z + 0.02)
	_tray.global_rotation = Vector3.ZERO
	_layout_tray()


## Cihaz gidince tepsideki parçalar masaya serbest düşer; geçici test parçaları silinir.
func _release_tray() -> void:
	selected = null
	tool = null
	_tint_cur = null
	for p in tray_parts:
		if not is_instance_valid(p):
			continue
		if "is_test_part" in p and p.is_test_part:
			p.queue_free()
			continue
		_set_tint(p, null)
		var gt: Transform3D = p.global_transform
		var w: Node = get_parent()
		if p.get_parent():
			p.reparent(w, false)
		p.global_transform = gt
		p.visible = true
		p.collision_layer = 2
		p.collision_mask = 1
		p.freeze = false
	tray_parts.clear()


# ---------------------------------------------------------------- ESD tepsi + vurgu + UI

func _build_tray() -> void:
	_tray = Node3D.new()
	_tray.visible = false
	add_child(_tray)
	var base_m := MU.mat(Color(0.08, 0.10, 0.14), 0.15, 0.85)
	var rim_m := MU.mat(Color(0.32, 0.36, 0.42), 0.65, 0.35)
	var line_m := MU.mat(Color(0.16, 0.22, 0.30), 0.1, 0.9)
	MU.rbox(_tray, Vector3(TRAY_W, 0.008, TRAY_D), Vector3(0, 0.004, 0), base_m, 0.004)
	for z in [-1, 1]:
		MU.rbox(_tray, Vector3(TRAY_W, 0.014, 0.007), Vector3(0, 0.007, z * (TRAY_D / 2.0 - 0.0035)), rim_m, 0.002)
	for x in [-1, 1]:
		MU.rbox(_tray, Vector3(0.007, 0.014, TRAY_D), Vector3(x * (TRAY_W / 2.0 - 0.0035), 0.007, 0), rim_m, 0.002)
	MU.box(_tray, Vector3(TRAY_W - 0.02, 0.0008, 0.002), Vector3(0, TRAY_TOP + 0.0004, 0.0), line_m)
	var stock_bar_m := MU.mat(Color(0.22, 0.78, 0.45), 0.1, 0.85)
	var pulled_bar_m := MU.mat(Color(0.95, 0.65, 0.16), 0.1, 0.85)
	MU.box(_tray, Vector3(TRAY_W - 0.12, 0.001, 0.0025), Vector3(-0.045, TRAY_TOP + 0.0005, -TRAY_D / 2.0 + 0.011), stock_bar_m)
	MU.box(_tray, Vector3(TRAY_W - 0.02, 0.001, 0.0025), Vector3(0, TRAY_TOP + 0.0005, 0.002), pulled_bar_m)
	var l_st := MU.label(_tray, "YENİ / STOK", Vector3(-TRAY_W / 2.0 + 0.068, TRAY_TOP + 0.0014, -TRAY_D / 2.0 + 0.022), 26, Color(0.55, 0.96, 0.68), Vector3(-90, 0, 0), 0.00022)
	l_st.double_sided = false
	var l_pu := MU.label(_tray, "SÖKÜLEN (MÜŞTERİ)", Vector3(-TRAY_W / 2.0 + 0.095, TRAY_TOP + 0.0014, 0.015), 26, Color(1.0, 0.80, 0.42), Vector3(-90, 0, 0), 0.00022)
	l_pu.double_sided = false
	var l := MU.label(_tray, "PARÇA TEPSİSİ", Vector3(0, 0.010, TRAY_D / 2.0 + 0.0005), 34, Color(0.75, 0.85, 0.95), Vector3.ZERO, 0.00022)
	l.double_sided = false

	# sağ arka köşede manyetik vida tabağı
	var dish_c := Vector3(TRAY_W / 2.0 - 0.056, TRAY_TOP + 0.001, -TRAY_D / 2.0 + 0.056)
	MU.cyl(_tray, 0.044, 0.003, dish_c, rim_m, Vector3.ZERO, 20)
	MU.cyl(_tray, 0.038, 0.0036, dish_c + Vector3(0, 0.0005, 0), MU.mat(Color(0.12, 0.13, 0.16), 0.7, 0.35), Vector3.ZERO, 20)
	var sm := MU.mat(Color(0.8, 0.84, 0.9), 0.9, 0.25)
	_dish_screws = []
	for i in 4:
		var ang := float(i) * PI * 0.5 + 0.4
		var sp := dish_c + Vector3(cos(ang) * 0.016, 0.0038, sin(ang) * 0.016)
		var sc := Node3D.new()
		sc.position = sp
		_tray.add_child(sc)
		MU.cyl(sc, 0.0032, 0.002, Vector3.ZERO, sm, Vector3.ZERO, 8)
		sc.visible = false
		_dish_screws.append(sc)

	# köşe çerçevesi (boş yuva / cam kapak için, dolu sarı kutu yerine şeffaf L-köşeler)
	_hl = MeshInstance3D.new()
	_hl.mesh = _build_brackets_mesh()
	_hl_mat = StandardMaterial3D.new()
	_hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hl_mat.albedo_color = Color(HL_CYAN.r, HL_CYAN.g, HL_CYAN.b, 0.9)
	_hl_mat.no_depth_test = true
	_hl_mat.render_priority = 12
	_hl.material_override = _hl_mat
	_hl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hl.visible = false
	add_child(_hl)


func _build_brackets_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var h := 0.5
	var arm := 0.24
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var c := Vector3(sx * h, sy * h, sz * h)
				verts.append(c)
				verts.append(c + Vector3(-sx * arm, 0.0, 0.0))
				verts.append(c)
				verts.append(c + Vector3(0.0, -sy * arm, 0.0))
				verts.append(c)
				verts.append(c + Vector3(0.0, 0.0, -sz * arm))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m


func _update_screw_dish() -> void:
	if _dish_screws.is_empty():
		return
	var loose_cnt := 0
	if device != null and is_instance_valid(device) and kind == "pc" and "screws" in device:
		for sid in ["panel_1", "panel_2"]:
			if not bool(device.screws.get(sid, true)):
				loose_cnt += 1
		for sid in ["gpu", "m2"]:
			if device.part_in(sid) != null and not bool(device.screws.get(sid, false)):
				loose_cnt += 1
	for i in _dish_screws.size():
		_dish_screws[i].visible = i < loose_cnt


func _build_materials() -> void:
	_mat_neutral = _tint_mat(Color(0.55, 0.8, 1.0, 0.6))
	_mat_ok = _tint_mat(Color(0.25, 1.0, 0.4, 0.6))
	_mat_warn = _tint_mat(Color(1.0, 0.72, 0.15, 0.6))
	_mat_bad = _tint_mat(Color(1.0, 0.25, 0.2, 0.6))
	_rim_shader = Shader.new()
	_rim_shader.code = RIM_SHADER_CODE
	_hl_rim_mats = {
		"cyan": _make_rim_mat(HL_CYAN),
		"green": _make_rim_mat(T.GOOD),
		"amber": _make_rim_mat(T.ACCENT),
		"red": _make_rim_mat(T.BAD),
	}


func _make_rim_mat(c: Color) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = _rim_shader
	sm.set_shader_parameter("rim_color", Color(c.r, c.g, c.b, 1.0))
	return sm


func _tint_mat(c: Color) -> StandardMaterial3D:
	var m := MU.new_mat(c, 0, 0.5, 0.8)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 10
	return m


func _card_style(rad := 8, pad := Vector2(12, 8)) -> StyleBoxFlat:
	return T.flat(Color(0.06, 0.075, 0.11, 0.90), rad, Color(0.25, 0.32, 0.42, 0.78), 1, pad, 6)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 3
	add_child(_ui)
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.visible = false
	_ui.add_child(_ui_root)

	# 1) ÜST BARI: cihaz özeti, watt ölçer, hızlı eylem düğmeleri, kasa parası
	_top_bar = K.panel(_ui_root, "HudCard")
	_top_bar.add_theme_stylebox_override("panel", _card_style(9, Vector2(14, 7)))
	_top_bar.pivot_offset = Vector2.ZERO
	_top_hb = HBoxContainer.new()
	_top_hb.add_theme_constant_override("separation", 10)
	_top_bar.add_child(_top_hb)

	# 2) SOL SEKMELİ ÇEKMECE: İş / Stok / Tepsi
	_side = K.panel(_ui_root, "HudCard")
	_side.add_theme_stylebox_override("panel", _card_style(9, Vector2(12, 10)))
	_side.pivot_offset = Vector2.ZERO
	var side_outer := VBoxContainer.new()
	side_outer.add_theme_constant_override("separation", 8)
	side_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.add_child(side_outer)
	_side_tab_bar = HBoxContainer.new()
	_side_tab_bar.add_theme_constant_override("separation", 6)
	side_outer.add_child(_side_tab_bar)
	K.hsep(side_outer).add_theme_constant_override("separation", 2)
	_side_scroll = ScrollContainer.new()
	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_side_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_outer.add_child(_side_scroll)
	_side_vb = VBoxContainer.new()
	_side_vb.add_theme_constant_override("separation", 6)
	_side_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_scroll.add_child(_side_vb)

	# 3) ALT DOCK: alet çubuğu + kısa tuş ipuçları
	_dock = K.panel(_ui_root, "HudCard")
	_dock.add_theme_stylebox_override("panel", _card_style(10, Vector2(14, 7)))
	var dock_vb := VBoxContainer.new()
	dock_vb.add_theme_constant_override("separation", 5)
	_dock.add_child(dock_vb)
	_dock_tools = HBoxContainer.new()
	_dock_tools.alignment = BoxContainer.ALIGNMENT_CENTER
	_dock_tools.add_theme_constant_override("separation", 6)
	dock_vb.add_child(_dock_tools)
	_dock_keys = HBoxContainer.new()
	_dock_keys.alignment = BoxContainer.ALIGNMENT_CENTER
	_dock_keys.add_theme_constant_override("separation", 8)
	dock_vb.add_child(_dock_keys)

	# 4) FARE YANI İNCELEME KARTI
	_tip = K.panel(_ui_root, "Toast")
	_tip.add_theme_stylebox_override("panel", T.flat(Color(0.05, 0.065, 0.10, 0.95), 8, Color(0.28, 0.36, 0.48, 0.8), 1, Vector2(10, 8), 8))
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.pivot_offset = Vector2.ZERO
	_tip.visible = false
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 9)
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(th)
	_tip_accent = ColorRect.new()
	_tip_accent.custom_minimum_size = Vector2(4, 0)
	_tip_accent.color = HL_CYAN
	_tip_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.add_child(_tip_accent)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.add_child(tv)
	_tip_title = K.label(tv, "", 16, T.TEXT, "BoldLabel")
	_tip_spec = K.label(tv, "", 12, T.MUTED)
	_tip_sub = K.label(tv, "", 14, T.ACCENT)

	_rebuild_keys()
	Settings.changed.connect(_on_setting_changed)
	get_viewport().size_changed.connect(_layout_ui)
	_layout_ui()


func _on_setting_changed(k: String) -> void:
	if k == "hud_scale":
		_layout_ui()
	elif k == "touch_controls":
		_rebuild_keys()
		_layout_ui()


func _rebuild_keys() -> void:
	if _dock_keys == null:
		return
	for c in _dock_keys.get_children():
		_dock_keys.remove_child(c)
		c.queue_free()
	var touch := Settings.is_touch_enabled()
	_dock.mouse_filter = Control.MOUSE_FILTER_PASS
	var pairs: Array
	if touch:
		pairs = [["SÜRÜKLE", "Döndür"], ["İKİ PARMAK", "Yakınlaştır"], ["DOKUN", "Sök / Tak"]]
	else:
		pairs = [["SAĞ TIK", "Döndür"], ["TEKERLEK", "Yakınlaştır"], ["F", "Yatır / Dik"], ["Q E", "90°"], ["TAB", "Çık"]]
	for pair in pairs:
		K.keycap(_dock_keys, pair[0], 11)
		K.label(_dock_keys, pair[1], 13, T.MUTED)
		K.spacer(_dock_keys, 0).custom_minimum_size = Vector2(6, 0)
	if touch:
		K.button(_dock_keys, "Çık", func(): exit(), "PrimaryButton", 13, Vector2(60, 26))


func _layout_ui() -> void:
	if _ui_root == null or not is_inside_tree():
		return
	var vs := get_viewport().get_visible_rect().size
	var s := Settings.hud_scale
	var sv := Vector2(s, s)

	# Üst bar (tam genişlik - 28px kenar boşluğu)
	_top_bar.scale = sv
	_top_bar.position = Vector2(14.0, 12.0)
	_top_bar.custom_minimum_size = Vector2(maxf(520.0, (vs.x - 28.0) / s), 48.0)
	_top_bar.reset_size()
	var top_bottom: float = 12.0 + _top_bar.size.y * s

	# Alt dock (alt-ortadan ölçekli)
	_dock.reset_size()
	_dock.pivot_offset = Vector2(_dock.size.x * 0.5, _dock.size.y)
	_dock.scale = sv
	_dock.position = Vector2((vs.x - _dock.size.x) * 0.5, vs.y - _dock.size.y - 12.0)

	# Sol sekmeli çekmece (üst bar ile alt boşluk arasında)
	var top_y: float = top_bottom + 10.0
	var dock_h: float = maxf(_dock.size.y, 44.0) * s
	var bottom_margin: float = maxf(68.0, dock_h + 22.0)
	var avail_h: float = maxf(180.0, vs.y - top_y - bottom_margin)
	var max_unscaled_h: float = avail_h / s
	var side_w := 304.0
	_side.scale = sv
	_side.position = Vector2(14.0, top_y)
	_side.custom_minimum_size = Vector2(side_w, 0.0)
	var want_h: float = _side_vb.get_combined_minimum_size().y + 84.0
	var panel_h: float = clampf(want_h, 190.0, max_unscaled_h)
	_side.size = Vector2(side_w, panel_h)

	_tip.pivot_offset = Vector2.ZERO
	_tip.scale = sv


# ---------------------------------------------------------------- giriş / çıkış

## Tezgâh görünümüne geçer. PC kasası tezgâha yatırılır, birinci şahıs kartlar gizlenir.
func enter() -> bool:
	if state != "off":
		return false
	var d = Game.bench_device
	var p = Game.player
	if not is_instance_valid(d) or p == null or not Game.started or Game.phase != "day" or Game.ui_modal or Game.is_carrying():
		return false
	if device != d:
		_bind(d)
	if p.held != null:
		var h = p.release_held()
		if h.is_tool():
			_stash_tool = h
			h.reparent(self, false)
			h.visible = false
		else:
			tray_add(h)
	if kind == "pc":
		_stand_xf = device.global_transform
		var desk_y: float = float(get_parent().get("DESK_Y")) if get_parent().get("DESK_Y") != null else 0.75
		var cw: float = float(device.case_w) if "case_w" in device else PC_SCRIPT.W
		var ch: float = float(device.case_h) if "case_h" in device else PC_SCRIPT.H
		var flat_basis := _stand_xf.basis * Basis(Vector3(0.0, 0.0, 1.0), PI * 0.5)
		var flat_pos := Vector3(PC_FLAT_X, desk_y + 0.008 + cw * 0.5, PC_MAT_Z + ch * 0.5)
		_flat_xf = Transform3D(flat_basis, flat_pos)
		_laid_flat = true
		_case_from_xf = _stand_xf
		_case_goal_xf = _flat_xf
		_case_t = 0.0
		if device.has_method("set_flat_mode"):
			device.set_flat_mode(true)
	if is_instance_valid(device):
		_set_tag_active(device, false)
	if not _orbit_ready:
		_init_orbit()
	_from_xf = p.cam.global_transform
	_from_fov = p.cam.fov
	cam.global_transform = _from_xf
	cam.fov = _from_fov
	cam.make_current()
	state = "entering"
	_t = 0.0
	Game.bench_active = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	p.target = null
	p.hint = ""
	if Game.hud and Game.hud.has_method("set_bench_mode"):
		Game.hud.set_bench_mode(true)
	else:
		if Game.hud and Game.hud.crosshair:
			Game.hud.crosshair.visible = false
		if Game.hud and Game.hud.corner_hint:
			Game.hud.corner_hint.visible = false
	_ui_root.visible = true
	_sig = ""
	_refresh_side(true)
	_layout_ui()
	call_deferred("_layout_ui")
	Game.sfx.click()
	return true


## Tezgâh modunda PC'yi yatırır veya tekrar dik konuma getirir (`F` tuşu veya Üst Bar düğmesi).
func toggle_lay_flat() -> void:
	if kind != "pc" or not is_instance_valid(device) or state == "off" or state == "leaving":
		return
	_laid_flat = not _laid_flat
	_case_from_xf = device.global_transform
	_case_goal_xf = _flat_xf if _laid_flat else _stand_xf
	_case_t = 0.0
	if device.has_method("set_flat_mode"):
		device.set_flat_mode(_laid_flat)
	_frame_camera(false)
	_sig = ""
	Game.sfx.click()


## Birinci şahıs görünüme döner. immediate: geçiş animasyonsuz (cihaz gitti, gün bitti vb.).
func exit(immediate := false) -> void:
	if state == "off":
		return
	if state == "leaving" and not immediate:
		return
	cancel_selection()
	tool = null
	_rmb = false
	_mmb = false
	_touches.clear()
	_touch_pos = Vector2(-1, -1)
	_touch_was_pinch = false
	_touch_pinch_dist = 0.0
	hovered = {}
	_clear_hl()
	_tip.visible = false
	_clear_glow()
	if kind == "pc" and is_instance_valid(device) and _laid_flat:
		if device.has_method("set_flat_mode"):
			device.set_flat_mode(false, immediate)
		if not immediate and Game.bench_device == device:
			_case_from_xf = device.global_transform
			_case_goal_xf = _stand_xf
			_case_t = 0.0
	if immediate or Game.player == null:
		_finish_exit(not Game.ui_modal and Game.phase == "day")
		return
	state = "leaving"
	_t = 0.0
	_from_xf = cam.global_transform
	_from_fov = cam.fov
	Game.sfx.click()


func _finish_exit(capture: bool) -> void:
	if is_instance_valid(device):
		if kind == "pc":
			if device.has_method("set_flat_mode"):
				device.set_flat_mode(false, true)
			if _laid_flat and Game.bench_device == device:
				device.global_transform = _stand_xf
		_set_tag_active(device, true)
	_laid_flat = false
	_case_t = 1.0
	state = "off"
	Game.bench_active = false
	_ui_root.visible = false
	var p = Game.player
	if p:
		p.cam.make_current()
		if is_instance_valid(_stash_tool) and p.held == null:
			_stash_tool.visible = true
			p.pick_up(_stash_tool)
	_stash_tool = null
	if Game.hud and Game.hud.has_method("set_bench_mode"):
		Game.hud.set_bench_mode(false)
	else:
		if Game.hud and Game.hud.crosshair:
			Game.hud.crosshair.visible = true
		if Game.hud and Game.hud.corner_hint:
			Game.hud.corner_hint.visible = true
	if capture and Game.started:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_tag_active(dev: Node, on: bool) -> void:
	if not is_instance_valid(dev):
		return
	var tag = dev.get_node_or_null("TicketTag")
	if not tag:
		return
	tag.visible = on
	for c in tag.get_children():
		if c is CollisionObject3D:
			if not on:
				if not c.has_meta("_saved_layer"):
					c.set_meta("_saved_layer", c.collision_layer)
				c.collision_layer = 0
			else:
				c.collision_layer = int(c.get_meta("_saved_layer", 2))


# ---------------------------------------------------------------- yörünge

func _init_orbit() -> void:
	_orbit_ready = true
	_frame_camera(true)


func _frame_camera(snap: bool) -> void:
	if not is_instance_valid(device):
		return
	var ref_xf: Transform3D = _flat_xf if (kind == "pc" and _laid_flat) else (_stand_xf if kind == "pc" else device.global_transform)
	var b: Basis = ref_xf.basis
	var ch: float = float(device.case_h) if (kind == "pc" and "case_h" in device) else PC_SCRIPT.H
	var local_c := Vector3(0.02, ch * 0.5, 0.0) if kind == "pc" else Vector3(0.0, 0.23, 0.0)
	_d_min = 0.28
	_d_max = 1.65
	_pan_max = 0.55
	var pan_goal := Vector3.ZERO
	match kind:
		"pc":
			if _laid_flat:
				_dist_goal = 1.10
				_elev = 1.02
				_yaw_goal = 0.0
				pan_goal = Vector3(0.22, 0.0, 0.01)
			else:
				_dist_goal = 0.95
				_elev = 0.34
				var f: Vector3 = b * Vector3(1, 0, 0)
				_yaw_goal = atan2(f.x, f.z)
				var tt: Vector3 = _tray.global_position - (ref_xf * local_c)
				tt.y = 0.0
				pan_goal = tt.limit_length(0.12)
		"laptop":
			local_c = Vector3(0, 0.07, 0)
			_d_min = 0.22
			_d_max = 1.0
			_pan_max = 0.35
			_dist_goal = 0.58
			_elev = 0.85
			_yaw_goal = 0.0
			pan_goal = Vector3(0.0, 0.0, 0.08)
		_:
			local_c = Vector3(0, 0.005, 0)
			_d_min = 0.12
			_d_max = 0.65
			_pan_max = 0.22
			_dist_goal = 0.34
			_elev = 1.02
			_yaw_goal = 0.0
			pan_goal = Vector3(0.06, 0.0, 0.0)
	_center = ref_xf * local_c
	_pan = pan_goal
	if snap:
		_yaw = _yaw_goal
		_dist = _dist_goal


func _orbit_xf() -> Transform3D:
	var c := _center + _pan
	var dir := Vector3(cos(_elev) * sin(_yaw), sin(_elev), cos(_elev) * cos(_yaw))
	var d := _dist
	var q := PhysicsRayQueryParameters3D.create(c, c + dir * d, 1, _excl)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r:
		d = maxf(0.12, (r.position - c).length() - 0.05)
	var pos := c + dir * d
	return Transform3D(Basis.looking_at(-dir, Vector3.UP), pos)


func _process(delta: float) -> void:
	_prune_tray()
	if state == "off":
		return
	var why := _force_exit_reason()
	if why != "":
		_report_exit(why)
		exit(true)
		return
	if _case_t < 1.0 and is_instance_valid(device):
		_case_t = minf(1.0, _case_t + delta / TRANS)
		var ce := smoothstep(0.0, 1.0, _case_t)
		device.global_transform = _case_from_xf.interpolate_with(_case_goal_xf, ce)
	var k := 1.0 - exp(-14.0 * delta)
	_yaw = lerp_angle(_yaw, _yaw_goal, k)
	_dist = lerpf(_dist, _dist_goal, k)
	if state == "on":
		var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if mv != Vector2.ZERO:
			var right := Vector3(cos(_yaw), 0, -sin(_yaw))
			var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
			_pan += (right * mv.x - fwd * mv.y) * 0.4 * delta * (_dist / 0.8)
			_pan = _pan.limit_length(_pan_max)
	match state:
		"entering":
			_t = minf(1.0, _t + delta / TRANS)
			var e := smoothstep(0.0, 1.0, _t)
			cam.global_transform = _from_xf.interpolate_with(_orbit_xf(), e)
			cam.fov = lerpf(_from_fov, BENCH_FOV, e)
			if _t >= 1.0:
				state = "on"
		"leaving":
			_t = minf(1.0, _t + delta / TRANS)
			var e := smoothstep(0.0, 1.0, _t)
			var p = Game.player
			cam.global_transform = _from_xf.interpolate_with(p.cam.global_transform, e)
			cam.fov = lerpf(_from_fov, p.cam.fov, e)
			if _t >= 1.0:
				_finish_exit(not Game.ui_modal and Game.phase == "day")
		"on":
			cam.global_transform = _orbit_xf()
			if Game.pc_service == null or not Game.pc_service.is_open():
				_update_hover()
				_update_selected()
				_update_glow()
			_sig_t -= delta
			if _sig_t <= 0.0:
				_sig_t = 0.15
				_refresh_side(false)


# ---------------------------------------------------------------- girdi

func _input(event: InputEvent) -> void:
	if Game.pc_service != null and Game.pc_service.is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("bench"):
			if state == "off":
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Game.ui_modal and Game.bench_device != null and not Game.is_carrying():
					if enter():
						get_viewport().set_input_as_handled()
			elif state == "on":
				exit()
				get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") and state != "off":
			get_viewport().set_input_as_handled()
			if selected != null or tool != null:
				cancel_selection()
				tool = null
				_sig = ""
			elif state == "on":
				exit()


func _unhandled_input(event: InputEvent) -> void:
	if state != "on" or (Game.pc_service != null and Game.pc_service.is_open()):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			_yaw_goal += PI / 2.0
		elif event.physical_keycode == KEY_E:
			_yaw_goal -= PI / 2.0
		elif event.physical_keycode == KEY_F:
			toggle_lay_flat()
	elif event is InputEventScreenTouch:
		_handle_touch(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_handle_drag(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					if not _over_gui():
						click(_resolve(_ray_hit(event.position)))
				else:
					if selected != null and not _over_gui():
						var res := _resolve(_ray_hit(event.position))
						if res.get("kind", "") in ["slot", "installed"]:
							install_selected(res.slot)
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_rmb = true
					_rmb_moved = 0.0
				else:
					_rmb = false
					if _rmb_moved < 8.0 and (selected != null or tool != null):
						cancel_selection()
						tool = null
						_sig = ""
			MOUSE_BUTTON_MIDDLE:
				_mmb = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_dist_goal = clampf(_dist_goal * 0.88, _d_min, _d_max)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_dist_goal = clampf(_dist_goal / 0.88, _d_min, _d_max)
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if _rmb:
			_rmb_moved += event.relative.length()
			var sens: float = 0.004 * Settings.sensitivity
			var dy: float = event.relative.y * (-1.0 if Settings.invert_y else 1.0)
			_yaw -= event.relative.x * sens
			_yaw_goal = _yaw
			_elev = clampf(_elev + dy * sens, deg_to_rad(4.0), deg_to_rad(88.0))
		elif _mmb:
			var s := _dist * 0.0012
			var right := Vector3(cos(_yaw), 0, -sin(_yaw))
			var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
			_pan += (-right * event.relative.x + fwd * event.relative.y) * s
			_pan = _pan.limit_length(_pan_max)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_touch_start = event.position
			_touch_pos = event.position
			_touch_moved = 0.0
			_touch_was_pinch = false
			_touch_pinch_dist = 0.0
		elif _touches.size() >= 2:
			_touch_was_pinch = true
			_touch_pos = Vector2(-1, -1)
			var pts := _touches.values()
			_touch_pinch_dist = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
	else:
		var was_single := _touches.size() == 1 and not _touch_was_pinch
		_touches.erase(event.index)
		if was_single:
			if _touch_moved < 16.0:
				click(_resolve(_ray_hit(event.position)))
			elif selected != null:
				var res := _resolve(_ray_hit(event.position))
				if res.get("kind", "") in ["slot", "installed"]:
					install_selected(res.slot)
		if _touches.is_empty():
			_touch_pos = Vector2(-1, -1)
			_touch_was_pinch = false
			_touch_pinch_dist = 0.0
		elif _touches.size() < 2:
			_touch_pinch_dist = 0.0


func _handle_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		_touch_was_pinch = true
		var pts := _touches.values()
		var d := (pts[0] as Vector2).distance_to(pts[1] as Vector2)
		if _touch_pinch_dist > 1.0 and d > 1.0:
			_dist_goal = clampf(_dist_goal * (_touch_pinch_dist / d), _d_min, _d_max)
		_touch_pinch_dist = d
	elif _touches.size() == 1 and not _touch_was_pinch:
		_touch_moved += event.relative.length()
		_touch_pos = event.position
		if selected == null:
			var sens: float = 0.005 * Settings.sensitivity
			var dy: float = event.relative.y * (-1.0 if Settings.invert_y else 1.0)
			_yaw -= event.relative.x * sens
			_yaw_goal = _yaw
			_elev = clampf(_elev + dy * sens, deg_to_rad(4.0), deg_to_rad(88.0))


# ---------------------------------------------------------------- fare ışını & vurgu

func _ray_hit(mp: Vector2) -> Dictionary:
	var from := cam.project_ray_origin(mp)
	var to := from + cam.project_ray_normal(mp) * 4.0
	var ex: Array = []
	if Game.player:
		ex.append(Game.player.get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, to, 3, ex)
	q.collide_with_areas = true
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r:
		r["ray_from"] = from
		r["ray_dir"] = cam.project_ray_normal(mp)
	else:
		r = {"ray_from": from, "ray_dir": cam.project_ray_normal(mp)}
	return r


func _resolve(hit: Dictionary) -> Dictionary:
	var c = hit.get("collider")
	if c == null or not is_instance_valid(c):
		return {}
	if c.has_method("is_tool") and c.is_tool() and c.visible:
		return {"kind": "tool", "node": c, "tool": c}
	if device == null or not is_instance_valid(device):
		return {}
	if "part_type" in c and c.has_method("is_tool") and not c.is_tool():
		if c.slot != null and device.is_ancestor_of(c):
			return {"kind": "installed", "node": c, "slot": c.slot, "part": c}
		if tray_parts.has(c):
			return {"kind": "tray", "node": c, "part": c}
		return {}
	if "accepts" in c and "pc" in c:
		if device.is_ancestor_of(c):
			return {"kind": "installed" if c.part != null else "slot", "node": c, "slot": c, "part": c.part}
		return {}
	if not device.is_ancestor_of(c):
		return {}
	if c.has_method("interact") and "action" in c:
		return {"kind": "widget", "node": c}
	return {"kind": "body", "node": c}


func _mp() -> Vector2:
	if mouse_override.x >= 0.0:
		return mouse_override
	if _touch_pos.x >= 0.0:
		return _touch_pos
	return get_viewport().get_mouse_position()


func _over_gui() -> bool:
	return mouse_override.x < 0.0 and get_viewport().gui_get_hovered_control() != null


func _update_hover() -> void:
	if _over_gui() or _rmb or _mmb:
		hovered = {}
		_clear_hl()
		_tip.visible = false
		return
	var hit := _ray_hit(_mp())
	hovered = _resolve(hit)
	hovered["hit"] = hit
	var txt := _tooltip_for(hovered)
	_set_hl(hovered)
	if txt.is_empty():
		_tip.visible = false
		return
	_tip_title.text = txt[0]
	_tip_spec.text = txt[1]
	_tip_spec.visible = txt[1] != ""
	_tip_sub.text = txt[2]
	_tip_sub.add_theme_color_override("font_color", txt[3])
	_tip_sub.visible = txt[2] != ""
	_tip_accent.color = txt[3]
	_tip.visible = true
	_tip.reset_size()
	var vs := get_viewport().get_visible_rect().size
	var tip_sz := _tip.size * Settings.hud_scale
	var mp := _mp() + Vector2(20, 24)
	_tip.position = Vector2(clampf(mp.x, 0, vs.x - tip_sz.x - 4), clampf(mp.y, 0, vs.y - tip_sz.y - 4))


func _clear_hl() -> void:
	for mi in _hl_meshes:
		if is_instance_valid(mi):
			mi.material_overlay = null
	_hl_meshes.clear()
	if _hl:
		_hl.visible = false


func _apply_rim(target: Node, mat_key: String) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var sm: Material = _hl_rim_mats.get(mat_key, _hl_rim_mats.get("cyan"))
	var meshes := target.find_children("*", "MeshInstance3D", true, false)
	var applied := 0
	for m in meshes:
		if m is MeshInstance3D and m.visible and m.name != "Crack" and m.name != "Ghost":
			m.material_overlay = sm
			_hl_meshes.append(m)
			applied += 1
	return applied > 0


func _place_brackets(node: Node, col: Color) -> void:
	if node == null or not is_instance_valid(node):
		return
	var cs: CollisionShape3D = null
	for c in node.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			cs = c
			break
	if cs == null:
		return
	var sz: Vector3 = (cs.shape as BoxShape3D).size * 1.04
	var gt: Transform3D = cs.global_transform
	_hl.global_transform = Transform3D(gt.basis.scaled_local(sz), gt.origin)
	_hl_mat.albedo_color = Color(col.r, col.g, col.b, 0.92)
	_hl.visible = true


func _hl_key(res: Dictionary) -> String:
	var k: String = res.get("kind", "")
	if selected != null and (k == "slot" or k == "installed"):
		var r := can_install(res.slot, selected)
		if not r.ok:
			return "red"
		return "amber" if str(r.get("severity", "ok")) == "warn" else "green"
	if k == "installed" and res.get("part") != null:
		var pt = res.part
		if ("seated" in pt and not pt.seated) or ("bent_pins" in pt and pt.bent_pins) or ("bad_caps" in pt and pt.bad_caps):
			return "amber"
		if device != null and device.has_method("slot_screwed") and res.get("slot") != null and device.slot_screwed(res.slot.name):
			return "amber"
		if Game.has_upgrade("multimeter") and (pt.broken or ("vram_bad" in pt and pt.vram_bad)):
			return "amber"
	if k == "tool" and tool == res.get("tool"):
		return "amber"
	if k == "tray" and res.get("part") != null:
		var pt = res.part
		var orig: String = str(pt.get("origin")) if "origin" in pt else ""
		if orig == "stock":
			return "green"
		if "is_test_part" in pt and pt.is_test_part:
			return "cyan"
		return "amber"
	return "cyan"


## Sarı kutucuk yerine: parçalar/aletlerde şık Fresnel kenar parlaması, boş yuvalarda ve cam kapakta L-köşeler.
func _set_hl(res: Dictionary) -> void:
	_clear_hl()
	var k: String = res.get("kind", "")
	if k == "" or k == "body":
		return
	if (k == "installed" or k == "slot") and res.get("slot") != null:
		if not _slot_open(res.slot) and tool == null and selected == null:
			return
	var key := _hl_key(res)
	var col_map := {"cyan": HL_CYAN, "green": T.GOOD, "amber": T.ACCENT, "red": T.BAD}
	var bcol: Color = col_map.get(key, HL_CYAN)
	if k == "installed":
		var target = res.part if res.get("part") != null else res.get("node")
		if res.get("part") != null and _apply_rim(target, key):
			return
		_place_brackets(res.get("node"), bcol)
		return
	if k == "tray" or k == "tool":
		if _apply_rim(res.get("node"), key):
			return
		_place_brackets(res.get("node"), bcol)
		return
	if k == "widget":
		var wn: Node = res.get("node")
		var parent: Node = wn.get_parent() if wn else null
		var pivot = device.get("panel_pivot") if (device != null and "panel_pivot" in device) else null
		if parent != null and parent != device and parent != pivot:
			var meshes := parent.find_children("*", "MeshInstance3D", true, false)
			if meshes.size() > 0 and meshes.size() <= 8 and _apply_rim(parent, key):
				return
		_place_brackets(wn, bcol)
		return
	if k == "slot":
		_place_brackets(res.get("node"), bcol)


## Parçanın teknik özelliklerini tek satırda özetler (soket, DDR, watt, uzunluk, TDP, kapasite).
static func _spec_text(d: PartDef) -> String:
	if d == null:
		return ""
	var s := d.specs
	var c := d.compat
	var out: Array[String] = []
	match d.category:
		"mobo":
			if c.has("socket"): out.append(str(c.socket))
			if c.has("ram_type"): out.append(str(c.ram_type))
			if c.has("form_factor"): out.append(str(c.form_factor))
			if c.has("ram_slots"): out.append("%d RAM" % int(c.ram_slots))
			if c.has("m2_slots"): out.append("%d M.2" % int(c.m2_slots))
		"cpu":
			if s.has("socket"): out.append(str(s.socket))
			if s.has("cores"): out.append("%d Çekirdek" % int(s.cores))
			if s.has("tdp"): out.append("%dW TDP" % int(s.tdp))
			out.append("iGPU" if bool(s.get("igpu", false)) else "GPU gerekir")
		"cooler":
			if str(s.get("type", "")) == "aio" and int(s.get("radiator_mm", 0)) > 0:
				out.append("%dmm AIO" % int(s.radiator_mm))
			elif s.has("height_mm"):
				out.append("%dmm" % int(s.height_mm))
			if s.has("tdp"): out.append("%dW TDP" % int(s.tdp))
		"ram":
			if s.has("gb"): out.append("%d GB" % int(s.gb))
			if s.has("type"): out.append(str(s.type))
			if s.has("mhz"): out.append("%d MHz" % int(s.mhz))
		"gpu":
			if s.has("vram"): out.append("%d GB VRAM" % int(s.vram))
			if s.has("tdp"): out.append("%dW" % int(s.tdp))
			if s.has("length_mm"): out.append("%dmm" % int(s.length_mm))
			var pins: Array = c.get("pcie_pins", [])
			if not pins.is_empty():
				out.append("+".join(pins.map(func(x): return str(x).to_upper())))
		"psu":
			if s.has("watts"): out.append("%dW" % int(s.watts))
			if s.has("efficiency"): out.append(str(s.efficiency))
			var conns: Dictionary = c.get("connectors", {})
			if int(conns.get("12vhpwr", 0)) > 0:
				out.append("12VHPWR")
		"ssd", "nvme", "hdd":
			if s.has("gb"): out.append("%d GB" % int(s.gb))
			if s.has("iface"): out.append(str(s.iface))
		"fan":
			if s.has("size_mm"): out.append("%dmm" % int(s.size_mm))
			if bool(s.get("rgb", false)): out.append("RGB")
		"lap_ram":
			if s.has("gb"): out.append("%d GB" % int(s.gb))
			if s.has("type"): out.append(str(s.type))
			if s.has("mhz"): out.append("%d MHz" % int(s.mhz))
		"lap_ssd":
			if s.has("gb"): out.append("%d GB" % int(s.gb))
			if s.has("iface"): out.append(str(s.iface))
		"lap_bat":
			if s.has("wh"): out.append("%d Wh" % int(s.wh))
			if s.has("volt"): out.append("%.1fV" % float(s.volt))
		"lap_scr":
			if s.has("inch"): out.append("%.1f\"" % float(s.inch))
			if s.has("res"): out.append(str(s.res))
			if s.has("panel"): out.append(str(s.panel))
		"tel_bat":
			if s.has("mah"): out.append("%d mAh" % int(s.mah))
			if s.has("volt"): out.append("%.2fV" % float(s.volt))
		"tel_scr":
			if s.has("panel"): out.append(str(s.panel))
		"tel_port":
			if s.has("port"): out.append(str(s.port))
	return " · ".join(out)


func _part_spec_text(part, slot = null) -> String:
	if part == null:
		return ""
	var d: PartDef = part.def() if part.has_method("def") else DB.parts.def_for(part.part_type, part.tier)
	var base := _spec_text(d)
	var tags: Array[String] = []
	if "seated" in part and not part.seated:
		tags.append("Oturmamış!")
	if "bent_pins" in part and part.bent_pins:
		tags.append("Eğik pin!")
	if "bad_caps" in part and part.bad_caps:
		tags.append("Şişmiş kondansatör!")
	if "is_test_part" in part and part.is_test_part:
		tags.append("TEST PARÇASI")
	elif part.has_method("origin_tag"):
		var otag := str(part.origin_tag())
		if otag != "" and (slot == null or ( "origin" in part and str(part.origin) == "stock")):
			tags.append(otag)
	if slot != null and device != null and device.has_method("slot_screwed") and device.slot_screwed(slot.name):
		tags.append("Vidalı")
	if Game.has_upgrade("smart_usb") and part.part_type in ["ssd", "nvme", "hdd"] and "health" in part:
		tags.append("SMART %%%d" % int(part.health))
	if Game.has_upgrade("multimeter"):
		if part.broken:
			tags.append("ARIZALI!")
		elif "vram_bad" in part and part.vram_bad:
			tags.append("VRAM Hatası!")
		else:
			tags.append("Sağlam ✓")
	if tags.is_empty():
		return base
	var t_str := " · ".join(tags)
	return t_str if base.is_empty() else (base + "\n" + t_str)


static func _tool_short_desc(tt: String) -> String:
	match tt:
		"screwdriver": return "Kapak/parça vidalarını söker, CPU pinlerini düzeltir"
		"paste": return "Boş CPU soketine taze macun sürer"
		"air": return "Kasa ve fan tozunu temizler"
		"ipa": return "Sıvı teması ve oksit temizleyici"
		"psu_tester": return "PSU voltaj ve kablo çıkışlarını ölçer"
		"multimeter": return "Parça/anakart voltaj & kondansatör ölçümü"
		"post_card": return "Ucuz anakartlarda POST hata kodunu gösterir"
		"thermal_cam": return "Sıcaklık, toz % ve fan taraması"
		"ram_usb": return "RAM yuvaları ve XMP testi"
		"smart_usb": return "Disk SMART sağlığı & doluluk taraması"
		"antivirus_usb": return "Virüs taraması ve temizliği"
		"install_usb": return "Format, bilgiOS kurulumu & BIOS güncelleme"
	return "Tezgâh tamir aleti"


func _tooltip_for(res: Dictionary) -> Array:
	var k: String = res.get("kind", "")
	if k == "":
		return []
	var click := "[Sol tık]"
	if k == "tool" and res.get("tool") != null:
		var tnode = res.tool
		var sel_this: bool = tool == tnode
		return [tnode.display_name, _tool_short_desc(str(tnode.tool_type)), ("Bırak  " if sel_this else "Eline Al  ") + click, T.ACCENT if sel_this else HL_CYAN]
	if selected != null:
		match k:
			"slot", "installed":
				var r := can_install(res.slot, selected)
				var sp := _part_spec_text(selected)
				var title := "%s" % PM.type_name(res.slot.accepts)
				if r.ok:
					if str(r.get("severity", "ok")) == "warn" and str(r.get("reason", "")) != "":
						return [title, sp, "⚠ %s  ·  Tak %s" % [str(r.reason), click], T.ACCENT]
					return [title, sp, "Tak: %s  %s" % [selected.display_name, click], T.GOOD]
				return [title, sp, str(r.reason), T.BAD]
			"tray":
				return [res.part.display_name, _part_spec_text(res.part), "Seçimi bunla değiştir  " + click, HL_CYAN]
		return []
	if tool != null:
		var target = res.get("slot")
		if k == "widget" and tool.tool_type == "screwdriver":
			var wh := str(res.node.get_hint(self))
			if wh != "":
				return [wh.replace("[E]", "").strip_edges(), "", click, T.ACCENT]
		if k in ["slot", "installed", "widget", "body"]:
			return [tool.display_name, "", str(device.tool_hint(tool, target)).replace("[E]", click).replace("  ", " "), HL_CYAN]
		return []
	match k:
		"installed":
			if not _slot_open(res.slot):
				return []
			if "seated" in res.part and not res.part.seated:
				return [res.part.display_name, _part_spec_text(res.part, res.slot), "Yerine oturt  " + click, T.ACCENT]
			if device.has_method("slot_screwed") and device.slot_screwed(res.slot.name):
				var hint := "Vidayı otomatik sök & Sök  " if Game.has_upgrade("auto_screw") else "Önce vidasını sök!  "
				return [res.part.display_name, _part_spec_text(res.part, res.slot), hint + click, T.ACCENT]
			return [res.part.display_name, _part_spec_text(res.part, res.slot), "Sök  " + click, HL_CYAN]
		"slot":
			if not _slot_open(res.slot):
				return []
			return ["Boş yuva: %s" % PM.type_name(res.slot.accepts), "", "Tepsiden veya Stoktan parça seç", T.MUTED]
		"tray":
			var t_col := HL_CYAN
			if "origin" in res.part:
				if str(res.part.origin) == "stock":
					t_col = T.GOOD
				elif str(res.part.origin) == "customer":
					t_col = T.ACCENT
			return [res.part.display_name, _part_spec_text(res.part), "Seç  " + click, t_col]
		"widget":
			var h := str(res.node.get_hint(self))
			if h == "":
				return []
			return [h.replace("[E]", "").strip_edges(), "", click, HL_CYAN]
	return []


# ---------------------------------------------------------------- eylemler (fare tıklaması ve test aynı işlevleri çağırır)

func click(res: Dictionary) -> void:
	if res.is_empty():
		return
	var k: String = res.kind
	if k == "tool" and res.get("tool") != null:
		select_tool(res.tool)
		Game.sfx.click()
		return
	if selected != null:
		if k == "slot" or k == "installed":
			install_selected(res.slot)
		elif k == "tray":
			select_part(res.part)
		return
	if tool != null:
		if k == "widget" and tool.tool_type == "screwdriver":
			res.node.interact(self)
			_sig = ""
		elif k == "slot" or k == "installed":
			use_tool(tool, res.slot)
		elif k == "widget" or k == "body":
			use_tool(tool, null)
		return
	match k:
		"installed":
			remove_part(res.slot)
		"tray":
			select_part(res.part)
		"widget":
			res.node.interact(self)
			Game.sfx.click()
		"slot":
			Game.msg("Önce tepsiden veya Stok sekmesinden parça seç.", Color(1, 0.8, 0.4))


## Yuva şu an erişilebilir mi (kapak açık, cihaz kapalı)?
func _slot_open(slot) -> bool:
	var d = slot.pc
	return d.slot_open(slot) if d.has_method("slot_open") else d.panel_open


## PC için standart kasa durumu. Anakart yuvası henüz eklenmemiş eski kasalarda yerleşik AM4 anakart varsayılır.
func _pc_case_state() -> Dictionary:
	var st := Compatibility.case_state_of(device)
	if st.mobo == null and device != null and "slots" in device and not device.slots.has("mobo"):
		st.mobo = DB.parts.get_def("mobo_am4_matx")
	return st


## Uyumluluk kontrolü: PC için Compatibility.check(), laptop/telefon için yuva türü denetimi.
func can_install(slot, part) -> Dictionary:
	if slot == null or part == null:
		return {"ok": false, "reason": "Geçersiz hedef", "code": "invalid", "severity": "block"}
	if slot.part != null:
		return {"ok": false, "reason": "Yuva dolu", "code": "occupied", "severity": "block"}
	if not _slot_open(slot):
		return {"ok": false, "reason": "Yuvaya erişemiyorsun: önce kapağı aç", "code": "closed", "severity": "block"}
	if kind == "pc":
		var pdef: PartDef = part.def() if part.has_method("def") else DB.parts.def_for(part.part_type, part.tier)
		return Compatibility.check(slot, pdef, _pc_case_state())
	var extra: Array = slot.get("accepts_extra") if "accepts_extra" in slot else []
	if slot.accepts != part.part_type and not extra.has(part.part_type):
		return {"ok": false, "reason": "Uyumsuz: bu yuva %s ister" % PM.type_name(slot.accepts), "code": "wrong_slot", "severity": "block"}
	return {"ok": true, "reason": "", "code": "ok", "severity": "ok"}


## Takılı parçayı yuvadan söküp tepsiye koyar. Oturmamış RAM varsa önce yerine oturtur. Parçayı döndürür (olmadıysa null).
func remove_part(slot):
	if slot == null or slot.part == null:
		return null
	if not _slot_open(slot):
		Game.msg("Önce kapağı aç.", Color(1, 0.8, 0.4))
		return null
	if "seated" in slot.part and not slot.part.seated:
		slot.part.seated = true
		slot.part.rotation_degrees = Vector3.ZERO
		Game.sfx.click()
		device.on_parts_changed()
		Game.msg("RAM yuvasına tam oturtuldu!", Color(0.5, 1.0, 0.5))
		_sig = ""
		return null
	if device.has_method("can_remove_reason"):
		var why := str(device.can_remove_reason(slot.name))
		if why != "":
			Game.sfx.error()
			Game.msg(why, Color(1.0, 0.72, 0.35))
			return null
	var part = slot.part
	slot.detach()
	if part.has_method("mark_pulled_from"):
		part.mark_pulled_from(device)
	tray_add(part)
	_ever_removed = true
	Game.sfx.pickup()
	return part


## Parçayı tepsiye koyar (elden, raftan, yuvadan).
func tray_add(part) -> bool:
	if part == null or device == null or (part.has_method("is_tool") and part.is_tool()):
		return false
	if part.get_parent():
		part.reparent(_tray, false)
	else:
		_tray.add_child(part)
	part.slot = null
	part.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	part.freeze = true
	part.linear_velocity = Vector3.ZERO
	part.angular_velocity = Vector3.ZERO
	part.collision_layer = 2
	part.collision_mask = 0
	part.visible = true
	if not tray_parts.has(part):
		tray_parts.append(part)
	_layout_tray()
	_sig = ""
	return true


## Doğrudan dükkân stoğundan 1 parça alıp tepsiye (ve seçime) koyar.
func take_from_stock(sku_id: String, cheap := false, auto_select := true):
	if device == null or state == "off":
		return null
	var id: String = DB.parts.resolve_id(sku_id)
	var part = null
	if cheap:
		if not Game.take_stock_cheap_sku(id):
			Game.sfx.error()
			Game.msg("Muadil %s stokta yok!" % PM.display_name_sku(id), Color(1.0, 0.5, 0.4))
			return null
		part = PART.new().setup_sku(id, false)
		part.make_cheap()
	else:
		if not Game.take_stock_sku(id):
			Game.sfx.error()
			Game.msg("%s stokta yok!" % PM.display_name_sku(id), Color(1.0, 0.5, 0.4))
			return null
		part = PART.new().setup_sku(id, Game.take_was_dud)
	part.origin = "stock"
	part.origin_ticket = 0
	tray_add(part)
	Game.sfx.pickup()
	if auto_select:
		select_part(part)
	_sig = ""
	return part


## Tepsideki sağlam (ve test olmayan) parçayı dükkân stoğuna koyar (müşteri parçasıysa cebe atar).
func return_tray_part(part) -> bool:
	return _store_tray_part(part, false)


## Müşteriden sökülen sağlam parçayı kendi dükkân stoğuna alır (teslimde yakalanma riski taşır).
func pocket_tray_part(part) -> bool:
	return _store_tray_part(part, true)


func _store_tray_part(part, as_pocket: bool) -> bool:
	if part == null or not tray_parts.has(part):
		return false
	if part.broken:
		Game.sfx.error()
		Game.msg("Bozuk parça stoğa geri konmaz (hurdaya atabilirsin).", Color(1.0, 0.72, 0.35))
		return false
	if "is_test_part" in part and part.is_test_part:
		tray_parts.erase(part)
		if selected == part:
			cancel_selection()
		part.queue_free()
		_layout_tray()
		_sig = ""
		return true
	var from_cust: bool = as_pocket or ("origin" in part and str(part.origin) == "customer")
	if selected == part:
		cancel_selection()
	tray_parts.erase(part)
	var raw_sku: String = part.sku if not part.sku.is_empty() else Game.sku(part.part_type, part.tier)
	var id: String = DB.parts.resolve_id(raw_sku)
	if "cheap" in part and part.cheap:
		Game.add_stock_cheap_sku(id, 1)
	else:
		Game.add_stock_sku(id, 1)
	if from_cust:
		Game.stats["stolen_parts"] = int(Game.stats.get("stolen_parts", 0)) + 1
		Game.sfx.coin()
		Game.msg("%s kendi stoğuna atıldı! (Teslimde müşteri fark edebilir!)" % part.display_name, Color(1.0, 0.78, 0.25))
	else:
		Game.sfx.click()
		Game.msg("%s dükkân stoğuna geri kondu." % part.display_name, Color(0.65, 0.9, 1.0))
	part.queue_free()
	_layout_tray()
	_sig = ""
	return true


## Tepsideki parçayı hurdaya atar (sağlam orijinal/ikinci el parça ise %40 hurda geliri öder).
func scrap_tray_part(part) -> bool:
	if part == null or not tray_parts.has(part):
		return false
	if selected == part:
		cancel_selection()
	tray_parts.erase(part)
	var is_test: bool = "is_test_part" in part and part.is_test_part
	if not is_test and not part.broken:
		var val: int = maxi(5, int(part.value() * 0.4))
		Game.add_money(val)
		Game.cash_sound()
		if Game.hud:
			Game.hud.pop_money(val)
		Game.msg("%s hurdaya satıldı (+%d TL)." % [part.display_name, val], Color(0.6, 1.0, 0.6))
	else:
		Game.sfx.click()
		Game.msg("%s atıldı." % part.display_name, Color(0.8, 0.85, 0.9))
	part.queue_free()
	_layout_tray()
	_sig = ""
	return true


func select_part(part) -> bool:
	if part == null or not tray_parts.has(part):
		return false
	cancel_selection()
	tool = null
	selected = part
	part.collision_layer = 0
	_tint_cur = null
	_layout_tray()
	Game.sfx.click()
	_sig = ""
	return true


func cancel_selection() -> void:
	if selected == null:
		return
	var p = selected
	selected = null
	if is_instance_valid(p):
		_set_tint(p, null)
		p.collision_layer = 2
		p.visible = true
	_tint_cur = null
	_clear_glow()
	_layout_tray()
	_sig = ""


## Seçili parçayı yuvaya takar.
func install_selected(slot) -> bool:
	if selected == null or slot == null:
		return false
	var r := can_install(slot, selected)
	if not r.ok:
		Game.msg(str(r.reason), Color(1, 0.6, 0.4))
		Game.sfx.error()
		return false
	var part = selected
	selected = null
	_set_tint(part, null)
	part.visible = true
	_tint_cur = null
	tray_parts.erase(part)
	_clear_glow()
	slot.install(part)
	_ever_installed = true
	if str(r.get("severity", "ok")) == "warn" and str(r.get("reason", "")) != "":
		Game.msg(str(r.reason), Color(1.0, 0.78, 0.3))
	Game.sfx.click()
	_layout_tray()
	_sig = ""
	return true


func select_tool(t) -> void:
	cancel_selection()
	tool = null if tool == t else t
	_sig = ""


## Aleti hedefe uygular (slot null: kasanın geneli).
func use_tool(t, slot) -> void:
	if t == null or device == null:
		return
	if kind == "pc" and not device.panel_open:
		Game.msg("Aleti kullanmak için önce kapağı aç.", Color(1, 0.8, 0.4))
		return
	device.tool_use(self, t, slot)


func toggle_panel() -> void:
	if device:
		device.toggle_panel()
		_sig = ""


func press_power() -> void:
	if device:
		device.power_button()
		_sig = ""


## Elde edilebilir aletler: moda girerken elde olan + masadaki görünür aletler.
func available_tools() -> Array:
	var out: Array = []
	if is_instance_valid(_stash_tool):
		out.append(_stash_tool)
	if device == null:
		return out
	for n in get_parent().get_children():
		if n != _stash_tool and n.has_method("is_tool") and n.is_tool() and n.get("tool_type") != null \
				and (n as Node3D).visible and (n as Node3D).global_position.distance_to(device.global_position) < 1.8:
			out.append(n)
	return out


# ---------------------------------------------------------------- tepsi düzeni

func _prune_tray() -> void:
	for i in range(tray_parts.size() - 1, -1, -1):
		var p = tray_parts[i]
		if not is_instance_valid(p) or p.get_parent() != _tray:
			tray_parts.remove_at(i)
			if p == selected:
				selected = null
			_sig = ""


func _flat_basis(part) -> Basis:
	var b := Basis.IDENTITY
	if part.part_type in ["mobo", "cpu", "cooler", "ram", "gpu", "nvme", "fan", "cmos"]:
		b = Basis.from_euler(Vector3(0, 0, PI / 2.0))
	var info: Dictionary = PM.info(part.part_type)
	var bb: AABB = Transform3D(b, Vector3.ZERO) * AABB(info.center - info.size / 2.0, info.size)
	if bb.size.z > bb.size.x * 1.2:
		b = Basis(Vector3.UP, PI / 2.0) * b
	return b


func _footprint(part, b: Basis) -> AABB:
	var info: Dictionary = PM.info(part.part_type)
	return Transform3D(b, Vector3.ZERO) * AABB(info.center - info.size / 2.0, info.size)


func _layout_tray() -> void:
	var iw := TRAY_W - 0.05
	var stock_list: Array = []
	var pulled_list: Array = []
	for p in tray_parts:
		if p == selected or not is_instance_valid(p):
			continue
		var orig: String = str(p.get("origin")) if "origin" in p else ""
		var is_test: bool = "is_test_part" in p and p.is_test_part
		if orig == "stock" or orig == "test" or is_test:
			stock_list.append(p)
		else:
			pulled_list.append(p)
	_layout_tray_zone(stock_list, iw, -TRAY_D / 2.0 + 0.032, true)
	_layout_tray_zone(pulled_list, iw, 0.028, false)


func _layout_tray_zone(list: Array, iw: float, z_start: float, avoid_dish: bool) -> void:
	var cx := -iw / 2.0
	var rz := z_start
	var row_d := 0.0
	for p in list:
		var b := _flat_basis(p)
		var bb := _footprint(p, b)
		var fx := bb.size.x
		var fz := bb.size.z
		# sağ arka köşedeki manyetik vida tabağını boş bırak
		var row_right := (iw / 2.0 - 0.092) if (avoid_dish and rz < -TRAY_D / 2.0 + 0.115) else iw / 2.0
		if cx + fx > row_right and cx > -iw / 2.0 + 0.001:
			rz += row_d + 0.008
			cx = -iw / 2.0
			row_d = 0.0
			row_right = (iw / 2.0 - 0.092) if (avoid_dish and rz < -TRAY_D / 2.0 + 0.115) else iw / 2.0
		var target := Vector3(cx + fx / 2.0, TRAY_TOP + bb.size.y / 2.0 + 0.0005, rz + fz / 2.0)
		p.transform = Transform3D(b, target - bb.get_center())
		cx += fx + 0.010
		row_d = maxf(row_d, fz)


# ---------------------------------------------------------------- hayalet parça ve yuva ışığı

func _set_tint(part, mat) -> void:
	if not is_instance_valid(part):
		return
	for m in part.find_children("*", "MeshInstance3D", true, false):
		m.material_override = mat


func _update_selected() -> void:
	if selected == null or not is_instance_valid(selected):
		return
	selected.visible = not _over_gui()
	if hovered.is_empty():
		return
	var tint: StandardMaterial3D = _mat_neutral
	var b := _flat_basis(selected)
	var bb := _footprint(selected, b)
	var hit: Dictionary = hovered.get("hit", {})
	var snapped_to_slot := false
	if hovered.has("slot") and hovered.slot != null:
		var r := can_install(hovered.slot, selected)
		if r.ok:
			selected.global_transform = hovered.slot.global_transform
			tint = _mat_warn if str(r.get("severity", "ok")) == "warn" else _mat_ok
			snapped_to_slot = true
		else:
			tint = _mat_bad
	if not snapped_to_slot:
		var o: Vector3 = hit.get("ray_from", cam.global_position)
		var d: Vector3 = hit.get("ray_dir", -cam.global_transform.basis.z)
		var t: float = (cam.global_position - (_center + _pan)).length()
		if hit.has("position"):
			t = minf(t, (hit.position - o).length() - 0.03)
		var pt: Vector3 = o + d * maxf(t, 0.05)
		selected.global_transform = Transform3D(b, pt - b * bb.get_center())
	if _tint_cur != tint:
		_tint_cur = tint
		_set_tint(selected, tint)


func _update_glow() -> void:
	if device == null:
		return
	for s in device.slots.values():
		if selected != null and s.part == null and _slot_open(s):
			var r := can_install(s, selected)
			var c := (AMBER if str(r.get("severity", "ok")) == "warn" else GREEN) if r.ok else RED
			if hovered.get("slot") == s:
				c.a = 0.6
			s.bench_tint = c
		else:
			s.bench_tint = Color(0, 0, 0, 0)


func _clear_glow() -> void:
	if device == null or not is_instance_valid(device):
		return
	for s in device.slots.values():
		s.bench_tint = Color(0, 0, 0, 0)


# ---------------------------------------------------------------- 3 bölgeli tezgâh ekranı

func _device_title() -> String:
	return "Bilgisayar" if kind == "pc" else str(device.device_name)


func _job_rec() -> Dictionary:
	var jm = Game.job_mgr
	if jm == null or device == null:
		return {}
	for rec in Game.jobs_active:
		if jm.devices.get(int(rec.ticket)) == device:
			return rec
	return {}


func _looks_fixed(rec: Dictionary) -> bool:
	return not rec.is_empty() and Game.job_mgr._problem_of(rec) == ""


func _job_dict() -> Dictionary:
	var j = device.get_meta("job") if device.has_meta("job") else device.get("job")
	return j if j is Dictionary else {}


func _stock_sig() -> String:
	var out := ""
	for k in Game.stock:
		var q := int(Game.stock[k])
		if q > 0:
			out += "%s:%d;" % [str(k), q]
	for k in Game.stock_cheap:
		var q := int(Game.stock_cheap[k])
		if q > 0:
			out += "%sc:%d;" % [str(k), q]
	return out


func _refresh_side(force: bool) -> void:
	if device == null or not is_instance_valid(device):
		return
	_update_screw_dish()
	_ever_open = _ever_open or device.panel_open
	_ever_power = _ever_power or device.powered
	var tools := available_tools()
	var ids := []
	for p in tray_parts:
		ids.append(p.get_instance_id())
	var tn := []
	for t in tools:
		tn.append(t.tool_type)
	var rec := _job_rec()
	var pc_sig := ""
	if kind == "pc":
		var cs := _pc_case_state()
		var w := Compatibility.calc_watts(cs)
		pc_sig = "%s|%s|%d|%d|%s|%s|%s|%d|%s|%s" % [
			str(cs.get("case_id", "")), cs.mobo.id if cs.mobo != null else "",
			int(w.draw), int(w.psu), str(device.cables.values()), str(device.cables_tidy),
			str(device.screws_missing()), device.sw_faults.size(), str(device.post_card_active), str(_laid_flat)
		]
	else:
		pc_sig = str(device.sw_fault) if "sw_fault" in device else ""
	var sig := str([
		_tab, _stock_cat, _looks_fixed(rec), str(rec.get("status", "")), ids,
		selected.get_instance_id() if selected else 0, tool.tool_type if tool else "", tn,
		device.panel_open, device.powered, _ever_open, _ever_power, _ever_removed, _ever_installed,
		str(_job_dict().get("name", "")), pc_sig, Game.money, _stock_sig()
	])
	if sig == _sig and not force:
		return
	_sig = sig
	_rebuild_all(tools)


func _clear_box(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _rebuild_all(tools: Array) -> void:
	var rec := _job_rec()
	_rebuild_top_bar(rec)
	_rebuild_tabs()
	_rebuild_drawer(rec)
	_rebuild_dock(tools)
	_layout_ui()
	call_deferred("_layout_ui")


func _rebuild_top_bar(rec: Dictionary) -> void:
	_clear_box(_top_hb)
	var title_txt := _device_title().to_upper()
	if not rec.is_empty():
		title_txt = "#%d · %s" % [int(rec.ticket), str(rec.name)]
	K.label(_top_hb, title_txt, 17, T.ACCENT, "TitleLabel").size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if not rec.is_empty():
		var fixed := _looks_fixed(rec)
		var pill := K.panel(_top_hb, "InsetPanel")
		pill.add_theme_stylebox_override("panel", T.flat(
			Color(0.14, 0.34, 0.18, 0.8) if fixed else Color(0.32, 0.22, 0.08, 0.8),
			5, T.GOOD if fixed else T.ACCENT, 1, Vector2(8, 2)))
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		K.label(pill, "HAZIR ✓ — RAFA KOY" if fixed else "TAMİRDE", 12, T.GOOD if fixed else T.ACCENT, "BoldLabel")

	if kind == "pc":
		var cs := _pc_case_state()
		var mobo: PartDef = cs.get("mobo", null)
		var w := Compatibility.calc_watts(cs)
		var spec_txt := "%s · %s" % [str(mobo.compat.get("socket", "")) if mobo else "Anakart Yok",
			str(mobo.compat.get("ram_type", "")) if mobo else "—"]
		var sl := K.label(_top_hb, spec_txt, 13, T.INFO, "BoldLabel")
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var w_col := T.GOOD
		if w.psu <= 0 or w.draw > w.psu:
			w_col = T.BAD
		elif w.psu < w.recommended or float(w.draw) / float(w.psu) > 0.85:
			w_col = T.ACCENT
		var wl := K.label(_top_hb, "%dW / %s" % [w.draw, ("%dW" % w.psu) if w.psu > 0 else "PSU Yok"], 13, w_col, "BoldLabel")
		wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_hb.add_child(spacer)

	var ml := K.label(_top_hb, "₺ %s" % K.money(Game.money), 18, T.LCD, "LcdLabel")
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if kind == "pc":
		var b_flat := K.button(_top_hb, "Dikleştir [F]" if _laid_flat else "Yatır [F]", toggle_lay_flat, "", 13, Vector2(0, 32))
		b_flat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var open_lbl := ("Kapağı Kapat" if device.panel_open else "Kapağı Aç") if kind == "pc" else \
		(("Düzelt" if device.panel_open else "Ters Çevir") if kind == "laptop" else \
		("Ekranı İndir" if device.panel_open else "Ekranı Kaldır"))
	var b_panel := K.button(_top_hb, open_lbl, toggle_panel, "", 13, Vector2(0, 32))
	b_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var b_pwr := K.button(_top_hb, "Kapat" if device.powered else "Güç", press_power, "", 13, Vector2(0, 32))
	b_pwr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if kind == "pc":
		var b_bios := K.button(_top_hb, "BIOS / Servis", func():
			if Game.pc_service:
				Game.pc_service.open(device), "", 13, Vector2(0, 32))
		b_bios.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var b_exit := K.button(_top_hb, "Çık [Tab]", func(): exit(), "PrimaryButton", 13, Vector2(82, 32))
	b_exit.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _rebuild_tabs() -> void:
	_clear_box(_side_tab_bar)
	var labels := [[0, "İş"], [1, "Stok"], [2, "Tepsi (%d)" % tray_parts.size()]]
	for sp in labels:
		var idx: int = sp[0]
		var b := K.button(_side_tab_bar, sp[1], func():
			_tab = idx
			_sig = "", "PrimaryButton" if _tab == idx else "SegButton", 14, Vector2(0, 32))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _rebuild_drawer(rec: Dictionary) -> void:
	_clear_box(_side_vb)
	match _tab:
		0: _build_tab_job(_side_vb, rec)
		1: _build_tab_stock(_side_vb)
		2: _build_tab_tray(_side_vb)


func _build_tab_job(vb: VBoxContainer, rec: Dictionary) -> void:
	var job := _job_dict()
	if not rec.is_empty():
		var card := K.panel(vb, "InsetPanel")
		card.add_theme_stylebox_override("panel", T.flat(Color(0, 0, 0, 0.25), 6, Color(1, 1, 1, 0.06), 1, Vector2(10, 8)))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)
		var hr := HBoxContainer.new()
		cv.add_child(hr)
		K.label(hr, str(rec.name), 15, T.TEXT, "BoldLabel").size_flags_horizontal = Control.SIZE_EXPAND_FILL
		K.label(hr, "%s TL" % K.money(int(rec.pay)), 15, T.GOOD, "BoldLabel")
		var gl := K.label(cv, ST.short_goal(rec), 13, T.INFO)
		gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gl.custom_minimum_size = Vector2(246, 0)
		var intro := str(rec.get("intro", ""))
		if intro != "":
			var il := K.label(cv, "\"%s\"" % intro, 12, T.MUTED)
			il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			il.custom_minimum_size = Vector2(246, 0)
		K.label(cv, "Teslim: %s · %s" % [ST.due_label(float(rec.due_abs), Game.day), ST.status_text(rec, Game.now_abs())], 12, T.ACCENT)
	elif not job.is_empty():
		K.label(vb, str(job.get("name", "")), 15, T.TEXT, "BoldLabel")
		var intro := str(job.get("intro", job.get("goal", "")))
		if intro != "":
			var l := K.label(vb, intro, 13, T.MUTED)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(260, 0)

	if kind == "pc":
		var miss_s := str(device.missing_screws_text()) if device.has_method("missing_screws_text") else ""
		if miss_s != "":
			var sl := K.label(vb, "⚠ Eksik vida: " + miss_s, 12, T.ACCENT)
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sl.custom_minimum_size = Vector2(260, 0)
		var loose_c := false
		for cv in device.cables.values():
			if str(cv) != "ok":
				loose_c = true
				break
		if loose_c:
			var cl := K.label(vb, "⚠ Gevşek / takılmamış güç veya veri kablosu var!", 12, T.BAD)
			cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cl.custom_minimum_size = Vector2(260, 0)
		if device.dust > 0.45:
			var dl := K.label(vb, "⚠ Kasa içi tozlu (%%%d)" % roundi(device.dust * 100.0), 12, T.ACCENT)
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.custom_minimum_size = Vector2(260, 0)
		if Game.job_mgr != null and not rec.is_empty():
			var audit: Dictionary = Game.job_mgr.audit_parts(rec, device)
			if not audit.stolen_items.is_empty():
				var wl := K.label(vb, "! Müşterinin %s parçası eksik/düşük — teslimde fark edilebilir (%%%d risk)" % [
					str(audit.stolen_items[0].orig_name), roundi(float(audit.catch_chance) * 100.0)], 12, T.ACCENT)
				wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				wl.custom_minimum_size = Vector2(260, 0)
		var bt := K.button(vb, "Kablolar Düzenli ✓ (+30 TL bahşiş)" if device.cables_tidy else "Kabloları Düzenle (+30 TL)", func():
			device.tidy_cables()
			_sig = "", "", 13, Vector2(0, 32))
		bt.disabled = device.cables_tidy
	elif kind == "phone" and "sw_fault" in device and device.sw_fault:
		K.button(vb, "Yazılım Sıfırla (Reset)", func():
			device.fix_software()
			Game.sfx.beep_scan()
			Game.msg("Telefon yazılımı sıfırlandı!", Color(0.5, 1.0, 0.5))
			_sig = "", "PrimaryButton", 14, Vector2(0, 32))

	if kind == "pc" and Game.has_upgrade("test_bench_parts"):
		K.hsep(vb).add_theme_constant_override("separation", 4)
		K.label(vb, "YEDEK TEST PARÇALARI", 11, T.MUTED, "SmallCaps")
		var tp_row := HBoxContainer.new()
		tp_row.add_theme_constant_override("separation", 5)
		vb.add_child(tp_row)
		for tp in [["PSU 750W", "psu_750w"], ["DDR4 Test", "ram_ddr4_16g_rgb"], ["DDR5 Test", "ram_ddr5_16g"]]:
			var btp := K.button(tp_row, tp[0], func(): _spawn_test_part(tp[1]), "", 12, Vector2(0, 30))
			btp.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _build_tab_stock(vb: VBoxContainer) -> void:
	var devs: Array = ["pc"] if kind == "pc" else ["laptop", "phone"]
	if kind == "pc":
		var cf := HFlowContainer.new()
		cf.add_theme_constant_override("h_separation", 4)
		cf.add_theme_constant_override("v_separation", 4)
		vb.add_child(cf)
		for c in STOCK_CATS:
			var cid: String = c.id
			var cb := K.button(cf, c.label, func():
				_stock_cat = cid
				_sig = "", "PrimaryButton" if _stock_cat == cid else "SegButton", 12, Vector2(0, 26))
			cb.custom_minimum_size = Vector2(0, 26)
	var cat_filter: Array = []
	if kind == "pc":
		for c in STOCK_CATS:
			if c.id == _stock_cat:
				cat_filter = c.cats
				break
	var cs := _pc_case_state() if kind == "pc" else {}
	var shown := 0
	for d in DB.parts.shelf_items(devs):
		if not cat_filter.is_empty() and not cat_filter.has(d.category):
			continue
		var q_orig := Game.stock_of_sku(d.id)
		var q_cheap := Game.stock_cheap_of_sku(d.id)
		if q_orig <= 0 and q_cheap <= 0:
			continue
		shown += 1
		var card := K.panel(vb, "InsetPanel")
		card.add_theme_stylebox_override("panel", T.flat(Color(0, 0, 0, 0.24), 5, Color(1, 1, 1, 0.05), 1, Vector2(8, 6)))
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 6)
		card.add_child(rh)
		var info_v := VBoxContainer.new()
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_v.add_theme_constant_override("separation", -1)
		rh.add_child(info_v)
		var nl := K.label(info_v, PM.display_name_sku(d.id), 13, T.TEXT, "BoldLabel")
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size = Vector2(150, 0)
		var meta := "Stok: %d%s" % [q_orig, (" (+%d M)" % q_cheap) if q_cheap > 0 else ""]
		var mcol := T.MUTED
		if kind == "pc":
			var cr := Compatibility.check_catalog_part(d, cs)
			if cr.ok:
				meta += " · Uyumlu"
				mcol = T.GOOD
			else:
				meta += " · Uyumsuz"
				mcol = T.BAD
		K.label(info_v, meta, 11, mcol)
		var acts := VBoxContainer.new()
		acts.add_theme_constant_override("separation", 3)
		rh.add_child(acts)
		if q_orig > 0:
			K.button(acts, "Al", func(): take_from_stock(d.id, false), "PrimaryButton", 12, Vector2(64, 26))
		if q_cheap > 0:
			K.button(acts, "Muadil", func(): take_from_stock(d.id, true), "SegButton", 11, Vector2(64, 24))
	if shown == 0:
		var empty_l := K.label(vb, "Bu kategoride stok yok.\nSipariş için dükkân laptopuna bak.", 13, T.MUTED)
		empty_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_l.custom_minimum_size = Vector2(260, 0)


func _build_tab_tray(vb: VBoxContainer) -> void:
	if tray_parts.is_empty():
		var e := K.label(vb, "Tepsi boş. Cihazdan söktüğün veya Stoktan aldığın parçalar buraya iner.", 13, T.MUTED)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.custom_minimum_size = Vector2(260, 0)
		return
	for p in tray_parts:
		if not is_instance_valid(p):
			continue
		var is_test: bool = "is_test_part" in p and p.is_test_part
		var orig: String = str(p.get("origin")) if "origin" in p else ""
		var otag: String = str(p.origin_tag()) if p.has_method("origin_tag") else ""
		var border_col := T.INFO if is_test else (T.GOOD if orig == "stock" else (T.ACCENT if orig == "customer" else Color(1, 1, 1, 0.06)))
		var card := K.panel(vb, "InsetPanel")
		card.add_theme_stylebox_override("panel", T.flat(Color(0, 0, 0, 0.25), 5, border_col, 1, Vector2(8, 6)))
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", 4)
		card.add_child(pv)
		var sel: bool = p == selected
		K.label(pv, p.display_name, 13, T.ACCENT if sel else T.TEXT, "BoldLabel")
		var status_txt := "Test Parçası" if is_test else ("ARIZALI" if p.broken else "Sağlam")
		var cond := ("%s · %s" % [otag, status_txt]) if otag != "" and not is_test else status_txt
		var cond_col := T.INFO if is_test else (T.BAD if p.broken else (T.GOOD if orig == "stock" else T.ACCENT))
		K.label(pv, cond, 11, cond_col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		pv.add_child(row)
		var bs := K.button(row, "İptal" if sel else "Seç", (cancel_selection if sel else select_part.bind(p)), "PrimaryButton" if sel else "", 12, Vector2(0, 26))
		bs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not p.broken and not is_test:
			if orig == "customer":
				K.button(row, "Cebe At", func(): pocket_tray_part(p), "", 12, Vector2(68, 26))
			else:
				K.button(row, "Rafa", func(): return_tray_part(p), "", 12, Vector2(58, 26))
		K.button(row, "At", func(): scrap_tray_part(p), "", 12, Vector2(46, 26))


func _rebuild_dock(tools: Array) -> void:
	_clear_box(_dock_tools)
	if tools.is_empty():
		var l := K.label(_dock_tools, "Masada kullanılabilir alet yok", 12, T.MUTED)
		return
	for t in tools:
		var act: bool = t == tool
		var tb := K.button(_dock_tools, t.display_name + (" ✓" if act else ""), func(): select_tool(t),
			"PrimaryButton" if act else "SegButton", 12, Vector2(0, 28))


func _spawn_test_part(sku_id: String) -> void:
	if device == null or state == "off":
		return
	var p = PART.new().setup_sku(sku_id, false)
	p.make_test_part()
	tray_add(p)
	Game.sfx.click()
	Game.msg("Tepsiye eklendi: %s (teslimde çıkarın)." % p.display_name, Color(0.7, 0.9, 1.0))


func _force_exit_reason() -> String:
	if not is_instance_valid(device):
		return "cihaz yok oldu"
	if Game.bench_device != device:
		return "tezgâhtaki cihaz değişti"
	if Game.phase != "day":
		return "gün bitti (%s)" % Game.phase
	if Game.ui_modal and not (Game.pc_service != null and Game.pc_service.is_open()):
		return "bir menü açıldı"
	return ""


func _report_exit(why: String) -> void:
	push_warning("Tezgâh modu kapandı: " + why)
	Game.msg("Tezgâh modu kapandı: " + why, Color(1.0, 0.75, 0.4))
