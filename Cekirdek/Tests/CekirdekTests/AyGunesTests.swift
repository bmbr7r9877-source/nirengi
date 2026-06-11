import Testing
import Foundation
@testable import Cekirdek

/// Verilen motor oyları + sonucu olan tek kayıt üretir.
private func kayit(motor: String, skor: Double, getiri: Double?) -> SicilKaydi {
    var k = SicilKaydi(tarih: Date(), sembol: "TEST", fiyat: 100, nirengiSkor: skor,
                       karar: skor >= 60 ? "Al" : (skor <= 40 ? "Sat" : "Tut"),
                       motorlar: [motor: MotorOyu(skor: skor, guven: 0.8)])
    if let g = getiri {
        k.fiyatSonra = 100 * (1 + g / 100)
        k.getiriYuzde = g
        k.degerlendirmeTarihi = Date()
    }
    return k
}

@Test func ayIsabetliMotorAgirligiArtar() {
    // "İyi" motor: boğa dediğinde hep yükselmiş. "Kötü" motor: boğa dediğinde hep düşmüş.
    var kayitlar: [SicilKaydi] = []
    for _ in 0..<30 {
        kayitlar.append(kayit(motor: "İyi", skor: 70, getiri: 4))
        kayitlar.append(kayit(motor: "Kötü", skor: 70, getiri: -4))
    }
    let a = Ay().ogren(kayitlar)
    let iyi = a.carpanlar["İyi"] ?? 1
    let kotu = a.carpanlar["Kötü"] ?? 1
    #expect(iyi > 1.0, "İsabetli motor çarpanı (\(iyi)) > 1 olmalı")
    #expect(kotu < 1.0, "İsabetsiz motor çarpanı (\(kotu)) < 1 olmalı")
    #expect(a.isabet["İyi"] == 1.0)
}

@Test func ayAzVeriNotreYakin() {
    // Sadece 3 kayıt → shrinkage çarpanı 1.0'a yakın tutmalı.
    let kayitlar = (0..<3).map { _ in kayit(motor: "X", skor: 70, getiri: 5) }
    let a = Ay().ogren(kayitlar)
    let c = a.carpanlar["X"] ?? 1
    #expect(abs(c - 1.0) < 0.2, "Az veride çarpan (\(c)) nötre yakın olmalı")
}

@Test func ayOlgunOlmayanSayilmaz() {
    let kayitlar = (0..<10).map { _ in kayit(motor: "X", skor: 70, getiri: nil) }
    let a = Ay().ogren(kayitlar)
    #expect(a.ornekSayisi == 0)
    #expect(a.carpanlar.isEmpty)
}

@Test func gunesYuksekIsabetGuvenir() {
    // Kararlar hep tutmuş → güven katsayısı yüksek (skoru kısma).
    let kayitlar = (0..<60).map { _ in kayit(motor: "M", skor: 70, getiri: 4) }
    let k = Gunes().kalibreEt(kayitlar)
    #expect(k.genelIsabet == 1.0)
    #expect(k.guvenKatsayi > 0.8, "Yüksek isabette katsayı (\(k.guvenKatsayi)) yüksek olmalı")
}

@Test func gunesYaziTuraSkoruKisar() {
    // Yarısı tutmuş yarısı tutmamış → model bilgi taşımıyor → katsayı düşük.
    var kayitlar: [SicilKaydi] = []
    for i in 0..<60 { kayitlar.append(kayit(motor: "M", skor: 70, getiri: i % 2 == 0 ? 4 : -4)) }
    let k = Gunes().kalibreEt(kayitlar)
    #expect(k.guvenKatsayi < 0.7, "Yazı-tura modelde katsayı (\(k.guvenKatsayi)) düşük olmalı")
    // Uygulama: skor 80 → 50'ye doğru çekilmeli.
    let kalibre = Gunes.uygula(80, k)
    #expect(kalibre < 80 && kalibre > 50)
}
