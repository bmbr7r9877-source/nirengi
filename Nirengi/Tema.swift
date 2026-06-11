import SwiftUI

/// Tema — sade, açık (Midas tarzı) tek renk kaynağı.
enum Tema {
    static let arkaplan   = Color(red: 1, green: 1, blue: 1)
    static let yuzey      = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let kenar      = Color(red: 0.90, green: 0.92, blue: 0.95)
    static let metin      = Color(red: 0.06, green: 0.09, blue: 0.16)
    static let metinIkincil = Color(red: 0.39, green: 0.45, blue: 0.55)
    /// Marka rengi — turuncu (vurgu/aksан).
    static let turuncu    = Color(red: 1.0, green: 0.45, blue: 0.10)
    static let turuncuAcik = Color(red: 1.0, green: 0.60, blue: 0.30)
    /// Güven rengi — lacivert (taban/başlık/zemin).
    static let lacivert    = Color(red: 0.055, green: 0.13, blue: 0.25)
    static let lacivertAcik = Color(red: 0.09, green: 0.19, blue: 0.36)
    static let yesil      = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let kirmizi    = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let gri        = Color(red: 0.58, green: 0.64, blue: 0.72)

    /// Skora göre renk: yüksek=yeşil, orta=turuncu (marka), düşük=kırmızı.
    static func skorRengi(_ skor: Double) -> Color {
        switch skor {
        case 60...: return yesil
        case ..<45: return kirmizi
        default:    return turuncu
        }
    }
}
