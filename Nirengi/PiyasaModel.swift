import SwiftUI
import Cekirdek

/// Tüm sekmelerin paylaştığı veri kaynağı — gerçek BIST verisi (Yahoo, ~15 dk gecikmeli).
@MainActor
final class PiyasaModel: ObservableObject {
    @Published var hisseler: [HisseSatiri] = []
    @Published var yukleniyor = false
    @Published var hata: String?
    @Published var sonGuncelleme: Date?
    @Published var jupiterRejim: Jupiter.Sonuc? {  // makro rejim (piyasa geneli, bir kez)
        didSet { katkiOnbellek = [:] }
    }
    /// Sembol → geçerli VBTS tedbirleri (resmi BIST listesi, günde bir çekilir).
    @Published var tedbirler: [String: [Tedbir]] = [:] {
        didSet { katkiOnbellek = [:] }
    }
    /// USD/TRY günlük seri (Neptün bağlamı: kur şoku tespiti).
    private(set) var usdtryMumlar: [Mum] = []

    /// Neptün'ün piyasa-geneli bağlamı (XU100 + kur). Veriler henüz yoksa boş —
    /// motor bağlamsız da çalışır.
    func neptunBaglami() -> Neptun.Baglam {
        Neptun.Baglam(endeks: hisseler.first(where: { $0.sembol == "XU100" })?.mumlar ?? [],
                      usdtry: usdtryMumlar)
    }

    // MARK: - Ana sayfa skor seçimi (motor birleşimi)

    /// Listede anlık hesaplanabilen motorlar. (Satürn/Venüs hisse başına ağ
    /// isteği gerektirdiğinden listede yok; detay sayfasında hesaplanır.)
    static let listeMotorlari = ["Merkür", "Neptün", "Uranüs", "Jüpiter", "Mars", "Plüton"]

    /// Ana sayfa skor kolonunda hangi motorların birleşimi gösterilsin.
    @Published var skorSecimi: Set<String> = ["Merkür"] {
        didSet { UserDefaults.standard.set(Array(skorSecimi), forKey: "skorSecimi_v1") }
    }

    /// sembol → motor adı → katkı (hesap pahalı; veri yenilenince boşalır).
    private var katkiOnbellek: [String: [String: Katki]] = [:]

    /// Seçili motorların Konsey harmanı (ağırlık × güven). Tek motor Merkür ise
    /// doğrudan onun skoru.
    func birlesikSkor(_ satir: HisseSatiri) -> Double {
        if skorSecimi.isEmpty || skorSecimi == ["Merkür"] { return satir.sonuc.skor }
        let katkilar = Self.listeMotorlari.filter { skorSecimi.contains($0) }
            .compactMap { katki(satir, motor: $0) }
        guard !katkilar.isEmpty else { return satir.sonuc.skor }
        return Konsey.harmanla(katkilar, agirliklar: Konsey.varsayilanAgirliklar).skor
    }

    private func katki(_ satir: HisseSatiri, motor: String) -> Katki? {
        if let k = katkiOnbellek[satir.sembol]?[motor] { return k }
        guard let k = hesaplaKatki(satir, motor: motor) else { return nil }
        katkiOnbellek[satir.sembol, default: [:]][motor] = k
        return k
    }

    /// Skor/güven eşlemeleri DetayView'deki Konsey katkılarıyla birebir aynı.
    private func hesaplaKatki(_ satir: HisseSatiri, motor: String) -> Katki? {
        switch motor {
        case "Merkür":
            return Katki(motor: "Merkür", skor: satir.sonuc.skor, guven: satir.sonuc.guven, gerekce: satir.sonuc.verdict)
        case "Neptün":
            guard let t = Neptun().tahminEt(satir.mumlar, baglam: neptunBaglami()) else { return nil }
            // VBTS tedbirli payda fiyat keşfi kısıtlı: güveni tedbir ağırlığınca kırp.
            let carpan = TedbirListesi.guvenCarpani(tedbirler[satir.sembol] ?? [])
            let gerekce = carpan < 1 ? "\(t.oneri.rawValue) · VBTS tedbiri" : t.oneri.rawValue
            return Katki(motor: "Neptün", skor: max(0, min(100, 50 + t.degisimYuzde * 5)),
                         guven: t.guven / 100 * carpan, gerekce: gerekce)
        case "Uranüs":
            guard !satir.endeksMi, let u = uranusSonucu(satir) else { return nil }
            return Katki(motor: "Uranüs", skor: u.skor, guven: 0.7, gerekce: u.aciklama)
        case "Jüpiter":
            guard let j = jupiterRejim else { return nil }
            return Katki(motor: "Jüpiter", skor: j.skor, guven: 0.6, gerekce: j.rejim.rawValue)
        case "Mars":
            guard !satir.endeksMi, let mr = Mars().degerlendir(satir.mumlar) else { return nil }
            return Katki(motor: "Mars", skor: mr.skor, guven: mr.guvenilir ? 0.7 : 0.45, gerekce: mr.aciklama)
        case "Plüton":
            guard !satir.endeksMi, let p = Pluton().degerlendir(satir.mumlar) else { return nil }
            return Katki(motor: "Plüton", skor: p.skor, guven: min(0.75, 0.4 + p.rKare * 0.5), gerekce: p.aciklama)
        default:
            return nil
        }
    }

    // MARK: - Listeler (alfabetik)

    /// BIST 100 / 30 — paylaşılan evren (Cekirdek.BistEvren; robot da aynı listeyi kullanır).
    let bist100 = BistEvren.bist100
    let bist30 = BistEvren.bist30

    /// BIST endeksleri (Yahoo'da .IS ile mevcut) — hisse gibi gösterilir.
    let endeksler: [String] = [
        "XU100","XU030","XU050","XU500","XUMAL","XUHIZ","XUSIN","XBANK","XHOLD","XUTEK",
        "XGIDA","XKMYA","XMANA","XMADN","XILTM","XULAS","XINSA","XGMYO","XSGRT","XELKT",
        "XTRZM","XTCRT","XFINK",
    ]

    /// Listem — kullanıcının takip listesi (boş başlar, kalıcı: UserDefaults).
    @Published var listem: Set<String> = [] {
        didSet { UserDefaults.standard.set(Array(listem), forKey: "listem_v1") }
    }

    func listedeMi(_ sembol: String) -> Bool { listem.contains(sembol) }

    func listeyiDegistir(_ sembol: String) {
        if listem.contains(sembol) { listem.remove(sembol) } else { listem.insert(sembol) }
    }

    /// Şirket adları (bilinenler; yoksa sembol gösterilir).
    let adlar: [String: String] = [
        "AKBNK":"Akbank","ASELS":"Aselsan","ASTOR":"Astor Enerji","ALARK":"Alarko Holding",
        "ARCLK":"Arçelik","BIMAS":"BİM","BRSAN":"Borusan Boru","EKGYO":"Emlak Konut",
        "ENKAI":"Enka İnşaat","EREGL":"Ereğli Demir Çelik","FROTO":"Ford Otosan",
        "GARAN":"Garanti BBVA","GUBRF":"Gübre Fabrikaları","HEKTS":"Hektaş",
        "ISCTR":"İş Bankası","KCHOL":"Koç Holding","KONTR":"Kontrolmatik","KOZAL":"Koza Altın",
        "KRDMD":"Kardemir","MGROS":"Migros","OYAKC":"Oyak Çimento","PETKM":"Petkim",
        "PGSUS":"Pegasus","SAHOL":"Sabancı Holding","SASA":"Sasa Polyester","SISE":"Şişecam",
        "TCELL":"Turkcell","THYAO":"Türk Hava Yolları","TOASO":"Tofaş","TUPRS":"Tüpraş",
        "TTKOM":"Türk Telekom","VAKBN":"VakıfBank","YKBNK":"Yapı Kredi","HALKB":"Halkbank",
        "AEFES":"Anadolu Efes","CCOLA":"Coca-Cola İçecek","ULKER":"Ülker","TTRAK":"Türk Traktör",
        "TAVHL":"TAV Havalimanları","OTKAR":"Otokar","VESTL":"Vestel","MAVI":"Mavi",
        // Endeksler
        "XU100":"BIST 100","XU030":"BIST 30","XU050":"BIST 50","XU500":"BIST 500",
        "XUMAL":"BIST Mali","XUHIZ":"BIST Hizmetler","XUSIN":"BIST Sınai","XBANK":"BIST Banka",
        "XHOLD":"BIST Holding","XUTEK":"BIST Teknoloji","XGIDA":"BIST Gıda İçecek",
        "XKMYA":"BIST Kimya Petrol","XMANA":"BIST Metal Ana","XMADN":"BIST Madencilik",
        "XILTM":"BIST İletişim","XULAS":"BIST Ulaştırma","XINSA":"BIST İnşaat",
        "XGMYO":"BIST GMYO","XSGRT":"BIST Sigorta","XELKT":"BIST Elektrik",
        "XTRZM":"BIST Turizm","XTCRT":"BIST Ticaret","XFINK":"BIST Fin. Kiralama",
    ]

    init() {
        listem = Set(UserDefaults.standard.stringArray(forKey: "listem_v1") ?? [])
        if let s = UserDefaults.standard.stringArray(forKey: "skorSecimi_v1"), !s.isEmpty {
            skorSecimi = Set(s)
        }
    }

    /// Hisse → sektör endeksi eşlemesi (Uranüs için; paylaşılan evrenden).
    let sektorHaritasi = BistEvren.sektorHaritasi

    /// Uranüs (sektör rotasyonu) katkısı — hisse + sektör endeksi + XU100 hazırsa.
    func uranusSonucu(_ satir: HisseSatiri) -> Uranus.HisseSonuc? {
        guard let sektorKodu = sektorHaritasi[satir.sembol],
              let sektor = hisseler.first(where: { $0.sembol == sektorKodu }),
              let bench = hisseler.first(where: { $0.sembol == "XU100" })
        else { return nil }
        return Uranus().hisseSonucu(hisse: satir.mumlar, sektor: sektor.mumlar, benchmark: bench.mumlar)
    }

    func yukle() {
        guard hisseler.isEmpty, !yukleniyor else { return }
        yenile()
    }

    func yenile() {
        Task { await yenileAsync() }
        Task { jupiterRejim = await MakroServisi.shared.rejim() }
        Task { tedbirler = await TedbirServisi.shared.tedbirler() }
        Task {
            if usdtryMumlar.isEmpty,
               let v = try? await VeriMerkezi.cek(sembol: "USDTRY=X", borsaIstanbul: false) {
                usdtryMumlar = v.mumlar
            }
        }
    }

    func yenileAsync() async {
        guard !yukleniyor else { return }
        yukleniyor = true
        hata = nil
        // İlk yüklemede sonuçlar geldikçe ekrana basılır; yenilemede eski liste
        // ekranda kalır, yenisi hazır olunca tek seferde değişir.
        let yenileme = !hisseler.isEmpty
        var yeni: [HisseSatiri] = []
        // Hisseler + endeksler birlikte (endeks bayrağıyla).
        let hedefler: [(String, Bool)] = bist100.map { ($0, false) } + endeksler.map { ($0, true) }

        // XU100'ü önce çek: hisselerin görelatif güç (RS) kıyası için benchmark.
        // Endekslerin kendisi benchmark'sız değerlendirilir.
        let xu100Mumlar = (try? await VeriMerkezi.cek(sembol: "XU100"))?.mumlar

        // Yahoo'yu boğmamak için 8'erli gruplar; sonuçlar geldikçe ekrana basılır.
        for grup in hedefler.parcala(8) {
            let parca = await withTaskGroup(of: HisseSatiri?.self) { group -> [HisseSatiri] in
                for (s, endeksMi) in grup {
                    let ad = adlar[s] ?? s
                    group.addTask {
                        await Self.tekHisse(sembol: s, ad: ad, endeksMi: endeksMi,
                                            endeksMumlari: endeksMi ? nil : xu100Mumlar)
                    }
                }
                var arr: [HisseSatiri] = []
                for await h in group { if let h { arr.append(h) } }
                return arr
            }
            yeni.append(contentsOf: parca)
            if !yenileme {
                hisseler = yeni.sorted { $0.sonuc.skor > $1.sonuc.skor }
            }
        }

        // Likidite eşiği evrene göre: BIST 100 medyan cirosunun %5'i.
        // (Gerçek dağılım ölçümü: en cılız BIST 100 üyesi medyanın ~%7'sinde;
        // %5 bugünkü evrende yanlış alarm vermez, evren genişlerse gerçek
        // cılızları yakalar, enflasyondan etkilenmez.)
        let cirolar = yeni.filter { !$0.endeksMi }.map { Merkur.ortalamaCiro($0.mumlar) }.sorted()
        if !cirolar.isEmpty {
            let esik = cirolar[cirolar.count / 2] * 0.05
            let xu100 = yeni.first(where: { $0.sembol == "XU100" })?.mumlar ?? xu100Mumlar
            yeni = yeni.map { h in
                guard !h.endeksMi,
                      let s = Merkur().degerlendir(h.mumlar, endeks: xu100, likiditeEsigi: esik)
                else { return h }
                var g = h
                g.sonuc = s
                return g
            }
        }

        katkiOnbellek = [:]
        hisseler = yeni.sorted { $0.sonuc.skor > $1.sonuc.skor }
        yukleniyor = false
        if hisseler.isEmpty { hata = "Veri alınamadı. Bağlantını kontrol et." } else { sonGuncelleme = Date() }

        // Cihaz içi öğrenme: liste hazır olunca sicile günün tahminlerini yaz,
        // ufku dolanları değerlendir, Ay/Güneş'i güncelle (arka planda, günde bir).
        let girdiler = hisseler.filter { !$0.endeksMi }.map {
            OgrenmeDeposu.HisseGirdisi(
                sembol: $0.sembol, mumlar: $0.mumlar,
                merkur: Katki(motor: "Merkür", skor: $0.sonuc.skor, guven: $0.sonuc.guven, gerekce: $0.sonuc.verdict))
        }
        var sektorler: [String: [Mum]] = [:]
        for h in hisseler where h.endeksMi { sektorler[h.sembol] = h.mumlar }
        let jupiter = jupiterRejim.map {
            Katki(motor: "Jüpiter", skor: $0.skor, guven: 0.6, gerekce: $0.rejim.rawValue)
        }
        Task.detached(priority: .utility) {
            await OgrenmeDeposu.shared.gunlukDongu(hisseler: girdiler, sektorMumlari: sektorler, jupiter: jupiter)
        }
    }

    nonisolated static func tekHisse(sembol: String, ad: String, endeksMi: Bool = false,
                                     endeksMumlari: [Mum]? = nil) async -> HisseSatiri? {
        do {
            let veri = try await VeriMerkezi.cek(sembol: sembol)
            guard let sonuc = Merkur().degerlendir(veri.mumlar, endeks: endeksMumlari) else { return nil }
            let deg = veri.oncekiKapanis > 0
                ? (veri.fiyat - veri.oncekiKapanis) / veri.oncekiKapanis * 100 : 0
            return HisseSatiri(sembol: sembol, ad: ad, fiyat: veri.fiyat,
                               gunlukDegisim: deg, sonuc: sonuc, mumlar: veri.mumlar,
                               zaman: veri.zaman, endeksMi: endeksMi)
        } catch {
            return nil
        }
    }

    func oneCikan(_ adet: Int = 3) -> [HisseSatiri] { Array(hisseler.prefix(adet)) }
    func zayif(_ adet: Int = 3) -> [HisseSatiri] { Array(hisseler.suffix(adet).reversed()) }
}

private extension Array {
    func parcala(_ boyut: Int) -> [[Element]] {
        stride(from: 0, to: count, by: boyut).map { Array(self[$0..<Swift.min($0 + boyut, count)]) }
    }
}
