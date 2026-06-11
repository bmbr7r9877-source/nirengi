import Testing
import Foundation
@testable import Cekirdek

private func seri(egim: Double, adet: Int = 250, baslangic: Double = 100) -> [Mum] {
    var rng = SystemRandomNumberGenerator()
    var fiyat = baslangic
    var sonuc: [Mum] = []
    let bugun = Date()
    for i in 0..<adet {
        fiyat = max(1, fiyat * (1 + (egim + Double.random(in: -0.5...0.5, using: &rng)) / 100))
        let t = Calendar.current.date(byAdding: .day, value: -(adet - i), to: bugun)!
        sonuc.append(Mum(tarih: t, acilis: fiyat, yuksek: fiyat * 1.004,
                         dusuk: fiyat * 0.996, kapanis: fiyat, hacim: 1_000_000))
    }
    return sonuc
}

@Test func uranusYetersizVeriNil() {
    let u = Uranus()
    #expect(u.sektorSkoru(sektor: seri(egim: 0.1, adet: 30), benchmark: seri(egim: 0.1)) == nil)
}

@Test func gucluSektorZayiftanYuksek() throws {
    let u = Uranus()
    let bench = seri(egim: 0.05)
    let guclu = try #require(u.sektorSkoru(sektor: seri(egim: 0.5), benchmark: bench))
    let zayif = try #require(u.sektorSkoru(sektor: seri(egim: -0.5), benchmark: bench))
    #expect(guclu.skor > zayif.skor, "Güçlü sektör (\(guclu.skor)) zayıftan (\(zayif.skor)) yüksek olmalı")
}

@Test func hisseAlfasiSkoruEtkiler() throws {
    let u = Uranus()
    let bench = seri(egim: 0.05)
    let sektor = seri(egim: 0.2)
    let onde = try #require(u.hisseSonucu(hisse: seri(egim: 0.6), sektor: sektor, benchmark: bench))
    let geride = try #require(u.hisseSonucu(hisse: seri(egim: -0.4), sektor: sektor, benchmark: bench))
    #expect(onde.alfa20 > geride.alfa20)
    #expect(onde.skor > geride.skor)
}

@Test func katkiUretir() throws {
    let u = Uranus()
    let k = try #require(u.katki(hisse: seri(egim: 0.3), sektor: seri(egim: 0.2), benchmark: seri(egim: 0.1)))
    #expect(k.motor == "Uranüs")
    #expect(k.skor >= 0 && k.skor <= 100)
}
