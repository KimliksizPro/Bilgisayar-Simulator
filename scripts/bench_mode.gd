extends Node3D
## Tezgâh modu: kamera oyuncunun başından tezgâhtaki cihazın (Game.bench_device) etrafındaki yörünge kameraya geçer,
## fare serbest kalır (zaman AKMAYA devam eder, modal pause yok). Fareyle parça sök / tak, parça tepsisi, aletler, yan panel.
##
## Sözleşme: yalnızca Game.bench_device ile çalışır (PC kasası / laptop / telefon), iş sistemini bilmez.
## Cihaz tezgâhtan giderse (null / silinmiş / başka cihaz) mod nazikçe kapanır; tepsideki parçalar masaya serbest bırakılır.
## Tepsi: cihaz tezgâha gelince masada (oyuncuya bakan tarafta) belirir; sökülen parçalar buraya dizilir.
## Tezgâh moduna girerken elde parça varsa tepsiye konur; alet varsa moddan çıkınca geri eline verilir.

const MU := preload("res://scripts/mesh_util.gd")
const PM := preload("res://scripts/part_models.gd")
const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")
const PC_SCRIPT := preload("res://scripts/pc_case.gd")

const TRANS := 0.35          # geçiş süresi (sn)
const BENCH_FOV := 55.0
const TRAY_W := 0.64
const TRAY_D := 0.26
const TRAY_TOP := 0.006      # tepsi zemini (tepsi düğümüne göre y)
const GREEN := Color(0.2, 1.0, 0.35, 0.32)
const RED := Color(1.0, 0.2, 0.15, 0.32)

var state := "off"           # off, entering, on, leaving
var cam: Camera3D            # hem yörünge kamera hem (puff gibi) alet çağrıları için "oyuncu.cam" yerine geçer
var held = null              # yuva/alet ipuçları player.held okur; tezgâh modunda elde bir şey yok
var device = null            # bağlı tezgâh cihazı
var kind := "pc"             # pc, laptop, phone
var tray_parts: Array = []
var selected = null          # fareyle seçilen (hayalet) parça
var tool = null              # seçili alet (macun / hava)
var hovered := {}            # fare altındaki hedef (_resolve sonucu)
var mouse_override := Vector2(-1, -1)  # >= 0 ise gerçek fare yerine bu konum (dev/test)

var _tray: Node3D
var _hl: MeshInstance3D      # üstüne gelme vurgusu
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
var _excl: Array = []        # cihazın çarpışma gövdeleri (kamera duvar kontrolünde yok sayılır)
var _rmb := false
var _rmb_moved := 0.0
var _mmb := false
var _stash_tool = null       # moda girerken elde olan alet
var _tint_cur = null
var _mat_neutral: StandardMaterial3D
var _mat_ok: StandardMaterial3D
var _mat_bad: StandardMaterial3D
var _ever_open := false
var _ever_power := false
var _ever_removed := false
var _ever_installed := false
var _sig := ""
var _sig_t := 0.0

# arayüz
var _ui: CanvasLayer
var _ui_root: Control
var _side: PanelContainer
var _side_vb: VBoxContainer
var _tip: PanelContainer
var _tip_title: Label
var _tip_sub: Label
var _keys: PanelContainer


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
	if state != "off":
		Game.bench_active = false


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
	_sig = ""
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


## Tepsi masada cihazın oyuncuya bakan tarafında (dünya +Z).
func _place_tray() -> void:
	var o: Vector3 = device.global_position
	var desk_y: float = float(get_parent().get("DESK_Y")) if get_parent().get("DESK_Y") != null else 0.75
	_tray.global_position = Vector3(o.x, desk_y + 0.004, o.z + (0.26 if kind == "pc" else 0.24))
	_tray.global_rotation = Vector3.ZERO
	_layout_tray()


## Cihaz gidince tepsideki parçalar masaya serbest düşen parça olur.
func _release_tray() -> void:
	selected = null
	tool = null
	_tint_cur = null
	for p in tray_parts:
		if not is_instance_valid(p):
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


# ---------------------------------------------------------------- görünüm kurulumu

func _build_tray() -> void:
	_tray = Node3D.new()
	_tray.name = "Tray"
	_tray.visible = false
	add_child(_tray)
	var base_m := MU.mat(Color(0.1, 0.11, 0.13), 0.3, 0.7)
	var rim_m := MU.mat(Color(0.9, 0.62, 0.12), 0.4, 0.5)
	MU.rbox(_tray, Vector3(TRAY_W, 0.006, TRAY_D), Vector3(0, 0.003, 0), base_m, 0.003)
	for z in [-1, 1]:
		MU.rbox(_tray, Vector3(TRAY_W, 0.012, 0.006), Vector3(0, 0.006, z * (TRAY_D / 2 - 0.003)), rim_m, 0.002)
	for x in [-1, 1]:
		MU.rbox(_tray, Vector3(0.006, 0.012, TRAY_D), Vector3(x * (TRAY_W / 2 - 0.003), 0.006, 0), rim_m, 0.002)
	var l := MU.label(_tray, "PARÇA TEPSİSİ", Vector3(0, 0.0095, TRAY_D / 2 + 0.0002), 40, Color(0.1, 0.1, 0.1), Vector3.ZERO, 0.00022)
	l.double_sided = false
	_hl = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	_hl.mesh = bm
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.albedo_color = Color(1.0, 0.75, 0.2, 0.22)
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hl.material_override = hm
	_hl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hl.visible = false
	add_child(_hl)


func _build_materials() -> void:
	_mat_neutral = _tint_mat(Color(0.55, 0.8, 1.0, 0.6))
	_mat_ok = _tint_mat(Color(0.25, 1.0, 0.4, 0.6))
	_mat_bad = _tint_mat(Color(1.0, 0.25, 0.2, 0.6))


func _tint_mat(c: Color) -> StandardMaterial3D:
	var m := MU.new_mat(c, 0, 0.5, 0.8)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true  # imleçteki hayalet kasanın içindeki parçalara gömülüp kaybolmasın
	m.render_priority = 10
	return m


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 3
	add_child(_ui)
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.visible = false
	_ui.add_child(_ui_root)
	_side = K.panel(_ui_root, "ScrewCard")
	_side.position = Vector2(18, 210)
	_side_vb = VBoxContainer.new()
	_side_vb.add_theme_constant_override("separation", 6)
	_side_vb.custom_minimum_size = Vector2(250, 0)
	_side.add_child(_side_vb)
	# fare yanı bilgi kartı
	_tip = K.panel(_ui_root, "Toast")
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 1)
	_tip.add_child(tv)
	_tip_title = K.label(tv, "", 18, T.TEXT, "BoldLabel")
	_tip_sub = K.label(tv, "", 15, T.ACCENT)
	# alt tuş ipuçları
	_keys = K.panel(_ui_root, "HudCard")
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kh := HBoxContainer.new()
	kh.add_theme_constant_override("separation", 8)
	_keys.add_child(kh)
	for pair in [["SAĞ TIK", "Döndür"], ["TEKERLEK", "Yakınlaştır"], ["WASD", "Kaydır"], ["Q E", "90°"], ["TAB", "Çık"]]:
		K.keycap(kh, pair[0], 13)
		K.label(kh, pair[1], 15, T.MUTED)
		K.spacer(kh, 0).custom_minimum_size = Vector2(10, 0)
	get_viewport().size_changed.connect(_layout_ui)
	_layout_ui()


func _layout_ui() -> void:
	var vs := get_viewport().get_visible_rect().size
	_keys.reset_size()
	_keys.position = Vector2((vs.x - _keys.size.x) * 0.5, vs.y - _keys.size.y - 16)


# ---------------------------------------------------------------- giriş / çıkış

## Tezgâh görünümüne geçer. Elde parça varsa tepsiye konur, alet geri verilmek üzere saklanır.
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
	if Game.hud and Game.hud.crosshair:
		Game.hud.crosshair.visible = false
	if Game.hud and Game.hud.corner_hint:
		Game.hud.corner_hint.visible = false
	_ui_root.visible = true
	_sig = ""
	Game.sfx.click()
	return true


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
	hovered = {}
	_set_hl(null)
	_tip.visible = false
	_clear_glow()
	if immediate or Game.player == null:
		_finish_exit(not Game.ui_modal and Game.phase == "day")
		return
	state = "leaving"
	_t = 0.0
	_from_xf = cam.global_transform
	_from_fov = cam.fov
	Game.sfx.click()


func _finish_exit(capture: bool) -> void:
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
	if Game.hud and Game.hud.crosshair:
		Game.hud.crosshair.visible = true
	if Game.hud and Game.hud.corner_hint:
		Game.hud.corner_hint.visible = true
	if capture and Game.started:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- yörünge

func _init_orbit() -> void:
	_orbit_ready = true
	var b: Basis = device.global_transform.basis
	var local_c := Vector3(0, 0.23, 0)
	_d_min = 0.3
	_d_max = 1.6
	_pan_max = 0.5
	_dist_goal = 0.95
	_elev = 0.34
	_yaw_goal = 0.0
	match kind:
		"pc":
			var f: Vector3 = b * Vector3(1, 0, 0)  # açık yan (cam kapak) tarafı
			_yaw_goal = atan2(f.x, f.z)
		"laptop":
			local_c = Vector3(0, 0.07, 0)
			_d_min = 0.22
			_d_max = 1.0
			_pan_max = 0.3
			_dist_goal = 0.55
			_elev = 0.85
		_:
			local_c = Vector3(0, 0.005, 0)
			_d_min = 0.12
			_d_max = 0.6
			_pan_max = 0.15
			_dist_goal = 0.3
			_elev = 1.0
	_center = device.global_transform * local_c
	_yaw = _yaw_goal
	_dist = _dist_goal
	_pan = Vector3.ZERO
	# monitör ekranı kadraja yakın kalsın: bakış noktası biraz monitöre kayar
	var m = device.get("monitor") if kind == "pc" else null
	if m is Node3D and is_instance_valid(m):
		var to: Vector3 = m.global_position - _center
		to.y = 0.0
		_pan = to.limit_length(0.14)
	# tepsi de kadrajda kalsın: bakış noktası tepsiye doğru biraz kayar
	var tt: Vector3 = _tray.global_position - _center
	tt.y = 0.0
	_pan += tt.limit_length(0.09)


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
	# cihaz tezgâhtan gitti ya da gün bitti: nazikçe çık
	var why := _force_exit_reason()
	if why != "":
		_report_exit(why)
		exit(true)
		return
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
			_update_hover()
			_update_selected()
			_update_glow()
			_sig_t -= delta
			if _sig_t <= 0.0:
				_sig_t = 0.15
				_refresh_side(false)


# ---------------------------------------------------------------- girdi

func _input(event: InputEvent) -> void:
	# Tab / Esc önce arayüzden geçmesin: odaklı düğme Tab'ı yutmasın, Esc duraklatmayı açmasın
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
	if state != "on":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			_yaw_goal += PI / 2.0
		elif event.physical_keycode == KEY_E:
			_yaw_goal -= PI / 2.0
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					click(_resolve(_ray_hit(_mp())))
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_rmb = true
					_rmb_moved = 0.0
				else:
					_rmb = false
					if _rmb_moved < 8.0 and (selected != null or tool != null):  # sürüklemeden sağ tık: iptal
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


# ---------------------------------------------------------------- fare ışını

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


## Işın sonucunu {kind, node, slot, part} olarak yorumlar. kind: installed, slot, tray, widget, body ya da boş.
func _resolve(hit: Dictionary) -> Dictionary:
	if not hit.has("collider") or device == null:
		return {}
	var c = hit.collider
	if not is_instance_valid(c):
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


## Fare konumu (geliştirici ekran görüntüleri için mouse_override ile ezilebilir).
func _mp() -> Vector2:
	return mouse_override if mouse_override.x >= 0.0 else get_viewport().get_mouse_position()


func _over_gui() -> bool:
	return mouse_override.x < 0.0 and get_viewport().gui_get_hovered_control() != null


func _update_hover() -> void:
	if _over_gui() or _rmb or _mmb:
		hovered = {}
		_set_hl(null)
		_tip.visible = false
		return
	var hit := _ray_hit(_mp())
	hovered = _resolve(hit)
	hovered["hit"] = hit
	var node = hovered.get("node")
	var hl_ok: bool = node != null and hovered.get("kind", "") != "body"
	_set_hl(node if hl_ok else null)
	var txt := _tooltip_for(hovered)
	if txt.is_empty():
		_tip.visible = false
		return
	_tip_title.text = txt[0]
	_tip_sub.text = txt[1]
	_tip_sub.add_theme_color_override("font_color", txt[2])
	_tip_sub.visible = txt[1] != ""
	_tip.visible = true
	_tip.reset_size()
	var vs := get_viewport().get_visible_rect().size
	var mp := _mp() + Vector2(20, 24)
	_tip.position = Vector2(clampf(mp.x, 0, vs.x - _tip.size.x - 4), clampf(mp.y, 0, vs.y - _tip.size.y - 4))


## Çarpışma kutusu etrafında yarı saydam vurgu kutusu.
func _set_hl(node) -> void:
	if node == null or not is_instance_valid(node):
		_hl.visible = false
		return
	var cs = null
	for c in node.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			cs = c
			break
	if cs == null:
		_hl.visible = false
		return
	var sz: Vector3 = cs.shape.size * 1.04
	var gt: Transform3D = cs.global_transform
	_hl.global_transform = Transform3D(gt.basis.scaled(sz), gt.origin)
	_hl.visible = true


func _tooltip_for(res: Dictionary) -> Array:
	var k: String = res.get("kind", "")
	if k == "":
		return []
	var click := "[Sol tık]"
	if selected != null:
		match k:
			"slot", "installed":
				var r := can_install(res.slot, selected)
				return ["%s" % PM.type_name(res.slot.accepts), ("Tak: %s  %s" % [selected.display_name, click]) if r.ok else str(r.reason), T.GOOD if r.ok else T.BAD]
			"tray":
				return [res.part.display_name, "Seçimi bunla değiştir  " + click, T.ACCENT]
		return []
	if tool != null:
		var target = res.get("slot")
		if k in ["slot", "installed", "widget", "body"]:
			return [tool.display_name, str(device.tool_hint(tool, target)).replace("[E]", click).replace("  ", " "), T.ACCENT]
		return []
	match k:
		"installed":
			if not _slot_open(res.slot):
				return []
			return [res.part.display_name, "Sök  " + click, T.ACCENT]
		"slot":
			return ["Boş yuva: %s" % PM.type_name(res.slot.accepts), "Tepsiden parça seç, sonra tıkla", T.MUTED]
		"tray":
			return [res.part.display_name, "Seç  " + click, T.ACCENT]
		"widget":
			var h := str(res.node.get_hint(self))
			if h == "":
				return []
			return [h.replace("[E]", "").strip_edges(), click, T.ACCENT]
	return []


# ---------------------------------------------------------------- eylemler (fare tıklaması ve test aynı işlevleri çağırır)

func click(res: Dictionary) -> void:
	if res.is_empty():
		return
	var k: String = res.kind
	if selected != null:
		if k == "slot" or k == "installed":
			install_selected(res.slot)
		elif k == "tray":
			select_part(res.part)
		return
	if tool != null:
		if k == "slot" or k == "installed":
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
			Game.msg("Önce tepsiden takılacak parçayı seç.", Color(1, 0.8, 0.4))


## Yuva şu an erişilebilir mi (kapak açık, cihaz kapalı)?
func _slot_open(slot) -> bool:
	var d = slot.pc
	return d.slot_open(slot) if d.has_method("slot_open") else d.panel_open


## Faz 2 uyumluluk kuralları için kanca: {ok: bool, reason: String}. Şimdilik yalnızca yuva türü ve doluluk.
func can_install(slot, part) -> Dictionary:
	if slot.part != null:
		return {"ok": false, "reason": "Yuva dolu"}
	if not _slot_open(slot):
		return {"ok": false, "reason": "Yuvaya erişemiyorsun: önce kapağı aç"}
	if slot.accepts != part.part_type:
		return {"ok": false, "reason": "Uyumsuz: bu yuva %s ister" % PM.type_name(slot.accepts)}
	return {"ok": true, "reason": ""}


## Takılı parçayı yuvadan söküp tepsiye koyar. Parçayı döndürür (olmadıysa null).
func remove_part(slot):
	if slot == null or slot.part == null:
		return null
	if not _slot_open(slot):
		Game.msg("Önce kapağı aç.", Color(1, 0.8, 0.4))
		return null
	var part = slot.part
	slot.detach()
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
	Game.sfx.click()
	_layout_tray()
	_sig = ""
	return true


func select_tool(t) -> void:
	cancel_selection()
	tool = null if tool == t else t
	_sig = ""


## Aleti hedefe uygular (slot null: kasanın geneli, örn. basınçlı hava).
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


## Elde edilebilir aletler: moda girerken elde olan + masadaki (cihaza yakın) aletler.
func available_tools() -> Array:
	var out: Array = []
	if is_instance_valid(_stash_tool):
		out.append(_stash_tool)
	if device == null:
		return out
	for n in get_parent().get_children():
		if n != _stash_tool and n.has_method("is_tool") and n.is_tool() and n.get("tool_type") != null \
				and (n as Node3D).global_position.distance_to(device.global_position) < 1.8:
			out.append(n)
	return out


# ---------------------------------------------------------------- tepsi düzeni

func _prune_tray() -> void:
	# birinci şahıs modda oyuncu tepsiden parça alırsa listeden düşer
	for i in range(tray_parts.size() - 1, -1, -1):
		var p = tray_parts[i]
		if not is_instance_valid(p) or p.get_parent() != _tray:
			tray_parts.remove_at(i)
			if p == selected:
				selected = null
			_sig = ""


## Parçanın tepsiye yatış yönü: kart parçaları (işlemci, RAM, GPU) bileşen yüzü yukarı; en uzun kenar x'e.
func _flat_basis(part) -> Basis:
	var b := Basis.IDENTITY
	if part.part_type in ["cpu", "ram", "gpu"]:
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
	var iw := TRAY_W - 0.03
	var id := TRAY_D - 0.03
	var cx := -iw / 2.0
	var rz := -id / 2.0
	var row_d := 0.0
	for p in tray_parts:
		if p == selected or not is_instance_valid(p):
			continue
		var b := _flat_basis(p)
		var bb := _footprint(p, b)
		var fx := bb.size.x
		var fz := bb.size.z
		if cx + fx > iw / 2.0 and cx > -iw / 2.0 + 0.001:
			rz += row_d + 0.012
			cx = -iw / 2.0
			row_d = 0.0
		var target := Vector3(cx + fx / 2.0, TRAY_TOP + bb.size.y / 2.0 + 0.0005, rz + fz / 2.0)
		p.transform = Transform3D(b, target - bb.get_center())
		cx += fx + 0.012
		row_d = maxf(row_d, fz)


# ---------------------------------------------------------------- hayalet parça ve yuva ışığı

func _set_tint(part, mat) -> void:
	if not is_instance_valid(part):
		return
	for m in part.find_children("*", "MeshInstance3D", true, false):
		m.material_override = mat


## Seçili parça imleci izler; uyumlu yuvanın üstündeyse yuvaya oturur (yeşil), değilse kırmızı.
func _update_selected() -> void:
	if selected == null or not is_instance_valid(selected):
		return
	selected.visible = not _over_gui()  # imleç panelin üstündeyken hayalet gizlenir
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
			tint = _mat_ok
			snapped_to_slot = true
		else:
			tint = _mat_bad
	if not snapped_to_slot:
		var o: Vector3 = hit.get("ray_from", cam.global_position)
		var d: Vector3 = hit.get("ray_dir", -cam.global_transform.basis.z)
		# imleç ışınında, odak mesafesinde (yüzeyin önünde) süzülür
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
			var ok: bool = can_install(s, selected).ok
			var c := GREEN if ok else RED
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


# ---------------------------------------------------------------- yan panel

func _device_title() -> String:
	return "Bilgisayar" if kind == "pc" else str(device.device_name)


## Cihazın iş kaydı (Game.jobs_active); job_manager.devices fiş -> cihaz eşlemesinden bulunur.
func _job_rec() -> Dictionary:
	var jm = Game.job_mgr
	if jm == null or device == null:
		return {}
	for rec in Game.jobs_active:
		if jm.devices.get(int(rec.ticket)) == device:
			return rec
	return {}


## Cihaz teslim kontrolünü geçiyor mu (kayıt varsa)?
func _looks_fixed(rec: Dictionary) -> bool:
	return not rec.is_empty() and Game.job_mgr._problem_of(rec) == ""


func _job_dict() -> Dictionary:
	var j = device.get_meta("job") if device.has_meta("job") else device.get("job")
	return j if j is Dictionary else {}


func _checklist() -> Array:
	var open_txt := "Kapağı aç"
	var pw_txt := "Güç düğmesine bas, belirtileri oku"
	match kind:
		"laptop":
			open_txt = "Laptopu ters çevir (alt kapak)"
			pw_txt = "Güç düğmesine bas, ekranı oku"
		"phone":
			open_txt = "Ekran modülünü kaldır"
			pw_txt = "Güç tuşuna bas, belirtiye bak"
	var closed_ok: bool = _ever_installed and not device.panel_open
	return [
		[pw_txt, _ever_power],
		[open_txt, _ever_open],
		["Arızalı parçayı söküp tepsiye koy", _ever_removed],
		["Yeni parçayı seç, yuvaya tak", _ever_installed],
		["Dene, kapat ve teslim et", closed_ok and device.powered],
	]


## Yan panel: durum imzası değişmedikçe yeniden kurulmaz. force: imzayı yok say.
func _refresh_side(force: bool) -> void:
	if device == null or not is_instance_valid(device):
		return
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
	var sig := str([_looks_fixed(rec), str(rec.get("status", "")), ids, selected.get_instance_id() if selected else 0, tool.tool_type if tool else "", tn,
		device.panel_open, device.powered, _ever_open, _ever_power, _ever_removed, _ever_installed, str(_job_dict().get("name", ""))])
	if sig == _sig and not force:
		return
	_sig = sig
	_rebuild_side(tools)


func _rebuild_side(tools: Array) -> void:
	for c in _side_vb.get_children():
		_side_vb.remove_child(c)
		c.queue_free()
	var vb := _side_vb
	K.label(vb, _device_title().to_upper(), 22, T.ACCENT, "TitleLabel")
	var rec := _job_rec()
	var job := _job_dict()
	if not rec.is_empty():
		const ST := preload("res://scripts/job_store.gd")
		K.label(vb, "Fiş #%d · %s" % [int(rec.ticket), str(rec.name)], 16, T.TEXT, "BoldLabel")
		var l1 := K.label(vb, ST.short_goal(rec), 14, T.MUTED)
		l1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l1.custom_minimum_size = Vector2(250, 0)
		K.label(vb, "Teslim: %s · %s" % [ST.due_label(float(rec.due_abs), Game.day), ST.status_text(rec, Game.now_abs())], 14, T.ACCENT)
		if _looks_fixed(rec):
			var ok := K.label(vb, "Tamir tamam gibi — rafa koy", 15, T.GOOD, "BoldLabel")
			ok.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ok.custom_minimum_size = Vector2(250, 0)
	elif not job.is_empty():
		K.label(vb, str(job.get("name", "")), 16, T.TEXT, "BoldLabel")
		var intro := str(job.get("intro", job.get("goal", "")))
		if intro != "":
			var l := K.label(vb, intro, 14, T.MUTED)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(250, 0)
	K.hsep(vb)
	K.label(vb, "YAPILACAKLAR", 12, T.MUTED, "SmallCaps")
	for it in _checklist():
		var l := K.label(vb, ("[x] " if it[1] else "[  ] ") + it[0], 15, T.GOOD if it[1] else T.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(250, 0)
	K.hsep(vb)
	K.label(vb, "CİHAZ", 12, T.MUTED, "SmallCaps")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	var open_label := "Kapağı aç"
	match kind:
		"pc":
			open_label = "Kapağı kapat" if device.panel_open else "Kapağı aç"
		"laptop":
			open_label = "Düzelt" if device.panel_open else "Ters çevir"
		_:
			open_label = "Ekranı indir" if device.panel_open else "Ekranı kaldır"
	var b1 := K.button(row, open_label, toggle_panel, "", 16, Vector2(0, 38))
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b2 := K.button(row, "Kapat" if device.powered else "Güç", press_power, "", 16, Vector2(0, 38))
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not tools.is_empty():
		K.label(vb, "ALETLER", 12, T.MUTED, "SmallCaps")
		for t in tools:
			var tb := K.button(vb, t.display_name + ("  (seçili)" if t == tool else ""), select_tool.bind(t),
				"PrimaryButton" if t == tool else "", 16, Vector2(0, 36))
			tb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	K.label(vb, "TEPSİ (%d)" % tray_parts.size(), 12, T.MUTED, "SmallCaps")
	if tray_parts.is_empty():
		var e := K.label(vb, "Boş. Söktüğün parçalar buraya iner.", 14, T.MUTED)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.custom_minimum_size = Vector2(250, 0)
	for p in tray_parts:
		var sel: bool = p == selected
		var pb := K.button(vb, p.display_name, (cancel_selection if sel else select_part.bind(p)), "PrimaryButton" if sel else "", 16, Vector2(0, 36))
		pb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_side.reset_size()
	_side.call_deferred("reset_size")  # otomatik satır kaydırmalı etiketler yerleşince yeniden boyutla


## Tezgâh modunu zorla kapatan durum (boş = devam). Kendiliğinden kapanma şikâyetinin teşhisi için ayrı tutuldu.
func _force_exit_reason() -> String:
	if not is_instance_valid(device):
		return "cihaz yok oldu"
	if Game.bench_device != device:
		return "tezgâhtaki cihaz değişti"
	if Game.phase != "day":
		return "gün bitti (%s)" % Game.phase
	if Game.ui_modal:
		return "bir menü açıldı"
	return ""


## Kendiliğinden kapanmayı oyuncuya ve konsola bildir (hata ayıklama için).
func _report_exit(why: String) -> void:
	push_warning("Tezgâh modu kapandı: " + why)
	Game.msg("Tezgâh modu kapandı: " + why, Color(1.0, 0.75, 0.4))
