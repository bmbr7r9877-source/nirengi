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

// MARK: - BIST profili

private func tavanSerisiMumlar(tavanGun: Int = 4) -> [Mum] {
    var m = mumlar(egim: 0.1, adet: 250, gurultu: 0.5)
    let bugun = Date()
    var fiyat = m.last!.kapanis
    for i in 0..<tavanGun {
        fiyat *= 1.099   // ardışık tavan
        let tarih = Calendar.current.date(byAdding: .day, value: i + 1, to: bugun)!
        m.append(Mum(tarih: tarih, acilis: fiyat, yuksek: fiyat, dusuk: fiyat * 0.99,
                     kapanis: fiyat, hacim: 1_000_000))
    }
    return m
}

@Test func neptunTavanSerisindeGuvenDusuk() throws {
    let normal = try #require(Neptun().tahminEt(mumlar(egim: 0.3, gurultu: 0.5)))
    let tavanli = try #require(Neptun().tahminEt(tavanSerisiMumlar()))
    #expect(tavanli.guven < normal.guven)
    #expect(tavanli.gerekce.contains("limit serisi"))
}

@Test func neptunTahminGunlukLimitiAsamaz() throws {
    let t = try #require(Neptun(profil: .bist).tahminEt(tavanSerisiMumlar(tavanGun: 6)))
    let bilesikLimit = (pow(1.10, Double(t.ufukGun)) - 1) * 100
    #expect(abs(t.degisimYuzde) <= bilesikLimit + 0.01)
}

@Test func neptunDusukLikiditeGuveniKirpar() throws {
    var kuru = mumlar(egim: 0.3, gurultu: 0.5)
    kuru = kuru.enumerated().map { i, m in
        let hacim = i >= kuru.count - 15 ? 100.0 : m.hacim
        return Mum(tarih: m.tarih, acilis: m.acilis, yuksek: m.yuksek,
                   dusuk: m.dusuk, kapanis: m.kapanis, hacim: hacim)
    }
    let normalGuven = try #require(Neptun().tahminEt(mumlar(egim: 0.3, gurultu: 0.5))).guven
    let kuruGuven = try #require(Neptun().tahminEt(kuru)).guven
    #expect(kuruGuven <= normalGuven)
}

@Test func neptunBaglamGuveniKirpar() throws {
    let hisse = mumlar(egim: 0.5, gurultu: 0.4)              // net yukarı tahmin
    let dusenEndeks = mumlar(egim: -1.2, gurultu: 0.3)       // sert düşüş rejimi
    let sakinKur = mumlar(egim: 0.05, gurultu: 0.05)
    let bagsiz = try #require(Neptun().tahminEt(hisse))
    let bagli = try #require(Neptun().tahminEt(hisse,
        baglam: Neptun.Baglam(endeks: dusenEndeks, usdtry: sakinKur)))
    #expect(bagli.guven < bagsiz.guven)
    #expect(bagli.gerekce.contains("endeks düşüş rejimi"))
}
