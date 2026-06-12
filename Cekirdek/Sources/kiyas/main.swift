import Foundation
import Cekirdek
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Neptün walk-forward kıyas koşusu
//
// Soru: BIST uyarlaması + bağlam gözü, Neptün'ü gerçek veride iyileştirdi mi?
// Yöntem: BIST 30 × 2 yıl günlük mum. Her 5 barda bir "o güne kadarki veriyle
// tahmin et, ufuk dolunca gerçekle kıyasla" (geleceğe sızıntı yok; bağlam serileri
// de eğitim son tarihine kadar kırpılır — motor zaten tarihle filtreliyor).
// Varyantlar: naif (yarın=bugün) · serbest profil (≈eski Neptün) · BIST profili ·
// BIST+bağlam. Metrikler: yön isabeti, MAPE, Al/Sat sinyali net getirisi (maliyet düşülmüş).

let semboller = BistEvren.bist30
let adimAraligi = 5      // her 5 barda bir tahmin noktası
let minEgitim = 320      // ilk tahmin için en az bar (ufuk 4-5 bölgesi)

// MARK: - Veri çekme (ogrenme CLI ile aynı Yahoo chart ucu)

func mumCek(_ sembol: String, borsaIstanbul: Bool = true) async -> [Mum] {
    let ham = borsaIstanbul ? "\(sembol).IS" : sembol
    let kodlu = ham.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ham
    for deneme in 0..<3 {
        let host = deneme % 2 == 0 ? "query1" : "query2"
        let url = URL(string: "https://\(host).finance.yahoo.com/v8/finance/chart/\(kodlu)?range=2y&interval=1d")!
        var istek = URLRequest(url: url)
        istek.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (veri, yanit) = try? await URLSession.shared.data(for: istek),
              (yanit as? HTTPURLResponse)?.statusCode == 200,
              let m = mumAyikla(veri), m.count > 50
        else {
            try? await Task.sleep(nanoseconds: UInt64(1_500_000_000 * (deneme + 1)))
            continue
        }
        return m
    }
    return []
}

func mumAyikla(_ veri: Data) -> [Mum]? {
    guard let kok = (try? JSONSerialization.jsonObject(with: veri)) as? [String: Any],
          let chart = kok["chart"] as? [String: Any],
          let sonuc = (chart["result"] as? [[String: Any]])?.first,
          let zaman = sonuc["timestamp"] as? [Double],
          let gostergeler = sonuc["indicators"] as? [String: Any],
          let quote = (gostergeler["quote"] as? [[String: Any]])?.first
    else { return nil }
    let kapanis = quote["close"] as? [Double?] ?? []
    let acilis = quote["open"] as? [Double?] ?? []
    let yuksek = quote["high"] as? [Double?] ?? []
    let dusuk = quote["low"] as? [Double?] ?? []
    let hacim = quote["volume"] as? [Double?] ?? []
    var mumlar: [Mum] = []
    for i in zaman.indices where i < kapanis.count {
        guard let k = kapanis[i] else { continue }
        mumlar.append(Mum(tarih: Date(timeIntervalSince1970: zaman[i]),
                          acilis: (i < acilis.count ? acilis[i] : nil) ?? k,
                          yuksek: (i < yuksek.count ? yuksek[i] : nil) ?? k,
                          dusuk: (i < dusuk.count ? dusuk[i] : nil) ?? k,
                          kapanis: k,
                          hacim: (i < hacim.count ? hacim[i] : nil) ?? 0))
    }
    return mumlar
}

// MARK: - Metrik toplama

struct Olcum: Sendable {
    var yonDogru = 0, yonToplam = 0
    var apeler: [Double] = []
    var alGetirileri: [Double] = []     // Al sinyali sonrası net % (maliyet düşülmüş)
    var satGetirileri: [Double] = []    // Sat sinyali: kaçınılan net %

    mutating func birlestir(_ d: Olcum) {
        yonDogru += d.yonDogru; yonToplam += d.yonToplam
        apeler += d.apeler; alGetirileri += d.alGetirileri; satGetirileri += d.satGetirileri
    }
    var yonIsabet: Double { yonToplam > 0 ? Double(yonDogru) / Double(yonToplam) * 100 : 0 }
    var mape: Double { apeler.isEmpty ? 0 : apeler.reduce(0, +) / Double(apeler.count) }
}

func ort(_ d: [Double]) -> Double { d.isEmpty ? 0 : d.reduce(0, +) / Double(d.count) }

// MARK: - Bekçi ölçümü (Neptün = risk freni hipotezi)
//
// Soru: Neptün'ün risk sinyalleri (bant genişliği, düşük güven, limit/kur bayrağı)
// gerçekten "mayınlı" noktaları mı işaretliyor? Ve Merkür'ün Al sinyallerini
// bu frenle süzmek net getiriyi iyileştiriyor mu?

struct BekciKayit: Sendable {
    let bantYuzde: Double       // ufuk-sonu bant genişliği / fiyat ×100 (belirsizlik)
    let guven: Double           // Neptün güveni
    let bayrakli: Bool          // gerekçede limit serisi / kur şoku / endeks rejimi
    let getiri: Double          // gerçekleşen h-gün %
    let dusus: Double           // h penceresi içindeki en kötü kapanış % (≤0)
    let bantIcinde: Bool        // gerçek, [alt,üst] bandında kaldı mı
    let merkurSkor: Double?
}

// MARK: - Tek sembol koşusu

struct SembolSonuc: Sendable {
    var varyantlar: [String: Olcum]
    var bekci: [BekciKayit] = []
}

func kos(_ mumlar: [Mum], endeks: [Mum], usdtry: [Mum]) -> SembolSonuc {
    let maliyet = 0.5
    var sonuc = SembolSonuc(varyantlar: ["naif": Olcum(), "serbest": Olcum(),
                                         "bist": Olcum(), "bist+baglam": Olcum(),
                                         "bist-h1": Olcum(), "bist-h2": Olcum(), "bist-h3": Olcum()])
    let bars = mumlar.sorted { $0.tarih < $1.tarih }
    guard bars.count > minEgitim + 10 else { return sonuc }

    var t = minEgitim
    while t < bars.count - 6 {
        defer { t += adimAraligi }
        let egitim = Array(bars[0..<t])
        let simdiki = egitim.last!.kapanis
        guard simdiki > 0 else { continue }

        let motorlar: [(String, Neptun, Neptun.Baglam?)] = [
            ("serbest", Neptun(profil: .serbest), nil),
            ("bist", Neptun(), nil),
            ("bist+baglam", Neptun(), Neptun.Baglam(endeks: endeks, usdtry: usdtry)),
            ("bist-h1", Neptun(sabitUfuk: 1), nil),
            ("bist-h2", Neptun(sabitUfuk: 2), nil),
            ("bist-h3", Neptun(sabitUfuk: 3), nil),
        ]
        var ortakUfuk: Int?
        for (ad, motor, baglam) in motorlar {
            guard let tah = motor.tahminEt(egitim, baglam: baglam) else { continue }
            let h = tah.ufukGun
            if ad == "bist" { ortakUfuk = h }
            guard t + h - 1 < bars.count else { continue }
            let gercek = bars[t + h - 1].kapanis
            let gercekDegisim = (gercek - simdiki) / simdiki * 100

            var o = sonuc.varyantlar[ad]!
            if abs(tah.degisimYuzde) > 0.01 {       // nötr tahmin yön sayılmaz
                o.yonToplam += 1
                if tah.degisimYuzde * gercekDegisim > 0 { o.yonDogru += 1 }
            }
            o.apeler.append(abs(gercek - tah.tahminFiyat) / gercek * 100)
            if tah.oneri == .al { o.alGetirileri.append(gercekDegisim - maliyet) }
            if tah.oneri == .sat { o.satGetirileri.append(-gercekDegisim - maliyet) }
            sonuc.varyantlar[ad] = o

            // Bekçi kaydı (tam donanımlı varyant üzerinden, sızıntısız Merkür ile).
            if ad == "bist+baglam", let alt = tah.altBant.last, let ust = tah.ustBant.last {
                let pencere = bars[t..<min(t + h, bars.count)].map(\.kapanis)
                let dusus = (pencere.min() ?? simdiki) / simdiki * 100 - 100
                let bayrak = tah.gerekce.contains("limit serisi") || tah.gerekce.contains("kur şoku")
                    || tah.gerekce.contains("endeks düşüş")
                let sonTarih = egitim.last!.tarih
                let mSkor = Merkur().degerlendir(egitim, endeks: endeks.filter { $0.tarih <= sonTarih })?.skor
                sonuc.bekci.append(BekciKayit(bantYuzde: (ust - alt) / simdiki * 100,
                                              guven: tah.guven, bayrakli: bayrak,
                                              getiri: gercekDegisim, dusus: min(0, dusus),
                                              bantIcinde: gercek >= alt && gercek <= ust,
                                              merkurSkor: mSkor))
            }
        }
        // Naif taban çizgisi: yarın = bugün (aynı ufukta MAPE).
        if let h = ortakUfuk, t + h - 1 < bars.count {
            let gercek = bars[t + h - 1].kapanis
            var o = sonuc.varyantlar["naif"]!
            o.apeler.append(abs(gercek - simdiki) / gercek * 100)
            sonuc.varyantlar["naif"] = o
        }
    }
    return sonuc
}

// MARK: - Ana akış

@main struct Kiyas {
    static func main() async {
        print("📥 Veri çekiliyor: BIST 30 + XU100 + USDTRY (2y günlük)...")
        let endeks = await mumCek("XU100")
        let usdtry = await mumCek("USDTRY=X", borsaIstanbul: false)
        print("   XU100 \(endeks.count) bar · USDTRY \(usdtry.count) bar")

        var seriler: [(String, [Mum])] = []
        for s in semboller {
            let m = await mumCek(s)
            if m.count > minEgitim + 10 { seriler.append((s, m)) }
            else { print("   ⚠️ \(s): \(m.count) bar — atlandı") }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        print("   \(seriler.count)/\(semboller.count) sembol hazır. Koşu başlıyor...\n")

        var toplam: [String: Olcum] = ["naif": Olcum(), "serbest": Olcum(),
                                       "bist": Olcum(), "bist+baglam": Olcum(),
                                       "bist-h1": Olcum(), "bist-h2": Olcum(), "bist-h3": Olcum()]
        let sonuclar = await withTaskGroup(of: SembolSonuc.self) { group in
            for (_, m) in seriler {
                group.addTask { kos(m, endeks: endeks, usdtry: usdtry) }
            }
            var hepsi: [SembolSonuc] = []
            for await s in group { hepsi.append(s) }
            return hepsi
        }
        for s in sonuclar { for (ad, o) in s.varyantlar { toplam[ad]?.birlestir(o) } }
        let kayitlar = sonuclar.flatMap(\.bekci)

        print("VARYANT        | Yön%  | MAPE% | Al n / net%ort | Sat n / net%ort")
        print(String(repeating: "-", count: 70))
        for ad in ["naif", "serbest", "bist", "bist+baglam", "bist-h1", "bist-h2", "bist-h3"] {
            let o = toplam[ad]!
            let satir = String(format: "%-14@ | %5.1f | %5.2f | %4d / %+6.2f  | %4d / %+6.2f",
                               ad as NSString, o.yonIsabet, o.mape,
                               o.alGetirileri.count, ort(o.alGetirileri),
                               o.satGetirileri.count, ort(o.satGetirileri))
            print(satir)
        }
        print("\nNot: Yön% = sıfır-olmayan tahminlerde isabet (50 = yazı-tura).")
        print("Al/Sat net% = sinyal sonrası ufuk getirisi, %0.5 maliyet düşülmüş.")

        bekciRaporu(kayitlar)
    }

    // MARK: - Bekçi raporu

    static func bekciRaporu(_ kayitlar: [BekciKayit]) {
        guard kayitlar.count >= 30 else { print("\n(Bekçi: yetersiz kayıt)"); return }
        print("\n══ BEKÇİ ÖLÇÜMÜ (Neptün risk freni, n=\(kayitlar.count)) ══")

        let kapsama = Double(kayitlar.filter(\.bantIcinde).count) / Double(kayitlar.count) * 100
        print(String(format: "Bant kapsaması: %%%.1f (hedef ~90 — q90×1.2 bandı)", kapsama))

        func dilimRapor(_ baslik: String, _ gruplar: [(String, [BekciKayit])]) {
            print("\n\(baslik)  (n · ort getiri% · ort düşüş% · en kötü%)")
            for (ad, g) in gruplar where !g.isEmpty {
                print(String(format: "  %-12@ %4d · %+5.2f · %+5.2f · %+6.2f", ad as NSString, g.count,
                             ort(g.map(\.getiri)), ort(g.map(\.dusus)), g.map(\.getiri).min() ?? 0))
            }
        }

        // 1) Bant genişliği tertilleri: geniş bant gerçekten daha oynak/mayınlı mı?
        let bantSirali = kayitlar.sorted { $0.bantYuzde < $1.bantYuzde }
        let u = bantSirali.count / 3
        dilimRapor("Bant genişliği (belirsizlik) tertilleri:",
                   [("dar", Array(bantSirali[0..<u])), ("orta", Array(bantSirali[u..<2*u])),
                    ("geniş", Array(bantSirali[(2*u)...]))])

        // 2) Güven tertilleri: düşük güven kötü bölgeyi mi işaretliyor?
        let guvenSirali = kayitlar.sorted { $0.guven > $1.guven }
        dilimRapor("Neptün güveni tertilleri:",
                   [("yüksek", Array(guvenSirali[0..<u])), ("orta", Array(guvenSirali[u..<2*u])),
                    ("düşük", Array(guvenSirali[(2*u)...]))])

        // 3) Bayraklılar (limit serisi / kur şoku / endeks rejimi) vs temizler.
        dilimRapor("Rejim bayrağı:",
                   [("bayraklı", kayitlar.filter(\.bayrakli)), ("temiz", kayitlar.filter { !$0.bayrakli })])

        // 4) Fren simülasyonu: Merkür Al (skor ≥ 60) net getirisi, frenli/frensiz.
        let maliyet = 0.5
        let allar = kayitlar.filter { ($0.merkurSkor ?? 0) >= 60 }
        guard !allar.isEmpty else { print("\nFren testi: Merkür Al sinyali yok."); return }
        let genisEsik = bantSirali[2*u].bantYuzde       // geniş tertil sınırı
        let dusukEsik = guvenSirali[2*u].guven          // düşük güven tertil sınırı
        let frenli = allar.filter { !$0.bayrakli && $0.bantYuzde < genisEsik && $0.guven > dusukEsik }
        print("\nFren testi — Merkür Al (skor≥60), net% (maliyet düşülmüş):")
        print(String(format: "  frensiz   %4d işlem · ort %+5.2f · ort düşüş %+5.2f · en kötü %+6.2f",
                     allar.count, ort(allar.map(\.getiri)) - maliyet,
                     ort(allar.map(\.dusus)), allar.map(\.getiri).min() ?? 0))
        print(String(format: "  frenli    %4d işlem · ort %+5.2f · ort düşüş %+5.2f · en kötü %+6.2f",
                     frenli.count, ort(frenli.map(\.getiri)) - maliyet,
                     ort(frenli.map(\.dusus)), frenli.map(\.getiri).min() ?? 0))
        let engellenen = allar.filter { k in !frenli.contains { $0.getiri == k.getiri && $0.guven == k.guven } }
        if !engellenen.isEmpty {
            print(String(format: "  engellenen %3d işlem · ort %+5.2f  ← fren haklıysa bu, frenliden KÖTÜ olmalı",
                         engellenen.count, ort(engellenen.map(\.getiri)) - maliyet))
        }
    }
}
