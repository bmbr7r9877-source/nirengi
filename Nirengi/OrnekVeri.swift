import Foundation
import Cekirdek

/// Bir hisse için hesaplanmış görünüm modeli.
struct HisseSatiri: Identifiable {
    let id = UUID()
    let sembol: String
    let ad: String
    let fiyat: Double
    let gunlukDegisim: Double      // %
    let sonuc: Merkur.Sonuc
    let mumlar: [Mum]
    var zaman: Date = Date()       // verinin zaman damgası (Yahoo regularMarketTime)
    var endeksMi: Bool = false     // endeks ise fiyat ₺ değil puan

    /// Belirtilen gün öncesine göre % değişim (zaman aralığı seçici için).
    /// İstenen dönem mevcut veriden uzunsa en eski mumu baz alır (5Y vb.).
    func degisim(gunOnce: Int) -> Double {
        guard mumlar.count > 1 else { return gunlukDegisim }
        let son = mumlar.last!.kapanis
        let idx = max(0, mumlar.count - 1 - gunOnce)
        let eski = mumlar[idx].kapanis
        guard eski > 0 else { return 0 }
        return (son - eski) / eski * 100
    }
}

/// ÖRNEK VERİ — gerçek BIST verisi henüz bağlı değil.
/// Her sembol için sentetik mum üretip Merkür ile gerçek skor hesaplar.
/// (Amaç: arayüzü gerçek motorla canlı görmek.)
enum OrnekVeri {

    static func uret() -> [HisseSatiri] {
        let tanim: [(String, String, Double, Double)] = [
            // sembol, ad, başlangıç fiyat, GÜNLÜK YÜZDE eğim
            ("THYAO", "Türk Hava Yolları", 310, 0.18),
            ("ASELS", "Aselsan",            92, 0.12),
            ("GARAN", "Garanti BBVA",      128, 0.06),
            ("SISE",  "Şişecam",            48, -0.10),
            ("KCHOL", "Koç Holding",       210, 0.03),
            ("EREGL", "Ereğli Demir Çelik", 52, -0.16),
            ("BIMAS", "BİM",               510, 0.08),
            ("TUPRS", "Tüpraş",            178, 0.14),
        ]
        let merkur = Merkur()
        var satirlar: [HisseSatiri] = []
        for (sembol, ad, fiyat, egim) in tanim {
            let mumlar = sentetikMumlar(adet: 1300, baslangic: fiyat, egim: egim)
            guard let sonuc = merkur.degerlendir(mumlar, endeks: nil) else { continue }
            let son = mumlar.last!.kapanis
            let onceki = mumlar[mumlar.count - 2].kapanis
            let degisim = (son - onceki) / onceki * 100
            satirlar.append(HisseSatiri(
                sembol: sembol, ad: ad, fiyat: son,
                gunlukDegisim: degisim, sonuc: sonuc, mumlar: mumlar
            ))
        }
        // Skora göre yüksekten düşüğe sırala
        return satirlar.sorted { $0.sonuc.skor > $1.sonuc.skor }
    }

    /// egim = günlük yüzde sürüklenme (örn. 0.18 = %0.18/gün).
    static func sentetikMumlar(adet: Int, baslangic: Double, egim: Double) -> [Mum] {
        var fiyat = baslangic
        var sonuc: [Mum] = []
        let bugun = Date()
        for i in 0..<adet {
            let gurultuYuzde = Double.random(in: -1.0...1.0)   // ±%1 günlük gürültü
            fiyat = max(1, fiyat * (1 + (egim + gurultuYuzde) / 100))
            let tarih = Calendar.current.date(byAdding: .day, value: -(adet - i), to: bugun)!
            sonuc.append(Mum(
                tarih: tarih,
                acilis: fiyat,
                yuksek: fiyat * 1.006,
                dusuk: fiyat * 0.994,
                kapanis: fiyat,
                hacim: Double.random(in: 5_000_000...20_000_000)
            ))
        }
        return sonuc
    }
}
