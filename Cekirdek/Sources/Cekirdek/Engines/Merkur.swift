import Foundation

/// Merkür — teknik analiz motoru. (Gezegen teması: en hızlı gezegen = anlık hareket.)
///
/// Çok-bacaklı, rejim-duyarlı bir teknik skor üretir (0-100):
///   • Trend     — SMA20/50/200 dizilimi + konum + MACD (+ opsiyonel endekse görelik)
///   • Momentum  — RSI haritalama + hacim/likidite
///   • Volatilite — Bollinger sıkışması (squeeze) + ATR%
/// Ağırlıklar ADX'e göre rejim-duyarlı kayar (trend piyasada trend/momentum,
/// yatay piyasada volatilite öne çıkar). Güçlü dizilimde küçük sinerji bonusu.
///
/// (Sıfırdan, özgün uygulama — göstergeler kamuya açık standart matematik.)
public struct Merkur: Motor {
    public let isim = "Merkür"

    public init() {}

    // MARK: - Zengin sonuç

    public struct Bilesenler: Sendable {
        public let trend: Double        // 0..100
        public let momentum: Double     // 0..100
        public let volatilite: Double   // 0..100
        public let rsi: Double?
        public let adx: Double?
        public let aciklama: String
    }

    public struct Sonuc: Sendable {
        public let skor: Double         // 0..100
        public let verdict: String
        public let bilesenler: Bilesenler
    }

    // MARK: - Motor protokolü

    public func degerlendir(_ mumlar: [Mum]) -> Katki? {
        degerlendir(mumlar, endeks: nil).map { s in
            Katki(motor: isim, skor: s.skor, guven: guven(s), gerekce: s.bilesenler.aciklama)
        }
    }

    /// Endeks (örn. XU100/SPY) mumları verilirse görelatif güç (RS) bacağı devreye girer.
    public func degerlendir(_ mumlar: [Mum], endeks: [Mum]?) -> Sonuc? {
        let m = mumlar.sorted { $0.tarih < $1.tarih }
        guard m.count > 50 else { return nil }
        let kapanis = m.map(\.kapanis)

        let t = trendSkoru(m, kapanis: kapanis, endeks: endeks)
        let mom = momentumSkoru(m, kapanis: kapanis)
        let vol = volatiliteSkoru(m, kapanis: kapanis)

        // Rejim-duyarlı ağırlıklar (ADX).
        let adx = Gostergeler.sonADX(m)
        var wT = 0.45, wM = 0.35, wV = 0.20
        if let a = adx {
            if a > 25 { wT *= 1.25; wM *= 1.20 }              // trend piyasası
            else if a < 15 { wT *= 0.70; wM *= 0.75; wV *= 1.15 } // yatay/choppy
        }
        let toplam = wT + wM + wV
        wT /= toplam; wM /= toplam; wV /= toplam

        var skor = t.skor * wT + mom.skor * wM + vol.skor * wV

        // Sinerji: güçlü yukarı dizilim varsa küçük bonus.
        if t.guicluYukari { skor = min(100, skor * 1.05) }
        skor = max(0, min(100, skor))

        let bilesenler = Bilesenler(
            trend: t.skor, momentum: mom.skor, volatilite: vol.skor,
            rsi: mom.rsi, adx: adx,
            aciklama: "\(t.aciklama) · \(mom.aciklama) · \(vol.aciklama)"
        )
        return Sonuc(skor: skor, verdict: verdict(skor), bilesenler: bilesenler)
    }

    // MARK: - Trend bacağı

    private struct TrendSonuc { let skor: Double; let aciklama: String; let guicluYukari: Bool }

    private func trendSkoru(_ m: [Mum], kapanis: [Double], endeks: [Mum]?) -> TrendSonuc {
        let fiyat = kapanis.last ?? 0
        guard let s20 = Gostergeler.sonSMA(kapanis, 20),
              let s50 = Gostergeler.sonSMA(kapanis, 50),
              let s200 = Gostergeler.sonSMA(kapanis, 200), s20 > 0, s50 > 0, s200 > 0 else {
            return TrendSonuc(skor: 50, aciklama: "Trend: yetersiz veri", guicluYukari: false)
        }

        var ham = 0.0   // 0..30

        // 1. Genel eğilim (fiyat vs SMA200)
        if fiyat > s200 { ham += 10 }
        else if (s200 - fiyat) / s200 < 0.02 { ham += 5 }

        // 2. Dizilim
        let dizilimTam = (s20 > s50 && s50 > s200)
        if dizilimTam { ham += 10 }
        else if s20 > s50 { ham += 7 }
        else if s20 > s200 { ham += 3 }

        // 3. Konumlanma (SMA20'ye göre)
        let mesafe20 = (fiyat - s20) / s20
        if mesafe20 > 0 {
            ham += 5 + 5 * min(1.0, mesafe20 / 0.05)
        } else if s20 > s50 {
            let derinlik = abs(mesafe20)
            if derinlik < 0.03 { ham += 6 } else if derinlik < 0.07 { ham += 3 }
        }

        // 4. Aşırı uzama cezası (SMA50'den çok uzaksa)
        let mesafe50 = (fiyat - s50) / s50
        if mesafe50 > 0.20 { ham -= min(5, (mesafe50 - 0.20) * 100) }
        ham = max(0, min(30, ham))

        // MACD bacağı (0..10)
        var macdHam = 5.0
        var macdNot = ""
        let macd = Gostergeler.sonMACD(kapanis)
        if let h = macd.histogram, let sig = macd.sinyal {
            if h > 0 { macdHam = sig > 0 ? 10 : 8; macdNot = sig > 0 ? "MACD güçlü" : "MACD erken" }
            else { macdHam = h > sig ? 5 : 2; macdNot = h > sig ? "MACD toparlıyor" : "MACD zayıf" }
        }

        // RS bacağı (opsiyonel, 0..15)
        var rsHam: Double? = nil
        if let e = endeks?.sorted(by: { $0.tarih < $1.tarih }), e.count > 30, m.count > 30 {
            let sGetiri = (fiyat - kapanis[kapanis.count - 30]) / kapanis[kapanis.count - 30]
            let ek = e.map(\.kapanis)
            let mGetiri = (ek.last! - ek[ek.count - 30]) / ek[ek.count - 30]
            let fark = (sGetiri - mGetiri) * 100
            rsHam = fark >= 5 ? 15 : (fark >= 0 ? 10 : (fark > -5 ? 7 : 3))
        }

        // 0..100'e normalle
        let skor100: Double
        if let rs = rsHam { skor100 = (ham + macdHam + rs) / 55 * 100 }
        else { skor100 = (ham + macdHam) / 40 * 100 }

        return TrendSonuc(
            skor: max(0, min(100, skor100)),
            aciklama: String(format: "Trend %.0f/30%@", ham, macdNot.isEmpty ? "" : " \(macdNot)"),
            guicluYukari: dizilimTam && fiyat > s20
        )
    }

    // MARK: - Momentum bacağı

    private struct MomSonuc { let skor: Double; let aciklama: String; let rsi: Double? }

    private func momentumSkoru(_ m: [Mum], kapanis: [Double]) -> MomSonuc {
        // RSI bacağı (0..15)
        var rsiHam = 7.5
        var rsiNot = "RSI veri yok"
        let rsi = Gostergeler.sonRSI(kapanis)
        if let r = rsi {
            if r >= 50 && r <= 70 { rsiHam = 8 + 7 * (r - 50) / 20; rsiNot = "RSI güçlü" }
            else if r > 70 { rsiHam = r > 80 ? 6 : 12; rsiNot = r > 80 ? "RSI şişkin" : "RSI yüksek" }
            else if r >= 40 { rsiHam = 5 + 3 * (r - 40) / 10; rsiNot = "RSI nötr" }
            else { rsiHam = r < 30 ? 8 : 5; rsiNot = r < 30 ? "RSI dip" : "RSI zayıf" }
        }

        // Likidite bacağı (0..15) — ortalama dolar/lira hacmi
        let dilim = m.suffix(20)
        let ortHacim = dilim.map(\.hacim).reduce(0, +) / Double(max(1, dilim.count))
        let degerHacim = ortHacim * (kapanis.last ?? 0)
        var likHam = 1.0
        if degerHacim > 1_000_000 {
            likHam = 2 + 6 * min(1.0, max(0.0, (log10(degerHacim) - 6) / 2))
        }

        let skor100 = (rsiHam + likHam) / 30 * 100
        return MomSonuc(skor: max(0, min(100, skor100)), aciklama: rsiNot, rsi: rsi)
    }

    // MARK: - Volatilite bacağı

    private struct VolSonuc { let skor: Double; let aciklama: String }

    private func volatiliteSkoru(_ m: [Mum], kapanis: [Double]) -> VolSonuc {
        guard kapanis.count >= 20, let s20 = Gostergeler.sonSMA(kapanis, 20), s20 > 0 else {
            return VolSonuc(skor: 50, aciklama: "Volatilite nötr")
        }
        let son20 = Array(kapanis.suffix(20))
        let varyans = son20.map { pow($0 - s20, 2) }.reduce(0, +) / 20
        let bbGenislik = (sqrt(varyans) * 2) / s20 * 100
        let squeeze = bbGenislik < 2.0

        var skor = 50.0
        if squeeze { skor += 30 }
        if let atr = Gostergeler.sonATR(m) {
            let atrYuzde = atr / (kapanis.last ?? 1) * 100
            if atrYuzde > 1.5 && atrYuzde < 4.0 { skor += 20 }
            else if atrYuzde < 1.0 { skor += 10 }
            else if atrYuzde > 6.0 { skor -= 20 }
        }
        return VolSonuc(skor: max(0, min(100, skor)), aciklama: squeeze ? "Sıkışma" : "Normal volatilite")
    }

    // MARK: - Yardımcılar

    private func verdict(_ skor: Double) -> String {
        switch skor {
        case 85...100: return "A+ Fırsat (nadir)"
        case 70..<85:  return "Güçlü alım"
        case 50..<70:  return "Nötr / tut"
        case 30..<50:  return "Zayıf / izle"
        default:       return "Uzak dur"
        }
    }

    private func guven(_ s: Sonuc) -> Double {
        // Bacaklar aynı yönde + ADX verisi varsa güven yüksek.
        let b = s.bilesenler
        let yonler = [b.trend, b.momentum].map { $0 >= 50 }
        let uyum = yonler.allSatisfy { $0 } || yonler.allSatisfy { !$0 }
        var g = 0.6
        if b.adx != nil { g += 0.1 }
        if uyum { g += 0.2 }
        return min(1.0, g)
    }
}
