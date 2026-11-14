extends Node
## Global oyun durumu (autoload): para, gün/saat, itibar, geliştirmeler, kayıt, HUD/ses referansları.

signal money_changed(value: int)
signal rep_changed(value: float)
signal upgrade_bought(id: String)
signal day_started
signal day_ended(summary: Dictionary)
signal game_over(summary: Dictionary)

const SFX := preload("res://scripts/sfx.gd")
const PM := preload("res://scripts/part_models.gd")
const FADER := preload("res://scripts/fader.gd")
const MUSIC := preload("res://scripts/music.gd")
const DEV_ARGS := ["--propshot", "--shot", "--uishot", "--perf", "--partshot", "--looptest"]

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

const UPGRADE_LIST := [
	{"id": "sign", "name": "Reklam Tabelası", "price": 400, "desc": "Müşteriler daha sık gelir."},
	{"id": "wholesale", "name": "Toptan Anlaşma", "price": 600, "desc": "Raftaki tüm parçalar %15 indirimli."},
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

var started := false          # oyuncu Yeni Oyun / Devam Et seçti mi
var phase := "menu"           # menu / day / summary / over
var running := false          # HUD ayarlar: fare yakalı ve oyun akıyor
var save_path := SAVE_PATH


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
	money_changed.emit(money)
	return true


func msg(text: String, color := Color.WHITE) -> void:
	if hud:
		hud.show_message(text, color)


# --- Geliştirmelerin etkileri ---
func has_upgrade(id: String) -> bool:
	return upgrades.has(id)


func price_of(type: String, tier: int) -> int:
	var p := PM.price(type, tier)
	if has_upgrade("wholesale"):
		p = roundi(p * 0.85)
	return p


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
	stats = {"total_income": 0, "total_jobs": 0}
	started = true
	money_changed.emit(money)
	rep_changed.emit(rep)
	upgrade_bought.emit("")
	start_day()


func start_day() -> void:
	clock = OPEN_HOUR
	income_today = 0
	parts_today = 0
	jobs_today = 0
	rep_day_start = rep
	phase = "day"
	day_started.emit()


func next_day() -> void:
	day += 1
	start_day()


func end_day() -> void:
	if phase != "day":
		return
	var r := rent()
	money -= r
	money_changed.emit(money)
	var s := {"day": day, "income": income_today, "parts": parts_today, "rent": r,
		"net": income_today - parts_today - r, "rep_delta": rep - rep_day_start, "rep": rep,
		"money": money, "jobs": jobs_today, "warn": false}
	debt_days = debt_days + 1 if money < 0 else 0
	if day % RENT_RAISE_EVERY == 0:
		rent_level += 1
	s.next_rent = rent()
	if debt_days >= BANKRUPT_DAYS:
		phase = "over"
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(save_path)
		game_over.emit(s)
		return
	s.warn = debt_days > 0
	phase = "summary"
	save_game()
	day_ended.emit(s)


# --- Kayıt ---
func has_save() -> bool:
	return FileAccess.file_exists(save_path)


## Kayıt dosyasının özeti (ana menüde göstermek için); kayıt yoksa boş sözlük.
func peek_save() -> Dictionary:
	if not has_save():
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(parsed) != TYPE_DICTIONARY:
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
	var d := {"day": day, "clock": clock, "money": money, "rep": rep, "upgrades": upgrades.keys(),
		"jobs_done": jobs_done, "rent_level": rent_level, "debt_days": debt_days, "stats": stats}
	# gün sonu özeti açıkken kayıt ertesi günden devam etsin
	if phase == "summary":
		d.day = day + 1
		d.clock = OPEN_HOUR
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func load_game() -> bool:
	if not has_save():
		return false
	var txt := FileAccess.get_file_as_string(save_path)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
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
	stats = {"total_income": int(st.get("total_income", 0)), "total_jobs": int(st.get("total_jobs", 0))}
	return true


func continue_game() -> bool:
	if not load_game():
		return false
	started = true
	money_changed.emit(money)
	rep_changed.emit(rep)
	upgrade_bought.emit("")
	start_day()  # kayıtlı gün 09:00'dan taze başlar
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and started and (phase == "day" or phase == "summary"):
		save_game()
