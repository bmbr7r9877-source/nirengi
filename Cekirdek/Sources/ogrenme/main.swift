import Foundation
import Cekirdek
#if canImport(FoundationNetworking)
import FoundationNetworking   // Linux'ta URLSession buradan gelir
#endif

// MARK: - Nirengi günlük öğrenme robotu
//
// GitHub Actions her gün koşar:
//   1. BIST sembollerini Yahoo'dan çek (fiyat/mum).
//   2. Fiyat-bazlı motorlarla skorla → bugünün tahminlerini sicile EKLE.
//   3. Olgunlaşmış (ufuk kadar beklemiş) eski tahminleri gerçekleşen fiyatla DEĞERLENDİR.
//   4. Ay (isabet→ağırlık) ve Güneş (kalibrasyon) motorlarını koş → JSON yaz.
// Sonuç data/ klasörüne yazılır, repo'ya commit edilir; iOS app bu JSON'ları okur.

let ufukGun = 14                 // tahmin ufku (≈10 işlem günü)
let veriKlasor = "data"
let sicilYol = "\(veriKlasor)/sicil.json"
let agirlikYol = "\(veriKlasor)/agirliklar.json"
let kalibrasyonYol = "\(veriKlasor)/kalibrasyon.json"

// BIST 30 (öğrenme evreni — hafif tutuldu; rate-limit dostu).
let semboller = [
    "AKBNK","ARCLK","ASELS","BIMAS","EKGYO","ENKAI","EREGL","FROTO","GARAN","GUBRF",
    "HEKTS","ISCTR","KCHOL","KOZAL","KRDMD","PETKM","PGSUS","SAHOL","SASA","SISE",
    "TCELL","THYAO","TOASO","TUPRS","VAKBN","YKBNK","TTKOM","BRSAN","ODAS","KONTR"
]

// MARK: - Yardımcılar

let isoKodlayici: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return e
}()
let isoCozucu: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

func dosyaOku<T: Decodable>(_ yol: String, _ tip: T.Type) -> T? {
    guard let veri = FileManager.default.contents(atPath: yol) else { return nil }
    return try? isoCozucu.decode(T.self, from: veri)
}

func dosyaYaz<T: Encodable>(_ yol: String, _ deger: T) {
    try? FileManager.default.createDirectory(atPath: veriKlasor, withIntermediateDirectories: true)
    if let veri = try? isoKodlayici.encode(deger) {
        FileManager.default.createFile(atPath: yol, contents: veri)
    }
}

/// Yahoo Finance chart ucundan günlük mumları çeker (Linux/macOS uyumlu, key'siz).
func mumCek(_ sembol: String) async -> [Mum] {
    let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(sembol).IS?range=8mo&interval=1d")!
    var istek = URLRequest(url: url)
    istek.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
    guard let (veri, _) = try? await URLSession.shared.data(for: istek),
          let kok = (try? JSONSerialization.jsonObject(with: veri)) as? [String: Any],
          let chart = kok["chart"] as? [String: Any],
          let sonuc = (chart["result"] as? [[String: Any]])?.first,
          let zaman = sonuc["timestamp"] as? [Double],
          let gostergeler = sonuc["indicators"] as? [String: Any],
          let quote = (gostergeler["quote"] as? [[String: Any]])?.first
    else { return [] }

    let acilis = quote["open"] as? [Double?] ?? []
    let yuksek = quote["high"] as? [Double?] ?? []
    let dusuk = quote["low"] as? [Double?] ?? []
    let kapanis = quote["close"] as? [Double?] ?? []
    let hacim = quote["volume"] as? [Double?] ?? []

    var mumlar: [Mum] = []
    for i in zaman.indices {
        guard i < kapanis.count, let k = kapanis[i],
              let a = acilis[safe: i] ?? k, let y = yuksek[safe: i] ?? k,
              let d = dusuk[safe: i] ?? k else { continue }
        mumlar.append(Mum(tarih: Date(timeIntervalSince1970: zaman[i]),
                          acilis: a, yuksek: y, dusuk: d, kapanis: k,
                          hacim: (hacim[safe: i] ?? nil) ?? 0))
    }
    return mumlar
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Fiyat-bazlı motorlarla skorla → katkılar (Linux'ta ek veri kaynağı gerekmez).
func skorla(_ mumlar: [Mum]) -> [Katki] {
    var k: [Katki] = []
    if let m = Merkur().degerlendir(mumlar) { k.append(m) }
    if let n = Neptun().degerlendir(mumlar) { k.append(n) }
    if let mr = Mars().katki(mumlar) { k.append(mr) }
    if let p = Pluton().katki(mumlar) { k.append(p) }
    return k
}

// MARK: - Akış

let takvim = Calendar(identifier: .gregorian)
let bugun = Date()
var sicil = dosyaOku(sicilYol, [SicilKaydi].self) ?? []
print("📒 Mevcut sicil: \(sicil.count) kayıt (\(sicil.filter { $0.olgun }.count) olgun)")

// Sembol → mumlar (bir kez çek, hem skor hem değerlendirme için).
var mumHaritasi: [String: [Mum]] = [:]
for sembol in semboller {
    let m = await mumCek(sembol)
    if !m.isEmpty { mumHaritasi[sembol] = m.sorted { $0.tarih < $1.tarih } }
    try? await Task.sleep(nanoseconds: 400_000_000)   // rate-limit dostu
}
print("📥 Çekilen sembol: \(mumHaritasi.count)/\(semboller.count)")

// 1) Olgun tahminleri değerlendir.
var degerlendirilen = 0
for i in sicil.indices where !sicil[i].olgun {
    guard let hedef = takvim.date(byAdding: .day, value: ufukGun, to: sicil[i].tarih),
          hedef <= bugun,
          let mumlar = mumHaritasi[sicil[i].sembol],
          let sonra = mumlar.first(where: { $0.tarih >= hedef })
    else { continue }
    sicil[i].degerlendirmeTarihi = sonra.tarih
    sicil[i].fiyatSonra = sonra.kapanis
    sicil[i].getiriYuzde = (sonra.kapanis - sicil[i].fiyat) / sicil[i].fiyat * 100
    degerlendirilen += 1
}
print("✅ Değerlendirilen: \(degerlendirilen)")

// 2) Bugünün tahminlerini ekle (aynı gün/sembol yoksa).
let bugunGun = takvim.startOfDay(for: bugun)
var eklenen = 0
for (sembol, mumlar) in mumHaritasi {
    let varMi = sicil.contains { $0.sembol == sembol && takvim.isDate($0.tarih, inSameDayAs: bugunGun) }
    guard !varMi, let sonFiyat = mumlar.last?.kapanis else { continue }
    let katkilar = skorla(mumlar)
    guard !katkilar.isEmpty else { continue }
    let b = Konsey.harmanla(katkilar, agirliklar: Konsey.varsayilanAgirliklar)
    let motorlar = Dictionary(uniqueKeysWithValues: katkilar.map { ($0.motor, MotorOyu(skor: $0.skor, guven: $0.guven)) })
    sicil.append(SicilKaydi(tarih: bugunGun, sembol: sembol, fiyat: sonFiyat,
                            nirengiSkor: b.skor, karar: b.karar.rawValue, motorlar: motorlar))
    eklenen += 1
}
print("📝 Eklenen tahmin: \(eklenen)")

// 3) Ay + Güneş öğren.
let agirliklar = Ay().ogren(sicil)
let kalibrasyon = Gunes().kalibreEt(sicil)
print("🌙 Ay çarpanları (\(agirliklar.ornekSayisi) örnek): \(agirliklar.carpanlar.mapValues { String(format: "%.2f", $0) })")
print("☀️ Güneş katsayı: \(String(format: "%.2f", kalibrasyon.guvenKatsayi)) | genel isabet: \(String(format: "%.0f%%", kalibrasyon.genelIsabet * 100)) (\(kalibrasyon.ornekSayisi) örnek)")

// 4) Yaz.
dosyaYaz(sicilYol, sicil)
dosyaYaz(agirlikYol, agirliklar)
dosyaYaz(kalibrasyonYol, kalibrasyon)
print("💾 Yazıldı: \(sicilYol), \(agirlikYol), \(kalibrasyonYol)")
