extends Node
## Geliştirici testi: `godot --headless -- --diagtest` Faz 3 arıza & teşhis derinliğini doğrular.
## Başarılıysa "DIAGTEST OK" yazar.

const PC_SCENE := preload("res://scripts/pc_case.gd")
const PART := preload("res://scripts/part.gd")


func _ready() -> void:
	var main = get_parent()
	await get_tree().create_timer(0.5).timeout
	var jobs = Game.job_mgr
	jobs.arrivals_enabled = false
	jobs.force_express = 0
	Game.save_path = "user://test_save_diag.json"
	Game.new_game()

	_check_catalog_and_locks(jobs)
	await _check_screws_and_test_part(main, jobs)
	_check_debug_leds_and_postcard(main, jobs)
	_check_cables_and_multi(main, jobs)
	_check_hw_defects_and_underwatt(main, jobs)
	_check_software_and_service_panel(main, jobs)
	_check_mobile_faults(jobs)

	if FileAccess.file_exists(Game.save_path):
		DirAccess.remove_absolute(Game.save_path)
	print("DIAGTEST OK")
	get_tree().quit()


func _find_tool(main, ttype: String):
	for c in main.get_children():
		if c.has_method("is_tool") and c.is_tool() and str(c.get("tool_type")) == ttype:
			return c
	return null


func _check_catalog_and_locks(jobs) -> void:
	assert(DB.jobs._fault_order.size() == 50, "50 arıza tanımı bekleniyor: %d" % DB.jobs._fault_order.size())
	var wsum := 0
	for t in DB.jobs.templates():
		wsum += int(t.weight)
	assert(wsum == 100, "iş ağırlık toplamı 100 olmalı: %d" % wsum)
	# geliştirme kilidi: antivirus_usb/install_usb yokken sw_virus/sw_os_corrupt seçilmemeli
	jobs._director._day = 10
	jobs._director._rep = 5.0
	assert(not jobs._director._eligible("sw_virus", 2000) and not jobs._director._eligible("sw_os_corrupt", 2000), "kilitli USB işleri erken çıkmamalı")
	Game.upgrades["antivirus_usb"] = true
	Game.upgrades["install_usb"] = true
	assert(jobs._director._eligible("sw_virus", 2000) and jobs._director._eligible("sw_os_corrupt", 2000), "USB geliştirmeleri açılınca işler gelmeli")
	Game.upgrades.erase("antivirus_usb")
	Game.upgrades.erase("install_usb")
	print("OK Faz 3 veri havuzu & req_upgrade kilidi")


func _check_screws_and_test_part(main, jobs) -> void:
	var rec: Dictionary = jobs.drop_off(jobs._make_job_of("repair_gpu"))
	var pc = jobs.dev_to_bench(rec)
	assert(pc.panel_screwed(), "yeni PC vidaları sıkılı olmalı")
	pc.toggle_panel()
	assert(not pc.panel_open, "vidalar sıkılıyken yan kapak açılmamalı")
	pc.unscrew("panel_1")
	pc.unscrew("panel_2")
	pc.toggle_panel()
	assert(pc.panel_open, "kapak vidaları sökülünce açılmalı")
	# GPU vidası kilit ve açma
	pc.fasten_screw("gpu")
	assert(pc.can_remove_reason("gpu") != "", "GPU vidası sıkılıyken söküm engellenmeli")
	pc.unscrew("gpu")
	assert(pc.can_remove_reason("gpu") == "", "GPU vidası sökülünce engel kalkmalı")
	# tamir et (sağlam GPU), ama eksik vida teslimi engellemeli
	var bad_gpu = pc.part_in("gpu")
	pc.slots.gpu.detach()
	bad_gpu.queue_free()
	pc.slots.gpu.install(PART.new().setup_sku("gpu_entry_4g", false))
	pc.toggle_panel(true)
	assert(pc.diagnose() == "ok" and pc.screws_missing(), "eksik vida tespit edilmeli")
	assert(jobs._problem_of(rec) != "", "eksik vidayla teslim engellenmeli")
	# test parçası takılıysa da teslim engellenmeli
	pc.fasten_all()
	assert(jobs._problem_of(rec) == "", "vidalar sıkılınca teslim serbest olmalı")
	pc.unscrew_all()
	pc.toggle_panel()
	var old_psu = pc.part_in("psu")
	pc.slots.psu.detach()
	var tpsu = PART.new().setup_sku("psu_750w", false)
	tpsu.make_test_part()
	pc.slots.psu.install(tpsu)
	pc.fasten_all()
	pc.toggle_panel(true)
	assert("test parçanı" in jobs._problem_of(rec), "test parçası teslimde reddedilmeli")
	pc.unscrew_all()
	pc.toggle_panel()
	pc.slots.psu.detach()
	tpsu.queue_free()
	pc.slots.psu.install(old_psu)
	pc.fasten_all()
	pc.toggle_panel(true)
	assert(jobs._problem_of(rec) == "")
	jobs._remove_record(rec, false)
	print("OK vida mekaniği & test parçası koruması")


func _check_debug_leds_and_postcard(main, _jobs) -> void:
	var pc = PC_SCENE.new()
	main.add_child(pc)
	pc.fill([
		{"slot": "mobo", "sku": "mobo_am4_matx", "broken": false},
		{"slot": "cpu", "sku": "cpu_am4_6c", "broken": false},
		{"slot": "cooler", "sku": "cooler_stock", "broken": false},
		{"slot": "ram1", "sku": "ram_ddr4_8g", "broken": true},
		{"slot": "ssd", "sku": "ssd_sata_512", "broken": false},
		{"slot": "psu", "sku": "psu_550w", "broken": false},
		{"slot": "fan1", "sku": "fan_120_std", "broken": false},
		{"slot": "cmos", "sku": "cmos_cr2032", "broken": false},
	])
	assert(not pc.has_debug_leds(), "giriş anakartında Debug LED olmamalı")
	var post_tool = _find_tool(main, "post_card")
	assert(post_tool != null, "POST kartı aleti bulunamadı")
	pc.tool_use(Game.player, post_tool, null)
	assert(pc.post_card_active, "POST kartı etkinleşmedi")
	assert(pc.has_debug_leds(), "POST kartı takılıyken teşhis açık olmalı")
	pc.post_card_active = false
	# gamer anakartta yerleşik Debug LED olmalı
	var old_m = pc.part_in("mobo")
	pc.slots.mobo.detach()
	old_m.queue_free()
	pc.slots.mobo.install(PART.new().setup_sku("mobo_am4_atx", false))
	assert(pc.has_debug_leds(), "oyuncu anakartında Debug LED olmalı")
	pc.queue_free()
	print("OK Debug LED & POST Teşhis Kartı")


func _check_cables_and_multi(main, jobs) -> void:
	# 5 kablo türü tek tek sınanır
	var expected := {
		"cable_24pin": "atx_24",
		"cable_cpu": "cpu_8",
		"cable_gpu": "pcie_gpu",
		"cable_sata": "sata",
		"cable_fp": "front_panel",
	}
	for tid in expected:
		var cid: String = expected[tid]
		var rec: Dictionary = jobs.drop_off(jobs._make_job_of(tid))
		var pc = jobs.dev_to_bench(rec)
		var diags: Array = pc.diagnose_all()
		assert(diags.has(cid.replace("atx_24", "cable_24pin").replace("cpu_8", "cable_cpu").replace("pcie_gpu", "cable_gpu").replace("sata", "cable_sata").replace("front_panel", "cable_fp")), "kablo teşhis eksik: " + tid)
		assert(pc.plug_cable(cid), "kablo takılamadı: " + cid)
		assert(pc.diagnose() == "ok", "kablo takılınca düzelmedi: " + cid)
		pc.tidy_cables()
		assert(pc.cables_tidy, "kablo düzeni bayrağı açılmadı")
		jobs._remove_record(rec, false)
	# çoklu arıza: ram_unseated + cable_sata_loose
	var mrec: Dictionary = jobs.drop_off(jobs._make_job_of("multi_ram_cable"))
	var mpc = jobs.dev_to_bench(mrec)
	var all: Array = mpc.diagnose_all()
	assert(all.has("ram_unseated") and all.has("cable_sata") and all.size() >= 2, "çoklu arıza tespit edilmedi: %s" % [all])
	for rn in ["ram1", "ram2", "ram3", "ram4"]:
		var rp = mpc.part_in(rn)
		if rp != null and not rp.seated:
			rp.seated = true
			rp.rotation_degrees = Vector3.ZERO
	assert(mpc.diagnose_all().has("cable_sata") and not mpc.diagnose_all().has("ram_unseated"))
	mpc.plug_cable("sata")
	assert(mpc.diagnose() == "ok", "çoklu arıza tamamen temizlenmedi: " + mpc.diagnose())
	jobs._remove_record(mrec, false)
	print("OK 5 kablo + kablo düzeni + çoklu arıza")


func _check_hw_defects_and_underwatt(main, jobs) -> void:
	# CPU eğik pinler -> tornavida ile düzelt
	var rec_pin: Dictionary = jobs.drop_off(jobs._make_job_of("repair_cpu_pins"))
	var pc_pin = jobs.dev_to_bench(rec_pin)
	assert(pc_pin != null and pc_pin.diagnose() == "cpu_pins", "eğik pin teşhis edilmedi")
	var sd = _find_tool(main, "screwdriver")
	assert(sd != null, "tornavida bulunamadı")
	pc_pin.tool_use(Game.player, sd, pc_pin.slots.cpu)
	assert(pc_pin.diagnose() == "ok", "eğik pin tornavidayla düzelmedi")
	jobs._remove_record(rec_pin, false)
	# GPU VRAM glitch
	var rec_vram: Dictionary = jobs.drop_off(jobs._make_job_of("repair_gpu_artifact"))
	var pc_vram = jobs.dev_to_bench(rec_vram)
	assert(pc_vram != null and pc_vram.diagnose() == "gpu_artifact", "VRAM hatası teşhis edilmedi")
	pc_vram.power_button()
	assert(pc_vram.powered, "VRAM arızalı PC açılıp artifact göstermeli")
	pc_vram.power_off()
	jobs._remove_record(rec_vram, false)
	# Mobo şişmiş kondansatör
	var rec_cap: Dictionary = jobs.drop_off(jobs._make_job_of("repair_mobo_cap"))
	var pc_cap = jobs.dev_to_bench(rec_cap)
	assert(pc_cap != null and pc_cap.diagnose() == "mobo_cap", "kondansatör arızası teşhis edilmedi")
	jobs._remove_record(rec_cap, false)
	# HDD SMART fail
	var rec_hdd: Dictionary = jobs.drop_off(jobs._make_job_of("repair_hdd_smart"))
	var pc_hdd = jobs.dev_to_bench(rec_hdd)
	assert(pc_hdd != null and pc_hdd.diagnose() == "hdd_smart", "HDD SMART arızası teşhis edilmedi")
	jobs._remove_record(rec_hdd, false)
	# PSU watt yetersizliği -> psu_750w ile çöz
	var rec_watt: Dictionary = jobs.drop_off(jobs._make_job_of("psu_underwatt"))
	var pc_watt = jobs.dev_to_bench(rec_watt)
	assert(pc_watt != null and pc_watt.diagnose_all().has("psu_watts"), "PSU yetersiz watt tespit edilmedi: %s" % [pc_watt.diagnose_all() if pc_watt else []])
	pc_watt.unscrew_all()
	pc_watt.toggle_panel()
	var old_p = pc_watt.part_in("psu")
	pc_watt.slots.psu.detach()
	old_p.queue_free()
	pc_watt.slots.psu.install(PART.new().setup_sku("psu_750w", false))
	assert(pc_watt.diagnose() == "ok", "750W PSU takılınca düzelmedi: %s" % [pc_watt.diagnose_all()])
	jobs._remove_record(rec_watt, false)
	print("OK eğik pin, VRAM, kondansatör, SMART ve yetersiz watt PSU")


func _check_software_and_service_panel(main, _jobs) -> void:
	Game.upgrades["antivirus_usb"] = true
	Game.upgrades["install_usb"] = true
	var pc = PC_SCENE.new()
	main.add_child(pc)
	pc.fill([
		{"slot": "mobo", "sku": "mobo_am4_atx", "broken": false},
		{"slot": "cpu", "sku": "cpu_am4_6c", "broken": false},
		{"slot": "cooler", "sku": "cooler_stock", "broken": false},
		{"slot": "ram1", "sku": "ram_ddr4_8g", "broken": false},
		{"slot": "gpu", "sku": "gpu_entry_4g", "broken": false},
		{"slot": "ssd", "sku": "ssd_sata_512", "broken": false},
		{"slot": "psu", "sku": "psu_550w", "broken": false},
		{"slot": "fan1", "sku": "fan_120_std", "broken": false},
		{"slot": "cmos", "sku": "cmos_cr2032", "broken": false},
		{"sw_faults": ["sw_virus", "sw_os_corrupt", "sw_driver", "sw_boot_order", "sw_xmp_off", "sw_bios_update", "sw_disk_full"]},
	])
	assert(pc.diagnose_all().size() == 7, "7 yazılım arızası olmalı")
	var av = _find_tool(main, "antivirus_usb")
	var iu = _find_tool(main, "install_usb")
	pc.tool_use(Game.player, av, null)
	assert(not pc.has_sw_fault("sw_virus"))
	pc.tool_use(Game.player, iu, null)  # format -> sw_os_corrupt
	pc.tool_use(Game.player, iu, null)  # BIOS update -> sw_bios_update
	assert(not pc.has_sw_fault("sw_os_corrupt") and not pc.has_sw_fault("sw_bios_update"))
	assert(Game.pc_service != null)
	Game.pc_service.open(pc)
	Game.pc_service._apply_sw_fix("sw_driver", "ok")
	Game.pc_service._apply_sw_fix("sw_boot_order", "ok")
	Game.pc_service._apply_sw_fix("sw_xmp_off", "ok")
	Game.pc_service._apply_sw_fix("sw_disk_full", "ok")
	Game.pc_service.close()
	assert(pc.diagnose() == "ok", "tüm yazılım arızaları temizlenmedi: %s" % [pc.diagnose_all()])
	pc.queue_free()
	print("OK 7 yazılım/BIOS arızası & Servis Paneli")


func _check_mobile_faults(jobs) -> void:
	var main = get_parent()
	var air = _find_tool(main, "air")
	var sd = _find_tool(main, "screwdriver")
	var ipa = _find_tool(main, "ipa")
	var iu = _find_tool(main, "install_usb")
	# 10 laptop arızası
	var lap_codes := ["ram", "ssd", "bat", "scr", "kbd", "wifi", "dc", "lap_dust", "lap_hinge", "lap_liquid"]
	for code in lap_codes:
		var rec: Dictionary = jobs.drop_off(jobs._make_job_of("device_laptop", code))
		var dev = jobs.dev_to_bench(rec)
		assert(dev.diagnose() == code, "laptop teşhis yanlış (%s -> %s)" % [code, dev.diagnose()])
		match code:
			"lap_dust": dev.tool_use(Game.player, air, null)
			"lap_hinge": dev.tool_use(Game.player, sd, null)
			"lap_liquid": dev.tool_use(Game.player, ipa, null)
			_:
				var sl = dev.slots[code]
				var ptype: String = sl.accepts
				var old_p = sl.part
				sl.detach()
				old_p.queue_free()
				sl.install(PART.new().setup(ptype, 1, false))
		assert(dev.diagnose() == "ok", "laptop arızası düzelmedi: " + code)
		jobs._remove_record(rec, false)
	# 8 telefon arızası
	var ph_codes := ["bat", "port", "scr", "cam", "spk", "back", "tel_liquid", "tel_sw"]
	for code in ph_codes:
		var rec: Dictionary = jobs.drop_off(jobs._make_job_of("device_phone", code))
		var dev = jobs.dev_to_bench(rec)
		assert(dev.diagnose() == code, "telefon teşhis yanlış (%s -> %s)" % [code, dev.diagnose()])
		match code:
			"tel_liquid": dev.tool_use(Game.player, ipa, null)
			"tel_sw": dev.tool_use(Game.player, iu, null)
			_:
				var sl = dev.slots[code]
				var ptype: String = sl.accepts
				var old_p = sl.part
				sl.detach()
				old_p.queue_free()
				sl.install(PART.new().setup(ptype, 1, false))
		assert(dev.diagnose() == "ok", "telefon arızası düzelmedi: " + code)
		jobs._remove_record(rec, false)
	print("OK 10 laptop + 8 telefon arızası")
