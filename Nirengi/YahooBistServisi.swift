import Foundation
import Cekirdek

/// BIST verisini Yahoo Finance chart ucundan çeker (.IS sembolleri).
/// Tek çağrı → güncel fiyat + önceki kapanış + günlük mum geçmişi (Merkür için).
/// BIST'te Yahoo ~15 dk gecikmelidir.
enum YahooBistServisi {

    struct Sonuc {
        let fiyat: Double
        let oncekiKapanis: Double
        let mumlar: [Mum]
        let zaman: Date           // verinin kendi zaman damgası (regularMarketTime)
    }

    enum ServisHatasi: Error { case gecersizYanit, veriYok }

    static func cek(sembol: String, aralik: String = "5y", interval: String = "1d", borsaIstanbul: Bool = true) async throws -> Sonuc {
        let ek = borsaIstanbul ? ".IS" : ""
        let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(sembol)\(ek)?range=\(aralik)&interval=\(interval)")!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServisHatasi.gecersizYanit
        }

        guard
            let kok = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let chart = kok["chart"] as? [String: Any],
            let resultDizi = chart["result"] as? [[String: Any]],
            let r = resultDizi.first,
            let meta = r["meta"] as? [String: Any],
            let zaman = r["timestamp"] as? [Double],
            let gostergeler = r["indicators"] as? [String: Any],
            let quoteDizi = gostergeler["quote"] as? [[String: Any]],
            let q = quoteDizi.first
        else { throw ServisHatasi.gecersizYanit }

        let acilis = q["open"] as? [Double?] ?? []
        let yuksek = q["high"] as? [Double?] ?? []
        let dusuk = q["low"] as? [Double?] ?? []
        let kapanis = q["close"] as? [Double?] ?? []
        let hacim = q["volume"] as? [Double?] ?? []

        var mumlar: [Mum] = []
        for i in zaman.indices {
            guard i < kapanis.count,
                  let a = acilis[safe: i] ?? nil,
                  let y = yuksek[safe: i] ?? nil,
                  let d = dusuk[safe: i] ?? nil,
                  let k = kapanis[safe: i] ?? nil
            else { continue }
            let v = (hacim[safe: i] ?? nil) ?? 0
            mumlar.append(Mum(tarih: Date(timeIntervalSince1970: zaman[i]),
                              acilis: a, yuksek: y, dusuk: d, kapanis: k, hacim: v))
        }
        guard !mumlar.isEmpty else { throw ServisHatasi.veriYok }

        let fiyat = (meta["regularMarketPrice"] as? Double) ?? mumlar.last!.kapanis
        let oncekiKapanis = (meta["chartPreviousClose"] as? Double)
            ?? (mumlar.count > 1 ? mumlar[mumlar.count - 2].kapanis : fiyat)
        let zamanDamga: Date = (meta["regularMarketTime"] as? Double).map { Date(timeIntervalSince1970: $0) }
            ?? mumlar.last!.tarih

        return Sonuc(fiyat: fiyat, oncekiKapanis: oncekiKapanis, mumlar: mumlar, zaman: zamanDamga)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// USD/TRY geçmiş kurları (dolar-bazlı grafik için). Bir kez çekilip cache'lenir.
actor DovizServisi {
    static let shared = DovizServisi()
    private var kurlar: [(gun: Date, kur: Double)]?

    /// Gün → kur (artan tarihli dizi). Boşsa Yahoo'dan çeker.
    func usdtry() async -> [(gun: Date, kur: Double)] {
        if let k = kurlar { return k }
        do {
            let s = try await YahooBistServisi.cek(sembol: "USDTRY=X", borsaIstanbul: false)
            let cal = Calendar.current
            let dizi = s.mumlar.map { (cal.startOfDay(for: $0.tarih), $0.kapanis) }
            kurlar = dizi
            return dizi
        } catch {
            return []
        }
    }
}
