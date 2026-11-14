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
	await _eco_tests(main, jobs, p)
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
	await _staff_tests(main, jobs)
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
	var bill: int = Game.utility_bill()
	assert(bill >= 20 and bill <= 60, "elektrik faturası aralık dışı: %d" % bill)
	assert(Game.money == m - Game.BASE_RENT - bill, "kira + elektrik düşmedi")
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


## Muadil parça, garanti dönüşü, ikinci el pazarı, elektrik faturası ve ekonomi kaydı.
func _eco_tests(main, jobs, p) -> void:
	Game.add_money(2000)
	# 1) muadil sipariş: daha ucuz, muadil stoğuna girer
	assert(Game.price_of("psu", 1, true) < Game.price_of("psu", 1), "muadil ucuz değil")
	assert(Game.cart_subtotal({"psu:1:c": 2}) == Game.price_of("psu", 1, true) * 2, "muadil sepet tutarı")
	var m: int = Game.money
	var oc: int = Game.stock_cheap_of("psu", 1)
	var on: int = Game.stock_of("psu", 1)
	assert(Game.place_order({"psu:1:c": 2, "psu:1": 1}, true))
	assert(Game.money == m - Game.cart_subtotal({"psu:1:c": 2, "psu:1": 1}) - Game.SHIP_EXP_FEE, "muadil sipariş ücreti")
	Game.receive_order(int(Game.orders.back().id))
	assert(Game.stock_cheap_of("psu", 1) == oc + 2 and Game.stock_of("psu", 1) == on + 1, "muadil stoğa girmedi")
	print("OK muadil sipariş: orijinal %d TL, muadil %d TL" % [Game.price_of("psu", 1), Game.price_of("psu", 1, true)])
	# 2) raftan muadil al / geri koy
	main._buy(p, "psu", 1, true)
	assert(p.held != null and p.held.cheap and "muadil" in p.held.display_name and Game.stock_cheap_of("psu", 1) == oc + 1)
	main._shelf_use(p, "psu", 1)
	assert(p.held == null and Game.stock_cheap_of("psu", 1) == oc + 2, "muadil rafa geri konmadı")
	print("OK raftan muadil alma ve geri koyma")
	# 3) garanti: muadil parçalı teslim -> geri dönüş işi
	while jobs.state != "waiting":
		Game.clock = minf(Game.clock, 15.0)
		await get_tree().create_timer(0.2).timeout
	var j: Dictionary = jobs._make_job()
	while j.kind != "repair" or j.broken != "psu":
		j = jobs._make_job()
	jobs.job = j
	jobs._customer_talk(p)
	var pc = jobs.pc
	pc.toggle_panel()
	var slot = pc.slots.psu
	slot.interact(p)
	main._bin_use(p)
	main._buy(p, "psu", 1, true)  # muadil tak
	slot.interact(p)
	pc.power_button()
	pc.toggle_panel()
	Game.warranty_chance = 1.0
	var cname: String = jobs.job.name
	jobs._customer_talk(p)
	assert(jobs.state == "leaving", "teslim olmadı")
	assert(Game.warranty_list.size() == 1 and Game.warranty_list[0].type == "psu", "garanti riski kaydedilmedi")
	assert(int(Game.warranty_list[0].due) > Game.day and int(Game.warranty_list[0].due) <= Game.day + 2, "garanti günü")
	Game.warranty_chance = Game.WARRANTY_CHANCE
	print("OK garanti riski kaydedildi: %s, gün %d" % [Game.warranty_list[0].name, Game.warranty_list[0].due])
	# kayıt: ekonomi verisi saklanır
	Game.save_game()
	Game.warranty_list = []
	Game.stock_cheap = {}
	assert(Game.load_game() and Game.warranty_list.size() == 1 and Game.stock_cheap_of("psu", 1) == oc + 1, "ekonomi kaydı")
	print("OK ekonomi kaydı/yükleme")
	while jobs.state != "waiting":
		Game.clock = minf(Game.clock, 15.0)
		await get_tree().create_timer(0.2).timeout
	Game.warranty_list[0].due = Game.day  # günü gelsin (müşteri çoktan geldi; iş şimdi üretilir)
	j = jobs._make_job()
	assert(j.kind == "warranty" and j.pay == 0 and j.broken == "psu" and Game.warranty_list.is_empty(), "garanti işi üretilmedi")
	jobs.job = j
	jobs._customer_talk(p)
	pc = jobs.pc
	assert(pc.diagnose() == "nopower", "garanti işinde teşhis: " + pc.diagnose())
	pc.toggle_panel()
	slot = pc.slots.psu
	slot.interact(p)
	main._bin_use(p)
	main._buy(p, "psu", 1)
	slot.interact(p)
	pc.power_button()
	pc.toggle_panel()
	var money_b: int = Game.money
	var rep_b: float = Game.rep
	jobs._customer_talk(p)
	assert(jobs.state == "leaving" and Game.money == money_b, "garanti işi ücretli/teslim olmadı")
	assert(Game.rep > rep_b, "garanti sonrası itibar artmadı")
	print("OK garanti işi: ücret yok, itibar %.2f -> %.2f" % [rep_b, Game.rep])
	# garanti müşterisi kızıp giderse itibar fazla düşer
	await get_tree().create_timer(0.1).timeout
	while jobs.state != "waiting":
		Game.clock = minf(Game.clock, 15.0)
		await get_tree().create_timer(0.2).timeout
	jobs.job = {"name": "Test", "kind": "warranty", "warranty": true, "pay": 0, "broken": "psu", "parts": [], "intro": ""}
	rep_b = Game.rep
	jobs._leave_angry("test", 0.4)
	assert(rep_b - Game.rep > 0.5, "garanti kızgınlık cezası")
	print("OK garanti reddi: itibar %.2f -> %.2f" % [rep_b, Game.rep])
	# 4) ikinci el pazarı
	assert(Game.used_listings.size() == Game.UM.COUNT, "ilan yok")
	assert(Game.UM.generate(Game.day)[0].type == Game.used_listings[0].type, "ilanlar tohumlu değil")
	var l: Dictionary = Game.used_listings[0]
	assert(int(l.price) < Game.price_of(l.type, l.tier), "ikinci el pahalı")
	var k: String = Game.sku(l.type, l.tier)
	Game.stock[k] = 0
	Game.stock_dud.erase(k)
	m = Game.money
	assert(Game.UM.buy(int(l.id), 1) and Game.money == m - int(l.price) and l.sold, "ikinci el alınamadı")
	assert(Game.stock_of(l.type, l.tier) == 1 and int(Game.stock_dud.get(k, 0)) == 1)
	assert(not Game.UM.buy(int(l.id), 1), "aynı ilan iki kez satıldı")
	while p.held != null:
		p.drop()
	main._buy(p, l.type, l.tier)
	assert(p.held != null and p.held.broken and Game.stock_of(l.type, l.tier) == 0, "gizli arızalı çıkmadı")
	main._bin_use(p)
	print("OK ikinci el: %s %%%d, %d TL (yeni %d TL)" % [l.type, l.cond, l.price, Game.price_of(l.type, l.tier)])
	# 5) elektrik faturası formülü
	var jt: int = Game.jobs_today
	var up: Dictionary = Game.upgrades
	Game.upgrades = {}
	Game.jobs_today = 4
	assert(Game.utility_bill() == Game.UTIL_BASE + 4 * Game.UTIL_PER_JOB, "fatura formülü")
	Game.upgrades = {"coffee": true}
	assert(Game.utility_bill() == Game.UTIL_BASE + 4 * Game.UTIL_PER_JOB + Game.UTIL_COFFEE, "kahve faturası")
	Game.upgrades = up
	Game.jobs_today = jt
	print("OK elektrik faturası formülü")


## Bir koşul gerçekleşene kadar bekle (dükkân kapanmasın); süre dolarsa false.
func _wait_for(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call():
		Game.clock = minf(Game.clock, 15.0)
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		if t > limit:
			return false
	return true


## Personel: işe alma, tezgahtar karşılama/satış/koli, teknisyen tamiri, maaş, kayıt.
func _staff_tests(main, jobs) -> void:
	Game.new_game()
	var sm = Game.staff_mgr
	sm.force_run = true
	assert(Game.staff_candidates.size() == Game.STAFF_CANDIDATES, "aday yok")
	var clerk: Dictionary = Game.staff_candidates[0]
	var tech: Dictionary = Game.staff_candidates[1]
	assert(clerk.role == "tezgahtar" and tech.role == "teknisyen", "aday rolleri")
	for d in [clerk, tech]:
		d.skill = 5
		d.trait = "titiz"
	assert(Game.hire_staff(int(clerk.id)) and Game.hire_staff(int(tech.id)), "işe alma")
	assert(not Game.hire_staff(int(Game.staff_candidates[0].id)), "2'den fazla çalışan alındı")
	assert(sm.npcs.size() == 2, "çalışanlar dükkâna gelmedi")
	# 1) tezgahtar bekleyen müşteriyi karşılar, teknisyen stoktan parçayla tamir edip teslim eder
	Game.add_stock("gpu", 1, 2)
	var ok1 := await _wait_for(func(): return jobs.state == "waiting", 40.0)
	assert(ok1, "müşteri gelmedi")
	var j: Dictionary = jobs._make_job()
	while j.kind != "repair" or j.broken != "gpu":
		j = jobs._make_job()
	jobs.job = j
	var m: int = Game.money
	var ok2 := await _wait_for(func(): return jobs.state == "working", 20.0)
	assert(ok2, "tezgahtar müşteriyi karşılamadı")
	var gpu_before := Game.stock_of("gpu", 1)
	var ok3 := await _wait_for(func(): return jobs.state == "leaving", 120.0)
	assert(ok3, "teknisyen işi bitirmedi")
	assert(Game.money > m, "teknisyenin işinden para gelmedi")
	assert(Game.stock_of("gpu", 1) < gpu_before, "teknisyen stoktan parça kullanmadı")
	print("OK personel tamir: tezgahtar kabul etti, teknisyen tamir etti, para %d -> %d" % [m, Game.money])
	# 2) tezgah satışı: tezgahtar raftan getirip satar
	Game.add_stock("ram", 2, 1)
	var ok4 := await _wait_for(func(): return jobs.state == "waiting", 40.0)
	assert(ok4, "müşteri gelmedi (satış)")
	j = jobs._make_job()
	while j.kind != "sale" or j.want != ["ram", 2]:
		j = jobs._make_job()
	jobs.job = j
	var st := Game.stock_of("ram", 2)
	var mm: int = Game.money
	var ok5 := await _wait_for(func(): return jobs.state == "leaving", 30.0)
	assert(ok5, "tezgahtar satış yapmadı")
	assert(Game.money == mm + int(j.pay) and Game.stock_of("ram", 2) == st - 1, "satış tutarı/stok")
	print("OK personel satış: +%d TL" % j.pay)
	# 3) kargo: tezgahtar kapıdaki koliyi açar
	Game.add_money(500)
	var ssd := Game.stock_of("ssd", 1)
	assert(Game.place_order({"ssd:1": 1}, true))
	Game.clock += Game.SHIP_EXP_HOURS + 0.01
	main.delivery._send_courier()
	var ok6 := await _wait_for(func(): return not main.delivery.boxes.is_empty(), 20.0)
	assert(ok6, "kurye koliyi bırakmadı")
	var ok7 := await _wait_for(func(): return main.delivery.boxes.is_empty() and Game.orders.is_empty(), 60.0)
	assert(ok7, "tezgahtar koliyi açmadı")
	assert(Game.stock_of("ssd", 1) >= ssd, "koli stoğa girmedi")
	print("OK personel kargo: koli açıldı")
	# 4) gün sonu: maaşlar Z raporuna gider
	sm.force_run = false
	var summary := {}
	var cb := func(s): summary.merge(s)
	Game.day_ended.connect(cb)
	var wages := Game.staff_wages()
	var m2: int = Game.money
	var r := Game.rent()
	Game.end_day()
	Game.day_ended.disconnect(cb)
	assert(wages > 0 and int(summary.get("wages", -1)) == wages and Game.money == m2 - r - wages - Game.utility_today, "maaş ödenmedi")
	assert(sm.npcs.is_empty(), "gün sonunda çalışanlar kalmadı mı")
	print("OK maaşlar: %d TL (kasa %d -> %d)" % [wages, m2, Game.money])
	# 5) kayıt / yükleme ve işten çıkarma
	Game.staff = []
	assert(Game.continue_game() and Game.staff.size() == 2 and Game.staff[1].role == "teknisyen" and int(Game.staff[1].skill) == 5, "personel kaydı")
	assert(sm.npcs.size() == 2, "yüklemeden sonra çalışanlar yok")
	Game.fire_staff(int(Game.staff[0].id))
	assert(Game.staff.size() == 1 and Game.staff_wages() == int(tech.wage), "işten çıkarma")
	DirAccess.remove_absolute(Game.save_path)
	print("OK personel kayıt ve işten çıkarma")
