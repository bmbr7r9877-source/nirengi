import Foundation
import Cekirdek

/// Venüs sonucu — haberlerden duygu/etki.
struct VenusSonuc: Sendable {
    let skor: Double          // 0..100 (0 çok olumsuz, 50 nötr, 100 çok olumlu)
    let guven: Double         // 0..1
    let gerekce: String
    let baslikSayisi: Int
}

/// Venüs — haber/duygu motoru. (Argus "Hermes" mantığı.)
/// Google News RSS'ten şirket haberlerini çeker → Claude Haiku ile duygu skorlar.
/// LLM SADECE çekilen gerçek başlıkları okur (uydurmaz), yapılandırılmış çıktı verir.
/// Anthropic API anahtarı yoksa sessizce nil döner.
actor VenusServisi {
    static let shared = VenusServisi()
    private var cache: [String: VenusSonuc] = [:]
    private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

    /// Anthropic API anahtarı (kullanıcı girer; yoksa Venüs çalışmaz).
    private var apiKey: String? {
        let k = UserDefaults.standard.string(forKey: "anthropic_key") ?? ""
        return k.isEmpty ? nil : k
    }

    func analiz(sembol: String, ad: String) async -> VenusSonuc? {
        if let c = cache[sembol] { return c }
        guard let key = apiKey else { return nil }
        let basliklar = await haberCek(ad: ad)
        guard basliklar.count >= 2 else { return nil }
        guard let sonuc = await duyguSkorla(ad: ad, basliklar: basliklar, key: key) else { return nil }
        cache[sembol] = sonuc
        return sonuc
    }

    // MARK: - Google News RSS

    private func haberCek(ad: String) async -> [String] {
        let q = "\"\(ad)\"".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ad
        guard let url = URL(string: "https://news.google.com/rss/search?q=\(q)&hl=tr&gl=TR&ceid=TR:tr") else { return [] }
        var req = URLRequest(url: url); req.setValue(ua, forHTTPHeaderField: "User-Agent"); req.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let metin = String(data: data, encoding: .utf8) else { return [] }
        // <title>...</title> içinden başlıkları çıkar; ilki (feed başlığı) atlanır.
        var basliklar: [String] = []
        var arama = metin[...]
        while let bas = arama.range(of: "<title>"), let son = arama.range(of: "</title>", range: bas.upperBound..<arama.endIndex) {
            let t = String(arama[bas.upperBound..<son.lowerBound])
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { basliklar.append(t) }
            arama = arama[son.upperBound...]
        }
        // İlk başlık feed adı ("... - Google Haberler") → at; en güncel ~7 başlık.
        return Array(basliklar.dropFirst().prefix(7))
    }

    // MARK: - Claude Haiku (raw HTTP — Swift'te resmi SDK yok)

    private func duyguSkorla(ad: String, basliklar: [String], key: String) async -> VenusSonuc? {
        let haberMetni = basliklar.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let prompt = """
        Aşağıda \(ad) şirketiyle ilgili güncel haber başlıkları var. Bu başlıklara DAYANARAK \
        hissenin kısa vadeli görünümü için bir duygu/etki skoru ver. Sadece verilen başlıkları kullan, \
        bilgi uydurma. skor: 0 (çok olumsuz) — 50 (nötr) — 100 (çok olumlu). gerekce: tek cümle Türkçe.

        Başlıklar:
        \(haberMetni)
        """

        let govde: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 400,
            "messages": [["role": "user", "content": prompt]],
            "output_config": ["format": [
                "type": "json_schema",
                "schema": [
                    "type": "object",
                    "properties": [
                        "skor": ["type": "integer"],
                        "gerekce": ["type": "string"],
                    ],
                    "required": ["skor", "gerekce"],
                    "additionalProperties": false,
                ],
            ]],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: govde) else { return nil }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = body
        req.timeoutInterval = 30

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let kok = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = kok["content"] as? [[String: Any]],
              let metin = content.first?["text"] as? String,
              let icJson = metin.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: icJson) as? [String: Any]
        else { return nil }

        let skor = (parsed["skor"] as? Double) ?? Double(parsed["skor"] as? Int ?? 50)
        let gerekce = (parsed["gerekce"] as? String) ?? "Haber değerlendirmesi"
        // Güven: başlık sayısı arttıkça artar (max 0.8).
        let guven = min(0.8, 0.4 + Double(basliklar.count) * 0.06)
        return VenusSonuc(skor: max(0, min(100, skor)), guven: guven, gerekce: gerekce, baslikSayisi: basliklar.count)
    }
}
