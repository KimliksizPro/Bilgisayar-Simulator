extends RefCounted
## Laptop ve telefon işleri: müşteri cümleleri, iş üretimi, cihazı masaya koyma.
## job_manager.gd bu dosyayı birkaç satırla çağırır (iş üretimi, kabul, teslim kontrolü).

const LAPTOP := preload("res://scripts/laptop_device.gd")
const PHONE := preload("res://scripts/phone_device.gd")
const PM := preload("res://scripts/part_models.gd")

const CHANCE := 0.3   # tamir işlerinin yaklaşık bu kadarı laptop/telefon olur

## Cihazın yuva -> parça türü tablosu (arıza tanımlarından: part'ı olan kayıtlar).
static func slots(dev: String) -> Dictionary:
	var table := {}
	for f in DB.jobs.faults_for(dev):
		if f.part != "":
			table[f.diag_code] = f.part
	return table


## Yuvadaki veya bayraktaki arıza tanımı (laptop/telefon).
static func fault_of(dev: String, slot: String):
	return DB.jobs.fault_by_code(slot, dev)


static func is_device(job: Dictionary) -> bool:
	var dev := str(job.get("device", ""))
	return dev == "laptop" or dev == "phone"


## Laptop veya telefon tamir işi üretir (j: içinde "name" olan iş sözlüğü).
static func make(j: Dictionary, device := "", force_broken := "") -> Dictionary:
	var dev := device if device != "" else ("laptop" if randf() < 0.55 else "phone")
	var t = DB.jobs.template("device_" + dev)
	var table: Dictionary = slots(dev)
	var pool: Array = []
	for f in DB.jobs.faults_for(dev):
		if force_broken != "":
			if f.diag_code == force_broken or f.id == force_broken:
				pool.append(f)
		else:
			if Game.day >= f.min_day and (f.req_upgrade == "" or Game.has_upgrade(f.req_upgrade)):
				pool.append(f)
	if pool.is_empty():
		for f in DB.jobs.faults_for(dev):
			if f.part != "":
				pool.append(f)
	var f = pool.pick_random()
	var broken: String = f.diag_code
	var vague: Array = DB.jobs.text(t.intro_pool)
	j.kind = t.job_kind
	j.device = dev
	j.broken = broken
	j.intro = f.customer_lines.pick_random() if randf() < t.specific_chance else vague.pick_random()
	j.goal = t.goal
	j.pay = (PM.price(f.part, 1) if f.part != "" else 0) + f.roll_labor()
	var parts := []
	for slot in table:
		parts.append([slot, table[slot], 1, slot == broken])
	match f.kind:
		"overheat":
			var lo: float = f.dust.x if f.dust.x > 0.0 else 0.7
			var hi: float = f.dust.y if f.dust.y > lo else 0.95
			parts.append({"flags": {"dust": randf_range(lo, hi)}})
		"mechanical":
			parts.append({"flags": {"hinge_loose": true}})
		"liquid":
			parts.append({"flags": {"liquid_damage": true}})
		"software":
			parts.append({"flags": {"sw_fault": true}})
	j.parts = parts
	return j


static func new_device(job: Dictionary):
	return LAPTOP.new() if job.device == "laptop" else PHONE.new()


## Masadaki yer: kasa için pc_spot aynen; laptop/telefon masaya düz, oyuncuya bakar.
static func spot(dev, pc_spot: Transform3D) -> Transform3D:
	if not dev.has_method("slot_open"):
		return pc_spot
	var o := pc_spot.origin
	return Transform3D(Basis.IDENTITY, Vector3(o.x, o.y - 0.012 + dev.LIFT, o.z + 0.04))


## İş kabul edildi: ipuçları ve bildirim.
static func on_accept(hud, job: Dictionary) -> void:
	if job.device == "laptop":
		Game.msg("Laptop masana kondu. Güç düğmesine bas, ekranındaki hatayı oku!", Color(0.6, 0.9, 1.0))
		hud.tip("dev_laptop", "Laptop: güç düğmesi klavyenin sağ üstünde. Alt kapağı açmak için klavyeye bakıp E'ye bas; laptop ters döner. Kırık ekran, laptop düzken sökülür.")
	else:
		Game.msg("Telefon masana kondu. Yan tuştan aç, belirtiye bak!", Color(0.6, 0.9, 1.0))
		hud.tip("dev_phone", "Telefon: güç tuşu sağ kenarda. Açmak için telefonun üstüne bakıp E'ye bas; ekran kitap gibi yana kalkar.")


static func deliver_hint(job: Dictionary) -> String:
	match job.get("device", ""):
		"laptop": return "Laptopu teslim et  [E]"
		"phone": return "Telefonu teslim et  [E]"
	return "Bilgisayarı teslim et  [E]"
