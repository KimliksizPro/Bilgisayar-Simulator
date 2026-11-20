extends RefCounted
## Çoklu iş yardımcıları (saf fonksiyonlar): teslim zamanı hesabı, iş kaydı normalleştirme,
## cihaz durumunu kaydetme/geri yükleme, cihazı "kilitleme" (rafta/elde etkileşimi kapatma)
## ve cihaza yapışan fiş etiketi (Label3D + taşıma tutacağı).

const MU := preload("res://scripts/mesh_util.gd")
const DJ := preload("res://scripts/device_jobs.gd")
const PC := preload("res://scripts/pc_case.gd")

# --- teslim zamanı ayarları (oyun saati) ---
const EXPRESS_CHANCE := 0.2      # tamir işlerinin bu kadarı "bugün lazım" der
const EXPRESS_HOURS := 3.0       # ekspres iş: şimdiden bu kadar saat sonra
const EXPRESS_LATEST := 15.5     # bu saatten sonra gelen iş ekspres olmaz
const EXPRESS_BONUS := 1.2       # ekspres işin ücret çarpanı
const PICKUP_HOURS := [10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0]
const LONG_JOB_HOURS := 6.0      # şablon süresi bu kadar ya da fazlaysa iş 2 gün sürer (sıfırdan toplama)
const KEEP_META := "job_tag"     # kilitlenmeyen çarpışma düğümü işareti


## Yeni işin teslim zamanı: {due_abs, express}. now: Game.now_abs().
## Kural: tamir/yükseltme/garanti = ertesi gün 10:00-18:00 arası; sıfırdan toplama (şablon süresi >= 6 saat) = 2 gün sonra;
## ekspres (%20, toplama ve garanti hariç, saat 15:30'a kadar) = 3 oyun saati sonrası, aynı gün.
static func make_due(job: Dictionary, now: float, force_express := -1) -> Dictionary:
	var day := int(now / 24.0)
	var hour := now - day * 24.0
	var long: bool = float(job.get("hours", 0.0)) >= LONG_JOB_HOURS
	var can_express: bool = not long and not job.get("warranty", false) and hour <= EXPRESS_LATEST
	var express: bool = can_express and (randf() < EXPRESS_CHANCE if force_express < 0 else force_express == 1)
	if express:
		var due := snappedf(now + EXPRESS_HOURS, 0.5)
		return {"due_abs": due, "express": true}
	var days := 2 if long else 1
	var pick: float = PICKUP_HOURS.pick_random()
	return {"due_abs": (day + days) * 24.0 + pick, "express": false}


## "12:30" biçimi (mutlak saatten).
static func hour_text(abs_t: float) -> String:
	var d := int(abs_t / 24.0)
	var h := abs_t - d * 24.0
	return "%02d:%02d" % [int(h), int((h - int(h)) * 60.0)]


## Kısa teslim etiketi: "Bugün 15:30" / "Yarın 14:00" / "Gün 6 11:00".
static func due_label(due_abs: float, today: int) -> String:
	var d := int(due_abs / 24.0)
	var s := hour_text(due_abs)
	if d <= today:
		return "Bugün " + s
	if d == today + 1:
		return "Yarın " + s
	return "Gün %d %s" % [d, s]


## Müşterinin söyleyeceği söz: "Yarın öğlen uğrarım".
static func when_phrase(due_abs: float, today: int) -> String:
	var d := int(due_abs / 24.0)
	var h := due_abs - d * 24.0
	var part := "sabah" if h < 11.5 else ("öğlen" if h < 14.0 else ("ikindi" if h < 17.0 else "akşama doğru"))
	if d <= today:
		return "Bugün %s, saat %s gibi uğrarım" % [part, hour_text(due_abs)]
	if d == today + 1:
		return "Yarın %s uğrarım" % part
	return "Öbür gün %s uğrarım" % part


## Durum rengi: bekliyor = kehribar, hazır = yeşil, gecikmiş = kırmızı.
static func status_color(rec: Dictionary, now: float) -> Color:
	if str(rec.status) == "ready":
		return Color(0.25, 0.9, 0.4)
	if now > float(rec.due_abs):
		return Color(1.0, 0.2, 0.15)
	return Color(1.0, 0.7, 0.15)


static func status_text(rec: Dictionary, now: float) -> String:
	match str(rec.status):
		"ready": return "HAZIR"
		"on_bench": return "TEZGÂHTA"
		"failed": return "BAŞARISIZ"
	return "GECİKTİ" if now > float(rec.due_abs) else "BEKLİYOR"


## HUD listesi için kısa iş adı (arızayı ele vermez).
static func short_goal(rec: Dictionary) -> String:
	var ex: String = " · EKSPRES" if rec.get("express", false) else ""
	if rec.get("warranty", false):
		return "GARANTİ dönüşü" + ex
	match str(rec.get("kind", "")):
		"overheat_dust", "overheat_paste": return "PC aşırı ısınıyor" + ex
		"incompat_ram_ddr", "incompat_psu_gpu", "incompat_no_igpu": return "Uyumluluk sorunu" + ex
		"upgrade_gpu": return "Ekran kartı yükseltme" + ex
		"upgrade_ram": return "RAM 32 GB yükseltme" + ex
		"build": return "Sıfırdan PC toplama" + ex
		"laptop": return "Laptop tamiri" + ex
		"phone": return "Telefon tamiri" + ex
	return "PC arızası" + ex


# ---------------------------------------------------------------- kayıt normalleştirme (JSON sayıları float gelir)
static func normalize(r: Dictionary) -> Dictionary:
	var out: Dictionary = r.duplicate(true)
	for k in ["ticket", "pay", "due_day", "ext", "wrong", "fail_count"]:
		out[k] = int(out.get(k, 0))
	for k in ["due_abs", "accepted_abs", "ready_abs", "hours"]:
		if out.has(k):
			out[k] = float(out[k])
	out.due_abs = float(out.get("due_abs", 0.0))
	out.accepted_abs = float(out.get("accepted_abs", out.due_abs - 24.0))
	out.express = bool(out.get("express", false))
	out.warranty = bool(out.get("warranty", false))
	out.called = false  # yüklemede müşteri çağrısı yeniden değerlendirilir
	out.status = str(out.get("status", "waiting_bench"))
	out.location = str(out.get("location", "rack:0"))
	if out.status == "on_bench":
		out.status = "waiting_bench"  # tezgâhta kalan iş yüklemede yine tezgâha konur
		out.location = "bench"
	out.name = str(out.get("name", "Müşteri"))
	out.kind = str(out.get("kind", "repair"))
	out.device = str(out.get("device", ""))
	out.broken = str(out.get("broken", ""))
	var is_pc: bool = out.device == "" or out.device == "pc"
	if is_pc:
		var cid := str(out.get("case_id", "atx_mid"))
		out["case_id"] = "atx_mid" if cid.is_empty() else cid
	out.parts = _norm_parts(out.get("parts", []))
	var st = out.get("state", null)
	if st is Dictionary:
		if is_pc:
			var scid := str(st.get("case_id", out.get("case_id", "atx_mid")))
			st["case_id"] = "atx_mid" if scid.is_empty() else scid
		st.parts = _norm_parts(st.get("parts", []))
		st.dust = float(st.get("dust", 0.0))
		st.socket_paste = bool(st.get("socket_paste", false))
		out.state = st
	else:
		out.state = null
	if out.has("target") and not (out.target is Dictionary):
		out.erase("target")
	if out.has("target"):
		for k in ["min_tier", "ram_gb"]:
			if out.target.has(k):
				out.target[k] = int(out.target[k])
	return out


## Parça listesini normalleştirir: v4 sözlükleri ve geriye dönük v3 dizileri desteklenir.
static func _norm_parts(parts: Array) -> Array:
	var out := []
	for p in parts:
		if p is Dictionary:
			var sn := str(p.get("slot", ""))
			if sn == "dust" or p.has("dust"):
				out.append({"slot": "dust", "amount": float(p.get("amount", p.get("dust", 0.0)))})
				continue
			var raw_sku := str(p.get("sku", ""))
			var sku_id: String = DB.parts.resolve_id(raw_sku) if not raw_sku.is_empty() else ""
			out.append({
				"slot": sn,
				"sku": sku_id,
				"broken": bool(p.get("broken", false)),
				"paste_ok": bool(p.get("paste_ok", true)),
				"cheap": bool(p.get("cheap", false)),
				"health": int(p.get("health", 100)),
			})
		elif p is Array and p.size() >= 4:
			var q := [str(p[0]), str(p[1]), (float(p[2]) if str(p[0]) == "dust" else int(p[2])), bool(p[3])]
			if p.size() > 4:
				q.append(bool(p[4]))
			if p.size() > 5:
				q.append(bool(p[5]))
			out.append(q)
	return out


# ---------------------------------------------------------------- cihaz durumu
## Cihazın parça durumunu v4 kayda yazılabilir sözlüğe çevirir:
## case_id (PC için), parts: [{slot, sku, broken, paste_ok, cheap, health}], dust, socket_paste.
static func snapshot(dev) -> Dictionary:
	var parts := []
	for sn in dev.slots:
		var p = dev.slots[sn].part
		if p != null:
			var raw_sku: String = p.sku if not p.sku.is_empty() else DB.parts.id_for(p.part_type, p.tier)
			var sku_id: String = DB.parts.resolve_id(raw_sku) if not raw_sku.is_empty() else raw_sku
			parts.append({
				"slot": str(sn),
				"sku": sku_id,
				"broken": bool(p.broken),
				"paste_ok": bool(p.paste_ok),
				"cheap": bool(p.cheap),
				"health": int(p.health) if "health" in p else 100,
			})
	var out := {
		"parts": parts,
		"dust": float(dev.dust) if "dust" in dev else 0.0,
		"socket_paste": bool(dev.socket_paste) if "socket_paste" in dev else false,
	}
	if "case_id" in dev:
		out["case_id"] = str(dev.case_id)
	return out


## Boş yeni cihaza kayıtlı durumu kurar (v4 sözlükleri ve geriye dönük v3 dizileri destekler).
static func restore(dev, state: Dictionary) -> void:
	var is_pc: bool = not dev.has_method("slot_open")
	var raw_parts: Array = state.get("parts", [])
	var fill := []
	var cheap_slots := []
	var seen := {}
	for p in raw_parts:
		if p is Dictionary:
			var sn := str(p.get("slot", ""))
			if sn == "dust" or p.has("dust"):
				if is_pc:
					fill.append(p)
				continue
			seen[sn] = true
			if is_pc:
				fill.append(p)
			else:
				var sku_id: String = DB.parts.resolve_id(str(p.get("sku", "")))
				var d: PartDef = DB.parts.get_def(sku_id)
				var pt: String = d.category if d != null else str(p.get("type", ""))
				var tr: int = d.tier if d != null else int(p.get("tier", 1))
				fill.append([sn, pt, tr, bool(p.get("broken", false))])
				if bool(p.get("cheap", false)):
					cheap_slots.append(sn)
		elif p is Array and p.size() >= 4:
			var sn := str(p[0])
			seen[sn] = true
			fill.append([sn, p[1], p[2], p[3], p[4] if p.size() > 4 else true])
			if p.size() > 5 and bool(p[5]):
				cheap_slots.append(sn)
	# PC kaydında sökülü bırakılmış varsayılan parçalar geri takılmasın (omit işareti)
	if is_pc and not raw_parts.is_empty():
		for def_slot in ["mobo", "cooler", "fan1", "cmos"]:
			if not seen.has(def_slot):
				fill.append({"slot": def_slot, "omit": true})
	dev.fill(fill)
	for sn in cheap_slots:
		if dev.slots.has(sn) and dev.slots[sn].part != null:
			dev.slots[sn].part.make_cheap()
	if "dust" in dev and float(state.get("dust", 0.0)) > 0.0:
		dev.set_dust(float(state.dust))
	if "socket_paste" in dev and bool(state.get("socket_paste", false)):
		dev.socket_paste = true
		dev._update_visuals()


# ---------------------------------------------------------------- kilit (rafta/elde cihaz etkileşimi kapalı)
## locked: cihazın tüm çarpışma düğümleri (kasa, cam, yuvalar, parçalar) ışına kapanır ve yuva güncellemesi durur.
## Fiş etiketi (KEEP_META) açık kalır; taşıma tutacağı odur.
static func lock(dev, locked: bool) -> void:
	for n in dev.find_children("*", "CollisionObject3D", true, false):
		if n.has_meta(KEEP_META):
			continue
		if locked:
			if not n.has_meta("lock_layer"):
				n.set_meta("lock_layer", n.collision_layer)
				n.collision_layer = 0
		elif n.has_meta("lock_layer"):
			n.collision_layer = int(n.get_meta("lock_layer"))
			n.remove_meta("lock_layer")
	for s in dev.slots.values():
		s.set_process(not locked)
		if locked:
			s.ghost.visible = false


# ---------------------------------------------------------------- fiş etiketi
## Cihaza yapışan kâğıt fiş. Dönen düğüm: {root, stripe_mat}. hint/action job_manager'a bağlanır.
## Kasa: cam yanına dik duran kartela; laptop/telefon: ön kenarda hafif eğik.
static func attach_tag(dev, rec: Dictionary, hint_fn: Callable, action: Callable) -> Dictionary:
	var is_pc: bool = not dev.has_method("slot_open")
	var root := Node3D.new()
	root.name = "TicketTag"
	if is_pc:
		root.position = Vector3(PC.W / 2.0 + 0.06, 0.0, -0.11)
		root.rotation_degrees = Vector3(0, 90, 0)
	else:
		var front: float = (DJ.LAPTOP.D if str(rec.get("device", "")) == "laptop" else DJ.PHONE.PL) / 2.0
		root.position = Vector3(0.0, 0.0, front + 0.07)
	dev.add_child(root)
	MU.no_merge(root)
	var paper := MU.new_mat(Color(0.97, 0.94, 0.84), 0, 0.85)
	var stripe := MU.new_mat(Color(1.0, 0.7, 0.15), 0, 0.5, 0.8)
	var card := Node3D.new()
	card.rotation_degrees = Vector3(-24, 0, 0)
	card.position = Vector3(0, 0.044, 0)
	root.add_child(card)
	MU.box(card, Vector3(0.13, 0.085, 0.003), Vector3.ZERO, paper)
	MU.box(card, Vector3(0.13, 0.014, 0.0035), Vector3(0, 0.0355, 0.0004), stripe)
	var num := MU.label(card, "#%d" % int(rec.ticket), Vector3(0, 0.006, 0.0022), 64, Color(0.12, 0.2, 0.55), Vector3.ZERO, 0.00062)
	num.double_sided = false
	var nm := MU.label(card, str(rec.name), Vector3(0, -0.027, 0.0022), 40, Color(0.15, 0.13, 0.1), Vector3.ZERO, 0.0006)
	nm.double_sided = false
	# küçük ayak (kartelayı taşıyan çubuk)
	MU.box(root, Vector3(0.02, 0.03, 0.004), Vector3(0, 0.015, -0.022), paper, Vector3(15, 0, 0))
	var it = MU.interactable(root, Vector3(0.14, 0.1, 0.07), Vector3(0, 0.05, 0), hint_fn, action)
	it.set_meta(KEEP_META, true)
	return {"root": root, "stripe": stripe}
