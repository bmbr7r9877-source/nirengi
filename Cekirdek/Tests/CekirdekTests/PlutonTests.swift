import Testing
import Foundation
@testable import Cekirdek

/// Düşüş + son barlarda dip toparlanma içeren seri üretir (geri dönüş senaryosu).
private func dipSeri(adet: Int = 150) -> [Mum] {
    var sonuc: [Mum] = []
    let bugun = Date()
    for i in 0..<adet {
        // İlk %85 düzgün düşüş, son %15 dipten hafif toparlanma.
        let oran = Double(i) / Double(adet)
        let fiyat: Double
        if oran < 0.85 {
            fiyat = 100 - oran * 40                 // 100 → 66
        } else {
            fiyat = 66 + (oran - 0.85) * 30         // dipten toparlanma
        }
        let t = Calendar.current.date(byAdding: .day, value: -(adet - i), to: bugun)!
        let dusuk = fiyat * (i == adet - 1 ? 0.985 : 0.997)
        sonuc.append(Mum(tarih: t, acilis: fiyat, yuksek: fiyat * 1.003,
                         dusuk: dusuk, kapanis: fiyat,
                         hacim: i == adet - 1 ? 3_000_000 : 1_000_000))
    }
    return sonuc
}

private func duzSeri(adet: Int = 150, baslangic: Double = 100) -> [Mum] {
    var rng = SystemRandomNumberGenerator()
    var fiyat = baslangic
    var sonuc: [Mum] = []
    let bugun = Date()
    for i in 0..<adet {
        fiyat = max(1, fiyat * (1 + Double.random(in: -0.3...0.3, using: &rng) / 100))
        let t = Calendar.current.date(byAdding: .day, value: -(adet - i), to: bugun)!
        sonuc.append(Mum(tarih: t, acilis: fiyat, yuksek: fiyat * 1.004,
                         dusuk: fiyat * 0.996, kapanis: fiyat, hacim: 1_000_000))
    }
    return sonuc
}

@Test func plutonYetersizVeriNil() {
    #expect(Pluton().degerlendir(duzSeri(adet: 40)) == nil)
}

@Test func plutonKanalSeviyeleriTutarli() throws {
    // Düz gürültülü seride R² çok düşük → kanal yok (nil) doğrudur; trendli seri kullan.
    let s = try #require(Pluton().degerlendir(dipSeri()))
    #expect(s.altBant < s.ortaBant)
    #expect(s.ortaBant < s.ustBant)
    #expect(s.girisAlt <= s.girisUst)
}

@Test func plutonDipToparlanmaSkorlar() throws {
    let s = try #require(Pluton().degerlendir(dipSeri()))
    #expect(s.skor >= 0 && s.skor <= 100)
    // Dip seride R² yüksek (düzgün trend) — kanal güvenilir olmalı.
    #expect(s.rKare > 0.3, "R² (\(s.rKare)) düzgün trendde anlamlı olmalı")
}

@Test func plutonKatkiUretir() throws {
    let k = try #require(Pluton().katki(dipSeri()))
    #expect(k.motor == "Plüton")
    #expect(k.guven >= 0.4 && k.guven <= 0.75)
}

// MARK: - BIST uyarlaması

/// Dip serinin sonuna ardışık taban (−%9.5) barları ekler.
private func tabanSerili(_ adetTaban: Int) -> [Mum] {
    var m = dipSeri()
    var fiyat = m.last!.kapanis
    let bugun = Date()
    for i in 0..<adetTaban {
        fiyat *= 0.905
        let t = Calendar.current.date(byAdding: .day, value: i + 1, to: bugun)!
        m.append(Mum(tarih: t, acilis: fiyat / 0.905, yuksek: fiyat / 0.905,
                     dusuk: fiyat, kapanis: fiyat, hacim: 500_000))
    }
    return m
}

@Test func plutonTabanSerisindeSusar() {
    // ≥2 ardışık taban barı: fiyat keşfi yok, motor nil dönmeli.
    #expect(Pluton().degerlendir(tabanSerili(2)) == nil)
    #expect(Pluton().degerlendir(tabanSerili(3)) == nil)
}

@Test func plutonTekTabanBarindaTemkinli() throws {
    // Tek taban barında susmaz ama dip teyidi vermez + ceza yer:
    // skor, taban barı olmayan aynı serinin skorunun altında kalmalı.
    let tabanli = Pluton().degerlendir(tabanSerili(1))
    let normal = try #require(Pluton().degerlendir(dipSeri()))
    if let t = tabanli { #expect(t.skor < normal.skor) }
}

@Test func plutonLimitsizPiyasadaTabanSerisiYok() throws {
    // Serbest profilde (limit yok) aynı seri limit rejimi sayılmaz, motor konuşur.
    let s = Pluton(profil: .serbest).degerlendir(tabanSerili(2))
    #expect(s != nil)
}

@Test func plutonAgirTedbirSkoruNotraleCeker() throws {
    let temiz = try #require(Pluton().katki(dipSeri()))
    let tedbir = Tedbir(sembol: "TEST", tur: .tekFiyat, ad: "Tek Fiyat",
                        baslangic: nil, bitis: nil)
    let tedbirli = try #require(Pluton().katki(dipSeri(), tedbirler: [tedbir]))
    #expect(tedbirli.guven < temiz.guven)
    #expect(abs(tedbirli.skor - 50) <= abs(temiz.skor - 50))
}
