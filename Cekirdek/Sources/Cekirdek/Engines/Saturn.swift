import Foundation

/// Temel veri kümesi (Yahoo quoteSummary'den doldurulur). Eksik alanlar nil.
public struct TemelVeri: Sendable {
    public var fk: Double?            // trailing P/E
    public var ileriFK: Double?       // forward P/E
    public var pddd: Double?          // price/book
    public var peg: Double?
    public var roe: Double?           // 0..1 (oran)
    public var roa: Double?           // 0..1
    public var netMarj: Double?       // 0..1
    public var brutMarj: Double?      // 0..1
    public var borcOzkaynak: Double?  // debt/equity (Yahoo % verir → /100)
    public var cariOran: Double?
    public var gelirBuyume: Double?   // 0..1 (yıllık)
    public var karBuyume: Double?     // 0..1
    public var temettuVerimi: Double? // 0..1
    public var serbestNakit: Double?  // FCF (mutlak)
    public var piyasaDegeri: Double?

    public init() {}
}

/// Satürn — temel analiz motoru. (Argus "Atlas" mantığı, sıfırdan yazıldı.)
/// Ağırlıklı bölümler: Karlılık %30 · Değerleme %25 · Mali Sağlık %20 · Büyüme %15 · Nakit %10.
/// Her metrik bant-bazlı 0-100 skorlanır; eksik bölüm ağırlık hesabından düşülür (normalize).
/// 3'ten az geçerli bölüm → güvenilmez (skor nil).
public struct Saturn {
    public let isim = "Satürn"

    public init() {}

    public struct Bolum: Sendable {
        public let ad: String
        public let skor: Double
        public let agirlik: Double
    }

    public struct Sonuc: Sendable {
        public let skor: Double          // 0..100
        public let bolumler: [Bolum]     // mevcut (geçerli) bölümler
        public let eksikBolumler: [String]
        public let guvenilir: Bool
        public let aciklama: String
    }

    public func analiz(_ v: TemelVeri) -> Sonuc? {
        // Bölüm skorları (metrik ortalaması; metrik yoksa nil)
        let karlilik = ortala([
            v.roe.map { roeSkor($0) },
            v.roa.map { roaSkor($0) },
            v.netMarj.map { marjSkor($0) },
            v.brutMarj.map { brutMarjSkor($0) },
        ])
        let degerleme = ortala([
            v.fk.map { fkSkor($0) },
            v.ileriFK.map { fkSkor($0) },
            v.pddd.map { pdddSkor($0) },
            v.peg.map { pegSkor($0) },
        ])
        let saglik = ortala([
            v.borcOzkaynak.map { borcSkor($0) },
            v.cariOran.map { cariSkor($0) },
        ])
        let buyume = ortala([
            v.gelirBuyume.map { buyumeSkor($0 * 100) },
            v.karBuyume.map { buyumeSkor($0 * 100) },
        ])
        let nakit = ortala([
            (v.serbestNakit).flatMap { fcf in v.piyasaDegeri.map { mc in fcfSkor(fcf, piyasaDegeri: mc) } },
        ])

        let adaylar: [(String, Double?, Double)] = [
            ("Karlılık", karlilik, 0.30),
            ("Değerleme", degerleme, 0.25),
            ("Mali Sağlık", saglik, 0.20),
            ("Büyüme", buyume, 0.15),
            ("Nakit", nakit, 0.10),
        ]
        let gecerli = adaylar.compactMap { (ad, skor, w) -> Bolum? in skor.map { Bolum(ad: ad, skor: $0, agirlik: w) } }
        let eksik = adaylar.filter { $0.1 == nil }.map(\.0)

        guard !gecerli.isEmpty else { return nil }

        let guvenilir = gecerli.count >= 3
        let skor: Double
        if guvenilir {
            let toplamW = gecerli.reduce(0) { $0 + $1.agirlik }
            skor = gecerli.reduce(0) { $0 + $1.skor * $1.agirlik } / toplamW
        } else {
            skor = 50   // yetersiz veri → nötr (sahte güven verme)
        }

        let aciklama = guvenilir
            ? "Temel skor \(gecerli.count)/5 bölümden" + (eksik.isEmpty ? "" : " (eksik: \(eksik.joined(separator: ", ")))")
            : "Veri yetersiz (\(gecerli.count)/5) — nötr"
        return Sonuc(skor: skor, bolumler: gecerli, eksikBolumler: eksik, guvenilir: guvenilir, aciklama: aciklama)
    }

    /// Konsey için Katki. Güvenilmezse düşük güven.
    public func katki(_ v: TemelVeri) -> Katki? {
        guard let s = analiz(v) else { return nil }
        return Katki(motor: isim, skor: s.skor, guven: s.guvenilir ? 0.8 : 0.3, gerekce: s.aciklama)
    }

    private func ortala(_ skorlar: [Double?]) -> Double? {
        let g = skorlar.compactMap { $0 }
        guard !g.isEmpty else { return nil }
        return g.reduce(0, +) / Double(g.count)
    }

    // MARK: - Metrik bant skorları (Atlas eşikleri)

    private func fkSkor(_ pe: Double) -> Double {
        guard pe > 0 else { return 30 }   // negatif/0 = zarar → düşük
        switch pe { case ..<8: return 95; case 8..<12: return 80; case 12..<18: return 70
        case 18..<25: return 55; case 25..<40: return 40; default: return 25 }
    }
    private func pdddSkor(_ pb: Double) -> Double {
        guard pb > 0 else { return 40 }
        switch pb { case ..<1: return 90; case 1..<2: return 75; case 2..<4: return 60; case 4..<8: return 45; default: return 25 }
    }
    private func pegSkor(_ peg: Double) -> Double {
        guard peg > 0 else { return 50 }
        switch peg { case ..<1: return 90; case 1..<2: return 70; case 2..<3: return 50; default: return 30 }
    }
    private func roeSkor(_ roe01: Double) -> Double {
        let r = roe01 * 100
        switch r { case ..<0: return 10; case 0..<5: return 20; case 5..<10: return 40
        case 10..<15: return 55; case 15..<25: return 75; case 25..<40: return 90; default: return 95 }
    }
    private func roaSkor(_ roa01: Double) -> Double {
        let r = roa01 * 100
        switch r { case ..<0: return 10; case 0..<3: return 35; case 3..<7: return 55; case 7..<12: return 75; default: return 90 }
    }
    private func marjSkor(_ m01: Double) -> Double {
        let m = m01 * 100
        switch m { case ..<0: return 10; case 0..<5: return 35; case 5..<10: return 50
        case 10..<15: return 65; case 15..<20: return 80; default: return 90 }
    }
    private func brutMarjSkor(_ m01: Double) -> Double {
        let m = m01 * 100
        switch m { case ..<15: return 35; case 15..<30: return 55; case 30..<50: return 75; default: return 90 }
    }
    private func borcSkor(_ de: Double) -> Double {
        guard de >= 0 else { return 50 }
        switch de { case ..<0.3: return 95; case 0.3..<0.5: return 85; case 0.5..<1.0: return 70
        case 1.0..<1.5: return 55; case 1.5..<2.0: return 40; case 2.0..<3.0: return 25; default: return 10 }
    }
    private func cariSkor(_ cr: Double) -> Double {
        switch cr { case ..<1.0: return 30; case 1.0..<1.5: return 60; case 1.5..<3.0: return 85; default: return 65 }
    }
    private func buyumeSkor(_ yuzde: Double) -> Double {
        switch yuzde { case ..<(-10): return 10; case (-10)..<0: return 30; case 0..<5: return 50
        case 5..<10: return 60; case 10..<20: return 75; case 20..<30: return 90; default: return 95 }
    }
    private func temettuSkor(_ y01: Double) -> Double {
        let y = y01 * 100
        switch y { case ..<0.5: return 30; case 0.5..<2.0: return 50; case 2.0..<4.0: return 75; case 4.0..<6.0: return 90; default: return 60 }
    }
    private func fcfSkor(_ fcf: Double, piyasaDegeri: Double) -> Double {
        guard piyasaDegeri > 0 else { return 50 }
        let getiri = fcf / piyasaDegeri * 100   // FCF verimi %
        switch getiri { case ..<0: return 20; case 0..<3: return 55; case 3..<6: return 75; case 6..<10: return 88; default: return 95 }
    }
}
