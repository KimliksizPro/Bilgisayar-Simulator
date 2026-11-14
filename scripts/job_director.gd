extends RefCounted
## İş seçici: ağırlıklı torba (tekrarsız çekim) + yakın geçmiş cezası.
## Aynı iş art arda gelmez, aynı parça ailesi (gpu, ram...) en fazla 2 kez üst üste gelir.

const HISTORY_LEN := 4
const BUILD_MIN_MONEY := 300

## id -> [ağırlık, aile]. Toplam 100; aile payı en çok ~%15.
const TABLE := {
	"repair_psu": [8, "psu"], "repair_cpu": [8, "cpu"], "repair_ram": [7, "ram"],
	"repair_gpu": [7, "gpu"], "repair_ssd": [7, "ssd"],
	"overheat_dust": [4, "cooling"], "overheat_paste": [4, "cooling"],
	"upgrade_gpu": [5, "gpu"], "upgrade_ram": [5, "ram"], "build": [5, "build"],
	"sale_ram1": [2, "ram"], "sale_ram2": [1, "ram"], "sale_ssd": [3, "ssd"], "sale_psu": [3, "psu"],
	"sale_gpu1": [1, "gpu"], "sale_gpu2": [1, "gpu"], "sale_cpu": [4, "cpu"],
	"device_laptop": [14, "laptop"], "device_phone": [11, "phone"],
}

var bag: Array = []


static func family_of(id: String) -> String:
	return TABLE[id][1] if TABLE.has(id) else ""


static func _eligible(id: String, money: int) -> bool:
	return id != "build" or money >= BUILD_MIN_MONEY


func _refill() -> void:
	var fresh := []
	for id in TABLE:
		for i in TABLE[id][0]:
			fresh.append(id)
	fresh.shuffle()
	bag.append_array(fresh)


## Sıradaki iş kimliğini seçer; history (son seçilenler, en yeni sonda) yerinde güncellenir.
func next(money: int, history: Array) -> String:
	# uygun olmayanlar (para yetmeyen build) torbada birikmesin
	bag = bag.filter(func(k): return _eligible(k, money))
	if bag.is_empty():
		_refill()
	var last: String = history.back() if not history.is_empty() else ""
	var fams := []
	for h in history:
		fams.append(family_of(str(h)))
	var pick := ""
	# 0. kat: id farklı + aile son 3 içinde yok; 1. kat: id farklı + aile 2 kez üst üste değil
	for tier in 2:
		for attempt in 2:  # torbada uygun yoksa bir kez doldurup yeniden dene
			var idx := _find(tier, money, last, fams)
			if idx >= 0:
				pick = bag[idx]
				bag.remove_at(idx)
				break
			if attempt == 0:
				_refill()
		if pick != "":
			break
	if pick == "":  # kilitlenme olmasın: uygun herhangi biri
		var ok := TABLE.keys().filter(func(k): return _eligible(k, money))
		var diff := ok.filter(func(k): return k != last)
		pick = (diff if not diff.is_empty() else ok).pick_random()
	history.append(pick)
	while history.size() > HISTORY_LEN:
		history.pop_front()
	return pick


func _find(tier: int, money: int, last: String, fams: Array) -> int:
	var recent := fams.slice(maxi(0, fams.size() - 3))
	var f1: String = fams.back() if fams.size() >= 1 else ""
	var f2: String = fams[fams.size() - 2] if fams.size() >= 2 else ""
	for i in bag.size():
		var id: String = bag[i]
		if not _eligible(id, money) or id == last:
			continue
		var fam := family_of(id)
		if tier == 0 and fam in recent:
			continue
		if tier == 1 and fam == f1 and fam == f2:
			continue
		return i
	return -1
