import Foundation

/// Neptün — fiyat tahmini motoru. (Argus "Prometheus" mantığı, sıfırdan yazıldı.)
/// Sönümlü Holt (Damped Holt's Linear) + walk-forward parametre kalibrasyonu +
/// tahmin aralıkları + sanity clamp (volatilite tavanı + RSI vetosu) + maliyet-bilinçli öneri.
/// (Yöntem kamuya açık zaman serisi tahmini — kod özgün.)
public struct Neptun: Motor {
    public let isim = "Neptün"

    public init() {}

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

    // MARK: - Motor protokolü

    public func degerlendir(_ mumlar: [Mum]) -> Katki? {
        guard let t = tahminEt(mumlar) else { return nil }
        // Skor: beklenen değişimi 0-100'e ölçekle (yukarı tahmin → yüksek skor).
        let skor = max(0, min(100, 50 + t.degisimYuzde * 5))
        return Katki(motor: isim, skor: skor, guven: t.guven / 100,
                     gerekce: String(format: "%@ · tahmin %%%.1f (güven %%%.0f)",
                                     t.oneri.rawValue, t.degisimYuzde, t.guven))
    }

    /// Tam tahmin (UI/Konsey için).
    public func tahminEt(_ mumlar: [Mum]) -> Tahmin? {
        let tum = mumlar.sorted { $0.tarih < $1.tarih }.map(\.kapanis)
        guard tum.count >= 120 else { return nil }
        // Hız + güncellik: son 300 bar yeter (kalibrasyon grid-search maliyetini sınırlar).
        let fiyatlar = Array(tum.suffix(300))

        let ufuk = ufukGun(fiyatlar.count)
        let kalibrasyon = parametreKalibre(fiyatlar)
        let hamTahmin = sonumluHolt(fiyatlar, gun: ufuk,
                                    alpha: kalibrasyon.alpha, beta: kalibrasyon.beta, phi: kalibrasyon.phi)
        let volYuzde = sonVolatiliteYuzde(fiyatlar)
        let tahmin = sanityClamp(hamTahmin, fiyatlar: fiyatlar, volYuzde: volYuzde)
        let bant = tahminAraliklari(tahmin, mutlakHatalar: kalibrasyon.mutlakHatalar, sonFiyat: fiyatlar.last ?? 0)
        let guven = guvenHesapla(fiyatlar: fiyatlar, mape: kalibrasyon.mape,
                                 yonIsabeti: kalibrasyon.yonIsabeti, bantGenislikYuzde: bant.genislikYuzde)

        let suanki = fiyatlar.last ?? 0
        let tahminFiyat = tahmin.last ?? suanki
        let degisim = suanki > 0 ? (tahminFiyat - suanki) / suanki * 100 : 0
        let trend = trendBelirle(degisim: degisim, volYuzde: volYuzde, ufuk: ufuk)
        let oneri = oneriBelirle(suanki: suanki, tahmin: tahminFiyat,
                                 alt: bant.alt.last ?? tahminFiyat, ust: bant.ust.last ?? tahminFiyat,
                                 guven: guven, volYuzde: volYuzde)

        let gerekce = String(format: "Ufuk %d gün · MAPE %%%.1f · yön %%%.0f · %@",
                             ufuk, kalibrasyon.mape, kalibrasyon.yonIsabeti * 100, oneri.rawValue)
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
        let alpha: Double, beta: Double, phi: Double
        let mape: Double, yonIsabeti: Double, mutlakHatalar: [Double]
    }

    private func parametreKalibre(_ fiyatlar: [Double]) -> Kalibrasyon {
        let alphalar = [0.2, 0.3, 0.4, 0.6], betalar = [0.05, 0.1, 0.2, 0.3], philer = [0.85, 0.92, 0.98]
        let dogrulamaPenceresi = min(60, max(20, fiyatlar.count / 5))
        var enIyiSkor = -Double.greatestFiniteMagnitude
        var enIyi = Kalibrasyon(alpha: 0.3, beta: 0.1, phi: 0.92, mape: 100, yonIsabeti: 0, mutlakHatalar: [])

        for a in alphalar { for b in betalar { for p in philer {
            let tani = tekAdimTani(fiyatlar, pencere: dogrulamaPenceresi, alpha: a, beta: b, phi: p)
            guard !tani.isEmpty else { continue }
            let mape = tani.map(\.ape).reduce(0, +) / Double(tani.count)
            let yonIsabeti = Double(tani.filter(\.yonDogru).count) / Double(tani.count)
            // Skor: yön isabeti coin-flip üstüne ödüllendirilir (sadece MAPE bias'lı modeli seçebilir).
            let skor = -mape + 60 * max(0, yonIsabeti - 0.5)
            if skor > enIyiSkor {
                enIyiSkor = skor
                enIyi = Kalibrasyon(alpha: a, beta: b, phi: p, mape: mape,
                                    yonIsabeti: yonIsabeti, mutlakHatalar: tani.map(\.mutlakHata))
            }
        }}}
        return enIyi
    }

    private struct Tani { let mutlakHata: Double; let ape: Double; let yonDogru: Bool }

    private func tekAdimTani(_ fiyatlar: [Double], pencere: Int, alpha: Double, beta: Double, phi: Double) -> [Tani] {
        guard fiyatlar.count >= pencere + 10 else { return [] }
        var out: [Tani] = []
        let baslangic = fiyatlar.count - pencere
        for i in baslangic..<fiyatlar.count where i >= 5 {
            let egitim = Array(fiyatlar[0..<i])
            let gercek = fiyatlar[i]
            let tahmin = sonumluHolt(egitim, gun: 1, alpha: alpha, beta: beta, phi: phi, trim: false).first ?? gercek
            let mutlak = abs(gercek - tahmin)
            let ape = gercek > 0 ? mutlak / gercek * 100 : 100
            let onceki = egitim.last ?? gercek
            let yonDogru = (tahmin - onceki) * (gercek - onceki) > 0 || (tahmin == onceki && gercek == onceki)
            out.append(Tani(mutlakHata: mutlak, ape: ape, yonDogru: yonDogru))
        }
        return out
    }

    // MARK: - Tahmin aralıkları

    private struct Bant { let alt: [Double]; let ust: [Double]; let genislikYuzde: Double }

    private func tahminAraliklari(_ tahmin: [Double], mutlakHatalar: [Double], sonFiyat: Double) -> Bant {
        guard !tahmin.isEmpty else { return Bant(alt: [], ust: [], genislikYuzde: 0) }
        let yedek = max(0.01, sonFiyat * 0.02)
        let q90 = kantil(mutlakHatalar, 0.90) ?? yedek
        let oosSisme = 1.5   // in-sample residual OOS varyansı az tahmin eder
        let temelHata = max(q90 * oosSisme, yedek)
        var alt: [Double] = [], ust: [Double] = []
        for (i, t) in tahmin.enumerated() {
            let olcek = temelHata * sqrt(Double(i + 1))
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

    private func sanityClamp(_ tahmin: [Double], fiyatlar: [Double], volYuzde: Double) -> [Double] {
        guard !tahmin.isEmpty, let son = fiyatlar.last, son > 0 else { return tahmin }
        var c = tahmin
        let sigma = max(volYuzde, 0.5)
        for h in 0..<c.count {
            let tavanYuzde = 3.0 * sigma * sqrt(Double(h + 1))
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
        switch barSayisi { case 500...: return 5; case 200...: return 4; case 120...: return 3; case 60...: return 2; default: return 1 }
    }

    private func sonVolatiliteYuzde(_ fiyatlar: [Double]) -> Double {
        let pencere = min(20, fiyatlar.count - 1)
        guard pencere >= 2 else { return 0 }
        let kuyruk = Array(fiyatlar.suffix(pencere + 1))
        var getiriler: [Double] = []
        for i in 1..<kuyruk.count where kuyruk[i - 1] > 0 { getiriler.append((kuyruk[i] - kuyruk[i - 1]) / kuyruk[i - 1]) }
        guard getiriler.count >= 2 else { return 0 }
        let ort = getiriler.reduce(0, +) / Double(getiriler.count)
        let varyans = getiriler.reduce(0) { $0 + pow($1 - ort, 2) } / Double(getiriler.count - 1)
        return sqrt(varyans) * 100
    }

    private func guvenHesapla(fiyatlar: [Double], mape: Double, yonIsabeti: Double, bantGenislikYuzde: Double) -> Double {
        guard fiyatlar.count >= 10 else { return 0 }
        let son = Array(fiyatlar.suffix(10))
        let ort = son.reduce(0, +) / Double(son.count)
        let std = sqrt(son.reduce(0) { $0 + pow($1 - ort, 2) } / Double(son.count))
        let cv = ort > 0 ? std / ort : 0
        let mapeCeza = min(70, mape * 1.8)
        let genislikCeza = min(25, bantGenislikYuzde * 1.6)
        let volCeza = min(20, cv * 220)
        let yonBonus = max(0, yonIsabeti - 0.5) * 36
        return max(0, min(95, 85 - mapeCeza - genislikCeza - volCeza + yonBonus))
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
        let maliyet = 0.5   // BIST round-trip ~%0.5
        let minEdge = max(2 * maliyet, 0.5 * volYuzde)
        let guvenEsigi = 65.0
        let beklenen = (tahmin - suanki) / suanki * 100
        let temkinli = (alt - suanki) / suanki * 100
        let iyimser = (ust - suanki) / suanki * 100
        if guven >= guvenEsigi && temkinli >= maliyet && beklenen >= minEdge { return .al }
        if guven >= guvenEsigi && iyimser <= -maliyet && beklenen <= -minEdge { return .sat }
        return .tut
    }
}
