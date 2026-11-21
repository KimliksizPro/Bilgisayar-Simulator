extends RefCounted
## Arıza ve iş şablonu tanımları (data/faults.json, data/jobs.json).

const FaultDef := preload("res://scripts/data/fault_def.gd")
const JobTemplate := preload("res://scripts/data/job_template.gd")

const FAULTS_PATH := "res://data/faults.json"
const JOBS_PATH := "res://data/jobs.json"

var _faults := {}      # id -> FaultDef
var _fault_order: Array = []
var _templates := {}   # id -> JobTemplate
var _template_order: Array = []
var _texts := {}       # havuz adı -> Array
var _base_parts: Array = []
var errors: Array = []  # doğrulama hataları (test okur)


func load_all() -> void:
	_faults.clear()
	_fault_order.clear()
	_templates.clear()
	_template_order.clear()
	errors.clear()
	var fd: Variant = DB.read_json(FAULTS_PATH, {})
	for d in fd.get("faults", []):
		var f = FaultDef.from_dict(d)
		if f.id == "" or _faults.has(f.id):
			_err("Arıza kimliği boş ya da yinelenmiş: '%s'" % f.id)
			continue
		_faults[f.id] = f
		_fault_order.append(f)
	var jd: Variant = DB.read_json(JOBS_PATH, {})
	_texts = jd.get("text", {})
	_base_parts = jd.get("base_parts", [])
	for d in jd.get("templates", []):
		var t = JobTemplate.from_dict(d)
		if t.id == "" or _templates.has(t.id):
			_err("İş şablonu kimliği boş ya da yinelenmiş: '%s'" % t.id)
			continue
		if t.weight < 0:
			_err("İş '%s': ağırlık negatif" % t.id)
		if t.fault != "" and not _faults.has(t.fault):
			_err("İş '%s' bilinmeyen arızaya bağlı: %s" % [t.id, t.fault])
		for fid in t.faults:
			if not _faults.has(str(fid)):
				_err("İş '%s' bilinmeyen çoklu arızaya bağlı: %s" % [t.id, str(fid)])
		if t.intro_pool != "" and not _texts.has(t.intro_pool):
			_err("İş '%s' bilinmeyen metin havuzu: %s" % [t.id, t.intro_pool])
		_templates[t.id] = t
		_template_order.append(t)


func _err(msg: String) -> void:
	errors.append(msg)
	push_error("JobDB: " + msg)


func fault(id: String):
	return _faults.get(id)


## Bir cihazın tüm arızaları (dosya sırasıyla).
func faults_for(device: String) -> Array:
	return _fault_order.filter(func(f): return f.device == device)


## Teşhis koduna uyan ilk arıza (aşırı ısınmada ilki; ayrım için fault(id) kullan).
func fault_by_code(code: String, device := "pc"):
	for f in _fault_order:
		if f.device == device and f.diag_code == code:
			return f
	return null


func template(id: String):
	return _templates.get(id)


func templates() -> Array:
	return _template_order


## Ortak metin havuzu (isimler, belirsiz anlatımlar...). Yoksa boş dizi.
func text(pool: String) -> Array:
	return _texts.get(pool, [])


## Standart tam bilgisayar parça listesi [yuva, tür, kademe].
func base_parts() -> Array:
	return _base_parts
