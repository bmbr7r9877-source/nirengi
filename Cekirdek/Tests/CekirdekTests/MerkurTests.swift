import Testing
import Foundation
@testable import Cekirdek

/// Gerçekçi mum üretici: eğim + gürültü (yeni mantık SMA200 ve canlı RSI ister).
private func mumlar(egim: Double, adet: Int = 220, baslangic: Double = 100, gurultu: Double = 2.0) -> [Mum] {
    var rng = SystemRandomNumberGenerator()
    var fiyat = baslangic
    var sonuc: [Mum] = []
    let bugun = Date()
    for i in 0..<adet {
        let g = Double.random(in: -gurultu...gurultu, using: &rng)
        fiyat = max(1, fiyat + egim + g)
        let tarih = Calendar.current.date(byAdding: .day, value: -(adet - i), to: bugun)!
        sonuc.append(Mum(tarih: tarih, acilis: fiyat, yuksek: fiyat + 0.6,
                         dusuk: fiyat - 0.6, kapanis: fiyat, hacim: 2_000_000))
    }
    return sonuc
}

@Test func yetersizVeriNilDoner() {
    #expect(Merkur().degerlendir(mumlar(egim: 1, adet: 10)) == nil)
}

@Test func gostergelerSaglikli() throws {
    let k = mumlar(egim: 0.5).map(\.kapanis)
    let rsi = try #require(Gostergeler.sonRSI(k))
    #expect(rsi >= 0 && rsi <= 100)
    #expect(Gostergeler.sonSMA(k, 200) != nil)
    #expect(Gostergeler.sonMACD(k).histogram != nil)
}

@Test func yukselenSkorDusendenYuksek() throws {
    let yu = try #require(Merkur().degerlendir(mumlar(egim: 0.8), endeks: nil))
    let du = try #require(Merkur().degerlendir(mumlar(egim: -0.8), endeks: nil))
    #expect(yu.skor > du.skor, "Yükselen (\(yu.skor)) düşenden (\(du.skor)) yüksek olmalı")
}

@Test func yukselenTrendYuksekSkor() throws {
    let s = try #require(Merkur().degerlendir(mumlar(egim: 0.8), endeks: nil))
    #expect(s.skor > 60, "Güçlü yükseliş skoru 60+ olmalı, geldi: \(s.skor) [\(s.verdict)]")
}

@Test func dusenTrendDusukSkor() throws {
    let s = try #require(Merkur().degerlendir(mumlar(egim: -1.2, gurultu: 1.0), endeks: nil))
    #expect(s.skor < 45, "Düşüş skoru 45 altı olmalı, geldi: \(s.skor) [\(s.verdict)]")
}

@Test func konseyKararUretir() {
    let sonuc = Konsey(motorlar: [Merkur()]).karar(mumlar(egim: 0.8))
    #expect(sonuc.katkilar.count == 1)
    #expect(sonuc.karar != .yetersizVeri)
}

@Test func bosMumYetersizVeri() {
    #expect(Konsey(motorlar: [Merkur()]).karar([]).karar == .yetersizVeri)
}

@Test func rsBacagiCalisir() throws {
    let hisse = mumlar(egim: 1.2)
    let endeks = mumlar(egim: 0.2)
    let rsli = try #require(Merkur().degerlendir(hisse, endeks: endeks))
    let rssiz = try #require(Merkur().degerlendir(hisse, endeks: nil))
    #expect(rsli.skor >= 0 && rsli.skor <= 100)
    #expect(rssiz.skor >= 0 && rssiz.skor <= 100)
}
