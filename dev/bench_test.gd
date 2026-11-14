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


func _wait_job() -> void:
	while jobs.state != "waiting":
		Game.clock = minf(Game.clock, 15.0)
		await get_tree().create_timer(0.2).timeout


func _accept(id: String, broken := "") -> Object:
	await _wait_job()
	jobs.job = jobs._make_job_of(id, broken)
	jobs._customer_talk(p)
	var d = jobs.pc
	assert(d != null and Game.bench_device == d, "cihaz tezgâha gelmedi")
	return d


func _ready() -> void:
	main = get_parent()
	jobs = main.get_children().filter(func(c): return c.has_method("_next_customer"))[0]
	p = Game.player
	bench = main.bench
	await get_tree().create_timer(0.5).timeout
	Game.save_path = "user://test_save.json"
	Game.new_game()
	assert(bench != null and bench.state == "off")
	await _pc_repair()
	await _laptop_repair()
	await _bench_lost()
	print("BENCHTEST OK")
	get_tree().quit()


## Kasa: elde parça ile giriş (tepsiye iner), kapağı aç, bozuk RAM'i sök, sağlamı tak, dene, çık, teslim et.
func _pc_repair() -> void:
	var pc = await _accept("repair_ram")
	assert(bench.device == pc and bench.kind == "pc")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var can_capture: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED  # başsız sürücüde fare yakalanmayabilir
	main._buy(p, "ram", 1)
	var good = p.held
	assert(good != null and not good.broken)
	var clock0: float = Game.clock
	assert(bench.enter(), "tezgâh moduna girilemedi")
	assert(not get_tree().paused and not Game.paused, "tezgâh modu oyunu durdurmamalı")
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and Game.bench_active)
	assert(p.held == null and bench.tray_parts.has(good), "elde tutulan parça tepsiye inmedi")
	await _wait_state("on")
	assert(get_viewport().get_camera_3d() == bench.cam, "yörünge kamera aktif değil")
	await get_tree().create_timer(0.6).timeout
	assert(Game.clock > clock0, "tezgâh modunda saat akmadı")
	# fare ışını camı bulmalı
	var gp: Vector3 = pc.global_transform * Vector3(pc.W / 2.0 - 0.002, pc.H / 2.0, 0.0)
	var sp: Vector2 = bench.cam.unproject_position(gp)
	assert(not bench.cam.is_position_behind(gp))
	var res: Dictionary = bench._resolve(bench._ray_hit(sp))
	assert(res.get("kind", "") == "widget", "cam kapak fareyle bulunamadı: %s" % [res])
	bench.click(res)  # cam kapağa sol tık
	assert(pc.panel_open, "kapak açılmadı")
	# bozuk parçayı sök (tepsiye)
	var slot = pc.slots.ram1
	if pc.part_in("ram1") == null or not pc.part_in("ram1").broken:
		slot = pc.slots.ram2
	var bad = slot.part
	assert(bad != null and bad.broken)
	assert(bench.remove_part(slot) == bad, "söküm başarısız")
	assert(slot.part == null and bench.tray_parts.has(bad) and bad.get_parent() == bench._tray, "bozuk parça tepsiye inmedi")
	assert(bench.tray_parts.size() == 2)
	# uyumluluk kancası
	assert(bench.can_install(pc.slots.cpu, good).ok == false, "dolu yuva uyumlu görünüyor")
	assert(bench.can_install(pc.slots.gpu, good).ok == false)
	assert(bench.can_install(slot, good).ok == true)
	# tepsiden seç, yuvalar yansın
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
	assert(pc.diagnose() == "ok", "tamirden sonra teşhis: " + pc.diagnose())
	bench.press_power()
	assert(pc.powered)
	bench.toggle_panel()
	assert(not pc.panel_open)
	# Esc ile çık
	bench.exit()
	await _wait_state("off")
	assert(not Game.bench_active and get_viewport().get_camera_3d() == p.cam, "birinci şahıs kameraya dönülmedi")
	assert(not can_capture or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "fare geri yakalanmadı")
	var m: int = Game.money
	jobs._customer_talk(p)
	assert(jobs.state == "leaving", "teslim olmadı")
	assert(Game.money > m)
	await get_tree().process_frame
	assert(bench.device == null or not is_instance_valid(bench.device) or Game.bench_device == null)
	print("OK bench: kasa tamiri")


## Laptop: ters çevir, bataryayı tepsiye sök, yenisini tak.
func _laptop_repair() -> void:
	for t in ["lap_bat"]:
		Game.stock_dud.erase(Game.sku(t, 1))
		if Game.stock_of(t, 1) < 1:
			Game.add_stock(t, 1, 1)
	var d = await _accept("device_laptop", "bat")
	assert(bench.kind == "laptop")
	assert(bench.enter())
	await _wait_state("on")
	bench.toggle_panel()  # ters çevir
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
	bench.exit()
	await _wait_state("off")
	jobs._customer_talk(p)
	assert(jobs.state == "leaving", "laptop teslim olmadı")
	print("OK bench: laptop tamiri")


## Cihaz tezgâhtan gidince mod kapanır, tepsideki parçalar masaya serbest bırakılır.
func _bench_lost() -> void:
	var d = await _accept("repair_gpu")
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
	assert(bench.device == null)
	# silinen cihaz da modu kapatmalı
	Game.set_bench_device(d)
	assert(bench.enter())
	await _wait_state("on")
	d.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(bench.state == "off" and not Game.bench_active, "silinen cihazda mod kapanmadı")
	Game.set_bench_device(null)
	print("OK bench: cihaz gidince çıkış")
