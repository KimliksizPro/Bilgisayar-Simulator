extends RefCounted
## İkinci el pazarı: her gün aynı tohumdan üretilen kullanılmış parça ilanları.
## Satın alınan parça orijinal stoğa girer ama "arızalı çıkabilir" ilanlarda gizli bozuk olabilir.

const PM := preload("res://scripts/part_models.gd")

const COUNT := 6


## Günün ilanları (gün numarası tohum olduğundan kayıttan dönünce aynı ilanlar gelir).
static func generate(day: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 7919 + 13
	var cat_ids: Array = DB.parts.catalog_ids()
	var out := []
	if cat_ids.is_empty():
		return out
	for i in COUNT:
		var sku_id: String = str(cat_ids[rng.randi_range(0, cat_ids.size() - 1)])
		var d: PartDef = DB.parts.get_def(sku_id)
		var cond := rng.randi_range(35, 95)
		var risky := rng.randf() < 0.3
		var base: int = PM.price_sku(sku_id)
		var f := lerpf(0.22, 0.5, cond / 100.0) * (0.8 if risky else 1.0)
		out.append({
			"id": i,
			"sku": sku_id,
			"type": d.category if d else "",
			"tier": d.tier if d else 1,
			"cond": cond,
			"risky": risky,
			"price": maxi(5, roundi(base * f / 5.0) * 5),
			"sold": false,
		})
	return out


## Bu ilandaki parçanın bozuk çıkma ihtimali.
static func dud_chance(l: Dictionary) -> float:
	return 0.45 if l.risky else (100 - int(l.cond)) / 400.0


## İlanı satın al: parayı öder, parçayı stoğa koyar (gizli arıza şansıyla). force_dud: test için 0/1.
static func buy(id: int, force_dud := -1) -> bool:
	for l in Game.used_listings:
		if int(l.id) != id or l.sold:
			continue
		if not Game.spend(int(l.price), "parts"):
			Game.sfx.error()
			Game.msg("Paran yetmiyor! (%d TL lazım)" % int(l.price), Color(1, 0.5, 0.4))
			return false
		l.sold = true
		var dud: bool = randf() < dud_chance(l) if force_dud < 0 else force_dud == 1
		var k: String = DB.parts.resolve_id(str(l.get("sku", Game.sku(str(l.get("type", "")), int(l.get("tier", 1))))))
		Game.add_stock_sku(k, 1)
		if dud:
			Game.stock_dud[k] = int(Game.stock_dud.get(k, 0)) + 1
		Game.sfx.coin()
		Game.msg("İkinci el %s alındı, rafa kondu." % PM.display_name_sku(k), Color(0.6, 0.9, 1.0))
		return true
	return false
