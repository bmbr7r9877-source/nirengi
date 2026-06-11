import Foundation
import Cekirdek

/// Kaynak-bağımsız fiyat verisi paketi (hangi sağlayıcıdan geldiği fark etmez).
struct FiyatVerisi {
    let fiyat: Double
    let oncekiKapanis: Double
    let mumlar: [Mum]
    let zaman: Date
}

/// "Priz": fiyat verisi sağlayıcı arayüzü. Uygulama yalnızca bu arayüzü tanır;
/// arkasında bugün Yahoo var, yarın EODHD gibi ikinci bir sağlayıcı takılabilir —
/// uygulamanın geri kalanına dokunmadan.
protocol VeriKaynagi: Sendable {
    var ad: String { get }
    func cek(sembol: String, aralik: String, interval: String, borsaIstanbul: Bool) async throws -> FiyatVerisi
}

/// Yahoo Finance fişi (mevcut YahooBistServisi'ni sarar).
struct YahooKaynagi: VeriKaynagi {
    let ad = "Yahoo"
    func cek(sembol: String, aralik: String, interval: String, borsaIstanbul: Bool) async throws -> FiyatVerisi {
        let s = try await YahooBistServisi.cek(sembol: sembol, aralik: aralik, interval: interval, borsaIstanbul: borsaIstanbul)
        return FiyatVerisi(fiyat: s.fiyat, oncekiKapanis: s.oncekiKapanis, mumlar: s.mumlar, zaman: s.zaman)
    }
}

/// Kaynak zinciri: sırayla dener, ilk başarılı sonuç döner.
/// Yedek sağlayıcı eklemek = diziye bir eleman eklemek (örn. EODHDKaynagi(apiKey:)).
enum VeriMerkezi {
    static let kaynaklar: [VeriKaynagi] = [
        YahooKaynagi(),
        // EODHDKaynagi(apiKey: ...),   ← yedek kaynak alınınca buraya takılır
    ]

    static func cek(sembol: String, aralik: String = "5y", interval: String = "1d",
                    borsaIstanbul: Bool = true) async throws -> FiyatVerisi {
        var sonHata: Error = YahooBistServisi.ServisHatasi.veriYok
        for kaynak in kaynaklar {
            do {
                return try await kaynak.cek(sembol: sembol, aralik: aralik,
                                            interval: interval, borsaIstanbul: borsaIstanbul)
            } catch {
                sonHata = error   // bu kaynak düştü → sıradakini dene
            }
        }
        throw sonHata
    }
}
