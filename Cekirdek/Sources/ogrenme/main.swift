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

// Öğrenme evreni: BIST 100 (app ile paylaşılan liste).
// Ek çekilenler: sektör endeksleri + XU100 (Uranüs) ve makro semboller (Jüpiter).
let semboller = BistEvren.bist100
let endeksler = BistEvren.sektorEndeksleri + ["XU100"]

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

var sonHataNotu = ""   // teşhis: son başarısızlığın sebebi (log için)
var yahooCrumb = ""    // çerez+crumb (datacenter IP'lerde hisse verisi için gerekebiliyor)

/// Yahoo çerez + crumb akışı (TemelVeriServisi ile aynı yöntem):
/// fc.yahoo.com → çerez (URLSession.shared otomatik saklar) → /v1/test/getcrumb → crumb.
/// GitHub Actions IP'lerinde chart ucu BIST hisseleri için çerezsiz META-ONLY dönüyor.
@MainActor
func yahooIsinmasi() async {
    var c = URLRequest(url: URL(string: "https://fc.yahoo.com")!)
    c.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
    _ = try? await URLSession.shared.data(for: c)   // sonucu önemsiz, çerez yeter

    var k = URLRequest(url: URL(string: "https://query1.finance.yahoo.com/v1/test/getcrumb")!)
    k.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
    if let (veri, _) = try? await URLSession.shared.data(for: k),
       let s = String(data: veri, encoding: .utf8), !s.isEmpty, !s.contains("Unauthorized") {
        yahooCrumb = s
    }
    print("🍪 Yahoo ısınması: crumb \(yahooCrumb.isEmpty ? "ALINAMADI" : "alındı")")
}

/// Yahoo Finance chart ucundan günlük mumları çeker (Linux/macOS uyumlu, key'siz).
/// borsaIstanbul=false → sembole .IS eklenmez (makro: ^VIX, GC=F, USDTRY=X...).
/// GitHub Actions IP'lerinde Yahoo agresif rate-limit uygular → 3 deneme,
/// artan bekleme, query1/query2 host dönüşümü.
@MainActor
func mumCek(_ sembol: String, borsaIstanbul: Bool = true) async -> [Mum] {
    let ham = borsaIstanbul ? "\(sembol).IS" : sembol
    let kodlu = ham.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ham
    // range=2y: Mars 12-1 momentumu (~13 ay) + Uranüs MA200 rejimi tam veriyle çalışsın.
    // DİKKAT: Yahoo sadece belirli aralıkları tanır (1mo/3mo/6mo/1y/2y/5y...);
    // geçersiz aralık (örn. "8mo") bazı sembollerde TEK bar döndürüyor.
    for deneme in 0..<3 {
        let host = deneme % 2 == 0 ? "query1" : "query2"
        let crumbEki = yahooCrumb.isEmpty ? "" : "&crumb=\(yahooCrumb.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        let url = URL(string: "https://\(host).finance.yahoo.com/v8/finance/chart/\(kodlu)?range=2y&interval=1d\(crumbEki)")!
        var istek = URLRequest(url: url)
        istek.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        istek.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (veri, yanit) = try? await URLSession.shared.data(for: istek) else {
            sonHataNotu = "\(ham): ağ hatası (deneme \(deneme + 1))"
            try? await Task.sleep(nanoseconds: UInt64(2_000_000_000 * (deneme + 1)))
            continue
        }
        if let http = yanit as? HTTPURLResponse, http.statusCode != 200 {
            sonHataNotu = "\(ham): HTTP \(http.statusCode) (deneme \(deneme + 1))"
            try? await Task.sleep(nanoseconds: UInt64(3_000_000_000 * (deneme + 1)))   // 429 soğuması
            continue
        }
        if let m = mumAyikla(veri) { return m }
        let parca = String(data: veri.prefix(200), encoding: .utf8) ?? "ikili veri"
        sonHataNotu = "\(ham): parse boş (deneme \(deneme + 1)) gövde: \(parca)"
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
    return []
}

/// Yahoo chart JSON gövdesinden mum dizisi çıkarır.
func mumAyikla(_ veri: Data) -> [Mum]? {
    guard let kok = (try? JSONSerialization.jsonObject(with: veri)) as? [String: Any],
          let chart = kok["chart"] as? [String: Any],
          let sonuc = (chart["result"] as? [[String: Any]])?.first,
          let zaman = sonuc["timestamp"] as? [Double],
          let gostergeler = sonuc["indicators"] as? [String: Any],
          let quote = (gostergeler["quote"] as? [[String: Any]])?.first
    else { return nil }

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
    return mumlar.isEmpty ? nil : mumlar
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Fiyat + endeks + makro ile skorla → 6 motor katkısı (Satürn/Venüs hariç:
/// temel veri ve haber/LLM robotta yok; eklenince sicil onları da öğrenir).
func skorla(_ sembol: String, _ mumlar: [Mum],
            endeksMumlari: [String: [Mum]], jupiterKatki: Katki?) -> [Katki] {
    var k: [Katki] = []
    if let m = Merkur().degerlendir(mumlar) { k.append(m) }
    if let n = Neptun().degerlendir(mumlar) { k.append(n) }
    if let mr = Mars().katki(mumlar) { k.append(mr) }
    if let p = Pluton().katki(mumlar) { k.append(p) }
    if let sektorKodu = BistEvren.sektorHaritasi[sembol],
       let sektor = endeksMumlari[sektorKodu],
       let xu100 = endeksMumlari["XU100"],
       let u = Uranus().katki(hisse: mumlar, sektor: sektor, benchmark: xu100) {
        k.append(u)
    }
    if let j = jupiterKatki { k.append(j) }   // piyasa geneli — tüm hisselerde aynı
    return k
}

// MARK: - Akış

let takvim = Calendar(identifier: .gregorian)
let bugun = Date()
var sicil = dosyaOku(sicilYol, [SicilKaydi].self) ?? []
print("📒 Mevcut sicil: \(sicil.count) kayıt (\(sicil.filter { $0.olgun }.count) olgun)")

await yahooIsinmasi()

// Sembol → mumlar (bir kez çek, hem skor hem değerlendirme için).
var mumHaritasi: [String: [Mum]] = [:]
for sembol in semboller {
    let m = await mumCek(sembol)
    if !m.isEmpty { mumHaritasi[sembol] = m.sorted { $0.tarih < $1.tarih } }
    try? await Task.sleep(nanoseconds: 400_000_000)   // rate-limit dostu
}
print("📥 Çekilen sembol: \(mumHaritasi.count)/\(semboller.count)\(sonHataNotu.isEmpty ? "" : " | son hata: \(sonHataNotu)")")

// Yarıdan azı çekildiyse veri günü temsil etmiyor — sicile YANLIŞ tahmin yazma, çık.
guard mumHaritasi.count >= semboller.count / 2 else {
    print("⛔️ Çok az sembol çekilebildi (rate-limit?) — bugünkü koşu atlanıyor, sicil değişmedi.")
    exit(0)
}

// Sektör endeksleri + XU100 (Uranüs girdisi).
var endeksMumlari: [String: [Mum]] = [:]
for endeks in endeksler {
    let m = await mumCek(endeks)
    if !m.isEmpty { endeksMumlari[endeks] = m.sorted { $0.tarih < $1.tarih } }
    try? await Task.sleep(nanoseconds: 400_000_000)
}

/// Üye hisselerin eşit ağırlıklı, normalize kapanış ortalamasından sentetik endeks.
/// Yahoo çoğu BIST sektör endeksi için GEÇMİŞ VERMİYOR (sadece son fiyat; yalnız
/// XBANK/XUSIN/XU100 tam) — rotasyon sinyali için eşit ağırlıklı vekil yeterli.
func sentetikEndeks(_ uyeSerileri: [[Mum]]) -> [Mum] {
    var oranlar: [Date: [Double]] = [:]
    for seri in uyeSerileri {
        guard let ilk = seri.first?.kapanis, ilk > 0 else { continue }
        for m in seri {
            oranlar[takvim.startOfDay(for: m.tarih), default: []].append(m.kapanis / ilk)
        }
    }
    let minUye = max(2, uyeSerileri.count / 2)   // yarıdan az üyeli gün atlanır
    return oranlar.compactMap { gun, o -> Mum? in
        guard o.count >= minUye else { return nil }
        let ort = o.reduce(0, +) / Double(o.count) * 100
        return Mum(tarih: gun, acilis: ort, yuksek: ort, dusuk: ort, kapanis: ort, hacim: 0)
    }
    .sorted { $0.tarih < $1.tarih }
}

// Geçmişi eksik sektör endekslerini sentetikle doldur.
var sentetikSayisi = 0
for sektorKodu in BistEvren.sektorEndeksleri where (endeksMumlari[sektorKodu]?.count ?? 0) < 60 {
    let uyeler = BistEvren.sektorHaritasi.filter { $0.value == sektorKodu }.map(\.key)
    let seriler = uyeler.compactMap { mumHaritasi[$0] }
    guard seriler.count >= 2 else { continue }
    endeksMumlari[sektorKodu] = sentetikEndeks(seriler)
    sentetikSayisi += 1
}
print("📥 Çekilen endeks: \(endeksMumlari.count)/\(endeksler.count) (\(sentetikSayisi) sentetik)")

// Makro seriler (Jüpiter girdisi) — bir kez, piyasa geneli.
var makro = MakroGirdi()
for (alan, yahooSembol) in BistEvren.makroSemboller {
    let kapanis = await mumCek(yahooSembol, borsaIstanbul: false).map(\.kapanis)
    switch alan {
    case "vix":     makro.vix = kapanis
    case "spy":     makro.spy = kapanis
    case "dxy":     makro.dxy = kapanis
    case "faiz10y": makro.faiz10y = kapanis
    case "altin":   makro.altin = kapanis
    case "usdtry":  makro.usdtry = kapanis
    default: break
    }
    try? await Task.sleep(nanoseconds: 400_000_000)
}
let jupiterKatki = Jupiter().katki(makro)
print("📥 Jüpiter: \(jupiterKatki.map { String(format: "skor %.0f", $0.skor) } ?? "veri yetersiz")")

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
    let katkilar = skorla(sembol, mumlar, endeksMumlari: endeksMumlari, jupiterKatki: jupiterKatki)
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
