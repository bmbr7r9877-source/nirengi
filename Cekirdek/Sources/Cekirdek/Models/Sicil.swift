import Foundation

/// Bir motorun tek bir tahmindeki oyu (skor + güven).
public struct MotorOyu: Codable, Sendable, Equatable {
    public let skor: Double
    public let guven: Double
    public init(skor: Double, guven: Double) {
        self.skor = skor
        self.guven = guven
    }
}

/// Sicil kaydı — bir günde bir sembol için verilen tahmin ve (olgunlaşınca) sonucu.
/// Ay (öğrenme) ve Güneş (kalibrasyon) motorları bu kayıtların geçmişinden beslenir.
/// JSON dosyada saklanır; GitHub Actions her gün ekler/değerlendirir.
public struct SicilKaydi: Codable, Sendable, Equatable {
    public let tarih: Date              // tahminin yapıldığı gün
    public let sembol: String
    public let fiyat: Double            // tahmin anındaki kapanış
    public let nirengiSkor: Double
    public let karar: String            // "Al"/"Tut"/"Sat"
    public let motorlar: [String: MotorOyu]

    // --- Sonuç (olgunlaşınca doldurulur) ---
    public var degerlendirmeTarihi: Date?
    public var fiyatSonra: Double?
    public var getiriYuzde: Double?     // (fiyatSonra-fiyat)/fiyat*100

    public init(tarih: Date, sembol: String, fiyat: Double, nirengiSkor: Double,
                karar: String, motorlar: [String: MotorOyu]) {
        self.tarih = tarih
        self.sembol = sembol
        self.fiyat = fiyat
        self.nirengiSkor = nirengiSkor
        self.karar = karar
        self.motorlar = motorlar
    }

    /// Değerlendirilmiş mi (sonuç fiyatı var mı)?
    public var olgun: Bool { getiriYuzde != nil }
}

/// Ay'ın ürettiği öğrenilmiş motor ağırlıkları (Konsey'in varsayılanını çarpan olarak düzeltir).
public struct OgrenilmisAgirliklar: Codable, Sendable {
    public var guncelleme: Date
    public var ornekSayisi: Int                 // kaç olgun kayıttan öğrenildi
    public var carpanlar: [String: Double]      // motor → ağırlık çarpanı (0.5..1.5)
    public var isabet: [String: Double]         // motor → isabet oranı (0..1, şeffaflık)
    public init(guncelleme: Date, ornekSayisi: Int, carpanlar: [String: Double], isabet: [String: Double]) {
        self.guncelleme = guncelleme
        self.ornekSayisi = ornekSayisi
        self.carpanlar = carpanlar
        self.isabet = isabet
    }
}

/// Güneş'in ürettiği kalibrasyon — nihai skoru geçmiş isabete göre törpüler.
public struct Kalibrasyon: Codable, Sendable {
    public var guncelleme: Date
    public var ornekSayisi: Int
    public var guvenKatsayi: Double             // 0..1: skoru 50'ye ne kadar çekelim (1=dokunma)
    public var genelIsabet: Double              // model genel isabet oranı (şeffaflık)
    public init(guncelleme: Date, ornekSayisi: Int, guvenKatsayi: Double, genelIsabet: Double) {
        self.guncelleme = guncelleme
        self.ornekSayisi = ornekSayisi
        self.guvenKatsayi = guvenKatsayi
        self.genelIsabet = genelIsabet
    }
}
