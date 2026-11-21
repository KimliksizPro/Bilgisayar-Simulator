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
| Veri | `data/parts.json` (47 SKU = 34 PC + 13 mobil PartDef), `data/faults.json` (50 FaultDef), `data/jobs.json` (49 JobTemplate + metin havuzları); yükleyiciler `scripts/data/` |
| İş akışı | `job_manager.gd` (müşteri kuyruğu, bırak/al, teslim, bahşiş), `job_store.gd` (iş kayıtları, teslim süreleri, cihaz durumunu kaydet/yükle v5), `job_rack.gd` (bekleyen işler rafı), `job_carry.gd` (cihaz taşıma), `job_director.gd` (ağırlıklı torba + tekrar/kilit filtresi), `device_jobs.gd`, `warranty.gd` |
| Cihazlar | `pc_case.gd` (slotlar, vidalar, 5 kablo, `diagnose_all()`, bip/anakart Debug LED + POST kartı), `laptop_device.gd`, `phone_device.gd`, `device_base.gd`, `slot.gd`, `device_slot.gd` |
| Oyuncu | `player.gd` (hareket, elde tutma + viewmodel katmanı 20 / SubViewport), `part.gd`, `tool.gd` (12 alet: 4 başlangıç + 8 teşhis/servis) |
| Tezgâh modu | `bench_mode.gd` (Tab; yörünge kamera, fareyle sök/tak, tepsi, test parçaları, kablo düzenle, vida/parça ipuçları, yan panel). Sözleşme: `Game.bench_device`, `Game.bench_changed`, `Game.set_bench_device()` |
| UI | `hud.gd` (yazar kasa, tezgâh fişi, AÇIK İŞLER listesi), `office_panel.gd` (dükkân laptop'u: ParçaNet, kargo, 2 bölümlü geliştirmeler, ikinci el, personel), `pc_service_panel.gd` (monitörden [E] / tezgâhtan açılan BIOS, Yazılım & Teşhis paneli), `ui_kit.gd`, `ui_theme.gd`, `menu.gd`, `pause_menu.gd`, `settings_panel.gd` |
| Diğer | `staff.gd`/`employee.gd`/`staff_data.gd` (personel), `delivery.gd` (kurye), `used_market.gd`, `sfx.gd`, `music.gd` |

Kayıt: `user://save.json`, `SAVE_VERSION = 5`, `_migrate()` ile eski kayıtlar yükseltilir; atomik yazma + `.bak` yedek.

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
for t in looptest flowtest jobdisttest jobdatatest holdtest savetest datatest multijobtest benchtest compattest diagtest; do echo "== $t"; timeout 400 $G --headless --path . -- --$t 2>&1 | grep -E "SCRIPT ERROR|GEÇTİ|OK|FAIL|HATA" | tail -1; done
```
Beklenen son satırlar: `TÜM TESTLER GEÇTİ`, `AKIŞ TESTİ GEÇTİ`, `OK iş dağılımı testi`, `JOBDATATEST OK`, `HOLDTEST OK`, `SAVETEST OK`, `DATATEST OK`, `MULTIJOBTEST OK`, `BENCHTEST OK`, `COMPATTEST OK`, `DIAGTEST OK`. looptest ~2 dk sürer.
"RID leaked at exit" satırları başsız modun normal gürültüsüdür.

Ekran görüntüsü (render gerekir): `xvfb-run -a $G --path . --rendering-driver opengl3 -- --benchshot` (ayrıca `--jobshot`, `--holdshot`, `--propshot`, `--shot`, `--uishot`). Görüntüler `~/.local/share/godot/app_userdata/Bilgisayarcı Simülatör/` altına düşer.

## Mevcut durum (son güncelleme: Faz 3 tamamlandı)
- ✅ **Faz 0**: tekrar önleyici iş seçici, build düşme hatası, parçaya göre ücret, viewmodel elde tutma, ikinci el kayıt hatası, başarısız teslimde sebep.
- ✅ **Faz 1** (büyük ölçüde): veri altyapısı (parts/faults/jobs JSON), kayıt sürümü/yedek. Kalan: `game.gd`'yi servislere bölmek (ilgili sistem elden geçerken), personel rotalarında bazı sabit koordinatlar.
- ✅ **Faz 1.5**: tezgâh modu (1.5.4 vida/söküm sırası + 1.5.5 bilgi/sağlık kartı dahil) + çoklu iş (bırak-al, fiş, bekleyen işler rafı, kuyruk, gecikme kuralları, kayıt v5).
- ✅ **Faz 2**: gerçek parça çeşitliliği ve uyumluluk (`Compatibility.check()`, 34 PC SKU, 4 soket, DDR4/DDR5, PSU watt/konnektör, kasa boyut sınırları).
- ✅ **Faz 3**: 50 arıza, çoklu arıza (`diagnose_all()`), anakart Debug LED'leri & POST kartı, 12 teşhis/servis aleti, vida mekaniği & otomatik vida, 5 etkileşimli kablo + düzen bahşişi, BIOS/Servis paneli (`pc_service_panel.gd`), 10 laptop + 8 telefon arızası, kayıt şeması v5.

### Bilinen eksikler / ayar bekleyenler
- Tezgâh modundayken raftan parça alınamıyor (önce eline al; elde parçayla girince tepsiye gider).
- Fiş etiketi tezgâh görünümünde tepsinin üstüne biraz biniyor; fişler uzaktan okunmuyor.
- Müşteri gelişi seyrekleşti (14–24 sn × itibar; raf doluysa ×2) — oynanışa göre ayarlanmalı.
- Raf bölmeleri 4–6 kilitli; açan geliştirme yok (`Game.job_slot_bonus` hazır).
- Kasa taşırken oyuncu yavaşlamıyor. Takvim (6.2) yok.
- Daha yeni sürümlü bir kayıt varsa menüde "Devam Et" görünür ama yüklenmez.

## Sıradaki adımlar
1. Faz 3'ün oyun içi görsel/oynanış testi ve ince ayarlar.
2. **Faz 4 — depo ve envanter**: `InventoryItem` tekil kimlik, fiziksel parça kutuları, depo rafları, sökülen müşteri parçalarının ekonomisi.
3. Sonra Faz 5 (TamirOS), Faz 6–7, Faz 8; **sokak/mahalle (Faz 9) en sona** — kullanıcı böyle istedi.

## Git
- Yeni iş için `main`'den dal aç (ya da oturumun verdiği dal adını kullan), commit'le, push et, kullanıcı isterse PR aç (hedef: `main`).
- Commit mesajları Türkçe; oturumun verdiği attribution satırlarını ekle. Commit/PR metnine model kimliği yazma.
