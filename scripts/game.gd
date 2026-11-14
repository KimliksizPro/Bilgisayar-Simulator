extends Node
## Global oyun durumu (autoload): para, gün/saat, itibar, geliştirmeler, kayıt, HUD/ses referansları.

signal money_changed(value: int)
signal rep_changed(value: float)
signal upgrade_bought(id: String)
signal day_started
signal day_ended(summary: Dictionary)
signal game_over(summary: Dictionary)
signal stock_changed
signal orders_changed

const SFX := preload("res://scripts/sfx.gd")
const PM := preload("res://scripts/part_models.gd")
const FADER := preload("res://scripts/fader.gd")
const MUSIC := preload("res://scripts/music.gd")
const UM := preload("res://scripts/used_market.gd")
# geliştirici bayrakları (her biri ayrı satırda: paralel dallarda çakışmasın)
const DEV_ARGS := [
	"--propshot",
	"--shot",
	"--uishot",
	"--perf",
	"--partshot",
	"--looptest",
	"--jobdisttest",
	"--jobdatatest",
	"--holdtest",
	"--holdshot",
	"--savetest",
]

# --- Ayarlanabilir sabitler ---
const OPEN_HOUR := 9.0
const CLOSE_HOUR := 19.0
const DAY_REAL_SECONDS := 360.0          # bir gün kaç gerçek saniye
const HOURS_PER_SEC := (CLOSE_HOUR - OPEN_HOUR) / DAY_REAL_SECONDS
const START_MONEY := 300
const BASE_RENT := 150                    # günlük kira
const RENT_STEP := 25                     # her kira seviyesinde artış
const RENT_RAISE_EVERY := 3               # kaç günde bir kira seviyesi artar
const START_REP := 3.0
const BANKRUPT_DAYS := 2                  # üst üste kaç gün eksi bakiye = iflas
const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2                   # kayıt şeması sürümü (eski kayıtlar _migrate ile çevrilir)

const UPGRADE_LIST := [
	{"id": "sign", "name": "Reklam Tabelası", "price": 400, "desc": "Müşteriler daha sık gelir."},
	{"id": "wholesale", "name": "Toptan Anlaşma", "price": 600, "desc": "ParçaNet'te tüm parçalar %15 indirimli."},
	{"id": "courier", "name": "Kurye Anlaşması", "price": 500, "desc": "Kargolar yarı sürede ve ücretsiz gelir."},
	{"id": "coffee", "name": "Kahve Makinesi", "price": 350, "desc": "Müşteri sabrı %50 artar."},
	{"id": "cert", "name": "Usta Sertifikası", "price": 800, "desc": "İş ücretleri %15 artar."},
]

var money := START_MONEY
var jobs_done := 0
var hud = null
var player = null
var sfx = null
var fader = null
var dev_mode := false         # dev araçları (--shot vb.) menüsüz doğrudan oyuna girer
var paused := false           # duraklatma menüsü açık
var ui_modal := false         # özet/yönetim paneli/duraklatma gibi tam ekran arayüz açık

var day := 1
var clock := OPEN_HOUR
var rep := START_REP
var upgrades := {}
var rent_level := 0
var debt_days := 0
var stats := {"total_income": 0, "total_jobs": 0}
# gün içi sayaçlar
var income_today := 0
var parts_today := 0
var jobs_today := 0
var rep_day_start := START_REP

# --- stok ve sipariş (ParçaNet) ---
## Satılan ürünler: [tür, seviye]. Stok anahtarı "tür:seviye".
const CATALOG := [["cpu", 1], ["ram", 1], ["ram", 2], ["gpu", 1], ["gpu", 2], ["psu", 1], ["ssd", 1],
	# --- laptop / telefon parçaları ---
	["lap_ram", 1], ["lap_ssd", 1], ["lap_bat", 1], ["lap_scr", 1], ["tel_bat", 1], ["tel_scr", 1], ["tel_port", 1],
]
const START_STOCK := {"cpu:1": 1, "ram:1": 2, "gpu:1": 1, "psu:1": 1, "ssd:1": 1,
	# --- laptop / telefon parçaları ---
	"lap_ram:1": 1, "lap_ssd:1": 1, "lap_bat:1": 1, "lap_scr:1": 1, "tel_bat:1": 1, "tel_scr:1": 1, "tel_port:1": 1,
}
const SHIP_STD_HOURS := 2.0
const SHIP_EXP_HOURS := 0.5
const SHIP_STD_FEE := 15
const SHIP_EXP_FEE := 45
const FREE_SHIP_OVER := 250       # standart kargo bu tutarın üstünde ücretsiz
const BULK_QTY := 5               # aynı üründen bu kadar alınca ek indirim
const BULK_DISCOUNT := 0.10
const RETAIL_MARKUP := 1.35       # tezgahtan parça satışında kâr marjı
var stock := {}
var orders: Array = []            # {id, items: {sku: adet}, eta: mutlak saat, express, cost, state}
var next_order_id := 1
var job_history: Array = []       # iş seçicinin son seçtikleri (tekrar cezası için, kayda girer)
var market := 1.0                 # günlük piyasa çarpanı (kur)
var market_prev := 1.0
var shipping_today := 0
var sales_today := 0

# --- Ekonomi derinliği: muadil parça, garanti, ikinci el, elektrik faturası ---
const CHEAP_FACTOR := 0.6         # muadil parça fiyatı (orijinalin %60'ı)
const WARRANTY_CHANCE := 0.35     # muadil parça takılı teslimde müşterinin garantiye dönme ihtimali
const UTIL_BASE := 15             # günlük elektrik sabit bedeli
const UTIL_PER_JOB := 3           # çalışılan iş başına ek
const UTIL_COFFEE := 8            # Kahve Makinesi ek tüketimi
const UTIL_SIGN := 5              # Reklam Tabelası (ışıklı) ek tüketimi
var stock_cheap := {}             # "tür:seviye" -> muadil adet (orijinal stoktan ayrı)
var stock_dud := {}               # "tür:seviye" -> orijinal stoğun içindeki gizli arızalı (ikinci el) adet
var take_was_dud := false         # son take_stock() arızalı parça verdi mi
var warranty_list: Array = []     # bekleyen garanti dönüşleri: {due, name, type, tier}
var warranty_chance := WARRANTY_CHANCE
var used_listings: Array = []     # bugünün ikinci el ilanları
var _loaded_used_sold: Array = [] # kayıttan gelen satılmış ilan id'leri (günlük üretimde bir kez uygulanır)
var utility_today := 0

var started := false          # oyuncu Yeni Oyun / Devam Et seçti mi
var phase := "menu"           # menu / day / summary / over
var running := false          # HUD ayarlar: fare yakalı ve oyun akıyor
var save_path := SAVE_PATH
var _loaded_from_backup := false  # son okuma ana dosya yerine yedekten mi yapıldı


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var args := OS.get_cmdline_user_args()
	for a in DEV_ARGS:
		if a in args:
			dev_mode = true
	sfx = SFX.new()
	add_child(sfx)
	fader = FADER.new()
	add_child(fader)
	if DisplayServer.get_name() != "headless":
		add_child(MUSIC.new())
	if not dev_mode:
		fader.rect.modulate.a = 1.0
		fader.fade(0.0, 0.9)


func _process(delta: float) -> void:
	if phase == "day" and running and clock < CLOSE_HOUR:
		clock = minf(CLOSE_HOUR, clock + delta * HOURS_PER_SEC)


func is_closed() -> bool:
	return clock >= CLOSE_HOUR


func clock_text() -> String:
	var h := int(clock)
	var m := int((clock - h) * 60.0)
	return "%02d:%02d" % [h, m]


func rent() -> int:
	return BASE_RENT + RENT_STEP * rent_level


# --- Para ---
func add_money(amount: int, count_income := true) -> void:
	money += amount
	if amount > 0 and count_income:
		income_today += amount
		stats.total_income = int(stats.total_income) + amount
	money_changed.emit(money)


func spend(amount: int, category := "parts") -> bool:
	if money < amount:
		return false
	money -= amount
	if category == "parts":
		parts_today += amount
	elif category == "shipping":
		shipping_today += amount
	money_changed.emit(money)
	return true


func msg(text: String, color := Color.WHITE) -> void:
	if hud:
		hud.show_message(text, color)


# --- Geliştirmelerin etkileri ---
func has_upgrade(id: String) -> bool:
	return upgrades.has(id)


## Bugünkü ParçaNet alış fiyatı: piyasa çarpanı ve toptan anlaşma uygulanır.
func price_of(type: String, tier: int, cheap := false) -> int:
	var p := PM.price(type, tier) * market
	if has_upgrade("wholesale"):
		p *= 0.85
	if cheap:
		p *= CHEAP_FACTOR
	return roundi(p)


## Müşteriye tezgahtan satış fiyatı (piyasa fiyatı + kâr).
func retail_price(type: String, tier: int) -> int:
	return roundi(PM.price(type, tier) * market * RETAIL_MARKUP / 5.0) * 5


# --- Stok ---
static func sku(type: String, tier: int) -> String:
	return "%s:%d" % [type, tier]


func stock_of(type: String, tier: int) -> int:
	return int(stock.get(sku(type, tier), 0))


func add_stock(type: String, tier: int, n := 1) -> void:
	var k := sku(type, tier)
	stock[k] = maxi(0, int(stock.get(k, 0)) + n)
	stock_changed.emit()


func take_stock(type: String, tier: int) -> bool:
	var n := stock_of(type, tier)
	if n <= 0:
		return false
	# ikinci elden gelen gizli arızalılar stoğun içinde rastgele çıkar
	var k := sku(type, tier)
	var d := int(stock_dud.get(k, 0))
	take_was_dud = d > 0 and randi_range(1, n) <= d
	if take_was_dud:
		stock_dud[k] = d - 1
	add_stock(type, tier, -1)
	stock_dud[k] = mini(int(stock_dud.get(k, 0)), stock_of(type, tier))
	return true


# --- Muadil (ucuz) parça stoğu ---
func stock_cheap_of(type: String, tier: int) -> int:
	return int(stock_cheap.get(sku(type, tier), 0))


func add_stock_cheap(type: String, tier: int, n := 1) -> void:
	var k := sku(type, tier)
	stock_cheap[k] = maxi(0, int(stock_cheap.get(k, 0)) + n)
	stock_changed.emit()


func take_stock_cheap(type: String, tier: int) -> bool:
	if stock_cheap_of(type, tier) <= 0:
		return false
	add_stock_cheap(type, tier, -1)
	return true


func stock_value() -> int:
	var v := 0
	for k in stock:
		var a: PackedStringArray = k.split(":")
		v += PM.price(a[0], int(a[1])) * int(stock[k])
	for k in stock_cheap:
		var a: PackedStringArray = k.split(":")
		v += roundi(PM.price(a[0], int(a[1])) * CHEAP_FACTOR) * int(stock_cheap[k])
	return v


func stock_count() -> int:
	var n := 0
	for k in stock:
		n += int(stock[k])
	for k in stock_cheap:
		n += int(stock_cheap[k])
	return n


# --- Sipariş ---
## Mutlak oyun saati (gün * 24 + saat): kargo varış zamanları bununla tutulur.
func now_abs() -> float:
	return day * 24.0 + clock


func ship_hours(express: bool) -> float:
	var h := SHIP_EXP_HOURS if express else SHIP_STD_HOURS
	return h * (0.5 if has_upgrade("courier") else 1.0)


func ship_fee(express: bool, subtotal: int) -> int:
	if has_upgrade("courier"):
		return 0
	if express:
		return SHIP_EXP_FEE
	return 0 if subtotal >= FREE_SHIP_OVER else SHIP_STD_FEE


## Sepet tutarı (toplu alım indirimi dahil, kargo hariç).
func cart_subtotal(items: Dictionary) -> int:
	var t := 0
	for k in items:
		var a: PackedStringArray = k.split(":")
		var q := int(items[k])
		var line := price_of(a[0], int(a[1]), a.size() > 2) * q  # "tür:seviye:c" = muadil
		if q >= BULK_QTY:
			line = roundi(line * (1.0 - BULK_DISCOUNT))
		t += line
	return t


## Siparişi öde ve yola çıkar. Varış kapanıştan sonraysa ertesi sabah gelir.
func place_order(items: Dictionary, express: bool) -> bool:
	var clean := {}
	for k in items:
		if int(items[k]) > 0:
			clean[k] = int(items[k])
	if clean.is_empty():
		return false
	var sub := cart_subtotal(clean)
	var fee := ship_fee(express, sub)
	if money < sub + fee:
		sfx.error()
		msg("Paran yetmiyor! (%d TL lazım)" % (sub + fee), Color(1, 0.5, 0.4))
		return false
	spend(sub, "parts")
	if fee > 0:
		spend(fee, "shipping")
	var eta := now_abs() + ship_hours(express)
	orders.append({"id": next_order_id, "items": clean, "eta": eta, "express": express, "cost": sub + fee, "state": "transit"})
	next_order_id += 1
	sfx.coin()
	msg("Sipariş verildi (%d TL). Tahmini varış: %s" % [sub + fee, abs_time_text(eta)], Color(0.6, 0.9, 1.0))
	orders_changed.emit()
	return true


func abs_time_text(t: float) -> String:
	var d := int(t / 24.0)
	var h := t - d * 24.0
	if h >= CLOSE_HOUR:
		return "yarın 09:30"
	var hh := int(h)
	var mm := int((h - hh) * 60.0)
	var s := "%02d:%02d" % [hh, mm]
	return s if d == day else "Gün %d %s" % [d, s]


## Varış zamanı gelmiş, henüz kurye getirmemiş siparişler.
func due_orders() -> Array:
	var now := now_abs()
	return orders.filter(func(o): return o.state == "transit" and float(o.eta) <= now)


## Kargo kutusu açıldı: parçalar stoğa girer.
func receive_order(id: int) -> Dictionary:
	for i in orders.size():
		if int(orders[i].id) == id:
			var o: Dictionary = orders[i]
			orders.remove_at(i)
			for k in o.items:
				var a: PackedStringArray = k.split(":")
				if a.size() > 2:
					add_stock_cheap(a[0], int(a[1]), int(o.items[k]))
				else:
					add_stock(a[0], int(a[1]), int(o.items[k]))
			orders_changed.emit()
			return o
	return {}


static func items_text(items: Dictionary) -> String:
	var parts := []
	for k in items:
		var a: PackedStringArray = k.split(":")
		parts.append("%d x %s%s" % [int(items[k]), PM.display_name(a[0], int(a[1])), " (muadil)" if a.size() > 2 else ""])
	return ", ".join(parts)


## Her sabah piyasa kuru biraz oynar (0.8 - 1.3 arası rastgele yürüyüş).
func _roll_market() -> void:
	market_prev = market
	market = clampf(market + randf_range(-0.08, 0.1), 0.8, 1.3)
	market = snappedf(market, 0.01)




## Günlük elektrik faturası: sabit + çalışılan iş başına + Kahve Makinesi / Tabela tüketimi.
func utility_bill() -> int:
	var b := UTIL_BASE + UTIL_PER_JOB * jobs_today
	if has_upgrade("coffee"):
		b += UTIL_COFFEE
	if has_upgrade("sign"):
		b += UTIL_SIGN
	return b


func _reset_economy() -> void:
	stock_cheap = {}
	stock_dud = {}
	warranty_list = []
	used_listings = []
	_loaded_used_sold = []


func _save_economy(d: Dictionary) -> void:
	d.stock_cheap = stock_cheap
	d.stock_dud = stock_dud
	d.warranty = warranty_list
	# satılmış ikinci el ilanları (gün sonu özeti kaydıysa yarın taze ilan gelir)
	var sold_ids := []
	if phase != "summary":
		for l in used_listings:
			if l.sold:
				sold_ids.append(int(l.id))
	d.used_sold = sold_ids


func _load_economy(d: Dictionary) -> void:
	_reset_economy()
	used_listings = UM.generate(day)  # ilanlar günün tohumundan yeniden üretilir
	for id in d.get("used_sold", []):
		_loaded_used_sold.append(int(id))
	for k in d.get("stock_cheap", {}):
		stock_cheap[str(k)] = int(d.stock_cheap[k])
	for k in d.get("stock_dud", {}):
		stock_dud[str(k)] = int(d.stock_dud[k])
	for w in d.get("warranty", []):
		warranty_list.append({"due": int(w.get("due", day)), "name": str(w.get("name", "Müşteri")),
			"type": str(w.get("type", "ram")), "tier": int(w.get("tier", 1))})


func patience_mult() -> float:
	return 1.5 if has_upgrade("coffee") else 1.0


## İş ücreti: itibar (±%20) ve sertifika (+%15) uygulanır.
func job_pay(base: int) -> int:
	var m := 0.8 + 0.4 * rep / 5.0
	if has_upgrade("cert"):
		m *= 1.15
	return roundi(base * m)


## Müşteri bekleme süresi çarpanı: küçük = daha sık gelir.
func arrival_mult() -> float:
	var m := lerpf(1.6, 0.7, rep / 5.0)
	if has_upgrade("sign"):
		m *= 0.7
	return m


func buy_upgrade(id: String) -> bool:
	if has_upgrade(id):
		return false
	for u in UPGRADE_LIST:
		if u.id == id:
			if not spend(int(u.price), "upgrade"):
				sfx.error()
				return false
			upgrades[id] = true
			sfx.coin()
			upgrade_bought.emit(id)
			msg("%s satın alındı!" % u.name, Color(0.6, 0.9, 1.0))
			return true
	return false


func change_rep(delta: float) -> void:
	rep = clampf(rep + delta, 0.0, 5.0)
	rep_changed.emit(rep)


## Ödeme sesi: yazar kasa "cıngırt".
func cash_sound() -> void:
	sfx.coin()
	await get_tree().create_timer(0.2).timeout
	sfx.play(sfx.tone(2093.0, 0.12, 0.15))


# --- Gün akışı ---
func new_game() -> void:
	money = START_MONEY
	jobs_done = 0
	day = 1
	rep = START_REP
	upgrades = {}
	rent_level = 0
	debt_days = 0
	stats = {"total_income": 0, "total_jobs": 0, "total_sales": 0}
	stock = START_STOCK.duplicate()
	_reset_economy()
	orders = []
	next_order_id = 1
	job_history = []
	market = 1.0
	market_prev = 1.0
	_reset_staff()  # PERSONEL
	started = true
	money_changed.emit(money)
	rep_changed.emit(rep)
	upgrade_bought.emit("")
	stock_changed.emit()
	orders_changed.emit()
	start_day()


func start_day() -> void:
	clock = OPEN_HOUR
	income_today = 0
	parts_today = 0
	shipping_today = 0
	sales_today = 0
	jobs_today = 0
	_make_listings()
	rep_day_start = rep
	phase = "day"
	day_started.emit()


## Günün ilanlarını üretir; kayıttan gelen satılmış ilanlar işaretlenir (yalnızca bir kez).
func _make_listings() -> void:
	used_listings = UM.generate(day)
	for l in used_listings:
		if int(l.id) in _loaded_used_sold:
			l.sold = true
	_loaded_used_sold = []


func next_day() -> void:
	day += 1
	_roll_market()
	_loaded_used_sold = []  # yeni güne eski kayıttaki satış işaretleri taşınmaz
	start_day()


func end_day() -> void:
	if phase != "day":
		return
	var r := rent()
	var bill := utility_bill()
	utility_today = bill
	money -= r + bill
	var wg := _pay_wages()  # PERSONEL: maaşlar
	money_changed.emit(money)
	var s := {"day": day, "income": income_today, "parts": parts_today, "rent": r, "shipping": shipping_today, "utility": bill,
		"warranty_pending": warranty_list.size(),
		"sales": sales_today, "net": income_today - parts_today - shipping_today - r - bill, "rep_delta": rep - rep_day_start, "rep": rep,
		"money": money, "jobs": jobs_today, "warn": false}
	s.wages = wg; s.net -= wg  # PERSONEL
	debt_days = debt_days + 1 if money < 0 else 0
	if day % RENT_RAISE_EVERY == 0:
		rent_level += 1
	s.next_rent = rent()
	if debt_days >= BANKRUPT_DAYS:
		phase = "over"
		_delete_save_files()  # iflasta yedek de silinir: geri getirilemesin
		game_over.emit(s)
		return
	s.warn = debt_days > 0
	phase = "summary"
	save_game()
	day_ended.emit(s)


# --- Kayıt ---
## Geçerli bir kayıt (ana dosya ya da yedek) var mı.
func has_save() -> bool:
	return not _parse_save_file(save_path).is_empty() or not _parse_save_file(_bak_path()).is_empty()


func _bak_path() -> String:
	return save_path + ".bak"


func _tmp_path() -> String:
	return save_path + ".tmp"


## Tek bir kayıt dosyasını okur ve JSON sözlüğü olarak döndürür; bozuk/yoksa {}.
func _parse_save_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


## Kaydı okur; ana dosya bozuksa yedeğe bakar. Yedekten okunduysa _loaded_from_backup true olur.
func _read_save() -> Dictionary:
	_loaded_from_backup = false
	var d := _parse_save_file(save_path)
	if d.is_empty():
		d = _parse_save_file(_bak_path())
		if not d.is_empty():
			_loaded_from_backup = true
			push_warning("Kayıt dosyası bozuk, yedekten okunuyor: " + _bak_path())
	return d


## Kayıt dosyalarını (ana, yedek, geçici) siler.
func _delete_save_files() -> void:
	for p in [save_path, _bak_path(), _tmp_path()]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## Eski sürüm kayıtlarını güncel şemaya adım adım çevirir.
## Yeni sürüm eklenince her dönüşüm "if from_version < N:" bloğu olarak buraya yazılır.
func _migrate(d: Dictionary, from_version: int) -> Dictionary:
	if from_version < 2:
		pass  # v1 -> v2: şema aynı, yalnızca "version" alanı eklendi; dönüşüm gerekmez
	# if from_version < 3:
	# 	d["yeni_alan"] = varsayılan
	return d


## Kayıt sözlüğünü geçici dosyaya yazar, doğrular, eski kaydı yedekler ve yerine koyar.
## Başarısızlıkta eski kayıt korunur. Dönüş: başarılıysa true.
func _write_save_atomic(d: Dictionary) -> bool:
	var tmp := _tmp_path()
	var bak := _bak_path()
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Kayıt yazılamadı, geçici dosya açılamadı: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(d))
	var werr := f.get_error()
	f.close()
	if werr != OK or _parse_save_file(tmp).is_empty():
		push_error("Kayıt yazılamadı, geçici dosya bozuk (hata: %s)" % error_string(werr))
		DirAccess.remove_absolute(tmp)
		return false
	var had_old := FileAccess.file_exists(save_path)
	if had_old:
		# yalnızca geçerli ana dosya yedeklenir; bozuk dosya iyi yedeğin üstüne yazılmasın
		if not _parse_save_file(save_path).is_empty():
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			var cerr := DirAccess.copy_absolute(save_path, bak)
			if cerr != OK:
				push_error("Kayıt yedeklenemedi: %s" % error_string(cerr))
				DirAccess.remove_absolute(tmp)
				return false
		# Windows'ta üstüne yeniden adlandırma başarısız olabildiği için önce ana dosya silinir
		var derr := DirAccess.remove_absolute(save_path)
		if derr != OK:
			push_error("Eski kayıt silinemedi: %s" % error_string(derr))
			DirAccess.remove_absolute(tmp)
			return false
	var rerr := DirAccess.rename_absolute(tmp, save_path)
	if rerr != OK:
		push_error("Kayıt dosyası yerine konamadı: %s" % error_string(rerr))
		if had_old and FileAccess.file_exists(bak):
			# eski kaydı geri getir: oyuncu kaydını kaybetmesin
			DirAccess.copy_absolute(bak, save_path)
		DirAccess.remove_absolute(tmp)
		return false
	return true


## Kayıt dosyasının özeti (ana menüde göstermek için); kayıt yoksa boş sözlük.
func peek_save() -> Dictionary:
	var parsed := _read_save()
	if parsed.is_empty():
		return {}
	return {"day": int(parsed.get("day", 1)), "money": int(parsed.get("money", 0)), "rep": float(parsed.get("rep", 3.0))}


## Ana menüye dön: kaydet, kararıp sahneyi yeniden yükle.
func return_to_menu() -> void:
	if started and (phase == "day" or phase == "summary"):
		save_game()
	await fader.fade(1.0, 0.45)
	started = false
	phase = "menu"
	paused = false
	ui_modal = false
	running = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func save_game() -> void:
	var d := {"version": SAVE_VERSION, "day": day, "clock": clock, "money": money, "rep": rep, "upgrades": upgrades.keys(),
		"jobs_done": jobs_done, "rent_level": rent_level, "debt_days": debt_days, "stats": stats,
		"stock": stock, "market": market, "market_prev": market_prev, "next_order_id": next_order_id, "job_history": job_history}
	# kapıdaki/yoldaki kargolar kayıtta "yolda" sayılır; kurye yeniden getirir
	var ol := []
	for o in orders:
		ol.append({"id": o.id, "items": o.items, "eta": o.eta, "express": o.express, "cost": o.cost})
	d.orders = ol
	_save_economy(d)
	# gün sonu özeti açıkken kayıt ertesi günden devam etsin
	if phase == "summary":
		d.day = day + 1
		d.clock = OPEN_HOUR
		d.market = market
	_save_staff(d)  # PERSONEL
	if not _write_save_atomic(d):
		msg("Kayıt yazılamadı! Disk dolu ya da yazma izni yok olabilir.", Color(1, 0.5, 0.4))


func load_game() -> bool:
	if not has_save():
		return false
	var d := _read_save()
	if d.is_empty():
		return false
	var ver := int(d.get("version", 1))  # sürüm alanı yoksa ilk sürüm kabul edilir
	if ver > SAVE_VERSION:
		push_warning("Kayıt sürümü (%d) bu oyunun sürümünden (%d) yeni; kayıt yüklenmedi." % [ver, SAVE_VERSION])
		return false
	if _loaded_from_backup:
		msg("Kayıt dosyası bozuktu, yedekten yüklendi.", Color(1, 0.8, 0.4))
	d = _migrate(d, ver)
	day = int(d.get("day", 1))
	money = int(d.get("money", START_MONEY))
	rep = clampf(float(d.get("rep", START_REP)), 0.0, 5.0)
	jobs_done = int(d.get("jobs_done", 0))
	rent_level = int(d.get("rent_level", 0))
	debt_days = int(d.get("debt_days", 0))
	upgrades = {}
	for id in d.get("upgrades", []):
		upgrades[str(id)] = true
	var st = d.get("stats", {})
	stats = {"total_income": int(st.get("total_income", 0)), "total_jobs": int(st.get("total_jobs", 0)),
		"total_sales": int(st.get("total_sales", 0))}
	stock = {}
	var sd = d.get("stock", START_STOCK)
	for k in sd:
		stock[str(k)] = int(sd[k])
	market = float(d.get("market", 1.0))
	market_prev = float(d.get("market_prev", market))
	next_order_id = int(d.get("next_order_id", 1))
	job_history = []
	for h in d.get("job_history", []):
		job_history.append(str(h))
	_load_economy(d)
	orders = []
	for o in d.get("orders", []):
		var items := {}
		for k in o.get("items", {}):
			items[str(k)] = int(o.items[k])
		orders.append({"id": int(o.id), "items": items, "eta": float(o.eta), "express": bool(o.get("express", false)),
			"cost": int(o.get("cost", 0)), "state": "transit"})
	_load_staff(d)  # PERSONEL
	return true


func continue_game() -> bool:
	if not load_game():
		return false
	started = true
	money_changed.emit(money)
	rep_changed.emit(rep)
	upgrade_bought.emit("")
	stock_changed.emit()
	orders_changed.emit()
	start_day()  # kayıtlı gün 09:00'dan taze başlar
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and started and (phase == "day" or phase == "summary"):
		save_game()


# ================================================================ PERSONEL (çalışan alma)
signal staff_changed

const STAFF_DATA := preload("res://scripts/staff_data.gd")
const STAFF_MAX := 2              # en fazla kaç çalışan
const STAFF_CANDIDATES := 3       # iş ilanına her sabah gelen aday sayısı

var staff: Array = []             # işe alınanlar: {id, name, role, skill, trait, wage, auto}
var staff_candidates: Array = []
var staff_next_id := 1
var staff_mgr = null              # sahnedeki personel yöneticisi (scripts/staff.gd)


func staff_wages() -> int:
	var w := 0
	for e in staff:
		w += int(e.wage)
	return w


## Gün sonu: maaşlar kasadan düşer.
func _pay_wages() -> int:
	var w := staff_wages()
	money -= w
	return w


## Her sabah iş ilanına yeni adaylar gelir (ilk ikisi: bir tezgahtar, bir teknisyen).
func roll_staff_candidates() -> void:
	staff_candidates = []
	for i in STAFF_CANDIDATES:
		var role := "tezgahtar" if i == 0 else ("teknisyen" if i == 1 else "")
		staff_candidates.append(STAFF_DATA.make_candidate(staff_next_id, role))
		staff_next_id += 1
	staff_changed.emit()


func hire_staff(id: int) -> bool:
	if staff.size() >= STAFF_MAX:
		sfx.error()
		msg("En fazla %d çalışan alabilirsin." % STAFF_MAX, Color(1, 0.5, 0.4))
		return false
	for i in staff_candidates.size():
		if int(staff_candidates[i].id) == id:
			var c: Dictionary = staff_candidates[i]
			staff_candidates.remove_at(i)
			staff.append(c)
			sfx.coin()
			msg("%s işe başladı (%s, günlük %d TL)." % [c.name, STAFF_DATA.role_name(c.role), int(c.wage)], Color(0.6, 0.9, 1.0))
			staff_changed.emit()
			return true
	return false


func fire_staff(id: int) -> void:
	for i in staff.size():
		if int(staff[i].id) == id:
			var c: Dictionary = staff[i]
			staff.remove_at(i)
			msg("%s ile yollarınız ayrıldı." % c.name, Color(1, 0.8, 0.5))
			staff_changed.emit()
			return


func staff_by_id(id: int) -> Dictionary:
	for e in staff:
		if int(e.id) == id:
			return e
	return {}


func _reset_staff() -> void:
	staff = []
	staff_next_id = 1
	roll_staff_candidates()


func _save_staff(d: Dictionary) -> void:
	d.staff = staff
	d.staff_next_id = staff_next_id


func _load_staff(d: Dictionary) -> void:
	staff = []
	for e in d.get("staff", []):
		staff.append({"id": int(e.get("id", 0)), "name": str(e.get("name", "Çırak")), "role": str(e.get("role", "tezgahtar")),
			"skill": clampi(int(e.get("skill", 1)), 1, 5), "trait": str(e.get("trait", "titiz")),
			"wage": int(e.get("wage", 60)), "auto": bool(e.get("auto", true))})
	staff_next_id = int(d.get("staff_next_id", staff.size() + 1))
	roll_staff_candidates()
