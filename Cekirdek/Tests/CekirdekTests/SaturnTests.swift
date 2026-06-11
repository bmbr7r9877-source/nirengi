import Testing
@testable import Cekirdek

@Test func saturnGucluTemelYuksekSkor() throws {
    var v = TemelVeri()
    v.fk = 7; v.pddd = 0.9; v.roe = 0.30; v.roa = 0.12; v.netMarj = 0.18
    v.borcOzkaynak = 0.2; v.cariOran = 2.0; v.gelirBuyume = 0.25; v.karBuyume = 0.22
    let s = try #require(Saturn().analiz(v))
    #expect(s.guvenilir)
    #expect(s.skor > 75, "Güçlü temel skoru 75+ olmalı, geldi: \(s.skor)")
}

@Test func saturnZayifTemelDusukSkor() throws {
    var v = TemelVeri()
    v.fk = 45; v.pddd = 9; v.roe = -0.05; v.roa = -0.02; v.netMarj = -0.03
    v.borcOzkaynak = 3.5; v.cariOran = 0.7; v.gelirBuyume = -0.15; v.karBuyume = -0.20
    let s = try #require(Saturn().analiz(v))
    #expect(s.skor < 40, "Zayıf temel skoru 40 altı olmalı, geldi: \(s.skor)")
}

@Test func saturnYetersizVeriNotr() throws {
    var v = TemelVeri()
    v.fk = 10   // tek metrik → 1 bölüm → güvenilmez
    let s = try #require(Saturn().analiz(v))
    #expect(!s.guvenilir)
    #expect(s.skor == 50)
}

@Test func saturnHicVeriYokNil() {
    #expect(Saturn().analiz(TemelVeri()) == nil)
}

@Test func saturnKatkiGuven() throws {
    var v = TemelVeri()
    v.fk = 7; v.roe = 0.30; v.netMarj = 0.18; v.borcOzkaynak = 0.2; v.gelirBuyume = 0.2
    let k = try #require(Saturn().katki(v))
    #expect(k.motor == "Satürn")
    #expect(k.guven == 0.8)   // güvenilir
}
