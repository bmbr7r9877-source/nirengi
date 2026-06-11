import Testing
import Foundation
@testable import Cekirdek

private func mumlar(egim: Double, adet: Int = 250, baslangic: Double = 100, gurultu: Double = 1.0) -> [Mum] {
    var rng = SystemRandomNumberGenerator()
    var fiyat = baslangic
    var sonuc: [Mum] = []
    let bugun = Date()
    for i in 0..<adet {
        fiyat = max(1, fiyat * (1 + (egim + Double.random(in: -gurultu...gurultu, using: &rng)) / 100))
        let tarih = Calendar.current.date(byAdding: .day, value: -(adet - i), to: bugun)!
        sonuc.append(Mum(tarih: tarih, acilis: fiyat, yuksek: fiyat * 1.005,
                         dusuk: fiyat * 0.995, kapanis: fiyat, hacim: 1_000_000))
    }
    return sonuc
}

@Test func neptunYetersizVeriNil() {
    #expect(Neptun().degerlendir(mumlar(egim: 0.2, adet: 50)) == nil)
}

@Test func neptunYukselistePozitifTahmin() throws {
    let t = try #require(Neptun().tahminEt(mumlar(egim: 0.4)))
    #expect(t.guven >= 0 && t.guven <= 95)
    #expect(t.tahminFiyat > 0)
    #expect(t.ufukGun >= 1)
    #expect(t.degisimYuzde > -50 && t.degisimYuzde < 50)   // sanity clamp tutuyor
}

@Test func neptunKatkiUretir() throws {
    let k = try #require(Neptun().degerlendir(mumlar(egim: 0.4)))
    #expect(k.motor == "Neptün")
    #expect(k.skor >= 0 && k.skor <= 100)
}

@Test func neptunKonseyeGirer() {
    let sonuc = Konsey(motorlar: [Merkur(), Neptun()]).karar(mumlar(egim: 0.4))
    #expect(sonuc.katkilar.count == 2)
}
