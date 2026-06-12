import Foundation

/// Neptün — fiyat tahmini motoru. (Argus "Prometheus" mantığı, sıfırdan yazıldı.)
/// Sönümlü Holt (Damped Holt's Linear) + walk-forward parametre kalibrasyonu +
/// tahmin aralıkları + sanity clamp (volatilite tavanı + RSI vetosu) + maliyet-bilinçli öneri.
/// (Yöntem kamuya açık zaman serisi tahmini — kod özgün.)
public struct Neptun: Motor {
    public let isim = "Neptün"
    public let profil: PiyasaProfili
    /// Ufku veri uzunluğuna göre seçmek yerine sabitle (kıyas/araştırma için).
    public let sabitUfuk: Int?

    public init(profil: PiyasaProfili = .bist, sabitUfuk: Int? = nil) {
        self.profil = profil
        self.sabitUfuk = sabitUfuk
    }

    // MARK: - Zengin sonuç

    public enum Trend: String, Sendable { case gucluYukari, yukari, notr, asagi, gucluAsagi }
    public enum Oneri: String, Sendable { case al = "Al", tut = "Tut", sat = "Sat" }

    public struct Tahmin: Sendable {
        public let suankiFiyat: Double
        public let tahminFiyat: Double
        public let degisimYuzde: Double      // beklenen % değişim
        public let guven: Double             // 0..100
        public let trend: Trend
        public let oneri: Oneri
        public let ufukGun: Int
        public let mape: Double              // walk-forward hata
        public let yonIsabeti: Double        // 0..1
        public let altBant: [Double]
        public let ustBant: [Double]
        public let tahminler: [Double]
        public let gerekce: String
    }

    // MARK: - Risk bekçisi
    //
    // 2026-06 kıyası (BIST30×2y, n=1044): Neptün yön edge'i üretemiyor (<%50) ama
    // bantları isabetli (%91 kapsama) ve geniş bant mayınlı bölgeyi ayırıyor
    // (geniş tertil: ort −0.52 / en kötü −48 vs dar: +0.32 / −15). Merkür Al
    // sinyallerini bu frenle süzmek en kötü işlemi −48→−15'e indirdi.
    // Bu yüzden Neptün'ün asıl görevi yön oyu değil RİSK FRENİ.

    public enum RiskSeviyesi: String, Sendable { case dusuk = "Düşük", orta = "Orta", yuksek = "Yüksek" }

    public struct Risk: Sendable {
        public let skor: Double             // 0-100, yüksek = mayınlı
        public let seviye: RiskSeviyesi
        public let frenCarpani: Double      // Konsey skorunu nötre çeken çarpan (0.55...1)
        public let kotuSenaryoYuzde: Double // alt bant: ufuk sonunda beklenen en kötü %
        public let ufukGun: Int
        public let gerekce: String
        public let tahmin: Tahmin           // bant/teşhis detayları (UI grafiği için)
    }

    /// Risk değerlendirmesi. Bileşenler hep göreli (kâğıdın kendi geçmişine göre):
    /// 1) model belirsizliği — bandın günlük eşdeğeri, kâğıdın olağan oynaklığının kaç katı;
    /// 2) oynaklık rejimi — kısa vol kendi uzun voluna göre şişmiş mi;
    /// 3) likidite — ölü bar oranı + hacim kuruması.
    /// Limit serisi/kur şoku bayrakları VETO DEĞİL (kıyas: bayraklılar ort +0.91 getirdi) —
    /// güven/bant üzerinden zaten işliyor, burada sadece gerekçe notu.
    public func riskDegerlendir(_ mumlar: [Mum], baglam: Baglam? = nil) -> Risk? {
        guard let t = tahminEt(mumlar, baglam: baglam) else { return nil }
        let sirali = mumlar.sorted { $0.tarih < $1.tarih }
        let fiyatlar = Array(sirali.map(\.kapanis).suffix(300))
        guard let son = fiyatlar.last, son > 0,
              let alt = t.altBant.last, let ust = t.ustBant.last else { return nil }

        let h = Double(max(1, t.ufukGun))
        // Bant genişliği → günlük eşdeğer belirsizlik (kıyasın en güçlü ayracı).
        let gunlukBant = (ust - alt) / son * 100 / (2 * h.squareRoot())
        let kisaVol = max(0.3, volYuzde(fiyatlar, pencere: 20))
        let uzunVol = max(0.3, volYuzde(fiyatlar, pencere: 120))

        let belirsizlikOran = gunlukBant / kisaVol            // ~1.5 dar, ~3+ geniş bölge
        let belirsizlik = min(55, max(0, (belirsizlikOran - 1.2) * 35))
        let rejim = min(30, max(0, (kisaVol / uzunVol - 1) * 60))
        let likidite = likiditeCezasi(Array(sirali.suffix(300)))
        let skor = min(100, belirsizlik + rejim + likidite)

        let seviye: RiskSeviyesi = skor < 30 ? .dusuk : (skor < 55 ? .orta : .yuksek)
        // Fren: riskle doğrusal, [0.55, 1] — tam risk bile diğer motorları söndürmez, kısar.
        let fren = max(0.55, 1 - skor / 100 * 0.45)
        let kotu = (alt - son) / son * 100

        var parcalar: [String] = []
        if belirsizlik >= 15 { parcalar.append("bant geniş") }
        if rejim >= 10 { parcalar.append("oynaklık şişkin") }
        if likidite >= 5 { parcalar.append("likidite zayıf") }
        var gerekce = String(format: "%@ risk · kötü senaryo %%%.1f (%d gün)", seviye.rawValue, kotu, t.ufukGun)
        if !parcalar.isEmpty { gerekce += " · " + parcalar.joined(separator: ", ") }

        return Risk(skor: skor, seviye: seviye, frenCarpani: fren,
                    kotuSenaryoYuzde: kotu, ufukGun: t.ufukGun, gerekce: gerekce, tahmin: t)
    }

    // MARK: - Bağlam (piyasa geneli)

    /// Neptün'ün hisse dışına açılan gözü: endeks rejimi + kur şoku.
    /// Hisse fiyat geçmişi piyasa genelindeki kırılmayı gecikmeli yansıtır;
    /// bağlam bu kör noktayı güven/bant üzerinden kapatır. Opsiyonel: verilmezse
    /// motor eskisi gibi yalnız fiyatla çalışır.
    public struct Baglam: Sendable {
        public let endeks: [Mum]    // XU100 günlük
        public let usdtry: [Mum]    // USDTRY=X günlük

        public init(endeks: [Mum] = [], usdtry: [Mum] = []) {
            self.endeks = endeks
            self.usdtry = usdtry
        }
    }

    /// Bağlamın tahmine etkisi (hepsi göreli — serinin kendi oynaklığına göre z-skoru).
    private struct BaglamEtkisi {
        var guvenCarpani = 1.0
        var bantCarpani = 1.0
        var notlar: [String] = []
    }

    private func baglamEtkisi(_ baglam: Baglam?, sonTarih: Date, tahminYonu: Double) -> BaglamEtkisi {
        var etki = BaglamEtkisi()
        guard let b = baglam else { return etki }

        // Endeks rejimi: XU100'ün 20 günlük getirisi kendi oynaklığına göre kaç σ?
        // Sert düşüş rejiminde yukarı tahmin (ve tersi) hissenin geçmişinden gelmez — kırp.
        if let z = zSkor(b.endeks.filter { $0.tarih <= sonTarih }.map(\.kapanis), pencere: 20) {
            if z < -1, tahminYonu > 0 { etki.guvenCarpani *= 0.78; etki.notlar.append("endeks düşüş rejimi") }
            if z > 1, tahminYonu < 0 { etki.guvenCarpani *= 0.85; etki.notlar.append("endeks yükseliş rejimi") }
        }

        // Kur şoku: USD/TRY 5 günlük değişimi 2σ'yı aşmışsa belirsizlik rejimi —
        // yön ne olursa olsun güven kırpılır, tahmin aralığı genişler.
        if let z = zSkor(b.usdtry.filter { $0.tarih <= sonTarih }.map(\.kapanis), pencere: 5), abs(z) > 2 {
            etki.guvenCarpani *= 0.8
            etki.bantCarpani = 1.3
            etki.notlar.append("kur şoku")
        }
        return etki
    }

    /// Serinin son `pencere` günlük getirisini kendi günlük oynaklığıyla ölçekler (σ cinsinden).
    private func zSkor(_ seri: [Double], pencere: Int) -> Double? {
        guard seri.count >= pencere + 30, let son = seri.last, son > 0 else { return nil }
        let onceki = seri[seri.count - 1 - pencere]
        guard onceki > 0 else { return nil }
        let getiri = (son - onceki) / onceki * 100
        let gunlukVol = sonVolatiliteYuzde(Array(seri.dropLast(0)))
        guard gunlukVol > 0 else { return nil }
        return getiri / (gunlukVol * sqrt(Double(pencere)))
    }

    // MARK: - Motor protokolü

    public func degerlendir(_ mumlar: [Mum]) -> Katki? {
        guard let t = tahminEt(mumlar) else { return nil }
        // Skor: beklenen değişimi 0-100'e ölçekle (yukarı tahmin → yüksek skor).
        let skor = max(0, min(100, 50 + t.degisimYuzde * 5))
        return Katki(motor: isim, skor: skor, guven: t.guven / 100,
                     gerekce: String(format: "%@ · tahmin %%%.1f (güven %%%.0f)",
                                     t.oneri.rawValue, t.degisimYuzde, t.guven))
    }

    /// Tam tahmin (UI/Konsey için). `baglam` verilirse endeks rejimi + kur şoku
    /// güven ve tahmin aralığına işlenir.
    public func tahminEt(_ mumlar: [Mum], baglam: Baglam? = nil) -> Tahmin? {
        let sirali = mumlar.sorted { $0.tarih < $1.tarih }
        let tum = sirali.map(\.kapanis)
        guard tum.count >= 120 else { return nil }
        // Hız + güncellik: son 300 bar yeter (kalibrasyon grid-search maliyetini sınırlar).
        let fiyatlar = Array(tum.suffix(300))
        let sonMumlar = Array(sirali.suffix(300))

        let ufuk = ufukGun(fiyatlar.count)
        let kalibrasyon = parametreKalibre(fiyatlar, ufuk: ufuk)
        let son = fiyatlar.last ?? 0
        let holt = sonumluHolt(fiyatlar, gun: ufuk,
                               alpha: kalibrasyon.alpha, beta: kalibrasyon.beta, phi: kalibrasyon.phi)
        // Trend dozu λ: tahmin = naif + λ·(Holt − naif). Kısa vadede mean-reversion
        // baskınsa walk-forward λ'yı kısar; trend gerçekten taşıyorsa λ→1.
        let hamTahmin = holt.map { son + kalibrasyon.lambda * ($0 - son) }
        let volYuzde = sonVolatiliteYuzde(fiyatlar)
        let limitSeri = limitSerisiUzunlugu(fiyatlar)
        let tahmin = sanityClamp(hamTahmin, fiyatlar: fiyatlar, volYuzde: volYuzde, limitSeri: limitSeri)
        let yon = (tahmin.last ?? 0) - (fiyatlar.last ?? 0)
        let etki = baglamEtkisi(baglam, sonTarih: sonMumlar.last?.tarih ?? Date(), tahminYonu: yon)
        var bant = tahminAraliklari(tahmin, mutlakHatalar: kalibrasyon.mutlakHatalar,
                                    sonFiyat: fiyatlar.last ?? 0, ufuk: ufuk)
        if etki.bantCarpani != 1.0 {
            let orta = zip(bant.alt, bant.ust).map { ($0 + $1) / 2 }
            bant = Bant(alt: zip(orta, bant.alt).map { max(0, $0 - ($0 - $1) * etki.bantCarpani) },
                        ust: zip(orta, bant.ust).map { $0 + ($1 - $0) * etki.bantCarpani },
                        genislikYuzde: bant.genislikYuzde * etki.bantCarpani)
        }
        let likiditeCeza = likiditeCezasi(sonMumlar)
        var guven = guvenHesapla(fiyatlar: fiyatlar, mape: kalibrasyon.mape, naifMape: kalibrasyon.naifMape,
                                 yonIsabeti: kalibrasyon.yonIsabeti, bantGenislikYuzde: bant.genislikYuzde)
        // Limit rejimi: ardışık tavan/taban serisinde fiyat keşfi bozuk (kuyrukta emir
        // birikir, VBTS/brüt takas tedbiri gelebilir) — Holt'un gördüğü trend yapay.
        if limitSeri >= 2 { guven = max(0, guven - Double(limitSeri) * 12) }
        guven = max(0, guven - likiditeCeza) * etki.guvenCarpani

        let suanki = fiyatlar.last ?? 0
        let tahminFiyat = tahmin.last ?? suanki
        let degisim = suanki > 0 ? (tahminFiyat - suanki) / suanki * 100 : 0
        let trend = trendBelirle(degisim: degisim, volYuzde: volYuzde, ufuk: ufuk)
        let oneri = oneriBelirle(suanki: suanki, tahmin: tahminFiyat,
                                 alt: bant.alt.last ?? tahminFiyat, ust: bant.ust.last ?? tahminFiyat,
                                 guven: guven, volYuzde: volYuzde)

        var gerekce = String(format: "Ufuk %d gün · λ%.2f · MAPE %%%.1f · yön %%%.0f · %@",
                             ufuk, kalibrasyon.lambda, kalibrasyon.mape, kalibrasyon.yonIsabeti * 100, oneri.rawValue)
        if limitSeri >= 2 { gerekce += " · limit serisi (\(limitSeri) bar, tedbir riski)" }
        if !etki.notlar.isEmpty { gerekce += " · " + etki.notlar.joined(separator: ", ") }
        return Tahmin(suankiFiyat: suanki, tahminFiyat: tahminFiyat, degisimYuzde: degisim,
                      guven: guven, trend: trend, oneri: oneri, ufukGun: ufuk,
                      mape: kalibrasyon.mape, yonIsabeti: kalibrasyon.yonIsabeti,
                      altBant: bant.alt, ustBant: bant.ust, tahminler: tahmin, gerekce: gerekce)
    }

    // MARK: - Sönümlü Holt

    /// `trim`: çok-adımlı son tahminde median-trim uygulanır; 1-adımlık kalibrasyonda
    /// gereksiz olduğu için kapatılır (sıralama maliyetini hot-path'ten çıkarır).
    private func sonumluHolt(_ fiyatlar: [Double], gun: Int, alpha: Double, beta: Double, phi: Double, trim: Bool = true) -> [Double] {
        guard fiyatlar.count >= 2 else { return [] }
        var seviye = fiyatlar[0]
        var trend = fiyatlar[1] - fiyatlar[0]
        var trendGecmis: [Double] = []
        let pencere = 30, trimKat = 2.0

        for i in 1..<fiyatlar.count {
            let oncekiSeviye = seviye
            seviye = alpha * fiyatlar[i] + (1 - alpha) * (oncekiSeviye + phi * trend)
            trend = beta * (seviye - oncekiSeviye) + (1 - beta) * phi * trend
            if trim {
                // Trend median-trim: spike'ta uçan trendi törpüle (işaret korunur).
                trendGecmis.append(trend)
                if trendGecmis.count > pencere { trendGecmis.removeFirst() }
                if trendGecmis.count >= 10 {
                    let sirali = trendGecmis.map(abs).sorted()
                    let medyan = sirali[sirali.count / 2]
                    let tavan = max(medyan * trimKat, 1e-6)
                    if abs(trend) > tavan { trend = (trend > 0 ? 1 : -1) * tavan }
                }
            }
        }

        var sonuc: [Double] = []
        var kumulatif = 0.0
        for h in 1...gun {
            kumulatif += pow(phi, Double(h))
            sonuc.append(max(0, seviye + kumulatif * trend))
        }
        return sonuc
    }

    // MARK: - Parametre kalibrasyonu (walk-forward)

    private struct Kalibrasyon {
        let alpha: Double, beta: Double, phi: Double, lambda: Double
        let mape: Double, naifMape: Double, yonIsabeti: Double, mutlakHatalar: [Double]
    }

    /// Kalibrasyon GERÇEK ufukta yapılır: 1-adım hatayla seçip h'ye uzatmak,
    /// kısa-vade gürültüsüne göre seçilmiş parametreyi h-adım rejimine taşıyordu
    /// (2026-06 kıyas koşusu: yön isabeti <%50). Tanı artık h-adım, λ da grid'de.
    private func parametreKalibre(_ fiyatlar: [Double], ufuk: Int) -> Kalibrasyon {
        let alphalar = [0.2, 0.3, 0.4, 0.6], betalar = [0.05, 0.1, 0.2, 0.3], philer = [0.85, 0.92, 0.98]
        let lambdalar = [0.0, 0.35, 0.7, 1.0]
        let dogrulamaPenceresi = min(60, max(20, fiyatlar.count / 5))
        var enIyiSkor = -Double.greatestFiniteMagnitude
        var enIyi = Kalibrasyon(alpha: 0.3, beta: 0.1, phi: 0.92, lambda: 1.0,
                                mape: 100, naifMape: 100, yonIsabeti: 0, mutlakHatalar: [])
        var naifMape = 100.0

        for a in alphalar { for b in betalar { for p in philer {
            let noktalar = hAdimTani(fiyatlar, pencere: dogrulamaPenceresi, ufuk: ufuk, alpha: a, beta: b, phi: p)
            guard !noktalar.isEmpty else { continue }
            // Naif taban (yarın=bugün) parametreden bağımsız — bir kez ölç.
            if naifMape == 100.0 {
                let apeler = noktalar.map { $0.gercek > 0 ? abs($0.gercek - $0.onceki) / $0.gercek * 100 : 100 }
                naifMape = apeler.reduce(0, +) / Double(apeler.count)
            }
            for l in lambdalar {
                var mutlaklar: [Double] = [], apeler: [Double] = []
                var dogru = 0, sayilan = 0
                for n in noktalar {
                    let tahmin = n.onceki + l * (n.holt - n.onceki)
                    let mutlak = abs(n.gercek - tahmin)
                    mutlaklar.append(mutlak)
                    apeler.append(n.gercek > 0 ? mutlak / n.gercek * 100 : 100)
                    if abs(tahmin - n.onceki) > abs(n.onceki) * 1e-6 {
                        sayilan += 1
                        if (tahmin - n.onceki) * (n.gercek - n.onceki) > 0 { dogru += 1 }
                    }
                }
                let mape = apeler.reduce(0, +) / Double(apeler.count)
                // λ=0 (naif) yön üretmez → nötr 0.5 (ne ödül ne ceza).
                let yonIsabeti = sayilan > 0 ? Double(dogru) / Double(sayilan) : 0.5
                // Skor: yön isabeti coin-flip üstüne ödüllendirilir (sadece MAPE bias'lı modeli seçebilir).
                let skor = -mape + 60 * max(0, yonIsabeti - 0.5)
                if skor > enIyiSkor {
                    enIyiSkor = skor
                    enIyi = Kalibrasyon(alpha: a, beta: b, phi: p, lambda: l, mape: mape,
                                        naifMape: naifMape, yonIsabeti: yonIsabeti, mutlakHatalar: mutlaklar)
                }
            }
        }}}
        return enIyi
    }

    private struct TaniNokta { let onceki: Double; let holt: Double; let gercek: Double }

    /// Walk-forward h-adım tanı: [0..<i] ile eğit, i+h-1'deki gerçekle kıyasla.
    /// Holt tahmini ham döner; λ harmanı dışarıda denenir (Holt geçişi tek sefer).
    private func hAdimTani(_ fiyatlar: [Double], pencere: Int, ufuk: Int, alpha: Double, beta: Double, phi: Double) -> [TaniNokta] {
        guard fiyatlar.count >= pencere + ufuk + 10 else { return [] }
        var out: [TaniNokta] = []
        let bitis = fiyatlar.count - ufuk + 1
        let baslangic = bitis - pencere
        for i in baslangic..<bitis where i >= 5 {
            let egitim = Array(fiyatlar[0..<i])
            let gercek = fiyatlar[i + ufuk - 1]
            let holt = sonumluHolt(egitim, gun: ufuk, alpha: alpha, beta: beta, phi: phi, trim: false).last ?? gercek
            out.append(TaniNokta(onceki: egitim.last ?? gercek, holt: holt, gercek: gercek))
        }
        return out
    }

    // MARK: - Tahmin aralıkları

    private struct Bant { let alt: [Double]; let ust: [Double]; let genislikYuzde: Double }

    private func tahminAraliklari(_ tahmin: [Double], mutlakHatalar: [Double], sonFiyat: Double, ufuk: Int) -> Bant {
        guard !tahmin.isEmpty else { return Bant(alt: [], ust: [], genislikYuzde: 0) }
        let yedek = max(0.01, sonFiyat * 0.02)
        let q90 = kantil(mutlakHatalar, 0.90) ?? yedek
        let oosSisme = 1.2   // hata artık h-adımda ölçülüyor (OOS payı küçüldü)
        let temelHata = max(q90 * oosSisme, yedek)
        var alt: [Double] = [], ust: [Double] = []
        for (i, t) in tahmin.enumerated() {
            // q90 ufuk-sonu hatası: ara adımlar √(adım/ufuk) ile ufka doğru büyür.
            let olcek = temelHata * sqrt(Double(i + 1) / Double(max(1, ufuk)))
            alt.append(max(0, t - olcek)); ust.append(t + olcek)
        }
        let ortTahmin = max(0.01, tahmin.reduce(0, +) / Double(tahmin.count))
        let genislik = zip(alt, ust).map { $1 - $0 }.reduce(0, +) / Double(tahmin.count)
        return Bant(alt: alt, ust: ust, genislikYuzde: genislik / ortTahmin * 100)
    }

    private func kantil(_ d: [Double], _ q: Double) -> Double? {
        guard !d.isEmpty else { return nil }
        let s = d.sorted()
        return s[Int(Double(s.count - 1) * max(0, min(1, q)))]
    }

    // MARK: - Sanity clamp (vol tavanı + RSI veto)

    private func sanityClamp(_ tahmin: [Double], fiyatlar: [Double], volYuzde: Double, limitSeri: Int = 0) -> [Double] {
        guard !tahmin.isEmpty, let son = fiyatlar.last, son > 0 else { return tahmin }
        var c = tahmin
        let sigma = max(volYuzde, 0.5)
        // Limit rejiminde trende güven azalır: vol tavanı 3σ yerine 1.5σ.
        let sigmaKat = limitSeri >= 2 ? 1.5 : 3.0
        for h in 0..<c.count {
            var tavanYuzde = sigmaKat * sigma * sqrt(Double(h + 1))
            // Fiziksel sınır: günlük fiyat limiti olan piyasada h günde
            // bileşik limitten öteye gidilemez (BIST: ±%10/gün).
            if let limit = profil.gunlukLimitYuzde {
                let bilesik = (pow(1 + limit / 100, Double(h + 1)) - 1) * 100
                tavanYuzde = min(tavanYuzde, bilesik)
            }
            let degisim = (c[h] - son) / son * 100
            if abs(degisim) > tavanYuzde {
                c[h] = son * (1 + (degisim > 0 ? 1 : -1) * tavanYuzde / 100)
            }
        }
        // RSI vetosu: aşırı alımda yukarı, aşırı satımda aşağı tahmini ±2σ ile sınırla.
        if let rsi = Gostergeler.sonRSI(fiyatlar) {
            let limit = 2 * max(volYuzde, 0.5)
            for h in 0..<c.count {
                let degisim = (c[h] - son) / son * 100
                if rsi > 80 && degisim > limit { c[h] = son * (1 + limit / 100) }
                if rsi < 20 && degisim < -limit { c[h] = son * (1 - limit / 100) }
            }
        }
        return c
    }

    // MARK: - Yardımcılar

    private func ufukGun(_ barSayisi: Int) -> Int {
        if let u = sabitUfuk { return max(1, u) }
        switch barSayisi { case 500...: return 5; case 200...: return 4; case 120...: return 3; case 60...: return 2; default: return 1 }
    }

    private func sonVolatiliteYuzde(_ fiyatlar: [Double]) -> Double {
        volYuzde(fiyatlar, pencere: 20)
    }

    /// Son `pencere` günün günlük getiri standart sapması (%).
    private func volYuzde(_ fiyatlar: [Double], pencere istenen: Int) -> Double {
        let pencere = min(istenen, fiyatlar.count - 1)
        guard pencere >= 2 else { return 0 }
        let kuyruk = Array(fiyatlar.suffix(pencere + 1))
        var getiriler: [Double] = []
        for i in 1..<kuyruk.count where kuyruk[i - 1] > 0 { getiriler.append((kuyruk[i] - kuyruk[i - 1]) / kuyruk[i - 1]) }
        guard getiriler.count >= 2 else { return 0 }
        let ort = getiriler.reduce(0, +) / Double(getiriler.count)
        let varyans = getiriler.reduce(0) { $0 + pow($1 - ort, 2) } / Double(getiriler.count - 1)
        return sqrt(varyans) * 100
    }

    /// Güven, motorun kendi walk-forward kanıtından kurulur (2026-06 kıyas koşusuyla
    /// yeniden ölçeklendi): naife karşı GÖRELİ MAPE edge'i + SİMETRİK yön terimi
    /// (isabet <%50 ise ceza). Kıyas rejimi (yön ~%48, edge ~-%4) ≈ 30-40 bandına,
    /// kanıtlı kâğıt (yön %60+, pozitif edge) 65+ kapı eşiğine düşecek şekilde.
    private func guvenHesapla(fiyatlar: [Double], mape: Double, naifMape: Double,
                              yonIsabeti: Double, bantGenislikYuzde: Double) -> Double {
        guard fiyatlar.count >= 10 else { return 0 }
        let son = Array(fiyatlar.suffix(10))
        let ort = son.reduce(0, +) / Double(son.count)
        let std = sqrt(son.reduce(0) { $0 + pow($1 - ort, 2) } / Double(son.count))
        let cv = ort > 0 ? std / ort : 0
        let edge = (naifMape - mape) / max(naifMape, 0.1)            // naife göre göreli kazanç
        let edgeTerimi = max(-20, min(15, edge * 150))
        let yonTerimi = max(-25, min(25, (yonIsabeti - 0.5) * 120))
        let genislikCeza = min(20, bantGenislikYuzde * 0.8)
        let volCeza = min(15, cv * 150)
        return max(0, min(95, 55 + edgeTerimi + yonTerimi - genislikCeza - volCeza))
    }

    private func trendBelirle(degisim: Double, volYuzde: Double, ufuk: Int) -> Trend {
        let olcek = max(1.0, volYuzde * sqrt(Double(max(1, ufuk))))
        switch degisim / olcek {
        case 2.0...: return .gucluYukari
        case 0.8..<2.0: return .yukari
        case -0.8..<0.8: return .notr
        case -2.0..<(-0.8): return .asagi
        default: return .gucluAsagi
        }
    }

    private func oneriBelirle(suanki: Double, tahmin: Double, alt: Double, ust: Double, guven: Double, volYuzde: Double) -> Oneri {
        guard suanki > 0 else { return .tut }
        let maliyet = profil.islemMaliyetiYuzde
        let minEdge = max(2 * maliyet, 0.5 * volYuzde)
        // Yüksek enflasyonlu piyasada nominal sürüklenme yukarı: sat için daha çok kanıt.
        let satEdge = minEdge * profil.satEdgeCarpani
        let guvenEsigi = 65.0
        let beklenen = (tahmin - suanki) / suanki * 100
        let temkinli = (alt - suanki) / suanki * 100
        let iyimser = (ust - suanki) / suanki * 100
        if guven >= guvenEsigi && temkinli >= maliyet && beklenen >= minEdge { return .al }
        if guven >= guvenEsigi && iyimser <= -maliyet && beklenen <= -satEdge { return .sat }
        return .tut
    }

    // MARK: - BIST'e özgü rejim tespitleri

    /// Son barlardan geriye doğru ardışık "limit hareketi" sayısı.
    /// Limit hareketi: günlük değişim, profil limitinin `limitYakinlikOrani` katına ulaşmış bar
    /// (BIST: ±%9 ve üzeri ≈ tavan/taban). Limitsiz piyasada hep 0.
    private func limitSerisiUzunlugu(_ fiyatlar: [Double]) -> Int {
        guard let limit = profil.gunlukLimitYuzde, fiyatlar.count >= 2 else { return 0 }
        let esik = limit * profil.limitYakinlikOrani
        var seri = 0
        var i = fiyatlar.count - 1
        while i >= 1, fiyatlar[i - 1] > 0 {
            let degisim = abs(fiyatlar[i] - fiyatlar[i - 1]) / fiyatlar[i - 1] * 100
            if degisim >= esik { seri += 1; i -= 1 } else { break }
        }
        return seri
    }

    /// Likidite cezası (0..15 güven puanı). Mutlak hacim eşiği yok — göreli sinyaller:
    /// son 20 barda işlemsiz/işlemsize yakın bar oranı ve hacmin kendi medyanına göre çökmesi.
    private func likiditeCezasi(_ mumlar: [Mum]) -> Double {
        let son = Array(mumlar.suffix(20))
        guard son.count >= 10 else { return 0 }
        let hacimler = son.map(\.hacim)
        let medyan = hacimler.sorted()[hacimler.count / 2]
        guard medyan > 0 else { return 15 }
        let oluOran = Double(hacimler.filter { $0 < medyan * 0.05 }.count) / Double(hacimler.count)
        let uzunMedyan = mumlar.map(\.hacim).sorted()[mumlar.count / 2]
        let kuruma = uzunMedyan > 0 ? max(0, 1 - medyan / uzunMedyan) : 0
        return min(15, oluOran * 30 + kuruma * 10)
    }
}
