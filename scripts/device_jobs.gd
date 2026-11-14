extends RefCounted
## Laptop ve telefon işleri: müşteri cümleleri, iş üretimi, cihazı masaya koyma.
## job_manager.gd bu dosyayı birkaç satırla çağırır (iş üretimi, kabul, teslim kontrolü).

const LAPTOP := preload("res://scripts/laptop_device.gd")
const PHONE := preload("res://scripts/phone_device.gd")
const PM := preload("res://scripts/part_models.gd")

const CHANCE := 0.3   # tamir işlerinin yaklaşık bu kadarı laptop/telefon olur

## yuva -> parça türü
const LAPTOP_PARTS := {"ram": "lap_ram", "ssd": "lap_ssd", "bat": "lap_bat", "scr": "lap_scr"}
const PHONE_PARTS := {"bat": "tel_bat", "port": "tel_port", "scr": "tel_scr"}

const LAPTOP_LINES := {
	"bat": ["Usta laptop şarj tutmuyor, prizden çekince anında kapanıyor.",
		"Laptopun altı kabardı abi, masada topaç gibi dönüyor. Normal mi bu?",
		"Kablosuz bir dakika duramıyor usta, laptop değil masaüstü oldu."],
	"ssd": ["Açınca 'boot device' diye bir şey yazıyor, Windows gelmiyor. Tezim içinde usta!",
		"Laptop masadan düştü, o günden beri siyah ekranda İngilizce bir yazı çıkıyor."],
	"ram": ["Laptop durup durup donuyor, sonra mavi ekran verip kendini kapatıyor.",
		"Excel'i açınca mavi ekran veriyor usta, patron beni yiyecek.",
		"Ekranda üzgün surat çıkıyor abi, ':(' diye. Bilgisayar bana küsmüş."],
	"scr": ["Kedi klavyenin üstüne yatmış, kapağı kapatınca ekran paramparça oldu.",
		"Çantada ezilmiş usta, ekran kırıldı, renkli renkli çizgiler var.",
		"Oğlan oyunda kaybedince yumruğu ekrana vurmuş... Ne diyeyim."],
}
const PHONE_LINES := {
	"bat": ["Telefon %100'den bir saatte sıfıra iniyor usta, arkası da kabardı sanki.",
		"Şarjım yarım gün gitmiyor, bir de ekran yerinden kalkmış gibi duruyor.",
		"Telefon açılıyor, pil simgesi kıpkırmızı olup hemen kapanıyor."],
	"port": ["Şarj kablosunu takınca şarj olmuyor, ancak kabloyu eğip bükünce bir an oluyor.",
		"Telefon çayın içine düştü, o günden beri şarj olmuyor usta.",
		"Üç tane kablo değiştirdim, hiçbiri şarj etmiyor. Kablo değil herhalde?"],
	"scr": ["Telefon cebimden düştü, ekran örümcek ağı gibi oldu.",
		"Torun yere atmış, ekran çatlak, dokunmatik de çalışmıyor.",
		"Selfie çekerken elimden kaydı usta, ekran gitti, selfie de gitti."],
}
const VAGUE := {
	"laptop": ["Laptop bozuldu usta, bi bakıver.", "Üniversite ödevim içinde, ne olur kurtar şu laptopu.",
		"Bu laptop bir tuhaf usta, ne olduğunu sen anla."],
	"phone": ["Telefon bozuldu usta, WhatsApp gruplarından kopmuşum.", "Annemin telefonu, bir tuhaf oldu, bi bakar mısın?",
		"Telefon bozuk usta, bugün lazım."],
}


static func is_device(job: Dictionary) -> bool:
	return job.get("device", "") != ""


## Laptop veya telefon tamir işi üretir (j: içinde "name" olan iş sözlüğü).
static func make(j: Dictionary, device := "") -> Dictionary:
	var dev := device if device != "" else ("laptop" if randf() < 0.55 else "phone")
	var table: Dictionary = LAPTOP_PARTS if dev == "laptop" else PHONE_PARTS
	var lines: Dictionary = LAPTOP_LINES if dev == "laptop" else PHONE_LINES
	var broken: String = table.keys().pick_random()
	j.kind = dev
	j.device = dev
	j.broken = broken
	j.intro = lines[broken].pick_random() if randf() < 0.7 else VAGUE[dev].pick_random()
	j.goal = ("Laptopu çalıştır, ekranındaki hatayı oku. Arızalı parçayı bul ve değiştir." if dev == "laptop"
		else "Telefonu aç, belirtiye bak. Arızalı parçayı bul ve değiştir.")
	var labor := randi_range(12, 20) * 10 if dev == "laptop" else randi_range(8, 14) * 10
	j.pay = PM.price(table[broken], 1) + labor
	var parts := []
	for slot in table:
		parts.append([slot, table[slot], 1, slot == broken])
	j.parts = parts
	return j


static func new_device(job: Dictionary):
	return LAPTOP.new() if job.device == "laptop" else PHONE.new()


## Masadaki yer: kasa için pc_spot aynen; laptop/telefon masaya düz, oyuncuya bakar.
static func spot(dev, pc_spot: Transform3D) -> Transform3D:
	if not dev.has_method("slot_open"):
		return pc_spot
	var o := pc_spot.origin
	return Transform3D(Basis.IDENTITY, Vector3(o.x, o.y - 0.012 + dev.LIFT, o.z + 0.04))


## İş kabul edildi: ipuçları ve bildirim.
static func on_accept(hud, job: Dictionary) -> void:
	if job.device == "laptop":
		Game.msg("Laptop masana kondu. Güç düğmesine bas, ekranındaki hatayı oku!", Color(0.6, 0.9, 1.0))
		hud.tip("dev_laptop", "Laptop: güç düğmesi klavyenin sağ üstünde. Alt kapağı açmak için klavyeye bakıp E'ye bas; laptop ters döner. Kırık ekran, laptop düzken sökülür.")
	else:
		Game.msg("Telefon masana kondu. Yan tuştan aç, belirtiye bak!", Color(0.6, 0.9, 1.0))
		hud.tip("dev_phone", "Telefon: güç tuşu sağ kenarda. Açmak için telefonun üstüne bakıp E'ye bas; ekran kitap gibi yana kalkar.")


static func deliver_hint(job: Dictionary) -> String:
	match job.get("device", ""):
		"laptop": return "Laptopu teslim et  [E]"
		"phone": return "Telefonu teslim et  [E]"
	return "Bilgisayarı teslim et  [E]"
