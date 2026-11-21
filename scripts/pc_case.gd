extends Node3D
## Müşterinin bilgisayar kasası: form faktörü, anakart yuvası, tüm parça yuvaları, cam kapak, güç düğmesi, teşhis.

const MU := preload("res://scripts/mesh_util.gd")
const PM := preload("res://scripts/part_models.gd")
const SLOT := preload("res://scripts/slot.gd")
const PART := preload("res://scripts/part.gd")

# Varsayılan Mid-Tower ATX ölçüleri (statik PC.W/H/D referansları için korunur)
const W := 0.22
const H := 0.46
const D := 0.44
const BOARD_X := -0.0875

var case_id := "atx_mid"
var case_def: Dictionary = {}
var case_w := W
var case_h := H
var case_d := D
var board_x := BOARD_X
var slot_pos := {}

const CABLE_IDS := ["atx_24", "cpu_8", "pcie_gpu", "sata", "front_panel"]
const CABLE_NAMES := {
	"atx_24": "24-pin Anakart Güç",
	"cpu_8": "CPU 8-pin Güç",
	"pcie_gpu": "GPU PCIe Güç",
	"sata": "SATA Veri/Güç",
	"front_panel": "Ön Panel Güç Düğmesi",
}
const SCREW_NAMES := {
	"panel_1": "Üst Yan Kapak",
	"panel_2": "Alt Yan Kapak",
	"gpu": "GPU Braketi",
	"m2": "M.2 SSD",
}

var slots := {}
var monitor = null
var powered := false
var panel_open := false
var flat_mode := false
var panel_pivot: Node3D
var _panel_tw: Tween = null
var case_fans: Array = []
var rgb_mats: Array = []
var hum: AudioStreamPlayer3D
var led_mat: StandardMaterial3D
var inner_light: OmniLight3D
var debug_leds := {}
var _debug_led_group: Node3D
var post_card_active := false
var _hue := 0.0
var dust := 0.0            # 0..1 toz miktarı
var socket_paste := false  # CPU soketinde taze termal macun var mı
var cpu_temp := 35.0
var paste_blob: MeshInstance3D
var cables := {"atx_24": "ok", "cpu_8": "ok", "pcie_gpu": "ok", "sata": "ok", "front_panel": "ok"}
var cables_tidy := false
var screws := {"panel_1": true, "panel_2": true, "gpu": false, "m2": false}
var sw_faults: Array = []
var cable_groups := {}     # geriye dönük uyumluluk / eski kablo düğümleri
var cable_nodes := {}      # id -> {root, plug, warn, inter, ok_pos, loose_pos, tidy_pos}
var screw_nodes := {}      # id -> {root, head, hole, inter}
var _dust_nodes: Array = []  # [MeshInstance3D, gereken_slot]
var _dust_mat: StandardMaterial3D
var _dust_vis := 0.0
var _dust_tween: Tween
var _last_temp_i := -1
var _cap_t := 0.0
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	case_def = DB.parts.case_def(case_id)
	if case_def.is_empty():
		case_def = DB.parts.case_def("atx_mid")
	var sz = case_def.get("size", Vector3(W, H, D))
	if sz is Vector3:
		case_w = sz.x
		case_h = sz.y
		case_d = sz.z
	elif sz is Array and sz.size() >= 3:
		case_w = float(sz[0])
		case_h = float(sz[1])
		case_d = float(sz[2])
	board_x = -case_w / 2.0 + 0.0225
	slot_pos = _compute_slot_positions()

	var white := randf() < 0.4
	var shell_m := MU.mat(Color(0.9, 0.9, 0.92) if white else Color(0.08, 0.08, 0.09), 0.4, 0.45)
	var inner_m := MU.mat(Color(0.8, 0.8, 0.82) if white else Color(0.11, 0.11, 0.12), 0.4, 0.5)
	var t := 0.006
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var pieces := [
		[Vector3(case_w, t, case_d), Vector3(0, t / 2, 0), shell_m],
		[Vector3(case_w, t, case_d), Vector3(0, case_h - t / 2, 0), shell_m],
		[Vector3(case_w, case_h, t), Vector3(0, case_h / 2, -case_d / 2 + t / 2), inner_m],
		[Vector3(case_w, case_h, t), Vector3(0, case_h / 2, case_d / 2 - t / 2), shell_m],
		[Vector3(t, case_h, case_d), Vector3(-case_w / 2 + t / 2, case_h / 2, 0), shell_m],
	]
	for p in pieces:
		MU.rbox(body, p[0], p[1], p[2], 0.004)
		MU.add_box_shape(body, p[0], p[1])
	# dış kenar çerçevesi (yuvarlatılmış)
	for y in [0.0, case_h]:
		MU.rbox(self, Vector3(case_w + 0.004, 0.014, case_d + 0.004), Vector3(0, y, 0), shell_m, 0.006)
	# ön panel ızgarası
	var mesh_m := MU.mat(Color(0.2, 0.2, 0.22) if not white else Color(0.75, 0.75, 0.78), 0.6, 0.5)
	var bars := maxi(8, int(case_w * 64.0))
	for i in bars:
		var bx := -case_w * 0.14 + float(i) * (case_w * 0.55 / float(bars))
		MU.box(self, Vector3(0.002, case_h * 0.8, 0.003), Vector3(bx, case_h / 2, case_d / 2 + 0.002), mesh_m)
	# ayaklar
	var fx := case_w * 0.36
	var fz := case_d * 0.41
	for x in [-fx, fx]:
		for z in [-fz, fz]:
			MU.box(self, Vector3(0.03, 0.01, 0.03), Vector3(x, -0.005, z), MU.mat(Color(0.05, 0.05, 0.05)))
	# ön panel detayları
	MU.box(self, Vector3(0.006, case_h * 0.86, 0.004), Vector3(-case_w * 0.32, case_h / 2, case_d / 2 + 0.002), MU.mat(Color(0.3, 0.3, 0.32), 0.8, 0.3))
	led_mat = MU.new_mat(Color(0.1, 0.1, 0.1))
	MU.box(self, Vector3(0.008, 0.003, 0.003), Vector3(case_w * 0.18, case_h - 0.03, case_d / 2 + 0.001), led_mat)
	# güç düğmesi
	MU.cyl(self, 0.011, 0.006, Vector3(0.0, case_h - 0.03, case_d / 2 + 0.002), MU.mat(Color(0.75, 0.75, 0.78), 0.9, 0.3), Vector3(90, 0, 0))
	MU.interactable(self, Vector3(0.04, 0.04, 0.02), Vector3(0.0, case_h - 0.03, case_d / 2 + 0.006),
		func(_p): return "Güç düğmesi  [E]" if not powered else "Bilgisayarı kapat  [E]",
		func(_p): power_button())
	# cam yan kapak (menteşe arka kenarda)
	panel_pivot = MU.no_merge(Node3D.new())
	panel_pivot.position = Vector3(case_w / 2 - 0.002, 0, -case_d / 2)
	add_child(panel_pivot)
	var panel = MU.interactable(panel_pivot, Vector3(0.006, case_h, case_d), Vector3(0, case_h / 2, case_d / 2),
		func(_p): return "Kapağı aç  [E]" if not panel_open else "Kapağı kapat  [E]",
		func(_p): toggle_panel())
	MU.box(panel, Vector3(0.004, case_h - 0.02, case_d - 0.02), Vector3.ZERO, MU.glass())
	var frame_m := shell_m
	MU.box(panel, Vector3(0.005, 0.01, case_d), Vector3(0, case_h / 2 - 0.005, 0), frame_m)
	MU.box(panel, Vector3(0.005, 0.01, case_d), Vector3(0, -case_h / 2 + 0.005, 0), frame_m)
	MU.box(panel, Vector3(0.005, case_h, 0.01), Vector3(0, 0, case_d / 2 - 0.005), frame_m)
	MU.box(panel, Vector3(0.005, case_h, 0.01), Vector3(0, 0, -case_d / 2 + 0.005), frame_m)
	MU.merge_static(panel_pivot)
	_build_tray()
	_build_slots()
	# kasa içi LED şerit + ışık (parçalar karanlıkta kalmasın)
	var strip := MU.new_mat(Color(0.9, 0.95, 1.0), 0, 0.5, 2.0)
	rgb_mats.append(strip)
	MU.box(self, Vector3(0.006, 0.004, case_d - 0.04), Vector3(case_w * 0.27, case_h - 0.01, 0), strip)
	inner_light = OmniLight3D.new()
	inner_light.position = Vector3(0.04, case_h - 0.06, 0.0)
	inner_light.omni_range = 0.6
	inner_light.light_energy = 0.35
	inner_light.light_color = Color(0.9, 0.95, 1.0)
	add_child(inner_light)
	for f in case_fans:
		MU.no_merge(f)
	_build_cables()
	_build_screws()
	_build_rear_io()
	_build_dust()
	MU.merge_static(self)
	_built = true
	_update_visuals()
	hum = AudioStreamPlayer3D.new()
	hum.stream = Game.sfx.hum()
	hum.bus = "SFX"
	hum.volume_db = -14.0
	hum.position = Vector3(0, case_h * 0.43, 0)
	add_child(hum)


## Kasa form faktörüne göre tüm yuva konumlarını hesaplar.
func _compute_slot_positions() -> Dictionary:
	var dy := maxf(case_h - H, -0.105)
	var z_lim := case_d * 0.40
	var bx := board_x
	var pos := {
		"mobo": Vector3(bx, 0.29 + dy, clampf(-0.02, -z_lim, z_lim)),
		"cpu": Vector3(bx, 0.36 + dy, clampf(-0.06, -z_lim, z_lim)),
		"cooler": Vector3(bx + 0.006, 0.36 + dy, clampf(-0.06, -z_lim, z_lim)),
		"ram1": Vector3(bx, 0.35 + dy, clampf(0.024, -z_lim, z_lim)),
		"ram2": Vector3(bx, 0.35 + dy, clampf(0.039, -z_lim, z_lim)),
		"ram3": Vector3(bx, 0.35 + dy, clampf(0.054, -z_lim, z_lim)),
		"ram4": Vector3(bx, 0.35 + dy, clampf(0.069, -z_lim, z_lim)),
		"gpu": Vector3(bx, 0.235 + dy, clampf(-0.04, -z_lim, z_lim)),
		"m2": Vector3(bx + 0.002, 0.18 + dy, clampf(-0.01, -z_lim, z_lim)),
		"cmos": Vector3(bx + 0.002, 0.268 + dy, clampf(0.092, -z_lim, z_lim)),
		"psu": Vector3(0.0, 0.0475, -case_d / 2.0 + 0.09),
		"ssd": Vector3(0.02, 0.015, case_d / 2.0 - 0.10),
		"fan1": Vector3(case_w * 0.5 - 0.070, case_h - 0.085, -case_d / 2.0 + 0.019),
	}
	if int(case_def.get("fan_slots", 2)) >= 2:
		pos["fan2"] = Vector3(0.0, case_h * 0.55, case_d / 2.0 - 0.019)
	return pos


## Anakart tepsisi, pirinç yükselticiler ve hata LED'leri (anakart artık ayrı yuva).
func _build_tray() -> void:
	var tray := Node3D.new()
	add_child(tray)
	var tray_x := board_x - 0.005
	var mobo_p: Vector3 = slot_pos.mobo
	var tray_m := MU.mat(Color(0.14, 0.15, 0.17), 0.5, 0.55)
	var brass := MU.mat(Color(0.82, 0.65, 0.25), 0.9, 0.3)
	var metal := MU.mat(Color(0.5, 0.52, 0.56), 0.85, 0.3)
	var tray_h := minf(0.28, case_h - 0.14)
	var tray_d := minf(0.26, case_d - 0.12)
	MU.box(tray, Vector3(0.003, tray_h, tray_d), Vector3(tray_x, mobo_p.y, mobo_p.z), tray_m)
	# pirinç yükselticiler (standoff)
	for sy in [-tray_h * 0.42, 0.0, tray_h * 0.42]:
		for sz in [-tray_d * 0.42, tray_d * 0.42]:
			MU.cyl(tray, 0.0028, 0.005, Vector3(tray_x + 0.003, mobo_p.y + sy, mobo_p.z + sz), brass, Vector3(0, 0, 90), 6)
	# PCIe braketleri (arka)
	var brackets := 5 if case_h >= 0.42 else (4 if case_h >= 0.36 else 2)
	for i in brackets:
		MU.box(tray, Vector3(0.03, 0.012, 0.002), Vector3(-case_w * 0.27, slot_pos.gpu.y + 0.015 - i * 0.02, -case_d / 2.0 + 0.003), metal)
	# hata LED'leri (CPU / DRAM / VGA / BOOT — yalnızca debug_led'li anakartta veya POST kartıyla görünür)
	_debug_led_group = MU.no_merge(Node3D.new())
	_debug_led_group.name = "DebugLEDs"
	add_child(_debug_led_group)
	var names := ["CPU", "DRAM", "VGA", "BOOT"]
	var led_y := minf(mobo_p.y + tray_h * 0.46, case_h - 0.03)
	var led_z := minf(mobo_p.z + tray_d * 0.40, case_d * 0.38)
	for i in names.size():
		var lm := MU.new_mat(Color(0.25, 0.12, 0.05), 0, 0.4)
		debug_leds[names[i]] = lm
		MU.box(_debug_led_group, Vector3(0.002, 0.003, 0.005), Vector3(board_x + 0.004, led_y - i * 0.008, led_z), lm)
		var ll := MU.label(_debug_led_group, names[i], Vector3(board_x + 0.0042, led_y - i * 0.008, led_z - 0.011), 24, Color(0.9, 0.9, 0.9), Vector3(0, 90, 0), 0.00022)
		ll.double_sided = false


## Kasa yuvalarını kurar (mobo, cpu, cooler, ram1..4, gpu, psu, ssd/hdd, m2, fan1..2, cmos).
func _build_slots() -> void:
	var defs := [
		["mobo", "mobo", [], 0],
		["cpu", "cpu", [], 0],
		["cooler", "cooler", [], 0],
		["ram1", "ram", [], 0],
		["ram2", "ram", [], 1],
		["ram3", "ram", [], 2],
		["ram4", "ram", [], 3],
		["gpu", "gpu", [], 0],
		["psu", "psu", [], 0],
		["ssd", "ssd", ["hdd"], 0],
		["m2", "nvme", [], 0],
		["fan1", "fan", [], 0],
		["fan2", "fan", [], 1],
		["cmos", "cmos", [], 0],
	]
	for d in defs:
		var sn: String = d[0]
		if not slot_pos.has(sn):
			continue
		var s = SLOT.new()
		s.name = sn
		MU.no_merge(s)
		s.position = slot_pos[sn]
		if sn == "fan1":
			s.rotation_degrees = Vector3(0, -90, 0)  # arka egzoz: kasa içine (+Z) bakar
		elif sn == "fan2":
			s.rotation_degrees = Vector3(0, 90, 0)   # ön giriş: kasa içine (-Z) bakar
		add_child(s)
		s.setup(d[1], self, d[2], d[3])
		slots[sn] = s


## Gerçekçi eğrisel ve etkileşimli kablolar (24-pin, CPU 8-pin, PCIe GPU, SATA, ön panel).
func _build_cables() -> void:
	var sleeve := MU.mat(Color(0.07, 0.07, 0.08), 0.1, 0.75)
	var sleeve2 := MU.mat(Color(0.12, 0.12, 0.13), 0.1, 0.7)
	var plug_m := MU.mat(Color(0.04, 0.04, 0.045), 0.1, 0.5)
	var red := MU.mat(Color(0.75, 0.1, 0.1), 0, 0.6)
	var fp_m := MU.mat(Color(0.18, 0.22, 0.32), 0.1, 0.6)
	var warn_m := MU.mat(Color(1.0, 0.55, 0.1), 0, 0.4, 1.5)
	var bx := board_x
	var dy := maxf(case_h - H, -0.105)
	var psu_z: float = slot_pos.psu.z + 0.105
	var ssd_z: float = slot_pos.ssd.z + 0.056
	var gy: float = slot_pos.gpu.y

	var specs := [
		["atx_24",
			[Vector3(0.015, 0.118, psu_z), Vector3(0.025, 0.15 + dy * 0.4, 0.04), Vector3(0.0, 0.22 + dy * 0.6, 0.10),
				Vector3(-0.045, 0.31 + dy, 0.105), Vector3(bx + 0.025, 0.352 + dy, 0.10)],
			0.0085, sleeve2, Vector3(0.016, 0.056, 0.016), Vector3(bx + 0.016, 0.355 + dy, 0.102), Vector3(0.028, 0, 0.006)],
		["cpu_8",
			[Vector3(-0.015, 0.118, psu_z), Vector3(0.045, 0.17 + dy * 0.4, -0.05),
				Vector3(0.055, 0.28 + dy * 0.8, -0.09), Vector3(bx + 0.02, case_h - 0.025, -0.10)],
			0.0055, sleeve, Vector3(0.014, 0.012, 0.03), Vector3(bx + 0.012, case_h - 0.03, -0.10), Vector3(0.024, -0.014, 0.0)],
		["pcie_gpu",
			[Vector3(-0.04, 0.118, psu_z), Vector3(0.0, 0.13, 0.01),
				Vector3(0.045, gy, 0.04), Vector3(0.0105, gy + 0.023, 0.035)],
			0.0055, sleeve, Vector3(0.012, 0.014, 0.026), Vector3(0.0105, gy + 0.017, 0.035), Vector3(0.024, 0.018, 0.0)],
		["sata",
			[Vector3(0.045, 0.0675, 0.0), Vector3(0.06, 0.05, ssd_z * 0.5), Vector3(0.022, 0.015, ssd_z)],
			0.003, sleeve, Vector3(0.016, 0.009, 0.016), Vector3(0.016, 0.015, ssd_z), Vector3(0.0, 0.022, 0.022)],
		["front_panel",
			[Vector3(0.0, 0.04, case_d * 0.5 - 0.04), Vector3(-0.02, 0.11, 0.09), Vector3(bx + 0.012, 0.175 + dy, 0.075)],
			0.0028, fp_m, Vector3(0.012, 0.014, 0.022), Vector3(bx + 0.012, 0.175 + dy, 0.075), Vector3(0.026, -0.01, 0.0)],
	]
	cable_nodes.clear()
	cable_groups.clear()
	for sp in specs:
		var cid: String = sp[0]
		var g := MU.no_merge(Node3D.new())
		g.name = "Cable_" + cid
		add_child(g)
		var pts: Array[Vector3] = []
		for pt in sp[1]:
			pts.append(pt)
		var tube_mi := MU.tube(g, pts, float(sp[2]), sp[3], 6)
		MU.no_merge(tube_mi)
		if cid == "sata":
			var pdata: Array[Vector3] = [Vector3(bx + 0.012, 0.2 + dy, 0.10), Vector3(-0.03, 0.11, ssd_z * 0.85), Vector3(0.006, 0.015, ssd_z)]
			MU.no_merge(MU.tube(g, pdata, 0.0025, red, 5))
		var plug := MU.no_merge(Node3D.new())
		var ok_pos: Vector3 = sp[5]
		var loose_pos: Vector3 = ok_pos + sp[6]
		plug.position = ok_pos
		g.add_child(plug)
		MU.rbox(plug, sp[4], Vector3.ZERO, plug_m, 0.002)
		var warn := MU.box(plug, sp[4] * 1.15, Vector3.ZERO, warn_m)
		warn.visible = false
		var it = MU.interactable(plug, sp[4] + Vector3(0.028, 0.028, 0.028), Vector3.ZERO,
			func(_p): return _cable_hint(cid), func(_p): _cable_use(cid))
		cable_nodes[cid] = {"root": g, "plug": plug, "warn": warn, "inter": it, "ok_pos": ok_pos, "loose_pos": loose_pos, "tube": tube_mi}
		cable_groups[cid] = g
	if cable_nodes.has("pcie_gpu"):
		cable_groups["gpu"] = cable_nodes["pcie_gpu"].root
	if cable_nodes.has("atx_24"):
		cable_groups["psu"] = cable_nodes["atx_24"].root
	if cable_nodes.has("sata"):
		cable_groups["ssd"] = cable_nodes["sata"].root


## Sökülüp sıkılabilen vidalar: yan kapak (2), GPU braketi ve M.2 SSD vidası.
func _build_screws() -> void:
	screw_nodes.clear()
	var steel := MU.mat(Color(0.78, 0.8, 0.84), 0.9, 0.25)
	var hole_m := MU.mat(Color(0.05, 0.05, 0.06), 0.3, 0.7)
	var defs := [
		["panel_1", panel_pivot, Vector3(0.006, case_h - 0.04, case_d - 0.016), Vector3(0, 0, 90), Vector3(0.036, 0.04, 0.04)],
		["panel_2", panel_pivot, Vector3(0.006, 0.04, case_d - 0.016), Vector3(0, 0, 90), Vector3(0.036, 0.04, 0.04)],
		["gpu", self, Vector3(-case_w * 0.27, slot_pos.gpu.y + 0.008, -case_d / 2.0 + 0.008), Vector3(90, 0, 0), Vector3(0.04, 0.04, 0.036)],
		["m2", self, slot_pos.m2 + Vector3(0.005, 0.0, 0.038), Vector3(0, 0, 90), Vector3(0.032, 0.032, 0.032)],
	]
	for d in defs:
		var sid: String = d[0]
		var parent: Node3D = d[1]
		var root := MU.no_merge(Node3D.new())
		root.name = "Screw_" + sid
		root.position = d[2]
		parent.add_child(root)
		var head := MU.cyl(root, 0.0045, 0.006, Vector3.ZERO, steel, d[3], 10)
		var hole := MU.cyl(root, 0.003, 0.002, Vector3.ZERO, hole_m, d[3], 8)
		var it = MU.interactable(root, d[4], Vector3.ZERO,
			func(p): return _screw_hint(sid, p), func(p): _screw_use(sid, p))
		screw_nodes[sid] = {"root": root, "head": head, "hole": hole, "inter": it}


## Kasa arkası: I/O kalkanı, PSU girişi, PCIe kapakları (dış yüz).
func _build_rear_io() -> void:
	var z := -case_d / 2.0 - 0.0015
	var io_y: float = slot_pos.cpu.y + 0.02
	var plate := MU.mat(Color(0.55, 0.57, 0.6), 0.9, 0.35)
	var black := MU.mat(Color(0.03, 0.03, 0.035), 0.2, 0.5)
	var rx := -case_w * 0.27
	MU.box(self, Vector3(0.06, 0.09, 0.002), Vector3(rx, io_y, z), plate)
	for i in 4:
		MU.box(self, Vector3(0.012, 0.007, 0.0025), Vector3(rx - 0.02 + (i % 2) * 0.015, io_y + 0.035 - (i / 2) * 0.012, z - 0.0005), MU.mat(Color(0.1, 0.3, 0.9), 0, 0.5))
	MU.box(self, Vector3(0.014, 0.012, 0.0028), Vector3(rx + 0.015, io_y + 0.035, z - 0.0005), black)
	MU.box(self, Vector3(0.012, 0.009, 0.0028), Vector3(rx + 0.015, io_y + 0.015, z - 0.0005), MU.mat(Color(0.8, 0.8, 0.82), 0.9, 0.3))
	var jacks := [Color(0.2, 0.8, 0.3), Color(0.9, 0.3, 0.5), Color(0.2, 0.5, 0.9)]
	for i in 3:
		MU.cyl(self, 0.003, 0.003, Vector3(rx - 0.025 + i * 0.01, io_y - 0.025, z - 0.0005), MU.mat(jacks[i]), Vector3(90, 0, 0), 8)
	var brackets := 5 if case_h >= 0.42 else (4 if case_h >= 0.36 else 2)
	for i in brackets:
		MU.box(self, Vector3(0.05, 0.012, 0.002), Vector3(rx, slot_pos.gpu.y + 0.015 - i * 0.02, z), plate)
		MU.box(self, Vector3(0.04, 0.003, 0.0025), Vector3(rx, slot_pos.gpu.y + 0.015 - i * 0.02, z - 0.0004), black)
	# PSU girişi: IEC soket + anahtar + ızgara
	MU.box(self, Vector3(minf(0.15, case_w - 0.03), 0.085, 0.002), Vector3(0.0, 0.0475, z), black)
	MU.rbox(self, Vector3(0.03, 0.022, 0.004), Vector3(0.04, 0.035, z - 0.0015), MU.mat(Color(0.12, 0.12, 0.13), 0.2, 0.5), 0.002)
	MU.rbox(self, Vector3(0.012, 0.016, 0.004), Vector3(0.012, 0.035, z - 0.0015), MU.mat(Color(0.8, 0.1, 0.1), 0, 0.4), 0.002)
	for i in 6:
		MU.box(self, Vector3(0.08, 0.003, 0.0025), Vector3(-0.025, 0.02 + i * 0.01, z - 0.0005), MU.mat(Color(0.08, 0.08, 0.09)))


## Toz katmanları (yarı saydam gri tüylü quad'lar): gizlenebilir, birleştirilmez.
func _build_dust() -> void:
	_dust_mat = MU.new_mat(Color(1, 1, 1, 0.0), 0, 1.0)
	_dust_mat.albedo_texture = MU.dust_texture()
	_dust_mat.uv1_scale = Vector3(2, 2, 1)
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var holder := MU.no_merge(Node3D.new())
	holder.name = "Dust"
	add_child(holder)
	var specs := [
		[Vector2(minf(0.28, case_h - 0.14), minf(0.28, case_d - 0.12)), slot_pos.mobo + Vector3(0.005, 0, 0), Vector3(0, 90, 0), ""],
		[Vector2(case_w - 0.02, case_d - 0.02), Vector3(0.0, 0.009, 0.0), Vector3(-90, 0, 0), ""],
		[Vector2(0.088, 0.088), slot_pos.cpu + Vector3(0.0605, 0, 0), Vector3(0, 90, 0), "cpu"],
		[Vector2(0.22, 0.028), slot_pos.gpu + Vector3(0.1085, -0.013, 0), Vector3(0, 90, 0), "gpu"],
		[Vector2(0.104, 0.22), slot_pos.gpu + Vector3(0.053, -0.0335, 0), Vector3(90, 0, 0), "gpu"],
		[Vector2(0.12, 0.12), slot_pos.psu + Vector3(0, 0.0446, 0), Vector3(-90, 0, 0), "psu"],
		[Vector2(0.11, 0.11), slot_pos.fan1 + Vector3(0, 0, 0.016), Vector3.ZERO, ""],
	]
	if slot_pos.has("fan2"):
		specs.append([Vector2(0.12, 0.12), slot_pos.fan2 + Vector3(0, 0, -0.016), Vector3(0, 180, 0), ""])
	for sp in specs:
		var qm := QuadMesh.new()
		qm.size = sp[0]
		var mi := MeshInstance3D.new()
		mi.mesh = qm
		mi.material_override = _dust_mat
		mi.position = sp[1]
		mi.rotation_degrees = sp[2]
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		_dust_nodes.append([mi, sp[3]])
	# macun lekesi (CPU soketinde)
	paste_blob = MU.sphere(self, 0.011, slot_pos.cpu + Vector3(0.0045, 0, 0), MU.mat(Color(0.7, 0.72, 0.76), 0.8, 0.25), Vector3(0.22, 1, 1))
	MU.no_merge(paste_blob)
	paste_blob.visible = false


func set_dust(v: float) -> void:
	dust = clampf(v, 0.0, 1.0)
	_dust_vis = dust
	_apply_dust(dust)


## Basınçlı hava ile temizle: toz yavaşça kaybolur.
func clean_dust() -> void:
	var from := _dust_vis
	dust = 0.0
	_dust_vis = 0.0
	if _dust_tween:
		_dust_tween.kill()
	_dust_tween = create_tween()
	_dust_tween.tween_method(_apply_dust, from, 0.0, 0.8)


func _apply_dust(v: float) -> void:
	if _dust_mat == null:
		return
	_dust_mat.albedo_color.a = clampf(v * 1.1, 0.0, 1.0) * 0.5
	_update_visuals(v > 0.04)


func _is_unlocked() -> bool:
	return slots.is_empty() or slots.values()[0].is_processing()


func has_debug_leds() -> bool:
	if post_card_active:
		return true
	var mobo = part_in("mobo")
	if mobo != null:
		var d: PartDef = mobo.def()
		if d != null:
			return bool(d.specs.get("debug_led", false))
	return false


func gpu_needs_cable() -> bool:
	var g = part_in("gpu")
	if g == null:
		return false
	var d: PartDef = g.def()
	if d == null:
		return false
	return not d.compat.get("pcie_pins", []).is_empty()


func sata_present() -> bool:
	return part_in("ssd") != null


func _cable_visible(cid: String) -> bool:
	var st := str(cables.get(cid, "ok"))
	match cid:
		"atx_24", "cpu_8":
			return (part_in("psu") != null and part_in("mobo") != null) or st != "ok"
		"pcie_gpu":
			return (part_in("psu") != null and gpu_needs_cable()) or (part_in("gpu") != null and st != "ok")
		"sata":
			return sata_present() or st != "ok"
		"front_panel":
			return part_in("mobo") != null or st != "ok"
	return false


func _update_visuals(dust_on = null) -> void:
	if not _built:
		return
	var on: bool = (dust > 0.04) if dust_on == null else dust_on
	for d in _dust_nodes:
		var req: String = d[1]
		d[0].visible = on and (req == "" or (slots.has(req) and slots[req].part != null))
	if _debug_led_group:
		_debug_led_group.visible = has_debug_leds()
	var unlocked := _is_unlocked()
	for cid in cable_nodes:
		var cn: Dictionary = cable_nodes[cid]
		var vis := _cable_visible(cid)
		cn.root.visible = vis
		var st := str(cables.get(cid, "ok"))
		var is_ok := st == "ok"
		cn.plug.position = cn.ok_pos if is_ok else cn.loose_pos
		cn.warn.visible = vis and not is_ok
		cn.tube.position.x = -0.012 if cables_tidy else 0.0
		cn.inter.collision_layer = 3 if (unlocked and vis and panel_open) else 0
	for sid in screw_nodes:
		var sn: Dictionary = screw_nodes[sid]
		var show := true
		if sid == "gpu":
			show = part_in("gpu") != null
		elif sid == "m2":
			show = part_in("m2") != null
		sn.root.visible = show
		var tight := bool(screws.get(sid, false))
		sn.head.visible = tight
		sn.hole.visible = not tight
		var active := false
		if unlocked and show:
			active = (not panel_open) if (sid == "panel_1" or sid == "panel_2") else panel_open
		sn.inter.collision_layer = 3 if active else 0
	if paste_blob and slots.has("cpu"):
		paste_blob.visible = socket_paste and slots.cpu.part == null


func _cable_hint(cid: String) -> String:
	if not panel_open:
		return ""
	var nm := str(CABLE_NAMES.get(cid, cid))
	if str(cables.get(cid, "ok")) != "ok":
		return "Tak: %s kablosu  [E]" % nm
	return "%s kablosu (takılı)" % nm


func _cable_use(cid: String) -> void:
	if not panel_open:
		return
	if str(cables.get(cid, "ok")) != "ok":
		plug_cable(cid)


func plug_cable(cid: String) -> bool:
	if not cables.has(cid) or str(cables[cid]) == "ok":
		return false
	cables[cid] = "ok"
	Game.sfx.click()
	_update_visuals()
	Game.msg("%s kablosu takıldı." % str(CABLE_NAMES.get(cid, cid)), Color(0.5, 1.0, 0.5))
	return true


func fix_all_cables() -> void:
	for cid in CABLE_IDS:
		cables[cid] = "ok"
	_update_visuals()


func tidy_cables() -> bool:
	for cid in CABLE_IDS:
		if str(cables.get(cid, "ok")) != "ok":
			Game.sfx.error()
			Game.msg("Önce gevşek kabloları tak (%s)!" % str(CABLE_NAMES.get(cid, cid)), Color(1.0, 0.7, 0.35))
			return false
	if not cables_tidy:
		cables_tidy = true
		Game.sfx.click()
		_update_visuals()
		Game.msg("Kablolar kelepçelenip düzenlendi!", Color(0.5, 1.0, 0.6))
	return true


func panel_screwed() -> bool:
	return bool(screws.get("panel_1", false)) or bool(screws.get("panel_2", false))


func slot_screwed(slot_name: String) -> bool:
	if slot_name == "gpu" or slot_name == "m2":
		return bool(screws.get(slot_name, false))
	return false


func screws_missing() -> bool:
	if not bool(screws.get("panel_1", false)) or not bool(screws.get("panel_2", false)):
		return true
	if part_in("gpu") != null and not bool(screws.get("gpu", false)):
		return true
	if part_in("m2") != null and not bool(screws.get("m2", false)):
		return true
	return false


func missing_screws_text() -> String:
	var miss: Array[String] = []
	if not bool(screws.get("panel_1", false)) or not bool(screws.get("panel_2", false)):
		miss.append("Yan Kapak")
	if part_in("gpu") != null and not bool(screws.get("gpu", false)):
		miss.append("GPU Braketi")
	if part_in("m2") != null and not bool(screws.get("m2", false)):
		miss.append("M.2")
	return ", ".join(miss)


func _screw_hint(sid: String, player) -> String:
	var nm := str(SCREW_NAMES.get(sid, sid))
	var tight := bool(screws.get(sid, false))
	var verb := "Vidayı sök" if tight else "Vidayı sık"
	var is_bench: bool = player != null and player.has_method("enter")
	if is_bench or Game.has_upgrade("auto_screw"):
		return "%s: %s  [E]" % [verb, nm]
	var h = player.get("held") if player else null
	if h != null and h.has_method("is_tool") and h.is_tool() and h.tool_type == "screwdriver":
		return "%s: %s  [E]" % [verb, nm]
	return "%s vidası (%s — Tornavida gerekir)" % [nm, "sıkılı" if tight else "sökük"]


func _screw_use(sid: String, player) -> void:
	var is_bench: bool = player == null or player.has_method("enter")
	var h = player.get("held") if (player != null and not is_bench) else null
	var has_sd: bool = is_bench or Game.has_upgrade("auto_screw") or (h != null and h.has_method("is_tool") and h.is_tool() and h.tool_type == "screwdriver")
	if not has_sd:
		Game.sfx.error()
		Game.msg("Vidayı sökmek/sıkmak için eline Tornavida al.", Color(1.0, 0.75, 0.35))
		return
	toggle_screw(sid)


func toggle_screw(sid: String) -> bool:
	if not screws.has(sid):
		return false
	screws[sid] = not bool(screws[sid])
	Game.sfx.screw()
	_update_visuals()
	return true


func unscrew(sid: String) -> bool:
	if not bool(screws.get(sid, false)):
		return false
	screws[sid] = false
	Game.sfx.screw()
	_update_visuals()
	return true


func fasten_screw(sid: String) -> bool:
	if bool(screws.get(sid, false)):
		return false
	screws[sid] = true
	Game.sfx.screw()
	_update_visuals()
	return true


func unscrew_all() -> void:
	for k in screws:
		screws[k] = false
	_update_visuals()


func fasten_all() -> void:
	screws["panel_1"] = true
	screws["panel_2"] = true
	screws["gpu"] = part_in("gpu") != null
	screws["m2"] = part_in("m2") != null
	_update_visuals()


func mobo_has_children() -> bool:
	for sn in ["cpu", "cooler", "ram1", "ram2", "ram3", "ram4", "gpu", "m2", "cmos"]:
		if part_in(sn) != null:
			return true
	return false


func can_remove_reason(slot_name: String) -> String:
	if slot_name == "mobo" and mobo_has_children():
		return "Anakartı sökmeden önce üzerindeki parçaları çıkar."
	if slot_screwed(slot_name):
		if Game.has_upgrade("auto_screw"):
			screws[slot_name] = false
			_update_visuals()
			return ""
		return "Önce %s vidasını tornavidayla sök." % str(SCREW_NAMES.get(slot_name, slot_name))
	return ""


func on_slot_installed(slot_name: String) -> void:
	if slot_name == "gpu" or slot_name == "m2":
		screws[slot_name] = Game.has_upgrade("auto_screw")


func has_sw_fault(code: String) -> bool:
	return sw_faults.has(code)


func fix_sw_fault(code: String) -> bool:
	if not sw_faults.has(code):
		return false
	sw_faults.erase(code)
	on_parts_changed()
	return true


func cpu_installed(p) -> void:
	if socket_paste:
		p.paste_ok = true
		socket_paste = false
		Game.msg("İşlemci macunla takıldı.", Color(0.7, 0.9, 1.0))


# ---------------------------------------------------------------- aletler

func tool_hint(tool, slot) -> String:
	var tt := str(tool.tool_type)
	match tt:
		"paste":
			if slot == null or slot.accepts != "cpu":
				return "Termal macun: boş işlemci soketine sürülür"
			if slot.part:
				return "Macun için önce işlemciyi sök"
			if socket_paste:
				return "Soket zaten macunlu, işlemciyi tak"
			return "Termal macun sür  [E]"
		"air":
			return "Tozu üfle  [E]" if dust > 0.02 else "Üfle  [E] (zaten temiz)"
		"ipa":
			return "IPA ile temas noktalarını temizle  [E]"
		"screwdriver":
			if slot != null and slot.accepts == "cpu" and slot.part != null and slot.part.bent_pins:
				return "Eğik CPU pinlerini düzelt  [E]"
			if slot != null and (slot.name == "gpu" or slot.name == "m2") and slot.part != null:
				return ("Vidayı sök (%s)  [E]" if slot_screwed(slot.name) else "Vidayı sık (%s)  [E]") % str(SCREW_NAMES.get(slot.name, slot.name))
			return "Vidaları sök/sık  [E]"
		"psu_tester":
			return "PSU ve güç kablolarını test et  [E]"
		"multimeter":
			if slot != null and slot.part != null:
				return "Multimetre ile ölç: %s  [E]" % slot.part.display_name
			return "Anakart ve voltajı ölç  [E]"
		"post_card":
			return "POST Teşhis Kartı tak / kod oku  [E]"
		"thermal_cam":
			return "Termal Kamera ile sıcaklık & toz tara  [E]"
		"ram_usb":
			return "RAM Test USB ile bellekleri tara  [E]"
		"smart_usb":
			return "Disk SMART USB ile disk sağlığını tara  [E]"
		"antivirus_usb":
			return "Antivirüs USB ile virüs tara & temizle  [E]"
		"install_usb":
			return "Kurulum & BIOS USB kullan  [E]"
	return ""


func tool_use(player, tool, slot) -> void:
	var tt := str(tool.tool_type)
	match tt:
		"paste":
			if slot == null or slot.accepts != "cpu":
				Game.msg("Macunu boş işlemci soketine sürmelisin.", Color(1, 0.8, 0.4))
			elif slot.part:
				Game.msg("Önce işlemciyi sökmelisin.", Color(1, 0.8, 0.4))
			elif socket_paste:
				Game.msg("Soket zaten macunlu.", Color(1, 0.8, 0.4))
			else:
				socket_paste = true
				Game.sfx.squish()
				_update_visuals()
				Game.msg("Termal macun sürüldü. Şimdi işlemciyi tak.", Color(0.7, 0.9, 1.0))
		"air":
			tool.puff(player)
			if dust > 0.02:
				clean_dust()
				Game.msg("Kasanın içi tozdan arındı!", Color(0.7, 0.9, 1.0))
			else:
				Game.msg("İçerisi zaten temiz.")
		"ipa":
			tool.puff(player, Color(0.72, 0.96, 0.82, 0.35))
			Game.msg("IPA spreyiyle kontaklar temizlendi.", Color(0.7, 0.95, 0.8))
		"screwdriver":
			if slot != null and slot.accepts == "cpu" and slot.part != null and slot.part.bent_pins:
				slot.part.straighten_pins()
				Game.sfx.screw()
				on_parts_changed()
				Game.msg("Eğik CPU pinleri hassasça düzeltildi!", Color(0.5, 1.0, 0.5))
			elif slot != null and (slot.name == "gpu" or slot.name == "m2") and slot.part != null:
				toggle_screw(slot.name)
			elif not panel_open:
				if panel_screwed():
					unscrew("panel_1")
					unscrew("panel_2")
					Game.msg("Yan kapak vidaları söküldü.", Color(0.7, 0.9, 1.0))
				else:
					fasten_screw("panel_1")
					fasten_screw("panel_2")
					Game.msg("Yan kapak vidaları sıkıldı.", Color(0.7, 0.9, 1.0))
			else:
				Game.msg("Tornavida: sökmek/sıkmak istediğin vidaya veya eğik pinli CPU'ya tıkla.", Color(0.7, 0.9, 1.0))
		"psu_tester":
			Game.sfx.beep_scan()
			var psu = part_in("psu")
			var w := watt_summary()
			if psu == null:
				Game.msg("PSU Testi: Güç kaynağı takılı değil!", Color(1.0, 0.55, 0.35))
			elif psu.broken:
				Game.msg("PSU Testi: ARIZALI! +12V / +5V çıkışı yok.", Color(1.0, 0.35, 0.3))
			elif str(cables.get("atx_24", "ok")) != "ok" or str(cables.get("cpu_8", "ok")) != "ok" or (gpu_needs_cable() and str(cables.get("pcie_gpu", "ok")) != "ok"):
				Game.msg("PSU Testi: PSU sağlam (%dW) ama güç kablolarından biri gevşek!" % w.psu, Color(1.0, 0.78, 0.3))
			elif not w.ok or w.psu < w.recommended:
				Game.msg("PSU Testi: Watt yetersiz! (%dW < gereken %dW+)" % [w.psu, w.recommended], Color(1.0, 0.65, 0.3))
			else:
				Game.msg("PSU Testi: Tüm kanallar OK (+12.0V / +5.0V / %dW)." % w.psu, Color(0.5, 1.0, 0.5))
		"multimeter":
			Game.sfx.beep_scan()
			if slot != null and slot.part != null:
				var pt = slot.part
				if pt.broken:
					Game.msg("Multimetre (%s): KISA DEVRE / ARIZALI!" % pt.display_name, Color(1.0, 0.35, 0.3))
				elif pt.bad_caps:
					Game.msg("Multimetre (%s): Kondansatör voltajı dengesiz (şişmiş)!" % pt.display_name, Color(1.0, 0.5, 0.3))
				elif pt.bent_pins:
					Game.msg("Multimetre (%s): Pin temassızlığı tespit edildi!" % pt.display_name, Color(1.0, 0.6, 0.3))
				elif pt.vram_bad:
					Game.msg("Multimetre (%s): VRAM bellek hattında hata!" % pt.display_name, Color(1.0, 0.5, 0.3))
				else:
					Game.msg("Multimetre (%s): Voltaj değerleri NORMAL (Sağlam)." % pt.display_name, Color(0.5, 1.0, 0.5))
			else:
				var mobo = part_in("mobo")
				var cmos = part_in("cmos")
				if mobo == null or mobo.broken:
					Game.msg("Multimetre: Anakart besleme hattı ölü (0.0V).", Color(1.0, 0.35, 0.3))
				elif mobo.bad_caps:
					Game.msg("Multimetre: Anakart VRM kondansatörleri şişmiş (dalgalı voltaj)!", Color(1.0, 0.5, 0.3))
				elif cmos == null or cmos.broken:
					Game.msg("Multimetre: CMOS pili voltajı düşük (0.4V < 3.0V)!", Color(1.0, 0.7, 0.3))
				else:
					Game.msg("Multimetre: Anakart ve CMOS (+3.0V) hatları normal.", Color(0.5, 1.0, 0.5))
		"post_card":
			Game.sfx.beep_scan()
			post_card_active = true
			_update_visuals()
			var issues := diagnose_all()
			if issues.is_empty():
				Game.msg("POST Kartı [AA]: Sistem tüm donanım kontrollerinden geçti.", Color(0.5, 1.0, 0.5))
			else:
				var hex_map := {"nopower": "00", "cable_fp": "01", "cable_24pin": "02", "mobo": "05", "mobo_cap": "09",
					"cable_cpu": "10", "cpu": "12", "cpu_pins": "14", "ram": "53", "ram_unseated": "55",
					"cable_gpu": "92", "gpu": "96", "gpu_artifact": "98", "cable_sata": "A1", "ssd": "A2",
					"hdd_smart": "A4", "cooler": "C1", "fan": "C2", "cmos": "E0", "overheat": "F1"}
				var code := str(issues[0])
				Game.msg("POST Kartı [%s]: %s (%d sorun)" % [hex_map.get(code, "FF"), code, issues.size()], Color(1.0, 0.72, 0.3))
		"thermal_cam":
			Game.sfx.beep_scan()
			var cpu = part_in("cpu")
			var cooler = part_in("cooler")
			var paste_txt := "KURU!" if (cpu != null and not cpu.paste_ok) else "Taze"
			var fan_bad := false
			for fn in ["fan1", "fan2"]:
				var fp = part_in(fn)
				if fp != null and fp.broken:
					fan_bad = true
			var cooler_bad: bool = cooler == null or cooler.broken
			var c_col := Color(1.0, 0.45, 0.3) if (dust > 0.5 or paste_txt == "KURU!" or fan_bad or cooler_bad) else Color(0.5, 1.0, 0.5)
			Game.msg("Termal Kamera: CPU %.0f°C · Toz %%%d · Macun: %s%s" % [
				cpu_temp, roundi(dust * 100.0), paste_txt,
				(" · DURMUŞ FAN!" if (fan_bad or cooler_bad) else "")
			], c_col)
		"ram_usb":
			Game.sfx.beep_scan()
			var bad_msgs: Array[String] = []
			for rn in ["ram1", "ram2", "ram3", "ram4"]:
				var rp = part_in(rn)
				if rp == null:
					continue
				if rp.broken:
					bad_msgs.append("%s: BOZUK" % rn.to_upper())
				elif not rp.seated:
					bad_msgs.append("%s: OTURMAMIŞ" % rn.to_upper())
				else:
					bad_msgs.append("%s: OK" % rn.to_upper())
			if bad_msgs.is_empty():
				Game.msg("RAM Test USB: Hiç RAM algılanmadı!", Color(1.0, 0.45, 0.3))
			else:
				var xmp_txt := " · XMP KAPALI" if has_sw_fault("sw_xmp_off") else ""
				var any_bad := bad_msgs.any(func(s): return not s.ends_with("OK")) or xmp_txt != ""
				Game.msg("RAM Testi: " + ", ".join(bad_msgs) + xmp_txt, Color(1.0, 0.65, 0.3) if any_bad else Color(0.5, 1.0, 0.5))
		"smart_usb":
			Game.sfx.beep_scan()
			var d_msgs: Array[String] = []
			for sn in ["m2", "ssd"]:
				var sp = part_in(sn)
				if sp == null:
					continue
				if sp.broken:
					d_msgs.append("%s: YANIT YOK" % sn.to_upper())
				else:
					d_msgs.append("%s: %%%d sağlık" % [sn.to_upper(), int(sp.health)])
			if d_msgs.is_empty():
				Game.msg("SMART USB: Hiçbir depolama birimi bulunamadı!", Color(1.0, 0.45, 0.3))
			else:
				var full_txt := " · DİSK DOLU (%99)" if has_sw_fault("sw_disk_full") else ""
				var warn: bool = has_sw_fault("sw_disk_full") or d_msgs.any(func(s): return "YANIT" in s) or (part_in("ssd") != null and part_in("ssd").health < 35) or (part_in("m2") != null and part_in("m2").health < 35)
				Game.msg("SMART USB: " + ", ".join(d_msgs) + full_txt, Color(1.0, 0.65, 0.3) if warn else Color(0.5, 1.0, 0.5))
		"antivirus_usb":
			Game.sfx.beep_scan()
			if fix_sw_fault("sw_virus"):
				Game.msg("Antivirüs USB: Virüs ve reklam yazılımları temizlendi!", Color(0.5, 1.0, 0.5))
			else:
				Game.msg("Antivirüs USB: Tehdit bulunamadı, sistem temiz.", Color(0.7, 0.9, 1.0))
		"install_usb":
			Game.sfx.beep_scan()
			if fix_sw_fault("sw_os_corrupt"):
				Game.msg("Kurulum USB: Disk formatlandı ve BilgiOS yeniden kuruldu!", Color(0.5, 1.0, 0.5))
			elif fix_sw_fault("sw_bios_update"):
				Game.msg("Kurulum & BIOS USB: Anakart BIOS'u v3.2 sürümüne güncellendi!", Color(0.5, 1.0, 0.5))
			else:
				Game.msg("Kurulum USB: İşletim sistemi ve BIOS zaten güncel.", Color(0.7, 0.9, 1.0))


func get_hint(player) -> String:
	if player.held and player.held.is_tool():
		if not panel_open and player.held.tool_type != "screwdriver":
			return "Aleti kullanmak için kapağı aç"
		return tool_hint(player.held, null)
	return ""


func interact(player) -> void:
	if player.held and player.held.is_tool() and (panel_open or player.held.tool_type == "screwdriver"):
		tool_use(player, player.held, null)


# ---------------------------------------------------------------- parça doldurma ve sorgular

## Müşteri bilgisayarını doldurur.
## v3 dizi biçimi: [[slot_adı, tip, seviye, bozuk_mu, (macun_ok), (muadil)], ...]
## v4 sözlük biçimi: [{"slot", "sku", "broken", "paste_ok", "cheap", "health"}, ...]
## Eski çağrılar (mobo/cooler/fan1/cmos olmadan) uyumlu varsayılanlarla tamamlanır; boş [] kasa boş kalır.
func fill(parts: Array) -> void:
	var seen := {}
	var has_any_part := false
	cables = {"atx_24": "ok", "cpu_8": "ok", "pcie_gpu": "ok", "sata": "ok", "front_panel": "ok"}
	cables_tidy = false
	sw_faults = []
	screws = {"panel_1": true, "panel_2": true, "gpu": false, "m2": false}
	var has_explicit_screws := false
	for entry in parts:
		if entry is Dictionary:
			if entry.has("cables") and entry["cables"] is Dictionary:
				for ck in entry["cables"]:
					cables[str(ck)] = str(entry["cables"][ck])
				continue
			if entry.has("screws") and entry["screws"] is Dictionary:
				has_explicit_screws = true
				for sk in entry["screws"]:
					screws[str(sk)] = bool(entry["screws"][sk])
				continue
			if entry.has("sw_faults") and entry["sw_faults"] is Array:
				for sf in entry["sw_faults"]:
					if not sw_faults.has(str(sf)):
						sw_faults.append(str(sf))
				continue
			var sn := str(entry.get("slot", ""))
			if sn == "dust" or entry.has("dust"):
				set_dust(float(entry.get("amount", entry.get("dust", 0.0))))
				continue
			if sn.is_empty():
				continue
			seen[sn] = true
			var sku_id := str(entry.get("sku", ""))
			if sku_id.is_empty() or bool(entry.get("omit", false)):
				continue
			if not slots.has(sn):
				continue
			var part = PART.new().setup_sku(sku_id, bool(entry.get("broken", false)))
			if entry.has("paste_ok"):
				part.paste_ok = bool(entry.get("paste_ok", true))
			if entry.has("health"):
				part.health = int(entry.get("health", 100))
			if entry.has("seated"):
				part.seated = bool(entry.get("seated", true))
			if bool(entry.get("bent_pins", false)):
				part.mark_bent_pins(true)
			if bool(entry.get("bad_caps", false)):
				part.mark_bad_caps(true)
			if entry.has("vram_bad"):
				part.vram_bad = bool(entry.get("vram_bad", false))
			slots[sn].install(part)
			if bool(entry.get("cheap", false)):
				part.make_cheap()
			has_any_part = true
		elif entry is Array and entry.size() >= 4:
			var sn := str(entry[0])
			if sn == "dust":  # ["dust", "", miktar, false]: kasa tozu
				set_dust(float(entry[2]))
				continue
			seen[sn] = true
			if not slots.has(sn):
				continue
			var part = PART.new().setup(str(entry[1]), int(entry[2]), bool(entry[3]))
			if entry.size() > 4:  # 5. eleman: CPU macunu sağlam mı
				part.paste_ok = bool(entry[4])
			slots[sn].install(part)
			if entry.size() > 5 and bool(entry[5]):
				part.make_cheap()
			has_any_part = true
	# Geriye dönük uyumluluk: eski işler/testler mobo/cooler/fan1/cmos vermediyse uyumlu varsayılanları tak
	if has_any_part:
		_fill_legacy_defaults(seen)
	if not has_explicit_screws:
		screws["gpu"] = part_in("gpu") != null
		screws["m2"] = part_in("m2") != null
	_update_visuals(null if dust <= 0.0 else dust > 0.04)


func _fill_legacy_defaults(seen: Dictionary) -> void:
	if not seen.has("mobo") and slots.has("mobo") and slots["mobo"].part == null:
		var mobo_sku := _default_mobo_for_installed()
		slots["mobo"].install(PART.new().setup_sku(mobo_sku, false))
	if not seen.has("cooler") and slots.has("cooler") and slots["cooler"].part == null:
		slots["cooler"].install(PART.new().setup_sku("cooler_stock", false))
	if not seen.has("fan1") and slots.has("fan1") and slots["fan1"].part == null:
		slots["fan1"].install(PART.new().setup_sku("fan_120_std", false))
	if not seen.has("cmos") and slots.has("cmos") and slots["cmos"].part == null:
		slots["cmos"].install(PART.new().setup_sku("cmos_cr2032", false))


func _default_mobo_for_installed() -> String:
	var cpu = part_in("cpu")
	if cpu != null:
		var cdef: PartDef = cpu.def()
		if cdef != null:
			match str(cdef.compat.get("socket", "")):
				"AM5": return "mobo_am5_atx"
				"LGA1700": return "mobo_lga1700_matx"
				"LGA1851": return "mobo_lga1851_itx"
	if case_id == "itx_compact":
		return "mobo_lga1851_itx"
	return "mobo_am4_matx"


func part_in(slot_name: String):
	return slots[slot_name].part if slots.has(slot_name) else null


func installed_parts() -> Array:
	var out := []
	for s in slots.values():
		if s.part:
			out.append(s.part)
	return out


func total_ram() -> int:
	var gb := 0
	for n in ["ram1", "ram2", "ram3", "ram4"]:
		var p = part_in(n)
		if p and not p.broken:
			var d: PartDef = p.def()
			gb += int(d.specs.get("gb", 0)) if d != null else PM.ram_gb(p.tier)
	return gb


## Standart kasa durum sözlüğü (Compatibility motoru ile tam uyumlu).
func case_state() -> Dictionary:
	return Compatibility.case_state_of(self)


## Canlı güç tüketimi özeti: {"draw", "psu", "recommended", "ok"}.
func watt_summary() -> Dictionary:
	return Compatibility.calc_watts(case_state())


# ---------------------------------------------------------------- teşhis ve güç

## Tüm etkin arızaları öncelik sırasıyla liste olarak döndürür (çoklu arıza desteği).
func diagnose_all() -> Array[String]:
	var out: Array[String] = []
	var add_code := func(c: String):
		if not c.is_empty() and not out.has(c):
			out.append(c)

	if str(cables.get("front_panel", "ok")) != "ok":
		add_code.call("cable_fp")
	var psu = part_in("psu")
	if psu == null or psu.broken:
		add_code.call("nopower")
	if str(cables.get("atx_24", "ok")) != "ok":
		add_code.call("cable_24pin")
	var mobo = part_in("mobo")
	if mobo == null or mobo.broken:
		add_code.call("mobo")
	elif mobo.bad_caps:
		add_code.call("mobo_cap")
	if str(cables.get("cpu_8", "ok")) != "ok":
		add_code.call("cable_cpu")
	var cpu = part_in("cpu")
	if cpu == null or cpu.broken:
		add_code.call("cpu")
	elif cpu.bent_pins:
		add_code.call("cpu_pins")
	var rams := []
	for n in ["ram1", "ram2", "ram3", "ram4"]:
		var r = part_in(n)
		if r:
			rams.append(r)
	if rams.is_empty() or rams.any(func(r): return r.broken):
		add_code.call("ram")
	if rams.any(func(r): return not r.seated):
		add_code.call("ram_unseated")
	var gpu = part_in("gpu")
	if gpu != null:
		if gpu_needs_cable() and str(cables.get("pcie_gpu", "ok")) != "ok":
			add_code.call("cable_gpu")
		if gpu.broken:
			add_code.call("gpu")
		elif gpu.vram_bad:
			add_code.call("gpu_artifact")
	var storages := []
	for n in ["ssd", "m2"]:
		var st = part_in(n)
		if st:
			storages.append(st)
	if sata_present() and str(cables.get("sata", "ok")) != "ok":
		add_code.call("cable_sata")
	if storages.is_empty() or storages.any(func(s): return s.broken):
		add_code.call("ssd")
	if storages.any(func(s): return s.health < 35):
		add_code.call("hdd_smart")
	var cooler = part_in("cooler")
	if cooler == null or cooler.broken:
		add_code.call("cooler")
	for fn in ["fan1", "fan2"]:
		var fp = part_in(fn)
		if fp != null and fp.broken:
			add_code.call("fan")
	var cmos = part_in("cmos")
	if cmos == null or cmos.broken:
		add_code.call("cmos")
	var sys := Compatibility.check_system(case_state())
	if not sys.ok:
		for iss in sys.issues:
			var ic := str(iss.code)
			match ic:
				"no_mobo": add_code.call("mobo")
				"no_cpu": add_code.call("cpu")
				"no_cooler": add_code.call("cooler")
				"no_ram": add_code.call("ram")
				"no_storage": add_code.call("ssd")
				"no_psu": add_code.call("nopower")
				_: add_code.call(ic)
	var w := watt_summary()
	if w.psu > 0 and w.draw > 0 and w.psu < w.recommended:
		add_code.call("psu_watts")
	if dust > 0.5 or (cpu != null and not cpu.paste_ok):
		add_code.call("overheat")
	for sf in sw_faults:
		add_code.call(str(sf))
	return out


## İlk öncelikli teşhis kodu ("ok" = sorun yok).
func diagnose() -> String:
	var all := diagnose_all()
	return all[0] if not all.is_empty() else "ok"


func toggle_panel(force := false) -> void:
	if not panel_open and not force and not Game.has_upgrade("auto_screw") and panel_screwed():
		Game.sfx.error()
		var cnt := (1 if bool(screws.get("panel_1", false)) else 0) + (1 if bool(screws.get("panel_2", false)) else 0)
		Game.msg("Önce yan kapak vidalarını tornavidayla sök (%d vida)." % cnt, Color(1.0, 0.75, 0.35))
		return
	panel_open = not panel_open
	if panel_open and (force or Game.has_upgrade("auto_screw")):
		screws["panel_1"] = false
		screws["panel_2"] = false
	elif not panel_open and Game.has_upgrade("auto_screw"):
		screws["panel_1"] = true
		screws["panel_2"] = true
	_apply_panel_pose()
	Game.sfx.click()
	_update_visuals(null if dust <= 0.0 else dust > 0.04)


## Tezgâh modunda kasa yatırıldığında cam yan kapağı kasanın arkasına yaslar; kalkınca menteşeye geri oturtur.
func set_flat_mode(on: bool, instant := false) -> void:
	if flat_mode == on and not instant:
		return
	flat_mode = on
	_apply_panel_pose(instant)


func _apply_panel_pose(instant := false) -> void:
	if panel_pivot == null:
		return
	var rest_pos := Vector3(case_w / 2.0 - 0.002, 0.0, -case_d / 2.0)
	var target_pos := rest_pos
	var target_rot := Vector3.ZERO
	if panel_open:
		if flat_mode:
			target_pos = Vector3(-case_w / 2.0 + 0.01, case_h + 0.06, -case_d / 2.0)
			target_rot = Vector3(0.0, 0.0, deg_to_rad(-80.0))
		else:
			target_rot = Vector3(0.0, deg_to_rad(100.0), 0.0)
	if _panel_tw and _panel_tw.is_valid():
		_panel_tw.kill()
	if instant:
		panel_pivot.position = target_pos
		panel_pivot.rotation = target_rot
		return
	_panel_tw = create_tween().set_parallel(true)
	_panel_tw.tween_property(panel_pivot, "position", target_pos, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_panel_tw.tween_property(panel_pivot, "rotation", target_rot, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func power_button() -> void:
	Game.sfx.click()
	if powered:
		power_off()
		Game.msg("Bilgisayar kapatıldı.")
		return
	var code := diagnose()
	var fdef = DB.jobs.fault_by_code(code)  # belirti verisi (LED, bip, ekran, mesaj) arıza tanımından
	var sym: Dictionary = fdef.symptoms if fdef != null else {}
	if code in ["nopower", "mobo", "cable_fp", "cable_24pin"]:
		var fb := "Güç düğmesi tepki vermiyor! Ön panel kablosunu kontrol et." if code == "cable_fp" else \
			("24-pin anakart güç kablosu gevşek!" if code == "cable_24pin" else \
			("Hiçbir tepki yok... Anakart takılı değil veya arızalı." if code == "mobo" else "Hiçbir tepki yok... Fanlar bile dönmüyor."))
		_symptom_msg(sym, fb)
		return
	if code == "psu_watts" or code == "psu_connectors":
		Game.sfx.error()
		var fb := "Güç kaynağı yetersiz! Sistem açılmadan koruma kapattı." if code == "psu_watts" else "Ekran kartı güç kablosu uyumsuz! PSU konnektörü yetmiyor."
		_symptom_msg(sym, fb)
		return
	powered = true
	cpu_temp = 36.0
	_last_temp_i = -1
	_cap_t = 0.0
	var led_name: String = str(sym.get("led", _fallback_led(code)))
	if has_debug_leds() and led_name != "" and debug_leds.has(led_name):
		var lm: StandardMaterial3D = debug_leds[led_name]
		lm.albedo_color = Color(1.0, 0.45, 0.1)
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.45, 0.1)
		lm.emission_energy_multiplier = 6.0
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.2, 0.6, 1.0)
	led_mat.emission_energy_multiplier = 3.0
	hum.play()
	if code == "ok":
		Game.sfx.beeps([0.15])
		if monitor:
			monitor.boot(self)
		Game.msg("Tek kısa bip... Bilgisayar sorunsuz açıldı!", Color(0.5, 1, 0.5))
		return
	var beeps: Array = []
	for b in sym.get("beep", []):
		beeps.append(float(b))
	if not beeps.is_empty():
		Game.sfx.beeps(beeps)
	var screen := str(sym.get("screen", _fallback_screen(code)))
	if monitor:
		match screen:
			"no_signal": monitor.show_no_signal()
			"no_boot": monitor.show_no_boot()
			"artifact": monitor.show_artifact(self)
			"virus": monitor.show_virus(self)
			"os_bsod": monitor.show_bsod("CRITICAL_PROCESS_DIED", "İşletim sistemi dosyaları bozuk.\nKurulum USB'si veya Servis Paneli'nden format atın.")
			"driver_warn": monitor.show_desktop_warn(self, "Sürücü Hatası (Kod 43)", "Görüntü sürücüsü çakışıyor.\nMonitörden (E) Servis Paneli > Yazılım ile onarın.")
			"boot_order": monitor.show_bios_warn("BilgiBIOS — Açılış Sırası Hatası", "PXE-E61: Ağdan başlatılamadı.\nMonitörden (E) BIOS > Boot Sırasını düzeltin.")
			"bios_old": monitor.show_bios_warn("BilgiBIOS — Eski Sürüm", "Yeni işlemci tam tanınmadı (BIOS güncellemesi gerekli).\nKurulum & BIOS USB'si veya BIOS sekmesiyle güncelleyin.")
			"disk_full": monitor.show_desktop_warn(self, "Disk Dolu (%99)", "C: sürücüsünde boş alan kalmadı.\nServis Paneli > Yazılım'dan Disk Temizliği yapın.")
			"disk_warn": monitor.show_desktop_warn(self, "SMART Disk Uyarısı", "Sabit diskte bad sector tespit edildi!\nSMART sağlığı kritik — diski değiştirin.")
			"cmos_warn": monitor.show_bios_warn("CMOS Checksum Error", "BIOS tarih/saat sıfırlandı (01.01.2001).\nCMOS pilini (CR2032) değiştirin.")
			"boot": monitor.boot(self)
	_symptom_msg(sym, _fallback_msg(code))


func _fallback_led(code: String) -> String:
	match code:
		"socket", "cooler", "cooler_socket", "cooler_height", "cooler_rad", "cpu_pins", "cable_cpu", "sw_bios_update": return "CPU"
		"ddr_notch", "ram_slot_limit", "ram_unseated": return "DRAM"
		"no_display", "gpu_length", "cable_gpu", "gpu_artifact": return "VGA"
		"cmos", "m2_limit", "sata_limit", "cable_sata", "sw_boot_order", "hdd_smart": return "BOOT"
	return ""


func _fallback_screen(code: String) -> String:
	match code:
		"cooler", "fan", "mobo_cap", "sw_xmp_off": return "boot"
		"cmos": return "cmos_warn"
		"cable_sata": return "no_boot"
		"gpu_artifact": return "artifact"
		"sw_virus": return "virus"
		"sw_os_corrupt": return "os_bsod"
		"sw_driver": return "driver_warn"
		"sw_boot_order": return "boot_order"
		"sw_bios_update": return "bios_old"
		"sw_disk_full": return "disk_full"
		"hdd_smart": return "disk_warn"
		"no_display", "ddr_notch", "socket", "ram_slot_limit", "gpu_length", "cpu_pins", "ram_unseated", "cable_cpu", "cable_gpu": return "no_signal"
	return "no_signal"


func _fallback_msg(code: String) -> String:
	match code:
		"no_display": return "Ekrana görüntü gelmiyor: bu işlemcide dahili grafik yok, ekran kartı gerekli."
		"cooler": return "CPU soğutucu takılı değil veya arızalı! İşlemci hızla ısınıyor."
		"fan": return "Kasa fanlarından biri dönmüyor!"
		"cmos": return "CMOS pili eksik veya bitik — BIOS ayarları sıfırlandı."
		"ddr_notch": return "RAM çentiği anakartla uyumsuz, sistem açılmıyor."
		"socket": return "İşlemci soketi anakartla uyumsuz!"
		"cpu_pins": return "İşlemci pinleri eğilmiş! Sistem POST geçmiyor."
		"ram_unseated": return "RAM yuvasına tam oturmamış!"
		"cable_gpu": return "Ekran kartı güç kablosu takılı değil!"
		"cable_cpu": return "CPU 8-pin güç kablosu takılı değil!"
		"cable_sata": return "SATA veri/güç kablosu gevşek — disk bulunamıyor!"
		"cable_24pin": return "24-pin anakart güç kablosu takılı değil!"
		"cable_fp": return "Ön panel güç düğmesi kablosu takılı değil!"
	return "Sistem uyumsuzluk nedeniyle açılmadı (%s)." % code


## Belirti mesajı (sym.msg, sym.msg_color); boşsa fallback.
func _symptom_msg(sym: Dictionary, fallback: String) -> void:
	var c: Array = sym.get("msg_color", [1.0, 0.6, 0.4])
	var msg := str(sym.get("msg", fallback))
	if msg != "":
		Game.msg(msg, Color(float(c[0]), float(c[1]), float(c[2])))


func power_off() -> void:
	powered = false
	for lm in debug_leds.values():
		lm.emission_enabled = false
		lm.albedo_color = Color(0.25, 0.12, 0.05)
	led_mat.emission_enabled = false
	hum.stop()
	for m in _all_rgb():
		m.emission_energy_multiplier = 0.0
	inner_light.light_color = Color(0.9, 0.95, 1.0)
	if monitor:
		monitor.show_off()


func on_parts_changed() -> void:
	if _built:
		_update_visuals(null if dust <= 0.0 else dust > 0.04)
	if powered:
		power_off()
		Game.msg("Parça değişince bilgisayar kapandı.")


func _all_rgb() -> Array:
	var out := rgb_mats.duplicate()
	for p in installed_parts():
		out.append_array(p.rgb_mats)
	return out


func _process(delta: float) -> void:
	if not powered:
		cpu_temp = move_toward(cpu_temp, 30.0, 8.0 * delta)
		return
	_heat(delta)
	if not powered:
		return
	_hue = fmod(_hue + delta * 0.15, 1.0)
	var spin := 1.0 + maxf(cpu_temp - 50.0, 0.0) / 40.0
	for r in case_fans:
		r.rotate_object_local(Vector3.UP, delta * 30.0 * spin)
	for p in installed_parts():
		if p.broken:
			continue
		for r in p.rotors:
			r.rotate_object_local(Vector3.UP, delta * 28.0)
	var i := 0
	for m in _all_rgb():
		var c := Color.from_hsv(fmod(_hue + i * 0.12, 1.0), 0.85, 1.0)
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.5
		i += 1
	inner_light.light_color = Color.from_hsv(_hue, 0.6, 1.0)


## CPU sıcaklığı: masaüstü açıkken ısınma/soğuma; aşırı ısınırsa (veya şişmiş kondansatörde) bilgisayar kapanır.
func _heat(delta: float) -> void:
	if monitor == null or not monitor.desktop.visible:
		return
	var issues := diagnose_all()
	var mobo = part_in("mobo")
	if mobo != null and mobo.bad_caps:
		_cap_t += delta
		if _cap_t >= 2.2:
			power_off()
			Game.sfx.error()
			Game.msg("Anakart voltaj dalgalanmasıyla kapandı (şişmiş kondansatör)!", Color(1, 0.4, 0.3))
			return
	var hot := issues.has("overheat") or issues.has("cooler")
	var target := 99.0 if hot else 45.0
	cpu_temp = move_toward(cpu_temp, target, (14.0 if hot else 18.0) * delta)
	var ti := int(cpu_temp)
	if ti != _last_temp_i:
		_last_temp_i = ti
		monitor.set_temp(ti)
	if cpu_temp >= 98.5:
		power_off()
		Game.sfx.error()
		Game.msg("Bilgisayar aşırı ısınıp kapandı!", Color(1, 0.4, 0.3))
