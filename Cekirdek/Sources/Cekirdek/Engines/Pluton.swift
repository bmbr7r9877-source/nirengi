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
///
/// BIST uyarlaması (PiyasaProfili üzerinden, mutlak eşik gömülmez):
///   • Taban serisi (≥2 ardışık limit-aşağı bar): fiyat keşfi yok, kuyrukta satış
///     birikmiş — "dip" yanılsamadır, motor susar (nil). Tek taban barında dip
///     teyidi sayılmaz ve ceza uygulanır (mıknatıs etkisi: limit devamı olasıdır).
///   • Hacim teyidi medyan bazlı ve limit barında geçersiz (tavan/taban hacmi yapay).
///   • Volatilite cezası görelidir: kısa vadeli vol kendi uzun vadeli rejiminin
///     üstüne çıktıysa ceza (sabit % eşik yok — her piyasada çalışır).
///   • Maliyet bilinci: orta banda dönüş potansiyeli gidiş-dönüş maliyeti
///     karşılamıyorsa skor nötrale çekilir.
///   • VBTS tedbiri: güven tedbir çarpanıyla kırpılır; ağır kademede (brüt takas,
///     tek fiyat) skor da nötrale çekilir.
public struct Pluton {
    public let isim = "Plüton"

    public let geriBakis: Int
    public let regresyonK: Double
    public let profil: PiyasaProfili

    public init(geriBakis: Int = 120, regresyonK: Double = 2.0, profil: PiyasaProfili = .bist) {
        self.geriBakis = geriBakis
        self.regresyonK = regresyonK
        self.profil = profil
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

        // Limit rejimi: ≥2 ardışık taban barında "geri dönüş" okunamaz — kuyrukta
        // eşleşmemiş satış var, gözüken dip gerçek talep dengesi değil. Motor susar.
        let tabanSeri = limitSerisi(kapanis, yon: -1)
        if tabanSeri >= 2 { return nil }
        let sonBarTaban = tabanSeri == 1
        let sonBarTavan = limitSerisi(kapanis, yon: 1) >= 1

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

        // Tetikleyiciler. Taban barındaki "alt bant teması" sayılmaz:
        // limitli düşüşte gün içi dip yapay olarak kesilmiştir.
        let altTema = son.dusuk <= alt + 0.10 * tampon && !sonBarTaban
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

        // Hacim teyidi: medyan bazlı (tavan/taban barları ortalamayı çarpıtır)
        // ve limit barında geçersiz — limit hacmi gerçek alıcı iştahı değildir.
        let hacimler = dilim.suffix(21).dropLast().map(\.hacim).sorted()
        if !hacimler.isEmpty, !sonBarTaban, !sonBarTavan {
            let medyanHacim = hacimler[hacimler.count / 2]
            if medyanHacim > 0 && son.hacim > 1.5 * medyanHacim { skor += 10 }
        }

        // Cezalar.
        if egim < -(orta * 0.0005) { skor -= 20 }
        // Volatilite rejimi (göreli): son 20 barın oynaklığı kendi uzun vadeli
        // rejiminin belirgin üstündeyse geri dönüş zamanlaması güvenilmez.
        if volRejimOrani(kapanis) > 1.6 { skor -= 10 }
        if rsiSon > 50 { skor -= 15 }
        // Taban barı: dip teyidi yok + mıknatıs etkisi (limit devamı olası).
        if sonBarTaban { skor -= 15 }

        // Maliyet bilinci: orta banda dönüş bile gidiş-dönüş maliyetini
        // karşılamıyorsa sinyalin pratikte değeri yok — nötrale çek.
        let potansiyelYuzde = son.kapanis > 0 ? (t1 - son.kapanis) / son.kapanis * 100 : 0
        let maliyetsiz = potansiyelYuzde < 2 * profil.islemMaliyetiYuzde
        if maliyetsiz { skor = 50 + (skor - 50) * 0.5 }

        skor = min(max(skor, 0), 100)

        var aciklama = gerekce(skor: skor, tema: altTema, rsi: rsiDonus, uyum: uyumsuzluk, egim: egim)
        if sonBarTaban { aciklama += " Taban barı: dip teyidi yok, limit devamı riski." }
        if maliyetsiz { aciklama += " Dönüş potansiyeli işlem maliyetini karşılamıyor." }
        return Sonuc(skor: skor, altBant: alt, ortaBant: orta, ustBant: ust,
                     girisAlt: girisAlt, girisUst: girisUst, gecersizSeviye: gecersiz,
                     hedefler: [t1, t2], rKare: rKare, aciklama: aciklama)
    }

    /// Konsey katkısı (güven: R² ölçeklendirir, 0.4..0.75).
    /// VBTS tedbiri varsa güven tedbir çarpanıyla kırpılır; ağır kademede
    /// (brüt takas, tek fiyat) fiyat keşfi bozuk olduğundan skor da nötrale çekilir.
    public func katki(_ mumlar: [Mum], tedbirler: [Tedbir] = []) -> Katki? {
        guard let s = degerlendir(mumlar) else { return nil }
        let tedbirCarpani = TedbirListesi.guvenCarpani(tedbirler)
        let guven = min(0.75, 0.4 + s.rKare * 0.5) * tedbirCarpani
        var skor = s.skor
        var gerekce = s.aciklama
        if tedbirCarpani <= 0.7 {
            skor = 50 + (skor - 50) * tedbirCarpani
            gerekce += " Ağır VBTS tedbiri: fiyat keşfi kısıtlı."
        }
        return Katki(motor: isim, skor: skor, guven: guven, gerekce: gerekce)
    }

    // MARK: - BIST'e özgü rejim tespitleri

    /// Son bardan geriye ardışık limit-hareketi sayısı (yön: +1 tavan, −1 taban).
    /// Limit hareketi: günlük değişim, profil limitinin `limitYakinlikOrani`
    /// katına ulaşmış bar. Limitsiz piyasada hep 0.
    private func limitSerisi(_ kapanis: [Double], yon: Double) -> Int {
        guard let limit = profil.gunlukLimitYuzde, kapanis.count >= 2 else { return 0 }
        let esik = limit * profil.limitYakinlikOrani
        var seri = 0
        var i = kapanis.count - 1
        while i >= 1, kapanis[i - 1] > 0 {
            let degisim = (kapanis[i] - kapanis[i - 1]) / kapanis[i - 1] * 100
            if degisim * yon >= esik { seri += 1; i -= 1 } else { break }
        }
        return seri
    }

    /// Kısa vadeli (20 bar) getiri oynaklığının uzun vadeli rejime oranı.
    /// >1 = oynaklık kendi normalinin üstünde. Mutlak eşik içermez.
    private func volRejimOrani(_ kapanis: [Double]) -> Double {
        func std(_ d: ArraySlice<Double>) -> Double {
            var getiriler: [Double] = []
            var onceki: Double?
            for f in d {
                if let o = onceki, o > 0 { getiriler.append((f - o) / o) }
                onceki = f
            }
            guard getiriler.count >= 2 else { return 0 }
            let ort = getiriler.reduce(0, +) / Double(getiriler.count)
            return (getiriler.reduce(0) { $0 + ($1 - ort) * ($1 - ort) } / Double(getiriler.count - 1)).squareRoot()
        }
        let uzun = std(kapanis[...])
        let kisa = std(kapanis.suffix(21))
        guard uzun > 0 else { return 1 }
        return kisa / uzun
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
