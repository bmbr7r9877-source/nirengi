import Foundation

/// Güneş — meta kalibrasyon motoru. (Argus "Alkindus" mantığı, sıfırdan/sadeleştirilmiş.)
///
/// Saf fonksiyon: Konsey'in geçmiş "Al"/"Sat" kararları gerçekten tuttu mu? Modelin
/// kendine güveni geçmiş isabetiyle uyumlu mu? Aşırı-güvenliyse skoru 50'ye (nötre)
/// çekecek bir GÜVEN KATSAYISI üretir (0..1, 1 = dokunma).
///
///   • Yön doğruluğu: karar "Al" iken getiri > +eşik, "Sat" iken < −eşik → isabet.
///   • Genel isabet ~0.5 (yazı-tura) ise model bilgi taşımıyor → skoru kıs.
///   • İsabet 0.5'in belirgin üstündeyse → skora güven, dokunma.
///   • Az veri → temkin (katsayı düşük tutulur, shrinkage).
public struct Gunes {
    public let isim = "Güneş"

    public let getiriEsik: Double
    public let minOrnek: Int

    public init(getiriEsik: Double = 1.0, minOrnek: Int = 40) {
        self.getiriEsik = getiriEsik
        self.minOrnek = minOrnek
    }

    public func kalibreEt(_ kayitlar: [SicilKaydi]) -> Kalibrasyon {
        let yonlu = kayitlar.filter { $0.olgun && $0.karar != "Tut" }

        guard !yonlu.isEmpty else {
            // Hiç sonuç yok → temkinli başlangıç: skoru yarı yola çek.
            return Kalibrasyon(guncelleme: Date(), ornekSayisi: 0, guvenKatsayi: 0.6, genelIsabet: 0.5)
        }

        var dogru = 0
        for k in yonlu {
            guard let g = k.getiriYuzde else { continue }
            let isabetli = (k.karar == "Al" && g > getiriEsik) || (k.karar == "Sat" && g < -getiriEsik)
            if isabetli { dogru += 1 }
        }
        let isabet = Double(dogru) / Double(yonlu.count)

        // Edge: 0.5 isabet → 0 katsayı temayülü; 0.65+ isabet → 1.0'a yakın.
        // (0.5 → 0, 0.65 → 1.0 doğrusal; clamp 0..1)
        let kenar = min(1.0, max(0.0, (isabet - 0.5) / 0.15))
        // Shrinkage: az veride katsayıyı yukarı çekme (henüz güvenme → ama tamamen sıfırlama).
        let guc = min(1.0, Double(yonlu.count) / Double(minOrnek))
        let katsayi = 0.5 + (kenar - 0.5) * guc * 0.9 + (1 - guc) * 0.1
        let guvenKatsayi = min(1.0, max(0.3, katsayi))

        return Kalibrasyon(
            guncelleme: Date(),
            ornekSayisi: yonlu.count,
            guvenKatsayi: guvenKatsayi,
            genelIsabet: isabet
        )
    }

    /// Kalibrasyonu bir skora uygula: 50 etrafında güven katsayısıyla törpüle.
    public static func uygula(_ skor: Double, _ k: Kalibrasyon) -> Double {
        50 + (skor - 50) * k.guvenKatsayi
    }
}
