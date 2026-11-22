extends Node
## Geliştirici testi: `godot --headless -- --benchtest` tezgâh modunu dener: giriş/çıkış, saat akışı,
## fareyle sök/tak API'si, tepsi, laptop ve cihaz tezgâhtan giderse çıkış.

var main
var jobs
var p
var bench


func _wait_state(want: String) -> void:
	var n := 0
	while bench.state != want and n < 200:
		await get_tree().process_frame
		n += 1
	assert(bench.state == want, "tezgâh durumu %s, beklenen %s" % [bench.state, want])


func _wait_for(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		if t > limit:
			return false
	return true


func _ready() -> void:
	main = get_parent()
	jobs = Game.job_mgr
	p = Game.player
	bench = main.bench
	await get_tree().create_timer(0.5).timeout
	Game.save_path = "user://test_save_bench.json"
	jobs.arrivals_enabled = false
	jobs.force_express = 0
	Game.new_game()
	assert(bench != null and bench.state == "off")
	await _pc_repair()
	await _laptop_repair()
	await _part_stealing()
	await _bench_lost()
	print("BENCHTEST OK")
	get_tree().quit()


## Kasa: gerçek bırakma + taşıma ile tezgâha, elde parça ile giriş, sök/tak, rafa koy, teslim.
func _pc_repair() -> void:
	var rec: Dictionary = jobs.drop_off(jobs._make_job_of("repair_ram"))
	var t := int(rec.ticket)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var can_capture: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED  # başsız sürücüde fare yakalanmayabilir
	assert(jobs.pick_up_device(rec, p) == "" and Game.is_carrying())
	assert(not bench.enter(), "cihaz taşırken tezgâh moduna girilmemeli")
	await get_tree().create_timer(0.4).timeout
	assert(jobs.place_on_bench() and Game.bench_device == jobs.devices[t])
	var pc = Game.bench_device
	assert(bench.device == pc and bench.kind == "pc")
	assert(bench._job_rec().get("ticket", -1) == t, "iş kaydı bulunamadı")
	main._buy(p, "ram", 1)
	var good = p.held
	assert(good != null and not good.broken)
	var clock0: float = Game.clock
	assert(bench.enter(), "tezgâh moduna girilemedi")
	assert(not get_tree().paused and not Game.paused, "tezgâh modu oyunu durdurmamalı")
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and Game.bench_active)
	assert(not Game.hud.corner_hint.visible, "Esc ipucu gizlenmedi")
	assert(p.held == null and bench.tray_parts.has(good), "elde tutulan parça tepsiye inmedi")
	await _wait_state("on")
	assert(bench.is_laid_flat() and pc.flat_mode, "PC tezgâh moduna girince yatmadı")
	bench.toggle_lay_flat()
	assert(not bench.is_laid_flat() and not pc.flat_mode, "PC dikleştirme çalışmadı")
	bench.toggle_lay_flat()
	await get_tree().create_timer(0.45).timeout
	assert(bench.is_laid_flat() and pc.flat_mode, "PC yeniden yatmadı")
	assert(get_viewport().get_camera_3d() == bench.cam, "yörünge kamera aktif değil")
	await get_tree().create_timer(0.6).timeout
	assert(Game.clock > clock0, "tezgâh modunda saat akmadı")
	assert(not bench._looks_fixed(rec), "bozuk cihaz tamir görünüyor")
	# masadaki 3D alet tıklanabilmeli
	var desk_tools: Array = bench.available_tools()
	assert(not desk_tools.is_empty(), "masada alet bulunamadı")
	var tres: Dictionary = bench._resolve({"collider": desk_tools[0]})
	assert(tres.get("kind", "") == "tool", "masadaki alet tanınmadı")
	bench.click(tres)
	assert(bench.tool == desk_tools[0], "alet seçilmedi")
	bench.click(tres)
	assert(bench.tool == null, "alet bırakılmadı")
	# doğrudan stok çekmecesinden parça alma & iade
	var st_before: int = Game.stock_of_sku("ram_ddr4_8g")
	if st_before < 1:
		Game.add_stock_sku("ram_ddr4_8g", 1)
		st_before = 1
	var stk_p = bench.take_from_stock("ram_ddr4_8g", false, false)
	assert(stk_p != null and Game.stock_of_sku("ram_ddr4_8g") == st_before - 1 and bench.tray_parts.has(stk_p), "stoktan tepsiye alınamadı")
	assert(bench.return_tray_part(stk_p) and Game.stock_of_sku("ram_ddr4_8g") == st_before, "tepsiden rafa iade çalışmadı")
	var gp: Vector3 = pc.global_transform * Vector3(pc.W / 2.0 - 0.002, pc.H / 2.0, 0.0)
	var sp: Vector2 = bench.cam.unproject_position(gp)
	assert(not bench.cam.is_position_behind(gp))
	var res: Dictionary = bench._resolve(bench._ray_hit(sp))
	assert(res.get("kind", "") == "widget", "cam kapak fareyle bulunamadı: %s" % [res])
	# vidalar sıkılıyken yan kapak açılmamalı; sökülünce açılmalı
	assert(pc.panel_screwed(), "yeni PC kapak vidaları sıkılı başlamalı")
	bench.click(res)
	assert(not pc.panel_open, "kapak vidaları sıkılıyken açılmamalı")
	assert(pc.unscrew("panel_1") and pc.unscrew("panel_2"))
	bench.click(res)
	assert(pc.panel_open, "vidalar sökülünce kapak açılmadı")
	# GPU vidası kilit/açma denemesi
	if pc.part_in("gpu") != null:
		pc.fasten_screw("gpu")
		assert(bench.remove_part(pc.slots.gpu) == null, "GPU vidası sıkılıyken sökülmemeli")
		pc.unscrew("gpu")
	var slot = pc.slots.ram1
	if pc.part_in("ram1") == null or not pc.part_in("ram1").broken:
		slot = pc.slots.ram2
	var bad = slot.part
	assert(bad != null and bad.broken)
	# takılı parça üstüne gelince sarı kutu değil Fresnel kenar vurgusu açılmalı
	bench._set_hl({"kind": "installed", "slot": slot, "part": bad, "node": bad})
	assert(not bench._hl.visible and not bench._hl_meshes.is_empty() and bench._hl_meshes[0].material_overlay != null, "Fresnel kenar vurgusu aktif değil")
	bench._clear_hl()
	assert(bench._hl_meshes.is_empty(), "vurgu temizlenmedi")
	assert(bench.remove_part(slot) == bad, "söküm başarısız")
	assert(slot.part == null and bench.tray_parts.has(bad) and bad.get_parent() == bench._tray)
	assert("origin" in good and good.origin == "stock", "stok parçası etiketlenmedi")
	assert("origin" in bad and bad.origin == "customer" and bad.origin_ticket == t, "müşteri parçası etiketlenmedi")
	assert(good.position.z < 0.0 and bad.position.z > 0.0, "tepside stok ve sökülen bölgeleri ayrılmadı (good.z=%.3f, bad.z=%.3f)" % [good.position.z, bad.position.z])
	assert(bench.tray_parts.size() == 2)
	# Tepsideki RAM yassı yatmalı ve fare ışınıyla sağdaki stok/müşteri parçaları alınabilmeli
	await get_tree().physics_frame
	var ram_bb: AABB = bench._footprint(good, good.transform.basis)
	assert(ram_bb.size.y < ram_bb.size.z and ram_bb.size.y < 0.015, "tepsideki RAM yassı yatmadı: %s" % [ram_bb.size])
	var good_center: Vector3 = good.global_transform * main.PART.PM.info("ram").center
	var bad_center: Vector3 = bad.global_transform * main.PART.PM.info("ram").center
	var pick_good: Dictionary = bench._pick_at(bench.cam.unproject_position(good_center))
	var pick_bad: Dictionary = bench._pick_at(bench.cam.unproject_position(bad_center))
	assert(pick_good.get("kind", "") == "tray" and pick_good.get("part") == good, "stok parçası fareyle alınamadı: %s" % [pick_good])
	assert(pick_bad.get("kind", "") == "tray" and pick_bad.get("part") == bad, "müşteri parçası fareyle alınamadı: %s" % [pick_bad])
	# Tornavida seçiliyken tepsideki parçaya tıklamak aleti bırakıp parçayı seçmeli
	var sd_tools: Array = desk_tools.filter(func(tl): return tl.tool_type == "screwdriver")
	assert(not sd_tools.is_empty())
	bench.select_tool(sd_tools[0])
	assert(bench.tool == sd_tools[0])
	bench.click(pick_good)
	assert(bench.tool == null and bench.selected == good, "alet aktifken tepsi parçasına tıklayınca seçilmedi")
	bench.cancel_selection()
	assert(bench.best_slot_for(good) == slot, "en uygun boş yuva bulunamadı")
	# Manyetik vida tabağına tıklayınca takılabilir vida (GPU) sıkılmalı
	if pc.part_in("gpu") != null and not pc.slot_screwed("gpu"):
		bench.click({"kind": "screw_dish", "node": bench._dish_root})
		assert(pc.slot_screwed("gpu"), "vida tabağına tıklayınca GPU vidası sıkılmadı")
	assert(bench.can_install(pc.slots.cpu, good).ok == false)
	assert(bench.can_install(pc.slots.gpu, good).ok == false)
	assert(bench.can_install(slot, good).ok == true)
	assert(bench.select_part(good))
	await get_tree().process_frame
	await get_tree().process_frame
	assert(slot.bench_tint.a > 0.0 and slot.bench_tint.g > slot.bench_tint.r, "uygun yuva yeşil değil")
	bench.cancel_selection()
	assert(bench.selected == null and slot.bench_tint.a == 0.0)
	bench.select_part(good)
	assert(bench.install_selected(pc.slots.cpu) == false, "yanlış yuvaya takıldı")
	assert(bench.install_selected(slot), "takılamadı")
	assert(slot.part == good and not bench.tray_parts.has(good) and good.slot == slot)
	# Seçili bozuk müşteri parçasını hurda kutusuna tıklayarak atma
	assert(bench.tray_parts.has(bad))
	assert(bench.select_part(bad))
	bench.click({"kind": "scrap_bin", "node": main.scrap_bin})
	assert(not bench.tray_parts.has(bad) and bench.selected == null, "hurda kutusuna tıklayınca parça atılmadı")
	assert(pc.diagnose() == "ok")
	bench.press_power()
	assert(pc.powered)
	bench.toggle_panel()
	assert(not pc.panel_open)
	assert(not bench._looks_fixed(rec), "vidalar eksik iken tamir tamam görünmemeli")
	pc.fasten_all()
	assert(bench._looks_fixed(rec), "vidalar sıkılınca tamir tamam ipucu çıkmadı")
	bench.exit()
	await _wait_state("off")
	assert(not bench.is_laid_flat() and not pc.flat_mode, "çıkışta PC dikleşmedi")
	assert(not Game.bench_active and get_viewport().get_camera_3d() == p.cam)
	assert(Game.hud.corner_hint.visible)
	assert(not can_capture or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "fare geri yakalanmadı")
	# cihazı al (tezgâh boşalır), rafa koy: hazır
	assert(jobs.pick_up_device(rec, p) == "" and Game.bench_device == null)
	await get_tree().create_timer(0.4).timeout
	assert(jobs.place_on_rack(jobs.rack.free_slot()))
	assert(str(rec.status) == "ready", "tamir edilen iş hazır olmadı")
	# teslim saati gelir, müşteri alır
	Game.clock = 12.0
	rec.due_abs = Game.now_abs() - 0.1
	jobs.call_pickup(rec)
	var ok: bool = await _wait_for(func(): return jobs.state == "waiting" and jobs.mode == "pickup", 60.0)
	assert(ok, "teslim müşterisi gelmedi")
	var m: int = Game.money
	assert(jobs.pick_up_device(rec, p) == "")
	jobs._customer_talk(p)
	assert(Game.money == m + int(rec.pay), "ödeme alınmadı")
	assert(Game.job_by_ticket(t).is_empty())
	print("OK bench: kasa tamiri, rafa koy, teslim")


## Laptop: ters çevir, bataryayı tepsiye sök, yenisini tak.
func _laptop_repair() -> void:
	Game.stock_dud.erase(Game.sku("lap_bat", 1))
	var d = jobs.dev_bench_job(jobs._make_job_of("device_laptop", "bat"))
	assert(d != null and Game.bench_device == d)
	assert(bench.kind == "laptop")
	assert(bench.enter())
	await _wait_state("on")
	bench.toggle_panel()
	assert(d.panel_open)
	var slot = d.slots.bat
	assert(bench.can_install(slot, slot.part).ok == false)
	var bad = bench.remove_part(slot)
	assert(bad != null and bad.broken and bench.tray_parts.has(bad))
	var good = main.PART.new().setup("lap_bat", 1, false)
	main.add_child(good)
	assert(bench.tray_add(good))
	assert(bench.select_part(good) and bench.install_selected(slot))
	assert(d.diagnose() == "ok")
	bench.toggle_panel()
	# mod açıkken cihaz taşınırsa (tezgâh null) temiz çıkış
	var rec: Dictionary = bench._job_rec()
	assert(not rec.is_empty())
	assert(jobs.pick_up_device(rec, p) == "")
	await get_tree().process_frame
	assert(bench.state == "off" and not Game.bench_active, "cihaz taşınınca mod kapanmadı")
	assert(get_viewport().get_camera_3d() == p.cam)
	assert(bench.tray_parts.is_empty() and bench.device == null)
	assert(jobs.place_on_rack(jobs.rack.free_slot()))
	print("OK bench: laptop tamiri, taşınınca çıkış")


## Müşteri cihazından çalışan parçayı kendi stoğuna alma (Cebe At) ve yakalanma / kaçma testi.
func _part_stealing() -> void:
	# 1) Çalışan parçayı cebe atıp muadille değiştirme -> yakalanmadan teslim
	Game.stock_dud.erase("gpu_entry_4g")
	var rec: Dictionary = jobs.drop_off(jobs._make_job_of("repair_gpu"))
	assert(not rec.is_empty())
	var pc = jobs.dev_to_bench(rec)
	assert(pc != null)
	assert(bench.enter())
	await _wait_state("on")
	pc.unscrew_all()
	bench.toggle_panel()
	# Bozuk GPU'yu sağlam stok GPU ile değiştir
	var bad_gpu = bench.remove_part(pc.slots.gpu)
	assert(bad_gpu != null)
	var good_gpu = main.PART.new().setup_sku("gpu_entry_4g", false)
	main.add_child(good_gpu)
	good_gpu.origin = "stock"
	assert(bench.tray_add(good_gpu) and bench.select_part(good_gpu) and bench.install_selected(pc.slots.gpu))
	# Çalışan müşteri RAM'ini sök -> cebe at -> yerine ucuz muadil RAM tak
	var cust_ram = bench.remove_part(pc.slots.ram1)
	assert(cust_ram != null and not cust_ram.broken and cust_ram.origin == "customer")
	var st0: int = Game.stock_of_sku(cust_ram.sku)
	var stolen0: int = int(Game.stats.get("stolen_parts", 0))
	assert(bench.pocket_tray_part(cust_ram), "müşteri parçası stoğa alınamadı")
	assert(Game.stock_of_sku("ram_ddr4_8g") == st0 + 1, "cebe atılan parça stoğa eklenmedi")
	assert(int(Game.stats.get("stolen_parts", 0)) == stolen0 + 1)
	var cheap_ram = main.PART.new().setup_sku("ram_ddr4_8g", false)
	cheap_ram.make_cheap()
	cheap_ram.origin = "stock"
	main.add_child(cheap_ram)
	assert(bench.tray_add(cheap_ram) and bench.select_part(cheap_ram) and bench.install_selected(pc.slots.ram1))
	bench.toggle_panel()
	pc.fasten_all()
	var audit: Dictionary = jobs.audit_parts(rec, pc)
	assert(not audit.stolen_items.is_empty(), "parça değişimi denetimde yakalanmadı")
	bench.exit()
	await _wait_state("off")
	assert(jobs.pick_up_device(rec, p) == "")
	await get_tree().create_timer(0.3).timeout
	jobs.theft_catch_override = 0.0
	jobs.call_pickup(rec)
	var ok1: bool = await _wait_for(func(): return jobs.state == "waiting" and jobs.mode == "pickup", 60.0)
	assert(ok1, "teslim müşterisi gelmedi")
	var m0: int = Game.money
	jobs._customer_talk(p)
	assert(Game.money > m0, "yakalanmadan teslimde ödeme alınmalı")

	# 2) Aynı senaryo bu kez teslimde yakalanır -> para cezası ve itibar düşüşü
	var rec2: Dictionary = jobs.drop_off(jobs._make_job_of("repair_gpu"))
	var pc2 = jobs.dev_to_bench(rec2)
	assert(pc2 != null and bench.enter())
	await _wait_state("on")
	pc2.unscrew_all()
	bench.toggle_panel()
	bench.remove_part(pc2.slots.gpu)
	var g2 = main.PART.new().setup_sku("gpu_entry_4g", false)
	g2.origin = "stock"
	main.add_child(g2)
	assert(bench.tray_add(g2) and bench.select_part(g2) and bench.install_selected(pc2.slots.gpu))
	var cr2 = bench.remove_part(pc2.slots.ram1)
	assert(bench.pocket_tray_part(cr2))
	var c2 = main.PART.new().setup_sku("ram_ddr4_8g", false)
	c2.make_cheap()
	c2.origin = "stock"
	main.add_child(c2)
	assert(bench.tray_add(c2) and bench.select_part(c2) and bench.install_selected(pc2.slots.ram1))
	bench.toggle_panel()
	pc2.fasten_all()
	bench.exit()
	await _wait_state("off")
	assert(jobs.pick_up_device(rec2, p) == "")
	await get_tree().create_timer(0.3).timeout
	jobs.theft_catch_override = 1.0
	jobs.call_pickup(rec2)
	var ok2: bool = await _wait_for(func(): return jobs.state == "waiting" and jobs.mode == "pickup", 60.0)
	assert(ok2, "teslim müşterisi #2 gelmedi")
	var m1: int = Game.money
	var r1: float = Game.rep
	jobs._customer_talk(p)
	assert(Game.money < m1 and Game.rep < r1, "yakalanınca ceza ve itibar düşüşü olmadı")
	jobs.theft_catch_override = -1.0
	print("OK bench: parça cebe atma, gizli/yakalanma teslimleri")


## Cihaz tezgâhtan gidince mod kapanır, tepsideki parçalar masaya serbest bırakılır.
func _bench_lost() -> void:
	await get_tree().create_timer(0.4).timeout
	var d = jobs.dev_bench_job(jobs._make_job_of("repair_gpu"))
	assert(d != null)
	assert(bench.enter())
	await _wait_state("on")
	var loose = main.PART.new().setup("cpu", 1, false)
	main.add_child(loose)
	assert(bench.tray_add(loose) and bench.select_part(loose))
	Game.set_bench_device(null)
	await get_tree().process_frame
	assert(bench.state == "off" and not Game.bench_active, "cihaz gidince mod kapanmadı")
	assert(get_viewport().get_camera_3d() == p.cam)
	assert(bench.tray_parts.is_empty() and bench.selected == null)
	assert(not loose.freeze and loose.get_parent() == main, "tepsi parçası serbest bırakılmadı")
	Game.set_bench_device(d)
	assert(bench.enter())
	await _wait_state("on")
	d.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(bench.state == "off" and not Game.bench_active, "silinen cihazda mod kapanmadı")
	Game.set_bench_device(null)
	print("OK bench: cihaz gidince çıkış")
