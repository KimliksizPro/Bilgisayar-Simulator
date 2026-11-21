extends RefCounted
## Arıza tanımı (data/faults.json). Yeni arıza = JSON'a bir kayıt.

var id := ""
var device := "pc"            # pc / laptop / phone
var part := ""                # bozulan parça türü ("psu", "lap_ram"...); aşırı ısınmada/kabloda/yazılımda boş olabilir
var diag_code := ""           # teşhis kodu (nopower, cpu, ram, gpu, ssd, overheat; laptop/telefonda yuva adı)
var kind := "broken"          # broken / overheat / incompat / cable / software / pin_bend / unseated / vram_fault / smart_fail / capacitor / mechanical / liquid
var cable := ""               # kablo arızasıysa kablo kimliği (atx_24, cpu_8, pcie_gpu, sata, front_panel)
var sw_flag := ""             # yazılım arızasıysa bayrak kimliği
var req_upgrade := ""         # bu arızayı içeren işin açılması için gereken geliştirme
var symptoms := {}            # belirti verisi: led, beep (süre listesi), screen, msg, msg_color
var customer_lines: Array = []  # müşterinin ilk anlatımı
var fail_lines: Array = []    # teslim reddedilince müşteri cümlesi
var hint := ""                # teslim reddedilince HUD ipucu
var difficulty := 1
var labor := Vector2i(100, 150)  # işçilik aralığı (TL, 10'ar 10'ar)
var min_day := 0
var min_rep := 0.0
# aşırı ısınma ayarları
var dust := Vector2(0.0, 0.0)
var dust_chance := 0.0
var paste_dry := false


static func from_dict(d: Dictionary):
	var f = new()
	f.id = str(d.get("id", ""))
	f.device = str(d.get("device", "pc"))
	f.part = str(d.get("part", ""))
	f.diag_code = str(d.get("diag_code", ""))
	f.kind = str(d.get("kind", "broken"))
	f.cable = str(d.get("cable", ""))
	f.sw_flag = str(d.get("sw_flag", ""))
	f.req_upgrade = str(d.get("req_upgrade", ""))
	f.symptoms = d.get("symptoms", {})
	f.customer_lines = d.get("customer_lines", [])
	f.fail_lines = d.get("fail_lines", [])
	f.hint = str(d.get("hint", ""))
	f.difficulty = int(d.get("difficulty", 1))
	var lb: Array = d.get("labor", [100, 150])
	f.labor = Vector2i(int(lb[0]), int(lb[1]))
	f.min_day = int(d.get("min_day", 0))
	f.min_rep = float(d.get("min_rep", 0.0))
	var du: Array = d.get("dust", [0.0, 0.0])
	f.dust = Vector2(float(du[0]), float(du[1]))
	f.dust_chance = float(d.get("dust_chance", 0.0))
	f.paste_dry = bool(d.get("paste_dry", false))
	return f


## İşçilik ücreti: aralıktan 10 TL basamaklı rastgele.
func roll_labor() -> int:
	return randi_range(labor.x / 10, labor.y / 10) * 10
