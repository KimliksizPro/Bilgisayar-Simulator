# Bilgisayarcı Simülatör — Yol Haritası

> Hazırlanış: 3 ajanlı araştırma (PC Building Simulator 1/2, Computer Repair Shop, PC Creator, Internet Cafe Sim;
> Supermarket Sim, TCG Card Shop Sim, Car Mechanic Sim, ReStory, Gas Station Sim) + mevcut kodun satır satır denetimi.
> Sokak / mahalle bilerek **en sona** bırakıldı.

Her madde: **Boyut** S (birkaç saat) · M (1-2 gün) · L (3+ gün). Fazlar sırayla yapılmalı; çünkü sonraki fazlar
önceki fazın altyapısına dayanıyor (özellikle Faz 1 veri altyapısı olmadan içerik eklemek her parça için ~6 dosya
düzenlemek demek).

---

## Mevcut durumun özeti (denetimden)

| Konu | Şu an | Sorun |
| --- | --- | --- |
| Arıza çeşidi | PC: psu/cpu/ram/gpu/ssd + toz/macun · Laptop: 4 · Telefon: 3 → toplam **14**, hepsi "tek parça bozuk" | Yazılım, kablo, anakart, fan, çoklu arıza yok |
| İş seçimi | `job_manager.gd:_make_job` saf `randf()`, geçmiş hafızası yok | Aynı arıza üst üste gelebiliyor; **para < 300 iken build dalı `upgrade_gpu`'ya düşüyor** (`job_manager.gd:206-218`) → erken oyunda işlerin ~%30'u ekran kartıyla ilgili |
| Teşhis | Anakart debug LED'leri arızalı parçayı direkt gösteriyor + duvarda arıza rehberi | Teşhis bulmaca değil, otomatik |
| Elde tutma | Parça (`RigidBody3D`, freeze) kameranın çocuğuna reparent ediliyor (`player.gd:30-32, 101-107`) | Duvara/kasaya yaklaşınca geri çekilme yok, ayrı render katmanı yok → geometrinin içine/arkasına giriyor |
| Envanter | `Game.stock = {"tip:seviye": adet}` sayaçları | Parçaların kimliği yok; kargo kutusu açılınca parçalar "sayıya" dönüşüyor, raf sadece dağıtıcı |
| Parça verisi | tip + tier (sadece RAM/GPU'da 2 seviye), tek CPU, tek PSU, tek SSD | Soket, DDR nesli, watt, form faktör yok; "DDR4" sadece dokuya yazılmış yazı |
| Dükkân PC'si | Tam ekran 2D panel (`office_panel.gd`, 6 sekme) | İşletim sistemi hissi yok; e-posta, iş talepleri, envanter, teşhis uygulaması yok |
| Müşteri | Aynı anda tek müşteri, kuyruk yok, iş süresi 4 oyun saati | Çok iş / çok gün süren sipariş yok |
| Kayıt | Gün sonunda | Saat geri yüklenmiyor, ikinci el "satıldı" bayrakları kaydedilmiyor (para istismarı), yerdeki parçalar kayboluyor |
| Kod | `main.gd` 854, `hud.gd` 780, `game.gd` 725, `office_panel.gd` 639 satır; tüm içerik kod içinde sabit | Yeni içerik eklemek pahalı ve kırılgan |

---

## Faz 0 — Acil düzeltmeler ✅ TAMAMLANDI

| # | İş | Boyut | Not |
| --- | --- | --- | --- |
| 0.1 ✅ | **Build fall-through hatası**: para < 300 iken build'i ağırlık 0 yap, başka dala düşmesin | S | `job_manager.gd:206` |
| 0.2 ✅ | **Tekrar önleyici iş seçici ("JobDirector")**: ağırlıklı torba (Tetris 7-bag mantığı) + son 4 işte görülen arızanın ağırlığını ×0.25, aynı arızayı arka arkaya ×0; ceza **parça ailesine** de uygulansın (gpu tamiri, gpu yükseltme, gpu satışı birbirini zincirlemesin). Geçmiş kayda yazılsın | M | Rakip oyunların 1 numaralı şikâyeti tekrar |
| 0.3 ✅ | **Elde tutma düzeltmesi**: (a) her karede kameradan ileri raycast, `mesafe = min(0.45, çarpma-0.1)` ile parça duvara yaklaşınca geri çekilsin; (b) asıl çözüm: elde tutulan nesne ayrı görsel katmanda (`layers`) ve aynı FOV'lu ikinci kamerayla `SubViewport`'ta çizilip ana görüntünün üstüne bindirilsin (viewmodel) → hiçbir zaman duvara girmez; (c) elde tutarken `RigidBody3D` yerine sade `Node3D` görsel kopya, bırakınca fizik gövdesi geri gelsin; (d) parça başına tutma açısı/ofset (GPU, PSU tuhaf duruyor) | M | Önce (c) ile oyunda test edilip gecikmenin kaynağı doğrulanmalı |
| 0.4 ✅ | **Ödeme parça maliyetine göre**: tamir ücreti = parça fiyatı + işçilik (zorluk × taban) — şu an CPU tamiri ile RAM tamiri aynı parayı veriyor | S | `job_manager.gd:232` |
| 0.5 ✅ | **Kayıt hataları**: ikinci el `sold` bayraklarını kaydet; saati geri yükle (veya gün ortası kaydı kaldır ama net söyle) | S | `game.gd:559,627`, `used_market.gd` |
| 0.6 ✅ | Başarısız teslimde **neden** başarısız olduğunu söyle (Computer Repair Shop'un en çok eleştirilen kusuru) | S | |

## Faz 1 — Veri altyapısı (her şeyin temeli)

Amaç: yeni parça/arıza/iş eklemek = bir `.tres` dosyası eklemek.

| # | İş | Boyut |
| --- | --- | --- |
| 1.1 | `PartDef` Resource: `id, kategori, marka, model, tier, taban_fiyat, specs{}, compat{soket, ram_tipi, tdp, watt, uzunluk...}, model_builder_id, tutma_ofseti` | M |
| 1.2 | `FaultDef` Resource: `id, cihaz_türleri, etkilenen_kategori, belirtiler (bip deseni, ekran durumu, LED), müşteri_cümleleri[], zorluk, ağırlık, min_gün/min_itibar, ücret_formülü` | M |
| 1.3 | `JobTemplate` Resource: tamir, yükseltme, sıfırdan toplama, satış, veri kurtarma, temizlik, kurulum; kısıtlar + ödüller | M |
| 1.4 | `game.gd`'yi böl: `Economy`, `Inventory`, `Orders`, `SaveSystem` (sürümlü şema + migration), `Day/Reputation`, `Staff` — `Game` ince bir cephe kalsın | L |
| 1.5 | Raf / tezgâh / personel rota noktaları `Marker3D` olsun (`staff.gd:13-24` sabit koordinatları kalksın) | M |
| 1.6 | Başsız test betikleri: JobDirector dağılımı, uyumluluk kuralları, kayıt-yükleme gidiş-dönüşü | M |

## Faz 1.5 — Tezgâh modu ve çoklu iş (oynanışın kalbi) ⭐

Şu an tamir "uzaktan bakıp E'ye basarak" yapılıyor. PC Building Simulator'da asıl oyun tezgâhta, kasanın etrafında
geçiyor. Bu faz oyunu "prototip"ten "oynanabilir oyun"a taşıyan en önemli adım.

**Tezgâh modu**

| # | İş | Boyut |
| --- | --- | --- |
| 1.5.1 | Tezgâha `E` → kamera yumuşakça tezgâh görünümüne geçer, fare serbest kalır; `Esc`/`Tab` ile çıkış | M |
| 1.5.2 | Kasanın etrafında **yörünge kamera**: sağ tık sürükle döndür, tekerlek yakınlaştır, kasayı yan yatır / çevir | M |
| 1.5.3 | Fareyle parçaya tıkla → söküm; parça **tezgâh tepsisine** iner. Tepsiden sürükle → yuvaya bırak; uyumlu yuvalar yeşil, uyumsuzlar kırmızı yanar (hayalet önizleme) | L |
| 1.5.4 | Söküm sırası: yan kapak vidaları → kapak → GPU braketi vidası → GPU kilidi → GPU (Faz 3.5 tornavida ile) | M |
| 1.5.5 | Parçanın üstüne gelince küçük bilgi kartı: ad, durum, spec, (teşhis aleti varsa) sağlık | S |
| 1.5.6 | Tezgâh yan paneli: iş fişi (müşteri ne istedi), yapılacaklar listesi, tepside duran parçalar | M |
| 1.5.7 | Laptop ve telefon için de aynı mod (yakın plan, alt kapak vidaları, ters çevirme) | M |
| 1.5.8 | Birinci şahıs modda da tamir yapılabilsin ama tezgâh modu varsayılan ve rahat yol olsun | S |

**Çoklu iş**

| # | İş | Boyut |
| --- | --- | --- |
| 1.5.9 | Kasalar **taşınabilir nesne** olsun: müşteri tezgâha bırakır, oyuncu alıp tezgâha / rafa koyar | M |
| 1.5.10 | Her kasaya **iş fişi** yapışık (fiş no, müşteri, teslim günü); fişe bakınca iş detayı | S |
| 1.5.11 | **Bekleyen işler rafı**: gelen ve bitmiş PC'ler burada durur; "hazır" olanlar yeşil etiket | M |
| 1.5.12 | Aynı anda 3-5 aktif iş; müşteri PC'yi bırakıp gider, **ertesi gün(ler) almaya gelir** (Faz 6.1 ile birlikte) | L |
| 1.5.13 | `job_manager.gd` tek `pc` / tek `customer` değişkeninden **iş listesine** geçsin (şu an mimari tek işe kilitli) | L |
| 1.5.14 | Teslim: müşteri tezgâha gelir, fiş numarasını söyler, raftan doğru kasayı verirsin; yanlış kasa = rezalet 😄 | S |
| 1.5.15 | HUD'da aktif işler listesi (fiş no, kalan süre, durum); servis fişi tek iş yerine liste olsun | M |

## Faz 2 — Gerçek parça çeşitliliği ve uyumluluk

Hayali markalarla (lisans derdi yok; PCBS1 de bütçe parçalarda hayali marka kullanıyor), gerçek dünya kurallarıyla.

| # | İş | Boyut |
| --- | --- | --- |
| 2.1 | **Anakart** parça + yuvası: `soket` (AM4, AM5, LGA1700, LGA1851), `ram_tipi` DDR4/DDR5, `ram_yuva`, `form_faktör` ATX/mATX/ITX, `m2_yuva`, `pcie_nesli`, çipset | L |
| 2.2 | CPU çeşitleri (soket, çekirdek, TDP, dahili grafik var/yok — dahili grafiksiz CPU + GPU'suz kasa = görüntü yok arızası) | M |
| 2.3 | RAM: DDR4/DDR5, kapasite 8/16/32, hız; **çentik farkı** → yanlış nesil yuvaya fiziksel olarak girmesin; tek/çift kanal | M |
| 2.4 | Depolama: SATA SSD, NVMe M.2, HDD (SMART sağlığı) | M |
| 2.5 | PSU watt (450/550/750/1000) + konnektörler (6/8-pin, 12VHPWR); **toplam watt hesabı** | M |
| 2.6 | Yeni yuvalar: CPU soğutucu (hava/AIO, yükseklik), kasa fanları, CMOS pili | M |
| 2.7 | Kasa çeşitleri: form faktör, maks. GPU uzunluğu, maks. soğutucu yüksekliği | M |
| 2.8 | `Compatibility.check(slot, parça, sistem)` → `{ok, sebep}`; yuvaya bakınca ipucu: "Bu anakart AM5, işlemci AM4" · ParçaNet'te "Uyumluluk" düğmesi · canlı watt göstergesi | M |
| 2.9 | İş üretici asla uyumsuz başlangıç sistemi yaratmasın (PCBS2 v1.6 dersi) — ama bazı işler **bilerek** uyumsuzluk içersin (müşteri yanlış RAM almış vb.) | S |

## Faz 3 — Arıza ve teşhis derinliği

Hedef: 14 sonuç → **30+ arıza**, çoklu arıza, teşhis gerçekten bir bulmaca.

**Arıza havuzu (önerilen):**

- *Donanım:* PSU ölü · PSU yetersiz watt (yükte kapanma) · RAM bozuk (tek modül, çift RAM'de hangisi?) · RAM yuvaya tam oturmamış · CPU bozuk · CPU pinleri eğik (AM4) / soket pini eğik (LGA) · GPU bozuk · GPU artefakt (VRAM) · GPU güç kablosu takılı değil · SSD/HDD ölü · HDD bad sector (yavaşlık, SMART) · anakart ölü · şişmiş kondansatör · CMOS pili bitik (saat/BIOS sıfırlanıyor) · fan ölü · toz · kurumuş termal macun · 24-pin/CPU 8-pin gevşek · ön panel güç düğmesi kablosu çıkmış
- *Yazılım:* virüs/reklam yazılımı · bozuk işletim sistemi (format + kurulum USB) · sürücü sorunu · yanlış boot sırası (BIOS) · XMP kapalı / RAM düşük hızda · BIOS güncellemesi gerekiyor (yeni CPU eski anakartta) · disk dolu
- *Laptop:* klavye, menteşe, şarj soketi, fan/toz, Wi-Fi kartı, sıvı teması
- *Telefon:* kamera, hoparlör/mikrofon, arka cam, sıvı teması, yazılım (format)

| # | İş | Boyut |
| --- | --- | --- |
| 3.1 | Yukarıdaki havuzu `FaultDef` olarak ekle, zorluk ve kilit seviyesine göre yay | L |
| 3.2 | **Çoklu arıza** (toz + ölü fan, virüs + ölen disk) — `diagnose()` artık listeyi döndürsün | M |
| 3.3 | **Debug LED'leri varsayılan olmaktan çıksın**: ucuz anakartlarda yok, sadece bip kodu; pahalı anakartlarda var. Duvar rehberi bip kodlarına dönüşsün | S |
| 3.4 | **Teşhis aletleri** (geliştirme olarak alınır): PSU test cihazı, multimetre, RAM test USB'si, POST kartı, termal kamera, disk SMART aracı, antivirüs USB, Windows kurulum USB'si, yedek "test parçaları" (bilinen sağlam RAM/PSU ile değiştirerek eleme) | L |
| 3.5 | **Tornavida ve vida mekaniği** (şu an masada süs): yan kapak, GPU braketi, M.2 vidası. İsteğe bağlı otomatik vida geliştirmesi (PCBS2 QoL) | M |
| 3.6 | **Kablo bağlantıları**: 24-pin, CPU 8-pin, PCIe güç, SATA — takılı/gevşek durumu | M |
| 3.7 | Kabloları düzenleme ve temizlik kalitesi müşteri memnuniyetine/bahşişe etki etsin (PCBS2, ReStory) | S |

## Faz 4 — Depo ve envanter

| # | İş | Boyut |
| --- | --- | --- |
| 4.1 | **Parça kimliği**: `InventoryItem {uid, part_id, durum %, köken (yeni/muadil/ikinci el/sökülmüş), gizli_kusur}` — sayaçlar kalksın | M |
| 4.2 | Kargo kutusu açılınca parçalar **fiziksel olarak** çıksın (parça kutuları) | M |
| 4.3 | **Depo rafları**: kategori bölmeli raflar, parçayı istediğin bölmeye koy; satın alınabilir ek raf | M |
| 4.4 | **Tezgâh parça tepsisi**: sökülen parçalar karışmasın, iş başına tepsi | S |
| 4.5 | Müşterinin eski parçaları: geri ver / satın al / hurdaya at → ikinci el olarak sat (ekonomi döngüsü) | M |
| 4.6 | Yerdeki ve raftaki parçalar kaydedilsin | M |
| 4.7 | İsteğe bağlı "otomatik yerleştir" (Supermarket Sim'de oyuncular bunun için mod yazmış) | S |

## Faz 5 — Dükkân işletim sistemi ("TamirOS")

Masadaki monitörde `SubViewport` ile çalışan gerçek bir masaüstü (`monitor.gd` zaten bu yöntemi kullanıyor).
Monitöre `E` ile bakınca kamera ekrana yaklaşır, fare serbest kalır.

| # | İş | Boyut |
| --- | --- | --- |
| 5.1 | Çerçeve: masaüstü, görev çubuğu, saat, pencere aç/kapa/sürükle, `OSApp` taban sınıfı | L |
| 5.2 | Mevcut sekmeleri uygulamaya çevir: ParçaNet, Kargo Takip, Geliştirmeler, İkinci El, Personel, Dükkân İstatistik | M |
| 5.3 | **E-posta / İş Talepleri**: online siparişler (kargo ile gelen PC, birkaç gün süreli), müşteri mesajları, tedarikçi kampanyaları | M |
| 5.4 | **Envanter** uygulaması (Faz 4 ile): filtre, sırala, hangi rafta | M |
| 5.5 | **Muhasebe**: gelir/gider grafiği, faturalar, kira, kredi | M |
| 5.6 | **Fiyat teklifi**: müşteriye tamir fiyatı ver; fazla pahalıysa reddeder, ucuzsa zarar (pazarlık) | M |
| 5.7 | **Tezgâhtaki PC'nin işletim sistemi** (müşteri PC'si): BIOS ekranı (boot sırası, XMP, sıcaklık), antivirüs, benchmark, disk sağlığı, format/kurulum — teşhisin yarısı burada (PCBS2'de böyle) | L |
| 5.8 | Kargo hızı seçenekleri: standart / ertesi gün / ekspres ("bekle mi, öde mi" kararı) | S |

## Faz 6 — Müşteri, sipariş ve gün sistemi

| # | İş | Boyut |
| --- | --- | --- |
| 6.1 | **Kuyruk** ve aynı anda birden fazla iş: müşteri PC'yi bırakır, fiş alır, **sonraki gün(ler)** almaya gelir | L |
| 6.2 | İş takvimi: teslim tarihleri gün bazında, HUD'da ve OS'te takvim | M |
| 6.3 | **Kısmi bilgi**: müşteri belirtiyi söyler, sebebi değil; ama zorunlu şartlar (bütçe, "oyun oynayacağım") net yazılsın — "gizli kontrol listesi" şikâyetinden kaçın | S |
| 6.4 | Müşteri tipleri: aceleci, cimri, teknik bilen, yaşlı amca, oyuncu çocuk, esnaf; sabır, pazarlık, bahşiş farkı | M |
| 6.5 | **Daimi müşteriler ve küçük hikâyeler** (ReStory'nin en sevilen yanı): aynı müşteri tekrar gelir, önceki işini hatırlar | L |
| 6.6 | Yıldızlı değerlendirme + yorumlar (OS'te "Harita yorumları") | S |
| 6.7 | İş türleri: sıfırdan toplama (bütçe + hedef performans), yükseltme, temizlik, veri kurtarma, format + kurulum, laptop ekran, telefon batarya, toptan (ofis 5 PC) | M |
| 6.8 | Gün ritmi: sabah hazırlık → gündüz müşteri → akşam atölye → gece Z raporu (mevcut rapor genişletilsin) | S |

## Faz 7 — İlerleme ve ekonomi

| # | İş | Boyut |
| --- | --- | --- |
| 7.1 | **XP / seviye merdiveni** (PCBS2 şablonu): Sv2 kablo düzeni · Sv3 toz aleti · Sv4 termal macun işleri · Sv5 ikinci tezgâh + kurulum USB · Sv7 ileri teşhis · Sv10 overclock + dükkân büyütme · Sv12 sıvı soğutma … | M |
| 7.2 | **Lisanslar**: laptop tamiri, telefon tamiri, anakart lehim işleri ayrı ayrı açılsın (ReStory) | S |
| 7.3 | İkinci/üçüncü tezgâh (paralel iş) | M |
| 7.4 | **Yenilenmiş PC satışı**: hurda/ikinci el parçalardan PC topla, vitrinde sat | M |
| 7.5 | Kredi / borç, internet faturası (online işleri açar) | S |
| 7.6 | Uzun vadeli hedefler: dükkân büyütme, şube, kupa/başarımlar — "geç oyun sıkıcılığı" her rakipte en büyük şikâyet | M |
| 7.7 | Personel genişlemesi: kuyruk olunca teknisyen gerçekten işe yarasın, rolleri sınırlı olsun (TCG: işçiler her şeyi yapamaz) | M |

## Faz 8 — Cila

| # | İş | Boyut |
| --- | --- | --- |
| 8.1 | Serbest kurulum (sandbox) modu | S |
| 8.2 | Öğretici: ilk 3 iş senaryolu ve açıklamalı | M |
| 8.3 | Yerelleştirme altyapısı (`tr()` + çeviri dosyaları) | M |
| 8.4 | Ses: bip kodları, fan sesi (tozlu fan farklı ses), tornavida | S |
| 8.5 | Kayıt güvenliği: yedek kayıt, bozuk kayıttan kurtarma (PCBS2'de kayıt kaybı en büyük güven kırıcı) | S |

## Ekstra oynanış fikirleri

Araştırmadan ve tür bilgisinden çıkan, oyunu "bir tur daha" dedirtecek fikirler. Yanlarında hangi faza girdikleri yazıyor.

**Müşteriyle ilişki**
- **Ek arıza onayı** (Faz 6): söktün, anakart da gitmiş → müşteriyi ara: "Abi anakart da yanmış, 1.500 TL daha tutar, yapayım mı?" Onaylar, reddeder ya da pazarlık eder. Çok gerçekçi ve her işe karar katıyor.
- **Ek satış (upsell)** (Faz 6): "Hazır açmışken SSD'ye geçelim mi, 10 kat hızlanır" → kabul ederse ekstra kâr, ısrar edersen itibar düşer.
- **Veri yedeği** (Faz 3/5): formattan önce müşterinin verisini yedeklemezsen ve "düğün fotoğraflarım nerede?!" → büyük itibar kaybı. Yedekleme diski bir alet olsun.
- **Geri dönen arıza** (Faz 6): yarım yamalak tamir (ucuz muadil PSU, macun sürmeden) → müşteri 2-3 gün sonra kızgın geri gelir. Mevcut garanti sistemi bunun temeli.
- **Şüpheli müşteriler** (Faz 6): "garantiden" diye kendi bozduğu parçayı getiren, çalıntı olabilecek laptop satmak isteyen, şifresini unuttuğu telefonu açtırmak isteyen müşteri → ahlaki seçimler, polis/itibar sonucu.
- **Müşteri telefonla durum sorar** (Faz 5/6): masadaki telefon çalar, "abi benimki ne oldu?"; geç kalan işlerde baskı.
- **Kurumsal sözleşmeler** (Faz 7): mahalledeki internet kafe, okul, muhasebe bürosu → haftalık bakım anlaşması, düzenli gelir, toplu iş (5 PC birden).

**Ekonomi ve dünya**
- **Piyasa olayları** (Faz 7): sabah gazetesi / haber uygulaması: "Kripto patladı, ekran kartı fiyatları %40 arttı", "çip krizi", "okullar açılıyor → öğrenci laptop işleri artar", "bayram öncesi telefon ekranı kırılan çok". Mevcut piyasa çarpanı bunun temeli.
- **Elektronik hurda kutusu** (Faz 4/7): hurdacıdan kilo ile kasa al, içinden çıkan sağlam parçaları test et, yenileyip sat.
- **Yenilenmiş PC vitrini** (Faz 7.4): kendi topladığın PC'lere fiyat etiketi koy, vitrinde sat; fiyat çok yüksekse satılmaz.
- **Benchmark hedefli toplama işleri** (Faz 6): "15.000 TL bütçe, şu oyunda 60 FPS istiyorum" → bütçe ve performans bulmacası.
- **Zaman hızlandırma** (Faz 6): kargo / iş beklerken "dükkânı kapat ve uyu" ya da saati 2x hızlandır.

**Atölye ve aletler**
- **Lehim istasyonu** (Faz 3/7): şişmiş kondansatör değişimi, şarj soketi lehimi — basit bir mini oyun (zamanlama / sıcaklık).
- **Overclock ve sıcaklık testi** (Faz 5.7): müşteri "biraz hızlandır" der, stres testinde çökmeden ne kadar zorlayabilirsin.
- **Dükkân temizliği ve düzeni** (Faz 7): toz, dağınık parçalar, çöp → müşteri memnuniyetini etkiler; temizlikçi personel.
- **Dükkân dekorasyonu** (Faz 7): poster, bitki, RGB şerit, koltuk → itibar/müşteri sabrı bonusu (PCBS2'de çok sevilen kısım).

**Motivasyon**
- **Başarımlar ve istatistikler** (Faz 7.6): "100 PSU değiştirdin", "hiç geri dönmeyen 30 iş".
- **Hikâye dalı / ana hedef** (Faz 7.6): örneğin dükkânı devraldığın amcanın borcunu ödemek, mahallenin bir numaralı bilgisayarcısı olmak, rakip zincir mağazayla rekabet.
- **Fotoğraf modu** (Faz 8): topladığın PC'nin fotoğrafını çek, dükkân panosuna as.

## Faz 9 — Sonra: Sokak / mahalle

Mahalle, komşu esnaf, hurdacı, kargo şubesi, dükkân dışı aktiviteler. Ayrıca planlanacak.

---

## Önerilen sıra (kısa)

1. **Faz 0** — hemen (tekrar eden işler, elde tutma, build hatası)
2. **Faz 1** — altyapı; bundan sonra içerik eklemek ucuzlar
3. **Faz 1.5** — tezgâh modu + çoklu iş (oyunu oynanabilir yapan adım)
4. **Faz 2 + 3** — parça çeşitliliği ve arıza derinliği (oyunun kalbi)
5. **Faz 4** — depo
6. **Faz 5** — TamirOS
7. **Faz 6 + 7** — müşteri/sipariş/ilerleme
8. **Faz 8**, sonra **Faz 9** sokak

## Kaynaklar (araştırmadan seçme)

- PC Building Simulator 2 uyumluluk / ilerleme / teşhis: ludo.guide PCBS2 rehberleri, pcbuildingsim.com v1.6 & v1.15 yama notları
- PC Building Simulator: Wikipedia, Steam tartışmaları (teşhis ipuçları), vaporlens özetleri
- Computer Repair Shop: GameGrin ve GamesHorizon incelemeleri (eleştirilen kusurlar)
- ReStory: Prima Games incelemesi, Pixel Nitro
- Supermarket Simulator / TCG Card Shop Simulator: Steam tartışmaları, Nexus StoreDelivery modu

> Not: Kaynakların bir kısmı ikincil (rehber siteleri, özetler); seviye numaraları gibi ayrıntılar yaklaşık kabul edilmeli.
