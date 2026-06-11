import Foundation
import Cekirdek

/// Öğrenilmiş ağırlık (Ay) ve kalibrasyonun (Güneş) tüketim noktası.
///
/// İki kaynak olabilir:
///   1. CİHAZ (varsayılan): OgrenmeDeposu — uygulama kullanıldıkça telefonda biriken sicil.
///   2. UZAK (opsiyonel): Ayarlar'a raw URL girilirse bir robotun ürettiği JSON da indirilir.
/// İkisi de varsa ÖRNEK SAYISI BÜYÜK olan kazanır (daha çok kanıt = daha güvenilir).
actor OgrenmeServisi {
    static let shared = OgrenmeServisi()

    private var uzakAgirliklar: OgrenilmisAgirliklar?
    private var uzakKalibrasyon: Kalibrasyon?
    private var uzakYuklendi = false

    /// Robot çıktısının kök URL'si (boşsa uzak kaynak devre dışı).
    private var taban: String? {
        let s = UserDefaults.standard.string(forKey: "ogrenme_base_url") ?? ""
        return s.isEmpty ? nil : s
    }

    /// Uzak JSON'ları bir kez indirir (URL girilmişse).
    func yukle() async {
        guard !uzakYuklendi, let taban else { return }
        uzakYuklendi = true
        let cozucu = JSONDecoder()
        cozucu.dateDecodingStrategy = .iso8601
        uzakAgirliklar = await indir("\(taban)/data/agirliklar.json", OgrenilmisAgirliklar.self, cozucu)
        uzakKalibrasyon = await indir("\(taban)/data/kalibrasyon.json", Kalibrasyon.self, cozucu)
    }

    private func indir<T: Decodable>(_ url: String, _ tip: T.Type, _ cozucu: JSONDecoder) async -> T? {
        guard let u = URL(string: url),
              let (veri, _) = try? await URLSession.shared.data(from: u) else { return nil }
        return try? cozucu.decode(T.self, from: veri)
    }

    /// Etkin Konsey ağırlıkları: varsayılan × (cihaz/uzak hangisi daha çok örnekliyse onun çarpanı).
    func etkinAgirliklar() async -> [String: Double] {
        let yerel = await OgrenmeDeposu.shared.mevcutAgirliklar()
        let secilen: OgrenilmisAgirliklar?
        switch (yerel, uzakAgirliklar) {
        case let (y?, u?): secilen = y.ornekSayisi >= u.ornekSayisi ? y : u
        case let (y?, nil): secilen = y
        case let (nil, u?): secilen = u
        default: secilen = nil
        }
        var w = Konsey.varsayilanAgirliklar
        if let carpanlar = secilen?.carpanlar {
            for (motor, carpan) in carpanlar where w[motor] != nil {
                w[motor]! *= carpan
            }
        }
        return w
    }

    /// Etkin kalibrasyon (yoksa nil → skor olduğu gibi kalır).
    func mevcutKalibrasyon() async -> Kalibrasyon? {
        let yerel = await OgrenmeDeposu.shared.mevcutKalibrasyon()
        switch (yerel, uzakKalibrasyon) {
        case let (y?, u?): return y.ornekSayisi >= u.ornekSayisi ? y : u
        case let (y?, nil): return y
        case let (nil, u?): return u
        default: return nil
        }
    }
}
