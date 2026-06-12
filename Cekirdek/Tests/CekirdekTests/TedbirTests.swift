import Testing
import Foundation
@testable import Cekirdek

private let ornekCSV = """
11.06.2026 18:12:00;
Pay Adı;İşlem Kodu;Uygulanan Tedbir Kodu;Uygulanan Tedbir Adı;Tedbirin İlk Tarihi;Tedbirin Son Tarihi;
ANEL ELEKTRIK;ANELE;PASKI;AÇIĞA SATIŞ YASAĞI;09.04.2026;02.07.2026;
ANEL ELEKTRIK;ANELE;PBRUT;BRÜT TAKAS;20.04.2026;02.07.2026;
KORAY GMYO;KGYO;PKISY;KREDİLİ İŞLEM YASAĞI;12.05.2026;11.06.2026;
ESKI PAY;ESKI;PBRUT;BRÜT TAKAS;01.01.2026;01.02.2026;
BILINMEYEN;BLNM;PXXXX;YENİ TEDBİR;01.06.2026;01.08.2026;
"""

@Test func tedbirCSVAyristirilir() {
    let t = TedbirListesi.ayristir(ornekCSV)
    #expect(t.count == 5)
    #expect(t[0].sembol == "ANELE" && t[0].tur == .acigaSatisYasagi)
    #expect(t[1].tur == .brutTakas)
    #expect(t[4].tur == .diger)   // bilinmeyen kod kırılmaz
}

@Test func tedbirHaritasiSuresiDolaniEler() {
    let bicim = DateFormatter(); bicim.dateFormat = "dd.MM.yyyy"
    let bugun = bicim.date(from: "11.06.2026")!
    let h = TedbirListesi.haritala(TedbirListesi.ayristir(ornekCSV), tarih: bugun)
    #expect(h["ANELE"]?.count == 2)
    #expect(h["KGYO"]?.count == 1)    // bitiş günü dahil
    #expect(h["ESKI"] == nil)         // süresi dolmuş
}

@Test func tedbirGuvenCarpaniEnAgirdan() {
    let h = TedbirListesi.haritala(TedbirListesi.ayristir(ornekCSV),
                                   tarih: ISO8601DateFormatter().date(from: "2026-06-11T00:00:00Z")!)
    #expect(TedbirListesi.guvenCarpani(h["ANELE"] ?? []) == 0.7)   // brüt takas baskın
    #expect(TedbirListesi.guvenCarpani([]) == 1.0)
}
