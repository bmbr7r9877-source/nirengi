import Foundation
import Cekirdek

/// Borsa İstanbul'un resmi VBTS tedbir listesini çeker (ücretsiz CSV, key gerektirmez).
/// Liste seans sonrası güncellenir; gün içinde bir kez çekmek yeter.
actor TedbirServisi {
    static let shared = TedbirServisi()
    private static let kaynak = URL(string: "https://www.borsaistanbul.com/erd/menkul_tedbir_listesi.csv")!

    private var onbellek: [String: [Tedbir]]?
    private var onbellekGunu: Date?

    /// Sembol → geçerli tedbirler. Hata olursa boş döner (tedbir bilgisi
    /// iyileştirmedir, yokluğu analizi durdurmaz).
    func tedbirler() async -> [String: [Tedbir]] {
        let bugun = Calendar.current.startOfDay(for: Date())
        if let o = onbellek, onbellekGunu == bugun { return o }
        guard let (veri, _) = try? await URLSession.shared.data(from: Self.kaynak),
              let csv = String(data: veri, encoding: .utf8)
        else { return onbellek ?? [:] }
        let harita = TedbirListesi.haritala(TedbirListesi.ayristir(csv))
        onbellek = harita
        onbellekGunu = bugun
        return harita
    }
}
