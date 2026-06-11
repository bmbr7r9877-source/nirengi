import Foundation

/// Mars — faktör / smart-beta motoru. (Argus "Athena" mantığı, sıfırdan yazıldı.)
///
/// Dört faktör 0-100 skorlanır, sonra doğrusal-olmayan harmana sokulur (sigmoid):
///   • Değer  — F/K, PD/DD, PEG (ucuzluk). Temel veri ister.
///   • Kalite — ROE, net marj, borç/özkaynak. Temel veri ister.
///   • Momentum — 12-1 (Jegadeesh-Titman: 12 aylık getiri eksi son ay). Fiyattan.
///   • DüşükRisk — düşük volatilite (ATR%) + likidite (hacim·fiyat). Fiyattan.
///
/// Temel veri yoksa sadece fiyat faktörleri (Momentum + DüşükRisk) kullanılır ve
/// güven düşürülür (kısmî faktör profili). Bu, Argus Athena'nın Atlas'a bağımlı
/// faktörlerini BIST tarafında temel veri geldiğinde devreye sokar.
public struct Mars {
    public let isim = "Mars"

    public init() {}

    public struct Faktorler: Sendable {
        public let deger: Double?      // nil = temel veri yok
        public let kalite: Double?
        public let momentum: Double
        public let dusukRisk: Double
    }

    public struct Sonuc: Sendable {
        public let skor: Double           // 0..100
        public let faktorler: Faktorler
        public let baskinFaktor: String
        public let guvenilir: Bool        // temel veri var mı?
        public let aciklama: String
    }

    /// Ana API: mumlar (+ ops. temel veri) → faktör skoru.
    public func degerlendir(_ mumlar: [Mum], temel: TemelVeri? = nil) -> Sonuc? {
        let m = mumlar.sorted { $0.tarih < $1.tarih }
        guard m.count >= 30 else { return nil }

        let momentum = momentumFaktoru(m)
        let dusukRisk = dusukRiskFaktoru(m)
        let deger = temel.flatMap { degerFaktoru($0) }
        let kalite = temel.flatMap { kaliteFaktoru($0) }

        let faktorler = Faktorler(deger: deger, kalite: kalite, momentum: momentum, dusukRisk: dusukRisk)

        // Ağırlıklı harman — mevcut faktörler üzerinden normalize.
        //   Değer 0.28 · Kalite 0.27 · Momentum 0.25 · DüşükRisk 0.20
        var bilesenler: [(String, Double, Double)] = [
            ("Momentum", momentum, 0.25),
            ("Düşük Risk", dusukRisk, 0.20),
        ]
        if let d = deger  { bilesenler.append(("Değer", d, 0.28)) }
        if let k = kalite { bilesenler.append(("Kalite", k, 0.27)) }

        let toplamAgirlik = bilesenler.reduce(0) { $0 + $1.2 }
        var lineer = bilesenler.reduce(0) { $0 + $1.1 * ($1.2 / toplamAgirlik) }

        // Doğrusal-olmayan düzeltme (Athena polinom etkisi): kalite×momentum hizalanması
        // bonus, momentum×risk çatışması (yüksek momentum + yüksek risk) ceza.
        if let k = kalite {
            let q = k / 100, mo = momentum / 100
            lineer += (q * mo - 0.25) * 6              // hizalanma bonusu/cezası
        }
        let mo = momentum / 100, dr = dusukRisk / 100
        lineer += ((1 - dr) * mo - 0.25) * (-5)         // momentum yüksek + risk yüksek → ceza

        let skor = min(max(lineer, 0), 100)

        let baskin = bilesenler.max(by: { $0.1 * $0.2 < $1.1 * $1.2 })?.0 ?? "Momentum"
        let aciklama: String
        if let d = deger, let k = kalite {
            aciklama = String(format: "Değer %.0f · Kalite %.0f · Mom %.0f · Risk %.0f", d, k, momentum, dusukRisk)
        } else {
            aciklama = String(format: "Mom %.0f · Düşük Risk %.0f (temel veri yok)", momentum, dusukRisk)
        }

        return Sonuc(skor: skor, faktorler: faktorler, baskinFaktor: baskin,
                     guvenilir: temel != nil, aciklama: aciklama)
    }

    /// Konsey için katkı (güven: tam profil 0.7, kısmî 0.45).
    public func katki(_ mumlar: [Mum], temel: TemelVeri? = nil) -> Katki? {
        guard let s = degerlendir(mumlar, temel: temel) else { return nil }
        return Katki(motor: isim, skor: s.skor,
                     guven: s.guvenilir ? 0.7 : 0.45,
                     gerekce: "\(s.baskinFaktor) faktörü öne çıkıyor — \(s.aciklama)")
    }

    // MARK: - Faktörler

    /// 12-1 momentum (son ayı atlayarak), bantlı skor.
    private func momentumFaktoru(_ m: [Mum]) -> Double {
        let k = m.map(\.kapanis)
        let guncel = k.last ?? 0
        func getiri(ay: Int) -> Double? {
            let geri = ay * 21
            guard k.count > geri, k[k.count - 1 - geri] > 0 else { return nil }
            return (guncel - k[k.count - 1 - geri]) / k[k.count - 1 - geri]
        }
        guard let r12 = getiri(ay: 12), let r1 = getiri(ay: 1) else {
            // Yeterli geçmiş yok → kısa vadeli 3 aylık momentuma düş.
            guard let r3 = getiri(ay: 3) else { return 50 }
            return min(max(50 + r3 * 120, 0), 100)
        }
        let m12_1 = r12 - r1
        switch m12_1 {
        case 0.30...:     return 90
        case 0.15..<0.30: return 75
        case 0.0..<0.15:  return 60
        case -0.15..<0.0: return 40
        default:          return 25
        }
    }

    /// Düşük volatilite (ATR%) + likidite ortalaması → "düşük risk = yüksek skor".
    private func dusukRiskFaktoru(_ m: [Mum]) -> Double {
        var puanlar: [Double] = []

        if let atr = Gostergeler.sonATR(m, periyot: 14), let fiyat = m.last?.kapanis, fiyat > 0 {
            let atrYuzde = atr / fiyat * 100
            switch atrYuzde {
            case ..<1.5: puanlar.append(95)
            case ..<2.5: puanlar.append(80)
            case ..<4.0: puanlar.append(50)
            default:     puanlar.append(20)
            }
        }

        if m.count >= 5 {
            let son5 = m.suffix(5)
            let ortHacim = son5.map(\.hacim).reduce(0, +) / Double(son5.count)
            let fiyat = m.last?.kapanis ?? 1
            let tlHacim = ortHacim * fiyat
            switch tlHacim {
            case 50_000_000...: puanlar.append(100)
            case 10_000_000...: puanlar.append(80)
            case 1_000_000...:  puanlar.append(50)
            default:            puanlar.append(20)
            }
        }

        guard !puanlar.isEmpty else { return 50 }
        return puanlar.reduce(0, +) / Double(puanlar.count)
    }

    /// Değer faktörü: ucuzluk (F/K, PD/DD, PEG). Düşük çarpan → yüksek skor.
    private func degerFaktoru(_ t: TemelVeri) -> Double? {
        var puanlar: [Double] = []
        if let fk = t.fk, fk > 0 {
            switch fk {
            case ..<8:   puanlar.append(95)
            case ..<12:  puanlar.append(80)
            case ..<18:  puanlar.append(60)
            case ..<28:  puanlar.append(40)
            default:     puanlar.append(20)
            }
        }
        if let pddd = t.pddd, pddd > 0 {
            switch pddd {
            case ..<1.0: puanlar.append(95)
            case ..<2.0: puanlar.append(75)
            case ..<4.0: puanlar.append(50)
            default:     puanlar.append(25)
            }
        }
        if let peg = t.peg, peg > 0 {
            switch peg {
            case ..<1.0: puanlar.append(90)
            case ..<2.0: puanlar.append(60)
            default:     puanlar.append(30)
            }
        }
        guard !puanlar.isEmpty else { return nil }
        return puanlar.reduce(0, +) / Double(puanlar.count)
    }

    /// Kalite faktörü: ROE + net marj (yüksek iyi) + borç/özkaynak (düşük iyi).
    private func kaliteFaktoru(_ t: TemelVeri) -> Double? {
        var puanlar: [Double] = []
        if let roe = t.roe {
            switch roe {
            case 0.25...:    puanlar.append(95)
            case 0.15..<0.25: puanlar.append(78)
            case 0.08..<0.15: puanlar.append(58)
            case 0.0..<0.08:  puanlar.append(40)
            default:          puanlar.append(20)
            }
        }
        if let marj = t.netMarj {
            switch marj {
            case 0.20...:     puanlar.append(92)
            case 0.10..<0.20: puanlar.append(72)
            case 0.03..<0.10: puanlar.append(52)
            case 0.0..<0.03:  puanlar.append(35)
            default:          puanlar.append(18)
            }
        }
        if let bo = t.borcOzkaynak, bo >= 0 {
            switch bo {
            case ..<0.3: puanlar.append(95)
            case ..<0.7: puanlar.append(75)
            case ..<1.5: puanlar.append(50)
            default:     puanlar.append(25)
            }
        }
        guard !puanlar.isEmpty else { return nil }
        return puanlar.reduce(0, +) / Double(puanlar.count)
    }
}
