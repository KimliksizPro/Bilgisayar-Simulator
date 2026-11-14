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


func start() -> void:
	_next_customer(1.5)


func _next_customer(delay: float) -> void:
	state = "none"
	hud.set_job("Müşteri bekleniyor...", "")
	await get_tree().create_timer(delay).timeout
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
	elif roll < 0.42:
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
		customer.say(problem)
		Game.sfx.error()
		return
	state = "leaving"
	Game.add_money(job.pay)
	Game.jobs_done += 1
	Game.sfx.coin()
	customer.say(["Eline sağlık usta, sağ ol!", "Helal olsun, tıkır tıkır çalışıyor!",
		"Çok teşekkürler, herkese seni önereceğim!"].pick_random())
	Game.msg("+%d TL kazandın!" % job.pay, Color(0.5, 1, 0.5))
	hud.set_job("İş tamamlandı!", "")
	var old_pc = pc
	pc = null
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(old_pc, "scale", Vector3.ONE * 0.01, 0.4)
	tw.tween_callback(func():
		old_pc.power_off()
		old_pc.queue_free())
	await get_tree().create_timer(1.2).timeout
	customer.say("")
	var c = customer
	c.walk([INSIDE, DOOR, SPAWN], func(): c.queue_free())
	_next_customer(4.0)
