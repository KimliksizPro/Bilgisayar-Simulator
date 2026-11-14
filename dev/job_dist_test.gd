extends Node
## Geliştirici testi: `godot --headless -- --jobdisttest` iş seçicinin dağılımını ölçer.

const DIRECTOR := preload("res://scripts/job_director.gd")
const N := 2000


func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	var d = DIRECTOR.new()
	var hist: Array = []
	var fam_count := {}
	var id_count := {}
	var max_id := 0
	var max_fam := 0
	var cur_id := 0
	var cur_fam := 0
	var last_id := ""
	var last_fam := ""
	# para < 300 ve >= 300 iki turda denenir
	for rnd in 2:
		var money := 100 if rnd == 0 else 1000
		for i in N:
			var id: String = d.next(money, hist)
			var fam: String = DIRECTOR.family_of(id)
			if rnd == 0:
				assert(id != "build", "para < 300 iken build seçildi")
			id_count[id] = int(id_count.get(id, 0)) + 1
			fam_count[fam] = int(fam_count.get(fam, 0)) + 1
			cur_id = cur_id + 1 if id == last_id else 1
			cur_fam = cur_fam + 1 if fam == last_fam else 1
			max_id = maxi(max_id, cur_id)
			max_fam = maxi(max_fam, cur_fam)
			last_id = id
			last_fam = fam
	var total := N * 2
	print("--- iş dağılımı (%d çekim) ---" % total)
	var fams := fam_count.keys()
	fams.sort()
	for f in fams:
		print("aile %-8s %5.1f%%" % [f, 100.0 * fam_count[f] / total])
	var ids := id_count.keys()
	ids.sort()
	for k in ids:
		print("id   %-15s %5.1f%%" % [k, 100.0 * id_count[k] / total])
	print("en uzun aynı-id serisi: %d, aynı-aile serisi: %d" % [max_id, max_fam])
	assert(max_id == 1, "aynı id art arda geldi")
	assert(max_fam <= 2, "aynı aile 3 kez art arda geldi")
	print("OK iş dağılımı testi")
	get_tree().quit()
