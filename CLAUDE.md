# CLAUDE.md — Bilgisayarcı Simülatör

Bu dosya yeni bir Claude oturumunun projeye hızla devam edebilmesi içindir (handoff).
**Önce bunu, sonra `ROADMAP.md`'yi oku.** Oyunun özellik/kontrol listesi `README.md`'de.

## Proje
- Birinci şahıs, stilize 3D **mahalle bilgisayarcısı / tamir dükkânı simülatörü**. Godot **4.4** (standart, .NET değil), GDScript.
- Modellerin hepsi **kodla üretiliyor** (`mesh_util.gd`, `part_models.gd`, `device_parts.gd`, `props.gd`); sahne dosyası neredeyse boş (`scenes/main.tscn` → `scripts/main.gd`).
- Varsayılan dal: **`main`**. Çalışma PR üzerinden birleştirilir.

## Kullanıcıyla çalışma şekli
- Kullanıcı Türkçe ve samimi konuşur ("knk"); cevaplar Türkçe, kısa ve net olsun.
- Kullanıcı Claude'un **orkestratör** olmasını istiyor: işleri parçala, **Haiku** ajanlarına (net, küçük, iyi tanımlı işler) ve **Sonnet** ajanlarına (mimari, render, büyük refactor) **detaylı promptlarla** ver, **paralel** çalıştır.
  - Paralel ajanlar `isolation: "worktree"` ile çalışsın, push etmesin; orkestratör dalları birleştirip **tüm testleri kendisi** çalıştırır, sonra push eder.
  - Ajanlara hangi dosyalara dokunmayacaklarını açıkça yaz (çakışmayı önler). Ortak sözleşme gerekiyorsa önce orkestratör küçük bir iskelet commit'ler (ör. `DB` autoload, `Game.bench_device`).
  - Ajan promptuna: Godot yolu, test komutları, commit mesajı formatı (Türkçe + attribution satırları), "rapor ne içersin" ekle.
- Büyük faz bitince: ROADMAP'te ✅ işaretle, ekran görüntüsü göster, kullanıcıdan oyun içi test iste, PR öner.

## Kod kuralları
- **Girinti TAB**. Kısa Türkçe yorumlar. Oyuncuya görünen tüm metin Türkçe.
- İçerik **veriden** gelir (Faz 1): yeni parça/arıza/iş eklerken önce `data/*.json`.
- Yeni `.gd` dosyaları için Godot'un ürettiği `.uid` dosyalarını da commit'le.
- `DEV_ARGS` (`scripts/game.gd`) **her bayrak ayrı satırda** — paralel dallarda çakışmasın diye.

## Mimari haritası
| Alan | Dosyalar |
| --- | --- |
| Autoload'lar | `Settings` (settings.gd), `DB` (db.gd), `Game` (game.gd: ekonomi, stok, sipariş, personel, kayıt, gün) |
| Veri | `data/parts.json` (PartDef), `data/faults.json` (FaultDef), `data/jobs.json` (JobTemplate + metin havuzları); yükleyiciler `scripts/data/` |
| İş akışı | `job_manager.gd` (müşteri kuyruğu, bırak/al, teslim), `job_store.gd` (iş kayıtları, teslim süreleri, cihaz durumunu kaydet/yükle), `job_rack.gd` (bekleyen işler rafı), `job_carry.gd` (cihaz taşıma), `job_director.gd` (ağırlıklı torba + tekrar cezası), `device_jobs.gd`, `warranty.gd` |
| Cihazlar | `pc_case.gd` (slotlar, teşhis `diagnose()`, bip/LED), `laptop_device.gd`, `phone_device.gd`, `device_base.gd`, `slot.gd`, `device_slot.gd` |
| Oyuncu | `player.gd` (hareket, elde tutma + viewmodel katmanı 20 / SubViewport), `part.gd`, `tool.gd` (macun, hava) |
| Tezgâh modu | `bench_mode.gd` (Tab; yörünge kamera, fareyle sök/tak, tepsi, yan panel). Sözleşme: `Game.bench_device`, `Game.bench_changed`, `Game.set_bench_device()` |
| UI | `hud.gd` (yazar kasa, tezgâh fişi, AÇIK İŞLER listesi), `office_panel.gd` (dükkân laptop'u: ParçaNet, kargo, geliştirmeler, ikinci el, personel), `ui_kit.gd`, `ui_theme.gd`, `menu.gd`, `pause_menu.gd`, `settings_panel.gd` |
| Diğer | `staff.gd`/`employee.gd`/`staff_data.gd` (personel), `delivery.gd` (kurye), `used_market.gd`, `sfx.gd`, `music.gd` |

Kayıt: `user://save.json`, `SAVE_VERSION = 3`, `_migrate()` ile eski kayıtlar yükseltilir; atomik yazma + `.bak` yedek.

## Test (zorunlu, her değişiklikten sonra)
Bulut ortamında Godot kurulu değil; indir (ağ izin veriyor):
```bash
mkdir -p /tmp/godot && cd /tmp/godot && curl -sSLo g.zip https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip && unzip -oq g.zip
```
`G=/tmp/godot/Godot_v4.4.1-stable_linux.x86_64`, proje kökünde:
```bash
timeout 300 $G --headless --path . --import
```
```bash
timeout 100 $G --headless --path . --quit-after 300 2>&1 | grep -E "SCRIPT ERROR|Parse Error"
```
```bash
for t in looptest flowtest jobdisttest jobdatatest holdtest savetest datatest multijobtest benchtest; do echo "== $t"; timeout 400 $G --headless --path . -- --$t 2>&1 | grep -E "SCRIPT ERROR|GEÇTİ|OK|FAIL|HATA" | tail -1; done
```
Beklenen son satırlar: `TÜM TESTLER GEÇTİ`, `AKIŞ TESTİ GEÇTİ`, `OK iş dağılımı testi`, `JOBDATATEST OK`, `HOLDTEST OK`, `SAVETEST OK`, `DATATEST OK`, `MULTIJOBTEST OK`, `BENCHTEST OK`. looptest ~2 dk sürer.
"RID leaked at exit" satırları başsız modun normal gürültüsüdür.

Ekran görüntüsü (render gerekir): `xvfb-run -a $G --path . --rendering-driver opengl3 -- --benchshot` (ayrıca `--jobshot`, `--holdshot`, `--propshot`, `--shot`, `--uishot`). Görüntüler `~/.local/share/godot/app_userdata/Bilgisayarcı Simülatör/` altına düşer.

## Mevcut durum (son güncelleme: Faz 1.5 sonu, PR #2 main'e birleşti)
- ✅ **Faz 0**: tekrar önleyici iş seçici, build düşme hatası, parçaya göre ücret, viewmodel elde tutma, ikinci el kayıt hatası, başarısız teslimde sebep.
- ✅ **Faz 1** (büyük ölçüde): veri altyapısı (parts/faults/jobs JSON), kayıt sürümü/yedek. Kalan: `game.gd`'yi servislere bölmek (ilgili sistem elden geçerken), personel rotalarında bazı sabit koordinatlar.
- ✅ **Faz 1.5**: tezgâh modu + çoklu iş (bırak-al, fiş, bekleyen işler rafı, kuyruk, gecikme kuralları, kayıt v3).

### Bilinen eksikler / ayar bekleyenler
- Tezgâh modundayken raftan parça alınamıyor (önce eline al; elde parçayla girince tepsiye gider).
- Fiş etiketi tezgâh görünümünde tepsinin üstüne biraz biniyor; fişler uzaktan okunmuyor.
- Müşteri gelişi seyrekleşti (14–24 sn × itibar; raf doluysa ×2) — oynanışa göre ayarlanmalı.
- Raf bölmeleri 4–6 kilitli; açan geliştirme yok (`Game.job_slot_bonus` hazır).
- Kasa taşırken oyuncu yavaşlamıyor. Takvim (6.2) yok.
- Başarısız teslim ipucu bozuk parçayı fazla açık söylüyor → Faz 3'te teşhis aletine bağlanmalı.
- Vida/söküm sırası (1.5.4) ve parça sağlık bilgisi (1.5.5) Faz 3 ile gelecek.
- Daha yeni sürümlü bir kayıt varsa menüde "Devam Et" görünür ama yüklenmez.

## Sıradaki adımlar
1. Kullanıcının oyun içi geri bildirimini al (tezgâh modu hissi, elde tutma, çoklu iş temposu) ve küçük ayarları yap.
2. **Faz 2 — parçalar ve uyumluluk**: anakart parça+slotu; soketler AM4/AM5/LGA1700/LGA1851; DDR4/DDR5 (çentik farkı); PSU watt + konnektörler; kasa form faktörü; `Compatibility.check()` (tezgâh modundaki `bench_mode.can_install()` kancasını doldurur); stok anahtarları `"tip:tier"`'dan gerçek SKU id'lerine geçmeli (PartDB şu an (kategori, tier) eşsizliği istiyor). Raf satır/seviye sayısı artmalı (`main.gd rows_y`, `device_rack.gd LEVELS`).
3. **Faz 3 — arıza ve teşhis**: 30+ arıza (yazılım, kablo, eğik pin, CMOS, çoklu arıza), debug LED'leri pahalı anakarta özel, teşhis aletleri, tornavida/vida, kablo bağlantıları. Yeni PC teşhis kodu için `pc_case.diagnose()`'a dal eklemek gerekir.
4. Sonra Faz 4 (depo), Faz 5 (TamirOS), Faz 6–7, Faz 8; **sokak/mahalle (Faz 9) en sona** — kullanıcı böyle istedi.

## Git
- Yeni iş için `main`'den dal aç (ya da oturumun verdiği dal adını kullan), commit'le, push et, kullanıcı isterse PR aç (hedef: `main`).
- Commit mesajları Türkçe; oturumun verdiği attribution satırlarını ekle. Commit/PR metnine model kimliği yazma.
