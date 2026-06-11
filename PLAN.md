# Yeni Finans Uygulaması — Mimari Plan

> Marka adı önerisi: **Nirengi** (birden çok ölçümden tek referans nokta = çok motor → tek karar). Alternatif: Mihenk, Pusula, Rasat. Koda gömülmedi, değiştirilebilir.
> Klasör/çalışma adı: `yeni-finans-app`. Çekirdek modülü: `Cekirdek` (nötr, marka bağımsız).
> ⛔ Argus veya Argus'a ait HİÇBİR isim (motor/sınıf/marka) kullanılmayacak. Tamamen özgün isimler.
> Durum: **v0.1 çekirdek çalışıyor** (Swift paketi, 5/5 test geçti).
> Tarih: 2026-06-09

## Özgün motor isimleri — GEZEGEN / ROMA TEMASI (Argus Yunan tanrı temasından ayrı)
10 motor = 10 gök cismi. (Tip adları ASCII, ekran metni Türkçe.)
| Rol | Gezegen | Tip adı | Neden |
|---|---|---|---|
| Teknik momentum | **Merkür** ✅ (v0.1) | `Merkur` | En hızlı → anlık hareket |
| Fiyat tahmini | **Neptün** | `Neptun` | Derinlik/öngörü |
| Makro rejim | **Jüpiter** | `Jupiter` | En büyük → genel resim |
| Temel/kalite | **Satürn** | `Saturn` | Yapı, disiplin, sağlamlık |
| Haber/duygu | **Venüs** | `Venus` | Duygu/çekim → sentiment |
| Sektör rotasyonu | **Uranüs** | `Uranus` | Değişim/devrim → rotasyon |
| Ağırlık öğrenme | **Ay** | `Ay` | Evreler → adapte olan öğrenme |
| Faktör/smart beta | **Mars** | `Mars` | Strateji, güç faktörleri |
| Meta kalibrasyon | **Güneş** | `Gunes` | Merkez üst-akıl |
| Geri dönüş adayı | **Plüton** | `Pluton` | Yeniden doğuş → turnaround |

## v0.1 — YAPILDI (Cekirdek/ Swift paketi)
- `Models.swift`: Mum, Katki, Karar (al/tut/sat/yetersizVeri), Motor protokolü.
- `Indicators/Gostergeler.swift`: SMA/EMA/RSI(Wilder)/MACD/ATR/ADX/CCI — saf, özgün kod (kamuya açık matematik).
- `Engines/Merkur.swift`: (teknik analiz) Orion'un MANTIĞI yeniden yazıldı (kod kopyalanmadı): Trend (SMA20/50/200 dizilim+konum+ceza, MACD, opsiyonel RS), Momentum (RSI haritalama + likidite), Volatilite (BB squeeze + ATR%); ADX rejim-duyarlı ağırlıklar; sinerji bonusu; kademeli verdict. degerlendir([Mum])→Katki; degerlendir(_,endeks:)→zengin Sonuc.
- `Konsey.swift`: motor katkılarını güven×ağırlık ile harmanlar → skor + karar + gerekçeler.
- `demo` çalıştırılabilir + `CekirdekTests` (5 test, hepsi geçti).
- Çalıştırma: `cd Cekirdek && swift test` / `swift run demo`. **Xcode gerekmez.**

## BIST gecikmeli veri kaynakları (madde 3 — araştırıldı)
- Resmi: Borsa İstanbul lisanslı veri satıcıları (gecikmeli lisans ucuz).
- Banka API: Yapı Kredi (BIST endeks), Vakıf Bank (BIST 30/100 fiyat) — kısıtlı kapsam.
- Foreks: UzmanPara/Bigpara'ya 15dk gecikmeli besleyen kaynak — lansman için gerçekçi.
- MVP: gecikmeli veri + "15 dk gecikmelidir" etiketi; ölçeklenince gerçek-zamanlı lisans.


## 0. Temel ilkeler
- **Argus'tan fikir/kavram alınır, KOD ALINMAZ.** Aynı mantık, sıfırdan ve daha temiz yazılır. (Hukuki temizlik: orijinal Argus repo lisanssız = "tüm hakları saklı"; kodu kopyalamak yasak, kavram serbest.)
- **Dikey dilim (vertical slice):** her aşama çalışan, gösterilebilir bir ürün bırakır.
- **Lansman = 15 dk gecikmeli BIST verisi.** "Gerçek-zamanlı değildir" + "yatırım tavsiyesi değildir" en baştan. Gerçek-zamanlı BIST lisansı (pahalı) gelir oluşunca eklenir.
- **Argus'un derdi taşınmaz:** çoklu durum kaynağı, ölü kod, geçiş kalıntısı YOK. Tek durum yüzeyi baştan.
- Öncelik: **BIST + Türkçe** (pazardaki asıl boşluk). Global (US) sonra eklenir.

## 1. Teknik yığın
- iOS 17+, Swift, SwiftUI, SwiftData (yerel kayıt), Keychain (anahtarlar).
- **Tek durum yüzeyi:** `AppState` (Argus'taki "3 ayrı watchlist" hatasına düşülmeyecek).
- Sunucu: Python / FastAPI (BIST + makro + beyin; ileride global aggregator).

## 2. Klasör / modül sınırları
```
App/            → giriş noktası, AppState, DI
DesignSystem/   → tema, tokens, ortak bileşenler (TEK renk kaynağı)
Data/
  ├─ Providers/ → BIST (gecikmeli), makro (TCMB/EVDS)
  ├─ Cache/     → disk + kalıcı snapshot (anında açılış)
  └─ Models/    → Quote, Candle, Symbol...
Engines/        → her motor BAĞIMSIZ (girdi → skor), saf fonksiyon gibi
  ├─ Technical  (Orion karşılığı: momentum)
  ├─ Forecast   (Prometheus karşılığı: tahmin)
  ├─ Macro      (Aether karşılığı: rejim)
  └─ ...
Council/        → orkestrasyon + karar motoru + ağırlıklar
Learning/       → sicil (forward-test) + öğrenen ağırlık
Features/       → ekranlar (Liste, Detay, Karne, Ayarlar)
```
**Kural:** Engine'ler birbirini ve UI'ı TANIMAZ; sadece `Council` onları çağırır. Argus'taki en büyük karmaşa böyle baştan engellenir.

## 3. Veri katmanı (BIST)
- Tek sorumluluk: `MarketDataStore` → fetch + cache + yayın.
- **Açılışta anında fiyat:** `Application Support`'a kalıcı snapshot (iOS `Caches`'i silse bile durur — Argus'ta acıyla öğrenilen ders).
- BIST gecikmeli veri kaynağı + TCMB/EVDS makro.

## 4. Motor ekleme sırası (dikey dilim yol haritası)
| Faz | Motor | Çıktı |
|---|---|---|
| v0.1 | **Technical** (momentum) | Tek skor + 1 liste ekranı + 1 detay ekranı |
| v0.2 | **Forecast** (Holt tahmin) | Bileşik rozet (örn. 0.6·teknik + 0.4·tahmin) |
| v0.3 | **Macro** (rejim eğimi) | Sinyale makro tilt |
| v0.4 | **Council** | Çoklu motor → tek karar (Al / Tut / Sat) + gerekçe |
| v0.5 | **Learning + Sicil** | Forward-test + isabet karnesi |
| v0.6 | Haber / LLM (opsiyonel) | Duygu skoru |

## 5. Council (asıl beyin — zor kısım)
- Her motor `Contribution(skor, güven, ağırlık)` döndürür.
- Council ağırlıklı harman → verdict + **açıklanabilir gerekçe** ("Karar Patikası" — şeffaflık = farkımız).
- Ağırlıklar başta sabit; sonra Learning besler.

## 6. Learning + Sicil (farkımızı yaratan)
- Tahmin kaydet → N gün bekle → gerçek fiyatla kıyasla → isabet işaretle → ağırlığı güncelle.
- **Sunucuda** çalışır (7/24; telefon kapalıyken bile birikir — "Argus Beyni" dersi).
- Kullanıcıya "karne" olarak gösterilir → güven.

## 7. Sunucu
- FastAPI uçları: `/bist/quote`, `/bist/history`, makro uçları, `/forecasts`, `/trackrecord`.
- Cron'lu beyin: günlük tahmin + sicil olgunlaştırma.
- Başta tek küçük VPS (Hetzner/DO).

## 8. Legal kancalar (baştan)
- İlk açılış: disclaimer + "yatırım tavsiyesi değildir" onayı.
- Her sinyal ekranında kalıcı uyarı.
- Gecikmeli veri etiketi.
- SPK riski için tek seferlik avukat danışmanlığı.

## 9. Maliyet özeti (referans)
- Kuruluş (nakit, geliştirmeyi kendimiz yaparsak): ~25.000–70.000 TL.
- Aylık — Beta: ~$60–110 · MVP (gecikmeli veri, 100-500 abone): ~$300–800 · Ciddi (gerçek-zamanlı BIST): ~$1.800–7.500.
- Bütçeyi patlatan kalem: **gerçek-zamanlı BIST lisansı** → lansmanda gecikmeli veriyle kaçınılır.
- Kâra geçiş: ~₺149/ay abonelikte ~250-300 ödeyen abone (MVP maliyetinde).

## Sonraki adım
- [ ] Özgün marka adı belirle (Argus değil)
- [ ] v0.1 iskeleti kur: boş Xcode projesi + klasör yapısı + Technical motoru + Liste/Detay ekranı
- [ ] BIST gecikmeli veri kaynağını netleştir
