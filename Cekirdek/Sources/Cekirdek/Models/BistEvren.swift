import Foundation

/// BIST sembol evreni — app (PiyasaModel) ve öğrenme robotu (ogrenme CLI) aynı
/// listeyi kullanır; tek yerden güncellenir. Yahoo'da bulunmayan sembol sessizce atlanır.
public enum BistEvren {
    /// BIST 100 — tam liste (alfabetik). Endeks bileşimi zamanla değişebilir.
    public static let bist100: [String] = [
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
    public static let bist30: [String] = [
        "AKBNK","ALARK","ARCLK","ASELS","ASTOR","BIMAS","BRSAN","EKGYO","ENKAI","EREGL",
        "FROTO","GARAN","GUBRF","HEKTS","ISCTR","KCHOL","KONTR","KOZAL","KRDMD","MGROS",
        "OYAKC","PETKM","PGSUS","SAHOL","SASA","SISE","TCELL","THYAO","TOASO","TUPRS",
    ]

    /// Hisse → sektör endeksi eşlemesi (Uranüs için; kaba eşleme, ileride rafine edilir).
    /// Eşlemesi olmayan hissede Uranüs skor üretmez.
    public static let sektorHaritasi: [String: String] = [
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

    /// Bilanço yapısı sanayi şirketinden kökten farklı sektörler (banka/sigorta/leasing).
    /// Satürn'ün bant eşikleri (borç/özkaynak, cari oran, marj bantları) bu şirketlerde
    /// YANILTICI sonuç verir → BIST'te bu sektörlerde Satürn kapalı tutulur,
    /// Mars'ın kalite faktöründe borç/özkaynak sayılmaz.
    public static let finansalSektorler: Set<String> = ["XBANK", "XSGRT", "XFINK"]

    public static func finansalMi(_ sembol: String) -> Bool {
        guard let s = sektorHaritasi[sembol] else { return false }
        return finansalSektorler.contains(s)
    }

    /// sektorHaritasi'nda geçen benzersiz sektör endeksleri (robotun çekmesi gerekenler).
    public static var sektorEndeksleri: [String] {
        Array(Set(sektorHaritasi.values)).sorted()
    }

    /// Jüpiter'in makro girdileri — Yahoo sembolleri (.IS DEĞİL, borsaIstanbul:false ile çekilir).
    public static let makroSemboller: [String: String] = [
        "vix": "^VIX", "spy": "^GSPC", "dxy": "DX-Y.NYB",
        "faiz10y": "^TNX", "altin": "GC=F", "usdtry": "USDTRY=X",
    ]
}
