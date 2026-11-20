extends Node
## Personel yöneticisi: işe alınan çalışanları dükkâna yerleştirir ve işlerini yürütür.
## Tezgahtar: tezgâhtaki müşteriyi karşılar (bırakılan işi kabul eder, fiş keser), satış müşterisine raftan parça
## getirip satar, işi hazır olan teslim müşterisine rafın hazır cihazını getirip verir, boşta kalınca kapıdaki
## kargo kolilerini açar. Teknisyen: Bekleyen İşler rafında duran masaüstü işlerini yerinde, stoktaki parçalarla
## kendisi tamir eder (süre ve doğruluk beceriye bağlı) ve "hazır" yapar; laptop/telefon ve tezgâhtaki işe karışmaz.

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
const RACK_WAY := Vector3(3.0, 0, 0.5)         # Bekleyen İşler rafına giden yolun ara noktası
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
		var rsku: String = Game.sku(str(r[0]), int(r[1])) if r is Array else str(r)
		Game.add_stock_sku(rsku, 1)
	e.reserved = []
	if e.held:
		var h = e.release_held()
		if is_instance_valid(h):
			var hsku: String = h.sku if not h.sku.is_empty() else Game.sku(h.part_type, h.tier)
			Game.add_stock_sku(hsku, 1)
			h.queue_free()
	if not e.rec.is_empty():
		jobs.busy.erase(int(e.rec.ticket))
	e.rec = {}
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
		if e.task == "idle" and not jobs.tech_candidates().is_empty():
			return "%s: raftaki işi ver  [E]" % who
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
			e.say_for(["Rafta iş yok usta, çay koyayım mı?", "Müşteri iş bırakınca ben bakarım usta."].pick_random(), 3.0)
		return
	e.say_for(["Buyur usta?", "Hallediyorum usta!", "Merak etme, gözüm müşteride."].pick_random(), 2.5)


## Rafın o işe ait gözünün önündeki duruş noktası (rafa dönük).
func _rack_front(rec: Dictionary) -> Vector3:
	var i := int(str(rec.location).substr(5))
	var jr = jobs.rack
	var g: Vector3 = jr.to_global(Vector3(jr.slot_xz(i).x, 0.0, jr.DEPTH + 0.55))
	return Vector3(g.x, 0.0, g.z)


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
		match jobs.mode:
			"dropoff":
				_clerk_accept(e, c)
			"pickup":
				if not _clerk_pickup(e, c) and not delivery.boxes.is_empty():
					_open_cargo(e)
			_:
				if not _clerk_sale(e, c) and not delivery.boxes.is_empty():
					_open_cargo(e)  # parça stokta yok: belki kapıdaki kolidedir
		return
	e.react_t = 0.0
	if not delivery.boxes.is_empty():
		_open_cargo(e)


## Tamir/yükseltme müşterisi: tezgaha geçip işi kabul eder, fiş keser, cihaz Bekleyen İşler rafına konur.
## Raf doluysa müşteriyi kibarca geri çevirir (itibar kaybı yok).
func _clerk_accept(e, c) -> void:
	e.task = "serve"
	e.noted = c
	e.walk([SERVE_CLERK], func():
		e.face_angle = 0.0
		if jobs.state == "waiting" and jobs.customer == c and jobs.mode == "dropoff":
			if Game.jobs_active.size() >= Game.max_active_jobs():
				jobs.decline_head()
				e.say_for("Rafımız dolu, yarın gelin lütfen.", 3.0)
			elif jobs._accept():
				Game.change_rep(float(SD.trait_info(e.info.trait).rep))
				e.say_for(["Hoş geldiniz! Fişinizi kestim, cihazı rafa alıyorum.", "Buyrun abi, bırakın biz bakarız."].pick_random(), 3.0)
				Game.msg("%s müşteriyi karşıladı, cihaz Bekleyen İşler rafında." % e.info.name, Color(0.6, 0.9, 1.0))
		e.noted = null
		_go_home(e))


## Teslim müşterisi: işi hazırsa rafa gidip cihazı getirir ve verir. Hazır değilse bir kez haber verir (false).
func _clerk_pickup(e, c) -> bool:
	var q: Array = jobs.queue
	if q.is_empty() or q[0].customer != c:
		return false
	var rec: Dictionary = q[0].rec
	if str(rec.status) != "ready" or not str(rec.location).begins_with("rack:") or jobs.busy.has(int(rec.ticket)):
		if e.noted != c:
			e.noted = c
			e.say_for("Usta #%d numaralı iş henüz hazır değil." % int(rec.ticket), 3.5, true)
		return false
	e.task = "serve"
	e.noted = c
	jobs.busy[int(rec.ticket)] = true
	e.rec = rec
	var front := _rack_front(rec)
	e.walk([SIDE_BACK, RACK_WAY, front], func():
		e.face_angle = atan2(jobs.rack.global_position.x - front.x, 0.0)
		Game.sfx.click()
		e.walk([RACK_WAY, SIDE_BACK, SERVE_CLERK], func():
			e.face_angle = 0.0
			jobs.busy.erase(int(rec.ticket))
			e.rec = {}
			if jobs.state == "waiting" and jobs.customer == c and jobs.mode == "pickup" and jobs.staff_handover():
				Game.change_rep(float(SD.trait_info(e.info.trait).rep))
				e.say_for("Buyrun, fiş #%d hazırdı. İyi günler!" % int(rec.ticket), 3.0)
			e.noted = null
			_go_home(e)))
	return true


## Parça müşterisi: stokta varsa raftan alıp getirir ve satar; yoksa bir kez haber verir.
func _clerk_sale(e, c) -> bool:
	var w = jobs.job.want
	var sku_id: String = DB.parts.resolve_id(str(w)) if w is String else (Game.sku(str(w[0]), int(w[1])) if w is Array and w.size() >= 2 else DB.parts.resolve_id(str(w[0])))
	var dname := PM.display_name_sku(sku_id)
	if not Game.take_stock_sku(sku_id):
		if e.noted != c:
			e.noted = c
			e.say_for("Usta stokta %s kalmamış! ParçaNet'ten ekspres sipariş versen?" % dname, 4.0, true)
			Game.msg("%s: stokta %s yok." % [e.info.name, dname], Color(1, 0.7, 0.4))
		return false
	e.task = "sell"
	e.noted = c
	e.reserved = [sku_id]
	var sp: Vector3 = Game.shelf_pos.get(sku_id, Vector3(SHELF_X, 0, -1.2))  # raf kurulurken main.gd yazar
	var shelf := Vector3(SHELF_X, 0, sp.z)
	e.say_for("Hemen getiriyorum, bir saniye.", 2.0)
	e.walk([shelf], func():
		e.face_angle = -PI * 0.5
		e.reserved = []
		var part = PART.new().setup_sku(sku_id, false)
		e.carry(part)
		Game.sfx.click()
		e.walk([SERVE_CLERK], func():
			e.face_angle = 0.0
			if jobs.state == "waiting" and jobs.customer == c and jobs.mode == "sale":
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
			if e.info.get("auto", true) and not jobs.tech_candidates().is_empty():
				e.react_t += delta
				if e.react_t >= 2.0:  # iş rafa konduktan biraz sonra işe koyulur
					e.react_t = 0.0
					assign(int(e.info.id), true)
				return
			e.react_t = 0.0
			if not has_clerk and jobs.state != "waiting" and not delivery.boxes.is_empty():
				_open_cargo(e)
		"repair":
			if not is_instance_valid(e.pc) or e.rec.is_empty() or jobs.devices.get(int(e.rec.ticket)) != e.pc \
					or Game.job_by_ticket(int(e.rec.ticket)).is_empty() or not str(e.rec.location).begins_with("rack:"):
				_abort(e, "")
				return
			if not e.at_desk:
				return
			e.work += delta * Game.HOURS_PER_SEC
			if tick_bubble:
				e.say("Tamir ediliyor... %%%d" % int(100.0 * minf(e.work / e.need, 1.0)))
			if e.work >= e.need:
				_finish(e)


## Raftaki bir işi teknisyene ver (yeterli stoğu olan ilk iş). Hata metni döner ("" = başladı).
func assign(id: int, quiet := false) -> String:
	var e = npcs.get(id)
	if e == null or e.info.role != "teknisyen":
		return "teknisyen yok"
	if e.task != "idle":
		return "meşgul"
	var cands: Array = jobs.tech_candidates()
	if cands.is_empty():
		return "iş yok"
	for rec in cands:
		var p = jobs.devices.get(int(rec.ticket))
		if p == null or not is_instance_valid(p):
			continue
		var pl := make_plan(p, rec)
		# gereken parçaları stoktan ayır (SKU kimliğiyle)
		var res := []
		var missing := ""
		for it in pl.parts:
			var sku_id: String = str(it[1])
			if not Game.take_stock_sku(sku_id):
				missing = PM.display_name_sku(sku_id)
				break
			res.append(sku_id)
		if missing != "":
			for r in res:
				Game.add_stock_sku(str(r), 1)
			if e.noted != p:
				e.noted = p
				e.say_for("Usta stokta %s yok! ParçaNet'ten getirtmek lazım." % missing, 4.0, true)
				Game.msg("%s: stok yok (%s)." % [e.info.name, missing], Color(1, 0.7, 0.4))
			elif not quiet:
				e.say_for("Hâlâ %s yok usta, stok gelmeden yapamam." % missing, 3.0, true)
			continue
		_start_repair(e, rec, p, pl, res)
		return ""
	return "stok yok"


func _start_repair(e, rec: Dictionary, p, pl: Dictionary, res: Array) -> void:
	e.reserved = res
	e.plan = pl
	e.pc = p
	e.rec = rec
	jobs.busy[int(rec.ticket)] = true
	e.noted = null
	e.work = 0.0
	var h: float = BASE_HOURS + PART_HOURS * pl.parts.size() + (DUST_HOURS if pl.dust else 0.0) + (PASTE_HOURS if pl.paste else 0.0)
	e.need = h * SD.time_mult(e.info)
	e.task = "repair"
	e.at_desk = false
	e.say_for("Tamamdır usta, ben hallederim.", 2.5)
	Game.msg("%s #%d numaralı işi aldı (~%.1f saat)." % [e.info.name, int(rec.ticket), e.need], Color(0.6, 0.9, 1.0))
	var front := _rack_front(rec)
	e.walk([SIDE_BACK, RACK_WAY, front], func():
		if e.task != "repair":
			return
		var tp: Vector3 = e.pc.global_position if is_instance_valid(e.pc) else front + Vector3(0.6, 0, 0)
		e.face_angle = atan2(tp.x - e.position.x, tp.z - e.position.z)
		e.at_desk = true
		if is_instance_valid(e.pc) and not e.pc.panel_open:
			e.pc.toggle_panel())


## Bilgisayarın şu anki hâline ve işe göre yapılacaklar: değişecek SKU'lar, toz, macun.
## Stoktaki uyumlu parçayı Compatibility.check() ile seçer.
static func make_plan(p, job: Dictionary) -> Dictionary:
	var parts := []
	var planned_counts := {}
	var hyp := Compatibility.case_state_of(p)
	if not p.slots.has("mobo") and hyp.mobo == null:
		hyp["mobo"] = DB.parts.get_def("mobo_am4_matx")  # anakart yuvası olmayan eski kasalar için yedek
	var order := ["mobo", "psu", "cpu", "cooler", "ram1", "ram2", "ram3", "ram4", "gpu", "ssd", "m2", "fan1", "fan2", "cmos"]
	for sn in p.slots.keys():
		if not order.has(sn):
			order.append(sn)
	var essentials := ["mobo", "psu", "cpu", "cooler", "ram1", "gpu", "ssd"]
	for sn in order:
		if not p.slots.has(sn):
			continue
		var slot = p.slots[sn]
		var part = slot.part
		var need_replace := false
		var pref_sku := ""
		if part and part.broken:
			need_replace = true
			pref_sku = DB.parts.resolve_id(part.sku if not part.sku.is_empty() else Game.sku(part.part_type, part.tier))
		elif part == null and essentials.has(sn):
			if sn == "ssd" and not hyp.storage.is_empty():
				continue
			if sn == "gpu" and hyp.cpu != null and Compatibility.check_display(hyp.cpu, null).ok:
				continue
			need_replace = true
		if need_replace:
			var picked := _pick_compatible_sku(slot, sn, pref_sku, 1, hyp, planned_counts)
			if not picked.is_empty():
				parts.append([sn, picked])
				planned_counts[picked] = int(planned_counts.get(picked, 0)) + 1
				_apply_hyp(hyp, sn, DB.parts.get_def(picked))
	match job.get("kind", ""):
		"upgrade_gpu":
			var g = p.part_in("gpu")
			if g == null or g.tier < 2:
				parts = _drop_slot_plan(parts, planned_counts, "gpu")
				if p.slots.has("gpu"):
					var gsku := _pick_compatible_sku(p.slots["gpu"], "gpu", "gpu_gamer_12g", 2, hyp, planned_counts)
					if not gsku.is_empty():
						parts.append(["gpu", gsku])
						planned_counts[gsku] = int(planned_counts.get(gsku, 0)) + 1
						_apply_hyp(hyp, "gpu", DB.parts.get_def(gsku))
		"upgrade_ram":
			if p.total_ram() < 32:
				parts = _drop_slot_plan(parts, planned_counts, "ram1")
				parts = _drop_slot_plan(parts, planned_counts, "ram2")
				for rslot in ["ram1", "ram2"]:
					if not p.slots.has(rslot):
						continue
					var rsku := _pick_compatible_sku(p.slots[rslot], rslot, "ram_ddr4_16g_rgb", 2, hyp, planned_counts)
					if not rsku.is_empty():
						parts.append([rslot, rsku])
						planned_counts[rsku] = int(planned_counts.get(rsku, 0)) + 1
						_apply_hyp(hyp, rslot, DB.parts.get_def(rsku))
	var cpu = p.part_in("cpu")
	var cpu_new := parts.any(func(it): return it[0] == "cpu")
	return {"parts": parts, "dust": p.dust > 0.02, "paste": cpu != null and not cpu_new and not cpu.paste_ok}


## Verilen yuva için stoktan uyumlu bir SKU seçer (yoksa ilk uyumlu SKU'yu eksik bildirimi için döner).
static func _pick_compatible_sku(slot, slot_name: String, pref_sku: String, min_tier: int, hyp: Dictionary, planned: Dictionary) -> String:
	var accepts := str(slot.accepts)
	var extra: Array = slot.get("accepts_extra") if "accepts_extra" in slot else []
	var mock_slot := {"accepts": accepts, "accepts_extra": extra, "part": null, "name": slot_name}
	# tercih edilen SKU stokta ve uyumluysa doğrudan onu seç
	if not pref_sku.is_empty():
		var pd: PartDef = DB.parts.get_def(pref_sku)
		if pd != null and pd.tier >= min_tier and Game.stock_of_sku(pd.id) - int(planned.get(pd.id, 0)) > 0:
			var r := Compatibility.check(mock_slot, pd, hyp)
			if r.ok and r.severity == "ok":
				return pd.id
	# aksi halde stoktaki tüm uyumlu adaylardan en ucuzunu (önce uyarısız) seç
	var cats := [accepts] + extra
	var cands: Array = []
	for c in cats:
		for d in DB.parts.by_category(str(c)):
			if d.tier >= min_tier:
				cands.append(d)
	cands.sort_custom(func(a, b): return a.price < b.price)
	var warn_match := ""
	var first_compat := ""
	for d in cands:
		var r := Compatibility.check(mock_slot, d, hyp)
		if not r.ok:
			continue
		if first_compat.is_empty():
			first_compat = d.id
		if Game.stock_of_sku(d.id) - int(planned.get(d.id, 0)) > 0:
			if r.severity == "ok":
				return d.id
			if warn_match.is_empty():
				warn_match = d.id
	if not warn_match.is_empty():
		return warn_match
	if not pref_sku.is_empty():
		var pd2: PartDef = DB.parts.get_def(pref_sku)
		if pd2 != null and Compatibility.check(mock_slot, pd2, hyp).ok:
			return pd2.id
	return first_compat if not first_compat.is_empty() else DB.parts.id_for(accepts, min_tier)


static func _apply_hyp(hyp: Dictionary, slot_name: String, d: PartDef) -> void:
	if d == null:
		return
	hyp.slots_occupied[slot_name] = d
	match d.category:
		"mobo": hyp["mobo"] = d
		"cpu": hyp["cpu"] = d
		"cooler": hyp["cooler"] = d
		"ram":
			var rs: Array = hyp.rams.duplicate()
			rs.append(d)
			hyp["rams"] = rs
		"gpu": hyp["gpu"] = d
		"psu": hyp["psu"] = d
		"ssd", "hdd", "nvme":
			var st: Array = hyp.storage.duplicate()
			st.append(d)
			hyp["storage"] = st
		"fan":
			var fs: Array = hyp.fans.duplicate()
			fs.append(d)
			hyp["fans"] = fs
		"cmos": hyp["cmos"] = d


static func _drop_slot_plan(parts: Array, planned: Dictionary, slot_name: String) -> Array:
	var out := []
	for it in parts:
		if it[0] == slot_name:
			planned[it[1]] = maxi(0, int(planned.get(it[1], 0)) - 1)
		else:
			out.append(it)
	return out


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
		var lost_sku: String = str(pl.parts[0][1])
		var dname := PM.display_name_sku(lost_sku)
		if Game.take_stock_sku(lost_sku):
			e.say_for("Eyvah, %s ters taktım, yandı! Yenisini takıyorum." % dname, 3.5, true)
			Game.msg("%s hata yaptı: 1 %s yandı (itibar düştü)." % [d.name, dname], Color(1, 0.6, 0.4))
			e.need += e.need * 0.4
			return
		# yanan parçanın yenisi stokta yok: ayrılanın biri gitti, kalanı rafa döner
		for i in e.reserved.size():
			var rsku: String = Game.sku(str(e.reserved[i][0]), int(e.reserved[i][1])) if e.reserved[i] is Array else str(e.reserved[i])
			if rsku == lost_sku:
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
				var osku: String = old.sku if not old.sku.is_empty() else Game.sku(old.part_type, old.tier)
				Game.add_stock_sku(osku, 1)  # sağlam eski parça rafa
			old.queue_free()
		slot.install(PART.new().setup_sku(str(it[1]), false))
	e.reserved = []
	if pl.dust:
		p.clean_dust()
	if pl.paste and p.part_in("cpu"):
		p.part_in("cpu").paste_ok = true
	Game.sfx.click()
	if p.panel_open:
		p.toggle_panel()
	Game.change_rep(float(SD.trait_info(d.trait).rep))
	var problem: String = jobs._problem_of(e.rec)
	if problem != "":
		_abort(e, "Usta bir şey eksik kaldı, sen bir bakar mısın?")
		return
	e.say_for("Tamamdır, tıkır tıkır çalışıyor! Rafa hazır diye bıraktım.", 3.0)
	jobs.staff_finished(e.rec)
	_release(e)
	_go_home(e)


func _abort(e, line: String) -> void:
	_release(e)
	e.at_desk = false
	if line != "":
		e.say_for(line, 4.0, true)
	else:
		e.say("")
	_go_home(e)
