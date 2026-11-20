extends Node
## Geliştirici testi: `godot --headless -- --multijobtest` çoklu iş akışını sınar:
## 3 bırakma + kapasite sınırı + geri çevirme, cihaz taşıma, tamir, hazır işareti, kayıt/yükleme (iş ve parça durumu),
## gün geçişinde kalıcılık, v2 kayıt göçü, teslim müşterisi: yanlış cihaz, doğru cihaz, gecikme kuralı.

const ST := preload("res://scripts/job_store.gd")
var fails: Array = []
var bench_events := 0


func _ready() -> void:
	var main = get_parent()
	await get_tree().create_timer(0.5).timeout
	Engine.time_scale = 4.0
	var jobs = Game.job_mgr
	var p = Game.player
	Game.save_path = "user://test_save_multi.json"
	_wipe()
	jobs.arrivals_enabled = false
	jobs.force_express = 0
	Game.new_game()
	Game.bench_changed.connect(func(_d): bench_events += 1)
	for t in ["psu", "cpu", "ram"]:
		Game.add_stock(t, 1, 3)
	await _due_mapping()
	await _dropoffs(main, jobs, p)
	await _carry_and_repair(main, jobs, p)
	await _save_load(main, jobs, p)
	await _day_change(jobs)
	await _pickups(main, jobs, p)
	await _migration(jobs)
	_wipe()
	if fails.is_empty():
		print("MULTIJOBTEST OK")
		get_tree().quit()
	else:
		print("MULTIJOBTEST BAŞARISIZ: ", fails)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("BAŞARISIZ: ", what)


func _wait_for(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		if t > limit:
			return false
	return true


## Teslim zamanı eşlemesi: tamir ertesi gün 10-18, toplama 2 gün, ekspres +3 saat (aynı gün).
func _due_mapping() -> void:
	var jm = Game.job_mgr
	var now := Game.day * 24.0 + 9.0
	var rj: Dictionary = jm._make_job_of("repair_psu")
	var d1 := ST.make_due(rj, now, 0)
	_check(not d1.express and int(d1.due_abs / 24.0) == Game.day + 1 and fposmod(d1.due_abs, 24.0) >= 10.0 and fposmod(d1.due_abs, 24.0) <= 18.0, "tamir ertesi gün 10-18")
	var bj: Dictionary = jm._make_job_of("build")
	var d2 := ST.make_due(bj, now, 1)
	_check(not d2.express and int(d2.due_abs / 24.0) == Game.day + 2, "toplama 2 gün (ekspres olmaz)")
	var d3 := ST.make_due(rj, now, 1)
	_check(d3.express and is_equal_approx(d3.due_abs, now + 3.0), "ekspres +3 saat")
	var late := ST.make_due(rj, Game.day * 24.0 + 17.0, 1)
	_check(not late.express, "geç saatte ekspres yok")
	_check(ST.due_label(d1.due_abs, Game.day).begins_with("Yarın"), "etiket Yarın")
	_check(ST.when_phrase(d1.due_abs, Game.day).begins_with("Yarın"), "söz Yarın")
	print("OK teslim zamanı eşlemesi")


## 3 müşteri sıraya girer, kabul edilir; dördüncü için raf dolu: geri çevrilir (itibar kaybı yok).
func _dropoffs(_main, jobs, p) -> void:
	jobs.force_jobs = [jobs._make_job_of("repair_psu"), jobs._make_job_of("repair_cpu"), jobs._make_job_of("repair_ram")]
	for i in 3:
		jobs._spawn_arrival()
	_check(jobs.queue.size() == 3, "kuyruk 3 müşteri")
	var ok: bool = await _wait_for(func(): return jobs.state == "waiting", 60.0)
	_check(ok, "ilk müşteri tezgâha gelmedi")
	jobs._talk(jobs.queue[1], p)  # sıradakine konuşmak işe yaramaz
	_check(Game.jobs_active.is_empty(), "sıradaki müşteri kabul edildi")
	for i in 3:
		var okk: bool = await _wait_for(func(): return jobs.state == "waiting", 60.0)
		_check(okk, "müşteri %d gelmedi" % i)
		jobs._customer_talk(p)
		await get_tree().create_timer(0.1).timeout
	_check(Game.jobs_active.size() == 3, "3 iş kabul edilmedi: %d" % Game.jobs_active.size())
	var tickets := Game.jobs_active.map(func(r): return int(r.ticket))
	_check(tickets == [101, 102, 103], "fiş numaraları %s" % str(tickets))
	_check(jobs.devices.size() == 3 and jobs.rack.occ.count(0) == 3, "cihazlar rafta değil")
	for r in Game.jobs_active:
		_check(str(r.status) == "waiting_bench" and str(r.location).begins_with("rack:"), "iş durumu/yeri")
		_check(float(r.due_abs) > Game.now_abs(), "teslim zamanı geçmişte")
	# raf dolu: dördüncü müşteri
	jobs.force_jobs = [jobs._make_job_of("repair_gpu")]
	jobs._spawn_arrival()
	var ok4: bool = await _wait_for(func(): return jobs.state == "waiting", 60.0)
	_check(ok4, "4. müşteri gelmedi")
	var rep_b: float = Game.rep
	_check(not jobs._accept(), "raf doluyken kabul edildi")
	_check(Game.jobs_active.size() == 3, "kapasite aşıldı")
	_check(jobs.decline_head() and is_equal_approx(Game.rep, rep_b), "raf doluyken geri çevirme itibar kaybettirdi")
	await _wait_for(func(): return jobs.queue.is_empty(), 20.0)
	# HUD listesi
	Game.hud._rebuild_jobs()
	_check(Game.hud._jobs_box.get_child_count() == 3, "HUD listesinde 3 satır olmalı")
	print("OK 3 bırakma, kapasite sınırı, geri çevirme, fiş numaraları")


## İş 2'yi tezgâha taşı (Game.bench_device), tamir et, rafa koy: hazır. Tamamlanmamış iş rafa konunca hazır olmaz.
func _carry_and_repair(main, jobs, p) -> void:
	var r1: Dictionary = Game.job_by_ticket(101)
	var r2: Dictionary = Game.job_by_ticket(102)
	var ev: int = bench_events
	_check(jobs.pick_up_device(r2, p) == "" and jobs.carry.active() and Game.is_carrying(), "cihaz alınamadı")
	_check(jobs.pick_up_device(r1, p) == "elin dolu", "taşırken ikinci cihaz alındı")
	_check(jobs.rack.occ.count(0) == 4, "alınan gözün boşalması")
	_check(not Game.player.held, "oyuncunun elinde parça")
	await get_tree().create_timer(0.35).timeout
	_check(jobs.place_on_bench() and Game.bench_device == jobs.devices[102], "tezgâha konmadı")
	_check(bench_events == ev + 1 and str(r2.status) == "on_bench" and str(r2.location) == "bench", "tezgâh sözleşmesi")
	var pc = Game.bench_device
	await get_tree().create_timer(0.35).timeout
	pc.toggle_panel()
	var slot = pc.slots.cpu
	slot.interact(p)  # sök
	_check(p.held != null and p.held.broken, "bozuk işlemci alınamadı")
	main._bin_use(p)
	main._buy(p, "cpu", 1)
	slot.interact(p)  # tak
	_check(slot.part != null and not slot.part.broken and pc.diagnose() == "ok", "işlemci takılmadı")
	pc.toggle_panel()
	_check(jobs.pick_up_device(r2, p) == "" and Game.bench_device == null and bench_events == ev + 2, "tezgâhtan alma / null sözleşmesi")
	var slot_i: int = jobs.rack.free_slot()
	_check(jobs.place_on_rack(slot_i), "rafa konmadı")
	_check(str(r2.status) == "ready" and str(r2.location) == "rack:%d" % slot_i, "tamir edilen iş hazır olmadı")
	# tamamlanmamış iş: tezgâha al, bozukken rafa koy -> hazır değil
	_check(jobs.pick_up_device(r1, p) == "", "iş 1 alınamadı")
	await get_tree().create_timer(0.35).timeout
	jobs.place_on_bench()
	await get_tree().create_timer(0.35).timeout
	_check(jobs.pick_up_device(r1, p) == "", "iş 1 tezgâhtan alınamadı")
	await get_tree().create_timer(0.35).timeout
	jobs.place_on_rack(jobs.rack.free_slot())
	_check(str(r1.status) == "waiting_bench", "bozuk iş hazır sayıldı")
	# tezgâh değişimi: iş 1'i tekrar tezgâha koy, psu'yu sök (kayıt testi için yarım iş)
	jobs.pick_up_device(r1, p)
	await get_tree().create_timer(0.35).timeout
	jobs.place_on_bench()
	await get_tree().create_timer(0.35).timeout
	var pc1 = Game.bench_device
	pc1.toggle_panel()
	pc1.slots.psu.interact(p)
	main._bin_use(p)
	_check(pc1.slots.psu.part == null, "psu sökülmedi")
	# iş 3: toz ve kuru macun (parça durumu kayda girsin)
	var pc3 = jobs.devices[103]
	pc3.set_dust(0.77)
	pc3.slots.cpu.part.paste_ok = false
	print("OK taşıma, tezgâh sözleşmesi, hazır kuralı")


func _states() -> Dictionary:
	var out := {}
	for t in Game.job_mgr.devices:
		var d = Game.job_mgr.devices[t]
		var st: Dictionary = ST.snapshot(d)
		var parts: Array = st.parts.duplicate(true)
		parts.sort_custom(func(a, b): return str(a[0]) < str(b[0]))
		out[t] = {"parts": parts, "dust": snappedf(st.dust, 0.01), "paste": st.socket_paste}
	return out


## Kayıt: iş listesi + cihaz parça durumu; yükleyince cihazlar yeniden kurulur.
func _save_load(_main, jobs, _p) -> void:
	var before := _states()
	var recs_before := Game.jobs_active.map(func(r): return [int(r.ticket), str(r.status), str(r.location), snappedf(float(r.due_abs), 0.01), int(r.pay)])
	Game.save_game()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	_check(int(d.version) == Game.SAVE_VERSION and d.jobs.size() == 3 and int(d.next_ticket) == 104, "kayıt dosyası jobs/next_ticket/versiyon")
	Game.jobs_active = []
	Game.next_ticket = 1
	_check(Game.load_game(), "yükleme")
	_check(Game.jobs_active.size() == 3 and Game.next_ticket == 104, "yüklenen iş sayısı / fiş sayacı")
	var recs_after := Game.jobs_active.map(func(r): return [int(r.ticket), str(r.status), str(r.location), snappedf(float(r.due_abs), 0.01), int(r.pay)])
	_check(recs_after == recs_before, "iş kayıtları değişti: %s vs %s" % [str(recs_before), str(recs_after)])
	_check(jobs.devices.size() == 3, "cihazlar yeniden kurulmadı")
	var after := _states()
	_check(after == before, "cihaz durumu değişti:\n%s\n%s" % [str(before), str(after)])
	_check(Game.bench_device == jobs.devices[101], "tezgâhtaki cihaz geri gelmedi")
	_check(is_equal_approx(jobs.devices[103].dust, 0.77) and not jobs.devices[103].slots.cpu.part.paste_ok, "toz/macun durumu")
	_check(jobs.devices[101].slots.psu.part == null, "sökülü psu geri geldi")
	_check(str(Game.job_by_ticket(102).status) == "ready", "hazır durumu kayboldu")
	print("OK kayıt/yükleme: iş listesi ve cihaz durumları")


## Gün geçişi: açık işler cihazlarıyla birlikte ertesi güne kalır.
func _day_change(jobs) -> void:
	var before := _states()
	Game.clock = Game.CLOSE_HOUR
	var ok: bool = await _wait_for(func(): return Game.phase == "summary", 10.0)
	_check(ok, "gün sonu özeti açılmadı")
	_check(Game.jobs_active.size() == 3, "gün sonunda işler silindi")
	Game.next_day()
	await get_tree().create_timer(0.3).timeout
	_check(Game.day == 2 and Game.jobs_active.size() == 3 and jobs.devices.size() == 3, "ertesi gün işler yok")
	_check(_states() == before, "gece cihaz durumu değişti")
	_check(Game.bench_device == jobs.devices[101], "tezgâh cihazı ertesi gün yok")
	print("OK gün geçişinde kalıcılık")


## Teslim müşterileri: yanlış cihaz, doğru cihaz, gecikme (ek gün, sonra cihazı alıp gitme).
func _pickups(main, jobs, p) -> void:
	Game.clock = 18.5  # üç işin de teslim saati geçti
	var ok: bool = await _wait_for(func(): return jobs.queue.size() == 3 and jobs.state == "waiting", 60.0)
	_check(ok, "teslim müşterileri gelmedi (%d)" % jobs.queue.size())
	_check(jobs.mode == "pickup" and int(jobs.queue[0].rec.ticket) == 101, "baştaki müşteri #101 değil")
	var r2: Dictionary = Game.job_by_ticket(102)
	# yanlış cihaz: #102'yi #101 müşterisine ver
	var rep_b: float = Game.rep
	_check(jobs.pick_up_device(r2, p) == "", "iş 2 alınamadı")
	jobs._customer_talk(p)
	_check(Game.rep < rep_b and Game.jobs_active.size() == 3 and jobs.queue[0].wrong == 1, "yanlış cihaz cezası")
	await get_tree().create_timer(0.3).timeout
	jobs.return_carried()
	await get_tree().create_timer(0.3).timeout
	_check(str(r2.status) == "ready" and str(r2.location).begins_with("rack:"), "iş 2 rafa dönmedi")
	# #101 hâlâ psu'suz: taşıyıp verirsek reddedilir
	var r1: Dictionary = Game.job_by_ticket(101)
	var money_b: int = Game.money
	jobs.pick_up_device(r1, p)
	jobs._customer_talk(p)
	_check(Game.money == money_b and Game.jobs_active.size() == 3, "bozuk cihaz teslim edildi")
	jobs.return_carried()
	await get_tree().create_timer(0.4).timeout
	# tamir et (psu tak), doğru cihazı ver
	var pc1 = Game.bench_device
	pc1.toggle_panel()
	main._buy(p, "psu", 1)
	pc1.slots.psu.interact(p)
	pc1.toggle_panel()
	_check(pc1.diagnose() == "ok", "psu takılınca teşhis")
	jobs.pick_up_device(r1, p)
	jobs._customer_talk(p)
	_check(Game.jobs_active.size() == 2 and Game.money == money_b + int(r1.pay), "doğru cihaz ödenmedi")
	_check(Game.job_by_ticket(101).is_empty(), "teslim edilen iş listede")
	await _wait_for(func(): return jobs.state == "waiting" and int(jobs.queue[0].rec.ticket) == 102, 20.0)
	# #102 hazır: rafta, getir, ver
	money_b = Game.money
	_check(jobs.pick_up_device(r2, p) == "", "iş 2 alınamadı (2)")
	jobs._customer_talk(p)
	_check(Game.jobs_active.size() == 1 and Game.money == money_b + int(r2.pay), "hazır cihaz ödenmedi")
	await _wait_for(func(): return jobs.state == "waiting" and int(jobs.queue[0].rec.ticket) == 103, 20.0)
	# #103 hazır değil: sabır biter -> bir gün ek (itibar -0.2); ertesi gün yine hazır değil -> cihazı alıp gider
	var r3: Dictionary = Game.job_by_ticket(103)
	var due_b: float = float(r3.due_abs)
	rep_b = Game.rep
	Game.running = true
	jobs.queue[0].wait_t = 1.0e6
	jobs._process(0.1)
	Game.running = false
	_check(Game.jobs_active.size() == 1 and is_equal_approx(float(r3.due_abs), due_b + 24.0) and int(r3.ext) == 1, "ek gün verilmedi")
	_check(Game.rep < rep_b and jobs.queue.is_empty(), "ek gün itibar cezası / sıra")
	_check(not r3.called, "çağrı işareti sıfırlanmadı")
	Game.day += 1  # ertesi gün
	Game.clock = 18.5
	await _wait_for(func(): return jobs.state == "waiting" and jobs.mode == "pickup", 60.0)
	money_b = Game.money
	rep_b = Game.rep
	Game.running = true
	jobs.queue[0].wait_t = 1.0e6
	jobs._process(0.1)
	Game.running = false
	_check(Game.jobs_active.is_empty() and Game.money == money_b and Game.rep < rep_b - 0.4, "ikinci gecikmede cihaz alınmadı")
	await _wait_for(func(): return jobs.queue.is_empty(), 20.0)
	_check(jobs.devices.is_empty() and jobs.rack.occ.count(0) == 6, "cihaz/raf temizlenmedi")
	print("OK teslim: yanlış cihaz, doğru cihaz, gecikme kuralları")


## Eski (v2) kayıt: iş listesi yok, yüklenir.
func _migration(jobs) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	d["version"] = 2
	d.erase("jobs")
	d.erase("next_ticket")
	var f := FileAccess.open(Game.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	Game.jobs_active = [{"ticket": 5}]
	_check(Game.load_game() and Game.jobs_active.is_empty() and Game.next_ticket == 101, "v2 kaydı göçü")
	_check(jobs.devices.is_empty(), "v2 kaydından sonra cihaz kaldı")
	print("OK v2 kayıt göçü")


func _wipe() -> void:
	for p in [Game.save_path, Game.save_path + ".bak", Game.save_path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
