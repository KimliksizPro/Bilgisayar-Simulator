extends Node
## Oyun içeriği veritabanı (autoload: DB).
## Parçalar, arızalar ve iş şablonları res://data/*.json dosyalarından yüklenir;
## yeni içerik eklemek = JSON'a bir kayıt eklemek.
## Her alanın yükleyicisi kendi betiğindedir (scripts/data/), böylece birbirinden bağımsız gelişir.

const PartDB := preload("res://scripts/data/part_db.gd")
const JobDB := preload("res://scripts/data/job_db.gd")

var parts: PartDB = PartDB.new()   # parça tanımları (PartDef)
var jobs: JobDB = JobDB.new()      # arıza (FaultDef) ve iş şablonları (JobTemplate)


func _ready() -> void:
	reload()


## Tüm veriyi diskten yeniden yükler (geliştirme sırasında da çağrılabilir).
func reload() -> void:
	parts.load_all()
	jobs.load_all()


## Ortak JSON okuyucu: dosya yoksa ya da bozuksa hatayı yazar ve `fallback` döner.
static func read_json(path: String, fallback: Variant = {}) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("DB: veri dosyası yok: " + path)
		return fallback
	var txt := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(txt)
	if data == null:
		push_error("DB: JSON okunamadı: " + path)
		return fallback
	return data
