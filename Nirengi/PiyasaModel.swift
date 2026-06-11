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

    /// BIST 100 — tam liste (alfabetik). Bazı semboller zamanla değişebilir;
    /// Yahoo'da bulunmayan/çekilmeyen sembol sessizce atlanır.
    let bist100: [String] = [
        "AEFES","AGHOL","AKBNK","AKCNS","AKFGY","AKSA","AKSEN","ALARK","ALBRK","ALFAS",
        "ARCLK","ASELS","ASTOR","AYDEM","BERA","BIMAS","BIOEN","BRSAN","BRYAT","BUCIM",
        "CCOLA","CIMSA","CWENE","DOAS","DOHOL","ECILC","EGEEN","EKGYO","ENJSA","ENKAI",
        "EREGL","EUPWR","FROTO","GARAN","GESAN","GLYHO","GUBRF","GWIND","HALKB","HEKTS",
        "ISCTR","ISDMR","ISGYO","ISMEN","KARSN","KCAER","KCHOL","KMPUR","KONTR","KONYA",
        "KORDS","KOZAA","KOZAL","KRDMD","MAVI","MGROS","MIATK","ODAS","OTKAR","OYAKC",
        "PETKM","PGSUS","PSGYO","QUAGR","SAHOL","SASA","SAYAS","SISE","SKBNK","SMRTG",
        "SOKM","TAVHL","TCELL","THYAO","TKFEN","TMSN","TOASO","TSKB","TTKOM","TTRAK",
        "TUKAS","TUPRS","TURSG","ULKER","VAKBN","VESBE","VESTL","YEOTK","YKBNK","ZOREN",
    ]

    /// BIST 30 — alfabetik (BIST 100'ün alt kümesi).
    let bist30: [String] = [
        "AKBNK","ALARK","ARCLK","ASELS","ASTOR","BIMAS","BRSAN","EKGYO","ENKAI","EREGL",
        "FROTO","GARAN","GUBRF","HEKTS","ISCTR","KCHOL","KONTR","KOZAL","KRDMD","MGROS",
        "OYAKC","PETKM","PGSUS","SAHOL","SASA","SISE","TCELL","THYAO","TOASO","TUPRS",
    ]

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

    /// Hisse → sektör endeksi eşlemesi (Uranüs için; kaba eşleme, ileride rafine edilir).
    /// Eşlemesi olmayan hissede Uranüs skor üretmez.
    let sektorHaritasi: [String: String] = [
        // Banka
        "AKBNK":"XBANK","GARAN":"XBANK","HALKB":"XBANK","ISCTR":"XBANK","SKBNK":"XBANK",
        "TSKB":"XBANK","VAKBN":"XBANK","YKBNK":"XBANK","ALBRK":"XBANK",
        // Holding
        "AGHOL":"XHOLD","ALARK":"XHOLD","DOHOL":"XHOLD","KCHOL":"XHOLD","SAHOL":"XHOLD",
        "GLYHO":"XHOLD","BERA":"XHOLD","BRYAT":"XHOLD",
        // Kimya / petrokimya / gübre
        "SASA":"XKMYA","PETKM":"XKMYA","TUPRS":"XKMYA","GUBRF":"XKMYA","HEKTS":"XKMYA",
        "AKSA":"XKMYA","KMPUR":"XKMYA",
        // Metal ana
        "EREGL":"XMANA","ISDMR":"XMANA","KRDMD":"XMANA","KCAER":"XMANA","BRSAN":"XMANA",
        // Madencilik
        "KOZAL":"XMADN","KOZAA":"XMADN",
        // Ulaştırma
        "THYAO":"XULAS","PGSUS":"XULAS","TAVHL":"XULAS",
        // İletişim
        "TCELL":"XILTM","TTKOM":"XILTM",
        // GMYO
        "EKGYO":"XGMYO","ISGYO":"XGMYO","AKFGY":"XGMYO","PSGYO":"XGMYO",
        // Elektrik / enerji
        "AKSEN":"XELKT","AYDEM":"XELKT","ZOREN":"XELKT","ODAS":"XELKT","ENJSA":"XELKT",
        "GWIND":"XELKT","CWENE":"XELKT","BIOEN":"XELKT","EUPWR":"XELKT",
        // Ticaret / perakende
        "BIMAS":"XTCRT","MGROS":"XTCRT","SOKM":"XTCRT","DOAS":"XTCRT",
        // Gıda içecek
        "AEFES":"XGIDA","CCOLA":"XGIDA","ULKER":"XGIDA","TUKAS":"XGIDA",
        // Sınai (çimento/cam/oto/savunma/diğer imalat)
        "ASELS":"XUSIN","SISE":"XUSIN","ARCLK":"XUSIN","FROTO":"XUSIN","TOASO":"XUSIN",
        "OTKAR":"XUSIN","TTRAK":"XUSIN","TMSN":"XUSIN","VESTL":"XUSIN","VESBE":"XUSIN",
        "AKCNS":"XUSIN","CIMSA":"XUSIN","OYAKC":"XUSIN","BUCIM":"XUSIN","KONYA":"XUSIN",
        "EGEEN":"XUSIN","KARSN":"XUSIN","KORDS":"XUSIN","ASTOR":"XUSIN","GESAN":"XUSIN",
        "KONTR":"XUSIN","SMRTG":"XUSIN","YEOTK":"XUSIN","MIATK":"XUTEK",
        // İnşaat
        "ENKAI":"XINSA",
        // Sigorta
        "TURSG":"XSGRT",
        // Turizm / tekstil-giyim (yaklaşık)
        "MAVI":"XTCRT",
    ]

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
