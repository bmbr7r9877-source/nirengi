import Foundation
import Cekirdek

/// Öğrenme istemcisi — GitHub Actions robotunun ürettiği öğrenilmiş ağırlık (Ay) ve
/// kalibrasyonu (Güneş) uzak JSON'dan indirir, Konsey'e uygular.
///
/// Robot her iş günü `data/agirliklar.json` + `data/kalibrasyon.json` üretip repo'ya
/// commit eder. App bu ham (raw.githubusercontent) URL'leri okur. URL Ayarlar'dan
/// girilir (UserDefaults "ogrenme_base_url"); boşsa servis sessizce devre dışı (no-op)
/// ve Konsey varsayılan ağırlıklarla çalışır.
actor OgrenmeServisi {
    static let shared = OgrenmeServisi()

    private var agirliklar: OgrenilmisAgirliklar?
    private var kalibrasyon: Kalibrasyon?
    private var yuklendi = false

    /// Robot çıktısının bulunduğu kök URL (data/ klasörünün üst dizini).
    /// Örn: https://raw.githubusercontent.com/<kullanici>/<repo>/main
    private var taban: String? {
        let s = UserDefaults.standard.string(forKey: "ogrenme_base_url") ?? ""
        return s.isEmpty ? nil : s
    }

    /// Uzak JSON'ları bir kez indirir (varsa).
    func yukle() async {
        guard !yuklendi, let taban else { return }
        yuklendi = true
        let cozucu = JSONDecoder()
        cozucu.dateDecodingStrategy = .iso8601
        agirliklar = await indir("\(taban)/data/agirliklar.json", OgrenilmisAgirliklar.self, cozucu)
        kalibrasyon = await indir("\(taban)/data/kalibrasyon.json", Kalibrasyon.self, cozucu)
    }

    private func indir<T: Decodable>(_ url: String, _ tip: T.Type, _ cozucu: JSONDecoder) async -> T? {
        guard let u = URL(string: url),
              let (veri, _) = try? await URLSession.shared.data(from: u) else { return nil }
        return try? cozucu.decode(T.self, from: veri)
    }

    /// Öğrenilmiş çarpanlarla harmanlanmış Konsey ağırlıkları (yoksa varsayılan).
    func etkinAgirliklar() -> [String: Double] {
        var w = Konsey.varsayilanAgirliklar
        if let c = agirliklar?.carpanlar {
            for (motor, carpan) in c where w[motor] != nil {
                w[motor]! *= carpan
            }
        }
        return w
    }

    /// Güneş kalibrasyonunu bir skora uygular (yoksa skoru olduğu gibi döndürür).
    func kalibreEt(_ skor: Double) -> Double {
        guard let k = kalibrasyon else { return skor }
        return Gunes.uygula(skor, k)
    }

    /// Şeffaflık için: yüklenen kalibrasyon (UI'da "model güveni" göstermek için).
    func mevcutKalibrasyon() -> Kalibrasyon? { kalibrasyon }
}
