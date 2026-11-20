class_name PartDef
extends RefCounted
## Tek bir parça (SKU) tanımı: data/parts.json içindeki bir kayıt.

var id := ""             # SKU kimliği (snake_case, örn. "ram_ddr4_16g_rgb"); stok/kayıt anahtarı budur
var legacy_id := ""      # eski "tür:seviye" anahtarı (kayıt göçü ve geriye dönük uyumluluk için)
var category := ""       # parça türü: mobo, cpu, cooler, ram, gpu, psu, ssd, nvme, hdd, fan, cmos, lap_ram ...
var tier := 1            # eski (tür, seviye) araması için
var name := ""           # oyunda görünen Türkçe ad
var brand := ""          # kurgusal marka (boş olabilir)
var price := 0           # taban fiyat (TL)
var device := "pc"       # "pc" | "laptop" | "phone"
var model := {}          # prosedürel model: {"builder": ..., + oluşturucuya özel parametreler}
var specs := {}          # serbest teknik özellikler (gb, tdp, socket ...)
var compat := {}         # uyumluluk alanları (socket, ram_type, watts ...)
var shelf := false       # stok rafında/rafta görünsün mü
var start_stock := 0     # yeni oyundaki başlangıç stoğu
var catalog := false     # ParçaNet'te satılsın mı
var hold := {}           # isteğe bağlı elde tutuş ezmesi: {"euler": Vector3, "offset": Vector3}


static func from_dict(d: Dictionary) -> PartDef:
	var p := PartDef.new()
	p.id = str(d.get("id", ""))
	p.legacy_id = str(d.get("legacy_id", ""))
	p.category = str(d.get("category", ""))
	p.tier = int(d.get("tier", 1))
	p.name = str(d.get("name", ""))
	p.brand = str(d.get("brand", ""))
	p.price = int(d.get("price", 0))
	p.device = str(d.get("device", "pc"))
	p.model = d.get("model", {})
	p.specs = d.get("specs", {})
	p.compat = d.get("compat", {})
	p.shelf = bool(d.get("shelf", false))
	p.start_stock = int(d.get("start_stock", 0))
	p.catalog = bool(d.get("catalog", false))
	var h = d.get("hold", {})
	if typeof(h) == TYPE_DICTIONARY and h.has("euler"):
		p.hold = {"euler": vec3(h.euler), "offset": vec3(h.get("offset", [0, 0, 0]))}
	return p


## [x, y, z] dizisini Vector3'e çevirir.
static func vec3(a) -> Vector3:
	if typeof(a) == TYPE_ARRAY and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
