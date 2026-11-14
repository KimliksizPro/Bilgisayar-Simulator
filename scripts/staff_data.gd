extends RefCounted
## Personel verisi: aday üretimi (isim, rol, beceri, maaş, huy) ve huyların etkileri.

const FIRST := ["Ali", "Cem", "Deniz", "Emre", "Gökhan", "Hakan", "İbo", "Kadir", "Murat", "Onur",
	"Serkan", "Tolga", "Ufuk", "Yusuf", "Ayşe", "Büşra", "Ceren", "Dilek", "Esra", "Gizem", "Merve", "Sevgi"]
const LAST := ["Yılmaz", "Kaya", "Demir", "Şahin", "Çelik", "Öztürk", "Aydın", "Arslan", "Doğan", "Koç", "Kurt", "Polat"]

const ROLES := {
	"tezgahtar": {"name": "Tezgahtar", "desc": "Müşteriyi karşılar, işi kabul eder, raftan parça satar, kolileri açar.",
		"color": Color(0.78, 0.22, 0.16)},
	"teknisyen": {"name": "Teknisyen", "desc": "Masadaki bilgisayarı stoktaki parçalarla kendisi tamir eder.",
		"color": Color(0.14, 0.3, 0.55)},
}

## speed: iş hızı çarpanı, acc: doğruluk farkı, rep: her işte itibar katkısı, wage: maaş farkı
const TRAITS := {
	"titiz": {"name": "Titiz", "desc": "Yavaş ama neredeyse hiç hata yapmaz.", "speed": 0.8, "acc": 0.12, "rep": 0.0, "wage": 10},
	"hizli": {"name": "Hızlı ama dalgın", "desc": "Çabuk bitirir, arada bir parça yakar.", "speed": 1.35, "acc": -0.14, "rep": 0.0, "wage": 0},
	"guler": {"name": "Güler yüzlü", "desc": "Müşteriler onu sever: her işte itibar biraz artar.", "speed": 1.0, "acc": 0.0, "rep": 0.03, "wage": 5},
	"caylak": {"name": "Hevesli çaylak", "desc": "Ucuz ve istekli, tecrübesi az.", "speed": 1.0, "acc": -0.06, "rep": 0.0, "wage": -15},
	"eski": {"name": "Eski toprak", "desc": "Mahallenin eski ustası, işini bilir.", "speed": 0.95, "acc": 0.06, "rep": 0.01, "wage": 20},
	"uykucu": {"name": "Biraz uykucu", "desc": "Ağır çalışır ama maaşı düşük.", "speed": 0.75, "acc": 0.0, "rep": 0.0, "wage": -20},
}


static func make_candidate(id: int, role := "") -> Dictionary:
	if role == "":
		role = ROLES.keys().pick_random()
	var skill := randi_range(1, 5)
	var tr: String = TRAITS.keys().pick_random()
	var wage := 45 + skill * 20 + int(TRAITS[tr].wage) + randi_range(-2, 2) * 5
	if role == "tezgahtar":
		wage -= 10
	return {"id": id, "name": "%s %s" % [FIRST.pick_random(), LAST.pick_random()], "role": role,
		"skill": skill, "trait": tr, "wage": maxi(40, wage), "auto": true}


static func role_name(role: String) -> String:
	return ROLES.get(role, ROLES.tezgahtar).name


static func trait_info(tr: String) -> Dictionary:
	return TRAITS.get(tr, TRAITS.titiz)


## Teknisyen doğruluğu: beceri + huy (en fazla %97).
static func accuracy(d: Dictionary) -> float:
	return clampf(0.5 + 0.1 * int(d.skill) + float(trait_info(d.trait).acc), 0.3, 0.97)


## İş süresi çarpanı: yüksek beceri ve hızlı huy kısaltır.
static func time_mult(d: Dictionary) -> float:
	return (1.5 - 0.15 * int(d.skill)) / float(trait_info(d.trait).speed)
