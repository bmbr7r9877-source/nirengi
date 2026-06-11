import Foundation

/// Gostergeler — standart teknik analiz göstergeleri (kamuya açık matematik).
/// Sıfırdan, özgün uygulama. Tüm fonksiyonlar saf (yan etkisiz).
public enum Gostergeler {

    // MARK: - Hareketli ortalama (SMA)

    /// Her indekse hizalı SMA dizisi (ilk period-1 eleman nil).
    public static func sma(_ d: [Double], _ periyot: Int) -> [Double?] {
        guard periyot > 0, d.count >= periyot else { return Array(repeating: nil, count: d.count) }
        var sonuc = [Double?](repeating: nil, count: d.count)
        var toplam = d[0..<periyot].reduce(0, +)
        sonuc[periyot - 1] = toplam / Double(periyot)
        for i in periyot..<d.count {
            toplam += d[i] - d[i - periyot]
            sonuc[i] = toplam / Double(periyot)
        }
        return sonuc
    }

    public static func sonSMA(_ d: [Double], _ periyot: Int) -> Double? {
        guard d.count >= periyot, periyot > 0 else { return nil }
        return d.suffix(periyot).reduce(0, +) / Double(periyot)
    }

    /// Üssel hareketli ortalama dizisi.
    public static func ema(_ d: [Double], _ periyot: Int) -> [Double?] {
        guard periyot > 0, d.count >= periyot else { return Array(repeating: nil, count: d.count) }
        var sonuc = [Double?](repeating: nil, count: d.count)
        let k = 2.0 / Double(periyot + 1)
        var onceki = d[0..<periyot].reduce(0, +) / Double(periyot)   // SMA ile başlat
        sonuc[periyot - 1] = onceki
        for i in periyot..<d.count {
            onceki = (d[i] - onceki) * k + onceki
            sonuc[i] = onceki
        }
        return sonuc
    }

    // MARK: - RSI (Wilder)

    public static func sonRSI(_ kapanis: [Double], periyot: Int = 14) -> Double? {
        guard kapanis.count > periyot else { return nil }
        var kazanc = 0.0, kayip = 0.0
        for i in 1...periyot {
            let d = kapanis[i] - kapanis[i - 1]
            if d >= 0 { kazanc += d } else { kayip -= d }
        }
        var ortK = kazanc / Double(periyot)
        var ortY = kayip / Double(periyot)
        if kapanis.count > periyot + 1 {
            for i in (periyot + 1)..<kapanis.count {
                let d = kapanis[i] - kapanis[i - 1]
                ortK = (ortK * Double(periyot - 1) + max(0, d)) / Double(periyot)
                ortY = (ortY * Double(periyot - 1) + max(0, -d)) / Double(periyot)
            }
        }
        guard ortY > 0 else { return 100 }
        return 100 - (100 / (1 + ortK / ortY))
    }

    // MARK: - MACD

    /// (macd çizgisi, sinyal, histogram) son değerleri.
    public static func sonMACD(_ kapanis: [Double], hizli: Int = 12, yavas: Int = 26, sinyal: Int = 9)
        -> (macd: Double?, sinyal: Double?, histogram: Double?) {
        guard kapanis.count >= yavas + sinyal else { return (nil, nil, nil) }
        let emaHizli = ema(kapanis, hizli)
        let emaYavas = ema(kapanis, yavas)
        var macdDizi: [Double] = []
        for i in 0..<kapanis.count {
            if let h = emaHizli[i], let y = emaYavas[i] { macdDizi.append(h - y) }
        }
        guard macdDizi.count >= sinyal else { return (macdDizi.last, nil, nil) }
        let sinyalDizi = ema(macdDizi, sinyal)
        let macd = macdDizi.last
        let sig = sinyalDizi.last ?? nil
        let hist = (macd != nil && sig != nil) ? macd! - sig! : nil
        return (macd, sig, hist)
    }

    // MARK: - ATR (Wilder)

    public static func sonATR(_ mumlar: [Mum], periyot: Int = 14) -> Double? {
        guard mumlar.count >= periyot + 1 else { return nil }
        var tr: [Double] = []
        for i in 1..<mumlar.count {
            let h = mumlar[i].yuksek, l = mumlar[i].dusuk, oc = mumlar[i - 1].kapanis
            tr.append(max(h - l, max(abs(h - oc), abs(l - oc))))
        }
        let son = tr.suffix(periyot)
        return son.isEmpty ? nil : son.reduce(0, +) / Double(son.count)
    }

    // MARK: - ADX (trend gücü)

    public static func sonADX(_ mumlar: [Mum], periyot: Int = 14) -> Double? {
        guard mumlar.count >= periyot * 2 else { return nil }
        var trList: [Double] = [], plusDM: [Double] = [], minusDM: [Double] = []
        for i in 1..<mumlar.count {
            let h = mumlar[i].yuksek, l = mumlar[i].dusuk
            let ph = mumlar[i - 1].yuksek, pl = mumlar[i - 1].dusuk, pc = mumlar[i - 1].kapanis
            let up = h - ph, down = pl - l
            plusDM.append((up > down && up > 0) ? up : 0)
            minusDM.append((down > up && down > 0) ? down : 0)
            trList.append(max(h - l, max(abs(h - pc), abs(l - pc))))
        }
        func wilder(_ x: [Double]) -> [Double] {
            guard x.count >= periyot else { return [] }
            var sonuc: [Double] = []
            var t = x[0..<periyot].reduce(0, +)
            sonuc.append(t)
            for i in periyot..<x.count { t = t - t / Double(periyot) + x[i]; sonuc.append(t) }
            return sonuc
        }
        let trS = wilder(trList), pS = wilder(plusDM), mS = wilder(minusDM)
        guard trS.count == pS.count, trS.count == mS.count, !trS.isEmpty else { return nil }
        var dx: [Double] = []
        for i in 0..<trS.count where trS[i] > 0 {
            let pdi = 100 * pS[i] / trS[i]
            let mdi = 100 * mS[i] / trS[i]
            let sum = pdi + mdi
            dx.append(sum > 0 ? 100 * abs(pdi - mdi) / sum : 0)
        }
        guard dx.count >= periyot else { return dx.last }
        return dx.suffix(periyot).reduce(0, +) / Double(periyot)
    }

    // MARK: - CCI

    public static func sonCCI(_ mumlar: [Mum], periyot: Int = 20) -> Double? {
        guard mumlar.count >= periyot else { return nil }
        let dilim = mumlar.suffix(periyot)
        let tp = dilim.map { ($0.yuksek + $0.dusuk + $0.kapanis) / 3.0 }
        let ortTP = tp.reduce(0, +) / Double(periyot)
        let ortSapma = tp.map { abs($0 - ortTP) }.reduce(0, +) / Double(periyot)
        guard ortSapma > 0, let sonTP = tp.last else { return nil }
        return (sonTP - ortTP) / (0.015 * ortSapma)
    }
}
