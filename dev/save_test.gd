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
	# (e) iflas: kayıt, yedek ve geçici dosya silinir
	Game.phase = "day"
	Game.save_game()
	Game.save_game()
	Game.money = -500
	Game.debt_days = Game.BANKRUPT_DAYS - 1
	Game.phase = "day"
	Game.end_day()
	_check(Game.phase == "over", "(e) iflas olmadı")
	_check(not FileAccess.file_exists(TEST_PATH) and not FileAccess.file_exists(TEST_PATH + ".bak") and not FileAccess.file_exists(TEST_PATH + ".tmp"), "(e) iflasta dosyalar silinmedi")
	_check(not Game.has_save(), "(e) iflas sonrası kayıt var")
	print("OK (e) iflasta silme")
	_wipe()
	if fails.is_empty():
		print("SAVETEST OK")
		get_tree().quit()
	else:
		print("SAVETEST BAŞARISIZ: ", fails)
		get_tree().quit(1)


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
