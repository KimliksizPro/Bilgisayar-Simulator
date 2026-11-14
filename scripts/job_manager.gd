extends Node
## Müşteri akışı: müşteri gelir, derdini anlatır, bilgisayarı bırakır, tamir sonrası öder.

const PC := preload("res://scripts/pc_case.gd")
const CUSTOMER := preload("res://scripts/customer.gd")
const PM := preload("res://scripts/part_models.gd")
const WARRANTY := preload("res://scripts/warranty.gd")
const DJ := preload("res://scripts/device_jobs.gd")  # laptop / telefon işleri
const DIRECTOR := preload("res://scripts/job_director.gd")  # iş seçici

var _director := DIRECTOR.new()

const SPAWN := Vector3(-0.3, 0, 9.0)
const DOOR := Vector3(0, 0, 3.6)
const INSIDE := Vector3(0, 0, 2.5)
const COUNTER := Vector3(-0.6, 0, 1.95)


var world: Node3D
var monitor
var pc_spot: Transform3D
var hud
var state := "none"
var customer = null
var pc = null
var job := {}

# Sabır / süre ayarları
const WAIT_PATIENCE := 60.0   # konuşulmayı bekleme sınırı (gerçek sn)
const JOB_HOURS := 4.0        # iş süresi sınırı (oyun saati)

var _gen := 0                 # gün/oturum sayacı: eski bekleyen çağrıları iptal eder
var wait_t := 0.0
var work_hours := 0.0
var fail_count := 0
var _warned := false


func start() -> void:
	state = "none"
	hud.set_job("Hoş geldin!", "Yeni oyun başlat ya da kaydı yükle.")
	Game.day_started.connect(begin_day)
	Game.day_ended.connect(func(_s): _gen += 1)


## Yeni gün: ortada kalan müşteri/bilgisayarı temizle, ilk müşteriyi çağır.
func begin_day() -> void:
	_gen += 1
	if is_instance_valid(customer):
		customer.queue_free()
	if is_instance_valid(pc):
		pc.power_off()
		pc.queue_free()
	customer = null
	pc = null
	_next_customer(2.0)


func _arrival_delay() -> float:
	return randf_range(5.0, 9.0) * Game.arrival_mult()


func _process(delta: float) -> void:
	if Game.phase != "day":
		return
	if Game.running:
		if state == "waiting":
			wait_t += delta
			var lim := WAIT_PATIENCE * Game.patience_mult() * (2.0 if job.get("kind", "") == "sale" else 1.0)
			hud.set_patience(1.0 - wait_t / lim)
			if wait_t >= lim:
				_leave_angry("Çok bekledim usta, ben gidiyorum!", 0.4)
		elif state == "working":
			work_hours += delta * Game.HOURS_PER_SEC
			var lim := _job_limit()
			hud.set_patience(1.0 - work_hours / lim)
			if not _warned and work_hours > lim * 0.75:
				_warned = true
				customer.say("Usta biraz acele et, işim var!", true)
			if work_hours >= lim:
				_leave_angry("Bu kadar uzar mı be usta! Bilgisayarımı alıyorum, gidiyorum!", 0.5)
	# kapanış saati geldi ve müşteri kalmadı -> gün sonu
	if Game.is_closed() and (state == "none" or state == "closed"):
		Game.end_day()


func _job_limit() -> float:
	var base := float(job.get("hours", JOB_HOURS))
	return base * Game.patience_mult()


## Müşteri sabrı bitti: bilgisayarı alıp kızgın gider, itibar düşer.
func _leave_angry(line: String, rep_loss: float) -> void:
	state = "leaving"
	var c = customer
	c.say(line, true)
	if job.get("warranty", false):
		rep_loss += WARRANTY.REP_ANGRY_EXTRA  # garanti müşterisini kızdırmak daha pahalı
	Game.change_rep(-rep_loss)
	Game.sfx.error()
	Game.msg("%s kızıp gitti! İtibar düştü." % job.name, Color(1, 0.5, 0.4))
	hud.set_job("Müşteri gitti", "")
	hud.set_patience(-1.0)
	if is_instance_valid(pc):
		_dispose_pc(pc, 0.3)
		pc = null
	var g := _gen
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(c):
		c.say("")
		c.walk([INSIDE, DOOR, SPAWN], func(): c.queue_free())
	if g == _gen:
		_next_customer(_arrival_delay())


func _dispose_pc(old_pc, wait: float) -> void:
	var tw := create_tween()
	tw.tween_interval(wait)
	tw.tween_property(old_pc, "scale", Vector3.ONE * 0.01, 0.4)
	tw.tween_callback(func():
		old_pc.power_off()
		old_pc.queue_free())


func _next_customer(delay: float) -> void:
	state = "none"
	var g := _gen
	hud.set_job("Müşteri bekleniyor...", "")
	hud.set_patience(-1.0)
	await get_tree().create_timer(delay).timeout
	if g != _gen or Game.phase != "day":
		return
	if Game.is_closed():
		state = "closed"
		hud.set_job("Dükkân kapandı", "")
		return
	job = _make_job()
	customer = CUSTOMER.new()
	customer.position = SPAWN
	world.add_child(customer)
	customer.build(_customer_hint, _customer_talk, job.name)
	customer.say("")
	state = "arriving"
	hud.set_job("%s geliyor..." % job.name, "")
	customer.walk([DOOR, INSIDE, COUNTER], _on_arrived)


func _on_arrived() -> void:
	customer.face_angle = PI
	customer.say("Merhaba usta! " + job.intro)
	state = "waiting"
	wait_t = 0.0
	if job.kind == "sale":
		var w: Array = job.want
		hud.set_job("%s — %d TL" % [job.name, job.pay], job.goal + ("" if Game.stock_of(w[0], w[1]) > 0 else "\n\nStokta yok! ParçaNet'ten ekspres sipariş ver."))
	else:
		hud.set_job("Yeni müşteri: %s" % job.name, "Tezgahtaki müşteriyle konuş [E]")
	Game.msg("Bir müşteri geldi!", Color(0.6, 0.9, 1.0))
	hud.tip("talk", "Müşteriyle konuşmak için ona bakıp E'ye bas.")


## Sıradaki işi seçici belirler (ağırlıklı torba + tekrar cezası).
func _make_job() -> Dictionary:
	# garanti dönüşü (muadil parça bozuldu) her şeyden önce gelir
	var due := WARRANTY.take_due()
	if not due.is_empty():
		return WARRANTY.make_job(due, DB.jobs.base_parts())
	return _make_job_of(_director.next(Game.money, Game.job_history, Game.day, Game.rep))


## Verilen iş kimliğinden iş üretir (geçmişe dokunmaz; testler de bunu kullanır).
## broken: laptop/telefon için arızalı yuvayı sabitler. Şablon data/jobs.json'dan gelir.
func _make_job_of(id: String, broken := "") -> Dictionary:
	var t = DB.jobs.template(id)
	var j := {"name": DB.jobs.text("names").pick_random()}
	if t == null:
		push_error("Bilinmeyen iş şablonu: " + id)
		return j
	match t.kind:
		"device": return DJ.make(j, t.device, broken)
		"sale": return _job_sale(j, t)
		"repair": return _job_repair(j, t)
		"overheat": return _job_overheat(j, t)
	return _job_plain(j, t)  # upgrade / build


## Şablondaki ücret formülü: parça bedeli x adet + sabit ek.
func _template_pay(t) -> int:
	var pay: int = t.pay_extra
	if t.pay_part.size() == 2:
		pay += PM.price(str(t.pay_part[0]), int(t.pay_part[1])) * t.pay_count
	return pay


## Müşteri cümlesi: sabit intro, yoksa arıza cümlesi (specific_chance) ya da şablonun metin havuzu.
func _intro_of(t, fault) -> String:
	if t.intro != "":
		return t.intro
	var vague: Array = DB.jobs.text(t.intro_pool)
	if fault != null and not fault.customer_lines.is_empty() and (vague.is_empty() or randf() < t.specific_chance):
		return fault.customer_lines.pick_random()
	return vague.pick_random()


func _job_sale(j: Dictionary, t) -> Dictionary:
	# tezgahtan parça satışı
	var w: Array = t.want_key()
	var dname := PM.display_name(w[0], w[1])
	j.kind = t.job_kind
	j.want = w
	j.intro = DB.jobs.text(t.intro_pool).pick_random() % dname
	j.goal = t.goal % dname
	j.pay = Game.retail_price(w[0], w[1])
	j.parts = []
	return j


## Yükseltme ve sıfırdan toplama: sabit metin, formül ücret, isteğe bağlı teslim koşulu.
func _job_plain(j: Dictionary, t) -> Dictionary:
	j.kind = t.job_kind
	j.intro = t.intro
	j.goal = t.goal
	j.pay = _template_pay(t)
	j.parts = _with_broken(DB.jobs.base_parts(), "") if t.with_base_parts else []
	if not t.target.is_empty():
		j.target = t.target
	if t.hours > 0.0:
		j.hours = t.hours
	return j


func _job_repair(j: Dictionary, t) -> Dictionary:
	var f = DB.jobs.fault(t.fault)
	j.kind = t.job_kind
	j.broken = f.part
	j.intro = _intro_of(t, f)
	j.goal = t.goal
	# ücret = parça bedeli + işçilik (arıza tanımından)
	j.pay = PM.price(f.part, 1) + f.roll_labor()
	var parts := _with_broken(DB.jobs.base_parts(), f.part)
	if randf() < t.ram2_chance:
		parts.append(["ram2", "ram", 1, false])
	j.parts = parts
	return j


## Aşırı ısınma işi: kasa tozlu veya CPU macunu kurumuş (arıza tanımındaki dust/paste_dry).
func _job_overheat(j: Dictionary, t) -> Dictionary:
	var f = DB.jobs.fault(t.fault)
	j.kind = t.job_kind
	j.intro = _intro_of(t, f)
	j.goal = t.goal
	j.pay = f.roll_labor()
	var parts := _with_broken(DB.jobs.base_parts(), "")
	if f.paste_dry:
		for i in parts.size():
			if parts[i][0] == "cpu":
				parts[i] = ["cpu", "cpu", 1, false, false]
	if randf() < f.dust_chance:
		parts.append(["dust", "", randf_range(f.dust.x, f.dust.y), false])
	j.parts = parts
	return j


func _with_broken(base: Array, broken: String) -> Array:
	var out := []
	for b in base:
		out.append([b[0], b[1], b[2], b[1] == broken])
	return out


func _customer_hint(p) -> String:
	if job.get("kind", "") == "sale" and state == "waiting":
		var w: Array = job.want
		if p.held and not p.held.is_tool() and p.held.part_type == w[0] and p.held.tier == w[1] and not p.held.broken:
			return "Sat: %s — %d TL  [E]" % [PM.display_name(w[0], w[1]), job.pay]
		return "%s ile konuş  [E]" % job.name
	match state:
		"waiting": return "%s ile konuş  [E]" % job.name
		"working": return DJ.deliver_hint(job)
	return ""


func _customer_talk(p) -> void:
	if job.get("kind", "") == "sale" and state == "waiting":
		_try_sell(p)
		return
	match state:
		"waiting":
			_accept()
		"working":
			_try_deliver()


func _accept() -> void:
	job.pay = Game.job_pay(int(job.pay))  # itibar ve sertifika etkisi
	work_hours = 0.0
	fail_count = 0
	_warned = false
	pc = DJ.new_device(job) if DJ.is_device(job) else PC.new()
	pc.transform = DJ.spot(pc, pc_spot)
	world.add_child(pc)
	pc.monitor = monitor
	pc.fill(job.parts)
	state = "working"
	customer.say("Tamamdır usta, ben burada bekliyorum. Ücreti %d TL." % job.pay)
	hud.set_job("%s — %s" % [job.name, "GARANTİ (ücretsiz)" if job.get("warranty", false) else "%d TL" % job.pay], job.goal + "\n\nBitince müşteriyle konuş [E]")
	if DJ.is_device(job):  # laptop / telefon: kendi ipuçları
		DJ.on_accept(hud, job)
		return
	Game.msg("Bilgisayar masana kondu. Kapağı açıp incele!", Color(0.6, 0.9, 1.0))
	hud.dismiss_tip("talk")
	hud.tip("glass", "Kapağı açmak için bilgisayarın camına bakıp E'ye bas.")
	hud.tip("leds", "Güç düğmesine bas; bip seslerini ve anakartın hata LED'lerini izle. Duvardaki Arıza Rehberi yardımcı olur.")


func _problem() -> String:
	if DJ.is_device(job):  # laptop / telefon kendi kontrolünü yapar
		return pc.problem()
	var code: String = pc.diagnose()
	if code != "ok":
		var f = _fault_of(code)
		var lines: Array = f.fail_lines if f != null else []
		return lines.pick_random() if not lines.is_empty() else DB.jobs.text("fail_default")[0]
	var tg: Dictionary = job.get("target", {})
	if tg.has("min_tier"):
		var g = pc.part_in(str(tg.part))
		if g.tier < int(tg.min_tier):
			return str(tg.fail)
	if tg.has("ram_gb"):
		if pc.total_ram() < int(tg.ram_gb):
			return str(tg.fail) % pc.total_ram()
	if pc.panel_open:
		return "Kapağı kapatmadan mı vereceksin usta?"
	return ""


## Teşhis koduna uyan arıza tanımı; aşırı ısınmada toz mu macun mu olduğuna bakılır.
func _fault_of(code: String):
	if code == "overheat":
		return DB.jobs.fault("overheat_dust" if pc.dust > 0.5 else "overheat_paste")
	return DB.jobs.fault_by_code(code)


## Teslim reddedilince oyuncuya HUD'da teknik ipucu (müşteri cümlesinden ayrı).
func _problem_hint() -> String:
	if DJ.is_device(job) or pc == null:
		return ""
	var f = _fault_of(pc.diagnose())
	return f.hint if f != null else ""


func _try_deliver() -> void:
	var problem := _problem()
	if problem != "":
		customer.say(problem, true)
		var hint := _problem_hint()
		if hint != "":
			Game.msg(hint, Color(1.0, 0.8, 0.4))
		Game.sfx.error()
		fail_count += 1
		if fail_count <= 3:
			Game.change_rep(-0.05)
		return
	state = "leaving"
	hud.set_patience(-1.0)
	WARRANTY.on_delivered(pc, job)  # muadil parça takıldıysa geri dönüş riski kaydedilir
	if job.get("warranty", false):
		_finish_warranty()
		return
	Game.add_money(job.pay)
	Game.jobs_done += 1
	Game.jobs_today += 1
	Game.stats.total_jobs = int(Game.stats.total_jobs) + 1
	var fast := work_hours < _job_limit() * 0.4
	Game.change_rep(0.25 if fast else 0.15)
	Game.cash_sound()
	hud.pop_money(int(job.pay))
	customer.say(["Eline sağlık usta, sağ ol!", "Helal olsun, tıkır tıkır çalışıyor!",
		"Çok teşekkürler, herkese seni önereceğim!"].pick_random())
	Game.msg("+%d TL kazandın!" % job.pay + ("  (hızlı servis, itibar arttı)" if fast else ""), Color(0.5, 1, 0.5))
	hud.set_job("İş tamamlandı!", "")
	var old_pc = pc
	pc = null
	_dispose_pc(old_pc, 0.5)
	var g := _gen
	var c = customer
	await get_tree().create_timer(1.2).timeout
	c.say("")
	c.walk([INSIDE, DOOR, SPAWN], func(): c.queue_free())
	if g == _gen:
		_next_customer(_arrival_delay())


## Garanti işi teslimi: ücret yok, hızlıysa itibar düzelir.
func _finish_warranty() -> void:
	var fast := work_hours < _job_limit() * 0.5
	Game.change_rep(WARRANTY.REP_FAST if fast else WARRANTY.REP_SLOW)
	Game.cash_sound()
	customer.say(["Tamam usta, bu sefer sağlam olsun!", "Sağ ol usta, garanti dediğin böyle olur."].pick_random())
	Game.msg("Garanti işi tamamlandı" + ("  (hızlı servis, itibar düzeldi)" if fast else "."), Color(0.6, 0.9, 1.0))
	hud.set_job("Garanti işi tamamlandı!", "")
	var old_pc = pc
	pc = null
	_dispose_pc(old_pc, 0.5)
	var g := _gen
	var c = customer
	await get_tree().create_timer(1.2).timeout
	c.say("")
	c.walk([INSIDE, DOOR, SPAWN], func(): c.queue_free())
	if g == _gen:
		_next_customer(_arrival_delay())


## Parça satışı: oyuncu doğru parçayı elinde tutarak konuşursa satılır.
func _try_sell(p) -> void:
	var w: Array = job.want
	var dname := PM.display_name(w[0], w[1])
	var h = p.held if p else null
	if h == null or h.is_tool() or h.part_type != w[0] or h.tier != w[1] or h.broken:
		if h != null and not h.is_tool() and h.part_type == w[0]:
			customer.say("Yok usta, bu değil. Bana %s lazım." % dname, true)
			Game.sfx.error()
		elif Game.stock_of(w[0], w[1]) > 0:
			customer.say("Raftan bir %s getiriver usta, bekliyorum." % dname)
		else:
			customer.say("Stokta yok mu? Getirtebilirsen beklerim ama çok değil usta.")
		hud.tip("sale", "Parça satışı: raftan istenen parçayı al, elinde tutarken müşteriye E'ye bas.")
		return
	var part = p.release_held()
	if part.cheap:
		job.pay = roundi(int(job.pay) * Game.CHEAP_FACTOR)  # muadil parça daha ucuza satılır
	part.queue_free()
	state = "leaving"
	hud.set_patience(-1.0)
	Game.add_money(int(job.pay))
	Game.sales_today += 1
	Game.stats.total_sales = int(Game.stats.get("total_sales", 0)) + 1
	Game.change_rep(0.08)
	Game.cash_sound()
	hud.pop_money(int(job.pay))
	hud.dismiss_tip("sale")
	customer.say(["Sağ ol usta, hayırlı işler!", "Tamamdır, eline sağlık!", "Tam aradığım buydu, teşekkürler!"].pick_random())
	Game.msg("%s satıldı: +%d TL" % [dname, job.pay], Color(0.5, 1, 0.5))
	hud.set_job("Satış tamamlandı!", "")
	var g := _gen
	var c = customer
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(c):
		c.say("")
		c.walk([INSIDE, DOOR, SPAWN], func(): c.queue_free())
	if g == _gen:
		_next_customer(_arrival_delay())
