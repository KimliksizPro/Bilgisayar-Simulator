extends Node3D
## Ana sahne: dükkânı, ışıkları, rafları kurar; oyuncuyu ve iş yöneticisini başlatır.

const MU := preload("res://scripts/mesh_util.gd")
const PM := preload("res://scripts/part_models.gd")
const PART := preload("res://scripts/part.gd")
const TOOL := preload("res://scripts/tool.gd")
const PLAYER := preload("res://scripts/player.gd")
const HUD := preload("res://scripts/hud.gd")
const MONITOR := preload("res://scripts/monitor.gd")
const JOBS := preload("res://scripts/job_manager.gd")
const MENU := preload("res://scripts/menu.gd")
const DELIVERY := preload("res://scripts/delivery.gd")
const DEVICE_RACK := preload("res://scripts/device_rack.gd")  # laptop / telefon parça rafı
const PROPS := preload("res://scripts/props.gd")

const DESK_Y := 0.75

var hud
var delivery
var monitor
var player
var menu
var menu_cam: Camera3D
var _menu_t := 0.0
var sun: DirectionalLight3D
var street_light: OmniLight3D
var sign_light: OmniLight3D
var _day_env := {}


func _ready() -> void:
	randomize()
	_setup_input()
	_build_environment()
	_build_room()
	_build_outside()
	_build_desk()
	_build_tools()
	_build_shelf()
	DEVICE_RACK.build(self)
	_build_counter()
	_build_decor()
	MU.no_merge(monitor)
	MU.merge_static(self)
	_build_upgrades()  # birleştirmeden sonra: açılıp kapanan nesneler
	hud = HUD.new()
	add_child(hud)
	player = PLAYER.new()
	player.position = Vector3(0.9, 0, -0.9)
	player.rotation_degrees.y = 15
	add_child(player)
	var jobs = JOBS.new()
	jobs.world = self
	jobs.monitor = monitor
	jobs.hud = hud
	jobs.pc_spot = Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(-90), 0)), Vector3(0.45, DESK_Y + 0.012, -2.52))
	add_child(jobs)
	jobs.start()
	delivery = DELIVERY.new()
	delivery.world = self
	add_child(delivery)
	add_child(preload("res://scripts/staff.gd").new().setup(self, jobs, delivery))  # PERSONEL: çalışanlar
	Settings.changed.connect(func(k): if k == "quality": _apply_quality())
	if not Game.dev_mode:
		_start_menu()
	if "--shot" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/screenshot.gd"):
		add_child(load("res://dev/screenshot.gd").new())
	if "--uishot" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/ui_shot.gd"):
		add_child(load("res://dev/ui_shot.gd").new())
	if "--menushot" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/menu_shot.gd"):
		add_child(load("res://dev/menu_shot.gd").new())
	if "--flowtest" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/flow_test.gd"):
		add_child(load("res://dev/flow_test.gd").new())
	if "--perf" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/perf.gd"):
		add_child(load("res://dev/perf.gd").new())
	if "--propshot" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/props_shot.gd"):
		add_child(load("res://dev/props_shot.gd").new())
	if "--partshot" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/parts_shot.gd"):
		add_child(load("res://dev/parts_shot.gd").new())
	if "--jobdisttest" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/job_dist_test.gd"):
		add_child(load("res://dev/job_dist_test.gd").new())
	if "--holdtest" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/hold_test.gd"):
		add_child(load("res://dev/hold_test.gd").new())
	if "--holdshot" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/hold_shot.gd"):
		add_child(load("res://dev/hold_shot.gd").new())
	if "--looptest" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/loop_test.gd"):
		Engine.time_scale = 4.0
		add_child(load("res://dev/loop_test.gd").new())
	if "--savetest" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/save_test.gd"):
		add_child(load("res://dev/save_test.gd").new())


## Ana menü: akşamüstü, sokağın karşısından dükkânın vitrinine bakan, yavaşça süzülen kamera.
func _start_menu() -> void:
	menu_cam = Camera3D.new()
	menu_cam.fov = 50.0
	menu_cam.near = 0.05
	add_child(menu_cam)
	menu_cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = MENU.new()
	menu.start_game.connect(_begin_game)
	add_child(menu)
	hud.visible = false
	_set_evening(true)
	_drift_camera()


## Menü için akşam ışığı: gökyüzü ve güneş kısılır, tabela ve sokak lambası yanar.
func _set_evening(on: bool) -> void:
	if on:
		_day_env = {"bg": env.background_energy_multiplier, "amb": env.ambient_light_energy,
			"sun": sun.light_energy, "sun_col": sun.light_color, "sun_rot": sun.rotation_degrees, "exp": env.tonemap_exposure}
		env.background_energy_multiplier = 0.15
		env.ambient_light_energy = 0.12
		sun.light_energy = 0.45
		sun.light_color = Color(1.0, 0.55, 0.3)
		sun.rotation_degrees = Vector3(-9, 60, 0)
		env.tonemap_exposure = 1.25
		street_light.light_energy = 2.2
		sign_light.light_energy = 1.2
	elif not _day_env.is_empty():
		env.background_energy_multiplier = _day_env.bg
		env.ambient_light_energy = _day_env.amb
		sun.light_energy = _day_env.sun
		sun.light_color = _day_env.sun_col
		sun.rotation_degrees = _day_env.sun_rot
		env.tonemap_exposure = _day_env.exp
		street_light.light_energy = 0.0
		sign_light.light_energy = 0.0


func _drift_camera() -> void:
	# sokağın karşısından vitrine; hafif yatay salınım ve nefes alma
	var a := _menu_t * 0.08
	var pos := Vector3(-2.7 + sin(a) * 0.45, 1.7 + sin(a * 1.6) * 0.05, 11.4 + cos(a * 0.7) * 0.25)
	var look := Vector3(-1.9 + sin(a * 0.8) * 0.12, 2.3, 3.1)
	menu_cam.look_at_from_position(pos, look)


func _process(delta: float) -> void:
	if is_instance_valid(menu_cam):
		_menu_t += delta
		_drift_camera()


## Menüden oyuna geçiş: karart, oyunu başlat, oyuncu kamerasına geç, aç.
func _begin_game(continue_game: bool) -> void:
	await Game.fader.fade(1.0, 0.5)
	if continue_game:
		Game.continue_game()
	else:
		Game.new_game()
	menu.queue_free()
	menu = null
	menu_cam.queue_free()
	menu_cam = null
	_set_evening(false)
	player.cam.make_current()
	hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await Game.fader.fade(0.0, 0.7)


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"interact": [KEY_E], "interact_alt": [KEY_F], "drop": [KEY_G], "sprint": [KEY_SHIFT],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("interact", lmb)
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("drop", rmb)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		Settings.set_opt("quality", (Settings.quality + 1) % 3)
		Game.msg("Grafik kalitesi: %s" % Settings.QUALITY_NAMES[Settings.quality].to_upper(), Color(0.6, 0.9, 1.0))


var env: Environment


func _build_environment() -> void:
	env = Environment.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/hdri/street.hdr")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(200), 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, 24, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 14.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.light_volumetric_fog_energy = 1.5
	add_child(sun)
	var probe := ReflectionProbe.new()
	probe.size = Vector3(8.0, 3.0, 6.0)
	probe.position = Vector3(0, 1.5, 0)
	probe.box_projection = true
	probe.interior = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	add_child(probe)
	_apply_quality()


## Yüksek: SDFGI (yansıyan ışık), SSIL, SSR yansımalar, hacimsel sis, SSAO.
## Orta: sadece SSAO + SSR. Düşük: hepsi kapalı, gölgeler hafifletilmiş.
func _apply_quality() -> void:
	var q: int = Settings.quality
	env.sdfgi_enabled = q == 2
	env.sdfgi_use_occlusion = true
	env.sdfgi_min_cell_size = 0.1
	env.sdfgi_cascades = 3
	env.sdfgi_energy = 1.1
	env.ssil_enabled = q == 2
	env.ssil_intensity = 0.8
	env.ssao_enabled = q >= 1
	env.ssr_enabled = q >= 1
	env.ssr_max_steps = 48 if q == 2 else 24
	env.volumetric_fog_enabled = q == 2
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(1.0, 0.97, 0.92)
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_ambient_inject = 0.0
	env.glow_enabled = q >= 1
	if sun:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q >= 1 else DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 14.0 if q >= 1 else 9.0
		sun.shadow_blur = 1.5 if q == 2 else 1.0
	get_viewport().positional_shadow_atlas_size = 4096 if q == 2 else (2048 if q == 1 else 1024)


func _build_room() -> void:
	var floor_m := MU.pbr("floor", 0.7)
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 6)
	var fl := MeshInstance3D.new()
	fl.mesh = pm
	fl.material_override = floor_m
	add_child(fl)
	MU.static_box(self, Vector3(8.4, 0.2, 6.4), Vector3(0, -0.1, 0), null)
	var wall := MU.pbr("wall", 0.45, Color(1.0, 0.96, 0.88), 0.4)
	var trim := MU.pbr("wall", 0.45, Color(0.32, 0.42, 0.5), 0.6)
	var white := MU.pbr("wall", 0.45, Color(1.0, 1.0, 1.0), 0.3)
	MU.static_box(self, Vector3(8.4, 3, 0.2), Vector3(0, 1.5, -3.1), wall)
	MU.static_box(self, Vector3(0.2, 3, 6.2), Vector3(-4.1, 1.5, 0), wall)
	MU.static_box(self, Vector3(0.2, 3, 6.2), Vector3(4.1, 1.5, 0), wall)
	# alt lambri + süpürgelik
	MU.box(self, Vector3(8.0, 0.9, 0.02), Vector3(0, 0.45, -2.995), trim)
	MU.box(self, Vector3(0.02, 0.9, 6.0), Vector3(-3.995, 0.45, 0), trim)
	MU.box(self, Vector3(0.02, 0.9, 6.0), Vector3(3.995, 0.45, 0), trim)
	var rail := MU.mat(Color(0.92, 0.9, 0.86), 0, 0.5)
	MU.rbox(self, Vector3(8.0, 0.04, 0.04), Vector3(0, 0.9, -2.985), rail, 0.01)
	MU.rbox(self, Vector3(0.04, 0.04, 6.0), Vector3(-3.985, 0.9, 0), rail, 0.01)
	MU.rbox(self, Vector3(0.04, 0.04, 6.0), Vector3(3.985, 0.9, 0), rail, 0.01)
	var base_m := MU.mat(Color(0.15, 0.17, 0.2), 0, 0.6)
	MU.rbox(self, Vector3(8.0, 0.1, 0.03), Vector3(0, 0.05, -2.985), base_m, 0.008)
	MU.rbox(self, Vector3(0.03, 0.1, 6.0), Vector3(-3.985, 0.05, 0), base_m, 0.008)
	MU.rbox(self, Vector3(0.03, 0.1, 6.0), Vector3(3.985, 0.05, 0), base_m, 0.008)
	# ön vitrin + kapı boşluğu
	var frame := MU.mat(Color(0.18, 0.18, 0.2), 0.85, 0.3)
	var brick := MU.pbr("brick", 0.5, Color(0.75, 0.75, 0.78))
	for side in [-1, 1]:
		var cx: float = side * 2.475
		var seg := StaticBody3D.new()
		seg.position = Vector3(cx, 0, 3.1)
		add_child(seg)
		MU.add_box_shape(seg, Vector3(3.45, 3, 0.2), Vector3(0, 1.5, 0))
		MU.box(seg, Vector3(3.45, 0.5, 0.2), Vector3(0, 0.25, 0), trim)
		MU.box(seg, Vector3(3.45, 0.5, 0.02), Vector3(0, 0.25, 0.11), brick)
		MU.box(seg, Vector3(3.45, 1.9, 0.02), Vector3(0, 1.45, 0), MU.glass())
		MU.box(seg, Vector3(3.45, 0.6, 0.2), Vector3(0, 2.7, 0), wall)
		MU.box(seg, Vector3(3.45, 0.6, 0.02), Vector3(0, 2.7, 0.11), brick)
		MU.rbox(seg, Vector3(3.45, 0.05, 0.22), Vector3(0, 0.52, 0), frame, 0.01)
		MU.rbox(seg, Vector3(3.45, 0.05, 0.22), Vector3(0, 2.4, 0), frame, 0.01)
		for k in [-1, 0, 1]:
			MU.rbox(seg, Vector3(0.05, 1.9, 0.22), Vector3(k * 1.7, 1.45, 0), frame, 0.01)
	MU.static_box(self, Vector3(1.5, 0.6, 0.2), Vector3(0, 2.7, 3.1), wall)
	for x in [-0.725, 0.725]:
		MU.rbox(self, Vector3(0.06, 2.4, 0.24), Vector3(x, 1.2, 3.1), frame, 0.012)
	# "AÇIK" neon tabelası (camda, dışarı bakar)
	var open_sign := MU.label(self, "AÇIK", Vector3(1.4, 1.9, 3.05), 120, Color(0.3, 1.0, 0.5), Vector3(0, 180, 0), 0.0025)
	open_sign.shaded = false
	open_sign.double_sided = false
	open_sign.outline_size = 20
	open_sign.outline_modulate = Color(0.2, 1.0, 0.4, 0.3)
	# giriş paspası
	MU.rbox(self, Vector3(1.2, 0.015, 0.7), Vector3(0, 0.008, 2.55), MU.mat(Color(0.25, 0.2, 0.18), 0, 1.0), 0.006)
	# tavan ve lambalar
	MU.box(self, Vector3(8.4, 0.1, 6.4), Vector3(0, 3.05, 0), white)
	var lamp_m := MU.mat(Color(1.0, 0.97, 0.9), 0, 0.5, 5.0)
	var fixture := MU.mat(Color(0.85, 0.85, 0.87), 0.6, 0.35)
	for p in [Vector3(-1.6, 0, -1.2), Vector3(1.6, 0, -1.2), Vector3(-0.8, 0, 1.6)]:
		MU.rbox(self, Vector3(1.3, 0.05, 0.38), Vector3(p.x, 2.975, p.z), fixture, 0.012)
		MU.box(self, Vector3(1.2, 0.01, 0.3), Vector3(p.x, 2.948, p.z), lamp_m)
		var l := OmniLight3D.new()
		l.position = Vector3(p.x, 2.7, p.z)
		l.omni_range = 6.0
		l.omni_attenuation = 1.2
		l.light_energy = 1.0
		l.light_color = Color(1.0, 0.93, 0.82)
		l.light_size = 0.3
		l.shadow_enabled = p.x > 0.0  # sadece masa üstündeki lamba gölge düşürür
		l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		add_child(l)
	# klima
	var ac := MU.rbox(self, Vector3(0.9, 0.28, 0.2), Vector3(-2.2, 2.6, -2.88), MU.mat(Color(0.95, 0.95, 0.94), 0, 0.35), 0.04)
	for i in 6:
		MU.box(ac, Vector3(0.75, 0.006, 0.02), Vector3(0, -0.06 - i * 0.012, 0.1), MU.mat(Color(0.8, 0.8, 0.8)))
	# prizler
	for x in [-1.2, 1.2]:
		var o := MU.rbox(self, Vector3(0.08, 0.08, 0.015), Vector3(x, 0.35, -2.99), MU.mat(Color(0.95, 0.95, 0.93), 0, 0.4), 0.008)
		MU.cyl(o, 0.022, 0.01, Vector3(0, 0, 0.007), MU.mat(Color(0.8, 0.8, 0.78)), Vector3(90, 0, 0), 16)


func _build_outside() -> void:
	MU.static_box(self, Vector3(60, 0.2, 40), Vector3(0, -0.11, 23.2), MU.pbr("asphalt", 0.25))
	MU.static_box(self, Vector3(60, 0.15, 4.0), Vector3(0, -0.07, 5.2), MU.pbr("paving", 0.5))
	MU.rbox(self, Vector3(60, 0.16, 0.2), Vector3(0, -0.07, 7.2), MU.mat(Color(0.6, 0.6, 0.58), 0, 0.8), 0.03)
	for i in 12:
		MU.box(self, Vector3(1.6, 0.02, 0.15), Vector3(-26 + i * 5, 0.0, 11.0), MU.mat(Color(0.9, 0.9, 0.85), 0, 0.7))
	# dış cephe (tuğla)
	var brick := MU.pbr("brick", 0.5, Color(0.75, 0.75, 0.78))
	for x in [-6.5, 6.5]:
		MU.static_box(self, Vector3(4.6, 4.5, 0.4), Vector3(x, 2.25, 3.1), brick)
	MU.box(self, Vector3(8.6, 1.3, 0.4), Vector3(0, 3.65, 3.1), brick)
	_build_storefront()


## Vitrin: ışıklı kutu tabela, neon çerçeve, çizgili tente, vitrin yazıları, bayrak tabela,
## kaldırım panosu, saksılar ve sokak lambası. Ana menü kamerası buraya bakar.
func _build_storefront() -> void:
	var sign_font: Font = load("res://assets/fonts/Bungee.ttf")
	var hand_font: Font = load("res://assets/fonts/Caveat.ttf")
	var metal := MU.mat(Color(0.12, 0.12, 0.13), 0.7, 0.35)
	# --- ışıklı kutu tabela ---
	var sg := Node3D.new()
	sg.position = Vector3(0, 3.74, 3.36)
	add_child(sg)
	MU.rbox(sg, Vector3(5.6, 1.0, 0.2), Vector3.ZERO, metal, 0.03)
	MU.box(sg, Vector3(5.4, 0.82, 0.02), Vector3(0, 0, 0.1), MU.mat(Color(0.05, 0.09, 0.22), 0, 0.35, 1.4))
	var neon := MU.mat(Color(0.35, 0.9, 1.0), 0, 0.3, 6.0)
	for y in [-0.43, 0.43]:
		MU.cyl(sg, 0.012, 5.46, Vector3(0, y, 0.115), neon, Vector3(0, 0, 90), 8)
	for x in [-2.73, 2.73]:
		MU.cyl(sg, 0.012, 0.86, Vector3(x, 0, 0.115), neon, Vector3.ZERO, 8)
	var big := MU.label(sg, "BİLGİSAYARCI", Vector3(0, 0.07, 0.115), 200, Color(1.0, 0.75, 0.22), Vector3.ZERO, 0.0026)
	big.font = sign_font
	big.shaded = false
	big.double_sided = false
	big.outline_size = 28
	big.outline_modulate = Color(1.0, 0.55, 0.1, 0.35)
	var small := MU.label(sg, "TAMİR  ·  BAKIM  ·  YEDEK PARÇA  ·  KASA TOPLAMA", Vector3(0, -0.29, 0.115), 64, Color(0.92, 0.95, 1.0), Vector3.ZERO, 0.0022)
	small.font = sign_font
	small.shaded = false
	small.double_sided = false
	# tabela askı kolları
	for x in [-2.2, 2.2]:
		MU.cyl(sg, 0.02, 0.3, Vector3(x, 0.55, -0.05), metal, Vector3(70, 0, 0), 8)
	# --- çizgili tente ---
	var red := MU.mat(Color(0.72, 0.12, 0.12), 0, 0.85)
	var cream := MU.mat(Color(0.93, 0.9, 0.82), 0, 0.85)
	var aw := Node3D.new()
	aw.position = Vector3(0, 2.98, 3.72)
	aw.rotation_degrees = Vector3(-22, 0, 0)
	add_child(aw)
	var n := 16
	for i in n:
		var x := -4.0 + (i + 0.5) * 8.0 / n
		MU.box(aw, Vector3(8.0 / n, 0.03, 1.0), Vector3(x, 0, 0), red if i % 2 == 0 else cream)
		# ön saçak (dikey sarkan şerit)
		var flap := Node3D.new()
		flap.position = Vector3(x, 0, 0.5)
		flap.rotation_degrees = Vector3(22, 0, 0)
		aw.add_child(flap)
		MU.box(flap, Vector3(8.0 / n, 0.24, 0.02), Vector3(0, -0.12, 0), red if i % 2 == 0 else cream)
	for x in [-3.9, 3.9]:
		MU.cyl(self, 0.015, 1.15, Vector3(x, 2.75, 3.68), metal, Vector3(-55, 0, 0), 6)
	# --- vitrin camı yazıları (dışarıdan okunur) ---
	var vin := [["LAPTOP · PC · KASA", Vector3(-1.625, 2.08, 3.13), 46],
		["HIZLI SERVİS", Vector3(-1.625, 1.9, 3.13), 66],
		["ANAKART · EKRAN KARTI\nRAM · SSD · GÜÇ KAYNAĞI", Vector3(3.325, 2.02, 3.13), 38]]
	for v in vin:
		var vl := MU.label(self, v[0], v[1], v[2], Color(1, 1, 1, 0.9), Vector3.ZERO, 0.0022)
		vl.font = sign_font
		vl.double_sided = false
	var neon_open := MU.label(self, "AÇIK", Vector3(1.4, 1.62, 3.13), 140, Color(0.3, 1.0, 0.5), Vector3.ZERO, 0.0024)
	neon_open.font = sign_font
	neon_open.shaded = false
	neon_open.double_sided = false
	neon_open.outline_size = 24
	neon_open.outline_modulate = Color(0.2, 1.0, 0.4, 0.35)
	var hours := MU.label(self, "Pzt - Cmt  09:00 - 19:00", Vector3(1.4, 1.4, 3.13), 40, Color(1, 1, 1, 0.85), Vector3.ZERO, 0.0018)
	hours.double_sided = false
	# --- bayrak tabela (duvara dik) ---
	var blade := Node3D.new()
	blade.position = Vector3(4.5, 3.05, 3.85)
	blade.rotation_degrees = Vector3(0, 90, 0)
	add_child(blade)
	MU.cyl(self, 0.02, 0.6, Vector3(4.5, 3.62, 3.6), metal, Vector3(90, 0, 0), 8)
	MU.rbox(blade, Vector3(0.95, 0.95, 0.08), Vector3.ZERO, MU.mat(Color(1.0, 0.7, 0.18), 0, 0.4, 0.6), 0.03)
	for side in [1, -1]:
		var bl := MU.label(blade, "PC\nTAMİR", Vector3(0, 0, side * 0.045), 120, Color(0.08, 0.08, 0.1), Vector3(0, 0 if side > 0 else 180, 0), 0.0028)
		bl.font = sign_font
		bl.double_sided = false
	# --- kaldırım panosu (kara tahta, A tipi) ---
	var board := Node3D.new()
	board.position = Vector3(2.35, 0, 4.7)
	board.rotation_degrees = Vector3(0, -18, 0)
	add_child(board)
	var wood := MU.mat(Color(0.45, 0.3, 0.18), 0, 0.8)
	var chalk := MU.mat(Color(0.1, 0.16, 0.13), 0, 0.95)
	for side in [1, -1]:
		var face := Node3D.new()
		face.position = Vector3(0, 0.5, side * 0.17)
		face.rotation_degrees = Vector3(side * -12, 0 if side > 0 else 180, 0)
		board.add_child(face)
		MU.rbox(face, Vector3(0.66, 1.02, 0.03), Vector3.ZERO, wood, 0.01)
		MU.box(face, Vector3(0.56, 0.9, 0.01), Vector3(0, 0, 0.017), chalk)
		var t := MU.label(face, "BUGÜN", Vector3(0, 0.33, 0.024), 90, Color(1.0, 0.85, 0.3), Vector3.ZERO, 0.0016)
		t.font = hand_font
		t.double_sided = false
		var b := MU.label(face, "Fan temizliği\n+ termal macun\n\n%20 indirim!", Vector3(0, -0.04, 0.024), 72, Color(0.95, 0.95, 0.92), Vector3.ZERO, 0.0016)
		b.font = hand_font
		b.double_sided = false
	# --- kapı yanı saksılar ---
	var pot := MU.mat(Color(0.25, 0.25, 0.27), 0.2, 0.6)
	var bush := MU.mat(Color(0.16, 0.36, 0.15), 0, 0.8)
	for x in [-1.15, 1.15]:
		MU.rbox(self, Vector3(0.42, 0.5, 0.42), Vector3(x, 0.25, 3.62), pot, 0.03)
		MU.sphere(self, 0.3, Vector3(x, 0.72, 3.62), bush, Vector3(1.0, 1.15, 1.0))
		MU.sphere(self, 0.2, Vector3(x + 0.12, 0.95, 3.58), bush)
	# --- sokak lambası ---
	var pole := MU.mat(Color(0.16, 0.2, 0.18), 0.6, 0.5)
	MU.cyl(self, 0.07, 4.6, Vector3(5.6, 2.3, 6.7), pole, Vector3.ZERO, 12)
	MU.cyl(self, 0.12, 0.3, Vector3(5.6, 0.15, 6.7), pole, Vector3.ZERO, 12)
	MU.cyl(self, 0.035, 1.1, Vector3(5.6, 4.5, 6.2), pole, Vector3(90, 0, 0), 8)
	MU.rbox(self, Vector3(0.36, 0.12, 0.5), Vector3(5.6, 4.48, 5.7), pole, 0.03)
	MU.box(self, Vector3(0.3, 0.01, 0.42), Vector3(5.6, 4.415, 5.7), MU.mat(Color(1.0, 0.85, 0.6), 0, 0.5, 6.0))
	street_light = OmniLight3D.new()
	street_light.position = Vector3(5.6, 4.2, 5.7)
	street_light.light_color = Color(1.0, 0.78, 0.5)
	street_light.light_energy = 0.0
	street_light.omni_range = 9.0
	add_child(street_light)
	# tabela ışığı (akşam sahnesinde cepheyi aydınlatır)
	sign_light = OmniLight3D.new()
	sign_light.position = Vector3(0, 3.5, 4.6)
	sign_light.light_color = Color(0.55, 0.75, 1.0)
	sign_light.light_energy = 0.0
	sign_light.omni_range = 5.0
	add_child(sign_light)


func _build_desk() -> void:
	var wood := MU.pbr("wood", 0.8)
	MU.rbox(self, Vector3(2.6, 0.05, 0.8), Vector3(0.25, DESK_Y - 0.025, -2.5), wood, 0.012)
	var leg := MU.mat(Color(0.12, 0.12, 0.13), 0.85, 0.35)
	for x in [-0.98, 1.48]:
		for z in [-2.83, -2.17]:
			MU.rbox(self, Vector3(0.05, DESK_Y - 0.05, 0.05), Vector3(x, (DESK_Y - 0.05) / 2, z), leg, 0.01)
	MU.rbox(self, Vector3(2.5, 0.08, 0.03), Vector3(0.25, DESK_Y - 0.09, -2.85), leg, 0.008)
	MU.static_box(self, Vector3(2.6, DESK_Y, 0.8), Vector3(0.25, DESK_Y / 2, -2.5), null)
	MU.rbox(self, Vector3(1.0, 0.004, 0.5), Vector3(0.55, DESK_Y + 0.002, -2.45), MU.mat(Color(0.12, 0.3, 0.55), 0, 0.95), 0.002)
	monitor = MONITOR.new()
	monitor.position = Vector3(-0.5, DESK_Y, -2.72)
	add_child(monitor)
	# klavye, fare, telefon
	PROPS.keyboard(self, Vector3(-0.5, DESK_Y, -2.31))
	PROPS.mousepad(self, Vector3(-0.13, DESK_Y, -2.3))
	PROPS.mouse(self, Vector3(-0.12, DESK_Y + 0.003, -2.27), -8.0)
	PROPS.phone(self, Vector3(-0.87, DESK_Y, -2.32), 18.0, Color(0.16, 0.2, 0.32), true, "09:41")
	# masa lambası
	var lamp_rot := Vector3(-60, -35, 0)
	var lamp_bulb := Vector3(1.19, DESK_Y + 0.4, -2.65)
	PROPS.desk_lamp(self, Vector3(1.3, DESK_Y, -2.78), lamp_bulb, Basis.from_euler(lamp_rot * PI / 180.0) * Vector3.FORWARD, Color(0.85, 0.25, 0.18))
	var dl := SpotLight3D.new()
	dl.position = lamp_bulb
	dl.rotation_degrees = lamp_rot
	dl.spot_range = 2.0
	dl.spot_angle = 45
	dl.light_energy = 2.0
	dl.light_color = Color(1.0, 0.85, 0.65)
	dl.shadow_enabled = true
	add_child(dl)
	# tornavida ve kupa
	PROPS.screwdriver(self, Vector3(0.955, DESK_Y + 0.0125, -2.25))
	PROPS.mug(self, Vector3(-1.0, DESK_Y, -2.6), Color(0.95, 0.95, 0.92), 200.0)
	# arıza rehberi posteri
	var poster := MU.rbox(self, Vector3(1.3, 0.85, 0.012), Vector3(-0.2, 1.8, -2.99), MU.mat(Color(0.97, 0.95, 0.9), 0, 0.8), 0.004)
	MU.box(poster, Vector3(1.3, 0.12, 0.014), Vector3(0, 0.365, 0), MU.mat(Color(0.75, 0.15, 0.15), 0, 0.7))
	var t1 := MU.label(poster, "ARIZA REHBERİ", Vector3(0, 0.365, 0.009), 64, Color.WHITE, Vector3.ZERO, 0.0012)
	t1.double_sided = false
	var t2 := MU.label(poster, "• Hiçbir tepki yok  →  Güç Kaynağı (PSU)\n• Fan dönüyor, bip yok, görüntü yok  →  İşlemci (CPU)\n• Sürekli kısa bipler  →  RAM\n• 1 uzun 3 kısa bip  →  Ekran Kartı (GPU)\n• \"Boot device\" hatası  →  SSD\n• Açılıp kendi kendine kapanma  →  Toz / Termal Macun\n• Tek kısa bip  →  Her şey yolunda!", Vector3(0, -0.06, 0.009), 34, Color(0.12, 0.12, 0.14), Vector3.ZERO, 0.0011)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t2.line_spacing = 6
	t2.double_sided = false
	for c in [Vector2(-0.6, 0.38), Vector2(0.6, 0.38), Vector2(-0.6, -0.38), Vector2(0.6, -0.38)]:
		MU.sphere(poster, 0.008, Vector3(c.x, c.y, 0.008), MU.mat(Color(0.2, 0.4, 0.9), 0.3, 0.3))
	# hurda kutusu
	var bin_m := MU.mat(Color(0.2, 0.38, 0.28), 0.5, 0.45)
	MU.lathe(self, PackedVector2Array([Vector2(0, 0), Vector2(0.195, 0), Vector2(0.2, 0.012), Vector2(0.2, 0.012), Vector2(0.221, 0.48),
		Vector2(0.221, 0.48), Vector2(0.232, 0.486), Vector2(0.233, 0.505), Vector2(0.226, 0.51), Vector2(0.212, 0.5),
		Vector2(0.192, 0.04), Vector2(0, 0.035)]), Vector3(1.85, 0, -2.55), bin_m, 32)
	for k in 3:
		MU.lathe(self, PackedVector2Array([Vector2(0.2045 + k * 0.0045 * 2.2, 0.08 + k * 0.1), Vector2(0.2065 + k * 0.0045 * 2.2, 0.09 + k * 0.1)]), Vector3(1.85, 0, -2.55), MU.mat(Color(0.12, 0.2, 0.15), 0.5, 0.4), 32)
	var bl := MU.label(self, "HURDA", Vector3(1.85, 0.3, -2.55 + 0.2145), 60, Color(0.95, 0.95, 0.9), Vector3.ZERO, 0.0012)
	bl.double_sided = false
	MU.interactable(self, Vector3(0.46, 0.55, 0.46), Vector3(1.85, 0.27, -2.55), _bin_hint, _bin_use)


## Masadaki aletler: termal macun ve basınçlı hava.
func _build_tools() -> void:
	var tools := [["paste", Vector3(0.95, DESK_Y + 0.016, -2.5), 20.0], ["air", Vector3(1.13, DESK_Y + 0.096, -2.42), 0.0]]
	for t in tools:
		var tool = TOOL.new().setup(t[0])
		add_child(tool)
		tool.position = t[1]
		tool.rotation_degrees.y = t[2]
		tool.freeze = true


func _bin_hint(p) -> String:
	if p.held and p.held.is_tool():
		return "Aletler hurdaya atılmaz"
	if p.held:
		if p.held.broken:
			return "Arızalı parçayı at  [E]"
		return "Hurdaya sat: %s (+%d TL)  [E]" % [p.held.display_name, int(p.held.value() * 0.4)]
	return "Hurda kutusu"


func _bin_use(p) -> void:
	if p.held == null or p.held.is_tool():
		return
	var part = p.release_held()
	if part.broken:
		Game.msg("Arızalı %s hurdaya atıldı." % part.display_name)
	else:
		var v := int(part.value() * 0.4)
		Game.add_money(v)
		Game.msg("Hurdacıya sattın: +%d TL" % v, Color(0.5, 1, 0.5))
	Game.sfx.click()
	part.queue_free()


func _build_shelf() -> void:
	var x0 := -3.75
	var wood := MU.pbr("laminate", 1.0)
	var zc := -0.7
	var length := 3.0
	for z in [zc - length / 2, zc + length / 2]:
		MU.static_box(self, Vector3(0.42, 2.1, 0.04), Vector3(x0, 1.05, z), null)
		MU.rbox(self, Vector3(0.42, 2.1, 0.04), Vector3(x0, 1.05, z), wood, 0.008)
	MU.box(self, Vector3(0.02, 2.1, length), Vector3(x0 - 0.2, 1.05, zc), MU.pbr("wall", 0.5, Color(0.85, 0.88, 0.92), 0.3))
	var levels := [0.45, 0.95, 1.45, 1.95]
	for y in levels:
		MU.static_box(self, Vector3(0.42, 0.03, length), Vector3(x0, y, zc), null)
		MU.rbox(self, Vector3(0.42, 0.03, length), Vector3(x0, y, zc), wood, 0.006)
		# raf altı LED şerit
		MU.box(self, Vector3(0.01, 0.004, length - 0.1), Vector3(x0 + 0.18, y - 0.017, zc), MU.mat(Color(1.0, 0.95, 0.85), 0, 0.5, 3.0))
	for y in [0.75, 1.25, 1.75]:
		var sl := OmniLight3D.new()
		sl.position = Vector3(x0 + 0.15, y, zc)
		sl.omni_range = 1.6
		sl.light_energy = 0.7
		sl.light_color = Color(1.0, 0.95, 0.88)
		add_child(sl)
	var title := MU.label(self, "STOK RAFI", Vector3(x0 + 0.05, 2.48, zc), 90, Color(0.15, 0.2, 0.3), Vector3(0, 90, 0), 0.0025)
	title.double_sided = false
	var items := [
		[1.45, -1.6, "gpu", 1], [1.45, -0.9, "gpu", 2],
		[0.95, -1.7, "ram", 1], [0.95, -1.35, "ram", 2], [0.95, -0.85, "cpu", 1],
		[0.45, -1.6, "psu", 1], [0.45, -1.05, "ssd", 1],
	]
	for it in items:
		_shelf_item(x0, it[0] + 0.015, it[1] + 0.7 + zc, it[2], it[3])
	# en üst rafta süs kutuları
	var box_cols := [Color(0.15, 0.3, 0.7), Color(0.75, 0.2, 0.2), Color(0.1, 0.1, 0.12), Color(0.9, 0.6, 0.1)]
	for i in 6:
		var bs := Vector3(0.3, randf_range(0.18, 0.3), randf_range(0.2, 0.35))
		var bx := MU.rbox(self, bs, Vector3(x0, 1.965 + bs.y / 2, zc - 1.25 + i * 0.45), MU.mat(box_cols[i % 4], 0, 0.5), 0.008)
		MU.box(bx, Vector3(0.01, bs.y * 0.4, bs.z * 0.7), Vector3(0.15, 0, 0), MU.mat(Color(0.95, 0.95, 0.95), 0, 0.5))


func _shelf_item(x0: float, shelf_y: float, z: float, type: String, tier: int) -> void:
	var info: Dictionary = PM.INFO[type]
	var built := PM.build(type, tier)
	var n: Node3D = built.node
	var c: Vector3 = info.center
	var k := 1.5
	n.scale = Vector3.ONE * k
	n.position = Vector3(x0 + 0.06 - c.x * k, shelf_y + (info.size.y / 2 - c.y) * k, z - c.z * k)
	add_child(n)
	MU.no_merge(n)  # stok bitince gizlenebilsin
	var dname := PM.display_name(type, tier)
	var it = MU.interactable(self, info.size * 1.5 + Vector3(0.04, 0.04, 0.04), Vector3(x0 + 0.06, shelf_y + info.size.y * 0.75, z),
		func(p): return _shelf_hint(p, type, tier, dname),
		func(p): _shelf_use(p, type, tier))
	it.action_alt = func(p): _buy(p, type, tier, true)  # F: muadil (ucuz) parça al
	var l := MU.label(self, "", Vector3(x0 + 0.214, shelf_y - 0.045, z), 30, Color(0.1, 0.1, 0.1), Vector3(0, 90, 0), 0.001)
	l.double_sided = false
	_price_labels.append([l, dname, type, tier, n])
	var tag := MU.box(self, Vector3(0.002, 0.06, 0.24), Vector3(x0 + 0.212, shelf_y - 0.045, z), MU.mat(Color(1.0, 0.92, 0.4)))
	tag.name = "PriceTag"


func _shelf_hint(p, type: String, tier: int, dname: String) -> String:
	var n := Game.stock_of(type, tier)
	var c := Game.stock_cheap_of(type, tier)
	if p.held:
		if not p.held.is_tool() and p.held.part_type == type and p.held.tier == tier:
			return "Arızalı parça rafa konmaz" if p.held.broken else "Rafa geri koy: %s  [E]" % p.held.display_name
		return "Elin dolu"
	if n <= 0 and c <= 0:
		return "%s TÜKENDİ — laptoptan (ParçaNet) sipariş ver" % dname
	# E: orijinal, F: muadil
	if c <= 0:
		return "Al: %s  (stok %d)  [E]" % [dname, n]
	return "Al: %s  (orijinal %d [E] / muadil %d [F])" % [dname, n, c]


func _shelf_use(p, type: String, tier: int) -> void:
	if p.held:
		if not p.held.is_tool() and p.held.part_type == type and p.held.tier == tier and not p.held.broken:
			var part = p.release_held()
			var was_cheap: bool = part.cheap
			part.queue_free()
			if was_cheap:
				Game.add_stock_cheap(type, tier, 1)
			else:
				Game.add_stock(type, tier, 1)
			Game.sfx.click()
			Game.msg("%s rafa kondu (stok %d)." % [PM.display_name(type, tier) + (" (muadil)" if was_cheap else ""), Game.stock_cheap_of(type, tier) if was_cheap else Game.stock_of(type, tier)])
		return
	_buy(p, type, tier)


## Raftan parça al: stoktan düşer (parası ParçaNet siparişinde ödendi).
func _buy(p, type: String, tier: int, cheap := false) -> void:
	if p.held:
		return
	if cheap:
		if not Game.take_stock_cheap(type, tier):
			Game.msg("Muadil %s stokta yok!" % PM.display_name(type, tier), Color(1, 0.5, 0.4))
			Game.sfx.error()
			return
		var cp = PART.new().setup(type, tier, false)
		cp.make_cheap()
		add_child(cp)
		p.pick_up(cp)
		Game.sfx.click()
		return
	if not Game.take_stock(type, tier):
		Game.msg("%s stokta yok! Tezgahtaki laptoptan ParçaNet'e sipariş ver." % PM.display_name(type, tier), Color(1, 0.5, 0.4))
		Game.sfx.error()
		if Game.hud:
			Game.hud.tip("order", "Parça bitince tezgahtaki laptopu aç: ParçaNet'ten sipariş ver, kurye getirsin.")
		return
	var part = PART.new().setup(type, tier, Game.take_was_dud)  # ikinci elden gizli arızalı çıkabilir
	add_child(part)
	p.pick_up(part)
	Game.sfx.click()


var _price_labels := []   # raf etiketleri: [Label3D, ad, tür, seviye, model]
var _up_nodes := {}       # geliştirme id -> görünürlüğü açılacak düğümler


## Satın alınan geliştirmelerin fiziksel görünümleri (açılıp kapanırlar, birleştirilmez).
func _build_upgrades() -> void:
	var dark := MU.mat(Color(0.12, 0.12, 0.14), 0.5, 0.4)
	# reklam tabelası: ön duvarda, içeri bakan ışıklı tabela
	var sign_n := Node3D.new()
	sign_n.position = Vector3(-2.4, 2.72, 2.98)
	add_child(sign_n)
	MU.rbox(sign_n, Vector3(1.5, 0.42, 0.05), Vector3.ZERO, MU.mat(Color(0.1, 0.12, 0.2), 0.3, 0.4), 0.02)
	var st := MU.label(sign_n, "EN UCUZ TAMİR!\n%100 GARANTİ", Vector3(0, 0, -0.03), 60, Color(1.0, 0.9, 0.3), Vector3(0, 180, 0), 0.0016)
	st.shaded = false
	st.double_sided = false
	_up_nodes["sign"] = [sign_n]
	# kahve makinesi (tezgah ucu)
	var cm := Node3D.new()
	cm.position = Vector3(-2.55, 1.025, 1.3)
	add_child(cm)
	MU.rbox(cm, Vector3(0.2, 0.05, 0.24), Vector3(0, 0.025, 0), dark, 0.01)
	MU.rbox(cm, Vector3(0.2, 0.34, 0.2), Vector3(0, 0.22, 0.02), MU.mat(Color(0.75, 0.15, 0.12), 0.3, 0.4), 0.025)
	MU.rbox(cm, Vector3(0.14, 0.05, 0.06), Vector3(0, 0.3, -0.1), dark, 0.01)
	MU.cyl(cm, 0.035, 0.07, Vector3(0, 0.08, -0.07), MU.mat(Color(0.95, 0.95, 0.95), 0, 0.3), Vector3.ZERO, 12)
	MU.sphere(cm, 0.012, Vector3(0.07, 0.34, -0.1), MU.mat(Color(0.3, 1.0, 0.4), 0, 0.3, 3.0))
	_up_nodes["coffee"] = [cm]
	# sertifika: sağ duvarda çerçeveli
	var cert := Node3D.new()
	cert.position = Vector3(3.97, 1.7, 0.45)
	add_child(cert)
	MU.rbox(cert, Vector3(0.03, 0.5, 0.7), Vector3.ZERO, MU.mat(Color(0.55, 0.38, 0.15), 0.4, 0.4), 0.01)
	MU.rbox(cert, Vector3(0.012, 0.42, 0.62), Vector3(-0.01, 0, 0), MU.mat(Color(0.97, 0.94, 0.82), 0, 0.8), 0.004)
	var cl := MU.label(cert, "USTA\nSERTİFİKASI", Vector3(-0.018, 0.03, 0), 40, Color(0.35, 0.2, 0.05), Vector3(0, -90, 0), 0.0012)
	cl.double_sided = false
	var seal := MU.cyl(cert, 0.05, 0.01, Vector3(-0.018, -0.14, 0.2), MU.mat(Color(0.8, 0.12, 0.12), 0.3, 0.4), Vector3(0, 0, 90), 16)
	seal.name = "Seal"
	_up_nodes["cert"] = [cert]
	Game.upgrade_bought.connect(func(_id): _refresh_upgrades())
	Game.stock_changed.connect(_refresh_stock)
	_refresh_upgrades()


## Satın alınanları göster, raf fiyat etiketlerini güncelle.
func _refresh_upgrades() -> void:
	for id in _up_nodes:
		for n in _up_nodes[id]:
			n.visible = Game.has_upgrade(id)
	_refresh_stock()


## Raf etiketleri stok adedini gösterir; tükenen ürünün modeli raftan kalkar.
func _refresh_stock() -> void:
	for e in _price_labels:
		var c := Game.stock_cheap_of(e[2], e[3])
		var n := Game.stock_of(e[2], e[3]) + c
		e[0].text = "%s\n%s" % [e[1], (("STOK: %d" % (n - c) + (" +%d M" % c if c > 0 else "")) if n > 0 else "TÜKENDİ")]
		e[0].modulate = Color(0.1, 0.1, 0.1) if n > 0 else Color(0.75, 0.1, 0.08)
		e[4].visible = n > 0


func _build_counter() -> void:
	var wood := MU.pbr("wood", 0.8)
	var body_m := MU.pbr("wall", 0.6, Color(0.22, 0.3, 0.4), 0.5)
	MU.rbox(self, Vector3(3.4, 0.98, 0.6), Vector3(-1.0, 0.49, 1.3), body_m, 0.02)
	MU.rbox(self, Vector3(3.5, 0.05, 0.7), Vector3(-1.0, 1.0, 1.3), wood, 0.015)
	MU.rbox(self, Vector3(3.42, 0.06, 0.02), Vector3(-1.0, 0.06, 1.6), MU.mat(Color(0.12, 0.12, 0.13), 0.6, 0.4), 0.008)
	MU.static_box(self, Vector3(3.5, 1.03, 0.7), Vector3(-1.0, 0.515, 1.3), null)
	# yazar kasa, CRT, telefon, yönetim laptopu (oyuncu tezgahın −Z tarafında durur)
	PROPS.register(self, Vector3(-2.1, 1.025, 1.3), 180.0)
	PROPS.crt(self, Vector3(-1.4, 1.025, 1.33), 180.0)
	PROPS.phone(self, Vector3(-0.72, 1.025, 1.18), 200.0, Color(0.55, 0.12, 0.16), false)
	PROPS.laptop(self, Vector3(0.3, 1.025, 1.24), 180.0, _laptop_screen)
	MU.interactable(self, Vector3(0.4, 0.3, 0.3), Vector3(0.3, 1.175, 1.24),
		func(_p): return "Laptop: parça siparişi, kargo, geliştirmeler  [E]",
		func(_p): Game.hud.open_upgrades())
	var sticky := MU.label(self, "Kartvizit\nalınız :)", Vector3(-0.3, 1.03, 1.2), 40, Color(0.2, 0.2, 0.25), Vector3(-90, 180, 0), 0.001)
	sticky.double_sided = false
	MU.rbox(self, Vector3(0.12, 0.004, 0.1), Vector3(-0.3, 1.027, 1.2), MU.mat(Color(1.0, 0.95, 0.5), 0, 0.8), 0.002)


func _build_decor() -> void:
	var cardboard := MU.mat(Color(0.68, 0.52, 0.33), 0, 0.95)
	var tape := MU.mat(Color(0.85, 0.75, 0.55), 0, 0.5)
	var stacks := [[Vector3(3.4, 0.25, -2.5), Vector3(0.6, 0.5, 0.5), 0.0], [Vector3(3.35, 0.75, -2.5), Vector3(0.5, 0.5, 0.45), 12.0],
		[Vector3(3.5, 0.2, -1.8), Vector3(0.45, 0.4, 0.45), -8.0], [Vector3(3.3, 1.15, -2.45), Vector3(0.35, 0.3, 0.3), 25.0]]
	for s in stacks:
		var b := MU.static_box(self, s[1], s[0], null, Vector3(0, s[2], 0))
		MU.rbox(b, s[1], Vector3.ZERO, cardboard, 0.012)
		MU.box(b, Vector3(s[1].x + 0.002, 0.06, s[1].z + 0.002), Vector3(0, s[1].y / 2 - 0.02, 0), tape)
		var arrow := MU.label(b, "↑↑  KIRILIR", Vector3(0, 0, s[1].z / 2 + 0.002), 40, Color(0.25, 0.18, 0.1), Vector3.ZERO, 0.0012)
		arrow.double_sided = false
	# saksı bitkisi
	MU.cyl(self, 0.2, 0.4, Vector3(3.5, 0.2, 2.5), MU.mat(Color(0.65, 0.32, 0.2), 0, 0.7), Vector3.ZERO, 24, 0.24)
	MU.cyl(self, 0.22, 0.02, Vector3(3.5, 0.39, 2.5), MU.mat(Color(0.25, 0.17, 0.1), 0, 1.0), Vector3.ZERO, 24)
	var leaf := MU.mat(Color(0.2, 0.48, 0.2), 0, 0.6)
	for i in 14:
		var a := TAU * i / 7.0
		var piv := Node3D.new()
		piv.position = Vector3(3.5, 0.4, 2.5)
		piv.rotation = Vector3(deg_to_rad(randf_range(15, 55)), a, 0)
		add_child(piv)
		MU.sphere(piv, 0.09, Vector3(0, 0.3 + (i % 2) * 0.12, 0), leaf, Vector3(0.45, 1.9, 0.12))
	# duvar saati
	var clock := MU.cyl(self, 0.22, 0.04, Vector3(3.99, 2.2, -0.5), MU.mat(Color(0.97, 0.97, 0.97), 0, 0.3), Vector3(0, 0, 90), 32)
	MU.torus(clock, 0.21, 0.24, Vector3.ZERO, MU.mat(Color(0.12, 0.12, 0.12), 0.6, 0.3))
	MU.box(clock, Vector3(0.012, 0.012, 0.15), Vector3(0, -0.025, 0.05), MU.mat(Color(0.1, 0.1, 0.1)))
	MU.box(clock, Vector3(0.1, 0.012, 0.012), Vector3(0.04, -0.025, 0), MU.mat(Color(0.1, 0.1, 0.1)))
	# neon yazı
	var neon := MU.label(self, "★ TAMİR • TOPLAMA • YÜKSELTME ★", Vector3(3.98, 2.1, 1.5), 72, Color(1.0, 0.35, 0.8), Vector3(0, -90, 0), 0.0022)
	neon.shaded = false
	neon.double_sided = false
	neon.outline_size = 18
	neon.outline_modulate = Color(1.0, 0.3, 0.8, 0.35)
	var nl := OmniLight3D.new()
	nl.position = Vector3(3.6, 2.1, 1.5)
	nl.light_color = Color(1.0, 0.35, 0.8)
	nl.light_energy = 0.8
	nl.omni_range = 2.5
	add_child(nl)
	# duvar posterleri
	var posters := [["RGB = +10 FPS", Color(0.15, 0.1, 0.3), Color(0.4, 0.9, 1.0)], ["TERMAL MACUN\nSÜRMEYİ UNUTMA!", Color(0.95, 0.8, 0.2), Color(0.15, 0.1, 0.05)]]
	for i in posters.size():
		var pp := MU.rbox(self, Vector3(0.012, 0.6, 0.45), Vector3(3.99, 1.65, -2.2 + i * 0.65), MU.mat(posters[i][1], 0, 0.7), 0.004)
		var pl := MU.label(pp, posters[i][0], Vector3(-0.008, 0, 0), 48, posters[i][2], Vector3(0, -90, 0), 0.0012)
		pl.double_sided = false
	# sandalye
	var chair_m := MU.mat(Color(0.1, 0.1, 0.12), 0.1, 0.55)
	var fabric := MU.pbr("wall", 2.0, Color(0.2, 0.22, 0.28), 1.5)
	MU.rbox(self, Vector3(0.48, 0.08, 0.48), Vector3(0.4, 0.5, -1.75), fabric, 0.03)
	MU.rbox(self, Vector3(0.46, 0.6, 0.07), Vector3(0.4, 0.86, -1.5), fabric, 0.03, Vector3(-8, 0, 0))
	MU.cyl(self, 0.03, 0.45, Vector3(0.4, 0.25, -1.75), MU.mat(Color(0.6, 0.6, 0.62), 0.9, 0.25))
	for i in 5:
		var piv := Node3D.new()
		piv.position = Vector3(0.4, 0.05, -1.75)
		piv.rotation.y = TAU * i / 5.0
		add_child(piv)
		MU.rbox(piv, Vector3(0.28, 0.03, 0.04), Vector3(0.14, 0, 0), chair_m, 0.01)
		MU.sphere(piv, 0.025, Vector3(0.27, -0.025, 0), chair_m)
	# rafın yanında eski kasalar
	for i in 3:
		var k := MU.rbox(self, Vector3(0.2, 0.42, 0.42), Vector3(-3.6 + i * 0.03, 0.21 + i * 0.0, 1.5 - i * 0.3 * 0), MU.mat(Color(0.82, 0.8, 0.72), 0, 0.6), 0.01, Vector3(0, i * 4.0, 0))
		k.position = Vector3(-3.65, 0.21 + i * 0.42, 1.5)
		MU.rbox(k, Vector3(0.18, 0.04, 0.01), Vector3(0, 0.12, 0.21), MU.mat(Color(0.3, 0.3, 0.3)), 0.004)
	MU.static_box(self, Vector3(0.22, 1.26, 0.44), Vector3(-3.65, 0.63, 1.5), null)


## Yönetim laptopunun ekranı (bir kez çizilip dokuya pişirilir).
func _laptop_screen(root: Control) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.13)
	bg.size = root.size
	root.add_child(bg)
	var top := ColorRect.new()
	top.color = Color(0.1, 0.13, 0.2)
	top.size = Vector2(root.size.x, 52)
	root.add_child(top)
	var t := Label.new()
	t.text = "◆ BİLGİSAYARCI  ·  Yönetim Paneli"
	t.position = Vector2(20, 10)
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	root.add_child(t)
	var cards := [["Haftalık Gelir", "▲ %18", Color(0.45, 0.9, 0.55)], ["İtibar", "★★★☆☆", Color(1.0, 0.8, 0.3)], ["Geliştirmeler", "4 adet", Color(0.5, 0.75, 1.0)]]
	for i in cards.size():
		var p := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.15, 0.23)
		sb.set_corner_radius_all(10)
		p.add_theme_stylebox_override("panel", sb)
		p.position = Vector2(20 + i * 204, 72)
		p.size = Vector2(192, 92)
		root.add_child(p)
		var a := Label.new()
		a.text = cards[i][0]
		a.position = Vector2(14, 10)
		a.add_theme_font_size_override("font_size", 17)
		a.modulate = Color(1, 1, 1, 0.7)
		p.add_child(a)
		var b := Label.new()
		b.text = cards[i][1]
		b.position = Vector2(14, 38)
		b.add_theme_font_size_override("font_size", 30)
		b.add_theme_color_override("font_color", cards[i][2])
		p.add_child(b)
	# gelir grafiği
	var vals := [0.35, 0.5, 0.42, 0.62, 0.55, 0.78, 0.9]
	for i in vals.size():
		var bar := ColorRect.new()
		var h: float = vals[i] * 150.0
		bar.color = Color(0.35, 0.65, 1.0).lerp(Color(1.0, 0.75, 0.3), i / 6.0)
		bar.position = Vector2(34 + i * 52, 350 - h)
		bar.size = Vector2(34, h)
		root.add_child(bar)
	var btn := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(1.0, 0.72, 0.25)
	bsb.set_corner_radius_all(12)
	btn.add_theme_stylebox_override("panel", bsb)
	btn.position = Vector2(420, 250)
	btn.size = Vector2(196, 100)
	root.add_child(btn)
	var bl := Label.new()
	bl.text = "Paneli Aç\n[E]"
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bl.size = btn.size
	bl.add_theme_font_size_override("font_size", 26)
	bl.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05))
	btn.add_child(bl)
