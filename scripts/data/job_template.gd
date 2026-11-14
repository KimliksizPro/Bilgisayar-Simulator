extends RefCounted
## İş şablonu (data/jobs.json). Yeni iş = JSON'a bir kayıt; kod `kind`a göre genel çalışır.

var id := ""
var kind := ""                # repair / overheat / upgrade / build / sale / device (üretim yolu)
var job_kind := ""            # iş sözlüğündeki "kind" (HUD/personel buna bakar)
var family := ""              # tekrar cezası için aile
var weight := 0
var min_money := 0
var min_day := 0
var min_rep := 0.0
var fault := ""               # repair/overheat: FaultDef kimliği
var device := ""              # device: laptop / phone
var intro := ""               # sabit müşteri cümlesi
var intro_pool := ""          # ya da "text" havuzu (belirsiz anlatım / satış cümlesi)
var goal := ""
var specific_chance := 1.0    # arızaya özgü cümle şansı (yoksa intro_pool'dan)
var ram2_chance := 0.0        # repair: ikinci RAM takılı olma şansı
var pay_part: Array = []      # [tür, kademe]: ücrete eklenen parça bedeli
var pay_count := 1
var pay_extra := 0
var with_base_parts := false  # upgrade: tam çalışan standart bilgisayar
var want := ""                # sale: "tür:kademe"
var target := {}              # upgrade: teslim koşulu (part/min_tier ya da ram_gb) + fail cümlesi
var hours := 0.0              # 0 = varsayılan süre


static func from_dict(d: Dictionary):
	var t = new()
	t.id = str(d.get("id", ""))
	t.kind = str(d.get("kind", ""))
	t.job_kind = str(d.get("job_kind", t.kind))
	t.family = str(d.get("family", ""))
	t.weight = int(d.get("weight", 0))
	t.min_money = int(d.get("min_money", 0))
	t.min_day = int(d.get("min_day", 0))
	t.min_rep = float(d.get("min_rep", 0.0))
	t.fault = str(d.get("fault", ""))
	t.device = str(d.get("device", ""))
	t.intro = str(d.get("intro", ""))
	t.intro_pool = str(d.get("intro_pool", ""))
	t.goal = str(d.get("goal", ""))
	t.specific_chance = float(d.get("specific_chance", 1.0))
	t.ram2_chance = float(d.get("ram2_chance", 0.0))
	t.pay_part = d.get("pay_part", [])
	t.pay_count = int(d.get("pay_count", 1))
	t.pay_extra = int(d.get("pay_extra", 0))
	t.with_base_parts = bool(d.get("with_base_parts", false))
	t.want = str(d.get("want", ""))
	t.target = d.get("target", {})
	t.hours = float(d.get("hours", 0.0))
	return t


## sale için istenen parça: ["ram", 2]
func want_key() -> Array:
	var p := want.split(":")
	return [p[0], int(p[1]) if p.size() > 1 else 1]
