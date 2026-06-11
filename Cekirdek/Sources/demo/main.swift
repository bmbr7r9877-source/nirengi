import Foundation
import Cekirdek

// v0.1 demo — sentetik yükselen trend mumları üret, Konsey'i çalıştır.
// (Gerçek BIST verisi sonraki fazda bağlanacak.)

func sentetikMumlar(adet: Int, baslangic: Double, gunlukEgim: Double) -> [Mum] {
    var mumlar: [Mum] = []
    var fiyat = baslangic
    let bugun = Date()
    for i in 0..<adet {
        let gurultu = Double.random(in: -1.5...1.5)
        let kapanis = max(1, fiyat + gunlukEgim + gurultu)
        let tarih = Calendar.current.date(byAdding: .day, value: -(adet - i), to: bugun)!
        mumlar.append(Mum(
            tarih: tarih,
            acilis: fiyat,
            yuksek: max(fiyat, kapanis) + 0.5,
            dusuk: min(fiyat, kapanis) - 0.5,
            kapanis: kapanis,
            hacim: Double.random(in: 1_000_000...5_000_000)
        ))
        fiyat = kapanis
    }
    return mumlar
}

let konsey = Konsey(motorlar: [Merkur()])

func calistir(baslik: String, mumlar: [Mum]) {
    let s = konsey.karar(mumlar)
    print("\n=== \(baslik) ===")
    print(String(format: "Konsey skoru: %.1f  →  KARAR: %@", s.skor, s.karar.rawValue))
    for k in s.katkilar {
        print(String(format: "  • %@: %.1f (güven %.0f%%) — %@",
                     k.motor, k.skor, k.guven * 100, k.gerekce))
    }
}

calistir(baslik: "Yükselen trend", mumlar: sentetikMumlar(adet: 250, baslangic: 100, gunlukEgim: 0.8))
calistir(baslik: "Düşen trend",   mumlar: sentetikMumlar(adet: 250, baslangic: 100, gunlukEgim: -0.8))
calistir(baslik: "Yatay piyasa",  mumlar: sentetikMumlar(adet: 250, baslangic: 100, gunlukEgim: 0.0))
