extends Node
## Geliştirici testi: `godot --headless -- --compattest` Compatibility motorunun tüm kurallarını
## ve rastgele üretilen normal PC işlerinin uyumluluğunu doğrular. Başarılıysa "COMPATTEST OK" yazar.

const PC_CASE := preload("res://scripts/pc_case.gd")

const INCOMPAT_IDS := ["incompat_ram_ddr", "incompat_psu_gpu", "incompat_no_igpu"]

var fails: Array = []


func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	_test_basic_slot_rules()
	_test_form_factor()
	_test_cpu_socket()
	_test_ram_rules()
	_test_storage_limits()
	_test_gpu_length()
	_test_cooler_rules()
	_test_psu_rules()
	_test_display_rules()
	_test_calc_watts()
	_test_catalog_part()
	_test_random_pc_jobs(60)
	if fails.is_empty():
		print("COMPATTEST OK")
		get_tree().quit(0)
	else:
		print("COMPATTEST BAŞARISIZ (%d hata):" % fails.size())
		for f in fails:
			print("  - ", f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


func _def(sku: String) -> PartDef:
	var d: PartDef = DB.parts.get_def(sku)
	_check(d != null, "parça tanımı bulunamadı: " + sku)
	return d


func _slot(accepts: String, idx := 0, extra: Array = [], part = null, nm := "") -> Dictionary:
	return {"accepts": accepts, "accepts_extra": extra, "slot_index": idx, "part": part, "name": nm}


func _state(case_id := "atx_mid", overrides: Dictionary = {}) -> Dictionary:
	var st := {
		"case_id": case_id,
		"case_def": DB.parts.case_def(case_id),
		"mobo": null,
		"cpu": null,
		"cooler": null,
		"rams": [],
		"gpu": null,
		"psu": null,
		"storage": [],
		"fans": [],
		"cmos": null,
	}
	for k in overrides:
		st[k] = overrides[k]
	return st


# --- 1. Temel yuva kuralları ---
func _test_basic_slot_rules() -> void:
	var st := _state("atx_mid")
	var r_null := Compatibility.check(_slot("cpu"), null, st)
	_check(not r_null.ok and r_null.code == "invalid_part", "null parça engellenmeli")

	var r_occ := Compatibility.check(_slot("cpu", 0, [], _def("cpu_am4_6c")), _def("cpu_am4_6c"), st)
	_check(not r_occ.ok and r_occ.code == "occupied", "dolu yuva engellenmeli")

	var r_wrong := Compatibility.check(_slot("cpu"), _def("ram_ddr4_8g"), st)
	_check(not r_wrong.ok and r_wrong.code == "wrong_slot", "yanlış yuva türü engellenmeli")

	var r_nomobo := Compatibility.check(_slot("cpu"), _def("cpu_am4_6c"), st)
	_check(not r_nomobo.ok and r_nomobo.code == "no_mobo", "anakartsız CPU engellenmeli")


# --- 2. Kasa <-> anakart form faktörü ---
func _test_form_factor() -> void:
	var atx := _def("mobo_am4_atx")
	var matx := _def("mobo_am4_matx")
	var itx := _def("mobo_lga1851_itx")

	var r1 := Compatibility.check(_slot("mobo"), atx, _state("itx_compact"))
	_check(not r1.ok and r1.code == "form_factor", "ATX anakart itx_compact kasada engellenmeli")

	var r2 := Compatibility.check(_slot("mobo"), atx, _state("matx_mini"))
	_check(not r2.ok and r2.code == "form_factor", "ATX anakart matx_mini kasada engellenmeli")

	var r3 := Compatibility.check(_slot("mobo"), matx, _state("itx_compact"))
	_check(not r3.ok and r3.code == "form_factor", "mATX anakart itx_compact kasada engellenmeli")

	var r4 := Compatibility.check(_slot("mobo"), itx, _state("itx_compact"))
	_check(r4.ok, "ITX anakart itx_compact kasaya uymalı")

	var r5 := Compatibility.check(_slot("mobo"), atx, _state("atx_mid"))
	_check(r5.ok, "ATX anakart atx_mid kasaya uymalı")


# --- 3. CPU <-> anakart soket ---
func _test_cpu_socket() -> void:
	var r_am4_am5 := Compatibility.check(_slot("cpu"), _def("cpu_am4_6c"), _state("atx_mid", {"mobo": _def("mobo_am5_atx")}))
	_check(not r_am4_am5.ok and r_am4_am5.code == "socket", "AM4 CPU AM5 anakartta engellenmeli")

	var r_lga := Compatibility.check(_slot("cpu"), _def("cpu_lga1700_6c"), _state("itx_compact", {"mobo": _def("mobo_lga1851_itx")}))
	_check(not r_lga.ok and r_lga.code == "socket", "LGA1700 CPU LGA1851 anakartta engellenmeli")

	var r_lga_rev := Compatibility.check(_slot("cpu"), _def("cpu_lga1851_8c"), _state("matx_mini", {"mobo": _def("mobo_lga1700_matx")}))
	_check(not r_lga_rev.ok and r_lga_rev.code == "socket", "LGA1851 CPU LGA1700 anakartta engellenmeli")

	var r_ok_am5 := Compatibility.check(_slot("cpu"), _def("cpu_am5_6c"), _state("atx_mid", {"mobo": _def("mobo_am5_atx")}))
	_check(r_ok_am5.ok, "AM5 CPU AM5 anakarta uymalı")

	var r_ok_1851 := Compatibility.check(_slot("cpu"), _def("cpu_lga1851_8c"), _state("itx_compact", {"mobo": _def("mobo_lga1851_itx")}))
	_check(r_ok_1851.ok, "LGA1851 CPU LGA1851 anakarta uymalı")


# --- 4. RAM DDR çentiği ve yuva sınırı ---
func _test_ram_rules() -> void:
	var m_ddr4_2 := _def("mobo_am4_matx")   # DDR4, 2 yuva
	var m_ddr4_4 := _def("mobo_am4_atx")    # DDR4, 4 yuva
	var m_ddr5_4 := _def("mobo_am5_atx")    # DDR5, 4 yuva

	var r_d4_in_d5 := Compatibility.check(_slot("ram", 0), _def("ram_ddr4_8g"), _state("atx_mid", {"mobo": m_ddr5_4}))
	_check(not r_d4_in_d5.ok and r_d4_in_d5.code == "ddr_notch", "DDR4 RAM DDR5 anakartta engellenmeli")

	var r_d5_in_d4 := Compatibility.check(_slot("ram", 0), _def("ram_ddr5_16g"), _state("atx_mid", {"mobo": m_ddr4_2}))
	_check(not r_d5_in_d4.ok and r_d5_in_d4.code == "ddr_notch", "DDR5 RAM DDR4 anakartta engellenmeli")

	var r_lim_ok := Compatibility.check(_slot("ram", 1), _def("ram_ddr4_8g"), _state("atx_mid", {"mobo": m_ddr4_2}))
	_check(r_lim_ok.ok, "2 yuvalı anakartta slot_index=1 kabul edilmeli")

	var r_lim_blk := Compatibility.check(_slot("ram", 2), _def("ram_ddr4_8g"), _state("atx_mid", {"mobo": m_ddr4_2}))
	_check(not r_lim_blk.ok and r_lim_blk.code == "ram_slot_limit", "2 yuvalı anakartta slot_index=2 engellenmeli")

	var r_4slot_ok := Compatibility.check(_slot("ram", 3), _def("ram_ddr4_16g_rgb"), _state("atx_mid", {"mobo": m_ddr4_4}))
	_check(r_4slot_ok.ok, "4 yuvalı anakartta slot_index=3 kabul edilmeli")


# --- 5. M.2 ve SATA depolama sınırları ---
func _test_storage_limits() -> void:
	var m_1m2 := _def("mobo_am4_matx")     # 1 M.2, 4 SATA
	var m_2sata := _def("mobo_lga1851_itx")  # 1 M.2, 2 SATA

	var r_m2_ok := Compatibility.check(_slot("nvme", 0), _def("nvme_512"), _state("atx_mid", {"mobo": m_1m2}))
	_check(r_m2_ok.ok, "1 M.2 anakartta ilk M.2 yuvası kabul edilmeli")

	var r_m2_blk := Compatibility.check(_slot("nvme", 1), _def("nvme_1t_pro"), _state("atx_mid", {"mobo": m_1m2}))
	_check(not r_m2_blk.ok and r_m2_blk.code == "m2_limit", "1 M.2 anakartta 2. M.2 yuvası engellenmeli")

	var sata_slot := _slot("ssd", 0, ["hdd"])
	var r_hdd_ok := Compatibility.check(sata_slot, _def("hdd_sata_1t"), _state("itx_compact", {"mobo": m_2sata, "storage": [_def("ssd_sata_512")]}))
	_check(r_hdd_ok.ok, "2 SATA portlu anakartta 2. SATA disk kabul edilmeli")

	var r_sata_blk := Compatibility.check(sata_slot, _def("ssd_sata_512"), _state("itx_compact", {
		"mobo": m_2sata,
		"storage": [_def("ssd_sata_512"), _def("hdd_sata_1t")],
	}))
	_check(not r_sata_blk.ok and r_sata_blk.code == "sata_limit", "2 SATA portlu anakartta 3. SATA disk engellenmeli")


# --- 6. GPU uzunluk sınırı ---
func _test_gpu_length() -> void:
	var m_itx := _def("mobo_lga1851_itx")
	var m_atx := _def("mobo_am5_atx")

	var r_itx_blk := Compatibility.check(_slot("gpu"), _def("gpu_flagship_16g"), _state("itx_compact", {"mobo": m_itx}))
	_check(not r_itx_blk.ok and r_itx_blk.code == "gpu_length", "315mm GPU itx_compact (225mm) kasada engellenmeli")

	var r_matx_blk := Compatibility.check(_slot("gpu"), _def("gpu_flagship_16g"), _state("matx_mini", {"mobo": _def("mobo_am4_matx")}))
	_check(not r_matx_blk.ok and r_matx_blk.code == "gpu_length", "315mm GPU matx_mini (270mm) kasada engellenmeli")

	var r_itx_ok := Compatibility.check(_slot("gpu"), _def("gpu_entry_4g"), _state("itx_compact", {"mobo": m_itx}))
	_check(r_itx_ok.ok, "210mm GPU itx_compact kasaya sığmalı")

	var r_atx_ok := Compatibility.check(_slot("gpu"), _def("gpu_flagship_16g"), _state("atx_mid", {"mobo": m_atx}))
	_check(r_atx_ok.ok, "315mm GPU atx_mid (330mm) kasaya sığmalı")


# --- 7. Soğutucu yüksekliği, radyatör ve soket ---
func _test_cooler_rules() -> void:
	var m_itx := _def("mobo_lga1851_itx")
	var c_1851 := _def("cpu_lga1851_8c")
	var st_no_cpu := _state("atx_mid", {"mobo": _def("mobo_am4_atx")})
	var r_nocpu := Compatibility.check(_slot("cooler"), _def("cooler_stock"), st_no_cpu)
	_check(not r_nocpu.ok and r_nocpu.code == "no_cpu", "CPU olmadan soğutucu engellenmeli")

	var st_itx := _state("itx_compact", {"mobo": m_itx, "cpu": c_1851})
	var r_h_blk := Compatibility.check(_slot("cooler"), _def("cooler_tower"), st_itx)
	_check(not r_h_blk.ok and r_h_blk.code == "cooler_height", "155mm kule soğutucu itx_compact (120mm) kasada engellenmeli")

	var r_rad_blk := Compatibility.check(_slot("cooler"), _def("cooler_aio_240"), st_itx)
	_check(not r_rad_blk.ok and r_rad_blk.code == "cooler_rad", "240mm AIO itx_compact (max_rad_mm: 0) kasada engellenmeli")

	var st_matx := _state("matx_mini", {"mobo": _def("mobo_am4_matx"), "cpu": _def("cpu_am4_6c")})
	var r_rad_ok := Compatibility.check(_slot("cooler"), _def("cooler_aio_240"), st_matx)
	_check(r_rad_ok.ok, "240mm AIO matx_mini (max_rad_mm: 240) kasada kabul edilmeli")

	# Yalnızca AM4 destekleyen test soğutucusu LGA1851 anakartta engellenmeli
	var am4_only_cooler := PartDef.from_dict({
		"id": "test_cooler_am4", "category": "cooler", "tier": 1, "name": "AM4 Test Soğutucu",
		"price": 20, "device": "pc", "specs": {"type": "air", "height_mm": 55, "tdp": 95},
		"compat": {"sockets": ["AM4"]},
	})
	var r_csock := Compatibility.check(_slot("cooler"), am4_only_cooler, st_itx)
	_check(not r_csock.ok and r_csock.code == "cooler_socket", "soketi uymayan soğutucu engellenmeli")


# --- 8. PSU konnektör (engel) ve düşük watt (uyarı + check_system bayrağı) ---
func _test_psu_rules() -> void:
	var st_gpu := _state("atx_mid", {
		"mobo": _def("mobo_am5_atx"),
		"cpu": _def("cpu_am5_12c"),
		"cooler": _def("cooler_aio_240"),
		"rams": [_def("ram_ddr5_16g")],
		"storage": [_def("nvme_512")],
		"gpu": _def("gpu_flagship_16g"),
	})
	# Konnektör uyumsuzluğu (12VHPWR yok): engellenir
	var r_conn_psu := Compatibility.check(_slot("psu"), _def("psu_450w"), st_gpu)
	_check(not r_conn_psu.ok and r_conn_psu.code == "psu_connectors", "12VHPWR olmayan psu_450w + gpu_flagship_16g engellenmeli")

	var st_psu := st_gpu.duplicate()
	st_psu["gpu"] = null
	st_psu["psu"] = _def("psu_450w")
	var r_conn_gpu := Compatibility.check(_slot("gpu"), _def("gpu_flagship_16g"), st_psu)
	_check(not r_conn_gpu.ok and r_conn_gpu.code == "psu_connectors", "psu_450w takılıyken gpu_flagship_16g engellenmeli")

	# Düşük watt (konnektör var ama watt yetersiz): takmaya izin verir (severity == "warn"), check_system yakalar
	var weak_psu := PartDef.from_dict({
		"id": "test_psu_350w", "category": "psu", "tier": 1, "name": "Test 350W",
		"price": 30, "device": "pc", "specs": {"watts": 350},
		"compat": {"watts": 350, "connectors": {"8pin": 2, "6pin": 2, "12vhpwr": 1}},
	})
	var r_warn := Compatibility.check(_slot("psu"), weak_psu, st_gpu)
	_check(r_warn.ok and r_warn.severity == "warn" and r_warn.code == "psu_watts",
		"yetersiz watt PSU warn olarak takılabilmeli (got: %s)" % str(r_warn))

	var st_under := st_gpu.duplicate()
	st_under["psu"] = weak_psu
	var sys_under := Compatibility.check_system(st_under)
	var has_watt_issue := false
	for iss in sys_under.issues:
		if str(iss.code) == "psu_watts":
			has_watt_issue = true
	_check(not sys_under.ok and has_watt_issue, "yetersiz watt PSU check_system() içinde işaretlenmeli")

	var st_ok := st_gpu.duplicate()
	st_ok["psu"] = _def("psu_750w")
	var sys_ok := Compatibility.check_system(st_ok)
	_check(sys_ok.ok, "uyumlu 750W sistem check_system() geçmeli: %s" % str(sys_ok.issues))


# --- 9. Görüntü çıkışı (iGPU / GPU) ---
func _test_display_rules() -> void:
	var r_igpu := Compatibility.check_display(_def("cpu_am4_8c_g"), null)
	_check(r_igpu.ok, "iGPU işlemci GPU olmadan görüntü vermeli")

	var r_no_igpu := Compatibility.check_display(_def("cpu_am4_6c"), null)
	_check(not r_no_igpu.ok and r_no_igpu.code == "no_display", "iGPU olmayan işlemci GPU'suz no_display dönmeli")

	var r_with_gpu := Compatibility.check_display(_def("cpu_am4_6c"), _def("gpu_entry_4g"))
	_check(r_with_gpu.ok, "iGPU olmayan işlemci GPU ile görüntü vermeli")

	var r_none := Compatibility.check_display(null, null)
	_check(not r_none.ok and r_none.code == "no_display", "CPU ve GPU yokken no_display dönmeli")


# --- 10. Watt hesabı ---
func _test_calc_watts() -> void:
	var st := _state("atx_mid", {
		"cpu": _def("cpu_am4_6c"),          # 65W
		"gpu": _def("gpu_entry_4g"),        # 75W
		"rams": [_def("ram_ddr4_8g"), _def("ram_ddr4_8g")],  # 10W
		"storage": [_def("ssd_sata_512")],  # 5W
		"fans": [_def("fan_120_std")],      # 3W
		"psu": _def("psu_550w"),            # 550W
	})
	var w := Compatibility.calc_watts(st)
	# 50 + 65 + 75 + 10 + 5 + 3 = 208W, önerilen = ceil(208 * 1.25 / 50) * 50 = 300W
	_check(w.draw == 208 and w.psu == 550 and w.recommended == 300 and w.ok,
		"calc_watts beklenen 208/550/300/ok, gelen: %s" % str(w))

	var st_nopsu := st.duplicate()
	st_nopsu["psu"] = null
	var w2 := Compatibility.calc_watts(st_nopsu)
	_check(w2.psu == 0 and not w2.ok, "PSU yokken calc_watts.ok false olmalı")


# --- 11. ParçaNet katalog uyumluluk kontrolü ---
func _test_catalog_part() -> void:
	var st := _state("itx_compact", {
		"mobo": _def("mobo_lga1851_itx"),
		"cpu": _def("cpu_lga1851_8c"),
		"psu": _def("psu_450w"),
	})
	_check(not Compatibility.check_catalog_part(_def("mobo_am4_atx"), st).ok, "katalog: ATX mobo itx_compact reddedilmeli")
	_check(not Compatibility.check_catalog_part(_def("cpu_am4_6c"), st).ok, "katalog: AM4 CPU LGA1851 reddedilmeli")
	_check(not Compatibility.check_catalog_part(_def("ram_ddr4_8g"), st).ok, "katalog: DDR4 RAM DDR5 reddedilmeli")
	_check(Compatibility.check_catalog_part(_def("ram_ddr5_16g"), st).ok, "katalog: DDR5 RAM kabul edilmeli")
	_check(not Compatibility.check_catalog_part(_def("gpu_flagship_16g"), st).ok, "katalog: 315mm GPU itx_compact reddedilmeli")
	_check(not Compatibility.check_catalog_part(_def("cooler_aio_240"), st).ok, "katalog: 240mm AIO itx_compact reddedilmeli")
	_check(not Compatibility.check_catalog_part(_def("cooler_tower"), st).ok, "katalog: 155mm kule itx_compact reddedilmeli")
	_check(Compatibility.check_catalog_part(_def("lap_ram_8g"), st).ok, "katalog: mobil parça her zaman ok dönmeli")


# --- 12. 50+ rastgele üretilen normal PC işinde kazaen uyumsuzluk olmamalı ---
func _test_random_pc_jobs(count: int) -> void:
	var jm = Game.job_mgr
	if jm == null:
		_check(false, "Game.job_mgr bulunamadı")
		return
	var templates := []
	for t in DB.jobs.templates():
		if t.kind in ["sale", "device", "build", "incompat"]:
			continue
		if INCOMPAT_IDS.has(t.id) or INCOMPAT_IDS.has(t.fault):
			continue
		templates.append(t)
	_check(not templates.is_empty(), "normal PC iş şablonu bulunamadı")
	if templates.is_empty():
		return
	var tested := 0
	for i in count:
		var t = templates[i % templates.size()]
		var j: Dictionary = jm._make_job_of(t.id)
		var fault_id := str(j.get("fault", t.fault))
		if INCOMPAT_IDS.has(fault_id) or INCOMPAT_IDS.has(str(j.get("kind", ""))):
			continue
		var parts: Array = j.get("parts", [])
		if parts.is_empty():
			continue
		var pc = PC_CASE.new()
		if j.has("case_id") and not str(j.case_id).is_empty():
			pc.case_id = str(j.case_id)
		add_child(pc)
		pc.fill(parts)
		var sys := Compatibility.check_system(pc.case_state())
		if not sys.ok:
			_check(false, "normal iş '%s' (#%d) uyumsuz üretildi: %s" % [t.id, i, str(sys.issues)])
		pc.queue_free()
		tested += 1
	_check(tested >= 50, "en az 50 normal PC işi sınanmalı (sınanan: %d)" % tested)
