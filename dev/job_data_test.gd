extends Node
## Geliştirici testi: `godot --headless -- --jobdatatest` arıza/iş verisini doğrular,
## her şablondan bir iş üretip gerekli anahtarları denetler.

const JM := preload("res://scripts/job_manager.gd")
const REQUIRED := ["name", "kind", "intro", "goal", "pay", "parts"]


func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	var db = DB.jobs
	assert(db.errors.is_empty(), "veri doğrulama hataları: %s" % [db.errors])
	assert(db.templates().size() > 0 and db.faults_for("pc").size() > 0, "veri yüklenmedi")
	var total := 0
	for t in db.templates():
		total += t.weight
		assert(t.weight >= 0, "negatif ağırlık: " + t.id)
		if t.fault != "":
			assert(db.fault(t.fault) != null, "bilinmeyen arıza: " + t.fault)
	assert(total == 100, "toplam ağırlık 100 değil: %d" % total)
	for dev in ["pc", "laptop", "phone"]:
		assert(not db.faults_for(dev).is_empty(), "arıza yok: " + dev)
	for code in ["nopower", "cpu", "ram", "gpu", "ssd", "overheat"]:
		var f = db.fault_by_code(code)
		assert(f != null and f.hint != "" and not f.fail_lines.is_empty(), "eksik arıza verisi: " + code)
	var jm = JM.new()
	for t in db.templates():
		for i in 20:  # rastgele dallar için birkaç tur
			var j: Dictionary = jm._make_job_of(t.id)
			for k in REQUIRED:
				assert(j.has(k), "%s: '%s' anahtarı yok" % [t.id, k])
			assert(j.kind == t.job_kind, "%s: kind uyumsuz" % t.id)
			assert(str(j.intro) != "" and str(j.goal) != "" and int(j.pay) > 0, t.id + ": boş metin/ücret")
			assert(typeof(j.parts) == TYPE_ARRAY, t.id + ": parts dizi değil")
			if t.kind == "sale":
				assert(j.has("want"), t.id + ": want yok")
			if t.kind in ["repair", "device"]:
				assert(j.has("broken") and j.broken != "", t.id + ": broken yok")
	jm.free()
	print("JOBDATATEST OK (%d şablon, %d arıza)" % [db.templates().size(), db.faults_for("pc").size() + db.faults_for("laptop").size() + db.faults_for("phone").size()])
	get_tree().quit()
