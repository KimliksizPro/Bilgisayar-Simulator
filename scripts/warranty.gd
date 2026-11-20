extends RefCounted
## Garanti: muadil parça takılı teslim edilen işler 1-2 gün içinde geri dönebilir.
## Dönen iş "warranty" türünde ücretsiz bir tamirdir; reddedilirse/başarısız olunursa itibar düşer.

const PM := preload("res://scripts/part_models.gd")
const DJ := preload("res://scripts/device_jobs.gd")

const REP_FAST := 0.15        # hızlı garanti servisinde itibar kazancı
const REP_SLOW := 0.05
const REP_ANGRY_EXTRA := 0.3  # garanti müşterisi kızıp giderse ek itibar kaybı


## Teslimden hemen önce çağrılır: takılı muadil parçalardan biri ileride bozulacaksa kaydeder.
static func on_delivered(pc, job: Dictionary) -> void:
	for part in pc.installed_parts():
		if part.cheap and randf() < Game.warranty_chance:
			var sku_id: String = DB.parts.resolve_id(part.sku if not part.sku.is_empty() else Game.sku(part.part_type, part.tier))
			var d: PartDef = DB.parts.get_def(sku_id)
			Game.warranty_list.append({
				"due": Game.day + randi_range(1, 2),
				"name": str(job.get("name", "Müşteri")),
				"sku": sku_id,
				"type": d.category if d else part.part_type,
				"tier": d.tier if d else part.tier,
				"device": str(job.get("device", "")),
			})
			return  # bir iş en fazla bir kez geri döner


## Garanti kaydından kanonik SKU kimliğini çözer (eski {type, tier} kayıtları dahil).
static func _resolve_sku(w: Dictionary) -> String:
	var raw := str(w.get("sku", ""))
	if not raw.is_empty():
		return DB.parts.resolve_id(raw)
	return DB.parts.resolve_id(Game.sku(str(w.get("type", "ram")), int(w.get("tier", 1))))


## Günü gelmiş ilk garanti kaydını listeden çıkarıp döndürür; yoksa boş sözlük.
static func take_due() -> Dictionary:
	for i in Game.warranty_list.size():
		if int(Game.warranty_list[i].due) <= Game.day:
			var w: Dictionary = Game.warranty_list[i]
			Game.warranty_list.remove_at(i)
			return w
	return {}


## Garanti işi: aynı SKU'lu parçası arızalı, ücretsiz bir tamir. base: job_manager'ın parça listesi.
static func make_job(w: Dictionary, base: Array) -> Dictionary:
	var dev: String = str(w.get("device", ""))
	if dev != "":
		return _device_job(w, dev)
	var sku_id := _resolve_sku(w)
	var d: PartDef = DB.parts.get_def(sku_id)
	var broken: String = d.category if d else str(w.get("type", "ram"))
	var parts := []
	for b in base:
		if b is Dictionary:
			var nb: Dictionary = b.duplicate()
			var b_sku := DB.parts.resolve_id(str(nb.get("sku", "")))
			var bd: PartDef = DB.parts.get_def(b_sku)
			var b_cat := bd.category if bd else str(nb.get("type", ""))
			var is_match := b_cat == broken
			if is_match:
				nb["sku"] = sku_id
			nb["broken"] = is_match
			parts.append(nb)
		else:
			parts.append([b[0], b[1], b[2], b[1] == broken])
	var label := PM.display_name_sku(sku_id) if d else PM.type_name(broken)
	return {"name": w.name, "kind": "warranty", "warranty": true, "broken": broken, "broken_sku": sku_id, "pay": 0, "parts": parts,
		"intro": DB.jobs.text("warranty_pc_intro")[0],
		"goal": DB.jobs.text("warranty_pc_goal")[0] % label}


## Laptop/telefon garanti dönüşü: aynı cihaz, muadil takılan parçanın yuvası arızalı.
static func _device_job(w: Dictionary, dev: String) -> Dictionary:
	var sku_id := _resolve_sku(w)
	var d: PartDef = DB.parts.get_def(sku_id)
	var cat: String = d.category if d else str(w.get("type", ""))
	var j := DJ.make({"name": w.name}, dev)
	var table: Dictionary = DJ.slots(dev)
	var slot_name := ""
	for sl in table:
		if table[sl] == cat:
			slot_name = sl
	if slot_name == "":
		slot_name = j.broken
	var parts := []
	for sl in table:
		parts.append([sl, table[sl], 1, sl == slot_name])
	j.parts = parts
	j.broken = slot_name
	j.broken_sku = sku_id
	j.kind = "warranty"
	j.warranty = true
	j.pay = 0
	j.intro = DB.jobs.text("warranty_dev_intro")[0]
	j.goal = DB.jobs.text("warranty_dev_goal")[0] % PM.display_name_sku(sku_id)
	return j
