import Foundation

/// Ay — ağırlık öğrenme motoru. (Argus "Chiron" mantığı, sıfırdan/sadeleştirilmiş.)
///
/// Saf fonksiyon: olgun (sonucu belli) sicil kayıtlarından her motorun İSABET oranını
/// çıkarır, buna göre Konsey'in varsayılan ağırlığını çarpanla düzeltir.
///   • Bir motor bir kayıtta "boğa" oy verdiyse (skor ≥ 55) ve fiyat yükseldiyse → isabet.
///   • "ayı" oy (skor ≤ 45) ve fiyat düştüyse → isabet. Nötr oylar sayılmaz.
///   • isabet > 0.5 → ağırlık artar, < 0.5 → azalır. Çarpan [0.5, 1.5] arası.
///
/// Az veri varsa shrinkage: çarpan 1.0'a (nötr) çekilir — erken aşırı-öğrenmeyi önler.
public struct Ay {
    public let isim = "Ay"

    public let esik: Double          // boğa/ayı oyu eşiği (50 ± esik)
    public let getiriEsik: Double    // anlamlı hareket eşiği (%)
    public let minOrnek: Int         // bir motor için güvenilir minimum kayıt

    public init(esik: Double = 5, getiriEsik: Double = 1.0, minOrnek: Int = 20) {
        self.esik = esik
        self.getiriEsik = getiriEsik
        self.minOrnek = minOrnek
    }

    public func ogren(_ kayitlar: [SicilKaydi]) -> OgrenilmisAgirliklar {
        let olgun = kayitlar.filter { $0.olgun }

        var dogru: [String: Int] = [:]
        var toplam: [String: Int] = [:]

        for k in olgun {
            guard let g = k.getiriYuzde else { continue }
            for (motor, oy) in k.motorlar {
                let boga = oy.skor >= 50 + esik
                let ayi = oy.skor <= 50 - esik
                guard boga || ayi else { continue }   // nötr sayılmaz
                toplam[motor, default: 0] += 1
                let isabetli = (boga && g > getiriEsik) || (ayi && g < -getiriEsik)
                if isabetli { dogru[motor, default: 0] += 1 }
            }
        }

        var carpanlar: [String: Double] = [:]
        var isabetler: [String: Double] = [:]
        for (motor, n) in toplam {
            let oran = Double(dogru[motor] ?? 0) / Double(n)
            isabetler[motor] = oran
            // Shrinkage: örnek minOrnek'in altındaysa nötre yaklaştır.
            let guc = min(1.0, Double(n) / Double(minOrnek))
            let ham = 1.0 + (oran - 0.5) * 2.0          // 0.0..2.0
            let carpan = 1.0 + (ham - 1.0) * guc        // az veri → 1.0'a yakın
            carpanlar[motor] = min(1.5, max(0.5, carpan))
        }

        return OgrenilmisAgirliklar(
            guncelleme: Date(),
            ornekSayisi: olgun.count,
            carpanlar: carpanlar,
            isabet: isabetler
        )
    }
}
