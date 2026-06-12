import Foundation
import Cekirdek

// Merkür walk-forward backtest — gerçek motor kodu, tarihsel BIST verisi.
// Veri: /tmp/bist_tarihsel/*.json (Yahoo, 5y günlük). Her hisse için haftada bir
// (5 mumda bir) "o güne kadarki veriyle skor" üretilir, 10 işlem günü (~14 takvim
// günü, uygulamadaki sicil ufkuyla aynı) sonraki getiriyle eşlenir.
// Bakış açısı sızıntısı yok: motor yalnızca o günün ve öncesinin mumlarını görür.

struct Satir: Decodable {
    let t: Double, o: Double, h: Double, l: Double, c: Double, v: Double?
}

func yukle(_ url: URL) -> [Mum]? {
    guard let data = try? Data(contentsOf: url),
          let satirlar = try? JSONDecoder().decode([Satir].self, from: data) else { return nil }
    return satirlar.map {
        Mum(tarih: Date(timeIntervalSince1970: $0.t), acilis: $0.o,
            yuksek: $0.h, dusuk: $0.l, kapanis: $0.c, hacim: $0.v ?? 0)
    }
}

let klasor = URL(fileURLWithPath: "/tmp/bist_tarihsel")
let dosyalar = (try? FileManager.default.contentsOfDirectory(at: klasor, includingPropertiesForKeys: nil)) ?? []
guard let xu100 = yukle(klasor.appendingPathComponent("XU100.json")) else {
    fatalError("XU100 verisi yok")
}
// XU100 kapanışını tarihe göre hızlı erişim için indeksle.
let xuTarihler = xu100.map(\.tarih)

struct Gozlem {
    let skor: Double
    let guven: Double
    let getiri: Double      // hissenin 10 işlem günü sonraki % getirisi
    let endeksGetiri: Double
    var fark: Double { getiri - endeksGetiri }
}

let ufuk = 10          // işlem günü (~14 takvim günü)
let adim = 5           // haftada bir gözlem
let minGecmis = 250    // SMA200 + tampon

var gozlemler: [Gozlem] = []
var hisseSayisi = 0

for dosya in dosyalar where dosya.lastPathComponent != "XU100.json" {
    guard let mumlar = yukle(dosya), mumlar.count > minGecmis + ufuk else { continue }
    hisseSayisi += 1
    let merkur = Merkur()
    var i = minGecmis
    while i < mumlar.count - ufuk {
        let bugun = mumlar[i].tarih
        // Endeksi tarihle hizala: motorun göreceği son endeks mumu bugünden sonra olamaz.
        guard let xuIdx = xuTarihler.lastIndex(where: { $0 <= bugun }),
              xuIdx + ufuk < xu100.count else { i += adim; continue }
        let gecmis = Array(mumlar[0...i])
        let endeksGecmis = Array(xu100[0...xuIdx])
        if let s = merkur.degerlendir(gecmis, endeks: endeksGecmis) {
            let f0 = mumlar[i].kapanis
            let f1 = mumlar[i + ufuk].kapanis
            let e0 = xu100[xuIdx].kapanis
            let e1 = xu100[xuIdx + ufuk].kapanis
            if f0 > 0, e0 > 0 {
                gozlemler.append(Gozlem(skor: s.skor, guven: s.guven,
                                        getiri: (f1 - f0) / f0 * 100,
                                        endeksGetiri: (e1 - e0) / e0 * 100))
            }
        }
        i += adim
    }
}

print("Hisse: \(hisseSayisi), gözlem: \(gozlemler.count)\n")

func ozet(_ ad: String, _ g: [Gozlem]) {
    guard !g.isEmpty else { print("\(ad): gözlem yok"); return }
    let n = Double(g.count)
    let ortGetiri = g.map(\.getiri).reduce(0, +) / n
    let ortFark = g.map(\.fark).reduce(0, +) / n
    let isabet = Double(g.filter { $0.getiri > 0 }.count) / n * 100
    let endeksiYenme = Double(g.filter { $0.fark > 0 }.count) / n * 100
    print(String(format: "%@  n=%5d  ort getiri %%%5.2f  ort fark %%%5.2f  pozitif %%%4.1f  endeksi yendi %%%4.1f",
                 ad, g.count, ortGetiri, ortFark, isabet, endeksiYenme))
}

print("— Skor dilimlerine göre (10 işlem günü ileri) —")
let dilimler: [(String, ClosedRange<Double>)] = [
    ("  0-40 ", 0...40), (" 40-50 ", 40.0001...50), (" 50-60 ", 50.0001...60),
    (" 60-70 ", 60.0001...70), (" 70-80 ", 70.0001...80), (" 80-100", 80.0001...100),
]
for (ad, aralik) in dilimler {
    ozet(ad, gozlemler.filter { aralik.contains($0.skor) })
}

// Bilgi katsayısı: skor ile endekse göre fark getirisi arasındaki korelasyon.
func pearson(_ x: [Double], _ y: [Double]) -> Double {
    let n = Double(x.count)
    let mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
    var kov = 0.0, vx = 0.0, vy = 0.0
    for i in x.indices {
        kov += (x[i] - mx) * (y[i] - my)
        vx += pow(x[i] - mx, 2); vy += pow(y[i] - my, 2)
    }
    return kov / (sqrt(vx) * sqrt(vy))
}
let ic = pearson(gozlemler.map(\.skor), gozlemler.map(\.fark))
print(String(format: "\nBilgi katsayısı (skor ↔ endekse göre fark): %.4f", ic))

print("\n— Güven dilimlerine göre (skor 60+ gözlemler) —")
let yuksekSkor = gozlemler.filter { $0.skor > 60 }
ozet(" güven <0.6 ", yuksekSkor.filter { $0.guven < 0.6 })
ozet(" güven 0.6-0.8", yuksekSkor.filter { $0.guven >= 0.6 && $0.guven < 0.8 })
ozet(" güven 0.8+  ", yuksekSkor.filter { $0.guven >= 0.8 })
