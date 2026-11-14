extends RefCounted
## Garanti: muadil parça takılı teslim edilen işler 1-2 gün içinde geri dönebilir.
## Dönen iş "warranty" türünde ücretsiz bir tamirdir; reddedilirse/başarısız olunursa itibar düşer.

const PM := preload("res://scripts/part_models.gd")

const REP_FAST := 0.15        # hızlı garanti servisinde itibar kazancı
const REP_SLOW := 0.05
const REP_ANGRY_EXTRA := 0.3  # garanti müşterisi kızıp giderse ek itibar kaybı


## Teslimden hemen önce çağrılır: takılı muadil parçalardan biri ileride bozulacaksa kaydeder.
static func on_delivered(pc, job: Dictionary) -> void:
	for part in pc.installed_parts():
		if part.cheap and randf() < Game.warranty_chance:
			Game.warranty_list.append({"due": Game.day + randi_range(1, 2), "name": str(job.get("name", "Müşteri")),
				"type": part.part_type, "tier": part.tier})
			return  # bir iş en fazla bir kez geri döner


## Günü gelmiş ilk garanti kaydını listeden çıkarıp döndürür; yoksa boş sözlük.
static func take_due() -> Dictionary:
	for i in Game.warranty_list.size():
		if int(Game.warranty_list[i].due) <= Game.day:
			var w: Dictionary = Game.warranty_list[i]
			Game.warranty_list.remove_at(i)
			return w
	return {}


## Garanti işi: aynı türden parçası arızalı, ücretsiz bir tamir. base: job_manager'ın parça listesi.
static func make_job(w: Dictionary, base: Array) -> Dictionary:
	var broken: String = w.type
	var parts := []
	for b in base:
		parts.append([b[0], b[1], b[2], b[1] == broken])
	return {"name": w.name, "kind": "warranty", "warranty": true, "broken": broken, "pay": 0, "parts": parts,
		"intro": "Usta taktığın parça bozuldu, garantiden bakacaksın!",
		"goal": "GARANTİ: ücretsiz tamir. Takılan %s bozulmuş; değiştir. Hızlı çözersen itibarın düzelir." % PM.TYPE_NAMES[broken]}
