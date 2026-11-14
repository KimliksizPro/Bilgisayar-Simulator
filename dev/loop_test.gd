extends Node
## Geliştirici testi: `godot --headless -- --looptest` ile tam bir tamir döngüsünü dener.

func _ready() -> void:
	var main = get_parent()
	var jobs = main.get_children().filter(func(c): return c.has_method("_next_customer"))[0]
	var p = Game.player
	await get_tree().create_timer(0.5).timeout
	Game.save_path = "user://test_save.json"  # gerçek kaydı bozma
	Game.new_game()
	for type in ["psu", "cpu", "ram", "gpu", "ssd"]:
		print("bekleniyor: ", type)
		while jobs.state != "waiting":
			Game.clock = minf(Game.clock, 15.0)  # test sürerken dükkân kapanmasın
			await get_tree().create_timer(0.2).timeout
		var j: Dictionary = jobs._make_job()
		while j.kind != "repair" or j.broken != type:
			j = jobs._make_job()
		jobs.job = j
		jobs._customer_talk(p)
		var pc = jobs.pc
		assert(pc.diagnose() == ("nopower" if type == "psu" else type), "teşhis yanlış: " + pc.diagnose())
		pc.toggle_panel()
		var money_before: int = Game.money
		jobs._customer_talk(p)  # bitmeden teslim -> reddedilmeli
		assert(jobs.state == "working")
		var slot_name: String = "ram1" if type == "ram" else type
		if type == "ram" and pc.part_in("ram1") and not pc.part_in("ram1").broken:
			slot_name = "ram2"
		var slot = pc.slots[slot_name]
		slot.interact(p)  # sök
		assert(p.held != null and p.held.broken)
		main._bin_use(p)
		main._buy(p, type, 1)
		assert(p.held != null)
		slot.interact(p)  # tak
		assert(p.held == null and slot.part != null)
		pc.power_button()
		assert(pc.powered and pc.diagnose() == "ok")
		pc.toggle_panel()
		jobs._customer_talk(p)
		assert(jobs.state == "leaving", "teslim olmadı")
		print("OK %s: para %d -> %d" % [type, money_before, Game.money])
		await get_tree().create_timer(0.1).timeout
	await _supply_tests(main, jobs, p)
	await _device_tests(main, jobs, p)
	for kind in ["overheat_dust", "overheat_paste"]:
		print("bekleniyor: ", kind)
		while jobs.state != "waiting":
			Game.clock = minf(Game.clock, 15.0)  # test sürerken dükkân kapanmasın
			await get_tree().create_timer(0.2).timeout
		var j: Dictionary = jobs._make_job()
		while j.kind != kind:
			j = jobs._make_job()
		jobs.job = j
		jobs._customer_talk(p)
		var pc = jobs.pc
		assert(pc.diagnose() == "overheat", "teşhis yanlış: " + pc.diagnose())
		# 1) açılır, ısınır, kendi kendine kapanır
		pc.power_button()
		assert(pc.powered)
		await get_tree().create_timer(3.5).timeout
		assert(pc.cpu_temp > 50.0, "sıcaklık yükselmedi: %s" % pc.cpu_temp)
		await get_tree().create_timer(5.0).timeout
		assert(not pc.powered, "aşırı ısınınca kapanmadı")
		# teslim edilemez
		jobs._customer_talk(p)
		assert(jobs.state == "working", "arızalı bilgisayar teslim edildi")
		pc.toggle_panel()
		# 2) çözüm
		var tools := main.get_children().filter(func(c): return c.has_method("is_tool") and c.is_tool())
		assert(tools.size() == 2, "masada alet yok")
		if kind == "overheat_dust":
			var air = tools.filter(func(c): return c.tool_type == "air")[0]
			air.interact(p)
			assert(p.held == air)
			assert(pc.dust > 0.5)
			pc.slots.cpu.interact(p)  # yuvaya bakıp püskürt
			assert(pc.dust == 0.0, "toz temizlenmedi")
			p.drop()
		else:
			var cpu_slot = pc.slots.cpu
			cpu_slot.interact(p)  # CPU'yu sök
			assert(p.held != null and not p.held.paste_ok)
			var old_cpu = p.held
			p.release_held()
			old_cpu.queue_free()
			var paste = tools.filter(func(c): return c.tool_type == "paste")[0]
			paste.interact(p)
			assert(p.held == paste)
			cpu_slot.interact(p)  # boş sokete macun sür
			assert(pc.socket_paste)
			p.drop()
			main._buy(p, "cpu", 1)  # yeni CPU
			cpu_slot.interact(p)
			assert(cpu_slot.part != null and cpu_slot.part.paste_ok)
			assert(not pc.socket_paste)
		assert(pc.diagnose() == "ok", "çözümden sonra teşhis: " + pc.diagnose())
		pc.power_button()
		await get_tree().create_timer(6.0).timeout
		assert(pc.powered and pc.cpu_temp < 50.0, "sağlıklı bilgisayar ısındı: %s" % pc.cpu_temp)
		pc.toggle_panel()
		jobs._customer_talk(p)
		assert(jobs.state == "leaving", "teslim olmadı")
		print("OK %s" % kind)
		# aletleri masaya geri koy (sonraki iterasyon için)
		for t in tools:
			t.freeze = true
			t.global_position = Vector3(1.0, 0.8, -2.5)
		await get_tree().create_timer(0.1).timeout
	await _day_tests(jobs, p)
	print("TÜM TESTLER GEÇTİ")
	get_tree().quit()


## Gün sonu, itibar, geliştirme, kayıt ve iflas testleri.
func _day_tests(jobs, p) -> void:
	assert(Game.jobs_today >= 5 and Game.income_today > 0, "gün sayaçları")
	assert(Game.rep > 3.0, "itibar artmalıydı: %f" % Game.rep)
	# sabır: bekleyen müşteri çok beklerse kızıp gider
	while jobs.state != "waiting":
		Game.clock = minf(Game.clock, 15.0)  # test sürerken dükkân kapanmasın
		await get_tree().create_timer(0.2).timeout
	Game.running = true
	var rep_before: float = Game.rep
	jobs.wait_t = 1000.0
	jobs._process(0.1)
	assert(jobs.state == "leaving" and Game.rep < rep_before, "sabır testi")
	Game.running = false
	print("OK sabır: itibar %.2f -> %.2f" % [rep_before, Game.rep])
	# geliştirmeler
	var base_price: int = Game.price_of("cpu", 1)
	Game.add_money(2000)
	assert(Game.buy_upgrade("wholesale") and Game.price_of("cpu", 1) < base_price, "toptan")
	assert(Game.buy_upgrade("coffee") and Game.patience_mult() == 1.5, "kahve")
	assert(not Game.buy_upgrade("coffee"), "çift alım")
	print("OK geliştirmeler: cpu %d -> %d" % [base_price, Game.price_of("cpu", 1)])
	# kapanış -> gün sonu özeti
	while jobs.state != "none" and jobs.state != "closed":
		await get_tree().create_timer(0.2).timeout
	Game.clock = Game.CLOSE_HOUR
	var m: int = Game.money
	var d: int = Game.day
	while Game.phase != "summary":
		await get_tree().create_timer(0.2).timeout
	assert(Game.money == m - Game.BASE_RENT, "kira düşmedi")
	assert(Game.has_save(), "otomatik kayıt yok")
	print("OK gün sonu: gün %d, kasa %d -> %d" % [d, m, Game.money])
	# kayıt yükleme
	var saved_money: int = Game.money
	Game.money = 1
	Game.upgrades = {}
	assert(Game.continue_game() and Game.money == saved_money and Game.has_upgrade("coffee") and Game.day == d + 1, "yükleme")
	assert(Game.clock == Game.OPEN_HOUR and Game.phase == "day")
	print("OK kayıt/yükleme")
	# iflas: iki gün üst üste eksi
	Game.money = -500
	Game.end_day()
	assert(Game.phase == "summary" and Game.debt_days == 1)
	Game.phase = "day"
	Game.end_day()
	assert(Game.phase == "over", "iflas")
	DirAccess.remove_absolute(Game.save_path)
	print("OK iflas")


## Stok, ParçaNet siparişi, kurye teslimatı, rafa geri koyma ve tezgah satışı.
func _supply_tests(main, jobs, p) -> void:
	# 5 tamirden sonra CPU stoğu bitti
	assert(Game.stock_of("cpu", 1) == 0, "cpu stoğu: %d" % Game.stock_of("cpu", 1))
	main._buy(p, "cpu", 1)
	assert(p.held == null, "stok yokken parça alındı")
	# sipariş: 2 CPU + 5 RAM 16 GB (toplu indirim) ekspres
	Game.add_money(1000)
	var m: int = Game.money
	var items := {"cpu:1": 2, "ram:2": 5}
	var sub: int = Game.cart_subtotal(items)
	assert(sub < Game.price_of("cpu", 1) * 2 + Game.price_of("ram", 2) * 5, "toplu indirim yok")
	assert(Game.place_order(items, true), "sipariş verilemedi")
	assert(Game.money == m - sub - Game.SHIP_EXP_FEE, "sipariş ücreti yanlış")
	assert(Game.orders.size() == 1 and Game.due_orders().is_empty(), "sipariş hemen geldi")
	Game.clock += Game.SHIP_EXP_HOURS + 0.01
	assert(Game.due_orders().size() == 1, "varış zamanı")
	main.delivery._send_courier()
	var t := 0.0
	while main.delivery.boxes.is_empty() and t < 20.0:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	assert(not main.delivery.boxes.is_empty(), "kurye koliyi bırakmadı")
	var id: int = main.delivery.boxes.keys()[0]
	main.delivery.open_box(id, p)
	assert(Game.stock_of("cpu", 1) == 2 and Game.stock_of("ram", 2) == 5 and Game.orders.is_empty(), "koli stoğa girmedi")
	print("OK sipariş + kurye: %d TL, stok cpu=%d ram16=%d" % [sub, Game.stock_of("cpu", 1), Game.stock_of("ram", 2)])
	# rafa geri koy
	main._buy(p, "ram", 2)
	assert(p.held != null and Game.stock_of("ram", 2) == 4)
	main._shelf_use(p, "ram", 2)
	assert(p.held == null and Game.stock_of("ram", 2) == 5, "rafa geri konmadı")
	print("OK rafa geri koyma")
	# tezgah satışı
	while jobs.state != "waiting":
		Game.clock = minf(Game.clock, 15.0)  # test sürerken dükkân kapanmasın
		await get_tree().create_timer(0.2).timeout
	var j: Dictionary = jobs._make_job()
	while j.kind != "sale" or j.want != ["ram", 2]:
		j = jobs._make_job()
	jobs.job = j
	jobs._customer_talk(p)  # elinde parça yok -> satış olmaz
	assert(jobs.state == "waiting", "eli boşken satış oldu")
	main._buy(p, "ram", 2)
	var mm: int = Game.money
	jobs._customer_talk(p)
	assert(jobs.state == "leaving" and p.held == null and Game.money == mm + int(j.pay), "satış olmadı")
	assert(int(j.pay) > Game.price_of("ram", 2), "satışta kâr yok")
	print("OK tezgah satışı: +%d TL (alış %d)" % [j.pay, Game.price_of("ram", 2)])
	# kayıt: stok ve yoldaki sipariş saklanır
	assert(Game.place_order({"ssd:1": 1}, false))
	Game.save_game()
	var st: int = Game.stock_of("ram", 2)
	Game.stock = {}
	Game.orders = []
	assert(Game.load_game() and Game.stock_of("ram", 2) == st and Game.orders.size() == 1, "stok/sipariş kaydı")
	print("OK stok ve sipariş kaydı")


## Laptop ve telefon tamiri: her arıza için iş zorla, teşhis et, parçayı değiştir, teslim et.
func _device_tests(main, jobs, p) -> void:
	var cases := [["laptop", "bat"], ["laptop", "ssd"], ["laptop", "ram"], ["laptop", "scr"],
		["phone", "bat"], ["phone", "port"], ["phone", "scr"]]
	var screens := {"laptop": {"bat": "bat", "ssd": "noboot", "ram": "bsod", "scr": "glitch"},
		"phone": {"bat": "lowbat", "port": "port", "scr": "glitch"}}
	for c in cases:
		var dev: String = c[0]
		var broken: String = c[1]
		print("bekleniyor: ", dev, " ", broken)
		while jobs.state != "waiting":
			Game.clock = minf(Game.clock, 15.0)  # test sürerken dükkân kapanmasın
			await get_tree().create_timer(0.2).timeout
		var j: Dictionary = jobs._make_job()
		while j.get("device", "") != dev or j.broken != broken:
			j = jobs._make_job()
		jobs.job = j
		jobs._customer_talk(p)  # kabul
		var d = jobs.pc
		assert(d != null and d.has_method("slot_open"), "cihaz masaya gelmedi")
		assert(d.diagnose() == broken, "teşhis yanlış: " + d.diagnose())
		assert(Game.stock_of(d.slots[broken].accepts, 1) > 0, "başlangıç stoğu yok: " + d.slots[broken].accepts)
		# güç: kendi ekranında belirti
		d.power_button()
		assert(d.powered, "cihaz açılmadı")
		await get_tree().create_timer(1.6).timeout
		var want: String = screens[dev][broken]
		assert(d.screen_state == want or (want == "lowbat" and d.screen_state == "off"), "ekran durumu %s, beklenen %s" % [d.screen_state, want])
		if d.powered:
			d.power_button()  # kapat
		assert(not d.powered)
		jobs._customer_talk(p)  # bitmeden teslim -> reddedilmeli
		assert(jobs.state == "working", "arızalı cihaz teslim edildi")
		var slot = d.slots[broken]
		if not d.slot_open(slot):
			d.toggle_panel()
		assert(d.slot_open(slot), "yuva açılmadı")
		slot.interact(p)  # sök
		assert(p.held != null and p.held.broken, "bozuk parça alınamadı")
		var type: String = slot.accepts
		main._bin_use(p)
		main._buy(p, type, 1)
		assert(p.held != null and p.held.part_type == type, "raftan parça alınamadı")
		slot.interact(p)  # tak
		assert(p.held == null and slot.part != null and not slot.part.broken)
		assert(d.diagnose() == "ok", "tamirden sonra teşhis: " + d.diagnose())
		if d.panel_open:
			jobs._customer_talk(p)  # kapak açık -> reddedilmeli
			assert(jobs.state == "working", "kapak açıkken teslim edildi")
			d.toggle_panel()
		d.power_button()
		await get_tree().create_timer(1.4).timeout
		assert(d.powered and d.screen_state == ("desktop" if dev == "laptop" else "home"), "sağlam açılmadı: " + d.screen_state)
		var m: int = Game.money
		jobs._customer_talk(p)
		assert(jobs.state == "leaving", "teslim olmadı")
		assert(Game.money == m + int(j.pay), "ödeme alınmadı")
		print("OK %s %s: +%d TL" % [dev, broken, j.pay])
		await get_tree().create_timer(0.1).timeout
	# katalog ve stok rafı
	for t in ["lap_ram", "lap_ssd", "lap_bat", "lap_scr", "tel_bat", "tel_scr", "tel_port"]:
		assert(Game.CATALOG.has([t, 1]), "katalogda yok: " + t)
		assert(main._price_labels.any(func(e): return e[2] == t), "rafta yok: " + t)
	print("OK laptop/telefon katalog ve raf")
