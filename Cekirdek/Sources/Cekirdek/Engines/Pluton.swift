import Foundation

/// Plüton — geri dönüş (mean reversion) motoru. (Argus "Phoenix" mantığı, sıfırdan yazıldı.)
///
/// Doğrusal regresyon kanalı kurar (orta + ±k·σ bantları), fiyat alt banda yakınken
/// toparlanma sinyallerini puanlar:
///   • Alt bant teması (+20) · RSI dönüşü 40 altından (+15) · boğa uyumsuzluğu (+15)
///   • Derin aşırı-satım RSI<35 (+10) · hacim teyidi (+10)
///   • Cezalar: güçlü düşüş eğimi (−20) · yüksek volatilite (−10) · aşırı-satım değil RSI>50 (−15)
///
/// Kanal güvenilirliği R² ile ölçülür; zayıf kanalda skor YÖNE devrilmez, NÖTRALE
/// çekilir (Argus'un whiplash düzeltmesi): skor = 50 + (skor−50)·çarpan.
public struct Pluton {
    public let isim = "Plüton"

    public let geriBakis: Int
    public let regresyonK: Double

    public init(geriBakis: Int = 120, regresyonK: Double = 2.0) {
        self.geriBakis = geriBakis
        self.regresyonK = regresyonK
    }

    public struct Sonuc: Sendable {
        public let skor: Double           // 0..100
        public let altBant: Double
        public let ortaBant: Double
        public let ustBant: Double
        public let girisAlt: Double        // alım bölgesi
        public let girisUst: Double
        public let gecersizSeviye: Double  // invalidation
        public let hedefler: [Double]
        public let rKare: Double
        public let aciklama: String
    }

    public func degerlendir(_ mumlar: [Mum]) -> Sonuc? {
        let m = mumlar.sorted { $0.tarih < $1.tarih }
        guard m.count >= 60 else { return nil }

        let N = min(geriBakis, m.count)
        let dilim = Array(m.suffix(N))
        let kapanis = dilim.map(\.kapanis)

        let (egim, kesisim, sigma, orta, ust, alt) = kanal(kapanis, k: regresyonK)
        guard let son = dilim.last else { return nil }
        let atr = Gostergeler.sonATR(dilim, periyot: 14)

        // Tampon + bölgeler.
        let tampon: Double = atr.map { max(0.5 * $0, 0.15 * sigma) } ?? (0.15 * sigma)
        let girisAlt = alt - 0.10 * tampon
        let girisUst = min(alt + 0.90 * tampon, orta)
        let gecersiz = atr.map { alt - 0.75 * $0 } ?? (alt - 1.25 * sigma)

        // Hedefler: T1 = orta bant, T2 = düşüşte temkinli.
        let dususte = egim < -(orta * 0.0005)
        let t1 = orta
        let t2 = dususte ? orta + (ust - orta) * 0.5 : ust

        // Kanal güvenilirliği (R²) → kademeli çarpan.
        let rKare = rKareHesap(kapanis, egim: egim, kesisim: kesisim)
        let carpan: Double
        switch rKare {
        case 0.60...:     carpan = 1.00
        case 0.45..<0.60: carpan = 0.85
        case 0.30..<0.45: carpan = 0.65
        case 0.20..<0.30: carpan = 0.40
        case 0.10..<0.20: carpan = 0.20
        case 0.05..<0.10: carpan = 0.08
        default:          return nil   // R² < 0.05: kanal yok hükmünde
        }

        // Tetikleyiciler.
        let altTema = son.dusuk <= alt + 0.10 * tampon
        let rsiDizi = rsiDizisi(dilim, periyot: 14)
        let rsiSon = rsiDizi.last ?? 50
        let rsiOnce = rsiDizi.dropLast().last ?? 50
        let rsiDonus = rsiSon >= 40 && rsiOnce < 40 && rsiSon > rsiOnce
        let uyumsuzluk = bogaUyumsuzlugu(dilim, rsi: rsiDizi, geriBak: 30)
        let trendUygun = egim >= 0 || egim > -(orta * 0.0002)
        let yukselen = egim > 0 && son.kapanis > orta

        // Puanlama.
        var skor = 50.0
        if altTema { skor += 20 }
        if rsiDonus { skor += 15 }
        if uyumsuzluk { skor += 15 }
        if rsiSon < 35 { skor += 10 }
        if trendUygun { skor += 5 }
        if yukselen && !altTema { skor = 40 + (egim > 0 ? 10 : 0) }

        // Kanal güvenilirliği: nötrale çek (yöne devirme).
        skor = 50 + (skor - 50) * carpan

        // Hacim teyidi.
        let ortHacim = dilim.suffix(21).prefix(20).map(\.hacim).reduce(0, +) / 20.0
        if ortHacim > 0 && son.hacim > 1.5 * ortHacim { skor += 10 }

        // Cezalar.
        if egim < -(orta * 0.0005) { skor -= 20 }
        if orta > 0 && sigma / orta > 0.08 { skor -= 10 }
        if rsiSon > 50 { skor -= 15 }

        skor = min(max(skor, 0), 100)

        let aciklama = gerekce(skor: skor, tema: altTema, rsi: rsiDonus, uyum: uyumsuzluk, egim: egim)
        return Sonuc(skor: skor, altBant: alt, ortaBant: orta, ustBant: ust,
                     girisAlt: girisAlt, girisUst: girisUst, gecersizSeviye: gecersiz,
                     hedefler: [t1, t2], rKare: rKare, aciklama: aciklama)
    }

    /// Konsey katkısı (güven: R² ölçeklendirir, 0.4..0.75).
    public func katki(_ mumlar: [Mum]) -> Katki? {
        guard let s = degerlendir(mumlar) else { return nil }
        let guven = min(0.75, 0.4 + s.rKare * 0.5)
        return Katki(motor: isim, skor: s.skor, guven: guven, gerekce: s.aciklama)
    }

    // MARK: - Matematik

    private func kanal(_ closes: [Double], k: Double)
        -> (egim: Double, kesisim: Double, sigma: Double, orta: Double, ust: Double, alt: Double) {
        let n = Double(closes.count)
        guard n > 1 else { return (0, 0, 0, 0, 0, 0) }
        var sx = 0.0, sy = 0.0, sxy = 0.0, sx2 = 0.0
        for (i, y) in closes.enumerated() {
            let x = Double(i)
            sx += x; sy += y; sxy += x * y; sx2 += x * x
        }
        let egim = (n * sxy - sx * sy) / (n * sx2 - sx * sx)
        let kesisim = (sy - egim * sx) / n
        var kareToplam = 0.0
        for (i, y) in closes.enumerated() {
            let tahmin = kesisim + egim * Double(i)
            kareToplam += (y - tahmin) * (y - tahmin)
        }
        let sigma = (kareToplam / n).squareRoot()
        let orta = kesisim + egim * (n - 1)
        return (egim, kesisim, sigma, orta, orta + k * sigma, orta - k * sigma)
    }

    private func rKareHesap(_ closes: [Double], egim: Double, kesisim: Double) -> Double {
        guard closes.count > 1 else { return 0 }
        let ort = closes.reduce(0, +) / Double(closes.count)
        var ssRes = 0.0, ssTot = 0.0
        for (i, y) in closes.enumerated() {
            let tahmin = kesisim + egim * Double(i)
            ssRes += (y - tahmin) * (y - tahmin)
            ssTot += (y - ort) * (y - ort)
        }
        guard ssTot > 0 else { return 0 }
        return 1 - ssRes / ssTot
    }

    /// Wilder RSI serisi.
    private func rsiDizisi(_ mumlar: [Mum], periyot: Int) -> [Double] {
        let k = mumlar.map(\.kapanis)
        guard k.count > periyot else { return [] }
        var kazanc = 0.0, kayip = 0.0
        for i in 1...periyot {
            let d = k[i] - k[i - 1]
            if d >= 0 { kazanc += d } else { kayip -= d }
        }
        var ortKazanc = kazanc / Double(periyot)
        var ortKayip = kayip / Double(periyot)
        var sonuc: [Double] = []
        func rsi() -> Double { ortKayip == 0 ? 100 : 100 - 100 / (1 + ortKazanc / ortKayip) }
        sonuc.append(rsi())
        for i in (periyot + 1)..<k.count {
            let d = k[i] - k[i - 1]
            let g = d >= 0 ? d : 0, l = d < 0 ? -d : 0
            ortKazanc = (ortKazanc * Double(periyot - 1) + g) / Double(periyot)
            ortKayip = (ortKayip * Double(periyot - 1) + l) / Double(periyot)
            sonuc.append(rsi())
        }
        return sonuc
    }

    /// Boğa uyumsuzluğu: fiyat daha düşük dip yaparken RSI daha yüksek dip yapıyor.
    private func bogaUyumsuzlugu(_ mumlar: [Mum], rsi: [Double], geriBak: Int) -> Bool {
        guard rsi.count >= 20 else { return false }
        let boy = min(geriBak, rsi.count)
        let dilim = Array(rsi.suffix(boy))
        var dipler: [(Int, Double)] = []
        for i in 1..<(dilim.count - 1) where dilim[i] < dilim[i - 1] && dilim[i] < dilim[i + 1] && dilim[i] < 45 {
            dipler.append((i, dilim[i]))
        }
        guard dipler.count >= 2 else { return false }
        func fiyatDibi(_ dilimIndex: Int) -> Double {
            let ofset = dilim.count - 1 - dilimIndex
            return mumlar[mumlar.count - 1 - ofset].dusuk
        }
        let sonDip = dipler.last!
        let sonFiyat = fiyatDibi(sonDip.0)
        for i in 0..<(dipler.count - 1) {
            let onceki = dipler[i]
            if sonFiyat < fiyatDibi(onceki.0) && sonDip.1 > onceki.1 { return true }
        }
        return false
    }

    private func gerekce(skor: Double, tema: Bool, rsi: Bool, uyum: Bool, egim: Double) -> String {
        if skor >= 70 {
            return "Fiyat kanal dibine yakın; toparlanma sinyali (RSI/uyumsuzluk) ve hacim desteği var."
        } else if skor >= 40 {
            var p: [String] = []
            if tema { p.append("kanal teması") }
            if rsi { p.append("RSI dönüşü") }
            if uyum { p.append("uyumsuzluk") }
            let d = p.isEmpty ? "bekleme" : p.joined(separator: ", ")
            return "Kanal dibine yakınlık var ancak teyit zayıf (\(d))."
        } else {
            return egim < 0
                ? "Negatif trend eğimi nedeniyle geri dönüş senaryosu riskli."
                : "Teyit çok zayıf; geri dönüş için koşullar oluşmadı."
        }
    }
}
