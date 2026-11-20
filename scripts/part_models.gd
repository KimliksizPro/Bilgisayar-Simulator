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


static func display_name_sku(sku: String) -> String:
	var d := DB.parts.get_def(sku)
	return d.name if d else sku


static func display_name(type: String, tier: int) -> String:
	var id := DB.parts.id_for(type, tier)
	return display_name_sku(id) if not id.is_empty() else type


static func price_sku(sku: String) -> int:
	var d := DB.parts.get_def(sku)
	return d.price if d else 0


static func price(type: String, tier: int) -> int:
	var id := DB.parts.id_for(type, tier)
	return price_sku(id) if not id.is_empty() else 0


static func ram_gb(tier: int) -> int:
	var d := DB.parts.def_for("ram", tier)
	return int(d.specs.get("gb", 0)) if d else 0


## Dönüş: {"node": Node3D, "rotors": [Node3D], "rgb": [StandardMaterial3D]}
## Model parametreleri (etiket, RGB ...) parça tanımının "model", "specs" ve "compat" alanlarından gelir.
static func build_sku(sku: String) -> Dictionary:
	var out := {"node": Node3D.new(), "rotors": [], "rgb": []}
	var d := DB.parts.get_def(sku)
	var cat := d.category if d else sku
	var m: Dictionary = d.model if d else {"builder": cat}
	match str(m.get("builder", cat)):
		"mobo": _mobo(out, d, m)
		"cpu": _cpu(out, d, m)
		"cooler": _cooler(out, d, m)
		"ram": _ram(out, d, m)
		"gpu": _gpu(out, d, m)
		"psu": _psu(out, d, m)
		"ssd": _ssd(out, m)
		"nvme": _nvme(out, d, m)
		"hdd": _hdd(out, d, m)
		"fan": _fan(out, m)
		"cmos": _cmos(out)
		var b:  # laptop / telefon parçaları
			DP.build(out, b, m)
	MU.merge_static(out.node)
	return out


static func build(type: String, tier: int) -> Dictionary:
	var id := DB.parts.id_for(type, tier)
	if not id.is_empty():
		return build_sku(id)
	return build_sku(type)


# ---------------------------------------------------------------- ortak malzemeler

static func _gold() -> Material: return MU.mat(Color(0.95, 0.75, 0.3), 1.0, 0.22)
static func _alu() -> Material: return MU.mat(Color(0.78, 0.8, 0.83), 0.9, 0.32)
static func _silver() -> Material: return MU.mat(Color(0.86, 0.88, 0.9), 0.95, 0.22)
static func _copper() -> Material: return MU.mat(Color(0.85, 0.48, 0.28), 1.0, 0.28)
static func _black() -> Material: return MU.mat(Color(0.05, 0.05, 0.06), 0.2, 0.5)
static func _chip() -> Material: return MU.mat(Color(0.03, 0.03, 0.035), 0.1, 0.35)
static func _dark_metal() -> Material: return MU.mat(Color(0.16, 0.17, 0.19), 0.82, 0.34)


static func _text(n: Node3D, txt: String, pos: Vector3, size: int, color: Color, rot: Vector3, px := 0.0004) -> void:
	var l := MU.label(n, txt, pos, size, color, rot, px)
	l.double_sided = false


# ---------------------------------------------------------------- ANAKART (MOBO)

static func _mobo(out: Dictionary, d: PartDef, m: Dictionary) -> void:
	var n: Node3D = out.node
	var ff := str(d.compat.get("form_factor", m.get("form_factor", "ATX"))) if d else str(m.get("form_factor", "ATX"))
	var sock := str(d.compat.get("socket", m.get("socket", "AM4"))) if d else str(m.get("socket", "AM4"))
	var ram_slots := int(d.specs.get("ram_slots", m.get("ram_slots", 2))) if d else int(m.get("ram_slots", 2))
	var m2_slots := int(d.specs.get("m2_slots", m.get("m2_slots", 1))) if d else int(m.get("m2_slots", 1))
	var sata_ports := int(d.specs.get("sata_ports", 4)) if d else 4
	var pcie_gen := int(d.specs.get("pcie_gen", 3)) if d else 3
	var debug_led := bool(d.specs.get("debug_led", m.get("debug_led", false))) if d else bool(m.get("debug_led", false))
	var brand := d.brand.to_upper() if d and not d.brand.is_empty() else "DEMİR"
	var tier := d.tier if d else 1
	# form faktörüne göre PCB boyutları (Y = yükseklik, Z = genişlik)
	var pcb_h := 0.30
	var pcb_w := 0.245
	match ff:
		"mATX":
			pcb_h = 0.244
			pcb_w = 0.244
		"ITX":
			pcb_h = 0.17
			pcb_w = 0.17
	var is_itx := ff == "ITX"
	var bx := 0.004  # anakart ön yüzeyi
	# marka/seviyeye göre PCB ve vurgu rengi
	var pcb_col := Color(0.055, 0.065, 0.08)
	var accent_col := Color(0.68, 0.7, 0.74)
	if sock == "AM5":
		pcb_col = Color(0.04, 0.04, 0.05)
		accent_col = Color(0.85, 0.18, 0.22)
	elif sock == "LGA1700":
		pcb_col = Color(0.045, 0.065, 0.105)
		accent_col = Color(0.22, 0.52, 0.88)
	elif sock == "LGA1851":
		pcb_col = Color(0.05, 0.055, 0.075)
		accent_col = Color(0.15, 0.75, 0.92)
	elif tier >= 2:
		pcb_col = Color(0.045, 0.05, 0.06)
		accent_col = Color(0.85, 0.65, 0.22)
	var accent := MU.mat(accent_col, 0.7, 0.32)
	var dark_m := _dark_metal()
	var slot_m := MU.mat(Color(0.09, 0.09, 0.1), 0.1, 0.45)
	var slot_alt := MU.mat(Color(0.24, 0.25, 0.28), 0.1, 0.45)
	# ana PCB levhası + köşe vida delikleri
	MU.box(n, Vector3(bx, pcb_h, pcb_w), Vector3(bx * 0.5, 0, 0), MU.tex_mat(MU.pcb_texture(pcb_col)))
	for sy in [-pcb_h * 0.46, pcb_h * 0.46]:
		for sz in [-pcb_w * 0.46, pcb_w * 0.46]:
			MU.cyl(n, 0.0032, bx + 0.0005, Vector3(bx * 0.5, sy, sz), _gold(), Vector3(0, 0, 90), 10)
			MU.cyl(n, 0.0018, bx + 0.0008, Vector3(bx * 0.5, sy, sz), _black(), Vector3(0, 0, 90), 8)
	# arka I/O kalkanı + port detayları
	var io_h := 0.062 if is_itx else 0.074
	var io_y := pcb_h * 0.5 - io_h * 0.5 - 0.012
	var io_z := -pcb_w * 0.5 + 0.014
	MU.rbox(n, Vector3(0.022, io_h, 0.026), Vector3(bx + 0.011, io_y, io_z), dark_m, 0.003)
	MU.box(n, Vector3(0.0015, io_h - 0.008, 0.004), Vector3(bx + 0.0222, io_y, io_z + 0.006), accent)
	_text(n, brand, Vector3(bx + 0.0226, io_y, io_z - 0.002), 34, Color(0.92, 0.92, 0.94), Vector3(0, 90, 90), 0.00028)
	for i in 3:
		MU.box(n, Vector3(0.012, 0.009, 0.002), Vector3(bx + 0.009, io_y + 0.018 - i * 0.016, -pcb_w * 0.5 - 0.0008),
			MU.mat(Color(0.12, 0.35, 0.85), 0.2, 0.4) if i < 2 else _alu())
	# CPU soketi (AM4 / AM5 / LGA1700 / LGA1851)
	var cpu_y := pcb_h * 0.5 - (0.055 if is_itx else 0.068)
	var cpu_z := -pcb_w * 0.5 + (0.066 if is_itx else 0.082)
	_mobo_socket(n, bx, cpu_y, cpu_z, sock, accent)
	# VRM soğutucuları + kondansatörler
	var vrm_len := 0.052 if is_itx else 0.068
	MU.rbox(n, Vector3(0.015, 0.016, vrm_len), Vector3(bx + 0.0075, pcb_h * 0.5 - 0.014, cpu_z), dark_m, 0.002)
	for i in 3:
		MU.box(n, Vector3(0.0156, 0.0014, vrm_len), Vector3(bx + 0.0075, pcb_h * 0.5 - 0.019 + i * 0.005, cpu_z), _alu())
	if not is_itx:
		MU.rbox(n, Vector3(0.015, 0.058, 0.018), Vector3(bx + 0.0075, cpu_y, cpu_z - 0.044), dark_m, 0.002)
		for i in 3:
			MU.box(n, Vector3(0.0156, 0.058, 0.0014), Vector3(bx + 0.0075, cpu_y, cpu_z - 0.049 + i * 0.005), _alu())
	var cap_n := 4 if is_itx else 6
	for i in cap_n:
		MU.cyl(n, 0.0026, 0.007, Vector3(bx + 0.0035, cpu_y + 0.032, cpu_z - 0.018 + i * 0.0085), _silver(), Vector3(0, 0, 90), 8)
	# RAM yuvaları (2 veya 4)
	var ram_h := 0.118 if is_itx else 0.132
	var ram_y := clampf(cpu_y - 0.006, -pcb_h * 0.5 + ram_h * 0.5 + 0.018, pcb_h * 0.5 - ram_h * 0.5 - 0.01)
	var ram_step := 0.0105 if ram_slots >= 4 else 0.013
	var ram_z0 := cpu_z + (0.046 if is_itx else 0.056)
	var latch_m := MU.mat(Color(0.62, 0.62, 0.65), 0.2, 0.45)
	for i in ram_slots:
		var rz := ram_z0 + i * ram_step
		var sm := slot_alt if (i % 2 == 1 and ram_slots >= 4) else slot_m
		MU.box(n, Vector3(0.0065, ram_h, 0.0052), Vector3(bx + 0.0032, ram_y, rz), sm)
		for ly in [ram_y - ram_h * 0.5 - 0.003, ram_y + ram_h * 0.5 + 0.003]:
			MU.box(n, Vector3(0.008, 0.005, 0.0055), Vector3(bx + 0.004, ly, rz), latch_m)
	# PCIe x16 ana yuva (PCIe 4/5'te çelik zırh)
	var pcie_y := -pcb_h * 0.5 + 0.016 if is_itx else cpu_y - 0.088
	var pcie_z := -pcb_w * 0.5 + 0.072
	MU.box(n, Vector3(0.007, 0.0065, 0.089), Vector3(bx + 0.0035, pcie_y, pcie_z), slot_m)
	if pcie_gen >= 4:
		MU.box(n, Vector3(0.0074, 0.0074, 0.087), Vector3(bx + 0.0033, pcie_y, pcie_z), _silver())
		MU.box(n, Vector3(0.0078, 0.0035, 0.084), Vector3(bx + 0.0035, pcie_y, pcie_z), _black())
	# ikincil PCIe yuvaları (ATX / mATX)
	if ff == "ATX":
		MU.box(n, Vector3(0.0065, 0.006, 0.089), Vector3(bx + 0.0032, pcie_y - 0.072, pcie_z), slot_m)
		MU.box(n, Vector3(0.0065, 0.006, 0.024), Vector3(bx + 0.0032, pcie_y - 0.036, pcie_z - 0.032), slot_m)
	elif ff == "mATX":
		MU.box(n, Vector3(0.0065, 0.006, 0.024), Vector3(bx + 0.0032, pcie_y - 0.036, pcie_z - 0.032), slot_m)
	# M.2 yuvaları (1 veya 2)
	var m2_y1 := pcie_y + (0.018 if is_itx else 0.028)
	var m2_z := cpu_z + (0.004 if is_itx else 0.012)
	_mobo_m2(n, bx, m2_y1, m2_z, tier >= 2, dark_m)
	if m2_slots >= 2 and ff == "ATX":
		_mobo_m2(n, bx, pcie_y - 0.044, m2_z, tier >= 3, dark_m)
	# yonga seti soğutucusu + marka etiketi
	if not is_itx:
		var cs_y := -pcb_h * 0.5 + 0.048
		var cs_z := pcb_w * 0.5 - 0.05
		MU.rbox(n, Vector3(0.009, 0.044, 0.044), Vector3(bx + 0.0045, cs_y, cs_z), dark_m, 0.003)
		MU.box(n, Vector3(0.0094, 0.004, 0.04), Vector3(bx + 0.0045, cs_y + 0.016, cs_z), accent)
		_text(n, "%s\n%s" % [brand, sock], Vector3(bx + 0.0094, cs_y - 0.003, cs_z), 30, Color(0.92, 0.92, 0.95), Vector3(0, 90, 0), 0.00024)
	# 24-pin güç konnektörü + SATA portları + CMOS yuvası
	var p24_z := pcb_w * 0.5 - 0.012
	var p24_y := clampf(ram_y, -pcb_h * 0.5 + 0.04, pcb_h * 0.5 - 0.045)
	MU.rbox(n, Vector3(0.01, 0.052, 0.011), Vector3(bx + 0.005, p24_y, p24_z), _black(), 0.0012)
	var sata_show := mini(sata_ports, 6)
	for i in sata_show:
		MU.rbox(n, Vector3(0.0075, 0.0055, 0.01), Vector3(bx + 0.0038, -pcb_h * 0.5 + 0.02 + i * 0.0085, pcb_w * 0.5 - 0.01),
			MU.mat(Color(0.1, 0.14, 0.32), 0.1, 0.4), 0.001)
	if not is_itx:
		MU.cyl(n, 0.0105, 0.0025, Vector3(bx + 0.0014, pcie_y - 0.02, pcb_w * 0.5 - 0.052), _black(), Vector3(0, 0, 90), 16)
		MU.cyl(n, 0.0092, 0.0028, Vector3(bx + 0.0016, pcie_y - 0.02, pcb_w * 0.5 - 0.052), _silver(), Vector3(0, 0, 90), 16)
	# isteğe bağlı hata (debug) LED şeridi
	if debug_led:
		var dy := pcb_h * 0.5 - 0.018
		var dz := pcb_w * 0.5 - 0.018
		MU.rbox(n, Vector3(0.0022, 0.032, 0.009), Vector3(bx + 0.0011, dy - 0.012, dz), _black(), 0.0008)
		var cols := [Color(0.95, 0.25, 0.15), Color(0.95, 0.72, 0.15), Color(0.95, 0.95, 0.95), Color(0.2, 0.85, 0.35)]
		for i in 4:
			MU.box(n, Vector3(0.0028, 0.0032, 0.0045), Vector3(bx + 0.0015, dy - i * 0.0075, dz), MU.mat(cols[i], 0.0, 0.3, 1.2))
		_text(n, "LED", Vector3(bx + 0.0025, dy - 0.031, dz), 20, Color(0.85, 0.85, 0.88), Vector3(0, 90, 0), 0.00018)


static func _mobo_socket(n: Node3D, bx: float, y: float, z: float, sock: String, accent: Material) -> void:
	match sock:
		"AM4":
			# AM4 PGA ZIF soket (bej delikli gövde + plastik soğutucu tırnakları)
			MU.rbox(n, Vector3(0.0035, 0.048, 0.048), Vector3(bx + 0.0018, y, z), MU.mat(Color(0.78, 0.76, 0.68), 0.15, 0.5), 0.0015)
			MU.box(n, Vector3(0.0038, 0.018, 0.018), Vector3(bx + 0.0019, y, z), MU.mat(Color(0.68, 0.66, 0.58), 0.1, 0.55))
			MU.cyl(n, 0.0012, 0.046, Vector3(bx + 0.0036, y, z + 0.028), _silver(), Vector3.ZERO, 6)
			for oy in [-0.032, 0.032]:
				MU.rbox(n, Vector3(0.0055, 0.006, 0.044), Vector3(bx + 0.0028, y + oy, z), _black(), 0.001)
		"AM5":
			# AM5 LGA soket (metalik çerçeve + altın pin yatağı + yükleme kolu)
			MU.rbox(n, Vector3(0.0032, 0.052, 0.052), Vector3(bx + 0.0016, y, z), _silver(), 0.0018)
			MU.box(n, Vector3(0.0034, 0.038, 0.038), Vector3(bx + 0.0018, y, z), _black())
			MU.box(n, Vector3(0.0036, 0.032, 0.032), Vector3(bx + 0.0019, y, z), _gold())
			MU.cyl(n, 0.0013, 0.05, Vector3(bx + 0.004, y, z + 0.03), _silver(), Vector3.ZERO, 6)
			for oy in [-0.033, 0.033]:
				MU.rbox(n, Vector3(0.005, 0.0055, 0.046), Vector3(bx + 0.0025, y + oy, z), accent, 0.001)
		_:
			# LGA1700 / LGA1851 dikdörtgen ILM mekanizması
			MU.rbox(n, Vector3(0.0035, 0.058, 0.048), Vector3(bx + 0.0018, y, z), _silver(), 0.0018)
			MU.box(n, Vector3(0.0037, 0.044, 0.034), Vector3(bx + 0.0019, y, z), _black())
			MU.box(n, Vector3(0.0039, 0.038, 0.028), Vector3(bx + 0.002, y, z), _gold())
			MU.cyl(n, 0.0013, 0.054, Vector3(bx + 0.0042, y, z + 0.028), _silver(), Vector3.ZERO, 6)
			MU.box(n, Vector3(0.0045, 0.004, 0.036), Vector3(bx + 0.0024, y + 0.031, z), accent)


static func _mobo_m2(n: Node3D, bx: float, y: float, z: float, shield: bool, dark_m: Material) -> void:
	# M.2 konnektör ucu (-Z) + vida direği (+Z)
	MU.box(n, Vector3(0.0045, 0.02, 0.006), Vector3(bx + 0.0022, y, z - 0.036), _black())
	MU.cyl(n, 0.0024, 0.004, Vector3(bx + 0.002, y, z + 0.038), _silver(), Vector3(0, 0, 90), 8)
	if shield:
		MU.rbox(n, Vector3(0.0045, 0.021, 0.072), Vector3(bx + 0.0028, y, z + 0.002), dark_m, 0.0012)
		_text(n, "M.2", Vector3(bx + 0.0054, y, z + 0.012), 28, Color(0.8, 0.82, 0.86), Vector3(0, 90, 0), 0.00024)
	else:
		MU.box(n, Vector3(0.0006, 0.019, 0.068), Vector3(bx + 0.0005, y, z + 0.002), MU.mat(Color(0.14, 0.15, 0.17), 0.1, 0.6))


# ---------------------------------------------------------------- ÇIPLAK İŞLEMCİ (CPU)

static func _cpu(out: Dictionary, d: PartDef, m: Dictionary) -> void:
	var n: Node3D = out.node
	var sock := str(d.compat.get("socket", m.get("socket", "AM4"))) if d else str(m.get("socket", "AM4"))
	var label := str(m.get("label", "KAPLAN 6C"))
	var is_lga := sock.begins_with("LGA")
	var is_am5 := sock == "AM5"
	# PCB boyutları ve rengi sokete göre değişir
	var pcb_h := 0.048 if is_lga else 0.044
	var pcb_w := 0.040 if is_lga else 0.044
	var pcb_col := Color(0.06, 0.28, 0.13)
	var accent_col := Color(0.92, 0.34, 0.12)
	match sock:
		"AM5":
			pcb_col = Color(0.04, 0.24, 0.17)
			accent_col = Color(0.96, 0.48, 0.1)
		"LGA1700":
			pcb_col = Color(0.05, 0.17, 0.32)
			accent_col = Color(0.16, 0.54, 0.94)
		"LGA1851":
			pcb_col = Color(0.04, 0.13, 0.26)
			accent_col = Color(0.12, 0.78, 0.96)
	# arka yüz altın pin / kontak pedi + PCB alt tabaka
	MU.box(n, Vector3(0.0008, pcb_h - 0.004, pcb_w - 0.004), Vector3(0.0004, 0, 0), _gold())
	MU.box(n, Vector3(0.0024, pcb_h, pcb_w), Vector3(0.002, 0, 0), MU.tex_mat(MU.pcb_texture(pcb_col)))
	# köşe hizalama üçgeni (altın)
	MU.box(n, Vector3(0.0026, 0.004, 0.004), Vector3(0.0021, -pcb_h * 0.5 + 0.003, -pcb_w * 0.5 + 0.003), _gold())
	# metal IHS ısı yayıcı
	var ihs_m := _silver()
	if is_am5:
		# AM5 ikonik çentikli (ahtapot) IHS
		MU.rbox(n, Vector3(0.0034, 0.032, 0.032), Vector3(0.0048, 0, 0), ihs_m, 0.0014)
		MU.rbox(n, Vector3(0.0032, 0.038, 0.016), Vector3(0.0047, 0, 0), ihs_m, 0.0012)
		MU.rbox(n, Vector3(0.0032, 0.016, 0.038), Vector3(0.0047, 0, 0), ihs_m, 0.0012)
		# köşelerdeki SMD kapasitörler
		for sy in [-0.0155, 0.0155]:
			for sz in [-0.0155, 0.0155]:
				MU.box(n, Vector3(0.0012, 0.0026, 0.0018), Vector3(0.0037, sy, sz), _gold())
	elif is_lga:
		# LGA1700 / LGA1851 dikdörtgen basamaklı IHS
		MU.rbox(n, Vector3(0.0016, 0.043, 0.035), Vector3(0.0038, 0, 0), _alu(), 0.001)
		MU.rbox(n, Vector3(0.0032, 0.038, 0.030), Vector3(0.0050, 0, 0), ihs_m, 0.0014)
	else:
		# AM4 klasik kare IHS
		MU.rbox(n, Vector3(0.0034, 0.036, 0.036), Vector3(0.0048, 0, 0), ihs_m, 0.0015)
	# marka/soket vurgu şeridi + lazer baskı yazı
	var top_x := 0.0067
	MU.box(n, Vector3(0.0005, 0.0028, 0.024), Vector3(top_x, 0.012, 0), MU.mat(accent_col, 0.4, 0.35))
	_text(n, label, Vector3(top_x + 0.0003, 0.002, 0), 26, Color(0.16, 0.17, 0.2), Vector3(0, 90, 0), 0.00018)
	_text(n, sock, Vector3(top_x + 0.0003, -0.007, 0), 22, Color(0.28, 0.3, 0.34), Vector3(0, 90, 0), 0.00017)


# ---------------------------------------------------------------- CPU SOĞUTUCU (COOLER)

static func _cooler(out: Dictionary, d: PartDef, m: Dictionary) -> void:
	var style := str(m.get("style", "stock"))
	match style:
		"tower": _cooler_tower(out)
		"aio": _cooler_aio(out, bool(m.get("rgb", true)))
		_: _cooler_stock(out)


static func _cooler_stock(out: Dictionary) -> void:
	var n: Node3D = out.node
	# bakır çekirdek + montaj ayakları
	MU.cyl(n, 0.018, 0.008, Vector3(0.004, 0, 0), _copper(), Vector3(0, 0, 90), 16)
	var mount := _dark_metal()
	for sy in [-0.034, 0.034]:
		for sz in [-0.034, 0.034]:
			MU.box(n, Vector3(0.004, 0.01, 0.01), Vector3(0.005, sy, sz), mount)
			MU.cyl(n, 0.0025, 0.009, Vector3(0.007, sy, sz), _alu(), Vector3(0, 0, 90), 8)
	# dairesel alüminyum radyal kanatçıklar
	var fin_m := _alu()
	MU.cyl(n, 0.016, 0.024, Vector3(0.018, 0, 0), fin_m, Vector3(0, 0, 90), 14)
	for i in 16:
		var ang := TAU * i / 16.0
		var piv := Node3D.new()
		piv.position = Vector3(0.018, 0, 0)
		piv.rotation.x = ang
		n.add_child(piv)
		MU.box(piv, Vector3(0.022, 0.024, 0.0014), Vector3(0, 0.026, 0), fin_m)
	# siyah dairesel çerçeve + üstten üfleyen fan
	var frame := MU.mat(Color(0.09, 0.09, 0.1), 0.15, 0.55)
	MU.torus(n, 0.036, 0.042, Vector3(0.036, 0, 0), frame, Vector3(0, 0, 90))
	out.rotors.append(MU.fan(n, 0.036, Vector3(0.036, 0, 0), Vector3(0, 0, 90), frame,
		MU.mat(Color(0.15, 0.15, 0.17), 0, 0.45), null, MU.mat(Color(0.85, 0.28, 0.16), 0.3, 0.4)))


static func _cooler_tower(out: Dictionary) -> void:
	var n: Node3D = out.node
	# bakır soğuk plaka + 4 adet ısı borusu
	MU.rbox(n, Vector3(0.008, 0.046, 0.046), Vector3(0.004, 0, 0), _copper(), 0.002)
	for y in [-0.026, -0.009, 0.009, 0.026]:
		MU.cyl(n, 0.0028, 0.092, Vector3(0.052, y, 0.0), _copper(), Vector3(0, 0, 90), 10)
		MU.sphere(n, 0.003, Vector3(0.099, y, 0.0), _copper())
	# uzun alüminyum kanatçık kulesi
	var fin_m := _alu()
	for i in 18:
		MU.box(n, Vector3(0.0014, 0.094, 0.070), Vector3(0.02 + i * 0.0043, 0, 0), fin_m)
	# mat siyah üst kapak + marka şeridi
	MU.rbox(n, Vector3(0.004, 0.096, 0.072), Vector3(0.0965, 0, 0), _dark_metal(), 0.002)
	_text(n, "RÜZGAR", Vector3(0.099, 0, 0), 34, Color(0.88, 0.9, 0.94), Vector3(0, 90, 0), 0.00028)
	# yan fan (+Z yüzünde, soğutucudan geriye hava iter)
	var frame := MU.mat(Color(0.09, 0.09, 0.1), 0.1, 0.55)
	var fz := 0.045
	for y in [-0.043, 0.043]:
		MU.rbox(n, Vector3(0.074, 0.007, 0.018), Vector3(0.056, y, fz), frame, 0.002)
	for x in [0.02, 0.092]:
		MU.rbox(n, Vector3(0.007, 0.092, 0.018), Vector3(x, 0, fz), frame, 0.002)
	out.rotors.append(MU.fan(n, 0.036, Vector3(0.056, 0, fz), Vector3(90, 0, 0), frame,
		MU.mat(Color(0.14, 0.14, 0.16), 0, 0.45), null, MU.mat(Color(0.82, 0.84, 0.88), 0.6, 0.3)))


static func _cooler_aio(out: Dictionary, has_rgb: bool) -> void:
	var n: Node3D = out.node
	# pompa bloğu (CPU üzerinde)
	MU.rbox(n, Vector3(0.006, 0.05, 0.05), Vector3(0.003, 0, 0), _copper(), 0.002)
	var pump_m := MU.mat(Color(0.07, 0.075, 0.085), 0.45, 0.32)
	MU.cyl(n, 0.032, 0.038, Vector3(0.025, 0, 0), pump_m, Vector3(0, 0, 90), 20)
	MU.cyl(n, 0.029, 0.004, Vector3(0.045, 0, 0), MU.mat(Color(0.02, 0.02, 0.03), 0.9, 0.12), Vector3(0, 0, 90), 20)
	if has_rgb:
		var prgb := MU.new_mat(Color(0.25, 0.78, 1.0), 0, 0.25, 2.2)
		MU.torus(n, 0.022, 0.026, Vector3(0.0465, 0, 0), prgb, Vector3(0, 0, 90))
		out.rgb.append(prgb)
	_text(n, "AIO\n240", Vector3(0.0475, 0, 0), 26, Color(0.85, 0.92, 1.0), Vector3(0, 90, 0), 0.00022)
	# 240mm çift fanlı radyatör (üstte konumlanmış)
	var rad_x := 0.034
	var rad_y := 0.084
	var rad_z := 0.022
	var rad_m := MU.mat(Color(0.08, 0.08, 0.09), 0.5, 0.45)
	MU.rbox(n, Vector3(0.088, 0.022, 0.196), Vector3(rad_x, rad_y, rad_z), rad_m, 0.003)
	for i in 14:
		MU.box(n, Vector3(0.082, 0.023, 0.0018), Vector3(rad_x, rad_y, rad_z - 0.078 + i * 0.012), _dark_metal())
	# radyatör altı 2 adet 90mm fan
	var frame := MU.mat(Color(0.09, 0.09, 0.1), 0.1, 0.55)
	var blade := MU.mat(Color(0.14, 0.14, 0.16), 0, 0.45)
	for fz in [rad_z - 0.046, rad_z + 0.046]:
		var ring: Material = null
		if has_rgb:
			ring = MU.new_mat(Color(0.25, 0.78, 1.0), 0, 0.3, 2.0)
			out.rgb.append(ring)
		out.rotors.append(MU.fan(n, 0.038, Vector3(rad_x, rad_y - 0.017, fz), Vector3.ZERO, frame, blade, ring, _alu()))
	# örgülü sıvı soğutma hortumları (pompadan radyatöre)
	var tube_m := MU.mat(Color(0.09, 0.095, 0.105), 0.1, 0.75)
	for idx in 2:
		var ox := -0.008 if idx == 0 else 0.008
		var oz := 0.014 if idx == 0 else 0.028
		var pts: Array[Vector3] = [
			Vector3(0.024 + ox * 0.5, 0.022, oz),
			Vector3(0.048 + ox, 0.038, oz + 0.048),
			Vector3(0.052 + ox, 0.064, rad_z + 0.082),
			Vector3(rad_x + ox, rad_y - 0.006, rad_z + 0.092),
		]
		MU.tube(n, pts, 0.0052, tube_m, 7)
		MU.cyl(n, 0.0066, 0.008, pts[0], _alu(), Vector3(90, 0, 0), 8)
		MU.cyl(n, 0.0066, 0.008, pts[3], _alu(), Vector3.ZERO, 8)


# ---------------------------------------------------------------- RAM (DDR4 / DDR5)

static func _ram(out: Dictionary, d: PartDef, m: Dictionary) -> void:
	var n: Node3D = out.node
	var ddr := int(m.get("ddr", 4))
	if d and str(d.compat.get("ram_type", "")) == "DDR5":
		ddr = 5
	var is_rgb := bool(m.get("rgb", false))
	var gb := int(d.specs.get("gb", 8)) if d else 8
	var bare := not is_rgb and ddr == 4 and gb <= 8
	var pcb_col := Color(0.05, 0.25, 0.12) if bare else Color(0.05, 0.055, 0.065)
	MU.box(n, Vector3(0.03, 0.132, 0.0014), Vector3(0.017, 0, 0), MU.tex_mat(MU.pcb_texture(pcb_col), Vector3(1, 1, 1), 0.5))
	# altın kontaklar: DDR4 ve DDR5 çentik konumu gözle görülür biçimde kaydırılmış
	if ddr == 5:
		# DDR5 çentiği -Y tarafına kayık (y = -0.008)
		MU.box(n, Vector3(0.004, 0.053, 0.0018), Vector3(0.003, -0.0375, 0), _gold())
		MU.box(n, Vector3(0.004, 0.069, 0.0018), Vector3(0.003, 0.0295, 0), _gold())
		MU.box(n, Vector3(0.0046, 0.0045, 0.002), Vector3(0.0028, -0.008, 0), _black())
	else:
		# DDR4 çentiği +Y tarafına kayık (y = +0.011)
		MU.box(n, Vector3(0.004, 0.072, 0.0018), Vector3(0.003, -0.028, 0), _gold())
		MU.box(n, Vector3(0.004, 0.050, 0.0018), Vector3(0.003, 0.039, 0), _gold())
		MU.box(n, Vector3(0.0046, 0.0045, 0.002), Vector3(0.0028, 0.011, 0), _black())
	if bare:
		# çıplak giriş seviyesi modül: görünür bellek çipleri + etiket
		for side in [-1, 1]:
			for i in 8:
				MU.box(n, Vector3(0.011, 0.011, 0.0012), Vector3(0.019, -0.054 + i * 0.0155, side * 0.0013), _chip())
		MU.box(n, Vector3(0.007, 0.06, 0.0003), Vector3(0.029, 0, 0.0021), MU.mat(Color(0.92, 0.92, 0.9), 0, 0.6))
		_text(n, m.get("label", "8GB DDR4"), Vector3(0.029, 0, 0.0024), 28, Color(0.1, 0.1, 0.1), Vector3(0, 0, 90), 0.00022)
	else:
		# soğutuculu modül (DDR4 32GB / DDR5 / RGB)
		var sp_col := Color(0.15, 0.16, 0.19)
		if is_rgb:
			sp_col = Color(0.11, 0.12, 0.15) if ddr == 5 else Color(0.62, 0.08, 0.1)
		elif ddr == 5:
			sp_col = Color(0.12, 0.18, 0.28)
		var spreader := MU.mat(sp_col, 0.78, 0.28)
		var trim := MU.mat(Color(0.75, 0.78, 0.84), 0.85, 0.25) if ddr == 5 else MU.mat(Color(0.12, 0.12, 0.13), 0.6, 0.35)
		for side in [-1, 1]:
			MU.rbox(n, Vector3(0.026, 0.13, 0.0018), Vector3(0.019, 0, side * 0.0018), spreader, 0.0008)
			MU.box(n, Vector3(0.009, 0.12, 0.0004), Vector3(0.016, 0, side * 0.0029), trim)
		_text(n, m.get("label", "16GB DDR5"), Vector3(0.016, 0, 0.0033), 28,
			Color(0.1, 0.1, 0.12) if ddr == 5 else Color(0.95, 0.9, 0.9), Vector3(0, 0, 90), 0.00024)
		if is_rgb:
			var rgb := MU.new_mat(Color(0.85, 0.9, 1.0), 0, 0.3, 2.0)
			MU.rbox(n, Vector3(0.0055, 0.128, 0.0056), Vector3(0.0345, 0, 0), rgb, 0.0015)
			out.rgb.append(rgb)
		else:
			MU.rbox(n, Vector3(0.003, 0.128, 0.0052), Vector3(0.0332, 0, 0), _dark_metal(), 0.001)


# ---------------------------------------------------------------- EKRAN KARTI (GPU)

static func _gpu(out: Dictionary, d: PartDef, m: Dictionary) -> void:
	var n: Node3D = out.node
	var gamer: bool = bool(m.get("gamer", false))
	var len_mm := float(d.specs.get("length_mm", m.get("length_mm", 240))) if d else float(m.get("length_mm", 240))
	var z_len := clampf(len_mm / 1000.0, 0.18, 0.33)
	var z_rear := -0.12  # arka braket her uzunlukta PCIe yuvasıyla hizalı kalır
	var z_mid := z_rear + z_len * 0.5
	var z_front := z_rear + z_len
	var pins: Array = d.compat.get("pcie_pins", []) if d else []
	var has_12v := bool(m.get("pcie_12vhpwr", false)) or pins.has("12vhpwr")
	var has_8pin := pins.has("8pin")
	var flagship := has_12v or len_mm >= 300.0
	var pcb_col := Color(0.04, 0.2, 0.11) if not gamer else Color(0.05, 0.05, 0.06)
	MU.box(n, Vector3(0.1, 0.002, z_len), Vector3(0.052, 0, z_mid), MU.tex_mat(MU.pcb_texture(pcb_col)))
	# PCIe x16 altın kontakları (arka brakete göre sabit konumda)
	MU.box(n, Vector3(0.006, 0.0025, 0.07), Vector3(0.003, -0.001, z_rear + 0.06), _gold())
	MU.box(n, Vector3(0.006, 0.0025, 0.012), Vector3(0.003, -0.001, z_rear + 0.104), _gold())
	# arka plaka + havalandırma yarıkları
	var bp := MU.mat(Color(0.18, 0.18, 0.2), 0.8, 0.3) if not gamer else MU.mat(Color(0.08, 0.08, 0.09), 0.8, 0.3)
	MU.rbox(n, Vector3(0.1, 0.002, z_len - 0.004), Vector3(0.053, 0.0025, z_mid), bp, 0.001)
	var vent_n := maxi(4, int(z_len * 24.0))
	for i in vent_n:
		var vz := z_mid + 0.015 + i * 0.01
		if vz < z_front - 0.014:
			MU.box(n, Vector3(0.05, 0.0004, 0.003), Vector3(0.06, 0.0037, vz), _black())
	_text(n, m.get("badge", "TURBO"), Vector3(0.05, 0.0038, z_rear + 0.065), 60,
		Color(0.95, 0.8, 0.35) if flagship else Color(0.85, 0.85, 0.88), Vector3(-90, 0, 0), 0.0004)
	# soğutucu kanatçıkları + bakır ısı boruları
	var fin := _alu()
	var fin_n := int((z_len - 0.016) / 0.0052)
	var fin_h := 0.021 if flagship else 0.016
	var shroud_y := -0.029 if flagship else -0.024
	for i in fin_n:
		MU.box(n, Vector3(0.092, fin_h, 0.0009), Vector3(0.053, -0.003 - fin_h * 0.5, z_rear + 0.008 + i * 0.0052), fin)
	for x in [0.02, 0.05, 0.08]:
		MU.cyl(n, 0.003, z_len - 0.02, Vector3(x, -0.011, z_mid), _copper(), Vector3(90, 0, 0), 8)
	# koruyucu kaplama (shroud)
	var shroud := MU.mat(Color(0.3, 0.31, 0.33), 0.4, 0.45) if not gamer else MU.mat(Color(0.06, 0.06, 0.07), 0.5, 0.3)
	var accent_col := Color(0.7, 0.72, 0.75) if not gamer else (Color(0.92, 0.72, 0.2) if flagship else Color(0.75, 0.1, 0.25))
	var accent := MU.mat(accent_col, 0.7, 0.3)
	var side_h := 0.031 if flagship else 0.026
	var side_y := -0.0155 if flagship else -0.013
	MU.rbox(n, Vector3(0.104, 0.006, z_len), Vector3(0.053, shroud_y, z_mid), shroud, 0.003)
	MU.rbox(n, Vector3(0.006, side_h, z_len), Vector3(0.104, side_y, z_mid), shroud, 0.002)
	MU.rbox(n, Vector3(0.004, 0.004, z_len - 0.036), Vector3(0.107, shroud_y + 0.004, z_mid), accent, 0.0015)
	for z in [z_rear + 0.004, z_front - 0.004]:
		MU.rbox(n, Vector3(0.104, side_h, 0.006), Vector3(0.053, side_y, z), shroud, 0.002)
	# fanlar: uzunluğa göre 1 / 2 / 3 adet
	var fan_count := 1 if len_mm <= 215.0 else (2 if len_mm <= 255.0 else 3)
	var radius := minf(0.043, (z_len - 0.02) / (fan_count * 2.25))
	var hub := MU.mat(accent_col, 0.5, 0.3) if gamer else MU.mat(Color(0.8, 0.8, 0.82), 0.6, 0.3)
	for i in fan_count:
		var fz := z_mid + (i - (fan_count - 1) / 2.0) * ((z_len - 0.016) / fan_count)
		var ring: Material = null
		if gamer:
			ring = MU.new_mat(Color(1.0, 0.25, 0.6), 0, 0.3, 2.0)
			out.rgb.append(ring)
		MU.torus(n, radius * 1.02, radius * 1.1, Vector3(0.053, shroud_y - 0.003, fz), shroud)
		out.rotors.append(MU.fan(n, radius, Vector3(0.053, shroud_y - 0.007, fz), Vector3.ZERO, _black(),
			MU.mat(Color(0.12, 0.12, 0.14), 0, 0.45), ring, hub))
	if gamer:
		var rgb := MU.new_mat(Color(1.0, 0.25, 0.6), 0, 0.3, 2.5)
		MU.rbox(n, Vector3(0.002, 0.005, z_len * 0.62), Vector3(0.1075, -0.008, z_mid + 0.02), rgb, 0.001)
		out.rgb.append(rgb)
	_text(n, m.get("label", "TURBO 4GB"), Vector3(0.1072, side_y, z_rear + 0.065), 38, Color(0.92, 0.92, 0.92), Vector3(0, 90, 0), 0.00042)
	# arka braket + görüntü çıkışları
	var bracket := MU.mat(Color(0.75, 0.76, 0.78), 0.9, 0.3)
	MU.box(n, Vector3(0.1, 0.04, 0.0015), Vector3(0.052, -0.012, z_rear - 0.001), bracket)
	for i in 4:
		MU.rbox(n, Vector3(0.012, 0.006, 0.002), Vector3(0.02 + i * 0.018, -0.006, z_rear - 0.002), _black(), 0.0015)
	for i in 5:
		MU.box(n, Vector3(0.008, 0.012, 0.0018), Vector3(0.025 + i * 0.016, -0.022, z_rear - 0.002), _black())
	# güç girişi: slot beslemeli (yok) / 8-pin / 12VHPWR
	var pz := z_front - 0.042
	if has_12v:
		MU.rbox(n, Vector3(0.009, 0.0085, 0.017), Vector3(0.098, 0.007, pz), _black(), 0.0012)
		MU.box(n, Vector3(0.0096, 0.005, 0.013), Vector3(0.098, 0.0072, pz), MU.mat(Color(0.95, 0.78, 0.12), 0.3, 0.4))
		_text(n, "12VHPWR", Vector3(0.103, 0.007, pz), 18, Color(0.95, 0.85, 0.3), Vector3(0, 90, 0), 0.00018)
	elif has_8pin:
		MU.rbox(n, Vector3(0.008, 0.009, 0.02), Vector3(0.098, 0.007, pz), _black(), 0.0015)
		for i in 4:
			MU.box(n, Vector3(0.0086, 0.0055, 0.0032), Vector3(0.098, 0.0072, pz - 0.0065 + i * 0.0044), MU.mat(Color(0.22, 0.22, 0.24)))


# ---------------------------------------------------------------- GÜÇ KAYNAĞI (PSU)

static func _psu(out: Dictionary, d: PartDef, m: Dictionary) -> void:
	var n: Node3D = out.node
	var watts := int(d.specs.get("watts", 550)) if d else 550
	var eff := str(m.get("eff", d.specs.get("efficiency", "80+ Bronz") if d else "80+ Bronz")).to_upper()
	var conns: Dictionary = d.compat.get("connectors", {}) if d else {}
	var has_12v := int(conns.get("12vhpwr", 0)) > 0
	# verimlilik sınıfına göre şerit ve göbek rengi
	var stripe_col := Color(0.8, 0.56, 0.2)  # 80+ Bronz
	var body_col := Color(0.06, 0.06, 0.07)
	if watts <= 450:
		stripe_col = Color(0.84, 0.86, 0.9)  # 80+ Beyaz
	elif watts >= 1000:
		stripe_col = Color(0.74, 0.84, 0.96)  # 80+ Platin
		body_col = Color(0.075, 0.08, 0.095)
	elif watts >= 750:
		stripe_col = Color(0.94, 0.74, 0.16)  # 80+ Altın
	var body := MU.mat(body_col, 0.45, 0.5)
	var stripe_m := MU.mat(stripe_col, 0.5, 0.35)
	MU.rbox(n, Vector3(0.15, 0.085, 0.15), Vector3.ZERO, body, 0.004)
	# fan ızgarası (üst)
	var grill := MU.mat(Color(0.16, 0.16, 0.18), 0.8, 0.35)
	MU.cyl(n, 0.058, 0.001, Vector3(0, 0.0426, 0), MU.mat(Color(0.02, 0.02, 0.02)), Vector3.ZERO, 24)
	for r in [0.058, 0.044, 0.03, 0.016]:
		MU.torus(n, r - 0.0015, r, Vector3(0, 0.0435, 0), grill)
	MU.box(n, Vector3(0.116, 0.0016, 0.003), Vector3(0, 0.0438, 0), grill)
	MU.box(n, Vector3(0.003, 0.0016, 0.116), Vector3(0, 0.0438, 0), grill)
	MU.cyl(n, 0.012, 0.002, Vector3(0, 0.044, 0), stripe_m, Vector3.ZERO, 16)
	# yan etiket + watt şeridi
	var amps := int(round(watts * 0.96 / 12.0))
	MU.box(n, Vector3(0.001, 0.055, 0.104), Vector3(0.0755, 0, 0), MU.mat(Color(0.88, 0.88, 0.85), 0, 0.6))
	MU.box(n, Vector3(0.0012, 0.014, 0.104), Vector3(0.0756, 0.0205, 0), stripe_m)
	_text(n, m.get("label", "%dW" % watts), Vector3(0.0763, 0.0205, 0), 64, Color(0.08, 0.08, 0.08), Vector3(0, 90, 0), 0.00035)
	_text(n, "%s\nAC 220-240V ~ 5A\n+12V ═ %dA" % [eff, amps], Vector3(0.0763, -0.008, 0), 28, Color(0.15, 0.15, 0.15), Vector3(0, 90, 0), 0.00028)
	# arka yüz: güç soketi + anahtar + petek ızgara
	MU.rbox(n, Vector3(0.026, 0.02, 0.003), Vector3(0.04, -0.015, -0.0755), _black(), 0.002)
	for x in [0.033, 0.04, 0.047]:
		MU.box(n, Vector3(0.003, 0.006, 0.001), Vector3(x, -0.015, -0.0772), MU.mat(Color(0.15, 0.15, 0.15)))
	MU.rbox(n, Vector3(0.012, 0.016, 0.004), Vector3(0.012, -0.015, -0.076), MU.mat(Color(0.15, 0.15, 0.16), 0, 0.4), 0.002, Vector3(15, 0, 0))
	for i in 5:
		for j in 3:
			MU.cyl(n, 0.004, 0.001, Vector3(-0.055 + i * 0.011 + (j % 2) * 0.0055, 0.01 + j * 0.009, -0.0757), MU.mat(Color(0.02, 0.02, 0.02)), Vector3(90, 0, 0), 6)
	# ön yüz: modüler soketler + kablolar
	var port_n := 5 if watts >= 1000 else (4 if watts >= 750 else 3)
	for i in port_n:
		var px := -0.05 + i * (0.1 / maxf(port_n - 1, 1))
		var pm := MU.mat(Color(0.92, 0.72, 0.15), 0.2, 0.4) if (has_12v and i == port_n - 1) else MU.mat(Color(0.1, 0.1, 0.11))
		MU.rbox(n, Vector3(0.018, 0.012, 0.003), Vector3(px, 0.02, 0.0755), pm, 0.0015)
	var cable := MU.mat(Color(0.03, 0.03, 0.035), 0, 0.75)
	for i in 3:
		var x := -0.045 + i * 0.03
		MU.cyl(n, 0.005, 0.03, Vector3(x, 0.02, 0.09), cable, Vector3(90, 0, 0), 8)
		MU.sphere(n, 0.005, Vector3(x, 0.02, 0.105), cable)
		MU.cyl(n, 0.005, 0.05, Vector3(x, 0.045, 0.105), cable, Vector3.ZERO, 8)


# ---------------------------------------------------------------- 2.5" SATA SSD

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


# ---------------------------------------------------------------- M.2 NVMe SSD (2280)

static func _nvme(out: Dictionary, d: PartDef, m: Dictionary) -> void:
	var n: Node3D = out.node
	var has_hs := bool(m.get("heatsink", false))
	var label := str(m.get("label", "NVMe 512 GB"))
	# 2280 PCB: kalınlık X, genişlik Y (22mm), uzunluk Z (80mm)
	MU.box(n, Vector3(0.0012, 0.022, 0.08), Vector3(0.0008, 0, 0), MU.tex_mat(MU.pcb_texture(Color(0.045, 0.05, 0.065)), Vector3(1, 1, 1), 0.5))
	# M-key altın kenar konnektörü (-Z ucu) + vida yarımı (+Z ucu)
	MU.box(n, Vector3(0.0015, 0.017, 0.0042), Vector3(0.0008, 0.0015, -0.038), _gold())
	MU.box(n, Vector3(0.0017, 0.0022, 0.0046), Vector3(0.0008, -0.0055, -0.0378), _black())
	MU.cyl(n, 0.0026, 0.0015, Vector3(0.0008, 0, 0.039), _gold(), Vector3(0, 0, 90), 10)
	# denetleyici + NAND bellek yongaları
	MU.rbox(n, Vector3(0.0014, 0.011, 0.011), Vector3(0.002, 0, -0.022), _alu(), 0.0004)
	for z in [-0.002, 0.018]:
		MU.rbox(n, Vector3(0.0014, 0.014, 0.016), Vector3(0.002, 0, z), _chip(), 0.0004)
	if has_hs:
		# Pro model: oluklu alüminyum soğutucu blok + altın şerit
		MU.rbox(n, Vector3(0.0034, 0.021, 0.064), Vector3(0.0033, 0, 0.003), _dark_metal(), 0.0008)
		for y in [-0.007, 0.007]:
			MU.box(n, Vector3(0.0006, 0.0016, 0.06), Vector3(0.0051, y, 0.003), _gold())
		_text(n, label, Vector3(0.0053, 0, 0.004), 24, Color(0.95, 0.92, 0.82), Vector3(0, 90, 0), 0.00018)
	else:
		# standart model: mavi etiket
		MU.box(n, Vector3(0.0004, 0.017, 0.052), Vector3(0.0029, 0, 0.005), MU.mat(Color(0.1, 0.34, 0.82), 0, 0.45))
		_text(n, label, Vector3(0.0033, 0, 0.005), 24, Color.WHITE, Vector3(0, 90, 0), 0.00018)


# ---------------------------------------------------------------- 3.5" SABİT DİSK (HDD)

static func _hdd(out: Dictionary, d: PartDef, m: Dictionary) -> void:
	var n: Node3D = out.node
	var label := str(m.get("label", "1 TB 7200 RPM"))
	# döküm siyah gövde + fırçalanmış alüminyum üst kapak
	MU.rbox(n, Vector3(0.101, 0.021, 0.146), Vector3(0, -0.002, 0), _dark_metal(), 0.003)
	MU.rbox(n, Vector3(0.098, 0.0045, 0.142), Vector3(0, 0.0102, 0), _silver(), 0.0015)
	# üst kapakta mil izi + 6 köşe vidası
	MU.torus(n, 0.014, 0.016, Vector3(0, 0.0126, -0.016), _alu())
	for x in [-0.044, 0.044]:
		for z in [-0.062, 0.0, 0.062]:
			MU.cyl(n, 0.0022, 0.001, Vector3(x, 0.0127, z), _dark_metal(), Vector3.ZERO, 8)
	# üst etiket
	MU.box(n, Vector3(0.076, 0.0005, 0.088), Vector3(0, 0.0127, 0.008), MU.mat(Color(0.94, 0.94, 0.92), 0, 0.55))
	MU.box(n, Vector3(0.076, 0.0006, 0.018), Vector3(0, 0.0128, -0.027), MU.mat(Color(0.08, 0.42, 0.56), 0, 0.45))
	_text(n, "BİLGİ HDD", Vector3(0, 0.0133, -0.027), 34, Color.WHITE, Vector3(-90, 0, 0), 0.0003)
	_text(n, label + "\nSATA III 6Gb/s", Vector3(0, 0.0133, 0.012), 28, Color(0.12, 0.12, 0.14), Vector3(-90, 0, 0), 0.00028)
	# alt yüz: görünür yeşil kontrol PCB'si + yongalar + motor göbeği
	MU.box(n, Vector3(0.084, 0.0018, 0.072), Vector3(0, -0.0126, 0.028), MU.tex_mat(MU.pcb_texture(Color(0.04, 0.28, 0.16))))
	MU.box(n, Vector3(0.018, 0.0014, 0.018), Vector3(-0.012, -0.0138, 0.026), _chip())
	MU.box(n, Vector3(0.014, 0.0014, 0.01), Vector3(0.018, -0.0138, 0.032), _chip())
	MU.cyl(n, 0.022, 0.0016, Vector3(0, -0.0126, -0.028), _alu(), Vector3.ZERO, 18)
	# SATA veri + güç konnektörü (+Z kenarı)
	MU.box(n, Vector3(0.048, 0.006, 0.005), Vector3(-0.012, -0.008, 0.0735), _black())
	MU.box(n, Vector3(0.042, 0.0016, 0.002), Vector3(-0.012, -0.008, 0.0752), _gold())
	# yan montaj vida delikleri
	for x in [-0.0508, 0.0508]:
		for z in [-0.05, 0.0, 0.05]:
			MU.cyl(n, 0.002, 0.003, Vector3(x, -0.004, z), _black(), Vector3(0, 0, 90), 8)


# ---------------------------------------------------------------- 120mm KASA FANI

static func _fan(out: Dictionary, m: Dictionary) -> void:
	var n: Node3D = out.node
	var is_rgb := bool(m.get("rgb", false))
	var frame := MU.mat(Color(0.08, 0.085, 0.095), 0.15, 0.52)
	var pad := MU.mat(Color(0.16, 0.16, 0.18), 0.0, 0.85)
	# kare 120mm dış çerçeve (4 kenar + köşe kauçuk pedler + vida delikleri)
	for y in [-0.055, 0.055]:
		MU.rbox(n, Vector3(0.024, 0.01, 0.12), Vector3(0, y, 0), frame, 0.0025)
	for z in [-0.055, 0.055]:
		MU.rbox(n, Vector3(0.024, 0.12, 0.01), Vector3(0, 0, z), frame, 0.0025)
	for y in [-0.052, 0.052]:
		for z in [-0.052, 0.052]:
			MU.rbox(n, Vector3(0.0252, 0.014, 0.014), Vector3(0, y, z), pad, 0.002)
			MU.cyl(n, 0.0026, 0.026, Vector3(0, y, z), _black(), Vector3(0, 0, 90), 8)
	# arka destek kolları (-X yüzü)
	for a in [45.0, 135.0, 225.0, 315.0]:
		var piv := Node3D.new()
		piv.position = Vector3(-0.009, 0, 0)
		piv.rotation_degrees.x = a
		n.add_child(piv)
		MU.box(piv, Vector3(0.003, 0.054, 0.004), Vector3(0, 0.027, 0), frame)
	# RGB halka (yalnızca _rgb modelde)
	var ring: Material = null
	var hub := _alu()
	if is_rgb:
		ring = MU.new_mat(Color(0.3, 0.78, 1.0), 0, 0.25, 2.2)
		out.rgb.append(ring)
		MU.torus(n, 0.048, 0.054, Vector3(0.011, 0, 0), ring, Vector3(0, 0, 90))
		MU.torus(n, 0.048, 0.054, Vector3(-0.011, 0, 0), ring, Vector3(0, 0, 90))
		hub = ring
	var blade := MU.mat(Color(0.86, 0.88, 0.92), 0.0, 0.35) if is_rgb else MU.mat(Color(0.14, 0.14, 0.16), 0.0, 0.45)
	out.rotors.append(MU.fan(n, 0.051, Vector3.ZERO, Vector3(0, 0, 90), frame, blade, ring, hub))


# ---------------------------------------------------------------- CMOS PİLİ (CR2032)

static func _cmos(out: Dictionary) -> void:
	var n: Node3D = out.node
	# CR2032 gümüş düğme pil: kalınlık X (0..0.004), çap 20mm (Y/Z)
	MU.cyl(n, 0.010, 0.0032, Vector3(0.0018, 0, 0), _silver(), Vector3(0, 0, 90), 24)
	MU.cyl(n, 0.0092, 0.0008, Vector3(0.0005, 0, 0), _black(), Vector3(0, 0, 90), 20)
	MU.torus(n, 0.0086, 0.0098, Vector3(0.0032, 0, 0), _alu(), Vector3(0, 0, 90))
	_text(n, "+", Vector3(0.0036, 0.0042, 0), 26, Color(0.22, 0.24, 0.28), Vector3(0, 90, 0), 0.00018)
	_text(n, "CR2032\n3V", Vector3(0.0036, -0.0015, 0), 18, Color(0.24, 0.26, 0.3), Vector3(0, 90, 0), 0.00016)
