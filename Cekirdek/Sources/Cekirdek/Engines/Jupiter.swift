import Foundation

/// Makro girdi serileri (kapanışlar, artan tarihli). Boş seri → o bileşen atlanır.
public struct MakroGirdi: Sendable {
    public var vix: [Double] = []
    public var spy: [Double] = []        // S&P 500 (^GSPC)
    public var dxy: [Double] = []        // Dolar endeksi
    public var faiz10y: [Double] = []    // ABD 10Y (^TNX)
    public var altin: [Double] = []      // GC=F
    public var usdtry: [Double] = []
    public init() {}
}

/// Jüpiter — makro rejim motoru. (Argus "Aether" mantığı, piyasa-bazlı, sıfırdan.)
/// Her bileşen 0-100 (yüksek = risk-iştahlı / hisse-dostu). Ağırlıklı harman → rejim.
/// FRED gerektiren CPI/işsizlik/büyüme ÇIKARILDI (key yok); piyasa proxy'leriyle çalışır.
/// Piyasa geneli sinyal — tüm hisseler için aynı (yukarıdan-aşağı tilt).
public struct Jupiter {
    public let isim = "Jüpiter"
    public init() {}

    public enum Rejim: String, Sendable { case riskIstahli = "Risk iştahlı", temkinli = "Temkinli", savunmaci = "Savunmacı" }

    public struct Bilesen: Sendable { public let ad: String; public let skor: Double; public let agirlik: Double }

    public struct Sonuc: Sendable {
        public let skor: Double          // 0..100
        public let rejim: Rejim
        public let bilesenler: [Bilesen]
        public let aciklama: String
    }

    public func analiz(_ g: MakroGirdi) -> Sonuc? {
        let adaylar: [(String, Double?, Double)] = [
            ("VIX", vixSkor(g.vix), 0.26),
            ("S&P trend", trendSkor(g.spy), 0.20),
            ("Dolar (DXY)", dxySkor(g.dxy), 0.15),
            ("Altın", altinSkor(g.altin), 0.11),
            ("ABD 10Y", faizSkor(g.faiz10y), 0.13),
            ("USD/TRY", usdtrySkor(g.usdtry), 0.15),
        ]
        let gecerli = adaylar.compactMap { (ad, skor, w) -> Bilesen? in skor.map { Bilesen(ad: ad, skor: $0, agirlik: w) } }
        guard !gecerli.isEmpty else { return nil }

        let toplamW = gecerli.reduce(0) { $0 + $1.agirlik }
        let skor = gecerli.reduce(0) { $0 + $1.skor * $1.agirlik } / toplamW
        let rejim: Rejim = skor >= 60 ? .riskIstahli : (skor >= 45 ? .temkinli : .savunmaci)
        let ozet = gecerli.map { "\($0.ad) \(Int($0.skor.rounded()))" }.joined(separator: " · ")
        return Sonuc(skor: skor, rejim: rejim, bilesenler: gecerli, aciklama: ozet)
    }

    /// Konsey için Katki — makro rejim tüm hisseler için aynı tilt.
    public func katki(_ g: MakroGirdi) -> Katki? {
        guard let s = analiz(g) else { return nil }
        return Katki(motor: isim, skor: s.skor, guven: 0.6, gerekce: s.rejim.rawValue)
    }

    // MARK: - Bileşen skorları (Aether eşikleri)

    private func vixSkor(_ d: [Double]) -> Double? {
        guard let v = d.last else { return nil }
        var skor: Double
        switch v {
        case ..<12: skor = 95
        case 12..<18: skor = 95 - (v - 12) / 6 * 20
        case 18..<24: skor = 75 - (v - 18) / 6 * 25
        case 24..<30: skor = 50 - (v - 24) / 6 * 25
        case 30..<40: skor = 25 - (v - 30) / 10 * 20
        default: skor = 5
        }
        // İvme: VIX son 5 günde hızlı yükseliyorsa ek ceza, düşüyorsa sınırlı bonus.
        if d.count > 5 {
            let degisim5 = (v - d[d.count - 6]) / d[d.count - 6] * 100
            skor -= min(14, max(0, degisim5 - 8) * 0.35)
            skor += min(8, max(0, -degisim5 - 8) * 0.2)
        }
        return max(0, min(100, skor))
    }

    private func trendSkor(_ d: [Double]) -> Double? {
        guard let s = d.last, d.count >= 50 else {
            guard let s = d.last, let f = d.first else { return nil }
            return s > f ? 65 : 45   // flash
        }
        let sma = d.suffix(50).reduce(0, +) / 50
        if s > sma { return 80 }
        let dist = (sma - s) / sma
        return dist > 0.05 ? 20 : 40
    }

    private func dxySkor(_ d: [Double]) -> Double? {
        guard let last = d.last, d.count >= 50 else {
            guard let last = d.last, let f = d.first else { return nil }
            return last > f ? 45 : 65
        }
        let sma = d.suffix(50).reduce(0, +) / 50
        return last > sma ? 40 : 70   // güçlü dolar = risk-off
    }

    private func altinSkor(_ d: [Double]) -> Double? {
        guard let last = d.last, d.count >= 20 else { return nil }
        let sma = d.suffix(20).reduce(0, +) / 20
        let sapma = (last - sma) / sma * 100
        switch sapma {
        case 5...: return 15           // güvenli limana kaçış
        case 2..<5: return 30 - (sapma - 2) * 5
        case 0..<2: return 50 - sapma * 10
        case -2..<0: return 50 + (-sapma) * 15
        default: return 85             // altın zayıf = risk-on
        }
    }

    private func faizSkor(_ d: [Double]) -> Double? {
        guard let last = d.last, d.count >= 20 else { return nil }
        let onceki = d[d.count - 20]
        let degisim = last - onceki     // 10Y puan değişimi (~ay)
        // Hızlı yükselen faiz = risk-off; düşen = risk-on.
        switch degisim {
        case 0.5...: return 35
        case 0.2..<0.5: return 45
        case -0.2..<0.2: return 55
        case -0.5..<(-0.2): return 65
        default: return 72
        }
    }

    private func usdtrySkor(_ d: [Double]) -> Double? {
        guard let last = d.last, d.count >= 6 else { return nil }
        let degisim5 = (last - d[d.count - 6]) / d[d.count - 6] * 100   // 5 gün
        // Lira hızlı değer kaybediyorsa (USDTRY yükseliş) BIST için risk-off.
        switch degisim5 {
        case 2...: return 28
        case 0.5..<2: return 45
        case -0.5..<0.5: return 58
        default: return 70             // lira güçleniyor = risk-on
        }
    }
}
