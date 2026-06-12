import Foundation

/// Tek bir günlük (veya periyodik) mum verisi.
public struct Mum: Sendable, Equatable {
    public let tarih: Date
    public let acilis: Double
    public let yuksek: Double
    public let dusuk: Double
    public let kapanis: Double
    public let hacim: Double

    public init(tarih: Date, acilis: Double, yuksek: Double, dusuk: Double, kapanis: Double, hacim: Double) {
        self.tarih = tarih
        self.acilis = acilis
        self.yuksek = yuksek
        self.dusuk = dusuk
        self.kapanis = kapanis
        self.hacim = hacim
    }
}

/// Bir motorun ürettiği katkı: 0-100 skor + güven + kısa gerekçe.
/// Konsey bu katkıları ağırlıklı harmanlar.
public struct Katki: Sendable, Equatable {
    public let motor: String
    public let skor: Double      // 0...100 (50 = nötr)
    public let guven: Double     // 0...1
    public let gerekce: String

    public init(motor: String, skor: Double, guven: Double, gerekce: String) {
        self.motor = motor
        self.skor = max(0, min(100, skor))
        self.guven = max(0, min(1, guven))
        self.gerekce = gerekce
    }
}

/// Nihai karar.
public enum Karar: String, Sendable {
    case al = "Al"
    case tut = "Tut"
    case sat = "Sat"
    case yetersizVeri = "—"

    public static func skordan(_ skor: Double) -> Karar {
        switch skor {
        case 60...: return .al
        case ...40: return .sat
        default:    return .tut
        }
    }
}

/// Piyasaya özgü yapısal parametreler. Motorlar mutlak eşik gömmek yerine
/// buradan okur; yeni piyasa = yeni profil, kod değişmez.
public struct PiyasaProfili: Sendable {
    /// Günlük fiyat değişim limiti (% — yoksa nil). BIST: ±10 (VWAP bazlı tavan/taban).
    public let gunlukLimitYuzde: Double?
    /// Gidiş-dönüş işlem maliyeti (%). BIST: ~%0.2/yön komisyon + kayma ≈ %0.5.
    public let islemMaliyetiYuzde: Double
    /// Bir barın "limit hareketi" sayılması için limitin ne kadarına ulaşması gerekir (0..1).
    public let limitYakinlikOrani: Double
    /// Sat sinyali için ek kanıt çarpanı (≥1). Yüksek enflasyonlu piyasada nominal
    /// fiyatlar yukarı sürüklenir; aşağı tahmin daha kolay yanılır.
    public let satEdgeCarpani: Double

    public init(gunlukLimitYuzde: Double?, islemMaliyetiYuzde: Double,
                limitYakinlikOrani: Double = 0.9, satEdgeCarpani: Double = 1.0) {
        self.gunlukLimitYuzde = gunlukLimitYuzde
        self.islemMaliyetiYuzde = islemMaliyetiYuzde
        self.limitYakinlikOrani = limitYakinlikOrani
        self.satEdgeCarpani = satEdgeCarpani
    }

    public static let bist = PiyasaProfili(gunlukLimitYuzde: 10, islemMaliyetiYuzde: 0.5,
                                           limitYakinlikOrani: 0.9, satEdgeCarpani: 1.3)
    /// Limitsiz piyasalar (ABD hissesi, kripto) için makul varsayılan.
    public static let serbest = PiyasaProfili(gunlukLimitYuzde: nil, islemMaliyetiYuzde: 0.2)
}

/// Her motorun uyduğu sözleşme: mum dizisi → katkı (yoksa nil).
public protocol Motor: Sendable {
    var isim: String { get }
    func degerlendir(_ mumlar: [Mum]) -> Katki?
}
