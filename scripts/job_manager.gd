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

const NAMES := ["Ahmet Abi", "Ayşe Teyze", "Mehmet", "Zeynep", "Kerem", "Hasan Amca",
	"Elif", "Burak", "Fatma Abla", "Emre", "Selin", "Mustafa Amca"]

const REPAIR_LINES := {
	"psu": ["Abi dün akşam bi patlama sesi geldi, şimdi düğmeye basınca hiçbir şey olmuyor.",
		"Elektrikler gidip geldi, o günden beri bilgisayar hiç açılmıyor."],
	"cpu": ["Fanlar dönüyor ama ekrana hiçbir şey gelmiyor, ses de çıkarmıyor.",
		"Hız aşırtma yapayım dedim, bi koku geldi... şimdi açılmıyor."],
	"ram": ["Açınca sürekli bip bip bip diye ötüyor abi, kafayı yedim.",
		"Bilgisayar öterek açılmıyor, kardeşim bişey kurcaladı galiba."],
	"gpu": ["Oyun oynarken ekran gitti, şimdi açınca bi uzun üç kısa bip sesi geliyor.",
		"Ekrana görüntü gelmiyor, bilgisayar da garip garip ötüyor."],
	"ssd": ["Açılıyor ama 'boot device' diye bi şey yazıyor, Windows gelmiyor.",
		"Bilgisayar açılıyor ama işletim sistemi gelmiyor, siyah ekranda yazı var."],
}
const OVERHEAT_LINES := {
	"overheat_dust": ["Oyun oynarken bilgisayar kendi kendine kapanıyor usta, fanlar da çok bağırıyor.",
		"Fanlar jet gibi ötüyor abi, bir süre sonra da kapanıveriyor."],
	"overheat_paste": ["Bilgisayar açılıyor ama biraz kullanınca kapanıyor usta. Kasa da sıcacık oluyor.",
		"Yıllardır içine bakmadık abi, bir süredir kendi kendine kapanıp duruyor."],
}
const SALE_LINES := ["Usta bir %s lazım, var mı sende?", "Merhaba, %s alacaktım. Stokta var mı?",
	"Oğlana %s alacağım, en iyisinden ver usta.", "Kendim takacağım abi, bir %s versene."]
const BASE_PARTS := [["psu", "psu", 1], ["cpu", "cpu", 1], ["ram1", "ram", 1], ["gpu", "gpu", 1], ["ssd", "ssd", 1]]
const SALE_IDS := ["sale_ram1", "sale_ram2", "sale_ssd", "sale_psu", "sale_gpu1", "sale_gpu2", "sale_cpu"]
const SALE_WANTS := [["ram", 1], ["ram", 2], ["ssd", 1], ["psu", 1], ["gpu", 1], ["gpu", 2], ["cpu", 1]]
const VAGUE_LINES := ["Bozuldu abi, bi bakıver.", "Ne olduğunu anlamadım, bir sabah açılmadı.",
	"Oğlan bişey yaptı, çalışmıyor artık.", "Abi bu bilgisayar bozuk, acil lazım."]
# Teslim reddedilince müşterinin belirtisi (teşhis koduna göre)
const FAIL_LINES := {
	"nopower": ["Usta düğmeye basıyorum, hiç ses yok, fanlar bile dönmüyor!", "Açmaya çalışıyorum abi, elektrik almıyor gibi, ses bile yok."],
	"cpu": ["Fanlar dönüyor ama ekrana hiçbir şey gelmiyor, bip bip ötüyor.", "Dönüyor usta ama ekran boş, bi de garip sesler çıkarıyor."],
	"ram": ["Uzun uzun bipliyor usta, açılmıyor.", "Açılmaya çalışıyor ama sürekli bip sesi veriyor abi."],
	"gpu": ["Kasa çalışıyor ama monitör kapkara.", "Kasa açılıyor abi, ekrana görüntü hiç gelmiyor."],
	"ssd": ["Açılıyor ama 'boot device not found' yazıyor abi.", "Windows'a girmiyor usta, siyah ekranda disk yok yazıyor."],
}

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
const BUILD_HOURS := 7.0      # sıfırdan toplama için sınır

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
	var base := float(job.get("hours", BUILD_HOURS if job.get("kind", "") == "build" else JOB_HOURS))
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
		return WARRANTY.make_job(due, BASE_PARTS)
	return _make_job_of(_director.next(Game.money, Game.job_history))


## Verilen iş kimliğinden iş üretir (geçmişe dokunmaz; testler de bunu kullanır).
## broken: laptop/telefon için arızalı yuvayı sabitler.
func _make_job_of(id: String, broken := "") -> Dictionary:
	var j := {"name": NAMES.pick_random()}
	if id.begins_with("device_"):
		return DJ.make(j, id.substr(7), broken)
	if id.begins_with("sale_"):
		return _job_sale(j, SALE_WANTS[SALE_IDS.find(id)])
	if id.begins_with("repair_"):
		return _job_repair(j, id.substr(7))
	match id:
		"build": _job_build(j)
		"upgrade_gpu": _job_upgrade_gpu(j)
		"upgrade_ram": _job_upgrade_ram(j)
		_: _overheat_job(j, BASE_PARTS, id)
	return j


func _job_sale(j: Dictionary, w: Array) -> Dictionary:
	# tezgahtan parça satışı
	j.kind = "sale"
	j.want = w
	j.intro = SALE_LINES.pick_random() % PM.display_name(w[0], w[1])
	j.goal = "Raftan %s al, elinde tutarken müşteriyle konuş [E]." % PM.display_name(w[0], w[1])
	j.pay = Game.retail_price(w[0], w[1])
	j.parts = []
	return j


func _job_build(j: Dictionary) -> void:
	j.kind = "build"
	j.intro = "Sıfırdan bir bilgisayar topla abi. Kasa bende, parçaları sen al, toplayınca hakkını veririm."
	j.goal = "Boş kasaya tüm parçaları tak ve çalıştır."
	j.pay = 600
	j.parts = []


func _job_upgrade_gpu(j: Dictionary) -> void:
	j.kind = "upgrade_gpu"
	j.intro = "Oyunlar çok kasıyor usta. Bana iyi bir ekran kartı tak, parasını veririm."
	j.goal = "Oyuncu (RGB) ekran kartı tak."
	j.pay = PM.price("gpu", 2) + 140
	j.parts = _with_broken(BASE_PARTS, "")


func _job_upgrade_ram(j: Dictionary) -> void:
	j.kind = "upgrade_ram"
	j.intro = "Chrome açınca bilgisayar donuyor. RAM'i 32 GB yap abi."
	j.goal = "Toplam RAM'i 32 GB'a çıkar (2 x 16 GB)."
	j.pay = PM.price("ram", 2) * 2 + 110
	j.parts = _with_broken(BASE_PARTS, "")


func _job_repair(j: Dictionary, broken: String) -> Dictionary:
	j.kind = "repair"
	j.broken = broken
	j.intro = REPAIR_LINES[broken].pick_random() if randf() < 0.6 else VAGUE_LINES.pick_random()
	j.goal = "Arızalı parçayı bul ve değiştir."
	# ücret = parça bedeli + işçilik (işlemci/PSU teşhisi biraz daha pahalı)
	var labor := randi_range(11, 16) * 10 if broken in ["cpu", "psu"] else randi_range(9, 14) * 10
	j.pay = PM.price(broken, 1) + labor
	var parts := _with_broken(BASE_PARTS, broken)
	if randf() < 0.5:
		parts.append(["ram2", "ram", 1, false])
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
	if code == "overheat":
		return _overheat_problem()
	if code != "ok":
		var lines: Array = FAIL_LINES.get(code, [])
		return lines.pick_random() if not lines.is_empty() else "Usta bu bilgisayar hâlâ düzgün çalışmıyor ki!"
	match job.kind:
		"upgrade_gpu":
			var g = pc.part_in("gpu")
			if g.tier < 2:
				return "Abi bu aynı kart, oyunlar yine kasacak."
		"upgrade_ram":
			if pc.total_ram() < 32:
				return "Usta RAM hâlâ %d GB, 32 olacaktı." % pc.total_ram()
	if pc.panel_open:
		return "Kapağı kapatmadan mı vereceksin usta?"
	return ""


## Teslim reddedilince oyuncuya HUD'da teknik ipucu (müşteri cümlesinden ayrı).
func _problem_hint() -> String:
	if DJ.is_device(job) or pc == null:
		return ""
	match pc.diagnose():
		"nopower": return "İpucu: Güç gelmiyor — PSU'yu kontrol et."
		"cpu": return "İpucu: İşlemci sorunlu olabilir — CPU'yu kontrol et."
		"ram": return "İpucu: RAM hatalı ya da takılı değil — RAM'leri kontrol et."
		"gpu": return "İpucu: Ekran kartı arızalı olabilir — GPU'yu kontrol et."
		"ssd": return "İpucu: Açılış diski bulunamıyor — SSD'yi kontrol et."
		"overheat": return "İpucu: Aşırı ısınma — kasa tozunu temizle ya da CPU macununu yenile."
	return ""


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


## Aşırı ısınma işi: kasa tozlu (overheat_dust) veya CPU macunu kurumuş (overheat_paste).
func _overheat_job(j: Dictionary, base: Array, kind: String) -> void:
	j.kind = kind
	j.intro = OVERHEAT_LINES[kind].pick_random()
	j.pay = randi_range(14, 24) * 10
	var parts := _with_broken(base, "")
	if kind == "overheat_dust":
		j.goal = "Bilgisayar aşırı ısınıp kapanıyor. Nedenini bul ve gider."
		parts.append(["dust", "", randf_range(0.75, 1.0), false])
	else:
		j.goal = "Bilgisayar aşırı ısınıp kapanıyor. Nedenini bul ve gider."
		parts[1] = ["cpu", "cpu", 1, false, false]
		if randf() < 0.3:  # biraz toz da olsun ama sorun macun
			parts.append(["dust", "", randf_range(0.1, 0.3), false])
	j.parts = parts


func _overheat_problem() -> String:
	if pc.dust > 0.5:
		return "Usta kasanın içi hâlâ toz içinde, yine ısınıp kapanacak!"
	return "Usta işlemcinin macunu kurumuş, yine aşırı ısınıp kapanacak!"


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
