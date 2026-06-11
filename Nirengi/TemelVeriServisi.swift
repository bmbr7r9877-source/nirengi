import Foundation
import Cekirdek

/// Yahoo quoteSummary'den temel veri çeker (çerez + crumb akışı).
/// 1) fc.yahoo.com → çerez, 2) /v1/test/getcrumb → crumb, 3) quoteSummary?crumb=...
actor TemelVeriServisi {
    static let shared = TemelVeriServisi()

    private var crumb: String?
    private var cache: [String: TemelVeri] = [:]
    private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

    /// Crumb'ı bir kez alır (URLSession.shared çerezleri otomatik saklar).
    private func crumbAl() async -> String? {
        if let c = crumb { return c }
        // 1) Çerez tetikle
        var r1 = URLRequest(url: URL(string: "https://fc.yahoo.com")!)
        r1.setValue(ua, forHTTPHeaderField: "User-Agent")
        _ = try? await URLSession.shared.data(for: r1)
        // 2) Crumb
        var r2 = URLRequest(url: URL(string: "https://query1.finance.yahoo.com/v1/test/getcrumb")!)
        r2.setValue(ua, forHTTPHeaderField: "User-Agent")
        guard let (d, resp) = try? await URLSession.shared.data(for: r2),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let c = String(data: d, encoding: .utf8), !c.isEmpty, !c.contains("{") else { return nil }
        crumb = c
        return c
    }

    func cek(sembol: String) async -> TemelVeri? {
        if let c = cache[sembol] { return c }
        guard let crumb = await crumbAl() else { return nil }

        let modules = "financialData,defaultKeyStatistics,summaryDetail"
        let crumbEnc = crumb.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? crumb
        let urlStr = "https://query1.finance.yahoo.com/v10/finance/quoteSummary/\(sembol).IS?modules=\(modules)&crumb=\(crumbEnc)"
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url); req.setValue(ua, forHTTPHeaderField: "User-Agent"); req.timeoutInterval = 20

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let kok = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let qs = kok["quoteSummary"] as? [String: Any],
              let sonuc = (qs["result"] as? [[String: Any]])?.first
        else { return nil }

        let fin = sonuc["financialData"] as? [String: Any] ?? [:]
        let ks = sonuc["defaultKeyStatistics"] as? [String: Any] ?? [:]
        let sd = sonuc["summaryDetail"] as? [String: Any] ?? [:]

        func raw(_ d: [String: Any], _ k: String) -> Double? {
            (d[k] as? [String: Any])?["raw"] as? Double
        }

        var v = TemelVeri()
        v.fk = raw(sd, "trailingPE")
        v.ileriFK = raw(sd, "forwardPE") ?? raw(ks, "forwardPE")
        v.pddd = raw(ks, "priceToBook")
        v.peg = raw(ks, "pegRatio")
        v.roe = raw(fin, "returnOnEquity")
        v.roa = raw(fin, "returnOnAssets")
        v.netMarj = raw(fin, "profitMargins")
        v.brutMarj = raw(fin, "grossMargins")
        v.borcOzkaynak = raw(fin, "debtToEquity").map { $0 / 100 }   // Yahoo % verir → orana çevir
        v.cariOran = raw(fin, "currentRatio")
        v.gelirBuyume = raw(fin, "revenueGrowth")
        v.karBuyume = raw(fin, "earningsGrowth")
        v.temettuVerimi = raw(sd, "dividendYield")
        v.serbestNakit = raw(fin, "freeCashflow")
        v.piyasaDegeri = raw(sd, "marketCap")

        cache[sembol] = v
        return v
    }
}
