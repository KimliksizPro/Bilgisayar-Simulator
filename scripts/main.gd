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


func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.5, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.8, 0.9)
	sky_mat.ground_horizon_color = Color(0.6, 0.6, 0.62)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 28, 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)


func _build_room() -> void:
	var floor_m := MU.tex_mat(MU.tile_texture(), Vector3(4, 3, 1), 0.45, Color(0.82, 0.8, 0.78))
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 6)
	var fl := MeshInstance3D.new()
	fl.mesh = pm
	fl.material_override = floor_m
	add_child(fl)
	MU.static_box(self, Vector3(8.4, 0.2, 6.4), Vector3(0, -0.1, 0), null)
	var wall := MU.mat(Color(0.8, 0.74, 0.64), 0, 0.9)
	var trim := MU.mat(Color(0.32, 0.38, 0.45), 0, 0.7)
	MU.static_box(self, Vector3(8.4, 3, 0.2), Vector3(0, 1.5, -3.1), wall)
	MU.static_box(self, Vector3(0.2, 3, 6.2), Vector3(-4.1, 1.5, 0), wall)
	MU.static_box(self, Vector3(0.2, 3, 6.2), Vector3(4.1, 1.5, 0), wall)
	# alt şerit (lambri)
	MU.box(self, Vector3(8.0, 0.9, 0.02), Vector3(0, 0.45, -2.995), trim)
	MU.box(self, Vector3(0.02, 0.9, 6.0), Vector3(-3.995, 0.45, 0), trim)
	MU.box(self, Vector3(0.02, 0.9, 6.0), Vector3(3.995, 0.45, 0), trim)
	# ön vitrin + kapı boşluğu
	var frame := MU.mat(Color(0.2, 0.2, 0.22), 0.8, 0.35)
	for side in [-1, 1]:
		var cx: float = side * 2.475
		var seg := StaticBody3D.new()
		seg.position = Vector3(cx, 0, 3.1)
		add_child(seg)
		MU.add_box_shape(seg, Vector3(3.45, 3, 0.2), Vector3(0, 1.5, 0))
		MU.box(seg, Vector3(3.45, 0.5, 0.2), Vector3(0, 0.25, 0), trim)
		MU.box(seg, Vector3(3.45, 1.9, 0.03), Vector3(0, 1.45, 0), MU.glass())
		MU.box(seg, Vector3(3.45, 0.6, 0.2), Vector3(0, 2.7, 0), wall)
		MU.box(seg, Vector3(3.45, 0.05, 0.22), Vector3(0, 0.52, 0), frame)
		MU.box(seg, Vector3(3.45, 0.05, 0.22), Vector3(0, 2.4, 0), frame)
		for k in [-1, 0, 1]:
			MU.box(seg, Vector3(0.05, 1.9, 0.22), Vector3(k * 1.7, 1.45, 0), frame)
	MU.static_box(self, Vector3(1.5, 0.6, 0.2), Vector3(0, 2.7, 3.1), wall)
	# tavan ve lambalar
	MU.box(self, Vector3(8.4, 0.1, 6.4), Vector3(0, 3.05, 0), MU.mat(Color(0.92, 0.92, 0.9)))
	var lamp_m := MU.mat(Color(1.0, 0.97, 0.9), 0, 0.5, 4.0)
	for p in [Vector3(-1.6, 0, -1.2), Vector3(1.6, 0, -1.2), Vector3(0, 0, 1.6)]:
		MU.box(self, Vector3(1.2, 0.03, 0.3), Vector3(p.x, 2.985, p.z), lamp_m)
		var l := OmniLight3D.new()
		l.position = Vector3(p.x, 2.6, p.z)
		l.omni_range = 6.0
		l.light_energy = 0.75
		l.light_color = Color(1.0, 0.95, 0.86)
		l.shadow_enabled = p.z < 0
		add_child(l)


func _build_outside() -> void:
	MU.static_box(self, Vector3(60, 0.2, 40), Vector3(0, -0.11, 23.2), MU.mat(Color(0.22, 0.22, 0.24), 0, 0.95))
	MU.box(self, Vector3(60, 0.12, 4.0), Vector3(0, 0.0, 5.2), MU.mat(Color(0.62, 0.6, 0.57), 0, 0.9))
	for i in 12:
		MU.box(self, Vector3(1.6, 0.02, 0.15), Vector3(-26 + i * 5, 0.0, 11.0), MU.mat(Color(0.9, 0.9, 0.85)))
	var colors := [Color(0.8, 0.55, 0.45), Color(0.65, 0.7, 0.75), Color(0.85, 0.78, 0.6), Color(0.55, 0.6, 0.5)]
	for i in 7:
		var h := randf_range(6, 14)
		var b := MU.box(self, Vector3(6.5, h, 6), Vector3(-21 + i * 7, h / 2, 21), MU.mat(colors[i % colors.size()], 0, 0.9))
		for fy in range(2, int(h) - 1, 3):
			for fx in [-2.0, 0.0, 2.0]:
				MU.box(b, Vector3(1.0, 1.2, 0.05), Vector3(fx, fy - h / 2, -3.0), MU.mat(Color(0.35, 0.45, 0.55), 0.5, 0.2))
	for x in [-6.0, 5.5, 9.0]:
		MU.cyl(self, 0.12, 2.0, Vector3(x, 1.0, 6.6), MU.mat(Color(0.4, 0.28, 0.18)))
		MU.sphere(self, 1.0, Vector3(x, 2.6, 6.6), MU.mat(Color(0.3, 0.55, 0.25), 0, 0.9), Vector3(1, 1.2, 1))
	# tabela
	var sign_body := MU.box(self, Vector3(3.2, 0.6, 0.12), Vector3(0, 3.35, 3.3), MU.mat(Color(0.1, 0.15, 0.3)))
	var l := MU.label(sign_body, "BİLGİSAYARCI", Vector3(0, 0, 0.07), 150, Color(1.0, 0.85, 0.3), Vector3.ZERO, 0.0035)
	l.double_sided = false


func _build_desk() -> void:
	var wood := MU.tex_mat(MU.wood_texture(), Vector3(2, 1, 1), 0.55)
	MU.box(self, Vector3(2.6, 0.05, 0.8), Vector3(0.25, DESK_Y - 0.025, -2.5), wood)
	var leg := MU.mat(Color(0.15, 0.15, 0.16), 0.8, 0.4)
	for x in [-1.0, 1.5]:
		for z in [-2.85, -2.15]:
			MU.box(self, Vector3(0.05, DESK_Y - 0.05, 0.05), Vector3(x, (DESK_Y - 0.05) / 2, z), leg)
	MU.static_box(self, Vector3(2.6, DESK_Y, 0.8), Vector3(0.25, DESK_Y / 2, -2.5), null)
	MU.box(self, Vector3(1.0, 0.004, 0.5), Vector3(0.55, DESK_Y + 0.002, -2.45), MU.mat(Color(0.2, 0.35, 0.6), 0, 0.9))
	monitor = MONITOR.new()
	monitor.position = Vector3(-0.5, DESK_Y, -2.72)
	add_child(monitor)
	# klavye ve fare
	var kb := MU.box(self, Vector3(0.44, 0.02, 0.14), Vector3(-0.5, DESK_Y + 0.01, -2.32), MU.mat(Color(0.1, 0.1, 0.11)))
	var key_m := MU.mat(Color(0.2, 0.2, 0.22))
	for r in 4:
		for c in 14:
			MU.box(kb, Vector3(0.024, 0.008, 0.024), Vector3(-0.195 + c * 0.03, 0.013, -0.045 + r * 0.03), key_m)
	MU.sphere(self, 0.03, Vector3(-0.15, DESK_Y + 0.01, -2.3), MU.mat(Color(0.12, 0.12, 0.13)), Vector3(0.8, 0.45, 1.2))
	# masa lambası
	var lamp_m := MU.mat(Color(0.9, 0.3, 0.2), 0.3, 0.5)
	MU.cyl(self, 0.07, 0.02, Vector3(1.3, DESK_Y + 0.01, -2.75), lamp_m)
	MU.cyl(self, 0.01, 0.42, Vector3(1.3, DESK_Y + 0.22, -2.75), leg)
	MU.cyl(self, 0.03, 0.12, Vector3(1.22, DESK_Y + 0.42, -2.68), lamp_m, Vector3(40, 45, 0), 16, 0.08)
	var dl := OmniLight3D.new()
	dl.position = Vector3(1.15, DESK_Y + 0.33, -2.6)
	dl.omni_range = 1.6
	dl.light_energy = 0.8
	dl.light_color = Color(1.0, 0.85, 0.65)
	add_child(dl)
	# tornavida
	MU.cyl(self, 0.012, 0.09, Vector3(1.0, DESK_Y + 0.012, -2.25), MU.mat(Color(0.9, 0.2, 0.15)), Vector3(0, 0, 90), 8)
	MU.cyl(self, 0.003, 0.1, Vector3(0.905, DESK_Y + 0.012, -2.25), MU.mat(Color(0.8, 0.8, 0.82), 0.9, 0.3), Vector3(0, 0, 90), 6)
	# arıza rehberi posteri
	var poster := MU.box(self, Vector3(1.3, 0.85, 0.01), Vector3(-0.2, 1.8, -2.99), MU.mat(Color(0.97, 0.95, 0.88)))
	MU.box(poster, Vector3(1.3, 0.12, 0.012), Vector3(0, 0.365, 0), MU.mat(Color(0.75, 0.15, 0.15)))
	var t1 := MU.label(poster, "ARIZA REHBERİ", Vector3(0, 0.365, 0.008), 64, Color.WHITE, Vector3.ZERO, 0.0012)
	t1.double_sided = false
	var t2 := MU.label(poster, "• Hiçbir tepki yok  →  Güç Kaynağı (PSU)\n• Fan dönüyor, bip yok, görüntü yok  →  İşlemci (CPU)\n• Sürekli kısa bipler  →  RAM\n• 1 uzun 3 kısa bip  →  Ekran Kartı (GPU)\n• \"Boot device\" hatası  →  SSD\n• Tek kısa bip  →  Her şey yolunda!", Vector3(0, -0.06, 0.008), 34, Color(0.12, 0.12, 0.14), Vector3.ZERO, 0.0011)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t2.line_spacing = 6
	t2.double_sided = false
	# hurda kutusu
	var bin := MU.cyl(self, 0.2, 0.5, Vector3(1.85, 0.25, -2.55), MU.mat(Color(0.25, 0.4, 0.3), 0.4, 0.6), Vector3.ZERO, 16, 0.22)
	MU.torus(bin, 0.2, 0.23, Vector3(0, 0.25, 0), MU.mat(Color(0.15, 0.2, 0.17)))
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
	var wood := MU.tex_mat(MU.wood_texture(), Vector3(1, 3, 1), 0.6, Color(0.85, 0.85, 0.85))
	var zc := -0.7
	var length := 3.0
	for z in [zc - length / 2, zc + length / 2]:
		MU.static_box(self, Vector3(0.42, 2.1, 0.04), Vector3(x0, 1.05, z), wood)
	MU.box(self, Vector3(0.02, 2.1, length), Vector3(x0 - 0.2, 1.05, zc), wood)
	var levels := [0.45, 0.95, 1.45, 1.95]
	for y in levels:
		MU.static_box(self, Vector3(0.42, 0.03, length), Vector3(x0, y, zc), wood)
	var shelf_light := OmniLight3D.new()
	shelf_light.position = Vector3(x0 + 0.9, 1.6, zc)
	shelf_light.omni_range = 2.2
	shelf_light.light_energy = 0.6
	add_child(shelf_light)
	var title := MU.label(self, "PARÇA RAFI", Vector3(x0 + 0.05, 2.2, zc), 90, Color(0.2, 0.25, 0.35), Vector3(0, 90, 0), 0.0025)
	title.double_sided = false
	var items := [
		[1.45, -1.6, "gpu", 1], [1.45, -0.9, "gpu", 2],
		[0.95, -1.7, "ram", 1], [0.95, -1.35, "ram", 2], [0.95, -0.85, "cpu", 1],
		[0.45, -1.6, "psu", 1], [0.45, -1.05, "ssd", 1],
	]
	for it in items:
		_shelf_item(x0, it[0] + 0.015, it[1] + 0.7 + zc, it[2], it[3])


func _shelf_item(x0: float, shelf_y: float, z: float, type: String, tier: int) -> void:
	var info: Dictionary = PM.INFO[type]
	var built := PM.build(type, tier)
	var n: Node3D = built.node
	var c: Vector3 = info.center
	n.position = Vector3(x0 + 0.06 - c.x, shelf_y + info.size.y / 2 - c.y, z - c.z)
	add_child(n)
	var price := PM.price(type, tier)
	var dname := PM.display_name(type, tier)
	MU.interactable(self, info.size + Vector3(0.04, 0.04, 0.04), Vector3(x0 + 0.06, shelf_y + info.size.y / 2, z),
		func(p): return "Satın al: %s — %d TL  [E]" % [dname, price] if p.held == null else "Elin dolu",
		func(p): _buy(p, type, tier))
	var l := MU.label(self, "%s\n%d TL" % [dname, price], Vector3(x0 + 0.213, shelf_y - 0.045, z), 30, Color(0.1, 0.1, 0.1), Vector3(0, 90, 0), 0.0008)
	l.double_sided = false
	var tag := MU.box(self, Vector3(0.002, 0.05, 0.16), Vector3(x0 + 0.211, shelf_y - 0.045, z), MU.mat(Color(1.0, 0.92, 0.4)))
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
	var wood := MU.tex_mat(MU.wood_texture(), Vector3(3, 1, 1), 0.5)
	MU.box(self, Vector3(3.4, 0.98, 0.6), Vector3(-1.0, 0.49, 1.3), MU.mat(Color(0.25, 0.3, 0.38), 0, 0.7))
	MU.box(self, Vector3(3.5, 0.05, 0.7), Vector3(-1.0, 1.0, 1.3), wood)
	MU.static_box(self, Vector3(3.5, 1.03, 0.7), Vector3(-1.0, 0.515, 1.3), null)
	# yazar kasa
	var reg := MU.box(self, Vector3(0.35, 0.12, 0.3), Vector3(-2.1, 1.085, 1.3), MU.mat(Color(0.15, 0.15, 0.17)))
	MU.box(reg, Vector3(0.2, 0.1, 0.02), Vector3(0, 0.1, 0.05), MU.mat(Color(0.2, 0.8, 0.5), 0, 0.3, 1.5), Vector3(-20, 0, 0))
	# eski CRT monitör (süs)
	var crt := MU.box(self, Vector3(0.4, 0.35, 0.38), Vector3(-1.4, 1.2, 1.35), MU.mat(Color(0.85, 0.82, 0.72)))
	MU.box(crt, Vector3(0.32, 0.26, 0.01), Vector3(0, 0.01, -0.19), MU.mat(Color(0.15, 0.2, 0.18), 0.2, 0.2))
	var sticky := MU.label(self, "Kartvizit\nalınız :)", Vector3(-0.3, 1.03, 1.2), 40, Color(0.2, 0.2, 0.25), Vector3(-90, 180, 0), 0.001)
	sticky.double_sided = false


func _build_decor() -> void:
	var cardboard := MU.mat(Color(0.7, 0.55, 0.35), 0, 0.9)
	var tape := MU.mat(Color(0.85, 0.75, 0.55), 0, 0.6)
	var stacks := [[Vector3(3.4, 0.25, -2.5), Vector3(0.6, 0.5, 0.5), 0.0], [Vector3(3.35, 0.75, -2.5), Vector3(0.5, 0.5, 0.45), 12.0],
		[Vector3(3.5, 0.2, -1.8), Vector3(0.45, 0.4, 0.45), -8.0], [Vector3(3.3, 1.15, -2.45), Vector3(0.35, 0.3, 0.3), 25.0]]
	for s in stacks:
		var b := MU.static_box(self, s[1], s[0], cardboard, Vector3(0, s[2], 0))
		MU.box(b, Vector3(s[1].x + 0.002, 0.06, s[1].z + 0.002), Vector3(0, s[1].y / 2 - 0.02, 0), tape)
	# saksı bitkisi
	MU.cyl(self, 0.2, 0.4, Vector3(3.5, 0.2, 2.5), MU.mat(Color(0.7, 0.35, 0.2)), Vector3.ZERO, 14, 0.24)
	for i in 6:
		var a := TAU * i / 6.0
		MU.sphere(self, 0.22, Vector3(3.5 + cos(a) * 0.12, 0.62 + (i % 2) * 0.15, 2.5 + sin(a) * 0.12), MU.mat(Color(0.25, 0.55, 0.25), 0, 0.85), Vector3(0.7, 1.4, 0.7))
	# duvar saati
	var clock := MU.cyl(self, 0.22, 0.04, Vector3(3.99, 2.2, -0.5), MU.mat(Color(0.95, 0.95, 0.95)), Vector3(0, 0, 90), 24)
	MU.torus(clock, 0.21, 0.24, Vector3.ZERO, MU.mat(Color(0.15, 0.15, 0.15)))
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
	nl.light_energy = 0.6
	nl.omni_range = 2.5
	add_child(nl)
	# sandalye
	var chair_m := MU.mat(Color(0.12, 0.12, 0.14), 0.2, 0.6)
	MU.box(self, Vector3(0.48, 0.08, 0.48), Vector3(0.4, 0.5, -1.75), chair_m)
	MU.box(self, Vector3(0.48, 0.55, 0.06), Vector3(0.4, 0.82, -1.5), chair_m, Vector3(-8, 0, 0))
	MU.cyl(self, 0.03, 0.45, Vector3(0.4, 0.25, -1.75), MU.mat(Color(0.6, 0.6, 0.62), 0.9, 0.3))
	MU.cyl(self, 0.28, 0.03, Vector3(0.4, 0.04, -1.75), chair_m, Vector3.ZERO, 5)
