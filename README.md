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
| Esc | Duraklat (yönetim panelini kapatır) |
| Fare | Menü, yönetim paneli ve gün sonu ekranındaki düğmeler |
| F2 | Grafik kalitesi (Yüksek/Düşük) — oyun kasarsa Düşük yap |
| F3 | FPS ve draw call sayacı |

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
scripts/hud.gd          Ekran arayüzü
scripts/mesh_util.gd    Prosedürel model ve doku yardımcıları
scripts/sfx.gd          Kodla üretilen sesler
assets/                 Dokular ve HDRI (Poly Haven, CC0)
dev/                    Geliştirici araçları (ekran görüntüsü, otomatik test)
```

Otomatik test (tamir döngüsü + gün/itibar/kayıt/iflas): `godot --headless -- --looptest`
Arayüz görüntüleri: `godot -- --uishot`  
Performans ölçümü: `godot -- --perf`  ·  Parça vitrini görseli: `godot -- --partshot`

## Grafik

- **Yüksek kalite:** SDFGI (dolaylı ışık), SSIL, SSR yansımaları, hacimsel sis (ışık huzmeleri).
- **Düşük kalite:** bunlar kapalı, zayıf ekran kartlarında akıcı çalışır.
- Optimizasyon: sabit nesneler malzemeye göre tek mesh'te birleştirilir (`MU.merge_static`),
  sadece 3 ışık gölge düşürür, monitör ekranı sadece değişince yeniden çizilir.
- Tonlama: AgX. Kenarlar yuvarlatılmış özel mesh'ler (`MU.rbox`) ile yapılıyor.

## Lisanslar

Doku ve HDRI dosyaları [Poly Haven](https://polyhaven.com)'dan alınmıştır ve **CC0** (kamu malı) lisanslıdır:
floor_tiles_06, painted_plaster_wall, wood_table_001, laminate_floor_02, rectangular_paving,
asphalt_02, painted_brick, buikslotermeerplein (HDRI).
