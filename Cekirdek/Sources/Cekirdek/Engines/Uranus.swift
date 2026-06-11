import Foundation

/// Uranüs — sektör rotasyonu motoru. (Argus "Demeter" mantığı, sıfırdan yazıldı.)
///
/// İki katman:
///   1. SEKTÖR SKORU (endeks bazlı): para hangi sektöre akıyor?
///      momentum(%40) + benchmark'a görece güç eğimi(%30) + piyasa rejimi(%30).
///      (Argus'ta ayrıca şok etkisi %25 vardı — petrol/faiz/DXY/VIX sürücüleri.
///       BIST tarafında bu sürücü verileri henüz yok; eklenince bileşen geri gelir.)
///   2. HİSSE KATKISI: hissenin kendi sektörüne karşı 20 günlük alfası
///      sektör skoruyla harmanlanır → "güçlü sektörde güçlü hisse" en yüksek skoru alır.
public struct Uranus {
    public let isim = "Uranüs"

    public init() {}

    // MARK: - Sektör skoru

    public struct SektorSkoru: Sendable {
        public let skor: Double          // 0..100
        public let momentum: Double
        public let gorecGuc: Double
        public let rejim: Double
        public let aciklama: String
    }

    /// Sektör endeksinin gücü (benchmark = XU100).
    public func sektorSkoru(sektor: [Mum], benchmark: [Mum]) -> SektorSkoru? {
        let s = sektor.sorted { $0.tarih < $1.tarih }.map(\.kapanis)
        let b = benchmark.sorted { $0.tarih < $1.tarih }.map(\.kapanis)
        guard s.count >= 60, b.count >= 60 else { return nil }

        // 1. Momentum (%40): MA50 üstü/altı taban + 20 günlük log-getiri düzeltmesi.
        let ma50 = s.suffix(50).reduce(0, +) / Double(min(50, s.count))
        let guncel = s.last ?? 0
        let taban = guncel > ma50 ? 75.0 : 25.0
        let roc20 = logGetiriler(s).suffix(20).reduce(0, +)
        let momentum = min(max(taban + roc20 * 100, 0), 100)

        // 2. Görece güç (%30): sektör/benchmark oranının son 20 günlük eğimi.
        let rsOran = gorecGucOrani(varlik: s, benchmark: b)
        let rsEgim = egim(Array(rsOran.suffix(20)))
        let gorecGuc = min(max((rsEgim + 0.005) / 0.01 * 100, 0), 100)

        // 3. Rejim (%30): benchmark MA200 üstünde mi + benchmark volatilitesi.
        var rejim = 55.0
        let ma200 = b.suffix(200).reduce(0, +) / Double(min(200, b.count))
        if (b.last ?? 0) > ma200 { rejim += 12 } else { rejim -= 12 }
        let benchVol = volatiliteYuzde(b, pencere: 20)
        if benchVol > 2.5 { rejim -= 10 }            // çalkantılı piyasa: rotasyon güvenilmez
        rejim = min(max(rejim, 0), 100)

        let skor = momentum * 0.40 + gorecGuc * 0.30 + rejim * 0.30
        let aciklama = String(format: "Mom %.0f · RS %.0f · Rejim %.0f", momentum, gorecGuc, rejim)
        return SektorSkoru(skor: skor, momentum: momentum, gorecGuc: gorecGuc, rejim: rejim, aciklama: aciklama)
    }

    // MARK: - Hisse katkısı

    public struct HisseSonuc: Sendable {
        public let skor: Double          // 0..100 (harman)
        public let sektorSkoru: SektorSkoru
        public let alfa20: Double        // hisse - sektör, % (20 gün)
        public let aciklama: String
    }

    /// Hisse + kendi sektör endeksi + benchmark → harman skor.
    /// skor = 0.6·sektör + 0.4·alfaSkoru;  alfaSkoru = 50 + alfa·5 (±%10 alfa → 0/100 doygunluk)
    public func hisseSonucu(hisse: [Mum], sektor: [Mum], benchmark: [Mum]) -> HisseSonuc? {
        guard let sek = sektorSkoru(sektor: sektor, benchmark: benchmark) else { return nil }
        let h = hisse.sorted { $0.tarih < $1.tarih }.map(\.kapanis)
        let s = sektor.sorted { $0.tarih < $1.tarih }.map(\.kapanis)
        guard let hisseGetiri = yuzdeGetiri(h, gun: 20),
              let sektorGetiri = yuzdeGetiri(s, gun: 20) else { return nil }

        let alfa = hisseGetiri - sektorGetiri
        let alfaSkoru = min(max(50 + alfa * 5, 0), 100)
        let skor = sek.skor * 0.6 + alfaSkoru * 0.4

        let alfaNot: String
        if alfa > 1.5 { alfaNot = String(format: "sektörden %%%.1f önde", alfa) }
        else if alfa < -1.5 { alfaNot = String(format: "sektörden %%%.1f geride", abs(alfa)) }
        else { alfaNot = "sektörle paralel" }

        return HisseSonuc(skor: skor, sektorSkoru: sek, alfa20: alfa,
                          aciklama: "Sektör \(Int(sek.skor.rounded())) · \(alfaNot)")
    }

    /// Konsey için Katki üretimi.
    public func katki(hisse: [Mum], sektor: [Mum], benchmark: [Mum]) -> Katki? {
        guard let r = hisseSonucu(hisse: hisse, sektor: sektor, benchmark: benchmark) else { return nil }
        // Güven: yeterli veri varsa 0.7 (rotasyon sinyali orta vadeli, tek başına karar verdirmez).
        return Katki(motor: isim, skor: r.skor, guven: 0.7, gerekce: r.aciklama)
    }

    // MARK: - Yardımcılar (saf matematik)

    private func logGetiriler(_ d: [Double]) -> [Double] {
        guard d.count > 1 else { return [] }
        var out: [Double] = []
        for i in 1..<d.count where d[i - 1] > 0 && d[i] > 0 {
            out.append(log(d[i] / d[i - 1]))
        }
        return out
    }

    private func gorecGucOrani(varlik: [Double], benchmark: [Double]) -> [Double] {
        let n = min(varlik.count, benchmark.count)
        guard n > 0 else { return [] }
        let v = varlik.suffix(n), b = benchmark.suffix(n)
        return zip(v, b).compactMap { $1 > 0 ? $0 / $1 : nil }
    }

    /// Basit doğrusal regresyon eğimi.
    private func egim(_ d: [Double]) -> Double {
        let n = Double(d.count)
        guard n >= 2 else { return 0 }
        let xOrt = (n - 1) / 2
        let yOrt = d.reduce(0, +) / n
        var pay = 0.0, payda = 0.0
        for (i, y) in d.enumerated() {
            let dx = Double(i) - xOrt
            pay += dx * (y - yOrt)
            payda += dx * dx
        }
        // Oran serisinde mutlak eğim ölçeği seriye bağlı → normalize (ortalamaya böl).
        return payda > 0 && yOrt != 0 ? (pay / payda) / yOrt : 0
    }

    private func volatiliteYuzde(_ d: [Double], pencere: Int) -> Double {
        let k = Array(d.suffix(pencere + 1))
        guard k.count >= 3 else { return 0 }
        var g: [Double] = []
        for i in 1..<k.count where k[i - 1] > 0 { g.append((k[i] - k[i - 1]) / k[i - 1]) }
        let ort = g.reduce(0, +) / Double(g.count)
        let varyans = g.reduce(0) { $0 + pow($1 - ort, 2) } / Double(max(1, g.count - 1))
        return sqrt(varyans) * 100
    }

    private func yuzdeGetiri(_ d: [Double], gun: Int) -> Double? {
        guard d.count > gun, let son = d.last else { return nil }
        let eski = d[d.count - 1 - gun]
        guard eski > 0 else { return nil }
        return (son - eski) / eski * 100
    }
}
