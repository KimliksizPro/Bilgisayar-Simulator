extends Node
## Geliştirici testi: `godot --headless -- --savetest` kayıt sistemini sınar
## (round-trip, sürüm, yedekten kurtarma, yeni sürüm reddi, iflasta silme). Gerçek kayda dokunmaz.

const TEST_PATH := "user://test_save.json"
var fails: Array = []


func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	Game.save_path = TEST_PATH
	_wipe()
	Game.new_game()
	Game.phase = "day"
	# (a) yazma -> okuma: para, gün, stok korunur; ikinci yazma yedek oluşturur
	Game.money = 777
	Game.day = 4
	Game.stock[Game.sku("ram", 2)] = 3
	Game.save_game()
	Game.save_game()
	_check(FileAccess.file_exists(TEST_PATH + ".bak"), "(a) yedek oluşmadı")
	_check(not FileAccess.file_exists(TEST_PATH + ".tmp"), "(a) geçici dosya kaldı")
	_check(_read_dict(TEST_PATH).get("version") == Game.SAVE_VERSION, "(a) sürüm yazılmadı")
	_reset_memory()
	_check(Game.load_game() and Game.money == 777 and Game.day == 4 and Game.stock_of("ram", 2) == 3, "(a) round-trip")
	print("OK (a) round-trip")
	# (b) ana dosya bozuk -> yedekten yüklenir
	_write_text(TEST_PATH, "{garbage")
	_check(Game.has_save(), "(b) bozuk ana dosyada has_save yanlış")
	_reset_memory()
	_check(Game.load_game() and Game.money == 777, "(b) yedekten yükleme")
	_check(Game.peek_save().get("money") == 777, "(b) peek yedeği görmedi")
	print("OK (b) bozuk ana dosya, yedekten yükleme")
	# (b2) bozuk ana dosyanın üstüne yazılınca iyi yedek korunur
	Game.money = 5
	Game.save_game()
	_check(Game.load_game() and Game.money == 5, "(b2) yeni kayıt okunamadı")
	_check(int(_read_dict(TEST_PATH + ".bak").get("money", 0)) == 777, "(b2) iyi yedek bozuk dosyayla ezildi")
	print("OK (b2) bozuk dosya üstüne yazma, yedek korundu")
	# (c) sürüm alanı olmayan (v1) kayıt yüklenir
	Game.money = 555
	Game.save_game()
	var v1 := _read_dict(TEST_PATH)
	v1.erase("version")
	_write_text(TEST_PATH, JSON.stringify(v1))
	_reset_memory()
	_check(Game.load_game() and Game.money == 555, "(c) sürümsüz kayıt yüklenmedi")
	print("OK (c) v1 kayıt")
	# (d) sürümü daha yeni olan kayıt reddedilir
	var v999 := v1.duplicate()
	v999["version"] = 999
	v999["money"] = 111
	_write_text(TEST_PATH, JSON.stringify(v999))
	_reset_memory()
	_check(not Game.load_game(), "(d) yeni sürüm kayıt yüklendi")
	_check(Game.money == 1, "(d) reddedilen kayıt durumu değiştirdi")
	print("OK (d) yeni sürüm reddi")
	# (e) v3 -> v4 göçü: eski "tip:tier" stok, sipariş ("ram:1:c"), garanti ve v3 dizi iş parçaları
	_test_v3_to_v4_migration()
	print("OK (e) v3 -> v4 göçü")
	# (f) iflas: kayıt, yedek ve geçici dosya silinir
	Game.phase = "day"
	Game.save_game()
	Game.save_game()
	Game.money = -500
	Game.debt_days = Game.BANKRUPT_DAYS - 1
	Game.phase = "day"
	Game.end_day()
	_check(Game.phase == "over", "(f) iflas olmadı")
	_check(not FileAccess.file_exists(TEST_PATH) and not FileAccess.file_exists(TEST_PATH + ".bak") and not FileAccess.file_exists(TEST_PATH + ".tmp"), "(f) iflasta dosyalar silinmedi")
	_check(not Game.has_save(), "(f) iflas sonrası kayıt var")
	print("OK (f) iflasta silme")
	_wipe()
	if fails.is_empty():
		print("SAVETEST OK")
		get_tree().quit()
	else:
		print("SAVETEST BAŞARISIZ: ", fails)
		get_tree().quit(1)


func _test_v3_to_v4_migration() -> void:
	# 1) _migrate() ile v3 dizi iş parçalarının v4 sözlüklere ve SKU'lara dönüşümü
	var v3_job := {
		"ticket": 105,
		"name": "Ahmet Abi",
		"kind": "repair",
		"device": "pc",
		"pay": 250,
		"due_abs": 84.0,
		"status": "waiting_bench",
		"location": "rack:0",
		"parts": [
			["psu", "psu", 1, false],
			["cpu", "cpu", 1, false, true],
			["ram1", "ram", 1, true, true, true],
			["gpu", "gpu", 2, false],
			["ssd", "ssd", 1, false],
		],
		"state": {
			"parts": [
				["psu", "psu", 1, false],
				["cpu", "cpu", 1, false, false],
				["ram1", "ram", 1, true, true, true],
				["gpu", "gpu", 2, false],
				["ssd", "ssd", 1, false],
			],
			"dust": 0.2,
			"socket_paste": false,
		},
	}
	var mig_in := {
		"version": 3,
		"day": 5,
		"money": 910,
		"stock": {"cpu:1": 2, "ram:2": 3, "lap_bat:1": 1},
		"stock_cheap": {"ram:1": 4},
		"stock_dud": {"gpu:1": 1},
		"orders": [{"id": 7, "items": {"ram:1:c": 2, "gpu:2": 1}, "eta": 130.0, "express": false, "cost": 298}],
		"warranty": [{"due": 8, "name": "Ayşe Teyze", "type": "ram", "tier": 2}],
		"jobs": [v3_job.duplicate(true)],
	}
	var mig: Dictionary = Game._migrate(mig_in.duplicate(true), 3)
	_check(int(mig.stock.get("cpu_am4_6c", 0)) == 2 and int(mig.stock.get("ram_ddr4_16g_rgb", 0)) == 3 and int(mig.stock.get("lap_bat_56wh", 0)) == 1, "(e) stok SKU göçü")
	_check(int(mig.stock_cheap.get("ram_ddr4_8g", 0)) == 4, "(e) muadil stok SKU göçü")
	_check(int(mig.stock_dud.get("gpu_entry_4g", 0)) == 1, "(e) arızalı stok SKU göçü")
	_check(int(mig.orders[0].items.get("ram_ddr4_8g:c", 0)) == 2 and int(mig.orders[0].items.get("gpu_gamer_12g", 0)) == 1, "(e) sipariş kalemi göçü")
	_check(str(mig.warranty[0].get("sku", "")) == "ram_ddr4_16g_rgb", "(e) garanti SKU göçü")
	var mj: Dictionary = mig.jobs[0]
	_check(str(mj.get("case_id", "")) == "atx_mid", "(e) iş case_id varsayılanı")
	var slots_seen := {}
	for p in mj.parts:
		_check(p is Dictionary, "(e) iş parçası sözlük olmalı")
		if p is Dictionary:
			slots_seen[str(p.get("slot", ""))] = p
	_check(slots_seen.has("cpu") and str(slots_seen.cpu.sku) == "cpu_am4_6c", "(e) cpu SKU göçü")
	_check(slots_seen.has("ram1") and str(slots_seen.ram1.sku) == "ram_ddr4_8g" and bool(slots_seen.ram1.broken) and bool(slots_seen.ram1.cheap), "(e) ram1 alan göçü")
	_check(slots_seen.has("gpu") and str(slots_seen.gpu.sku) == "gpu_gamer_12g", "(e) gpu:2 SKU göçü")
	_check(slots_seen.has("mobo") and slots_seen.has("cooler") and slots_seen.has("fan1") and slots_seen.has("cmos"), "(e) eksik PC varsayılanları eklenmedi")
	var st_cpu := {}
	for p in mj.state.parts:
		if p is Dictionary and str(p.get("slot", "")) == "cpu":
			st_cpu = p
	_check(not st_cpu.is_empty() and not bool(st_cpu.get("paste_ok", true)) and int(st_cpu.get("health", 0)) == 100, "(e) state.parts paste_ok/health göçü")

	# 2) Disk üzerinden tam v3 -> v4 yükleme + kaydetme + tekrar yükleme gidiş-dönüşü
	var v3_disk := mig_in.duplicate(true)
	# job_store.gd v4 sözlükleri destekliyorsa işleri de tam disk gidiş-dönüşüne dahil et
	var supports_v4_jobs := Game.JOB_STORE.normalize({"ticket": 101, "parts": []}).has("case_id")
	if not supports_v4_jobs:
		v3_disk["jobs"] = []
	_write_text(TEST_PATH, JSON.stringify(v3_disk))
	_reset_memory()
	_check(Game.load_game(), "(e) v3 kayıt yüklenemedi")
	_check(Game.money == 910 and Game.day == 5, "(e) v3 para/gün")
	_check(Game.stock_of_sku("cpu_am4_6c") == 2 and Game.stock_of_sku("ram_ddr4_16g_rgb") == 3 and Game.stock_of_sku("lap_bat_56wh") == 1, "(e) yüklenen stok SKU")
	_check(Game.stock_cheap_of_sku("ram_ddr4_8g") == 4, "(e) yüklenen muadil stok")
	_check(int(Game.stock_dud.get("gpu_entry_4g", 0)) == 1, "(e) yüklenen arızalı stok")
	_check(Game.orders.size() == 1 and int(Game.orders[0].items.get("ram_ddr4_8g:c", 0)) == 2 and int(Game.orders[0].items.get("gpu_gamer_12g", 0)) == 1, "(e) yüklenen sipariş")
	_check(Game.warranty_list.size() == 1 and str(Game.warranty_list[0].get("sku", "")) == "ram_ddr4_16g_rgb", "(e) yüklenen garanti")
	# v4 olarak kaydet ve tekrar yükle
	Game.phase = "day"
	Game.save_game()
	var saved_v4 := _read_dict(TEST_PATH)
	_check(int(saved_v4.get("version", 0)) == Game.SAVE_VERSION, "(e) v4 sürümü yazılmadı")
	_check(saved_v4.stock.has("cpu_am4_6c") and not saved_v4.stock.has("cpu:1"), "(e) eski anahtar v4 kayıtta kalmamalı")
	_reset_memory()
	_check(Game.load_game() and Game.stock_of_sku("cpu_am4_6c") == 2 and Game.stock_cheap_of_sku("ram_ddr4_8g") == 4, "(e) v4 round-trip")
	_check(Game.orders.size() == 1 and int(Game.orders[0].items.get("ram_ddr4_8g:c", 0)) == 2, "(e) v4 sipariş round-trip")
	_check(Game.warranty_list.size() == 1 and str(Game.warranty_list[0].get("sku", "")) == "ram_ddr4_16g_rgb", "(e) v4 garanti round-trip")
	if supports_v4_jobs:
		_check(Game.jobs_active.size() == 1 and str(Game.jobs_active[0].get("case_id", "")) == "atx_mid", "(e) v4 iş round-trip")


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("BAŞARISIZ: ", what)


func _reset_memory() -> void:
	Game.money = 1
	Game.day = 1
	Game.stock = {}


func _read_dict(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _wipe() -> void:
	for p in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
