import Testing
@testable import Cekirdek

private func duz(_ deger: Double, _ n: Int = 60) -> [Double] { Array(repeating: deger, count: n) }
private func artan(_ bas: Double, _ son: Double, _ n: Int = 60) -> [Double] {
    (0..<n).map { bas + (son - bas) * Double($0) / Double(n - 1) }
}

@Test func jupiterRiskOnYuksekSkor() throws {
    var g = MakroGirdi()
    g.vix = duz(11)                    // çok düşük korku → 95
    g.spy = artan(90, 110)             // yükselen → SMA üstü 80
    g.dxy = artan(105, 98)             // zayıf dolar → 70
    g.altin = duz(100)                 // nötr
    g.faiz10y = artan(4.8, 4.3)        // düşen faiz → risk-on
    g.usdtry = duz(46)                 // sabit lira
    let s = try #require(Jupiter().analiz(g))
    #expect(s.skor > 65, "Risk-on skoru 65+ olmalı: \(s.skor)")
    #expect(s.rejim == .riskIstahli)
}

@Test func jupiterRiskOffDusukSkor() throws {
    var g = MakroGirdi()
    g.vix = duz(38)                    // yüksek korku → ~5
    g.spy = artan(110, 90)             // düşen → 20
    g.dxy = artan(98, 106)             // güçlü dolar → 40
    g.altin = artan(95, 110)           // altına kaçış → düşük
    g.faiz10y = artan(4.0, 4.8)        // yükselen faiz → risk-off
    g.usdtry = artan(45, 47)           // lira değer kaybı → risk-off
    let s = try #require(Jupiter().analiz(g))
    #expect(s.skor < 40, "Risk-off skoru 40 altı olmalı: \(s.skor)")
    #expect(s.rejim == .savunmaci)
}

@Test func jupiterEksikVeriRenormalize() throws {
    var g = MakroGirdi()
    g.vix = duz(15)                    // tek bileşen yeter
    let s = try #require(Jupiter().analiz(g))
    #expect(s.bilesenler.count == 1)
    #expect(s.skor > 0)
}

@Test func jupiterHicVeriNil() {
    #expect(Jupiter().analiz(MakroGirdi()) == nil)
}
