extends Node
## Personel yöneticisi: işe alınan çalışanları dükkâna yerleştirir ve işlerini yürütür.
## Tezgahtar: bekleyen müşteriyi karşılar (işi kabul eder), satış müşterisine raftan parça getirip satar,
## boşta kalınca kapıdaki kargo kolilerini açar. Teknisyen: masadaki işi stoktaki parçalarla
## kendisi tamir eder (süre ve doğruluk beceriye bağlı), bitince müşteriye teslim eder.

const EMP := preload("res://scripts/employee.gd")
const PART := preload("res://scripts/part.gd")
const PM := preload("res://scripts/part_models.gd")
const SD := preload("res://scripts/staff_data.gd")

# dükkân içi noktalar
const SPAWN := Vector3(0.4, 0, 9.0)
const DOOR := Vector3(0.25, 0, 3.6)
const SIDE_FRONT := Vector3(1.05, 0, 1.6)     # tezgahın sağ ucunun önü (müşteri tarafı)
const SIDE_BACK := Vector3(1.05, 0, 0.6)      # tezgahın sağ ucunun arkası (dükkân tarafı)
const HUB := Vector3(-0.6, 0, -1.2)           # dükkânın ortası: masa/raf yollarının kavşağı
const DESK_SPOT := Vector3(-0.2, 0, -1.95)    # tamir masasının önü
const SERVE_CLERK := Vector3(-0.9, 0, 0.72)   # tezgah arkası, müşterinin karşısı
const SERVE_TECH := Vector3(-0.3, 0, 0.72)
const CLERK_HOMES := [Vector3(-1.65, 0, 0.72), Vector3(-2.4, 0, 0.72)]
const TECH_HOMES := [Vector3(-2.4, 0, -2.35), Vector3(2.4, 0, -0.9)]
const SHELF_X := -3.1
# tamir süresi (oyun saati, beceri çarpanından önce)
const BASE_HOURS := 0.35
const PART_HOURS := 0.4
const DUST_HOURS := 0.35
const PASTE_HOURS := 0.45

var world: Node3D
var jobs
var delivery
var npcs := {}                # çalışan id -> employee düğümü
var force_run := false        # test: HUD olmadan da zaman aksın
var _bubble_t := 0.0


func setup(w: Node3D, j, d) -> Node:
	world = w
	jobs = j
	delivery = d
	return self


func _ready() -> void:
	Game.staff_mgr = self
	Game.day_started.connect(_on_day_started)
	Game.day_ended.connect(func(_s): _clear_all())
	Game.staff_changed.connect(_sync)


func _running() -> bool:
	return Game.phase == "day" and (Game.running or force_run)


# ---------------------------------------------------------------- yerleşim
## Yeni gün: çalışanlar yerlerinde hazır bekler, iş ilanına yeni adaylar gelir.
func _on_day_started() -> void:
	_clear_all()
	for d in Game.staff:
		_spawn(d, false)
	if Game.day > 1 or Game.staff_candidates.is_empty():
		Game.roll_staff_candidates()


func _clear_all() -> void:
	for id in npcs:
		var e = npcs[id]
		if is_instance_valid(e):
			_release(e)
			e.queue_free()
	npcs.clear()


## Game.staff değişti: yeni gelen kapıdan girer, kovulan çıkıp gider.
func _sync() -> void:
	if Game.phase != "day":
		return
	var ids := {}
	for d in Game.staff:
		ids[int(d.id)] = true
		if not npcs.has(int(d.id)):
			_spawn(d, true)
		else:
			npcs[int(d.id)].info = d
	for id in npcs.keys():
		if not ids.has(id):
			var e = npcs[id]
			npcs.erase(id)
			_release(e)
			e.task = "leave"
			e.say_for(["Hakkını helal et usta.", "Peki usta, kolay gelsin..."].pick_random(), 3.0)
			e.walk(_path_out(e), func(): e.queue_free())


func _spawn(d: Dictionary, walk_in: bool) -> void:
	var e = EMP.new()
	var idx := 0
	for o in Game.staff:
		if o.role == d.role and int(o.id) < int(d.id):
			idx += 1
	var clerk: bool = d.role == "tezgahtar"
	e.home = (CLERK_HOMES if clerk else TECH_HOMES)[mini(idx, 1)]
	e.home_face = 0.0 if clerk else PI * 0.5 * (1.0 if idx == 0 else -1.0)
	e.position = SPAWN if walk_in else e.home
	world.add_child(e)
	var id := int(d.id)
	e.setup_staff(d, func(_p): return _hint(id), func(_p): _talk(id))
	e.face_angle = e.home_face
	e.rotation.y = e.home_face
	npcs[id] = e
	if walk_in:
		e.task = "walk"
		e.walk([DOOR, SIDE_FRONT, SIDE_BACK] + _route(e, SIDE_BACK, e.home), func(): _go_idle(e))
		e.say_for("Merhaba usta! Bugün başlıyorum.", 3.0)


func _path_out(e) -> Array:
	return _route(e, e.position, SIDE_BACK) + [SIDE_BACK, SIDE_FRONT, DOOR, SPAWN]


## Teknisyen tarafındaki noktalara (masa, köşe) dükkân ortasından gidilir; tezgah arkası doğrudan.
func _route(_e, from: Vector3, to: Vector3) -> Array:
	var back_zone := func(p: Vector3) -> bool: return p.z < -0.3
	if back_zone.call(from) or back_zone.call(to):
		return [HUB, to]
	return [to]


func _go_idle(e) -> void:
	e.task = "idle"
	e.react_t = 0.0
	e.at_desk = false
	e.face_angle = e.home_face


func _go_home(e) -> void:
	e.task = "walk"
	e.walk(_route(e, e.position, e.home), func(): _go_idle(e))


## Ayrılmış stok ve eldeki parça geri rafa.
func _release(e) -> void:
	for r in e.reserved:
		Game.add_stock(r[0], int(r[1]), 1)
	e.reserved = []
	if e.held:
		var h = e.release_held()
		if is_instance_valid(h):
			Game.add_stock(h.part_type, h.tier, 1)
			h.queue_free()
	e.pc = null


# ---------------------------------------------------------------- etkileşim
func _hint(id: int) -> String:
	var e = npcs.get(id)
	if e == null:
		return ""
	var d: Dictionary = e.info
	var who := "%s %s" % [SD.role_name(d.role), d.name]
	if d.role == "teknisyen":
		if e.task == "repair":
			return "%s — tamir ediyor (%%%d)" % [who, int(100.0 * e.work / maxf(e.need, 0.01))]
		if e.task == "idle" and jobs.state == "working" and not _pc_taken(jobs.pc):
			return "%s: masadaki işi ver  [E]" % who
	return "%s  (%s)" % [who, _task_text(e)]


func _task_text(e) -> String:
	return {"idle": "boşta", "walk": "yolda", "serve": "müşteriyle", "sell": "parça getiriyor",
		"cargo": "koli açıyor", "repair": "tamirde", "leave": "gidiyor"}.get(e.task, "")


func _talk(id: int) -> void:
	var e = npcs.get(id)
	if e == null:
		return
	if e.info.role == "teknisyen" and e.task == "idle":
		var err := assign(id)
		if err == "":
			return
		if err == "iş yok":
			e.say_for(["Masada iş yok usta, çay koyayım mı?", "Müşteri gelince işi bana ver usta."].pick_random(), 3.0)
		return
	e.say_for(["Buyur usta?", "Hallediyorum usta!", "Merak etme, gözüm müşteride."].pick_random(), 2.5)


func _pc_taken(p) -> bool:
	for id in npcs:
		if npcs[id].task == "repair" and npcs[id].pc == p:
			return true
	return false


func technicians() -> Array:
	return npcs.values().filter(func(e): return e.info.role == "teknisyen" and e.task != "leave")


# ---------------------------------------------------------------- her kare
func _process(delta: float) -> void:
	if not _running():
		return
	_bubble_t += delta
	var tick_bubble := _bubble_t >= 0.5
	if tick_bubble:
		_bubble_t = 0.0
	var has_clerk := false
	for id in npcs:
		if npcs[id].info.role == "tezgahtar" and npcs[id].task != "leave":
			has_clerk = true
	for id in npcs.keys():
		var e = npcs[id]
		if not is_instance_valid(e):
			continue
		if e.info.role == "tezgahtar":
			_tick_clerk(e, delta)
		else:
			_tick_tech(e, delta, tick_bubble, has_clerk)


# ---------------------------------------------------------------- tezgahtar
func _react_delay(e) -> float:
	return (5.0 - 0.7 * int(e.info.skill)) / float(SD.trait_info(e.info.trait).speed)


func _customer_claimed(c) -> bool:
	for id in npcs:
		var o = npcs[id]
		if (o.task == "serve" or o.task == "sell") and o.noted == c:
			return true
	return false


func _tick_clerk(e, delta: float) -> void:
	if e.task != "idle":
		return
	var c = jobs.customer
	if jobs.state == "waiting" and is_instance_valid(c) and not _customer_claimed(c):
		e.react_t += delta
		if e.react_t < _react_delay(e):
			return
		if jobs.job.get("kind", "") != "sale":
			_clerk_accept(e, c)
		elif not _clerk_sale(e, c) and not delivery.boxes.is_empty():
			_open_cargo(e)  # parça stokta yok: belki kapıdaki kolidedir
		return
	e.react_t = 0.0
	if not delivery.boxes.is_empty():
		_open_cargo(e)


## Tamir/yükseltme müşterisi: tezgaha geçip işi kabul eder, bilgisayar masaya konur.
func _clerk_accept(e, c) -> void:
	e.task = "serve"
	e.noted = c
	e.walk([SERVE_CLERK], func():
		e.face_angle = 0.0
		if jobs.state == "waiting" and jobs.customer == c:
			jobs._accept()
			Game.change_rep(float(SD.trait_info(e.info.trait).rep))
			e.say_for(["Hoş geldiniz! Bilgisayarı hemen ustamın masasına alıyorum.", "Buyrun abi, bırakın biz bakarız."].pick_random(), 3.0)
			Game.msg("%s müşteriyi karşıladı, bilgisayar masada." % e.info.name, Color(0.6, 0.9, 1.0))
		e.noted = null
		_go_home(e))


## Parça müşterisi: stokta varsa raftan alıp getirir ve satar; yoksa bir kez haber verir.
func _clerk_sale(e, c) -> bool:
	var w: Array = jobs.job.want
	var dname := PM.display_name(w[0], w[1])
	if not Game.take_stock(w[0], w[1]):
		if e.noted != c:
			e.noted = c
			e.say_for("Usta stokta %s kalmamış! ParçaNet'ten ekspres sipariş versen?" % dname, 4.0, true)
			Game.msg("%s: stokta %s yok." % [e.info.name, dname], Color(1, 0.7, 0.4))
		return false
	e.task = "sell"
	e.noted = c
	e.reserved = [[w[0], w[1]]]
	var sp: Vector3 = Game.shelf_pos.get(Game.sku(w[0], w[1]), Vector3(SHELF_X, 0, -1.2))  # raf kurulurken main.gd yazar
	var shelf := Vector3(SHELF_X, 0, sp.z)
	e.say_for("Hemen getiriyorum, bir saniye.", 2.0)
	e.walk([shelf], func():
		e.face_angle = -PI * 0.5
		e.reserved = []
		var part = PART.new().setup(w[0], w[1], false)
		e.carry(part)
		Game.sfx.click()
		e.walk([SERVE_CLERK], func():
			e.face_angle = 0.0
			if jobs.state == "waiting" and jobs.customer == c and jobs.job.get("kind", "") == "sale":
				jobs._try_sell(e)
				Game.change_rep(float(SD.trait_info(e.info.trait).rep))
			_release(e)  # satış olmadıysa parça rafa döner
			e.noted = null
			_go_home(e)))
	return true


## Kapıdaki ParçaNet kolisini açar, parçalar stoğa girer.
func _open_cargo(e) -> void:
	var id: int = delivery.boxes.keys()[0]
	var box: Node3D = delivery.boxes[id]
	if not is_instance_valid(box):
		return
	e.task = "cargo"
	var spot := Vector3(box.position.x, 0, box.position.z - 0.45)
	var back := _route(e, e.position, SIDE_BACK)
	e.walk(back + [SIDE_BACK, SIDE_FRONT, spot], func():
		e.face_angle = 0.0
		if delivery.boxes.has(id):
			delivery.open_box(id)
			e.say_for("Koli açıldı, parçaları rafa dizdim usta.", 3.0)
		e.task = "walk"
		e.walk([SIDE_FRONT, SIDE_BACK] + _route(e, SIDE_BACK, e.home), func(): _go_idle(e)))


# ---------------------------------------------------------------- teknisyen
func _tick_tech(e, delta: float, tick_bubble: bool, has_clerk: bool) -> void:
	match e.task:
		"idle":
			if e.info.get("auto", true) and jobs.state == "working" and not _pc_taken(jobs.pc):
				e.react_t += delta
				if e.react_t >= 2.0:  # bilgisayar masaya konduktan biraz sonra işe koyulur
					e.react_t = 0.0
					assign(int(e.info.id), true)
				return
			e.react_t = 0.0
			if not has_clerk and jobs.state != "waiting" and not delivery.boxes.is_empty():
				_open_cargo(e)
		"repair":
			if not is_instance_valid(e.pc) or jobs.pc != e.pc or jobs.state != "working":
				_abort(e, "")
				return
			if not e.at_desk:
				return
			e.work += delta * Game.HOURS_PER_SEC
			if tick_bubble:
				e.say("Tamir ediliyor... %%%d" % int(100.0 * minf(e.work / e.need, 1.0)))
			if e.work >= e.need:
				_finish(e)


## Masadaki işi teknisyene ver. Hata metni döner ("" = başladı).
func assign(id: int, quiet := false) -> String:
	var e = npcs.get(id)
	if e == null or e.info.role != "teknisyen":
		return "teknisyen yok"
	if e.task != "idle":
		return "meşgul"
	if jobs.state != "working" or not is_instance_valid(jobs.pc):
		return "iş yok"
	if _pc_taken(jobs.pc):
		return "başkası yapıyor"
	var p = jobs.pc
	# teknisyen sadece masaüstü kasalarla çalışır; laptop/telefon ustaya kalır
	if str(jobs.job.get("device", "")) != "":
		if e.noted != p:
			e.noted = p
			if not quiet:
				e.say_for("Laptop/telefon benim işim değil usta, sen bakarsın.", 3.0)
		return "masaüstü değil"
	var pl := make_plan(p, jobs.job)
	# gereken parçaları stoktan ayır
	var res := []
	for it in pl.parts:
		if not Game.take_stock(it[1], int(it[2])):
			for r in res:
				Game.add_stock(r[0], int(r[1]), 1)
			var dname := PM.display_name(it[1], int(it[2]))
			if e.noted != p:
				e.noted = p
				e.say_for("Usta stokta %s yok! ParçaNet'ten getirtmek lazım." % dname, 4.0, true)
				Game.msg("%s: stok yok (%s)." % [e.info.name, dname], Color(1, 0.7, 0.4))
			elif not quiet:
				e.say_for("Hâlâ %s yok usta, stok gelmeden yapamam." % dname, 3.0, true)
			return "stok yok"
		res.append([it[1], int(it[2])])
	e.reserved = res
	e.plan = pl
	e.pc = p
	e.noted = null
	e.work = 0.0
	var h: float = BASE_HOURS + PART_HOURS * pl.parts.size() + (DUST_HOURS if pl.dust else 0.0) + (PASTE_HOURS if pl.paste else 0.0)
	e.need = h * SD.time_mult(e.info)
	e.task = "repair"
	e.at_desk = false
	e.say_for("Tamamdır usta, ben hallederim.", 2.5)
	Game.msg("%s işi aldı (~%.1f saat)." % [e.info.name, e.need], Color(0.6, 0.9, 1.0))
	e.walk(_route(e, e.position, DESK_SPOT), func():
		if e.task != "repair":
			return
		var tp: Vector3 = e.pc.global_position if is_instance_valid(e.pc) else DESK_SPOT + Vector3(0.6, 0, -0.6)
		e.face_angle = atan2(tp.x - e.position.x, tp.z - e.position.z)
		e.at_desk = true
		if is_instance_valid(e.pc) and not e.pc.panel_open:
			e.pc.toggle_panel())
	return ""


## Bilgisayarın şu anki hâline ve işe göre yapılacaklar: değişecek parçalar, toz, macun.
static func make_plan(p, job: Dictionary) -> Dictionary:
	var parts := []
	var need := {"psu": ["psu", 1], "cpu": ["cpu", 1], "ram1": ["ram", 1], "gpu": ["gpu", 1], "ssd": ["ssd", 1]}
	for s in ["psu", "cpu", "ram1", "ram2", "gpu", "ssd"]:
		var part = p.part_in(s)
		if part and part.broken:
			parts.append([s, part.part_type, part.tier])
		elif part == null and need.has(s):
			parts.append([s, need[s][0], need[s][1]])
	match job.get("kind", ""):
		"upgrade_gpu":
			var g = p.part_in("gpu")
			if g == null or g.tier < 2:
				parts = parts.filter(func(it): return it[0] != "gpu")
				parts.append(["gpu", "gpu", 2])
		"upgrade_ram":
			if p.total_ram() < 32:
				parts = parts.filter(func(it): return it[0] != "ram1" and it[0] != "ram2")
				parts.append(["ram1", "ram", 2])
				parts.append(["ram2", "ram", 2])
	var cpu = p.part_in("cpu")
	var cpu_new := parts.any(func(it): return it[0] == "cpu")
	return {"parts": parts, "dust": p.dust > 0.02, "paste": cpu != null and not cpu_new and not cpu.paste_ok}


func _finish(e) -> void:
	var p = e.pc
	var pl: Dictionary = e.plan
	var d: Dictionary = e.info
	# beceriye bağlı hata: parça yanar (stoktan bir tane daha gider) ya da iş uzar
	if randf() > SD.accuracy(d):
		Game.change_rep(-0.1)
		Game.sfx.error()
		if pl.parts.is_empty():
			e.say_for("Eyvah, macunu taşırdım! Silip yeniden yapıyorum.", 3.5, true)
			Game.msg("%s hata yaptı, iş uzadı (itibar düştü)." % d.name, Color(1, 0.6, 0.4))
			e.need += e.need * 0.4
			return
		var lost: Array = pl.parts[0]
		var dname := PM.display_name(lost[1], int(lost[2]))
		if Game.take_stock(lost[1], int(lost[2])):
			e.say_for("Eyvah, %s ters taktım, yandı! Yenisini takıyorum." % dname, 3.5, true)
			Game.msg("%s hata yaptı: 1 %s yandı (itibar düştü)." % [d.name, dname], Color(1, 0.6, 0.4))
			e.need += e.need * 0.4
			return
		# yanan parçanın yenisi stokta yok: ayrılanın biri gitti, kalanı rafa döner
		for i in e.reserved.size():
			if e.reserved[i][0] == lost[1] and int(e.reserved[i][1]) == int(lost[2]):
				e.reserved.remove_at(i)
				break
		_abort(e, "%s yaktım usta, stokta yenisi yok! Gerisi sende." % dname)
		Game.msg("%s hata yaptı: %s yandı, stokta yenisi yok." % [d.name, dname], Color(1, 0.5, 0.4))
		return
	if p.powered:
		p.power_off()
	for it in pl.parts:
		var slot = p.slots[it[0]]
		var old = slot.part
		if old:
			slot.detach()
			if not old.broken:
				Game.add_stock(old.part_type, old.tier, 1)  # sağlam eski parça rafa
			old.queue_free()
		slot.install(PART.new().setup(it[1], int(it[2]), false))
	e.reserved = []
	if pl.dust:
		p.clean_dust()
	if pl.paste and p.part_in("cpu"):
		p.part_in("cpu").paste_ok = true
	Game.sfx.click()
	if p.panel_open:
		p.toggle_panel()
	Game.change_rep(float(SD.trait_info(d.trait).rep))
	var problem: String = jobs._problem()
	if problem != "":
		_abort(e, "Usta bir şey eksik kaldı, sen bir bakar mısın?")
		return
	e.say_for("Tamamdır, tıkır tıkır çalışıyor! Teslim ediyorum.", 3.0)
	e.task = "serve"
	e.at_desk = false
	e.walk(_route(e, e.position, SERVE_TECH), func():
		e.face_angle = 0.0
		if jobs.state == "working" and jobs.pc == p:
			jobs._try_deliver()
		e.pc = null
		_go_home(e))


func _abort(e, line: String) -> void:
	_release(e)
	e.at_desk = false
	if line != "":
		e.say_for(line, 4.0, true)
	else:
		e.say("")
	_go_home(e)
