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

/// Her motorun uyduğu sözleşme: mum dizisi → katkı (yoksa nil).
public protocol Motor: Sendable {
    var isim: String { get }
    func degerlendir(_ mumlar: [Mum]) -> Katki?
}
