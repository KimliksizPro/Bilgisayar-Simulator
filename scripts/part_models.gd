extends RefCounted
## Bilgisayar parçalarının prosedürel modelleri ve bilgileri.
## Her model "takılı" pozisyonda kurulur: anakart yüzeyi = yerel X=0, parça +X yönüne çıkar.

const MU := preload("res://scripts/mesh_util.gd")
const DP := preload("res://scripts/device_parts.gd")  # laptop / telefon parça modelleri

## Tür bilgisi (çarpışma kutusu): {"size": Vector3, "center": Vector3, ...}. Veri: data/parts.json "categories".
static func info(type: String) -> Dictionary:
	return DB.parts.category_info(type)


static func type_name(type: String) -> String:
	return DB.parts.type_name(type)


static func display_name(type: String, tier: int) -> String:
	var d := DB.parts.def_for(type, tier)
	return d.name if d else type


static func price(type: String, tier: int) -> int:
	var d := DB.parts.def_for(type, tier)
	return d.price if d else 0


static func ram_gb(tier: int) -> int:
	var d := DB.parts.def_for("ram", tier)
	return int(d.specs.get("gb", 0)) if d else 0


## Dönüş: {"node": Node3D, "rotors": [Node3D], "rgb": [StandardMaterial3D]}
## Model parametreleri (etiket, RGB ...) parça tanımının "model" alanından gelir.
static func build(type: String, tier: int) -> Dictionary:
	var out := {"node": Node3D.new(), "rotors": [], "rgb": []}
	var d := DB.parts.def_for(type, tier)
	var m: Dictionary = d.model if d else {"builder": type}
	match str(m.get("builder", type)):
		"cpu": _cpu(out)
		"ram": _ram(out, m)
		"gpu": _gpu(out, m)
		"psu": _psu(out, m)
		"ssd": _ssd(out, m)
		var b:  # laptop / telefon parçaları
			DP.build(out, b, m)
	MU.merge_static(out.node)
	return out


# ---------------------------------------------------------------- ortak malzemeler

static func _gold() -> Material: return MU.mat(Color(0.95, 0.75, 0.3), 1.0, 0.22)
static func _alu() -> Material: return MU.mat(Color(0.78, 0.8, 0.83), 0.9, 0.32)
static func _copper() -> Material: return MU.mat(Color(0.85, 0.48, 0.28), 1.0, 0.28)
static func _black() -> Material: return MU.mat(Color(0.05, 0.05, 0.06), 0.2, 0.5)
static func _chip() -> Material: return MU.mat(Color(0.03, 0.03, 0.035), 0.1, 0.35)


static func _text(n: Node3D, txt: String, pos: Vector3, size: int, color: Color, rot: Vector3, px := 0.0004) -> void:
	var l := MU.label(n, txt, pos, size, color, rot, px)
	l.double_sided = false


# ---------------------------------------------------------------- İŞLEMCİ + SOĞUTUCU

static func _cpu(out: Dictionary) -> void:
	var n: Node3D = out.node
	MU.box(n, Vector3(0.002, 0.045, 0.045), Vector3(0.001, 0, 0), MU.tex_mat(MU.pcb_texture(Color(0.08, 0.3, 0.14))))
	MU.rbox(n, Vector3(0.003, 0.036, 0.036), Vector3(0.0035, 0, 0), _alu(), 0.002)
	# bakır taban + ısı boruları
	MU.rbox(n, Vector3(0.006, 0.05, 0.05), Vector3(0.008, 0, 0), _copper(), 0.002)
	for y in [-0.028, -0.01, 0.01, 0.028]:
		MU.cyl(n, 0.0028, 0.04, Vector3(0.026, y, 0.0), _copper(), Vector3(0, 0, 90), 10)
		MU.sphere(n, 0.0028, Vector3(0.046, y, 0.0), _copper())
	# alüminyum kanatçıklar
	var fin := _alu()
	for i in 13:
		MU.box(n, Vector3(0.026, 0.084, 0.0012), Vector3(0.025, 0, -0.042 + i * 0.007), fin)
	MU.rbox(n, Vector3(0.003, 0.084, 0.088), Vector3(0.0395, 0, 0), _black(), 0.002)
	# fan çerçevesi (kare) + fan
	var frame := MU.mat(Color(0.1, 0.1, 0.11), 0.1, 0.6)
	var fx := 0.051
	for y in [-0.041, 0.041]:
		MU.rbox(n, Vector3(0.016, 0.008, 0.09), Vector3(fx, y, 0), frame, 0.003)
	for z in [-0.041, 0.041]:
		MU.rbox(n, Vector3(0.016, 0.09, 0.008), Vector3(fx, 0, z), frame, 0.003)
	for y in [-0.04, 0.04]:
		for z in [-0.04, 0.04]:
			MU.cyl(n, 0.0025, 0.002, Vector3(fx + 0.0085, y, z), _alu(), Vector3(0, 0, 90), 8)
	out.rotors.append(MU.fan(n, 0.037, Vector3(fx, 0, 0), Vector3(0, 0, 90), frame,
		MU.mat(Color(0.14, 0.14, 0.16), 0, 0.45), null, MU.mat(Color(0.85, 0.2, 0.15), 0, 0.4)))


# ---------------------------------------------------------------- RAM

static func _ram(out: Dictionary, m: Dictionary) -> void:
	var n: Node3D = out.node
	MU.box(n, Vector3(0.03, 0.133, 0.0014), Vector3(0.017, 0, 0), MU.tex_mat(MU.pcb_texture(Color(0.05, 0.25, 0.12)), Vector3(1, 1, 1), 0.5))
	# altın kontaklar (çentikli)
	MU.box(n, Vector3(0.004, 0.07, 0.0018), Vector3(0.003, -0.026, 0), _gold())
	MU.box(n, Vector3(0.004, 0.05, 0.0018), Vector3(0.003, 0.038, 0), _gold())
	if not m.get("rgb", false):
		# çıplak modül: görünür bellek çipleri + etiket
		for side in [-1, 1]:
			for i in 8:
				MU.box(n, Vector3(0.011, 0.011, 0.0012), Vector3(0.019, -0.054 + i * 0.0155, side * 0.0013), _chip())
		MU.box(n, Vector3(0.007, 0.06, 0.0003), Vector3(0.029, 0, 0.0021), MU.mat(Color(0.92, 0.92, 0.9), 0, 0.6))
		_text(n, m.get("label", "8GB DDR4"), Vector3(0.029, 0, 0.0024), 28, Color(0.1, 0.1, 0.1), Vector3(0, 0, 90), 0.00022)
	else:
		# soğutuculu RGB modül
		var spreader := MU.mat(Color(0.62, 0.08, 0.1), 0.75, 0.28)
		for side in [-1, 1]:
			MU.rbox(n, Vector3(0.026, 0.13, 0.0018), Vector3(0.019, 0, side * 0.0018), spreader, 0.0008)
			MU.box(n, Vector3(0.01, 0.12, 0.0004), Vector3(0.016, 0, side * 0.0029), MU.mat(Color(0.12, 0.12, 0.13), 0.6, 0.35))
		_text(n, m.get("label", "ULTRA 16GB"), Vector3(0.016, 0, 0.0032), 30, Color(0.95, 0.9, 0.9), Vector3(0, 0, 90), 0.00025)
		var rgb := MU.new_mat(Color(0.85, 0.9, 1.0), 0, 0.3, 2.0)
		MU.rbox(n, Vector3(0.005, 0.128, 0.0055), Vector3(0.0345, 0, 0), rgb, 0.0015)
		out.rgb.append(rgb)


# ---------------------------------------------------------------- EKRAN KARTI

static func _gpu(out: Dictionary, m: Dictionary) -> void:
	var n: Node3D = out.node
	var gamer: bool = m.get("gamer", false)  # oyuncu (RGB) model
	var pcb_col := Color(0.04, 0.2, 0.11) if not gamer else Color(0.05, 0.05, 0.06)
	MU.box(n, Vector3(0.1, 0.002, 0.24), Vector3(0.052, 0, 0), MU.tex_mat(MU.pcb_texture(pcb_col)))
	MU.box(n, Vector3(0.006, 0.0025, 0.07), Vector3(0.003, -0.001, -0.06), _gold())
	MU.box(n, Vector3(0.006, 0.0025, 0.012), Vector3(0.003, -0.001, -0.016), _gold())
	# arka plaka + havalandırma yarıkları
	var bp := MU.mat(Color(0.18, 0.18, 0.2), 0.8, 0.3) if not gamer else MU.mat(Color(0.08, 0.08, 0.09), 0.8, 0.3)
	MU.rbox(n, Vector3(0.1, 0.002, 0.236), Vector3(0.053, 0.0025, 0), bp, 0.001)
	for i in 6:
		MU.box(n, Vector3(0.05, 0.0004, 0.003), Vector3(0.06, 0.0037, 0.04 + i * 0.01), _black())
	_text(n, m.get("badge", "TURBO"), Vector3(0.05, 0.0038, -0.05), 60, Color(0.85, 0.85, 0.88), Vector3(-90, 0, 0), 0.0004)
	# soğutucu kanatçıkları (yandan görünür)
	var fin := _alu()
	for i in 46:
		MU.box(n, Vector3(0.092, 0.016, 0.0009), Vector3(0.053, -0.011, -0.112 + i * 0.005), fin)
	for x in [0.02, 0.05, 0.08]:
		MU.cyl(n, 0.003, 0.22, Vector3(x, -0.01, 0), _copper(), Vector3(90, 0, 0), 8)
	# koruyucu kaplama (shroud)
	var shroud := MU.mat(Color(0.3, 0.31, 0.33), 0.4, 0.45) if not gamer else MU.mat(Color(0.06, 0.06, 0.07), 0.5, 0.3)
	var accent := MU.mat(Color(0.7, 0.72, 0.75), 0.8, 0.3) if not gamer else MU.mat(Color(0.75, 0.1, 0.25), 0.6, 0.3)
	MU.rbox(n, Vector3(0.104, 0.006, 0.24), Vector3(0.053, -0.024, 0), shroud, 0.003)
	MU.rbox(n, Vector3(0.006, 0.026, 0.24), Vector3(0.104, -0.013, 0), shroud, 0.002)
	MU.rbox(n, Vector3(0.004, 0.004, 0.2), Vector3(0.107, -0.02, 0), accent, 0.0015)
	for z in [-0.115, 0.115]:
		MU.rbox(n, Vector3(0.104, 0.026, 0.006), Vector3(0.053, -0.013, z), shroud, 0.002)
	# fanlar
	var fan_count := 3 if gamer else 2
	var radius := 0.034 if gamer else 0.042
	var hub := MU.mat(Color(0.8, 0.8, 0.82), 0.6, 0.3) if not gamer else MU.mat(Color(0.75, 0.1, 0.25), 0.4, 0.3)
	for i in fan_count:
		var z := (i - (fan_count - 1) / 2.0) * (0.232 / fan_count)
		var ring: Material = null
		if gamer:
			ring = MU.new_mat(Color(1.0, 0.25, 0.6), 0, 0.3, 2.0)
			out.rgb.append(ring)
		MU.torus(n, radius * 1.02, radius * 1.1, Vector3(0.053, -0.027, z), shroud)
		out.rotors.append(MU.fan(n, radius, Vector3(0.053, -0.031, z), Vector3.ZERO, _black(), MU.mat(Color(0.12, 0.12, 0.14), 0, 0.45), ring, hub))
	if gamer:
		var rgb := MU.new_mat(Color(1.0, 0.25, 0.6), 0, 0.3, 2.5)
		MU.rbox(n, Vector3(0.002, 0.005, 0.16), Vector3(0.1075, -0.008, 0.02), rgb, 0.001)
		out.rgb.append(rgb)
	_text(n, m.get("label", "TURBO 4GB"), Vector3(0.1072, -0.014, -0.06), 40, Color(0.92, 0.92, 0.92), Vector3(0, 90, 0), 0.00045)
	# braket + görüntü çıkışları
	var bracket := MU.mat(Color(0.75, 0.76, 0.78), 0.9, 0.3)
	MU.box(n, Vector3(0.1, 0.04, 0.0015), Vector3(0.052, -0.012, -0.121), bracket)
	for i in 4:
		MU.rbox(n, Vector3(0.012, 0.006, 0.002), Vector3(0.02 + i * 0.018, -0.006, -0.122), _black(), 0.0015)
	for i in 5:
		MU.box(n, Vector3(0.008, 0.012, 0.0018), Vector3(0.025 + i * 0.016, -0.022, -0.122), _black())
	# 8-pin güç girişi
	MU.rbox(n, Vector3(0.008, 0.009, 0.02), Vector3(0.098, 0.007, 0.075), _black(), 0.0015)
	if gamer:
		MU.rbox(n, Vector3(0.008, 0.009, 0.02), Vector3(0.098, 0.007, 0.05), _black(), 0.0015)


# ---------------------------------------------------------------- GÜÇ KAYNAĞI

static func _psu(out: Dictionary, m: Dictionary) -> void:
	var n: Node3D = out.node
	var body := MU.mat(Color(0.06, 0.06, 0.07), 0.45, 0.5)
	MU.rbox(n, Vector3(0.15, 0.085, 0.15), Vector3.ZERO, body, 0.004)
	# fan ızgarası (üst)
	var grill := MU.mat(Color(0.16, 0.16, 0.18), 0.8, 0.35)
	MU.cyl(n, 0.058, 0.001, Vector3(0, 0.0426, 0), MU.mat(Color(0.02, 0.02, 0.02)), Vector3.ZERO, 24)
	for r in [0.058, 0.044, 0.03, 0.016]:
		MU.torus(n, r - 0.0015, r, Vector3(0, 0.0435, 0), grill)
	MU.box(n, Vector3(0.116, 0.0016, 0.003), Vector3(0, 0.0438, 0), grill)
	MU.box(n, Vector3(0.003, 0.0016, 0.116), Vector3(0, 0.0438, 0), grill)
	MU.cyl(n, 0.012, 0.002, Vector3(0, 0.044, 0), MU.mat(Color(0.8, 0.65, 0.2), 0.6, 0.3), Vector3.ZERO, 16)
	# yan etiket
	MU.box(n, Vector3(0.001, 0.055, 0.1), Vector3(0.0755, 0, 0), MU.mat(Color(0.88, 0.88, 0.85), 0, 0.6))
	MU.box(n, Vector3(0.0012, 0.012, 0.1), Vector3(0.0756, 0.021, 0), MU.mat(Color(0.8, 0.6, 0.15), 0, 0.5))
	_text(n, m.get("label", "550W"), Vector3(0.0763, 0.021, 0), 64, Color(0.08, 0.08, 0.08), Vector3(0, 90, 0), 0.00035)
	_text(n, "80+ BRONZ\nAC 220-240V ~ 5A\n+12V ═ 45A", Vector3(0.0763, -0.008, 0), 30, Color(0.15, 0.15, 0.15), Vector3(0, 90, 0), 0.0003)
	# arka yüz: güç soketi + anahtar + petek ızgara
	MU.rbox(n, Vector3(0.026, 0.02, 0.003), Vector3(0.04, -0.015, -0.0755), _black(), 0.002)
	for x in [0.033, 0.04, 0.047]:
		MU.box(n, Vector3(0.003, 0.006, 0.001), Vector3(x, -0.015, -0.0772), MU.mat(Color(0.15, 0.15, 0.15)))
	MU.rbox(n, Vector3(0.012, 0.016, 0.004), Vector3(0.012, -0.015, -0.076), MU.mat(Color(0.15, 0.15, 0.16), 0, 0.4), 0.002, Vector3(15, 0, 0))
	for i in 5:
		for j in 3:
			MU.cyl(n, 0.004, 0.001, Vector3(-0.055 + i * 0.011 + (j % 2) * 0.0055, 0.01 + j * 0.009, -0.0757), MU.mat(Color(0.02, 0.02, 0.02)), Vector3(90, 0, 0), 6)
	# ön yüz: modüler soketler + kablolar
	for i in 4:
		MU.rbox(n, Vector3(0.022, 0.012, 0.003), Vector3(-0.045 + i * 0.03, 0.02, 0.0755), MU.mat(Color(0.1, 0.1, 0.11)), 0.0015)
	var cable := MU.mat(Color(0.03, 0.03, 0.035), 0, 0.75)
	for i in 3:
		var x := -0.045 + i * 0.03
		MU.cyl(n, 0.005, 0.03, Vector3(x, 0.02, 0.09), cable, Vector3(90, 0, 0), 8)
		MU.sphere(n, 0.005, Vector3(x, 0.02, 0.105), cable)
		MU.cyl(n, 0.005, 0.05, Vector3(x, 0.045, 0.105), cable, Vector3.ZERO, 8)


# ---------------------------------------------------------------- SSD

static func _ssd(out: Dictionary, m: Dictionary) -> void:
	var n: Node3D = out.node
	MU.rbox(n, Vector3(0.07, 0.007, 0.1), Vector3.ZERO, MU.mat(Color(0.26, 0.27, 0.3), 0.8, 0.3), 0.002)
	MU.rbox(n, Vector3(0.062, 0.0008, 0.078), Vector3(0, 0.0036, -0.006), MU.mat(Color(0.08, 0.3, 0.75), 0, 0.45), 0.0004)
	MU.box(n, Vector3(0.062, 0.0009, 0.014), Vector3(0, 0.0037, 0.026), MU.mat(Color(0.95, 0.95, 0.95), 0, 0.5))
	_text(n, m.get("brand_text", "BİLGİ SSD"), Vector3(0, 0.0042, -0.012), 34, Color.WHITE, Vector3(-90, 0, 0), 0.00035)
	_text(n, m.get("label", "512 GB"), Vector3(0, 0.0043, 0.026), 40, Color(0.1, 0.1, 0.12), Vector3(-90, 0, 0), 0.00028)
	# SATA konnektör
	MU.box(n, Vector3(0.04, 0.004, 0.003), Vector3(-0.008, 0, 0.0505), _black())
	MU.box(n, Vector3(0.036, 0.0012, 0.0015), Vector3(-0.008, 0, 0.0515), _gold())
	# vida delikleri
	for x in [-0.0352, 0.0352]:
		for z in [-0.03, 0.03]:
			MU.cyl(n, 0.0015, 0.004, Vector3(x, 0, z), MU.mat(Color(0.02, 0.02, 0.02)), Vector3(0, 0, 90), 8)
