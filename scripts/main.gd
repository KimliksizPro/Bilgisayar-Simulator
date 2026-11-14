extends Node3D
## Ana sahne: dükkânı, ışıkları, rafları kurar; oyuncuyu ve iş yöneticisini başlatır.

const MU := preload("res://scripts/mesh_util.gd")
const PM := preload("res://scripts/part_models.gd")
const PART := preload("res://scripts/part.gd")
const PLAYER := preload("res://scripts/player.gd")
const HUD := preload("res://scripts/hud.gd")
const MONITOR := preload("res://scripts/monitor.gd")
const JOBS := preload("res://scripts/job_manager.gd")

const DESK_Y := 0.75

var hud
var monitor


func _ready() -> void:
	randomize()
	_setup_input()
	_build_environment()
	_build_room()
	_build_outside()
	_build_desk()
	_build_shelf()
	_build_counter()
	_build_decor()
	MU.no_merge(monitor)
	MU.merge_static(self)
	hud = HUD.new()
	add_child(hud)
	var player = PLAYER.new()
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
	if "--shot" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/screenshot.gd"):
		add_child(load("res://dev/screenshot.gd").new())
	if "--perf" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/perf.gd"):
		add_child(load("res://dev/perf.gd").new())
	if "--partshot" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/parts_shot.gd"):
		add_child(load("res://dev/parts_shot.gd").new())
	if "--looptest" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/loop_test.gd"):
		Engine.time_scale = 4.0
		add_child(load("res://dev/loop_test.gd").new())


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"interact": [KEY_E], "drop": [KEY_G], "sprint": [KEY_SHIFT],
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
		Game.high_quality = not Game.high_quality
		_apply_quality()
		Game.msg("Grafik kalitesi: %s" % ("YÜKSEK" if Game.high_quality else "DÜŞÜK"), Color(0.6, 0.9, 1.0))


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
	var sun := DirectionalLight3D.new()
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


## Yüksek: SDFGI (yansıyan ışık), SSIL, SSR yansımalar, hacimsel sis (ışık huzmeleri).
## Düşük: zayıf ekran kartları için hepsi kapalı.
func _apply_quality() -> void:
	var hq: bool = Game.high_quality
	env.sdfgi_enabled = hq
	env.sdfgi_use_occlusion = true
	env.sdfgi_min_cell_size = 0.1
	env.sdfgi_cascades = 3
	env.sdfgi_energy = 1.1
	env.ssil_enabled = hq
	env.ssil_intensity = 0.8
	env.ssr_enabled = hq
	env.ssr_max_steps = 48
	env.volumetric_fog_enabled = hq
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(1.0, 0.97, 0.92)
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_ambient_inject = 0.0


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
	open_sign.outline_size = 20
	open_sign.outline_modulate = Color(0.2, 1.0, 0.4, 0.3)
	var open_back := MU.label(self, "AÇIK", Vector3(1.4, 1.9, 3.06), 120, Color(0.3, 1.0, 0.5, 0.35), Vector3.ZERO, 0.0025)
	open_back.shaded = false
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
	# dış cephe (tuğla) ve tabela
	var brick := MU.pbr("brick", 0.5, Color(0.75, 0.75, 0.78))
	for x in [-6.5, 6.5]:
		MU.static_box(self, Vector3(4.6, 4.5, 0.4), Vector3(x, 2.25, 3.1), brick)
	MU.box(self, Vector3(8.6, 1.3, 0.4), Vector3(0, 3.65, 3.1), brick)
	var sign_body := MU.rbox(self, Vector3(3.4, 0.62, 0.14), Vector3(0, 3.4, 3.38), MU.mat(Color(0.08, 0.12, 0.25), 0.3, 0.4), 0.03)
	var l := MU.label(sign_body, "BİLGİSAYARCI", Vector3(0, 0, 0.075), 150, Color(1.0, 0.85, 0.3), Vector3.ZERO, 0.0035)
	l.shaded = false
	l.double_sided = false
	# tente
	var awning := MU.mat(Color(0.75, 0.15, 0.15), 0, 0.8)
	MU.box(self, Vector3(8.0, 0.03, 1.0), Vector3(0, 2.95, 3.75), awning, Vector3(-18, 0, 0))


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
	# klavye ve fare
	var kb := MU.rbox(self, Vector3(0.44, 0.02, 0.14), Vector3(-0.5, DESK_Y + 0.01, -2.32), MU.mat(Color(0.1, 0.1, 0.11), 0.3, 0.5), 0.006)
	var key_m := MU.mat(Color(0.2, 0.2, 0.22), 0, 0.6)
	for r in 4:
		for c in 14:
			MU.rbox(kb, Vector3(0.025, 0.01, 0.025), Vector3(-0.195 + c * 0.03, 0.013, -0.045 + r * 0.03), key_m, 0.003)
	MU.rbox(kb, Vector3(0.16, 0.01, 0.025), Vector3(0.0, 0.013, 0.075), key_m, 0.003)
	MU.sphere(self, 0.03, Vector3(-0.15, DESK_Y + 0.01, -2.3), MU.mat(Color(0.12, 0.12, 0.13), 0.2, 0.4), Vector3(0.8, 0.45, 1.2))
	# masa lambası
	var lamp_m := MU.mat(Color(0.85, 0.25, 0.18), 0.4, 0.4)
	MU.cyl(self, 0.07, 0.02, Vector3(1.3, DESK_Y + 0.01, -2.75), lamp_m, Vector3.ZERO, 24)
	MU.cyl(self, 0.01, 0.42, Vector3(1.3, DESK_Y + 0.22, -2.75), leg)
	MU.cyl(self, 0.03, 0.12, Vector3(1.22, DESK_Y + 0.42, -2.68), lamp_m, Vector3(40, 45, 0), 24, 0.08)
	MU.sphere(self, 0.025, Vector3(1.19, DESK_Y + 0.39, -2.65), MU.mat(Color(1.0, 0.9, 0.7), 0, 0.5, 6.0))
	var dl := SpotLight3D.new()
	dl.position = Vector3(1.19, DESK_Y + 0.4, -2.65)
	dl.rotation_degrees = Vector3(-60, -35, 0)
	dl.spot_range = 2.0
	dl.spot_angle = 45
	dl.light_energy = 2.0
	dl.light_color = Color(1.0, 0.85, 0.65)
	dl.shadow_enabled = true
	add_child(dl)
	# tornavida ve kupa
	MU.capsule(self, 0.012, 0.09, Vector3(1.0, DESK_Y + 0.012, -2.25), MU.mat(Color(0.85, 0.15, 0.12), 0, 0.35), Vector3(0, 0, 90))
	MU.cyl(self, 0.003, 0.1, Vector3(0.905, DESK_Y + 0.012, -2.25), MU.mat(Color(0.8, 0.8, 0.82), 0.9, 0.25), Vector3(0, 0, 90), 8)
	var mug := MU.cyl(self, 0.04, 0.1, Vector3(-1.0, DESK_Y + 0.05, -2.6), MU.mat(Color(0.95, 0.95, 0.92), 0, 0.2), Vector3.ZERO, 24)
	MU.cyl(mug, 0.035, 0.005, Vector3(0, 0.045, 0), MU.mat(Color(0.25, 0.12, 0.05), 0, 0.1), Vector3.ZERO, 24)
	MU.torus(mug, 0.02, 0.028, Vector3(0.045, 0, 0), MU.mat(Color(0.95, 0.95, 0.92), 0, 0.2), Vector3(90, 0, 0))
	# arıza rehberi posteri
	var poster := MU.rbox(self, Vector3(1.3, 0.85, 0.012), Vector3(-0.2, 1.8, -2.99), MU.mat(Color(0.97, 0.95, 0.9), 0, 0.8), 0.004)
	MU.box(poster, Vector3(1.3, 0.12, 0.014), Vector3(0, 0.365, 0), MU.mat(Color(0.75, 0.15, 0.15), 0, 0.7))
	var t1 := MU.label(poster, "ARIZA REHBERİ", Vector3(0, 0.365, 0.009), 64, Color.WHITE, Vector3.ZERO, 0.0012)
	t1.double_sided = false
	var t2 := MU.label(poster, "• Hiçbir tepki yok  →  Güç Kaynağı (PSU)\n• Fan dönüyor, bip yok, görüntü yok  →  İşlemci (CPU)\n• Sürekli kısa bipler  →  RAM\n• 1 uzun 3 kısa bip  →  Ekran Kartı (GPU)\n• \"Boot device\" hatası  →  SSD\n• Tek kısa bip  →  Her şey yolunda!", Vector3(0, -0.06, 0.009), 34, Color(0.12, 0.12, 0.14), Vector3.ZERO, 0.0011)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t2.line_spacing = 6
	t2.double_sided = false
	for c in [Vector2(-0.6, 0.38), Vector2(0.6, 0.38), Vector2(-0.6, -0.38), Vector2(0.6, -0.38)]:
		MU.sphere(poster, 0.008, Vector3(c.x, c.y, 0.008), MU.mat(Color(0.2, 0.4, 0.9), 0.3, 0.3))
	# hurda kutusu
	var bin := MU.cyl(self, 0.2, 0.5, Vector3(1.85, 0.25, -2.55), MU.mat(Color(0.2, 0.38, 0.28), 0.5, 0.45), Vector3.ZERO, 24, 0.22)
	MU.torus(bin, 0.2, 0.23, Vector3(0, 0.25, 0), MU.mat(Color(0.12, 0.16, 0.14), 0.5, 0.4))
	var bl := MU.label(bin, "HURDA", Vector3(0, 0.05, 0.215), 60, Color(0.95, 0.95, 0.9), Vector3.ZERO, 0.0012)
	bl.double_sided = false
	MU.interactable(self, Vector3(0.46, 0.55, 0.46), Vector3(1.85, 0.27, -2.55), _bin_hint, _bin_use)


func _bin_hint(p) -> String:
	if p.held:
		if p.held.broken:
			return "Arızalı parçayı at  [E]"
		return "Hurdaya sat: %s (+%d TL)  [E]" % [p.held.display_name, int(p.held.value() * 0.4)]
	return "Hurda kutusu"


func _bin_use(p) -> void:
	if p.held == null:
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
	var title := MU.label(self, "PARÇA RAFI", Vector3(x0 + 0.05, 2.48, zc), 90, Color(0.15, 0.2, 0.3), Vector3(0, 90, 0), 0.0025)
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
	var price := PM.price(type, tier)
	var dname := PM.display_name(type, tier)
	MU.interactable(self, info.size * 1.5 + Vector3(0.04, 0.04, 0.04), Vector3(x0 + 0.06, shelf_y + info.size.y * 0.75, z),
		func(p): return "Satın al: %s — %d TL  [E]" % [dname, price] if p.held == null else "Elin dolu",
		func(p): _buy(p, type, tier))
	var l := MU.label(self, "%s\n%d TL" % [dname, price], Vector3(x0 + 0.214, shelf_y - 0.045, z), 30, Color(0.1, 0.1, 0.1), Vector3(0, 90, 0), 0.001)
	l.double_sided = false
	var tag := MU.box(self, Vector3(0.002, 0.06, 0.24), Vector3(x0 + 0.212, shelf_y - 0.045, z), MU.mat(Color(1.0, 0.92, 0.4)))
	tag.name = "PriceTag"


func _buy(p, type: String, tier: int) -> void:
	if p.held:
		return
	var price := PM.price(type, tier)
	if not Game.spend(price):
		Game.msg("Paran yetmiyor! (%d TL lazım)" % price, Color(1, 0.5, 0.4))
		Game.sfx.error()
		return
	var part = PART.new().setup(type, tier, false)
	add_child(part)
	p.pick_up(part)
	Game.sfx.coin()
	Game.msg("%s satın alındı: -%d TL" % [PM.display_name(type, tier), price])


func _build_counter() -> void:
	var wood := MU.pbr("wood", 0.8)
	var body_m := MU.pbr("wall", 0.6, Color(0.22, 0.3, 0.4), 0.5)
	MU.rbox(self, Vector3(3.4, 0.98, 0.6), Vector3(-1.0, 0.49, 1.3), body_m, 0.02)
	MU.rbox(self, Vector3(3.5, 0.05, 0.7), Vector3(-1.0, 1.0, 1.3), wood, 0.015)
	MU.rbox(self, Vector3(3.42, 0.06, 0.02), Vector3(-1.0, 0.06, 1.6), MU.mat(Color(0.12, 0.12, 0.13), 0.6, 0.4), 0.008)
	MU.static_box(self, Vector3(3.5, 1.03, 0.7), Vector3(-1.0, 0.515, 1.3), null)
	# yazar kasa
	var reg := MU.rbox(self, Vector3(0.35, 0.12, 0.3), Vector3(-2.1, 1.085, 1.3), MU.mat(Color(0.15, 0.15, 0.17), 0.3, 0.4), 0.02)
	MU.rbox(reg, Vector3(0.2, 0.1, 0.02), Vector3(0, 0.1, -0.05), MU.mat(Color(0.2, 0.8, 0.5), 0, 0.3, 1.5), 0.005, Vector3(20, 0, 0))
	for r in 3:
		for c in 4:
			MU.rbox(reg, Vector3(0.03, 0.01, 0.03), Vector3(-0.06 + c * 0.04, 0.062, 0.02 + r * 0.04), MU.mat(Color(0.85, 0.85, 0.82), 0, 0.5), 0.004)
	# eski CRT monitör (süs)
	var crt := MU.rbox(self, Vector3(0.4, 0.35, 0.38), Vector3(-1.4, 1.2, 1.35), MU.mat(Color(0.85, 0.82, 0.72), 0, 0.5), 0.04)
	MU.rbox(crt, Vector3(0.32, 0.26, 0.01), Vector3(0, 0.01, -0.19), MU.mat(Color(0.1, 0.14, 0.12), 0.2, 0.15), 0.02)
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
