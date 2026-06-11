import SwiftUI
import Cekirdek

/// Tüm sekmelerin paylaştığı veri kaynağı — gerçek BIST verisi (Yahoo, ~15 dk gecikmeli).
@MainActor
final class PiyasaModel: ObservableObject {
    @Published var hisseler: [HisseSatiri] = []
    @Published var yukleniyor = false
    @Published var hata: String?
    @Published var jupiterRejim: Jupiter.Sonuc?   // makro rejim (piyasa geneli, bir kez)

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
    }

    func yenileAsync() async {
        yukleniyor = true
        hata = nil
        hisseler = []
        // Hisseler + endeksler birlikte (endeks bayrağıyla).
        let hedefler: [(String, Bool)] = bist100.map { ($0, false) } + endeksler.map { ($0, true) }

        // Yahoo'yu boğmamak için 8'erli gruplar; sonuçlar geldikçe ekrana basılır.
        for grup in hedefler.parcala(8) {
            let parca = await withTaskGroup(of: HisseSatiri?.self) { group -> [HisseSatiri] in
                for (s, endeksMi) in grup {
                    let ad = adlar[s] ?? s
                    group.addTask { await Self.tekHisse(sembol: s, ad: ad, endeksMi: endeksMi) }
                }
                var arr: [HisseSatiri] = []
                for await h in group { if let h { arr.append(h) } }
                return arr
            }
            hisseler.append(contentsOf: parca)
            hisseler.sort { $0.sonuc.skor > $1.sonuc.skor }
        }

        yukleniyor = false
        if hisseler.isEmpty { hata = "Veri alınamadı. Bağlantını kontrol et." }

        // Cihaz içi öğrenme: liste hazır olunca sicile günün tahminlerini yaz,
        // ufku dolanları değerlendir, Ay/Güneş'i güncelle (arka planda, günde bir).
        let girdiler = hisseler.filter { !$0.endeksMi }.map {
            OgrenmeDeposu.HisseGirdisi(
                sembol: $0.sembol, mumlar: $0.mumlar,
                merkur: Katki(motor: "Merkür", skor: $0.sonuc.skor, guven: 0.8, gerekce: $0.sonuc.verdict))
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

    nonisolated static func tekHisse(sembol: String, ad: String, endeksMi: Bool = false) async -> HisseSatiri? {
        do {
            let veri = try await YahooBistServisi.cek(sembol: sembol)
            guard let sonuc = Merkur().degerlendir(veri.mumlar, endeks: nil) else { return nil }
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
