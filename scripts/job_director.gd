extends RefCounted
## İş seçici: ağırlıklı torba (tekrarsız çekim) + yakın geçmiş cezası.
## Aynı iş art arda gelmez, aynı parça ailesi (gpu, ram...) en fazla 2 kez üst üste gelir.

const HISTORY_LEN := 4

## Tablo data/jobs.json'dan gelir (DB.jobs.templates()): ağırlık, aile, uygunluk (min_money/min_day/min_rep).
## Toplam ağırlık 100 olacak şekilde ayarlı; aile payı en çok ~%15.

var bag: Array = []
var _day := 0
var _rep := 0.0


static func family_of(id: String) -> String:
	var t = DB.jobs.template(id)
	return t.family if t != null else ""


## Uygunluk: para / gün / itibar / geliştirme eşikleri (şablondan).
func _eligible(id: String, money: int) -> bool:
	var t = DB.jobs.template(id)
	if t == null or money < t.min_money or _day < t.min_day or _rep < t.min_rep:
		return false
	if t.req_upgrade != "" and not Game.has_upgrade(t.req_upgrade):
		return false
	return true


func _refill() -> void:
	var fresh := []
	for t in DB.jobs.templates():
		for i in t.weight:
			fresh.append(t.id)
	fresh.shuffle()
	bag.append_array(fresh)


## Sıradaki iş kimliğini seçer; history (son seçilenler, en yeni sonda) yerinde güncellenir.
func next(money: int, history: Array, day := 0, rep := 0.0) -> String:
	_day = day
	_rep = rep
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
		var ok := DB.jobs.templates().map(func(t): return t.id).filter(func(k): return _eligible(k, money))
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
