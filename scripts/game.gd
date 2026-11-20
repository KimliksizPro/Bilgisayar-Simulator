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
signal bench_changed(device)  # tezgâhtaki cihaz değişti (null = boş)
signal jobs_changed           # aktif iş listesi değişti (yeni iş, durum, teslim)
signal jobs_loaded            # kayıttan iş listesi yüklendi (cihazlar yeniden kurulur)

const SFX := preload("res://scripts/sfx.gd")
const PM := preload("res://scripts/part_models.gd")
const FADER := preload("res://scripts/fader.gd")
const MUSIC := preload("res://scripts/music.gd")
const UM := preload("res://scripts/used_market.gd")
const JOB_STORE := preload("res://scripts/job_store.gd")
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
	"--datatest",
	"--benchtest",
	"--benchshot",
	"--multijobtest",
	"--jobshot",
	"--compattest",
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
const SAVE_VERSION := 4                   # kayıt şeması sürümü (eski kayıtlar _migrate ile çevrilir)

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
## Tezgâhta üzerinde çalışılan cihaz (PC kasası / laptop / telefon) ya da null.
## Tezgâh modu ve çoklu iş sistemi arasındaki ortak sözleşme: cihazı tezgâha koyan set_bench_device çağırır.
var bench_device = null
var bench_active := false     # tezgâh modu (yörünge kamera) açık: fare serbest ama zaman akar
## Çoklu iş: müşterinin bırakıp gittiği, henüz teslim edilmemiş işler (bkz. job_manager.gd, job_store.gd).
## Kayıt: {ticket, name, kind, device, parts, pay, due_abs, express, status, location, state, ...}
var jobs_active: Array = []
var next_ticket := 101            # sıradaki fiş numarası
var job_slot_bonus := 0           # ileride geliştirmelerle artacak ek raf gözü
var job_mgr = null                # sahnedeki iş yöneticisi (scripts/job_manager.gd)
const BASE_JOB_SLOTS := 3         # başlangıçta aynı anda en fazla bu kadar açık iş
const MAX_JOB_SLOTS := 6          # rafın göz sayısı (üst sınır)
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
## Satılan ürünler: [tür, seviye]. Stok anahtarı "tür:seviye" (= parçanın SKU'su).
## Veri data/parts.json'dan gelir (DB.parts); eski adlar uyumluluk için korunur.
var CATALOG: Array:
	get: return DB.parts.catalog_pairs()
var START_STOCK: Dictionary:
	get: return DB.parts.start_stock()
## Raftaki ürünlerin dünya konumu: {sku: Vector3}. Raf kurulurken main.gd doldurur; personel buradan okur.
var shelf_pos := {}
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


## Aynı anda tutulabilecek açık iş sayısı (rafın açık göz sayısı).
func max_active_jobs() -> int:
	return mini(BASE_JOB_SLOTS + job_slot_bonus, MAX_JOB_SLOTS)


func job_by_ticket(ticket: int) -> Dictionary:
	for r in jobs_active:
		if int(r.ticket) == ticket:
			return r
	return {}


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


## Bugünkü ParçaNet alış fiyatı (SKU): piyasa çarpanı ve toptan anlaşma uygulanır.
func price_of_sku(sku_id: String, cheap := false) -> int:
	var p := PM.price_sku(sku_id) * market
	if has_upgrade("wholesale"):
		p *= 0.85
	if cheap:
		p *= CHEAP_FACTOR
	return roundi(p)


func price_of(type: String, tier: int, cheap := false) -> int:
	return price_of_sku(sku(type, tier), cheap)


## Müşteriye tezgahtan satış fiyatı (SKU, piyasa fiyatı + kâr).
func retail_price_sku(sku_id: String) -> int:
	return roundi(PM.price_sku(sku_id) * market * RETAIL_MARKUP / 5.0) * 5


func retail_price(type: String, tier: int) -> int:
	return retail_price_sku(sku(type, tier))


# --- Stok ---
## (tür, seviye) -> kanonik SKU kimliği.
static func sku(type: String, tier: int) -> String:
	var id: String = DB.parts.id_for(type, tier)
	return id if not id.is_empty() else "%s:%d" % [type, tier]


## Sepet/sipariş anahtarını çözer: "<sku>" veya "<sku>:c" (eski "tür:seviye[:c]" biçimi dahil).
static func parse_cart_key(k: String) -> Dictionary:
	var cheap := k.ends_with(":c")
	var base := k.substr(0, k.length() - 2) if cheap else k
	return {"sku": DB.parts.resolve_id(base), "cheap": cheap}


func stock_of_sku(sku_id: String) -> int:
	return int(stock.get(DB.parts.resolve_id(sku_id), 0))


func add_stock_sku(sku_id: String, n := 1) -> void:
	var k: String = DB.parts.resolve_id(sku_id)
	stock[k] = maxi(0, int(stock.get(k, 0)) + n)
	stock_changed.emit()


func take_stock_sku(sku_id: String) -> bool:
	var k: String = DB.parts.resolve_id(sku_id)
	var n := int(stock.get(k, 0))
	if n <= 0:
		return false
	# ikinci elden gelen gizli arızalılar stoğun içinde rastgele çıkar
	var d := int(stock_dud.get(k, 0))
	take_was_dud = d > 0 and randi_range(1, n) <= d
	if take_was_dud:
		stock_dud[k] = d - 1
	add_stock_sku(k, -1)
	stock_dud[k] = mini(int(stock_dud.get(k, 0)), int(stock.get(k, 0)))
	return true


func stock_of(type: String, tier: int) -> int:
	return stock_of_sku(sku(type, tier))


func add_stock(type: String, tier: int, n := 1) -> void:
	add_stock_sku(sku(type, tier), n)


func take_stock(type: String, tier: int) -> bool:
	return take_stock_sku(sku(type, tier))


# --- Muadil (ucuz) parça stoğu ---
func stock_cheap_of_sku(sku_id: String) -> int:
	return int(stock_cheap.get(DB.parts.resolve_id(sku_id), 0))


func add_stock_cheap_sku(sku_id: String, n := 1) -> void:
	var k: String = DB.parts.resolve_id(sku_id)
	stock_cheap[k] = maxi(0, int(stock_cheap.get(k, 0)) + n)
	stock_changed.emit()


func take_stock_cheap_sku(sku_id: String) -> bool:
	var k: String = DB.parts.resolve_id(sku_id)
	if int(stock_cheap.get(k, 0)) <= 0:
		return false
	add_stock_cheap_sku(k, -1)
	return true


func stock_cheap_of(type: String, tier: int) -> int:
	return stock_cheap_of_sku(sku(type, tier))


func add_stock_cheap(type: String, tier: int, n := 1) -> void:
	add_stock_cheap_sku(sku(type, tier), n)


func take_stock_cheap(type: String, tier: int) -> bool:
	return take_stock_cheap_sku(sku(type, tier))


func stock_value() -> int:
	var v := 0
	for k in stock:
		v += PM.price_sku(str(k)) * int(stock[k])
	for k in stock_cheap:
		v += roundi(PM.price_sku(str(k)) * CHEAP_FACTOR) * int(stock_cheap[k])
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
		var pk := parse_cart_key(str(k))
		var q := int(items[k])
		var line := price_of_sku(pk.sku, pk.cheap) * q  # "<sku>:c" = muadil
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
				var pk := parse_cart_key(str(k))
				if pk.cheap:
					add_stock_cheap_sku(pk.sku, int(o.items[k]))
				else:
					add_stock_sku(pk.sku, int(o.items[k]))
			orders_changed.emit()
			return o
	return {}


static func items_text(items: Dictionary) -> String:
	var parts := []
	for k in items:
		var pk := parse_cart_key(str(k))
		parts.append("%d x %s%s" % [int(items[k]), PM.display_name_sku(pk.sku), " (muadil)" if pk.cheap else ""])
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
		var wt := str(w.get("type", "ram"))
		var wtier := int(w.get("tier", 1))
		var wsku := str(w.get("sku", DB.parts.id_for(wt, wtier)))
		warranty_list.append({"due": int(w.get("due", day)), "name": str(w.get("name", "Müşteri")),
			"type": wt, "tier": wtier, "sku": wsku})


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
	jobs_active = []
	next_ticket = 101
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
		"warranty_pending": warranty_list.size(), "open_jobs": jobs_active.size(),
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
	if from_version < 3:
		# v2 -> v3: çoklu iş. Eski kayıtlarda bırakılmış iş yoktu: boş liste, fiş numarası baştan.
		d["jobs"] = []
		d["next_ticket"] = 101
	if from_version < 4:
		# v3 -> v4: stok/sipariş/garanti/iş anahtarları "tür:seviye" -> kanonik SKU kimliğine çevrilir
		for field in ["stock", "stock_cheap", "stock_dud"]:
			if d.has(field) and d[field] is Dictionary:
				var mapped := {}
				for k in d[field]:
					var nk: String = DB.parts.resolve_id(str(k))
					mapped[nk] = int(mapped.get(nk, 0)) + int(d[field][k])
				d[field] = mapped
		if d.has("orders") and d["orders"] is Array:
			for o in d["orders"]:
				if o is Dictionary and o.has("items") and o["items"] is Dictionary:
					var mapped_items := {}
					for k in o["items"]:
						var pk := parse_cart_key(str(k))
						var nk: String = str(pk.sku) + (":c" if pk.cheap else "")
						mapped_items[nk] = int(mapped_items.get(nk, 0)) + int(o["items"][k])
					o["items"] = mapped_items
		if d.has("warranty") and d["warranty"] is Array:
			for w in d["warranty"]:
				if w is Dictionary and not w.has("sku"):
					w["sku"] = DB.parts.id_for(str(w.get("type", "ram")), int(w.get("tier", 1)))
		if d.has("jobs") and d["jobs"] is Array:
			for j in d["jobs"]:
				if j is Dictionary:
					_migrate_job_v4(j)
	return d


func _migrate_job_v4(j: Dictionary) -> void:
	var is_pc := str(j.get("device", "pc")) == "pc" or str(j.get("device", "")) == ""
	if is_pc and not j.has("case_id"):
		j["case_id"] = "atx_mid"
	var inject := is_pc and str(j.get("kind", "")) != "build"
	if j.has("parts") and j["parts"] is Array:
		j["parts"] = _migrate_parts_v4(j["parts"], inject)
	var st = j.get("state", null)
	if st is Dictionary and st.has("parts") and st["parts"] is Array:
		st["parts"] = _migrate_parts_v4(st["parts"], inject)


func _migrate_parts_v4(parts: Array, inject_pc_defaults: bool) -> Array:
	var out := []
	var seen := {}
	for p in parts:
		if p is Dictionary:
			var np: Dictionary = p.duplicate()
			if np.has("sku"):
				np["sku"] = DB.parts.resolve_id(str(np["sku"]))
			if not np.has("health"):
				np["health"] = 100
			seen[str(np.get("slot", ""))] = true
			out.append(np)
		elif p is Array and p.size() >= 4:
			var sl := str(p[0])
			if sl == "dust":
				continue
			var t := str(p[1])
			var tier := int(p[2])
			var sku_id: String = DB.parts.id_for(t, tier)
			if sku_id.is_empty():
				sku_id = DB.parts.resolve_id("%s:%d" % [t, tier])
			seen[sl] = true
			out.append({
				"slot": sl,
				"sku": sku_id,
				"broken": bool(p[3]),
				"paste_ok": bool(p[4]) if p.size() > 4 else true,
				"cheap": bool(p[5]) if p.size() > 5 else false,
				"health": 100,
			})
	if inject_pc_defaults and not out.is_empty():
		for pair in [["mobo", "mobo_am4_matx"], ["cooler", "cooler_stock"], ["fan1", "fan_120_std"], ["cmos", "cmos_cr2032"]]:
			if not seen.has(pair[0]):
				out.append({"slot": pair[0], "sku": pair[1], "broken": false, "paste_ok": true, "cheap": false, "health": 100})
	return out


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
	_save_jobs(d)
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
	_load_jobs(d)
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


# ================================================================ ÇOKLU İŞ (kayıt)
## Açık işleri kayda yazar. Cihazların parça durumu önce düğümlerden okunur (job_manager.sync_states).
func _save_jobs(d: Dictionary) -> void:
	if job_mgr:
		job_mgr.sync_states()
	d.jobs = jobs_active
	d.next_ticket = next_ticket


func _load_jobs(d: Dictionary) -> void:
	jobs_active = []
	for r in d.get("jobs", []):
		if r is Dictionary:
			jobs_active.append(JOB_STORE.normalize(r))
	next_ticket = int(d.get("next_ticket", 101))
	for r in jobs_active:
		next_ticket = maxi(next_ticket, int(r.ticket) + 1)
	jobs_loaded.emit()
	jobs_changed.emit()


## Oyuncu şu an bir cihaz (kasa/laptop/telefon) taşıyor mu? Taşırken parça/alet alınamaz.
func is_carrying() -> bool:
	return job_mgr != null and job_mgr.carry.active()


func set_bench_device(d) -> void:
	if bench_device == d:
		return
	bench_device = d
	bench_changed.emit(d)
