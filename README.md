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
| Tab | **Tezgâh modu**: tezgâhtaki cihaza yakından bak (aç / kapat) |

### Tezgâh modu

Tezgâhta bir cihaz (kasa, laptop, telefon) varken `Tab` ile kamera cihazın etrafındaki yörünge kameraya geçer; fare serbest kalır
ama zaman akmaya devam eder. Birinci şahıs tamir (E ile bak-tak-sök) aynen çalışır; tezgâh modu rahat yoldur.

| Girdi | İş |
| --- | --- |
| Sağ tık + sürükle | Cihazın etrafında döndür (Y ters çevirme ve hassasiyet ayarlarına uyar) |
| Tekerlek | Yakınlaştır / uzaklaş |
| WASD / orta tık sürükle | Kamerayı hafifçe kaydır |
| Q / E | 90° döndür |
| Sol tık | Cam kapağı aç-kapat, güç düğmesine bas, takılı parçayı söküp **tepsiye** koy, tepsideki parçayı seç, seçili parçayı yuvaya tak, seçili aleti uygula |
| Sağ tık (sürüklemeden) | Seçili parça / aleti bırak |
| Esc veya Tab | Tezgâh modundan çık |

Sökülen parçalar cihazın önündeki parça tepsisine dizilir. Tepsideki parçayı (3B ya da yan panelden) seçince imleci izleyen bir
hayalete dönüşür; uyumlu boş yuvalar yeşil, uyumsuzlar kırmızı yanar. Moda girerken elindeki parça tepsiye konur
(alet ise çıkınca eline geri verilir). Masadaki termal macun ve basınçlı hava yan panelden seçilip hedefe tıklanır.
Cihaz tezgâhtan giderse mod kapanır ve tepsideki parçalar masaya bırakılır.

## Menüler ve arayüz

Arayüz "mahalle tamirhanesi" kimliğiyle tasarlandı: paneller köşeleri vidalı metal plaka, düğmeler basınca
içeri gömülen mekanik klavye tuşu, tuş ipuçları eski bej klavye tuşu, başlıklar tabela harfleri (Bungee) ve
altlarında sarı-siyah ikaz şeridi; sürgüler mikser fader'ı, anahtarlar LED'li, ilerleme çubukları segmentli LED.

- **Ana menü:** akşamüstü, sokağın karşısından dükkânın vitrinine bakan yavaşça süzülen kamera. Işıklı kutu tabela
  (neon çerçeveli), kırmızı-krem çizgili tente, vitrin camı yazıları, neon "AÇIK", bayrak tabela, kaldırımda
  kara tahta pano, saksılar, sokak lambası. Solda tabela harfleriyle başlık ve 1-6 kısayollu klavye tuşu düğmeler:
  *Devam Et* (kayıt varsa gün ve kasa LCD yazısıyla), *Yeni Oyun* (kayıt varsa onay sorar), *Ayarlar*,
  *Nasıl Oynanır*, *Emeği Geçenler*, *Çıkış*. Oyuna geçerken kararma geçişi ve gündüz ışığına dönüş.
- **Duraklatma (Esc):** kapıya asılan tabela gibi iki iple sarkıp sallanan panel ("Çay molası... birazdan dönerim!"),
  arka plan bulanıklaşır, oyun gerçekten durur. *Devam Et, Ayarlar, Nasıl Oynanır, Ana Menüye Dön* (önce kaydeder),
  *Oyundan Çık*. Pencere odağı kaybolunca oyun kendiliğinden duraklar.
- **HUD:** sol üstte **yazar kasa** (yeşil LCD'de para, gün ve saat; LED gün çubuğu; itibar yıldızları);
  sağ üstte mandallı **tezgâh fişi** (tezgâhtaki müşteri: fiş numarası, tükenmez kalemle ad, lastik mühürle ücret, sabır çubuğu)
  ve altında **Açık İşler** listesi (fiş no, müşteri, kısa iş, teslim "Yarın 14:00", durum BEKLİYOR / HAZIR / GECİKTİ / TEZGÂHTA / ELDE; tezgâhtaki iş vurgulanır);
  hedefe bakınca vizör köşeleri kapanan nişangah ve bej `E` tuşlu etkileşim ipucu; solda LED'li bildirimler;
  ödemede yükselen "+TL"; öğretici ipuçları bantla yapıştırılmış **sarı not kâğıdında**.
- **Gün sonu:** yazar kasa fişi gibi **Z Raporu** (tırtıklı kâğıt, gelir/gider/kira/net, itibar, yarınki kira).
- **Dükkân bilgisayarı (laptop):** ParçaNet, Kargo Takip, Geliştirmeler ("ALINDI" mührü) ve Dükkân sekmeleri. **İflas:** "DÜKKÂN KAPANDI" mührü.

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

## Stok, ParçaNet ve kurye

- **Stok rafı:** raftaki parçalar dükkânın stoğudur; etikette `STOK: N` yazar, biten ürün raftan kalkar (`TÜKENDİ`).
  Sağlam bir parçayı elinde tutarken rafa E'ye basınca stoğa geri girer. Yeni oyunda küçük bir başlangıç stoğu var.
- **ParçaNet (tezgahtaki laptop):** 14 ürünlük katalog (masaüstü + laptop/telefon parçaları), adet seçimi, sepet, toplu alım indirimi (aynı üründen 5+ adet %10),
  Standart (2 saat, 250 TL üstü ücretsiz) veya Ekspres (30 dk, 45 TL) kargo. Fiyatlar her sabah değişen **piyasa kuruna**
  göre oynar (0.80 - 1.30); kur değişimi ▲/▼ ile gösterilir. Toptan Anlaşma %15 indirim verir.
- **Kurye:** varış saati gelince turuncu üniformalı kurye yürüyerek gelir, ParçaNet kolisini kapının yanına bırakır.
  Koliye E → parçalar stoğa girer. Kapanıştan sonra varacak kargolar ertesi sabah gelir; gün sonunda açılmamış
  koliler otomatik stoğa alınır. Yoldaki siparişler kayıtla saklanır.
- **Kargo Takip:** her siparişin içeriği, ödenen tutar, tahmini varışı ve durumu (YOLDA / KURYEDE / KAPIDA).
  HUD'da yazar kasanın altında yoldaki kargo ve kapıdaki koli sayısı görünür.
- **Tezgah satışı:** bazı müşteriler sadece parça almaya gelir; istenen parçayı raftan alıp elinde tutarken müşteriye E
  ile satarsın (piyasa fiyatı + %35). Stokta yoksa ekspres sipariş vermeye vaktin var.
- **Dükkân sekmesi:** kasa, itibar, toplam gelir, iş ve satış sayıları, stok adedi ve değeri, kira, kur.
- **Kurye Anlaşması** (yükseltme): kargolar yarı sürede ve ücretsiz gelir. Z raporunda parça siparişi ve kargo
  giderleri ayrı satırdır.

## Personel (çalışan alma)

- **Personel sekmesi (laptop):** her sabah 3 aday başvurur (Türkçe isim, rol, 1–5 yıldız beceri, huy, günlük maaş).
  En fazla **2 çalışan** alınır; "Çıkar" ile işten çıkarılır. Maaşlar gün sonunda ödenir ve Z raporunda
  **Maaşlar** satırında görünür. Çalışanlar kayıtla saklanır.
- **Tezgahtar** (kırmızı önlük): tezgâhtaki müşteriyi kendisi karşılar (bırakılan işi kabul edip fiş keser; raf
  doluysa kibarca geri çevirir), parça isteyen müşteriye raftan getirip satar (stokta yoksa haber verir),
  teslime gelen müşteriye **hazır** işin cihazını rafdan getirip verir, boşta kalınca kapıdaki kolileri açar.
- **Teknisyen** (mavi önlük): **Bekleyen İşler rafındaki** masaüstü işlerini yerinde, stoktaki parçalarla kendisi
  yapar (arızalı parça, yükseltme, toz, termal macun, sıfırdan toplama) ve işi "hazır" yapar; ücret teslimde sana
  gelir. Laptop/telefon ve tezgâhtaki (senin üzerinde çalıştığın) işe karışmaz. İşi ona bakıp E ile ya da
  sekmedeki **İşi Ver** ile verirsin; "Kendi alır" açıksa rafa konan işi kendiliğinden alır. Süre ve hata
  olasılığı beceriye/huya bağlıdır; hata yaparsa bir parça yanar ve itibar düşer. Parça yoksa "stok yok" der.
- Huylar: Titiz, Hızlı ama dalgın, Güler yüzlü (itibar +), Hevesli çaylak (ucuz), Eski toprak, Biraz uykucu.
- Kod: `scripts/staff.gd` (yönetici, davranışlar), `scripts/employee.gd` (önlüklü model), `scripts/staff_data.gd`
  (aday/huy verisi); `game.gd` sonundaki PERSONEL bölümü (kayıt, maaş).

## Oynanış

- **Müşteri** tezgaha gelir (sıra bekleyen en çok 3 müşteri). Derdini dinle: **E** ile işi kabul et ya da **F** ile
  geri çevir. Kabul edince cihaz sağ duvardaki **Bekleyen İşler rafına** konur, müşteri **fiş numarasını** alıp
  teslim gününü söyler ("Yarın öğlen uğrarım") ve gider. Parça satışı müşterisi (tezgâh satışı) eskisi gibi anında olur.
- **İş kapasitesi:** aynı anda en çok **3 açık iş** (raf 6 gözlüdür, kalanı kilitli; `Game.max_active_jobs()`).
  Raf doluyken gelen müşteriyi **F** ile geri çevirirsin (itibar kaybı yok).
- **Cihaz taşıma:** rafta/tezgâhta cihazın üstündeki **fişe** (ya da rafın gözüne) bakıp **E**: kasayı/laptopu/telefonu
  elinde taşırsın (G ya da sağ tık: geldiği yere geri koyar; taşırken parça/alet alınamaz). Tezgâh yerine (masadaki
  mavi minder) ya da rafın boş gözüne bakıp **E** ile bırakırsın. Sadece tezgâhtaki cihazı açıp tamir edersin.
- **Cam kapağı** aç, **güç düğmesine** bas ve belirtileri izle (bip sesleri, ekran).
- Duvardaki **Arıza Rehberi** hangi belirtinin hangi parçayı gösterdiğini söyler.
- Anakarttaki **hata LED'leri** (CPU / DRAM / VGA / BOOT) açılışta sorunlu parçayı gösterir.
- Arızalı parçayı sök, **raftan** yenisini satın al, tak.
- Kapağı kapat, cihazı **rafa koy**: sorun kalmadıysa fiş şeridi ve raf ışığı **yeşil** yanar (HAZIR); hâlâ arıza
  varsa uyarı alırsın. Işıklar: kehribar = bekliyor, yeşil = hazır, kırmızı = teslim saati geçti.
- **Teslim:** müşteri fişte yazan saatte geri gelir (HUD'da "Yarın 14:00"). Fiş numarasını söyler; sen **o numaralı**
  cihazı rafta bulup (E ile al) müşteriye dönüp **E**'ye basarsın. Yanlış cihaz = komik şikâyet ve küçük itibar kaybı;
  arızalıysa müşteri itiraz eder; doğruysa paranı alırsın. Zamanında (rafta hazır) teslim itibarı artırır, erken
  bitirmek (teslim süresinin ilk yarısında hazır) daha çok.
- **Teslim zamanı:** tamir/yükseltme/garanti ertesi gün 10:00–18:00 arası; sıfırdan toplama 2 gün sonra; %20 ihtimalle
  **ekspres** müşteri (15:30'a kadar gelen tamir) "bugün lazım" der: 3 oyun saati sonra, ücret +%20.
- **Gecikme:** müşteri vakti gelince cihaz hazır değilse tezgâhta bekler (sabır ~60 sn; bu sürede tamir edip verebilirsin).
  Sabrı biterse ilkinde **bir gün daha** verir (itibar −0.2), ikincisinde cihazını **olduğu gibi alıp gider** (itibar −0.5, ücret yok).
  Açık işler gün sonunda ve gece boyunca rafta kalır; Z raporunda "Rafta açık iş" satırı vardır.
- Eski parçaları **hurda kutusuna** at (sağlam parçalar hurdacıya satılır).

## Gün döngüsü, itibar ve dükkân

- **Gün:** dükkân 09:00–19:00 açıktır (bir gün yaklaşık 6 gerçek dakika; `Game.DAY_REAL_SECONDS`).
  Saat sol üstte "Gün 3 · 14:25" olarak görünür. Kapanışta içerideki müşteri işini bitirebilir, sonra
  **gün sonu özeti** açılır (gelir, parça giderleri, kira, net, itibar). **Sonraki gün** ile devam edilir.
- **Kira:** her gün sonunda düşer (150 TL, 3 günde bir 25 TL artar). Kasa üst üste 2 gün eksi biterse
  **iflas** edersin ve yeni oyun başlar.
- **İtibar (0–5 yıldız):** başarılı teslim artırır (hızlıysa daha çok), hatalı teslim denemeleri ve
  kızıp giden müşteriler düşürür. İtibar iş ücretini (±%20) ve müşteri gelme sıklığını etkiler.
- **Sabır:** tezgâhta ~60 sn ilgilenmezsen müşteri kızıp gider (sırada bekleyenin sabrı yarı hızda tükenir).
  Tezgâh fişindeki çubuk kalan sabrı gösterir.
- **Geliştirmeler:** tezgahtaki laptopla aç (E) → Geliştirmeler. Reklam Tabelası (müşteri daha sık gelir),
  Toptan Anlaşma (ParçaNet %15 indirim), Kurye Anlaşması (kargo yarı sürede, ücretsiz),
  Kahve Makinesi (sabır +%50), Usta Sertifikası (ücret +%15).
  Satın alınanlar dükkânda görünür.
- **Kayıt:** gün sonunda ve oyundan çıkarken otomatik kaydedilir (`user://save.json`, sürüm 3). Başlangıç
  ekranında **Devam Et** ile kayıtlı günün 09:00'ından devam edersin, **Yeni Oyun** sıfırlar. Açık işler
  (fiş no, teslim zamanı, durum) ve cihazlarının parça durumu (takılı parçalar, arızalar, toz, macun, muadil) kayda girer;
  yüklenince cihazlar rafa / tezgâha geri konur. Eski (v2) kayıtlar açık iş olmadan yüklenir.

- **Muadil parça:** ParçaNet'te her ürün Orijinal ya da Muadil (%40 ucuz) alınabilir. Raftan orijinal **E**,
  muadil **F** ile alınır. Muadil parça turuncu etiketlidir, hurdada/tezgahta %60 değerindedir.
- **Garanti:** takılı muadil parçayla teslim edilen iş %35 ihtimalle 1-2 gün içinde `warranty` işi olarak
  geri döner (ücretsiz tamir; hızlı çözmek itibarı düzeltir, kızıp gitmesi itibarı düşürür). Mantık `scripts/warranty.gd`.
- **İkinci el pazarı:** laptopta İkinci El sekmesi, her gün tohumlu yeni ilanlar (`scripts/used_market.gd`).
  Alınan parça orijinal stoğa girer; "arızalı çıkabilir" ilanlarda gizli bozuk olabilir.
- **Elektrik faturası:** gün sonunda kiraya ek: 15 TL + iş başına 3 TL (+8 Kahve Makinesi, +5 Tabela). Z Raporu'nda görünür.

İş tipleri: arıza tamiri, aşırı ısınma, ekran kartı yükseltme, RAM yükseltme, sıfırdan bilgisayar toplama,
tezgahtan parça satışı.

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
scripts/job_manager.gd  Müşteri kuyruğu, bırakma/teslim akışı, iş kayıtları (Game.jobs_active)
scripts/job_rack.gd     Bekleyen İşler rafı (6 göz, numara, durum ışığı)
scripts/job_carry.gd    Cihaz taşıma (kameraya takılı kasa/laptop/telefon)
scripts/job_store.gd    Teslim zamanı, kayıt normalleştirme, cihaz durumu kaydet/yükle, fiş etiketi
scripts/hud.gd          HUD, gün sonu / iflas ekranları, öğretici ipuçları
scripts/office_panel.gd Laptop: ParçaNet siparişi, Kargo Takip, Geliştirmeler, Dükkân istatistikleri
scripts/delivery.gd     Kurye ve kargo kolileri
scripts/staff.gd        Personel: çalışanların davranışları (tezgahtar, teknisyen)
scripts/employee.gd     Önlüklü çalışan modeli
scripts/staff_data.gd   Aday üretimi, roller ve huylar
scripts/menu.gd         Ana menü (+ emeği geçenler, onay penceresi)
scripts/pause_menu.gd   Duraklatma menüsü (bulanık arka plan)
scripts/settings.gd     Ayarlar (autoload): kayıt, uygulama, ses kanalları
scripts/settings_panel.gd  Ayarlar ekranı (Grafik/Ses/Kontroller/Oyun)
scripts/howto_panel.gd  Nasıl Oynanır ekranı
scripts/ui_theme.gd     Ortak tema (renkler, font, stiller); assets/ui/theme.res bundan üretilir
scripts/ui_kit.gd       Arayüz yardımcıları (düğme, tuş kapağı, modal, animasyonlar)
scripts/music.gd        Kodla üretilen fon müziği
assets/fonts/           Exo 2, Bungee, VT323, Caveat yazı tipleri + OFL_*.txt lisansları
assets/ui/theme.res     Proje varsayılan teması (`dev/make_theme.gd` ile yeniden üretilir)
scripts/mesh_util.gd    Prosedürel model ve doku yardımcıları (yuvarlak kutu, levha, torna, tuş kapakları, 2D→doku pişirme)
scripts/props.gd        Detaylı eşyalar: klavye, fare, laptop, telefon, monitör, masa lambası, kupa, yazar kasa, CRT
scripts/sfx.gd          Kodla üretilen sesler (SFX kanalı)
assets/                 Dokular ve HDRI (Poly Haven, CC0)
dev/                    Geliştirici araçları (ekran görüntüsü, otomatik test)
```

Otomatik test (tamir döngüsü + gün/itibar/kayıt/iflas): `godot --headless -- --looptest`  
Çoklu iş testi (bırakma, kapasite, taşıma, kayıt/yükleme, teslim, gecikme): `godot --headless -- --multijobtest`  
Bekleyen işler rafı / taşıma / HUD listesi görüntüleri: `godot --rendering-driver opengl3 -- --jobshot` (`shot_jobs_*.png`)  
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

Yazı tipleri, hepsi [SIL Open Font License 1.1](https://openfontlicense.org): **Exo 2** (The Exo 2 Project Authors,
[OFL_Exo2.txt](assets/fonts/OFL_Exo2.txt)), **Bungee** (The Bungee Project Authors, [OFL_Bungee.txt](assets/fonts/OFL_Bungee.txt)),
**VT323** (The VT323 Project Authors, [OFL_VT323.txt](assets/fonts/OFL_VT323.txt)),
**Caveat** (The Caveat Project Authors, [OFL_Caveat.txt](assets/fonts/OFL_Caveat.txt)).
Oyun motoru: [Godot Engine](https://godotengine.org) (MIT). Ses efektleri ve fon müziği oyun içinde kodla üretilir.

## Laptop ve telefon tamiri

Tamir işlerinin bir kısmında müşteri masaüstü yerine **laptop** ya da **telefon** getirir; cihaz masaya düz konur
ve kendi küçük ekranında belirtiyi gösterir.

- **Laptop:** güç düğmesi klavyenin sağ üstünde. Klavyeye bakıp E: ekran kapanır, laptop ters döner, vidalı alt kapak
  sökülüp yana konur. İçeride SO-DIMM RAM, M.2 NVMe SSD ve batarya (anakart, fan, ısı borusu, hoparlörler).
  Ekran paneli kapaktadır; laptop düzken sökülür.
  Belirtiler: RAM → mavi ekran `MEMORY_MANAGEMENT`; SSD → `Boot device not found`; batarya → "%0, takılı, şarj olmuyor"
  uyarısı ve şişen pilin kabarttığı touchpad (içeride şişmiş pil görünür); ekran → çatlak cam ve renkli çizgiler.
- **Telefon:** güç tuşu sağ kenarda. Üstüne bakıp E: ekran modülü kitap gibi yana kalkar. İçeride batarya ve şarj soketi.
  Belirtiler: batarya → kırmızı %1 pil simgesi, hemen kapanır, şişen pil ekranı kaldırır; şarj soketi → "Şarj olmuyor"
  uyarısı, sokette pas; ekran → örümcek ağı çatlak.
- Yeni parçalar (Laptop RAM, M.2 SSD, laptop/telefon bataryası, laptop/telefon ekranı, şarj soketi) ParçaNet'te
  satılır ve arka duvardaki **LAPTOP & TELEFON** rafında durur; yeni oyunda birer adet stok vardır.
- Kod: `scripts/device_base.gd` (ortak), `laptop_device.gd`, `phone_device.gd`, `device_slot.gd`, `device_parts.gd`
  (modeller), `device_jobs.gd` (müşteri cümleleri, iş üretimi), `device_rack.gd` (raf).
- Geliştirici: `-- --uishot --devshot` cihaz görüntülerini `shot_dev_*.png` olarak kaydeder.
