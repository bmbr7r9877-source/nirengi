import Testing
import Foundation
@testable import Cekirdek

private func marsSeri(egim: Double, adet: Int = 300, baslangic: Double = 100, hacim: Double = 5_000_000) -> [Mum] {
    var rng = SystemRandomNumberGenerator()
    var fiyat = baslangic
    var sonuc: [Mum] = []
    let bugun = Date()
    for i in 0..<adet {
        fiyat = max(1, fiyat * (1 + (egim + Double.random(in: -0.4...0.4, using: &rng)) / 100))
        let t = Calendar.current.date(byAdding: .day, value: -(adet - i), to: bugun)!
        sonuc.append(Mum(tarih: t, acilis: fiyat, yuksek: fiyat * 1.003,
                         dusuk: fiyat * 0.997, kapanis: fiyat, hacim: hacim))
    }
    return sonuc
}

@Test func marsYetersizVeriNil() {
    #expect(Mars().degerlendir(marsSeri(egim: 0.1, adet: 20)) == nil)
}

@Test func marsGucluMomentumYuksekSkor() throws {
    let mars = Mars()
    let yukselen = try #require(mars.degerlendir(marsSeri(egim: 0.4)))
    let dusen = try #require(mars.degerlendir(marsSeri(egim: -0.4)))
    #expect(yukselen.faktorler.momentum > dusen.faktorler.momentum)
    #expect(yukselen.skor > dusen.skor)
}

@Test func marsTemelVeriGuveniArtirir() throws {
    let mars = Mars()
    var temel = TemelVeri()
    temel.fk = 7; temel.pddd = 0.9; temel.roe = 0.28; temel.netMarj = 0.22; temel.borcOzkaynak = 0.2
    let fiyatlar = marsSeri(egim: 0.2)
    let kFiyat = try #require(mars.katki(fiyatlar))
    let kTemel = try #require(mars.katki(fiyatlar, temel: temel))
    #expect(kTemel.guven > kFiyat.guven)
    // Ucuz + kaliteli temel skoru yukarı taşımalı.
    let sTemel = try #require(mars.degerlendir(fiyatlar, temel: temel))
    #expect(sTemel.guvenilir)
    #expect(sTemel.faktorler.deger != nil && sTemel.faktorler.kalite != nil)
}

@Test func marsKatkiUretir() throws {
    let k = try #require(Mars().katki(marsSeri(egim: 0.2)))
    #expect(k.motor == "Mars")
    #expect(k.skor >= 0 && k.skor <= 100)
}
