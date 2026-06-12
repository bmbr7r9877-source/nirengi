import Foundation

/// Borsa İstanbul VBTS tedbiri (tek pay + tek tedbir satırı).
/// Kaynak: borsaistanbul.com/erd/menkul_tedbir_listesi.csv (ücretsiz, resmi).
public struct Tedbir: Sendable, Equatable {
    /// Tedbir kademesi — VBTS'te hafiften ağıra doğru gelir.
    public enum Tur: String, Sendable {
        case acigaSatisYasagi = "PASKI"
        case krediliIslemYasagi = "PKISY"
        case brutTakas = "PBRUT"
        case emirPaketi = "PEMPK"
        case tekFiyat = "PTEKF"
        case emirIletimKisiti = "PEMIR"
        case diger = "?"
    }

    public let sembol: String
    public let tur: Tur
    public let ad: String          // CSV'deki insan-okur tedbir adı
    public let baslangic: Date?
    public let bitis: Date?

    /// Tedbirin fiyat keşfini ne kadar bozduğu → güven çarpanı (0..1).
    /// Kademe ağırlaştıkça (brüt takas, tek fiyat) momentumun sönme olasılığı artar.
    public var guvenCarpani: Double {
        switch tur {
        case .acigaSatisYasagi, .krediliIslemYasagi: return 0.85
        case .brutTakas: return 0.7
        case .emirPaketi, .emirIletimKisiti: return 0.6
        case .tekFiyat: return 0.5
        case .diger: return 0.8
        }
    }
}

/// VBTS tedbir CSV'sini ayrıştırır ve sembol bazında sorgulanır.
public enum TedbirListesi {
    /// CSV biçimi: ilk satır zaman damgası, ikinci satır başlık, sonrası
    /// `Pay Adı;İşlem Kodu;Tedbir Kodu;Tedbir Adı;İlk Tarih;Son Tarih;`.
    public static func ayristir(_ csv: String) -> [Tedbir] {
        let bicim = DateFormatter()
        bicim.dateFormat = "dd.MM.yyyy"
        bicim.locale = Locale(identifier: "tr_TR")
        bicim.timeZone = TimeZone(identifier: "Europe/Istanbul")

        var sonuc: [Tedbir] = []
        for satir in csv.split(whereSeparator: \.isNewline).dropFirst(2) {
            let alanlar = satir.split(separator: ";", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard alanlar.count >= 6, !alanlar[1].isEmpty else { continue }
            sonuc.append(Tedbir(sembol: alanlar[1],
                                tur: Tedbir.Tur(rawValue: alanlar[2]) ?? .diger,
                                ad: alanlar[3],
                                baslangic: bicim.date(from: alanlar[4]),
                                bitis: bicim.date(from: alanlar[5])))
        }
        return sonuc
    }

    /// Sembol → o gün geçerli tedbirler. Bitişi geçmiş satırlar elenir
    /// (bitiş günü dahil: tedbir o seans sonuna kadar sürer).
    public static func haritala(_ tedbirler: [Tedbir], tarih: Date = Date()) -> [String: [Tedbir]] {
        let gun = Calendar.current.startOfDay(for: tarih)
        var harita: [String: [Tedbir]] = [:]
        for t in tedbirler {
            if let bitis = t.bitis, bitis < gun { continue }
            harita[t.sembol, default: []].append(t)
        }
        return harita
    }

    /// Bir payın tedbir setinin bileşik güven çarpanı: en ağır tedbir belirler.
    public static func guvenCarpani(_ tedbirler: [Tedbir]) -> Double {
        tedbirler.map(\.guvenCarpani).min() ?? 1.0
    }
}
