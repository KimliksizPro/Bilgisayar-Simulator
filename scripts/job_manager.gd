extends Node
## Müşteri ve iş akışı (çoklu iş): müşteri gelir, derdini anlatır; oyuncu işi kabul edince cihaz "Bekleyen İşler"
## rafına konur, müşteri fiş alıp gider ve teslim gününde geri gelir. Cihaz rafta/tezgâhta taşınabilir; tamir
## edilip rafa konunca (hata yoksa) "hazır" sayılır. Teslimde müşteri fiş numarasını söyler, oyuncu doğru cihazı
## taşıyıp ona E'ye basar. Tezgâh satışı eskisi gibi anında olur.
##
## Veri: Game.jobs_active (kayıt listesi). Düğümler: devices {fiş -> cihaz}. Kuyruk: tezgâhta en çok 1, toplam 3 müşteri.
##
## Teslim zamanı (job_store.make_due): tamir/yükseltme/garanti = ertesi gün 10-18 arası; sıfırdan toplama = 2 gün;
## ekspres (%20, 15:30'a kadar gelen tamir) = 3 oyun saati sonra, ücret x1.2.
## Hazır kuralı: cihaz rafa konunca _problem_of "" ise otomatik "hazır" (yeşil ışık). Tezgâha alınınca durum sıfırlanır.
## Gecikme kuralı: müşteri vakti gelince kuyruğa girer; cihaz hazır değilse sabrı (~60 sn) dolana kadar beklenir
## (bu sürede teslim edilebilir). Sabır biterse ilkinde +1 gün verir (itibar -0.2); ikincisinde cihazı olduğu gibi alıp
## gider (itibar -0.5, ücret yok).

const PC := preload("res://scripts/pc_case.gd")
const CUSTOMER := preload("res://scripts/customer.gd")
const PM := preload("res://scripts/part_models.gd")
const WARRANTY := preload("res://scripts/warranty.gd")
const DJ := preload("res://scripts/device_jobs.gd")  # laptop / telefon işleri
const DIRECTOR := preload("res://scripts/job_director.gd")  # iş seçici
const ST := preload("res://scripts/job_store.gd")
const RACK := preload("res://scripts/job_rack.gd")
const CARRY := preload("res://scripts/job_carry.gd")
const MU := preload("res://scripts/mesh_util.gd")

var _director := DIRECTOR.new()

const SPAWN := Vector3(-0.3, 0, 9.0)
const DOOR := Vector3(0, 0, 3.6)
const INSIDE := Vector3(0, 0, 2.5)
const COUNTER := Vector3(-0.6, 0, 1.95)
const LINE := [Vector3(-0.6, 0, 1.95), Vector3(-0.15, 0, 2.55), Vector3(0.3, 0, 3.1)]  # kuyruk yerleri (0 = tezgâh)
const MAX_QUEUE := 3

# Sabır ayarları
const WAIT_PATIENCE := 60.0   # konuşulmayı bekleme sınırı (gerçek sn)
const LATE_REP := 0.2         # sabır bitince ek gün verilirse itibar kaybı
const TAKEN_REP := 0.5        # ikinci gecikmede cihazı alıp gitme itibar kaybı

var world: Node3D
var monitor
var pc_spot: Transform3D
var hud
var rack: Node3D                       # bekleyen işler rafı (main atar)
var carry := CARRY.new()               # taşınan cihaz

var queue: Array = []                  # müşteri kuyruğu: {customer, job, mode, rec, wait_t, arrived, wrong}
var devices := {}                      # fiş no -> cihaz düğümü
var tags := {}                         # fiş no -> {root, stripe}
var busy := {}                         # fiş no -> true (personel üzerinde çalışıyor)

# baştaki müşteri görünümü (personel ve testler okur)
var state := "none"                    # none / arriving / waiting / closed
var customer = null
var job := {}
var mode := ""                         # dropoff / sale / pickup

# test ve araç kancaları
var arrivals_enabled := true           # false: kendiliğinden yeni müşteri gelmez
var force_jobs: Array = []             # doluysa sıradaki bırakma/satış müşterisi bu işlerden gelir
var force_express := -1                # -1 rastgele, 0 hiç, 1 hep ekspres
var theft_catch_override := -1.0       # <0: normal olasılık, 0.0: yakalanmaz, 1.0: yakalanır

var pc: Object:                        # tezgâhtaki cihaz (eski adla)
	get: return Game.bench_device

var _gen := 0                          # gün/oturum sayacı: eski bekleyen çağrıları iptal eder
var _arrival_t := 2.0
var _due_t := 0.0
var _vis_t := 0.0


func start() -> void:
	state = "none"
	Game.job_mgr = self
	carry.jobs = self
	add_child(carry)
	hud.set_job("Hoş geldin!", "Yeni oyun başlat ya da kaydı yükle.")
	Game.day_started.connect(begin_day)
	Game.day_ended.connect(_on_day_ended)
	Game.jobs_loaded.connect(func(): if Game.phase == "day": _rebuild_all())
	# tezgâh yeri: cihazı koymak için ince bir etkileşim alanı
	var o := pc_spot.origin
	MU.interactable(world, Vector3(0.8, 0.03, 0.6), Vector3(o.x, o.y - 0.004, o.z),
		func(p): return bench_hint(p), func(p): bench_use(p))


## Yeni gün: kuyruğu temizle, raftaki işlerin cihazlarını kayıttan yeniden kur, ilk müşteriyi çağır.
func begin_day() -> void:
	_gen += 1
	_clear_queue()
	_rebuild_all()
	_arrival_t = 2.0
	_due_t = 0.0
	_sync_head()


## Gün sonu: cihazların durumu kayda geçer, elde taşınan cihaz yerine konur.
func _on_day_ended(_s) -> void:
	_gen += 1
	if carry.active():
		return_carried()
	sync_states()


func _arrival_delay() -> float:
	var d := randf_range(14.0, 24.0) * Game.arrival_mult()
	if Game.jobs_active.size() >= Game.max_active_jobs():
		d *= 2.0  # raf doluyken daha seyrek gelir
	return d


func _process(delta: float) -> void:
	if Game.phase != "day":
		return
	# yeni müşteri gelişi (bırakma ya da tezgâh satışı)
	if arrivals_enabled and not Game.is_closed():
		_arrival_t -= delta
		if _arrival_t <= 0.0:
			if queue.size() < MAX_QUEUE:
				_spawn_arrival()
				_arrival_t = _arrival_delay()
			else:
				_arrival_t = 1.0
	# teslim günü gelen işlerin müşterileri + parça değişimi fark edenlerin geri dönüşü
	_due_t -= delta
	if _due_t <= 0.0:
		_due_t = 0.5
		_check_due()
		if Game.running and Game.clock >= 9.5:
			_check_theft_alerts()
	_vis_t -= delta
	if _vis_t <= 0.0:
		_vis_t = 0.5
		_refresh_visuals()
	if Game.running:
		_tick_patience(delta)
	# kapanış saati geldi ve kuyruk boş -> gün sonu
	if Game.is_closed() and queue.is_empty():
		Game.end_day()


# ---------------------------------------------------------------- kuyruk
func _enqueue(m: String, j: Dictionary, rec: Dictionary) -> Dictionary:
	var e := {"mode": m, "job": j, "rec": rec, "customer": null, "wait_t": 0.0, "arrived": false, "wrong": 0,
		"was_ready": not rec.is_empty() and str(rec.status) == "ready"}
	var c = CUSTOMER.new()
	c.position = SPAWN
	world.add_child(c)
	c.build(func(p): return _hint(e, p), func(p): _talk(e, p), str(j.name))
	c.inter.action_alt = func(p): _alt(e, p)
	c.say("")
	e.customer = c
	queue.append(e)
	_walk_to_slot(e)
	_sync_head()
	return e


func _walk_to_slot(e: Dictionary) -> void:
	var idx := queue.find(e)
	if idx < 0:
		return
	e.arrived = false
	var c = e.customer
	var pts := [LINE[idx]]
	if c.position.z > 3.3:
		pts.push_front(DOOR)
	c.walk(pts, func(): _arrived(e))


func _arrived(e: Dictionary) -> void:
	if not queue.has(e):
		return
	e.arrived = true
	e.customer.face_angle = PI
	if queue[0] == e:
		_on_head_ready()
	else:
		_sync_head()


## Müşteri tezgâha ulaştı (ya da öndeki gidince sıra ona geldi): derdini anlatır.
func _on_head_ready() -> void:
	_sync_head()
	var e: Dictionary = queue[0]
	var c = e.customer
	e.wait_t = 0.0
	match e.mode:
		"sale":
			c.say("Merhaba usta! " + str(e.job.intro))
		"pickup":
			c.say("Merhaba usta, #%d numaralı fişle geldim. Cihazım hazır mı?" % int(e.rec.ticket))
		_:
			c.say("Merhaba usta! " + str(e.job.intro))
	Game.msg("Bir müşteri geldi!" if e.mode != "pickup" else "%s cihazını almaya geldi (#%d)." % [e.job.name, int(e.rec.ticket)], Color(0.6, 0.9, 1.0))
	if e.mode == "pickup":
		hud.tip("pickup", "Teslim: müşterinin fiş numarasına bak, rafta o numaralı cihazı bul (E ile al), müşteriye dönüp E'ye bas. Hazır değilse önce tamir et.")
	else:
		hud.tip("talk", "Müşteriyle konuşmak için ona bakıp E'ye bas. Geri çevirmek için F.")


## Baştaki müşteri görünümünü (state/customer/job/mode) ve HUD kartını günceller.
func _sync_head() -> void:
	if queue.is_empty():
		customer = null
		job = {}
		mode = ""
		state = "closed" if Game.is_closed() else "none"
		hud.set_job("Dükkân kapandı" if state == "closed" else "Müşteri bekleniyor...", "")
		hud.set_patience(-1.0)
		return
	var e: Dictionary = queue[0]
	customer = e.customer
	job = e.job
	mode = e.mode
	state = "waiting" if e.arrived else "arriving"
	if not e.arrived:
		hud.set_job("%s geliyor..." % e.job.name, "")
		hud.set_patience(-1.0)
		return
	match e.mode:
		"sale":
			var w: Array = e.job.want
			hud.set_job("%s — %d TL" % [e.job.name, e.job.pay], e.job.goal + ("" if Game.stock_of(w[0], w[1]) > 0 else "\n\nStokta yok! ParçaNet'ten ekspres sipariş ver."))
		"pickup":
			hud.set_job("%s — %d TL" % [e.job.name, int(e.rec.pay)] if int(e.rec.pay) > 0 else "%s — GARANTİ" % e.job.name,
				"Fiş #%d: rafta bu numaralı cihazı bul, getirip müşteriye E'ye bas." % int(e.rec.ticket), int(e.rec.ticket))
		_:
			hud.set_job("Yeni müşteri: %s" % e.job.name, "Kabul: E  ·  Geri çevir: F\nRaf: %d / %d dolu" % [Game.jobs_active.size(), Game.max_active_jobs()], Game.next_ticket)


func _tick_patience(delta: float) -> void:
	for e in queue.duplicate():
		if not e.arrived:
			continue
		var head: bool = queue[0] == e
		e.wait_t += delta * (1.0 if head else 0.5)
		var lim := _patience_limit(e)
		if head:
			hud.set_patience(1.0 - e.wait_t / lim)
		if e.wait_t >= lim:
			_patience_out(e)


func _patience_limit(e: Dictionary) -> float:
	return WAIT_PATIENCE * Game.patience_mult() * (2.0 if e.mode == "sale" else (1.5 if e.mode == "pickup" else 1.0))


func _clear_queue() -> void:
	for e in queue:
		if is_instance_valid(e.customer):
			e.customer.queue_free()
	queue.clear()


## Müşteri sıradan çıkar, kapıdan gider; sıra ilerler.
func _finish_entry(e: Dictionary, line := "", angry := false, wait := 1.2) -> void:
	var c = e.customer
	queue.erase(e)
	if line != "" and is_instance_valid(c):
		c.say(line, angry)
	_advance_queue()
	var g := _gen
	await get_tree().create_timer(wait).timeout
	if is_instance_valid(c):
		c.say("")
		c.walk([INSIDE, DOOR, SPAWN], func(): c.queue_free())
	if g != _gen:
		return


func _advance_queue() -> void:
	for i in queue.size():
		var e: Dictionary = queue[i]
		if e.arrived and e.customer.position.distance_to(LINE[i]) < 0.1:
			continue
		_walk_to_slot(e)
	_sync_head()
	if not queue.is_empty() and queue[0].arrived:
		_on_head_ready()


## Teslim günü gelmiş işlerin müşterilerini kuyruğa alır.
func _check_due() -> void:
	if Game.is_closed():
		return
	var now := Game.now_abs()
	for rec in Game.jobs_active:
		if queue.size() >= MAX_QUEUE:
			return
		if rec.called or now < float(rec.due_abs):
			continue
		rec.called = true
		_enqueue("pickup", rec, rec)


## Testler/araçlar: bu işin müşterisini hemen çağırır.
func call_pickup(rec: Dictionary) -> void:
	if rec.called:
		return
	rec.called = true
	_enqueue("pickup", rec, rec)


func _spawn_arrival() -> void:
	var j: Dictionary = force_jobs.pop_front() if not force_jobs.is_empty() else _make_job()
	_enqueue("sale" if j.kind == "sale" else "dropoff", j, {})


## Sabır bitti: bırakma/satış müşterisi kızıp gider; teslim müşterisine ek gün verilir ya da cihazı alıp gider.
func _patience_out(e: Dictionary) -> void:
	var c = e.customer
	if e.mode == "pickup":
		_pickup_overdue(e)
		return
	var rep_loss := 0.4
	if e.job.get("warranty", false):
		rep_loss += WARRANTY.REP_ANGRY_EXTRA  # garanti müşterisini kızdırmak daha pahalı
	Game.change_rep(-rep_loss)
	Game.sfx.error()
	Game.msg("%s kızıp gitti! İtibar düştü." % e.job.name, Color(1, 0.5, 0.4))
	_finish_entry(e, "Çok bekledim usta, ben gidiyorum!", true, 1.5)


## Teslim müşterisi sabrını yitirdi (cihaz hazır değil ya da getirilmedi).
func _pickup_overdue(e: Dictionary) -> void:
	var rec: Dictionary = e.rec
	Game.sfx.error()
	if int(rec.ext) < 1:
		rec.ext = int(rec.ext) + 1
		rec.due_abs = float(rec.due_abs) + 24.0
		rec.called = false
		Game.change_rep(-LATE_REP)
		Game.msg("#%d gecikti: müşteri bir gün daha verdi (itibar düştü)." % int(rec.ticket), Color(1, 0.7, 0.4))
		_finish_entry(e, "Hazır değilse neden çağırdın usta! Bir gün daha veriyorum, yarın bu saatte gelirim.", true, 1.8)
		Game.jobs_changed.emit()
		return
	var loss := TAKEN_REP + (WARRANTY.REP_ANGRY_EXTRA if rec.get("warranty", false) else 0.0)
	Game.change_rep(-loss)
	Game.msg("#%d: müşteri cihazını tamir edilmeden alıp gitti! İtibar düştü." % int(rec.ticket), Color(1, 0.5, 0.4))
	_remove_record(rec, true)
	_finish_entry(e, "Yeter artık! Cihazımı olduğu gibi alıyorum, başka yere götüreceğim!", true, 1.8)


# ---------------------------------------------------------------- etkileşim (müşteri)
func _hint(e: Dictionary, p) -> String:
	if queue.is_empty() or queue[0] != e or not e.arrived:
		return "Sırada bekliyor: %s" % e.job.name
	match e.mode:
		"sale":
			var w: Array = e.job.want
			if p.held and not p.held.is_tool() and p.held.part_type == w[0] and p.held.tier == w[1] and not p.held.broken:
				return "Sat: %s — %d TL  [E]" % [PM.display_name(w[0], w[1]), e.job.pay]
			return "%s ile konuş  [E]" % e.job.name
		"pickup":
			var rec: Dictionary = e.rec
			if not carry.active():
				return "#%d numaralı cihazı rafta bul, getir" % int(rec.ticket)
			if carry.ticket() != int(rec.ticket):
				return "Bu #%d, müşteri #%d istiyor" % [carry.ticket(), int(rec.ticket)]
			return "%s  [E]" % DJ.deliver_hint(rec)
	if Game.jobs_active.size() >= Game.max_active_jobs():
		return "Raf dolu! Geri çevir: F  ·  %s" % e.job.name
	return "%s: işi kabul et  [E]   ·   Geri çevir: F" % e.job.name


## Baştaki müşteriye E (oyuncu ya da personel "p" olarak); testler ve araçlar da bunu çağırır.
func _customer_talk(p) -> void:
	if not queue.is_empty():
		_talk(queue[0], p)


func _talk(e: Dictionary, p) -> void:
	if queue.is_empty() or queue[0] != e or not e.arrived:
		return
	match e.mode:
		"sale": _try_sell(p)
		"pickup": _try_handover(e, p)
		_: _accept()


func _alt(e: Dictionary, _p) -> void:
	if queue.is_empty() or queue[0] != e or not e.arrived:
		return
	decline_head()


## Baştaki bırakma müşterisini geri çevir. Raf doluysa itibar kaybı yok; değilse küçük kayıp.
func decline_head() -> bool:
	if queue.is_empty() or queue[0].mode == "pickup" or not queue[0].arrived:
		return false
	var e: Dictionary = queue[0]
	var full: bool = Game.jobs_active.size() >= Game.max_active_jobs()
	if e.mode == "dropoff" and not full:
		Game.change_rep(-0.1)
		_finish_entry(e, "Hay aksi... Peki usta, başka yere bakarım.", true)
	elif e.mode == "dropoff":
		_finish_entry(e, "Tamam usta, yarın uğrarım.")
		Game.msg("Müşteriyi geri çevirdin (raf dolu, itibar kaybı yok).", Color(0.6, 0.9, 1.0))
	else:
		_finish_entry(e, "Peki usta, kolay gelsin.")
	return true


# ---------------------------------------------------------------- bırakma (kabul)
## Baştaki bırakma müşterisinin işini kabul eder: fiş kesilir, cihaz rafa konur, müşteri gider.
func _accept() -> bool:
	if queue.is_empty() or queue[0].mode != "dropoff" or not queue[0].arrived:
		return false
	var e: Dictionary = queue[0]
	var rec := drop_off(e.job)
	if rec.is_empty():
		Game.msg("Raf dolu! Önce bir işi teslim et ya da müşteriyi geri çevir (F).", Color(1, 0.6, 0.4))
		Game.sfx.error()
		e.customer.say("Rafta yer yok mu usta? Peki...")
		return false
	var when := ST.when_phrase(float(rec.due_abs), Game.day)
	var ex: String = "Bugün lazım usta, çok acil! " if rec.express else ""
	_finish_entry(e, "%sTamamdır usta, fiş #%d. %s." % [ex, int(rec.ticket), when], false, 2.2)
	Game.msg("Fiş #%d kesildi. Teslim: %s." % [int(rec.ticket), ST.due_label(float(rec.due_abs), Game.day)] + (" (EKSPRES +%20)" if rec.express else ""), Color(0.6, 0.9, 1.0))
	hud.dismiss_tip("talk")
	hud.tip("ticket", "İş rafa kondu. Sağ duvardaki Bekleyen İşler rafında cihazın fişine bakıp E'ye bas: cihazı alırsın. Masadaki mavi minderin üstüne koyup tamir et.")
	return true


## Bir işi kayda geçirir ve cihazını rafa koyar. Yer yoksa {}. (müşteri animasyonu çağıranın işi)
func drop_off(j: Dictionary) -> Dictionary:
	var slot := -1
	if rack != null:
		slot = rack.free_slot()
	if Game.jobs_active.size() >= Game.max_active_jobs() or slot < 0:
		return {}
	var now := Game.now_abs()
	var rec: Dictionary = j.duplicate(true)
	rec.pay = Game.job_pay(int(j.pay))  # itibar ve sertifika etkisi
	var due := ST.make_due(j, now, force_express)
	rec.due_abs = float(due.due_abs)
	rec.express = bool(due.express)
	if rec.express:
		rec.pay = roundi(int(rec.pay) * ST.EXPRESS_BONUS)
	rec.ticket = Game.next_ticket
	Game.next_ticket += 1
	rec.accepted_abs = now
	rec.status = "waiting_bench"
	rec.location = "rack:%d" % slot
	rec.ext = 0
	rec.wrong = 0
	rec.fail_count = 0
	rec.called = false
	rec.state = null
	Game.jobs_active.append(rec)
	var dev = _spawn_device(rec, true)
	_pop(dev)
	Game.jobs_changed.emit()
	return rec


## Kayıttan cihaz düğümünü kurar: bench ise tezgâha, değilse rafa (kayıtlı göz doluysa ilk boşa).
func _spawn_device(rec: Dictionary, fresh := false):
	var dev = DJ.new_device(rec) if DJ.is_device(rec) else PC.new()
	if not DJ.is_device(rec):
		var cid := str(rec.get("case_id", ""))
		if rec.state is Dictionary and not str(rec.state.get("case_id", "")).is_empty():
			cid = str(rec.state.get("case_id", ""))
		if not cid.is_empty():
			dev.case_id = cid
	dev.monitor = monitor
	var t := int(rec.ticket)
	var loc := str(rec.location)
	var on_bench := loc == "bench" and Game.bench_device == null
	if on_bench:
		world.add_child(dev)
		dev.transform = DJ.spot(dev, pc_spot)
	else:
		var i := -1
		if loc.begins_with("rack:"):
			i = int(loc.substr(5))
			if i < 0 or i >= RACK.SLOTS or rack.occ[i] != 0:
				i = -1
		if i < 0:
			i = rack.free_slot()
		if i < 0:  # kapasite küçüldüyse son çare: herhangi boş göz
			for k in RACK.SLOTS:
				if rack.occ[k] == 0:
					i = k
					break
		rack.put(i, dev, t)
		rec.location = "rack:%d" % i
	if rec.state is Dictionary:
		ST.restore(dev, rec.state)
	else:
		dev.fill(rec.parts)
	# müşteriden gelen tüm takılı parçaları işaretle; eksiltme/değiştirme kontrolü için başlangıç durumunu sakla
	var capture_orig: bool = fresh and not DJ.is_device(rec) and str(rec.get("kind", "")) != "build" and not bool(rec.get("warranty", false)) and not rec.has("orig_parts")
	var orig := {}
	for sn in dev.slots:
		var sp = dev.slots[sn].part
		if sp == null:
			continue
		if "origin" in sp and str(sp.origin) == "":
			sp.origin = "customer"
			sp.origin_ticket = t
		if capture_orig:
			var raw_sku: String = sp.sku if not sp.sku.is_empty() else DB.parts.id_for(sp.part_type, sp.tier)
			var sid: String = DB.parts.resolve_id(raw_sku) if not raw_sku.is_empty() else raw_sku
			orig[str(sn)] = {
				"sku": sid,
				"tier": int(sp.tier),
				"price": int(sp.value()),
				"broken": bool(sp.broken),
				"cheap": bool(sp.cheap),
				"name": str(sp.display_name),
			}
	if capture_orig and not orig.is_empty():
		rec["orig_parts"] = orig
	devices[t] = dev
	tags[t] = ST.attach_tag(dev, rec, func(_p): return _tag_hint(rec), func(p): _tag_use(rec, p))
	if on_bench:
		rec.location = "bench"
		rec.status = "on_bench"
		Game.set_bench_device(dev)
	else:
		rec.location = str(rec.location)
		ST.lock(dev, true)
		if str(rec.status) == "on_bench":
			rec.status = "waiting_bench"
	return dev


func _pop(dev) -> void:
	if dev == null or not is_instance_valid(dev):
		return
	var s: Vector3 = dev.scale
	dev.scale = Vector3.ONE * 0.05
	var tw: Tween = dev.create_tween()
	tw.tween_property(dev, "scale", s, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Game.sfx.click()


## Kayıtlı bütün cihazları silip kayıttan yeniden kurar (gün başı, yükleme).
func _rebuild_all() -> void:
	if carry.active():
		carry.release()
	for t in devices:
		var d = devices[t]
		if is_instance_valid(d):
			if d.get_parent():
				d.get_parent().remove_child(d)
			d.queue_free()
	devices.clear()
	tags.clear()
	busy.clear()
	Game.set_bench_device(null)
	rack.occ.fill(0)
	for rec in Game.jobs_active:
		rec.called = false
		_spawn_device(rec)
	_refresh_visuals()
	Game.jobs_changed.emit()


## Cihaz düğümlerindeki durumu kayıtlara yazar (kayıt/gün sonu).
func sync_states() -> void:
	for rec in Game.jobs_active:
		var d = devices.get(int(rec.ticket))
		if d != null and is_instance_valid(d):
			rec.state = ST.snapshot(d)


## İş kaydını ve cihazını kaldırır (teslim/alıp gitme). shrink: küçülüp kaybolur.
func _remove_record(rec: Dictionary, shrink := true, toward := Vector3.INF) -> void:
	var t := int(rec.ticket)
	var d = devices.get(t)
	if carry.active() and carry.ticket() == t:
		carry.release()
	if Game.bench_device == d and d != null:
		Game.set_bench_device(null)
	rack.clear_slot(t)
	devices.erase(t)
	tags.erase(t)
	busy.erase(t)
	for i in Game.jobs_active.size():
		if int(Game.jobs_active[i].ticket) == t:
			Game.jobs_active.remove_at(i)
			break
	if d != null and is_instance_valid(d):
		if d.powered:
			d.power_off()
		if d.get_parent() != world and d.get_parent() != rack:
			d.reparent(world, true)  # elde taşınıyordu: müşteriye uzanıp küçülür
		var tw := create_tween()
		if toward != Vector3.INF:
			tw.tween_property(d, "global_position", toward, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			tw.tween_interval(0.3)
		if shrink:
			tw.tween_property(d, "scale", Vector3.ONE * 0.01, 0.4)
		tw.tween_callback(func():
			if is_instance_valid(d):
				d.queue_free())
		ST.lock(d, true)
	Game.jobs_changed.emit()


# ---------------------------------------------------------------- taşıma
func _tag_hint(rec: Dictionary) -> String:
	var now := Game.now_abs()
	var base := "Fiş #%d · %s · %s · %s" % [int(rec.ticket), rec.name, ST.due_label(float(rec.due_abs), Game.day), ST.status_text(rec, now)]
	var t := int(rec.ticket)
	if busy.has(t):
		return base + " — personel çalışıyor"
	if carry.active():
		return base + (" (elin dolu)" if carry.ticket() != t else "")
	return base + "  [E] Al"


func _tag_use(rec: Dictionary, p) -> void:
	pick_up_device(rec, p)


## Cihazı rafdan/tezgâhtan alıp taşımaya başlar. Hata metni döner ("" = alındı).
func pick_up_device(rec: Dictionary, p = null) -> String:
	var t := int(rec.ticket)
	if carry.active():
		Game.msg("Elin dolu: önce taşıdığın cihazı bırak.", Color(1, 0.8, 0.4))
		return "elin dolu"
	if p != null and p.held != null:
		Game.msg("Elin dolu: önce elindeki parçayı bırak.", Color(1, 0.8, 0.4))
		return "elin dolu"
	if busy.has(t):
		Game.msg("Bu cihazda personel çalışıyor.", Color(1, 0.8, 0.4))
		return "meşgul"
	var dev = devices.get(t)
	if dev == null or not is_instance_valid(dev) or str(rec.location) == "carry":
		return "yok"
	var from := str(rec.location)
	if from == "bench":
		Game.set_bench_device(null)
	else:
		rack.clear_slot(t)
	rec.location = "carry"
	carry.start(rec, dev, from)
	Game.jobs_changed.emit()
	hud.dismiss_tip("ticket")
	if str(rec.status) != "ready":
		hud.tip("bench", "Cihazı masadaki mavi minderin üstüne koymak için minderine bakıp E'ye bas. Tamirden sonra rafa geri koy: hazırsa yeşil yanar.")
	return ""


func rack_hint(i: int, _p) -> String:
	if i >= Game.max_active_jobs():
		return "Kilitli göz — iş kapasiten artınca açılır"
	var t: int = rack.occ[i]
	if t == 0:
		if carry.active():
			return "Rafa koy: #%d %s  [E]" % [carry.ticket(), carry.rec.name]
		return "Boş göz %d" % (i + 1)
	var r := Game.job_by_ticket(t)
	return _tag_hint(r) if not r.is_empty() else ""


func rack_use(i: int, p) -> void:
	if i >= Game.max_active_jobs():
		return
	var t: int = rack.occ[i]
	if carry.active():
		if t == 0:
			place_on_rack(i)
		else:
			Game.msg("Bu göz dolu.", Color(1, 0.8, 0.4))
		return
	if t != 0 and not Game.job_by_ticket(t).is_empty():
		pick_up_device(Game.job_by_ticket(t), p)


func bench_hint(_p) -> String:
	if carry.active():
		if Game.bench_device != null:
			return "Tezgâh dolu: önce üstündekini rafa koy"
		return "Tezgâha koy: #%d %s  [E]" % [carry.ticket(), carry.rec.name]
	if Game.bench_device != null:
		return ""
	return "Tezgâh boş: rafın üzerindeki bir işi alıp buraya koy"


func bench_use(_p) -> void:
	if carry.active() and Game.bench_device == null:
		place_on_bench()


## Taşınan cihazı rafın i. gözüne koyar ve hazır olup olmadığına bakar.
func place_on_rack(i: int) -> bool:
	if not carry.active() or i < 0 or i >= Game.max_active_jobs() or rack.occ[i] != 0:
		return false
	var rec: Dictionary = carry.rec
	var dev = carry.release()
	rack.occupy(i, int(rec.ticket))
	carry.settle(dev, rack, rack.slot_transform(i, dev))
	rec.location = "rack:%d" % i
	Game.sfx.pickup()
	_check_ready(rec, true)
	Game.jobs_changed.emit()
	return true


## Taşınan cihazı tezgâh yerine koyar (bir tezgâh yeri var; ileride çoğaltılabilir).
func place_on_bench() -> bool:
	if not carry.active() or Game.bench_device != null:
		return false
	var rec: Dictionary = carry.rec
	var dev = carry.release()
	carry.settle(dev, world, DJ.spot(dev, pc_spot))
	ST.lock(dev, false)
	Game.set_bench_device(dev)
	rec.location = "bench"
	rec.status = "on_bench"
	Game.sfx.pickup()
	if not rec.get("benched", false):
		rec["benched"] = true
		if DJ.is_device(rec):
			DJ.on_accept(hud, rec)
		else:
			Game.msg("Bilgisayar masana kondu. Kapağı açıp incele!", Color(0.6, 0.9, 1.0))
			hud.dismiss_tip("bench")
			hud.tip("glass", "Kapağı açmak için bilgisayarın camına bakıp E'ye bas.")
			hud.tip("leds", "Güç düğmesine bas; bip seslerini ve anakartın hata LED'lerini izle. Duvardaki Arıza Rehberi yardımcı olur.")
	Game.jobs_changed.emit()
	return true


## G / sağ tık: cihazı geldiği yere (dolu değilse) geri koyar.
func return_carried() -> void:
	if not carry.active():
		return
	if carry.origin == "bench" and Game.bench_device == null:
		place_on_bench()
		return
	var i := -1
	if carry.origin.begins_with("rack:"):
		i = int(carry.origin.substr(5))
	if i < 0 or i >= Game.max_active_jobs() or rack.occ[i] != 0:
		i = rack.free_slot()
	if i >= 0:
		place_on_rack(i)
	elif Game.bench_device == null:
		place_on_bench()


## Cihaz rafa konduğunda: hata yoksa "hazır". verbose: oyuncuya sonucu bildir.
func _check_ready(rec: Dictionary, verbose := false) -> bool:
	var prob := _problem_of(rec)
	if prob == "":
		if str(rec.status) != "ready":
			rec.status = "ready"
			rec.ready_abs = Game.now_abs()
			if verbose:
				Game.msg("#%d hazır! Müşteri %s gelecek." % [int(rec.ticket), ST.due_label(float(rec.due_abs), Game.day)], Color(0.5, 1, 0.5))
				Game.sfx.click()
				hud.tip("ready", "Hazır işler rafta yeşil yanar. Müşteri teslim saatinde gelir; cihazı raftan alıp müşteriye E ile ver.")
		return true
	rec.status = "waiting_bench"
	if verbose:
		var hint := _problem_hint_of(rec)
		Game.msg("#%d henüz hazır değil: %s" % [int(rec.ticket), hint if hint != "" else prob], Color(1.0, 0.8, 0.4))
	return false


# ---------------------------------------------------------------- teslim
## Cihazın teslim kontrolü ("" = sorun yok): test parçası, tüm arızalar, hedef, kapak, vidalar.
func _problem_of(rec: Dictionary) -> String:
	var dev = devices.get(int(rec.ticket))
	if dev == null or not is_instance_valid(dev):
		return "Cihaz yok"
	if DJ.is_device(rec):  # laptop / telefon kendi kontrolünü yapar
		return dev.problem()
	for p in dev.installed_parts():
		if "is_test_part" in p and p.is_test_part:
			return "Usta kendi test parçanı kasanın içinde unutmuşsun!"
	var issues: Array = dev.diagnose_all() if dev.has_method("diagnose_all") else []
	if not issues.is_empty():
		var f = _fault_of(dev, str(issues[0]))
		var lines: Array = f.fail_lines if f != null else []
		return lines.pick_random() if not lines.is_empty() else DB.jobs.text("fail_default")[0]
	var tg: Dictionary = rec.get("target", {})
	if tg.has("min_tier"):
		var g = dev.part_in(str(tg.part))
		if g == null or g.tier < int(tg.min_tier):
			return str(tg.fail)
	if tg.has("ram_gb"):
		if dev.total_ram() < int(tg.ram_gb):
			return str(tg.fail) % dev.total_ram()
	if dev.panel_open:
		return "Kapağı kapatmadan mı vereceksin usta?"
	if dev.has_method("screws_missing") and dev.screws_missing():
		return "Usta vidaları sıkmadan mı veriyorsun? (%s)" % dev.missing_screws_text()
	return ""


## Teşhis koduna uyan arıza tanımı; aşırı ısınmada toz mu macun mu olduğuna bakılır.
func _fault_of(dev, code: String):
	if code == "overheat":
		return DB.jobs.fault("overheat_dust" if dev.dust > 0.5 else "overheat_paste")
	return DB.jobs.fault_by_code(code)


## Teslim reddedilince oyuncuya HUD'da teknik ipucu (müşteri cümlesinden ayrı).
func _problem_hint_of(rec: Dictionary) -> String:
	var dev = devices.get(int(rec.ticket))
	if dev == null or not is_instance_valid(dev):
		return ""
	if DJ.is_device(rec):
		var dc: String = dev.diagnose()
		if dc != "ok":
			var df = DB.jobs.fault_by_code(dc, str(rec.device))
			return df.hint if df != null else ""
		return ""
	var issues: Array = dev.diagnose_all() if dev.has_method("diagnose_all") else []
	if not issues.is_empty():
		var f = _fault_of(dev, str(issues[0]))
		var h := str(f.hint) if f != null else ""
		if issues.size() > 1 and h != "":
			h += " (+%d sorun daha)" % (issues.size() - 1)
		return h
	if dev.has_method("screws_missing") and dev.screws_missing():
		return "İpucu: Eksik vidaları tornavidayla sık (%s)." % dev.missing_screws_text()
	return ""


## Müşteriye E: taşınan cihazı teslim etmeye çalış.
func _try_handover(e: Dictionary, _p) -> void:
	var rec: Dictionary = e.rec
	var c = e.customer
	if not carry.active():
		c.say("Fiş numaram #%d usta. Cihazımı getirsene!" % int(rec.ticket))
		Game.msg("Rafta #%d numaralı cihazı bul, E ile alıp müşteriye getir." % int(rec.ticket), Color(1.0, 0.8, 0.4))
		return
	if carry.ticket() != int(rec.ticket):
		e.wrong = int(e.wrong) + 1
		c.say(_wrong_line(carry.rec, rec), true)
		Game.sfx.error()
		if int(e.wrong) <= 3:
			Game.change_rep(-0.1)
		Game.msg("Yanlış cihaz! #%d lazımdı, sen #%d getirdin." % [int(rec.ticket), carry.ticket()], Color(1, 0.6, 0.4))
		return
	var problem := _problem_of(rec)
	if problem != "":
		c.say(problem, true)
		var hint := _problem_hint_of(rec)
		if hint != "":
			Game.msg(hint, Color(1.0, 0.8, 0.4))
		Game.sfx.error()
		rec.fail_count = int(rec.fail_count) + 1
		if int(rec.fail_count) <= 3:
			Game.change_rep(-0.05)
		return
	_complete(e)


func _wrong_line(got: Dictionary, want: Dictionary) -> String:
	var lines := [
		"Usta bu benimki değil! Benimkinin üstünde #%d yazıyor!" % int(want.ticket),
		"Bu %s benim değil, başkasının cihazını mı veriyorsun?!" % ("laptop" if str(got.get("device", "")) == "laptop" else ("telefon" if str(got.get("device", "")) == "phone" else "kasa")),
		"Ya usta, fişe bakmadın mı? #%d diyorum!" % int(want.ticket),
		"Bu %s'ın cihazı! Benimkini ver usta!" % str(got.name),
	]
	return lines.pick_random()


## Teslim kontrolü: müşterinin çalışan parçalarından eksilen veya daha düşük değerliye indirilen var mı?
func audit_parts(rec: Dictionary, dev = null) -> Dictionary:
	var out := {"stolen_items": [], "stolen_value": 0, "catch_chance": 0.0}
	if rec.is_empty() or DJ.is_device(rec) or str(rec.get("kind", "")) == "build" or bool(rec.get("warranty", false)):
		return out
	var d = dev if dev != null else devices.get(int(rec.get("ticket", -1)))
	if d == null or not is_instance_valid(d):
		return out
	var orig_parts = rec.get("orig_parts", {})
	if not (orig_parts is Dictionary) or orig_parts.is_empty():
		return out
	var critical_missing := false
	for sn in orig_parts:
		var op = orig_parts[sn]
		if not (op is Dictionary) or bool(op.get("broken", false)):
			continue
		var orig_price: int = int(op.get("price", 0))
		var cur = d.part_in(str(sn)) if d.has_method("part_in") else null
		if cur == null:
			out.stolen_items.append({"kind": "missing", "slot": str(sn), "orig_name": str(op.get("name", sn)), "cur_name": "", "diff": orig_price})
			out.stolen_value += orig_price
			if str(sn) in ["gpu", "cpu", "psu", "mobo"]:
				critical_missing = true
		else:
			var cur_price: int = int(cur.value())
			var downgraded: bool = cur_price < orig_price - 5
			var cheap_swap: bool = (not bool(op.get("cheap", false))) and bool(cur.cheap) and cur_price <= orig_price + 5
			if downgraded or cheap_swap:
				var diff: int = maxi(10, orig_price - cur_price)
				out.stolen_items.append({"kind": "downgrade", "slot": str(sn), "orig_name": str(op.get("name", sn)), "cur_name": str(cur.display_name), "diff": diff})
				out.stolen_value += diff
	if not out.stolen_items.is_empty():
		if int(out.stolen_value) >= 100 or critical_missing:
			out.catch_chance = 0.55
		elif int(out.stolen_value) >= 40:
			out.catch_chance = 0.35
		else:
			out.catch_chance = 0.20
	return out


func _check_theft_alerts() -> void:
	for i in range(Game.theft_alerts.size() - 1, -1, -1):
		var a: Dictionary = Game.theft_alerts[i]
		if int(a.get("due", 999)) <= Game.day:
			Game.theft_alerts.remove_at(i)
			var refund: int = maxi(15, roundi(float(a.get("value", 30)) * 0.5))
			Game.add_money(-refund, false)
			Game.change_rep(-0.4)
			Game.sfx.error()
			if hud:
				hud.pop_money(-refund)
			Game.msg("%s evde %s değişimini fark edip 1 yıldız yorum attı! (-%d TL iade, -0.4 itibar)" % [
				str(a.get("name", "Müşteri")), str(a.get("item", "parça")), refund], Color(1.0, 0.45, 0.3))


## Başarılı teslim: ödeme, itibar, istatistik; cihaz müşteriyle gider.
func _complete(e: Dictionary) -> void:
	var rec: Dictionary = e.rec
	var c = e.customer
	var dev = devices.get(int(rec.ticket))
	var audit := audit_parts(rec, dev)
	var stole_something: bool = not audit.stolen_items.is_empty()
	if stole_something:
		var caught: bool = (theft_catch_override >= 0.5) if theft_catch_override >= 0.0 else (randf() < float(audit.catch_chance))
		if caught:
			var first: Dictionary = audit.stolen_items[0]
			var fine: int = maxi(25, roundi(float(audit.stolen_value) * 0.75))
			var rep_loss: float = clampf(0.45 + float(audit.stolen_value) * 0.002, 0.5, 0.85)
			Game.add_money(-fine, false)
			Game.change_rep(-rep_loss)
			Game.sfx.error()
			if hud:
				hud.pop_money(-fine)
			Game.msg("YAKALANDIN! %s parça değişimini fark etti (-%d TL tazminat, -%.1f itibar)!" % [
				str(rec.name), fine, rep_loss], Color(1.0, 0.3, 0.25))
			var line := ("Usta dur bi saniye! Benim %s nereye uçtu?! Parçamı çalmışsın!" % str(first.orig_name)) if str(first.kind) == "missing" else (
				"Hey usta, benim %s vardı içinde, bu %s ne?! Beni mi kandırıyorsun?!" % [str(first.orig_name), str(first.cur_name)])
			_remove_record(rec, true, c.global_position + Vector3(0, 1.0, 0.1))
			_finish_entry(e, line, true, 2.2)
			return
	WARRANTY.on_delivered(dev, rec)  # muadil parça takıldıysa geri dönüş riski kaydedilir
	# erken bitirme: hazır olduğu an, kabul ile teslim arasının ilk yarısındaysa "hızlı"
	var ready_t: float = float(rec.get("ready_abs", Game.now_abs()))
	var span: float = maxf(float(rec.due_abs) - float(rec.accepted_abs), 1.0)
	var fast: bool = e.was_ready and (float(rec.due_abs) - ready_t) >= span * 0.5
	# müşteri tezgâhta uzun beklediyse (sabrının %35'inden fazla) iş "zamanında" sayılmaz
	var on_time: bool = e.was_ready or float(e.wait_t) < 0.35 * _patience_limit(e)
	if rec.get("warranty", false):
		var wf: bool = fast or on_time
		Game.change_rep(WARRANTY.REP_FAST if wf else WARRANTY.REP_SLOW)
		Game.cash_sound()
		Game.msg("Garanti işi tamamlandı" + ("  (hızlı servis, itibar düzeldi)" if wf else "."), Color(0.6, 0.9, 1.0))
		_remove_record(rec, true, c.global_position + Vector3(0, 1.0, 0.1))
		_finish_entry(e, ["Tamam usta, bu sefer sağlam olsun!", "Sağ ol usta, garanti dediğin böyle olur."].pick_random())
		return
	var tip := 0
	var tip_notes: Array[String] = []
	if not DJ.is_device(rec) and dev != null and is_instance_valid(dev):
		if "cables_tidy" in dev and dev.cables_tidy:
			tip += 30
			tip_notes.append("kablo düzeni +30 TL")
		if bool(rec.get("had_dust", false)) and "dust" in dev and dev.dust <= 0.04:
			tip += 20
			tip_notes.append("temizlik +20 TL")
	var total_pay := int(rec.pay) + tip
	Game.add_money(total_pay)
	Game.jobs_done += 1
	Game.jobs_today += 1
	Game.stats.total_jobs = int(Game.stats.total_jobs) + 1
	Game.change_rep(0.25 if fast else (0.15 if on_time else 0.05))
	Game.cash_sound()
	hud.pop_money(total_pay)
	var extra_msg := ("  (" + ", ".join(tip_notes) + ")" if not tip_notes.is_empty() else "")
	Game.msg("+%d TL kazandın!" % total_pay + ("  (hızlı servis, itibar arttı)" if fast else "") + extra_msg, Color(0.5, 1, 0.5))
	if stole_something:
		Game.msg("%s parça değişimini fark etmedi! (Tahmini kâr: ~%d TL)" % [str(rec.name), int(audit.stolen_value)], Color(0.95, 0.78, 0.3))
		if theft_catch_override < 0.0 and randf() < 0.35:
			Game.theft_alerts.append({
				"due": Game.day + randi_range(1, 2),
				"name": str(rec.name),
				"item": str(audit.stolen_items[0].orig_name),
				"value": int(audit.stolen_value),
			})
	_remove_record(rec, true, c.global_position + Vector3(0, 1.0, 0.1))
	_finish_entry(e, ["Eline sağlık usta, sağ ol!", "Helal olsun, tıkır tıkır çalışıyor!",
		"Çok teşekkürler, herkese seni önereceğim!"].pick_random())


## Personel: raftaki hazır cihazı baştaki teslim müşterisine verir (taşıma animasyonsuz). Başarı true.
func staff_handover() -> bool:
	if queue.is_empty() or queue[0].mode != "pickup" or not queue[0].arrived:
		return false
	var e: Dictionary = queue[0]
	var rec: Dictionary = e.rec
	if str(rec.location) == "carry" or busy.has(int(rec.ticket)):
		return false
	if _problem_of(rec) != "":
		return false
	_complete(e)
	return true


## Teknisyenin işini bitirdiği cihazı kontrol edip "hazır" yapar (rafta).
func staff_finished(rec: Dictionary) -> bool:
	return _check_ready(rec, true)


## Tezgâh satışı: oyuncu doğru parçayı elinde tutarak konuşursa satılır.
func _try_sell(p) -> void:
	if queue.is_empty() or queue[0].mode != "sale":
		return
	var e: Dictionary = queue[0]
	var j: Dictionary = e.job
	var w: Array = j.want
	var dname := PM.display_name(w[0], w[1])
	var h = p.held if p else null
	if h == null or h.is_tool() or h.part_type != w[0] or h.tier != w[1] or h.broken:
		if h != null and not h.is_tool() and h.part_type == w[0]:
			e.customer.say("Yok usta, bu değil. Bana %s lazım." % dname, true)
			Game.sfx.error()
		elif Game.stock_of(w[0], w[1]) > 0:
			e.customer.say("Raftan bir %s getiriver usta, bekliyorum." % dname)
		else:
			e.customer.say("Stokta yok mu? Getirtebilirsen beklerim ama çok değil usta.")
		hud.tip("sale", "Parça satışı: raftan istenen parçayı al, elinde tutarken müşteriye E'ye bas.")
		return
	var part = p.release_held()
	if part.cheap:
		j.pay = roundi(int(j.pay) * Game.CHEAP_FACTOR)  # muadil parça daha ucuza satılır
	part.queue_free()
	Game.add_money(int(j.pay))
	Game.sales_today += 1
	Game.stats.total_sales = int(Game.stats.get("total_sales", 0)) + 1
	Game.change_rep(0.08)
	Game.cash_sound()
	hud.pop_money(int(j.pay))
	hud.dismiss_tip("sale")
	Game.msg("%s satıldı: +%d TL" % [dname, j.pay], Color(0.5, 1, 0.5))
	_finish_entry(e, ["Sağ ol usta, hayırlı işler!", "Tamamdır, eline sağlık!", "Tam aradığım buydu, teşekkürler!"].pick_random())


# ---------------------------------------------------------------- görünüm
## Raf ışıkları ve fiş şeritleri (kehribar / yeşil / kırmızı).
func _refresh_visuals() -> void:
	var recs := {}
	for r in Game.jobs_active:
		recs[int(r.ticket)] = r
	var now := Game.now_abs()
	rack.refresh(now, recs)
	for t in tags:
		if recs.has(t) and is_instance_valid(tags[t].root):
			var c := ST.status_color(recs[t], now)
			var sm: StandardMaterial3D = tags[t].stripe
			sm.albedo_color = c
			sm.emission_enabled = true
			sm.emission = c


# ---------------------------------------------------------------- araç / test yardımcıları
## Bırakma + hemen tezgâha: işi kabul eder, cihazı doğrudan tezgâha koyar ve cihazı döndürür (taşıma animasyonsuz).
func dev_bench_job(j: Dictionary):
	var rec := drop_off(j)
	if rec.is_empty():
		return null
	return dev_to_bench(rec)


func dev_to_bench(rec: Dictionary):
	if Game.bench_device != null:
		return null
	var dev = devices[int(rec.ticket)]
	rack.clear_slot(int(rec.ticket))
	dev.reparent(world, false)
	dev.transform = DJ.spot(dev, pc_spot)
	ST.lock(dev, false)
	Game.set_bench_device(dev)
	rec.location = "bench"
	rec.status = "on_bench"
	Game.jobs_changed.emit()
	return dev


## Tezgâhtaki işi "elde taşıma" yoluyla teslime hazırla (oyuncu E'ye basmış gibi).
func dev_carry(rec: Dictionary, p = null) -> String:
	return pick_up_device(rec, p)


## Personelin üzerinde çalışmadığı, rafta bekleyen masaüstü işleri (teknisyen için).
func tech_candidates() -> Array:
	var out := []
	for rec in Game.jobs_active:
		if str(rec.status) != "waiting_bench" or not str(rec.location).begins_with("rack:") or busy.has(int(rec.ticket)):
			continue
		if DJ.is_device(rec):
			continue
		out.append(rec)
	return out


# ---------------------------------------------------------------- iş üretimi
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
		"incompat": return _job_incompat(j, t)
		"cable": return _job_cable(j, t)
		"software": return _job_software(j, t)
		"multi": return _job_multi(j, t)
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


## Yükseltme ve sıfırdan toplama: uyumlu PC profili (veya boş kasa), formül ücret, isteğe bağlı teslim koşulu.
func _job_plain(j: Dictionary, t) -> Dictionary:
	j.kind = t.job_kind
	j.intro = t.intro
	j.goal = t.goal
	j.pay = _template_pay(t)
	if t.with_base_parts:
		var prof := _progression_profile(t.profile.duplicate(true))
		if t.job_kind == "upgrade_gpu":
			prof["cases"] = ["atx_mid", "matx_mini"]
			prof["need_gpu"] = true
			prof["max_gpu_tier"] = 1
			prof["min_psu_watts"] = 550
		elif t.job_kind == "upgrade_ram":
			prof["ram_count"] = 1
			prof["max_ram_gb"] = 16
		var built := _build_compatible_pc(prof)
		j.case_id = built.case_id
		j.parts = built.parts
	else:
		j.case_id = "atx_mid" if Game.day <= 2 else ["atx_mid", "matx_mini", "itx_compact"].pick_random()
		j.parts = []
	if not t.target.is_empty():
		j.target = t.target
	if t.hours > 0.0:
		j.hours = t.hours
	return j


## PC parça/ayar listesine tek bir FaultDef arızasını işler; ücret hesabı için {sku, need_pay} döndürür.
func _apply_fault_to_parts(parts: Array, f) -> Dictionary:
	var res := {"sku": "", "need_pay": false}
	if f == null:
		return res
	var find_slots := func(cat: String) -> Array:
		var out := []
		for p in parts:
			if p is Dictionary and p.has("sku"):
				var d: PartDef = DB.parts.get_def(str(p.sku))
				if d != null and d.category == cat:
					out.append(p)
		return out
	match f.kind:
		"broken":
			var targets: Array = find_slots.call(f.part)
			if not targets.is_empty():
				var ch: Dictionary = targets.pick_random()
				ch["broken"] = true
				res.sku = str(ch.sku)
				res.need_pay = true
			elif f.part != "":
				res.sku = DB.parts.id_for(f.part, 1)
				res.need_pay = true
		"pin_bend":
			for p in parts:
				if p is Dictionary and str(p.get("slot", "")) == "cpu":
					p["bent_pins"] = true
					break
		"unseated":
			var rams: Array = find_slots.call("ram")
			if not rams.is_empty():
				var rp: Dictionary = rams.pick_random()
				rp["seated"] = false
		"vram_fault":
			var gpus: Array = find_slots.call("gpu")
			if not gpus.is_empty():
				var gp: Dictionary = gpus.pick_random()
				gp["vram_bad"] = true
				res.sku = str(gp.sku)
				res.need_pay = true
		"smart_fail":
			var hdds: Array = find_slots.call("hdd")
			if hdds.is_empty():
				hdds = find_slots.call("ssd")
			if not hdds.is_empty():
				var hd: Dictionary = hdds.pick_random()
				hd["health"] = randi_range(8, 26)
				res.sku = str(hd.sku)
				res.need_pay = true
		"capacitor":
			for p in parts:
				if p is Dictionary and str(p.get("slot", "")) == "mobo":
					p["bad_caps"] = true
					res.sku = str(p.sku)
					res.need_pay = true
					break
		"overheat":
			if f.paste_dry:
				for p in parts:
					if p is Dictionary and str(p.get("slot", "")) == "cpu":
						p["paste_ok"] = false
			if randf() < f.dust_chance:
				parts.append({"slot": "dust", "amount": randf_range(f.dust.x, f.dust.y)})
		"cable":
			var c_entry = null
			for p in parts:
				if p is Dictionary and p.has("cables"):
					c_entry = p
					break
			if c_entry == null:
				c_entry = {"cables": {}}
				parts.append(c_entry)
			c_entry.cables[f.cable] = "unplugged"
		"software":
			var s_entry = null
			for p in parts:
				if p is Dictionary and p.has("sw_faults"):
					s_entry = p
					break
			if s_entry == null:
				s_entry = {"sw_faults": []}
				parts.append(s_entry)
			if not s_entry.sw_faults.has(f.sw_flag):
				s_entry.sw_faults.append(f.sw_flag)
	return res


## İsteğe bağlı kozmetik toz (%40 şans, müşteri şikayet etmez ama temizleyene bahşiş verilir).
func _maybe_add_cosmetic_dust(j: Dictionary, parts: Array) -> void:
	if randf() < 0.4:
		parts.append({"slot": "dust", "amount": randf_range(0.18, 0.38)})
		j.had_dust = true


func _job_repair(j: Dictionary, t) -> Dictionary:
	var f = DB.jobs.fault(t.fault)
	j.kind = t.job_kind
	j.broken = f.diag_code if f.part == "" else f.part
	j.intro = _intro_of(t, f)
	j.goal = t.goal
	var prof: Dictionary = t.profile.duplicate(true)
	prof["ram2_chance"] = t.ram2_chance
	if f.part == "gpu" or f.kind == "vram_fault":
		prof["need_gpu"] = true
	if f.part == "ssd":
		prof["need_sata"] = true
		prof["sata_sku"] = "ssd_sata_512"
	elif f.part == "hdd":
		prof["need_sata"] = true
		prof["sata_sku"] = "hdd_sata_1t"
	prof = _progression_profile(prof)
	var built := _build_compatible_pc(prof)
	var parts: Array = built.parts
	var applied := _apply_fault_to_parts(parts, f)
	_maybe_add_cosmetic_dust(j, parts)
	j.case_id = built.case_id
	j.parts = parts
	j.pay = (PM.price_sku(applied.sku) if applied.need_pay and not str(applied.sku).is_empty() else 0) + f.roll_labor()
	return j


## Aşırı ısınma işi: uyumlu PC + kasa tozu veya kurumuş CPU macunu.
func _job_overheat(j: Dictionary, t) -> Dictionary:
	var f = DB.jobs.fault(t.fault)
	j.kind = t.job_kind
	j.intro = _intro_of(t, f)
	j.goal = t.goal
	j.pay = f.roll_labor()
	var prof := _progression_profile(t.profile.duplicate(true))
	if f.paste_dry and Game.day <= 2:
		prof["socket"] = "AM4"
	var built := _build_compatible_pc(prof)
	var parts: Array = built.parts
	_apply_fault_to_parts(parts, f)
	j.case_id = built.case_id
	j.parts = parts
	return j


## Bilerek uyumsuz PC işleri: DDR çentiği, PSU/GPU güç/konnektör, iGPU'suz işlemci, PSU watt yetersizliği.
func _job_incompat(j: Dictionary, t) -> Dictionary:
	var f = DB.jobs.fault(t.fault)
	j.kind = t.job_kind
	j.broken = f.part
	j.intro = _intro_of(t, f)
	j.goal = t.goal
	var built := {}
	var ref_sku := DB.parts.id_for(f.part, 1)
	match t.fault:
		"incompat_ram_ddr":
			var want_ddr5 := randf() < 0.5
			built = _build_compatible_pc({
				"ram_type": "DDR5" if want_ddr5 else "DDR4",
				"ram_count": 1,
			})
			var wrong_ram := "ram_ddr4_8g" if want_ddr5 else "ram_ddr5_16g"
			ref_sku = "ram_ddr5_16g" if want_ddr5 else "ram_ddr4_8g"
			for p in built.parts:
				if str(p.slot) == "ram1":
					p["sku"] = wrong_ram
		"incompat_psu_gpu":
			built = _build_compatible_pc({
				"case_id": "atx_mid",
				"need_gpu": true,
				"gpu_sku": "gpu_flagship_16g",
			})
			var weak_psu: String = ["psu_450w", "psu_550w"].pick_random()
			ref_sku = "psu_750w"
			for p in built.parts:
				if str(p.slot) == "psu":
					p["sku"] = weak_psu
		"incompat_no_igpu":
			var sock: String = ["AM4", "LGA1700"].pick_random()
			built = _build_compatible_pc({
				"socket": sock,
				"igpu": false,
				"need_gpu": true,
			})
			ref_sku = "gpu_entry_4g"
			built.parts = built.parts.filter(func(p): return str(p.slot) != "gpu")
		"psu_underwatt":
			built = _build_compatible_pc({
				"case_id": "atx_mid",
				"socket": "AM5",
				"cpu_sku": "cpu_am5_12c",
				"need_gpu": true,
				"gpu_sku": "gpu_gamer_12g",
				"ram_count": 2,
				"need_sata": true,
			})
			ref_sku = "psu_550w"
			for p in built.parts:
				if str(p.slot) == "psu":
					p["sku"] = "psu_450w"
		_:
			built = _build_compatible_pc({})
	j.case_id = built.case_id
	j.parts = built.parts
	j.pay = PM.price_sku(ref_sku) + f.roll_labor()
	return j


## Gevşek / takılmamış kablo işi.
func _job_cable(j: Dictionary, t) -> Dictionary:
	var f = DB.jobs.fault(t.fault)
	j.kind = t.job_kind
	j.broken = f.diag_code
	j.intro = _intro_of(t, f)
	j.goal = t.goal
	var prof: Dictionary = t.profile.duplicate(true)
	if f.cable == "pcie_gpu":
		prof["need_gpu"] = true
		prof["gpu_sku"] = "gpu_mid_8g"
	elif f.cable == "sata":
		prof["need_sata"] = true
	prof = _progression_profile(prof)
	var built := _build_compatible_pc(prof)
	var parts: Array = built.parts
	_apply_fault_to_parts(parts, f)
	_maybe_add_cosmetic_dust(j, parts)
	j.case_id = built.case_id
	j.parts = parts
	j.pay = f.roll_labor()
	return j


## Yazılım / BIOS işi.
func _job_software(j: Dictionary, t) -> Dictionary:
	var f = DB.jobs.fault(t.fault)
	j.kind = t.job_kind
	j.broken = f.diag_code
	j.intro = _intro_of(t, f)
	j.goal = t.goal
	var prof := _progression_profile(t.profile.duplicate(true))
	var built := _build_compatible_pc(prof)
	var parts: Array = built.parts
	_apply_fault_to_parts(parts, f)
	_maybe_add_cosmetic_dust(j, parts)
	j.case_id = built.case_id
	j.parts = parts
	j.pay = f.roll_labor()
	return j


## Çoklu arıza işi (2+ bağımsız arıza bir arada).
func _job_multi(j: Dictionary, t) -> Dictionary:
	j.kind = t.job_kind
	j.goal = t.goal
	var faults_list: Array = []
	for fid in t.faults:
		var ff = DB.jobs.fault(str(fid))
		if ff != null:
			faults_list.append(ff)
	var prof: Dictionary = t.profile.duplicate(true)
	for f in faults_list:
		if f.part == "gpu" or f.kind == "vram_fault" or f.cable == "pcie_gpu":
			prof["need_gpu"] = true
			if f.cable == "pcie_gpu" and not prof.has("gpu_sku"):
				prof["gpu_sku"] = "gpu_mid_8g"
		if f.part == "hdd":
			prof["need_sata"] = true
			prof["sata_sku"] = "hdd_sata_1t"
		elif f.part == "ssd" or f.cable == "sata":
			prof["need_sata"] = true
	prof = _progression_profile(prof)
	var built := _build_compatible_pc(prof)
	var parts: Array = built.parts
	var part_pay := 0
	var labor_pay := 0
	var codes: Array[String] = []
	for f in faults_list:
		var app := _apply_fault_to_parts(parts, f)
		if app.need_pay and not str(app.sku).is_empty():
			part_pay += PM.price_sku(str(app.sku))
		labor_pay += f.roll_labor()
		codes.append(f.diag_code if f.part == "" else f.part)
	var lead_f = faults_list[0] if not faults_list.is_empty() else null
	j.broken = "+".join(codes)
	j.intro = _intro_of(t, lead_f)
	j.case_id = built.case_id
	j.parts = parts
	j.pay = part_pay + labor_pay + 60
	return j


## Gün ilerleyişine göre varsayılan PC kurulum profili:
## 1. gün başlangıç AM4/DDR4, 2. gün DDR4 (AM4/LGA1700), 3+ gün tüm 3 kasa ve 4 soket.
func _progression_profile(base: Dictionary = {}) -> Dictionary:
	var prof := base.duplicate(true)
	if Game.day <= 1:
		if not prof.has("case_id") and not prof.has("cases"):
			prof["case_id"] = "atx_mid"
		if not prof.has("socket"):
			prof["socket"] = "AM4"
		if not prof.has("cpu_sku"):
			prof["cpu_sku"] = "cpu_am4_6c"
		if not prof.has("ram_sku"):
			prof["ram_sku"] = "ram_ddr4_8g"
		if not prof.has("gpu_sku"):
			prof["gpu_sku"] = "gpu_entry_4g"
		if not prof.has("psu_sku"):
			prof["psu_sku"] = "psu_550w"
		if not prof.has("need_gpu"):
			prof["need_gpu"] = true
		if not prof.has("need_sata"):
			prof["need_sata"] = true
	elif Game.day == 2:
		if not prof.has("ram_type"):
			prof["ram_type"] = "DDR4"
		if not prof.has("cases") and not prof.has("case_id"):
			prof["cases"] = ["atx_mid", "matx_mini"]
	return prof


## Yüzde yüz uyumlu, gerçekçi PC kurulumu üretir: {"case_id": String, "parts": Array[Dictionary]}.
## Tüm 3 kasa form faktörü (atx_mid, matx_mini, itx_compact) ve 4 CPU soketi (AM4, AM5, LGA1700, LGA1851) desteklenir.
func _build_compatible_pc(profile: Dictionary = {}) -> Dictionary:
	var all_cases: Array = profile.get("cases", ["atx_mid", "matx_mini", "itx_compact"])
	if profile.has("case_id"):
		all_cases = [str(profile.case_id)]
	var all_mobos: Array = DB.parts.by_category("mobo")
	var valid_pairs := []
	for cid in all_cases:
		var cdef := DB.parts.case_def(str(cid))
		if cdef.is_empty():
			continue
		var ffs: Array = cdef.get("form_factors", [])
		for m in all_mobos:
			if not ffs.has(str(m.compat.get("form_factor", ""))):
				continue
			if profile.has("socket") and str(m.compat.get("socket", "")) != str(profile.socket):
				continue
			if profile.has("ram_type") and str(m.compat.get("ram_type", "")) != str(profile.ram_type):
				continue
			if profile.has("mobo_sku") and m.id != str(profile.mobo_sku):
				continue
			valid_pairs.append([str(cid), cdef, m])
	if valid_pairs.is_empty():
		return _starter_pc_fallback()
	var pick: Array = valid_pairs.pick_random()
	var case_id: String = pick[0]
	var cdef: Dictionary = pick[1]
	var mobo: PartDef = pick[2]
	var sock := str(mobo.compat.get("socket", "AM4"))
	var ram_type := str(mobo.compat.get("ram_type", "DDR4"))

	# CPU: anakart soketine uyumlu
	var cpus := DB.parts.by_category("cpu").filter(func(c):
		if str(c.compat.get("socket", "")) != sock:
			return false
		if profile.has("cpu_sku") and c.id != str(profile.cpu_sku):
			return false
		if profile.has("igpu") and bool(c.specs.get("igpu", false)) != bool(profile.igpu):
			return false
		return true)
	if cpus.is_empty():
		return _starter_pc_fallback()
	var cpu: PartDef = cpus.pick_random()

	# Soğutucu: soket + kasa yükseklik/radyatör sınırına uyumlu
	var max_h := int(cdef.get("max_cooler_mm", 165))
	var max_rad := int(cdef.get("max_rad_mm", 240))
	var coolers := DB.parts.by_category("cooler").filter(func(cl):
		var socks: Array = cl.compat.get("sockets", [])
		if not socks.is_empty() and not socks.has(sock):
			return false
		if int(cl.specs.get("height_mm", 0)) > max_h:
			return false
		var rad := int(cl.specs.get("radiator_mm", 0))
		if rad > 0 and rad > max_rad:
			return false
		if profile.has("cooler_sku") and cl.id != str(profile.cooler_sku):
			return false
		return true)
	if coolers.is_empty():
		coolers = [DB.parts.get_def("cooler_stock")]
	var cooler: PartDef = coolers.pick_random()

	# RAM: anakart DDR nesli ve yuva sayısına uyumlu
	var max_ram_gb := int(profile.get("max_ram_gb", 0))
	var rams := DB.parts.by_category("ram").filter(func(r):
		if str(r.compat.get("ram_type", "")) != ram_type:
			return false
		if profile.has("ram_sku") and r.id != str(profile.ram_sku):
			return false
		if max_ram_gb > 0 and int(r.specs.get("gb", 8)) > max_ram_gb:
			return false
		return true)
	if rams.is_empty():
		return _starter_pc_fallback()
	var ram: PartDef = rams.pick_random()
	var max_slots := int(mobo.compat.get("ram_slots", 2))
	var ram_count := int(profile.get("ram_count", -1))
	if ram_count < 1:
		ram_count = 2 if (max_slots >= 2 and randf() < float(profile.get("ram2_chance", 0.5))) else 1
	ram_count = clampi(ram_count, 1, max_slots)

	# GPU: kasa uzunluğuna uyumlu (iGPU'lu işlemcide opsiyonel)
	var has_igpu := bool(cpu.specs.get("igpu", false))
	var need_gpu := bool(profile.get("need_gpu", false)) or not has_igpu
	var gpu: PartDef = null
	if need_gpu or randf() < 0.75:
		var max_gpu := int(cdef.get("max_gpu_mm", 330))
		var max_gpu_tier := int(profile.get("max_gpu_tier", 99))
		var gpus := DB.parts.by_category("gpu").filter(func(g):
			if int(g.specs.get("length_mm", 0)) > max_gpu:
				return false
			if g.tier > max_gpu_tier:
				return false
			if profile.has("gpu_sku") and g.id != str(profile.gpu_sku):
				return false
			return true)
		if not gpus.is_empty():
			gpu = gpus.pick_random()
	if gpu == null and not has_igpu:
		return _starter_pc_fallback()

	# Depolama: SATA SSD/HDD ve/veya M.2 NVMe
	var storage_entries := []
	var need_sata := bool(profile.get("need_sata", false))
	var use_nvme := not need_sata and int(mobo.compat.get("m2_slots", 0)) > 0 and randf() < 0.5
	if use_nvme:
		var nvmes := DB.parts.by_category("nvme")
		if not nvmes.is_empty():
			storage_entries.append(["m2", nvmes.pick_random()])
	if storage_entries.is_empty() or (not need_sata and randf() < 0.25):
		var sata_sku := str(profile.get("sata_sku", ""))
		var sata_def: PartDef = DB.parts.get_def(sata_sku) if not sata_sku.is_empty() else null
		if sata_def == null:
			var satas := DB.parts.by_category("ssd") + DB.parts.by_category("hdd")
			sata_def = satas.pick_random() if not satas.is_empty() else DB.parts.get_def("ssd_sata_512")
		storage_entries.append(["ssd", sata_def])

	# Kasa fanları + CMOS
	var fan_slots := int(cdef.get("fan_slots", 1))
	var fans := DB.parts.by_category("fan")
	var fan_def: PartDef = fans.pick_random() if not fans.is_empty() else DB.parts.get_def("fan_120_std")
	var fan_count := 2 if (fan_slots >= 2 and randf() < 0.6) else 1

	# Parça listesini (PSU hariç) oluşturup gereken watt + konnektörü hesapla
	var parts := [
		_part_entry("mobo", mobo.id),
		_part_entry("cpu", cpu.id),
		_part_entry("cooler", cooler.id),
		_part_entry("cmos", "cmos_cr2032"),
	]
	for i in ram_count:
		parts.append(_part_entry("ram%d" % (i + 1), ram.id))
	if gpu != null:
		parts.append(_part_entry("gpu", gpu.id))
	for se in storage_entries:
		parts.append(_part_entry(str(se[0]), se[1].id))
	for fi in fan_count:
		parts.append(_part_entry("fan%d" % (fi + 1), fan_def.id))

	var hyp := _case_state_from_parts(case_id, parts)
	var watts := Compatibility.calc_watts(hyp)
	var min_w := maxi(int(watts.recommended), int(profile.get("min_psu_watts", 0)))
	var psus := DB.parts.by_category("psu").filter(func(ps):
		if gpu != null and not Compatibility.check_psu_connectors(ps, gpu).ok:
			return false
		if int(ps.compat.get("watts", 0)) < min_w:
			return false
		if profile.has("psu_sku") and ps.id != str(profile.psu_sku):
			return false
		return true)
	if psus.is_empty():
		psus = DB.parts.by_category("psu").filter(func(ps):
			return (gpu == null or Compatibility.check_psu_connectors(ps, gpu).ok) and int(ps.compat.get("watts", 0)) >= int(watts.draw))
	if psus.is_empty():
		return _starter_pc_fallback()
	psus.sort_custom(func(a, b): return a.price < b.price)
	var psu: PartDef = psus[randi() % mini(2, psus.size())]
	parts.append(_part_entry("psu", psu.id))

	# Son doğrulama: tüm kurallardan geçmezse güvenli başlangıç kurulumuna düş
	var final_state := _case_state_from_parts(case_id, parts)
	if not Compatibility.check_system(final_state).ok:
		return _starter_pc_fallback()
	return {"case_id": case_id, "parts": parts}


static func _part_entry(slot: String, sku_id: String, broken := false, paste_ok := true, cheap := false, health := 100) -> Dictionary:
	return {"slot": slot, "sku": sku_id, "broken": broken, "paste_ok": paste_ok, "cheap": cheap, "health": health}


static func _case_state_from_parts(case_id: String, parts: Array) -> Dictionary:
	var cdef := DB.parts.case_def(case_id)
	var st := {
		"case_id": case_id,
		"case_def": cdef,
		"mobo": null,
		"cpu": null,
		"cooler": null,
		"rams": [],
		"gpu": null,
		"psu": null,
		"storage": [],
		"fans": [],
		"cmos": null,
		"slots_occupied": {},
	}
	for p in parts:
		if not (p is Dictionary):
			continue
		var sn := str(p.get("slot", ""))
		if sn == "dust" or sn.is_empty():
			continue
		var d: PartDef = DB.parts.get_def(str(p.get("sku", "")))
		if d == null:
			continue
		st.slots_occupied[sn] = d
		match d.category:
			"mobo": st.mobo = d
			"cpu": st.cpu = d
			"cooler": st.cooler = d
			"ram": st.rams.append(d)
			"gpu": st.gpu = d
			"psu": st.psu = d
			"ssd", "hdd", "nvme": st.storage.append(d)
			"fan": st.fans.append(d)
			"cmos": st.cmos = d
	return st


static func _starter_pc_fallback() -> Dictionary:
	return {
		"case_id": "atx_mid",
		"parts": [
			_part_entry("mobo", "mobo_am4_matx"),
			_part_entry("cpu", "cpu_am4_6c"),
			_part_entry("cooler", "cooler_stock"),
			_part_entry("ram1", "ram_ddr4_8g"),
			_part_entry("gpu", "gpu_entry_4g"),
			_part_entry("ssd", "ssd_sata_512"),
			_part_entry("psu", "psu_550w"),
			_part_entry("fan1", "fan_120_std"),
			_part_entry("cmos", "cmos_cr2032"),
		],
	}


func _with_broken(base: Array, broken: String) -> Array:
	var out := []
	for b in base:
		out.append([b[0], b[1], b[2], b[1] == broken])
	return out
