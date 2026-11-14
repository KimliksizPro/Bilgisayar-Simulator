# Bilgisayarcı Simülatör

Mahallenin bilgisayarcısı sensin! Müşteriler arızalı bilgisayarlarıyla gelir, derdini anlatır.
Kasayı aç, arızayı bul, parçayı değiştir, bilgisayarı çalıştır ve parayı kap.

Godot 4.4 ile yapılmış, stilize 3D bir oyun. Modeller kodla üretiliyor; zemin, duvar, ahşap gibi
yüzeylerde gerçek PBR dokular ve gökyüzü için gerçek bir şehir HDRI'si kullanılıyor.

## Nasıl çalıştırılır

1. [Godot 4.4](https://godotengine.org/download) (standart sürüm, .NET değil) indir.
2. Godot'u aç → **Import** → bu klasördeki `project.godot` dosyasını seç.
3. **F5** ile oyunu başlat.

## Kontroller

| Tuş | İş |
| --- | --- |
| WASD | Yürü |
| Shift | Koş |
| E / Sol tık | Etkileşim (al, tak, sök, konuş, satın al) |
| G / Sağ tık | Elindekini bırak |
| Esc | Duraklatma menüsü (yönetim panelini kapatır) |
| Fare / yön tuşları / Enter | Menüler (klavye ve gamepad ile odak gezintisi de çalışır) |
| F2 | Grafik kalitesi: Düşük → Orta → Yüksek (oyun kasarsa düşür) |
| F3 | FPS ve draw call sayacı |
| H | Öğretici ipucunu gizle |

## Menüler ve arayüz

- **Ana menü:** oyun açılınca gerçek dükkânın üzerinde yavaşça süzülen sinematik kamera, solda başlık ve düğmeler:
  *Devam Et* (kayıt varsa gün ve kasa gösterilir), *Yeni Oyun* (kayıt varsa onay sorar), *Ayarlar*,
  *Nasıl Oynanır*, *Emeği Geçenler*, *Çıkış*. Düğmelerde üstüne gelme/tıklama sesi ve animasyonu, oyuna
  geçerken kararma geçişi vardır.
- **Duraklatma (Esc):** arka plan bulanıklaşır, oyun gerçekten durur (saat, müşteri sabrı, fizik).
  *Devam Et, Ayarlar, Nasıl Oynanır, Ana Menüye Dön* (önce kaydeder), *Oyundan Çık*.
  Pencere odağı kaybolunca oyun kendiliğinden duraklar.
- **HUD:** sol üstte para (değişince sayarak güncellenir), gün/saat ve gün ilerleme çubuğu, itibar yıldızları;
  sağ üstte aktif iş kartı (müşteri, ücret, hedef, yeşilden kırmızıya kayan sabır çubuğu); ortada hedefe bakınca
  büyüyüp amber olan nişangah ve `[E] Eylem` etkileşim ipucu; solda kayarak giren para/uyarı/bilgi bildirimleri;
  ödemede yükselen "+TL"; ilk günlerde üstte kısa öğretici ipuçları.
- **Gün sonu özeti, Yönetim Paneli, iflas** ekranları aynı temayla, açılış/kapanış animasyonlu.

## Ayarlar

Ana menüden ve duraklatma menüsünden açılır, `user://settings.cfg` dosyasına kaydedilir ve açılışta uygulanır.

| Sekme | Ayarlar |
| --- | --- |
| Grafik | Kalite (Düşük/Orta/Yüksek), pencere modu (pencere/tam ekran/kenarsız), VSync, FPS sınırı, çözünürlük ölçeği (%50-100), FSR 1.0, FOV |
| Ses | Ana / Efekt / Müzik (ses kanalları `Master`, `SFX`, `Music`) |
| Kontroller | Fare hassasiyeti, Y eksenini ters çevir, tuş listesi |
| Oyun | FPS sayacı, ipuçlarını göster, ipuçlarını sıfırla |

Kalite: **Yüksek** SDFGI + SSIL + SSR + SSAO + hacimsel sis; **Orta** sadece SSAO + SSR; **Düşük** hepsi kapalı,
MSAA kapalı, gölgeler hafifletilmiş.

## Oynanış

- **Müşteri** tezgaha gelir. Onunla konuşunca bilgisayarı masana bırakır.
- **Cam kapağı** aç, **güç düğmesine** bas ve belirtileri izle (bip sesleri, ekran).
- Duvardaki **Arıza Rehberi** hangi belirtinin hangi parçayı gösterdiğini söyler.
- Anakarttaki **hata LED'leri** (CPU / DRAM / VGA / BOOT) açılışta sorunlu parçayı gösterir.
- Arızalı parçayı sök, **raftan** yenisini satın al, tak.
- Kapağı kapat, müşteriyle konuş ve paranı al.
- Eski parçaları **hurda kutusuna** at (sağlam parçalar hurdacıya satılır).

## Gün döngüsü, itibar ve dükkân

- **Gün:** dükkân 09:00–19:00 açıktır (bir gün yaklaşık 6 gerçek dakika; `Game.DAY_REAL_SECONDS`).
  Saat sol üstte "Gün 3 · 14:25" olarak görünür. Kapanışta içerideki müşteri işini bitirebilir, sonra
  **gün sonu özeti** açılır (gelir, parça giderleri, kira, net, itibar). **Sonraki gün** ile devam edilir.
- **Kira:** her gün sonunda düşer (150 TL, 3 günde bir 25 TL artar). Kasa üst üste 2 gün eksi biterse
  **iflas** edersin ve yeni oyun başlar.
- **İtibar (0–5 yıldız):** başarılı teslim artırır (hızlıysa daha çok), hatalı teslim denemeleri ve
  kızıp giden müşteriler düşürür. İtibar iş ücretini (±%20) ve müşteri gelme sıklığını etkiler.
- **Sabır:** müşteriyle ~60 sn konuşmazsan ya da iş ~4 oyun saatinden uzun sürerse kızıp gider
  (bilgisayarını da götürür). İş panelindeki çubuk kalan sabrı gösterir.
- **Yönetim Paneli:** tezgahtaki laptopla aç (E). Geliştirmeler: Reklam Tabelası (müşteri daha sık gelir),
  Toptan Anlaşma (raf fiyatları %15 indirim), Kahve Makinesi (sabır +%50), Usta Sertifikası (ücret +%15).
  Satın alınanlar dükkânda görünür.
- **Kayıt:** gün sonunda ve oyundan çıkarken otomatik kaydedilir (`user://save.json`). Başlangıç
  ekranında **Devam Et** ile kayıtlı günün 09:00'ından devam edersin, **Yeni Oyun** sıfırlar.

İş tipleri: arıza tamiri, ekran kartı yükseltme, RAM yükseltme, sıfırdan bilgisayar toplama.

## Proje yapısı

```
scenes/main.tscn        Ana sahne (sadece main.gd'yi yükler)
scripts/main.gd         Dükkânı, ışıkları, rafı, tezgahı kurar
scripts/game.gd         Global durum: para, gün/saat, itibar, geliştirmeler, kayıt — autoload
scripts/player.gd       Birinci şahıs oyuncu, etkileşim, taşıma
scripts/pc_case.gd      Kasa, anakart, yuvalar, teşhis, güç
scripts/part.gd         Alınıp takılabilen parça
scripts/part_models.gd  Parça modelleri, isimler, fiyatlar
scripts/slot.gd         Kasa içindeki parça yuvaları
scripts/monitor.gd      Monitör (BIOS / masaüstü ekranı)
scripts/customer.gd     Müşteri modeli ve yürüme
scripts/job_manager.gd  Müşteri/iş akışı
scripts/hud.gd          HUD, gün sonu / yönetim paneli / iflas ekranları, öğretici ipuçları
scripts/menu.gd         Ana menü (+ emeği geçenler, onay penceresi)
scripts/pause_menu.gd   Duraklatma menüsü (bulanık arka plan)
scripts/settings.gd     Ayarlar (autoload): kayıt, uygulama, ses kanalları
scripts/settings_panel.gd  Ayarlar ekranı (Grafik/Ses/Kontroller/Oyun)
scripts/howto_panel.gd  Nasıl Oynanır ekranı
scripts/ui_theme.gd     Ortak tema (renkler, font, stiller); assets/ui/theme.tres bundan üretilir
scripts/ui_kit.gd       Arayüz yardımcıları (düğme, tuş kapağı, modal, animasyonlar)
scripts/music.gd        Kodla üretilen fon müziği
assets/fonts/           Exo 2 yazı tipi + OFL.txt
assets/ui/theme.tres    Proje varsayılan teması (`dev/make_theme.gd` ile yeniden üretilir)
scripts/mesh_util.gd    Prosedürel model ve doku yardımcıları (yuvarlak kutu, levha, torna, tuş kapakları, 2D→doku pişirme)
scripts/props.gd        Detaylı eşyalar: klavye, fare, laptop, telefon, monitör, masa lambası, kupa, yazar kasa, CRT
scripts/sfx.gd          Kodla üretilen sesler (SFX kanalı)
assets/                 Dokular ve HDRI (Poly Haven, CC0)
dev/                    Geliştirici araçları (ekran görüntüsü, otomatik test)
```

Otomatik test (tamir döngüsü + gün/itibar/kayıt/iflas): `godot --headless -- --looptest`
Arayüz görüntüleri: `godot -- --uishot` (oyun içi), `godot -- --menushot` (ana menü); menü akışı testi: `godot --headless -- --flowtest`  
Dev argümanları (`--shot`, `--uishot`, `--perf`, `--partshot`, `--looptest`) ana menüyü atlayıp doğrudan oyuna girer.  
Performans ölçümü: `godot -- --perf`  ·  Parça vitrini görseli: `godot -- --partshot`  
Eşya/müşteri yakın çekimleri: `godot -- --propshot` (isteğe bağlı `--only=keyboard,laptop,faces`)

## Grafik

- **Yüksek kalite:** SDFGI (dolaylı ışık), SSIL, SSR yansımaları, hacimsel sis (ışık huzmeleri).
- **Orta kalite:** SSAO + SSR. **Düşük kalite:** hepsi kapalı, zayıf ekran kartlarında akıcı çalışır.
- Optimizasyon: sabit nesneler malzemeye göre tek mesh'te birleştirilir (`MU.merge_static`) ve boşalan
  düğümler silinir (sahnede ~1100 yerine ~95 MeshInstance kalır); dönen fanlar ve müşteri kol/bacakları da
  kendi içinde birleştirilir. Sadece 3 ışık gölge düşürür, 3D yazılar gölge geçişlerine girmez,
  monitör ekranı sadece değişince yeniden çizilir.
- Klavye tuşları gerçek eğimli kapaklardır ve harfleri basılıdır (Türkçe Q düzeni); bütün tuşlar tek mesh +
  tek malzemeyle çizilir. Harfler, laptop/telefon/yazar kasa ekranları bir kez 2D olarak çizilip mipmap'li
  dokuya "pişirilir" (`MU.bake_2d`), ardından SubViewport silinir: sürekli maliyeti yoktur.
- Şekiller: köşeleri yuvarlatılmış kutular (`MU.rbox`), telefon/laptop gibi pahlı levhalar (`MU.slab`),
  kupa/lamba/kutu gibi yuvarlak nesneler için torna profilleri (`MU.lathe`).
- Müşteriler adlarına göre görünür: "Teyze" gri topuzlu, "Amca" bıyıklı/kel olabilir, kadınlar uzun saçlı;
  kıyafet (tişört / gömlek / kapüşonlu), gözlük, sakal ve renkler rastgeledir.
- Tonlama: AgX.

## Lisanslar

Doku ve HDRI dosyaları [Poly Haven](https://polyhaven.com)'dan alınmıştır ve **CC0** (kamu malı) lisanslıdır:
floor_tiles_06, painted_plaster_wall, wood_table_001, laminate_floor_02, rectangular_paving,
asphalt_02, painted_brick, buikslotermeerplein (HDRI).

Yazı tipi: **Exo 2** (The Exo 2 Project Authors), [SIL Open Font License 1.1](assets/fonts/OFL.txt).
Oyun motoru: [Godot Engine](https://godotengine.org) (MIT). Ses efektleri ve fon müziği oyun içinde kodla üretilir.
