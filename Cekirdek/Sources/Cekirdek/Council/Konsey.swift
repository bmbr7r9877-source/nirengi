import Foundation

/// Konsey — motorların katkılarını ağırlıklı harmanlayıp tek karara çevirir.
/// Şeffaflık ilkesi: nihai skorun yanında her motorun gerekçesi de döner.
public struct Konsey: Sendable {
    public struct Sonuc: Sendable {
        public let skor: Double          // 0...100
        public let karar: Karar
        public let katkilar: [Katki]
    }

    private let motorlar: [Motor]
    /// Motor ismine göre ağırlık (yoksa 1.0). İleride Terazi (öğrenme) besler.
    private let agirliklar: [String: Double]

    public init(motorlar: [Motor], agirliklar: [String: Double] = [:]) {
        self.motorlar = motorlar
        self.agirliklar = agirliklar
    }

    public func karar(_ mumlar: [Mum]) -> Sonuc {
        let katkilar = motorlar.compactMap { $0.degerlendir(mumlar) }
        guard !katkilar.isEmpty else {
            return Sonuc(skor: 50, karar: .yetersizVeri, katkilar: [])
        }
        var toplamAgirlik = 0.0
        var toplamSkor = 0.0
        for k in katkilar {
            let w = (agirliklar[k.motor] ?? 1.0) * k.guven
            toplamSkor += k.skor * w
            toplamAgirlik += w
        }
        let skor = toplamAgirlik > 0 ? toplamSkor / toplamAgirlik : 50
        return Sonuc(skor: skor, karar: .skordan(skor), katkilar: katkilar)
    }

    /// Hazır katkı listesini (farklı veri ihtiyaçlı motorlardan toplanmış) harmanlar.
    /// Her katkı `guven × ağırlık` ile tartılır. Tek "Nirengi skoru" + karar üretir.
    public static func harmanla(_ katkilar: [Katki], agirliklar: [String: Double] = [:]) -> Sonuc {
        guard !katkilar.isEmpty else { return Sonuc(skor: 50, karar: .yetersizVeri, katkilar: []) }
        var toplamAgirlik = 0.0, toplamSkor = 0.0
        for k in katkilar {
            let w = (agirliklar[k.motor] ?? 1.0) * k.guven
            toplamSkor += k.skor * w
            toplamAgirlik += w
        }
        let skor = toplamAgirlik > 0 ? toplamSkor / toplamAgirlik : 50
        return Sonuc(skor: skor, karar: .skordan(skor), katkilar: katkilar)
    }

    /// Nirengi varsayılan motor ağırlıkları (Terazi/öğrenme gelene kadar sabit).
    public static let varsayilanAgirliklar: [String: Double] = [
        // Neptün 0.15→0.08 (2026-06 kıyas: 2y BIST30'da yön isabeti <%50 —
        // edge kanıtlanana dek düşük; Ay öğrenmesi sicil birikince düzeltir).
        "Merkür": 0.30, "Satürn": 0.20, "Neptün": 0.08,
        "Jüpiter": 0.13, "Uranüs": 0.12, "Venüs": 0.10,
        "Mars": 0.10, "Plüton": 0.08,
    ]
}
