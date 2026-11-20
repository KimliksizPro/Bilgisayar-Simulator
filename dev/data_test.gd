extends Node
## Geliştirici testi: `godot --headless -- --datatest` parça verisinin (data/parts.json) eski sabit
## tablolarla birebir aynı sonuç verdiğini denetler. Başarılıysa "DATATEST OK" yazar.

const PM := preload("res://scripts/part_models.gd")

# ESKİ sabit tablolar (part_models.gd / device_parts.gd / game.gd): [tür, seviye, ad, fiyat]
const OLD := [
	["cpu", 1, "İşlemci (6 Çekirdek)", 120], ["ram", 1, "RAM 8 GB", 40], ["ram", 2, "RAM 16 GB RGB", 80],
	["gpu", 1, "Ekran Kartı (Giriş)", 100], ["gpu", 2, "Ekran Kartı (Oyuncu RGB)", 250],
	["psu", 1, "Güç Kaynağı 550W", 60], ["ssd", 1, "SSD 512 GB", 50],
	["lap_ram", 1, "Laptop RAM 8 GB (SO-DIMM)", 45], ["lap_ssd", 1, "M.2 NVMe SSD 512 GB", 60],
	["lap_bat", 1, "Laptop Bataryası", 70], ["lap_scr", 1, "Laptop Ekranı 15.6\"", 110],
	["tel_bat", 1, "Telefon Bataryası", 30], ["tel_scr", 1, "Telefon Ekranı (OLED)", 90],
	["tel_port", 1, "Şarj Soketi (USB-C)", 15],
]
const OLD_CATALOG := [["cpu", 1], ["ram", 1], ["ram", 2], ["gpu", 1], ["gpu", 2], ["psu", 1], ["ssd", 1],
	["lap_ram", 1], ["lap_ssd", 1], ["lap_bat", 1], ["lap_scr", 1], ["tel_bat", 1], ["tel_scr", 1], ["tel_port", 1]]
const OLD_STOCK := {"cpu:1": 1, "ram:1": 2, "gpu:1": 1, "psu:1": 1, "ssd:1": 1,
	"lap_ram:1": 1, "lap_ssd:1": 1, "lap_bat:1": 1, "lap_scr:1": 1, "tel_bat:1": 1, "tel_scr:1": 1, "tel_port:1": 1}
# tür -> [çarpışma boyutu, merkez, tür adı]
const OLD_INFO := {
	"cpu": [Vector3(0.064, 0.09, 0.09), Vector3(0.032, 0, 0), "İşlemci"],
	"ram": [Vector3(0.037, 0.132, 0.008), Vector3(0.018, 0, 0), "RAM"],
	"gpu": [Vector3(0.11, 0.042, 0.245), Vector3(0.055, -0.016, 0), "Ekran Kartı"],
	"psu": [Vector3(0.15, 0.085, 0.15), Vector3.ZERO, "Güç Kaynağı"],
	"ssd": [Vector3(0.07, 0.008, 0.1), Vector3.ZERO, "SSD"],
	"lap_ram": [Vector3(0.068, 0.004, 0.03), Vector3.ZERO, "Laptop RAM"],
	"lap_ssd": [Vector3(0.08, 0.005, 0.022), Vector3.ZERO, "M.2 SSD"],
	"lap_bat": [Vector3(0.22, 0.008, 0.07), Vector3.ZERO, "Laptop Bataryası"],
	"lap_scr": [Vector3(0.31, 0.005, 0.19), Vector3.ZERO, "Laptop Ekranı"],
	"tel_bat": [Vector3(0.05, 0.004, 0.08), Vector3.ZERO, "Telefon Bataryası"],
	"tel_scr": [Vector3(0.072, 0.003, 0.152), Vector3.ZERO, "Telefon Ekranı"],
	"tel_port": [Vector3(0.05, 0.004, 0.014), Vector3.ZERO, "Şarj Soketi"],
}
const OLD_HOLD := {
	"gpu": [Vector3(10, -78, 0), Vector3(-0.02, -0.02, -0.09)],
	"psu": [Vector3(20, -40, 0), Vector3(0.0, -0.05, -0.04)],
	"cpu": [Vector3(25, -80, 0), Vector3(-0.02, 0.0, 0.05)],
	"ram": [Vector3(15, -60, -20), Vector3(0.0, 0.0, 0.07)],
	"ssd": [Vector3(40, -30, 0), Vector3(0.0, 0.0, 0.05)],
	"lap_scr": [Vector3(50, -25, 0), Vector3(-0.03, -0.03, -0.06)],
	"lap_bat": [Vector3(45, -30, 0), Vector3(-0.02, -0.02, -0.03)],
}
const OLD_DEFAULT_HOLD := [Vector3(15, -35, 0), Vector3.ZERO]
# yuvalarda kullanılan türler (pc_case / laptop_device / phone_device)
const SLOT_TYPES := ["cpu", "ram", "gpu", "psu", "ssd", "lap_ram", "lap_ssd", "lap_bat", "lap_scr", "tel_bat", "tel_scr", "tel_port"]


func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	var db = DB.parts
	assert(db.all().size() >= 35, "parça sayısı yetersiz: %d" % db.all().size())
	assert(db.cases().size() >= 3, "kasa form faktörü eksik")
	for cid in ["atx_mid", "matx_mini", "itx_compact"]:
		assert(not db.case_def(cid).is_empty(), "kasa tanımı yok: " + cid)
	for o in OLD:
		var key := "%s:%d" % [o[0], o[1]]
		var sku_id: String = db.id_for(o[0], o[1])
		assert(not sku_id.is_empty() and db.resolve_id(key) == sku_id, "id_for/resolve_id: " + key)
		var d: PartDef = db.get_def(key)
		assert(d != null and d.id == sku_id and d.legacy_id == key, "tanım yok: " + key)
		assert(d.category == o[0] and d.tier == o[1], "kategori/seviye: " + key)
		assert(PM.display_name(o[0], o[1]) == o[2], "ad farklı: %s -> %s" % [key, PM.display_name(o[0], o[1])])
		assert(PM.price(o[0], o[1]) == o[3], "fiyat farklı: " + key)
		assert(d.model.has("builder"), "model.builder yok: " + key)
		var b: Dictionary = PM.build_sku(sku_id)
		assert(b.node.get_child_count() > 0, "model boş: " + sku_id)
		b.node.free()
	# tüm SKU'ların modeli kurulabiliyor ve ':' içermiyor
	for p in db.all():
		assert(not p.id.contains(":"), "SKU ':' içeremez: " + p.id)
		var b: Dictionary = PM.build_sku(p.id)
		assert(b.node.get_child_count() > 0, "model boş: " + p.id)
		b.node.free()
	# yuvalarda kullanılan her tür çözülüyor
	for t in SLOT_TYPES:
		assert(db.has_category(t), "tür yok: " + t)
		assert(db.def_for(t, 1) != null, "tier 1 tanım yok: " + t)
	# tür bilgisi
	for t in OLD_INFO:
		var i: Dictionary = PM.info(t)
		assert(i.size.is_equal_approx(OLD_INFO[t][0]), "boyut: " + t)
		assert(i.center.is_equal_approx(OLD_INFO[t][1]), "merkez: " + t)
		assert(PM.type_name(t) == OLD_INFO[t][2], "tür adı: " + t)
		var h: Array = OLD_HOLD.get(t, OLD_DEFAULT_HOLD)
		var hp: Array = db.hold_pose(t, 1)
		assert(hp[0].is_equal_approx(h[0]) and hp[1].is_equal_approx(h[1]), "elde tutuş: " + t)
	assert(PM.ram_gb(1) == 8 and PM.ram_gb(2) == 16, "ram_gb")
	# katalog ve başlangıç stoğu
	assert(db.catalog_ids().size() == db.catalog().size(), "catalog_ids")
	for it in OLD_CATALOG:
		assert(Game.CATALOG.has(it), "eski katalog öğesi eksik: " + str(it))
	for k in Game.START_STOCK:
		assert(db.has_def(k), "stok anahtarı çözülmüyor: " + k)
	# raf: tüm raf ürünlerinin konumu raftan geliyor
	assert(db.shelf_items(["pc"]).size() >= 7 and db.shelf_items(["laptop", "phone"]).size() == 7, "raf ürün sayısı")
	for d in db.shelf_items(["pc"]):
		assert(Game.shelf_pos.has(d.id), "raf konumu yok: " + d.id)
	for d in db.shelf_items(["laptop", "phone"]):
		assert(Game.shelf_pos.has(d.id), "mobil raf konumu yok: " + d.id)
	# eski biçimli kayıt yüklenebiliyor (v1/v3 "tür:seviye" -> v4 SKU göçü)
	var old_path := Game.save_path
	Game.save_path = "user://datatest_save.json"
	var f := FileAccess.open(Game.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"day": 3, "money": 500, "stock": {"cpu:1": 4, "ram:2": 2, "lap_bat:1": 3}}))
	f.close()
	assert(Game.load_game(), "eski kayıt yüklenemedi")
	assert(Game.stock_of("cpu", 1) == 4 and Game.stock_of("ram", 2) == 2 and Game.stock_of("lap_bat", 1) == 3, "stok yüklenmedi")
	assert(Game.stock_of_sku("cpu_am4_6c") == 4 and Game.stock_of_sku("ram_ddr4_16g_rgb") == 2 and Game.stock_of_sku("lap_bat_56wh") == 3, "SKU stok göçü")
	DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_path
	print("DATATEST OK")
	get_tree().quit()
