extends Node
## Müşteri akışı: müşteri gelir, derdini anlatır, bilgisayarı bırakır, tamir sonrası öder.

const PC := preload("res://scripts/pc_case.gd")
const CUSTOMER := preload("res://scripts/customer.gd")
const PM := preload("res://scripts/part_models.gd")

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
const VAGUE_LINES := ["Bozuldu abi, bi bakıver.", "Ne olduğunu anlamadım, bir sabah açılmadı.",
	"Oğlan bişey yaptı, çalışmıyor artık.", "Abi bu bilgisayar bozuk, acil lazım."]

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
			var lim := WAIT_PATIENCE * Game.patience_mult()
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
	customer.build(_customer_hint, _customer_talk)
	customer.say("")
	state = "arriving"
	hud.set_job("%s geliyor..." % job.name, "")
	customer.walk([DOOR, INSIDE, COUNTER], _on_arrived)


func _on_arrived() -> void:
	customer.face_angle = PI
	customer.say("Merhaba usta! " + job.intro)
	state = "waiting"
	wait_t = 0.0
	hud.set_job("Yeni müşteri: %s" % job.name, "Tezgahtaki müşteriyle konuş [E]")
	Game.msg("Bir müşteri geldi!", Color(0.6, 0.9, 1.0))


func _make_job() -> Dictionary:
	var j := {"name": NAMES.pick_random()}
	var roll := randf()
	var base := [["psu", "psu", 1], ["cpu", "cpu", 1], ["ram1", "ram", 1], ["gpu", "gpu", 1], ["ssd", "ssd", 1]]
	if roll < 0.15 and Game.money >= 300:
		j.kind = "build"
		j.intro = "Sıfırdan bir bilgisayar topla abi. Kasa bende, parçaları sen al, toplayınca hakkını veririm."
		j.goal = "Boş kasaya tüm parçaları tak ve çalıştır."
		j.pay = 600
		j.parts = []
	elif roll < 0.3:
		j.kind = "upgrade_gpu"
		j.intro = "Oyunlar çok kasıyor usta. Bana iyi bir ekran kartı tak, parasını veririm."
		j.goal = "Oyuncu (RGB) ekran kartı tak."
		j.pay = PM.price("gpu", 2) + 140
		j.parts = _with_broken(base, "")
	elif roll < 0.4:
		_overheat_job(j, base, "overheat_dust" if randf() < 0.5 else "overheat_paste")
	elif roll < 0.5:
		j.kind = "upgrade_ram"
		j.intro = "Chrome açınca bilgisayar donuyor. RAM'i 32 GB yap abi."
		j.goal = "Toplam RAM'i 32 GB'a çıkar (2 x 16 GB)."
		j.pay = PM.price("ram", 2) * 2 + 110
		j.parts = _with_broken(base, "")
	else:
		var broken: String = ["psu", "cpu", "ram", "gpu", "ssd"].pick_random()
		j.kind = "repair"
		j.broken = broken
		j.intro = REPAIR_LINES[broken].pick_random() if randf() < 0.6 else VAGUE_LINES.pick_random()
		j.goal = "Arızalı parçayı bul ve değiştir."
		j.pay = randi_range(15, 26) * 10
		var parts := _with_broken(base, broken)
		if randf() < 0.5:
			parts.append(["ram2", "ram", 1, false])
		j.parts = parts
	return j


func _with_broken(base: Array, broken: String) -> Array:
	var out := []
	for b in base:
		out.append([b[0], b[1], b[2], b[1] == broken])
	return out


func _customer_hint(_p) -> String:
	match state:
		"waiting": return "%s ile konuş  [E]" % job.name
		"working": return "Bilgisayarı teslim et  [E]"
	return ""


func _customer_talk(_p) -> void:
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
	pc = PC.new()
	pc.transform = pc_spot
	world.add_child(pc)
	pc.monitor = monitor
	pc.fill(job.parts)
	state = "working"
	customer.say("Tamamdır usta, ben burada bekliyorum. Ücreti %d TL." % job.pay)
	hud.set_job("%s — %d TL" % [job.name, job.pay], job.goal + "\n\nBitince müşteriyle konuş [E]")
	Game.msg("Bilgisayar masana kondu. Kapağı açıp incele!", Color(0.6, 0.9, 1.0))


func _problem() -> String:
	var code: String = pc.diagnose()
	if code == "overheat":
		return _overheat_problem()
	if code != "ok":
		return "Usta bu bilgisayar hâlâ düzgün çalışmıyor ki!"
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


func _try_deliver() -> void:
	var problem := _problem()
	if problem != "":
		customer.say(problem, true)
		Game.sfx.error()
		fail_count += 1
		if fail_count <= 3:
			Game.change_rep(-0.05)
		return
	state = "leaving"
	hud.set_patience(-1.0)
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
