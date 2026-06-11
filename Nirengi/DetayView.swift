import SwiftUI
import Charts
import Cekirdek

/// Hisse detayı — Midas tarzı. Grafik SIRA ekseniyle çizilir (kapalı gün boşluğu olmaz).
struct DetayView: View {
    let satir: HisseSatiri
    @EnvironmentObject var model: PiyasaModel

    @State private var aralik: ZamanAralik = .gun1
    @State private var mum = false
    @State private var usd = false
    @State private var secilenIndex: Int?
    @State private var seriler: [ZamanAralik: [Mum]] = [:]   // ham (TL) mumlar, aralık başına cache
    @State private var usdKur: [(gun: Date, kur: Double)] = []
    @State private var cizilen: [Mum] = []                    // ekranda çizilen (TL veya USD) — bir kez hesaplanır
    @State private var yukleniyorGrafik = false
    @State private var neptunTahmin: Neptun.Tahmin?           // Neptün sonucu (arka planda hesaplanır)
    @State private var saturnSonuc: Saturn.Sonuc?             // Satürn (temel) — arka planda çekilir
    @State private var temelVeri: TemelVeri?                  // Mars faktörleri için ham temel veri
    @State private var etkinAgirliklar = Konsey.varsayilanAgirliklar  // Ay (öğrenilmiş) ile düzeltilebilir
    @State private var kalibrasyon: Kalibrasyon?              // Güneş — uzak kalibrasyon
    @State private var venusSonuc: VenusSonuc?                // Venüs (haber/LLM) — arka planda çekilir

    private var listede: Bool { model.listedeMi(satir.sembol) }

    private var secilenMum: Mum? {
        guard let i = secilenIndex, cizilen.indices.contains(i) else { return nil }
        return cizilen[i]
    }
    private var gosterilenFiyat: Double { secilenMum?.kapanis ?? cizilen.last?.kapanis ?? satir.fiyat }
    private var donemDegisim: Double {
        guard let ilk = cizilen.first?.kapanis, ilk > 0 else { return satir.gunlukDegisim }
        return (gosterilenFiyat - ilk) / ilk * 100
    }
    private var artida: Bool { donemDegisim >= 0 }
    private var seriRenk: Color { artida ? Tema.yesil : Tema.kirmizi }
    private var intradayAralik: Bool { [.gun1, .hafta1, .ay1, .ay3].contains(aralik) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                fiyatBlogu
                grafikBolumu
                nirengiSkoru
                motorlarBolumu
                istatistikBlogu
                Text("Yatırım tavsiyesi değildir. Veriler ~15 dk gecikmelidir.")
                    .font(.caption2).foregroundColor(Tema.gri)
            }
            .padding(20)
        }
        .background(Tema.arkaplan)
        .navigationTitle(satir.sembol)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { withAnimation { model.listeyiDegistir(satir.sembol) } } label: {
                    Image(systemName: listede ? "checkmark.circle.fill" : "plus")
                        .font(.system(size: 17, weight: .semibold)).foregroundColor(Tema.turuncu)
                }
            }
        }
        .task(id: aralik) { await seriYukle(); guncelleCizilen() }
        .task { if usdKur.isEmpty { usdKur = await DovizServisi.shared.usdtry(); if usd { guncelleCizilen() } } }
        .task {
            // Neptün'ü arka planda hesapla (ana akışı bloklamadan).
            if neptunTahmin == nil {
                let mumlar = satir.mumlar
                neptunTahmin = await Task.detached(priority: .userInitiated) {
                    Neptun().tahminEt(mumlar)
                }.value
            }
        }
        .task {
            // Satürn — endeks değilse temel veriyi çek (Yahoo quoteSummary).
            // BIST finansallarında (banka/sigorta/leasing) Satürn KAPALI: sanayi
            // şirketine göre ayarlı bantlar bu bilançolarda yanıltıcı skor üretir.
            // Temel veri yine de çekilir (Mars'ın değer faktörü F/K-PD/DD kullanır).
            if temelVeri == nil && !satir.endeksMi {
                if let v = await TemelVeriServisi.shared.cek(sembol: satir.sembol) {
                    temelVeri = v
                    if !BistEvren.finansalMi(satir.sembol) {
                        saturnSonuc = Saturn().analiz(v)
                    }
                }
            }
        }
        .task {
            // Venüs — endeks değilse haber/duygu (Anthropic anahtarı varsa).
            if venusSonuc == nil && !satir.endeksMi {
                venusSonuc = await VenusServisi.shared.analiz(sembol: satir.sembol, ad: satir.ad)
            }
        }
        .task {
            // Ay/Güneş — robotun ürettiği öğrenilmiş ağırlık + kalibrasyonu indir (URL varsa).
            await OgrenmeServisi.shared.yukle()
            etkinAgirliklar = await OgrenmeServisi.shared.etkinAgirliklar()
            kalibrasyon = await OgrenmeServisi.shared.mevcutKalibrasyon()
        }
        .onChange(of: usd) { _, _ in guncelleCizilen() }
    }

    // MARK: - Fiyat + USD/TRY

    private var fiyatBlogu: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(satir.ad).font(.subheadline).foregroundColor(Tema.metinIkincil)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(fiyatStr(gosterilenFiyat))
                        .font(.system(size: 42, weight: .bold)).foregroundColor(Tema.metin)
                    Text(yuzdeStr(donemDegisim))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(artida ? Tema.yesil : Tema.kirmizi)
                }
            }
            Spacer()
            usdTiki
        }
    }

    private var usdTiki: some View {
        Button { usd.toggle(); secilenIndex = nil } label: {
            HStack(spacing: 5) {
                Image(systemName: usd ? "checkmark.square.fill" : "square").font(.system(size: 12))
                Text("USD/TRY").font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(usd ? .white : Tema.metinIkincil)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(usd ? Tema.turuncu : Tema.yuzey))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Tema.kenar, lineWidth: usd ? 0 : 1))
        }
        .buttonStyle(.plain)
        .disabled(usdKur.isEmpty)
        .opacity(usdKur.isEmpty ? 0.5 : 1)
    }

    // MARK: - Grafik

    private var grafikBolumu: some View {
        VStack(spacing: 10) {
            Text(secilenMum.map { tarihStr($0.tarih, intraday: intradayAralik) } ?? " ")
                .font(.caption).foregroundColor(Tema.metinIkincil)
                .frame(maxWidth: .infinity, alignment: .center).frame(height: 16)

            ZStack {
                grafik.frame(height: 300)
                if yukleniyorGrafik && cizilen.isEmpty { ProgressView().tint(Tema.turuncu) }
                else if cizilen.isEmpty { Text("Grafik verisi yok").font(.subheadline).foregroundColor(Tema.gri) }
            }
            kontrolSatiri
        }
    }

    private var grafik: some View {
        Chart {
            if let ilk = cizilen.first?.kapanis {
                RuleMark(y: .value("Başlangıç", ilk))
                    .foregroundStyle(Tema.kenar).lineStyle(.init(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(cizilen.indices, id: \.self) { i in
                let m = cizilen[i]
                if mum {
                    RuleMark(x: .value("i", Double(i)), yStart: .value("Düşük", m.dusuk), yEnd: .value("Yüksek", m.yuksek))
                        .foregroundStyle(m.kapanis >= m.acilis ? Tema.yesil : Tema.kirmizi)
                        .lineStyle(.init(lineWidth: 1))
                    RectangleMark(x: .value("i", Double(i)), yStart: .value("Açılış", m.acilis), yEnd: .value("Kapanış", m.kapanis), width: .fixed(3))
                        .foregroundStyle(m.kapanis >= m.acilis ? Tema.yesil : Tema.kirmizi)
                } else {
                    LineMark(x: .value("i", Double(i)), y: .value("Fiyat", m.kapanis))
                        .interpolationMethod(.catmullRom).foregroundStyle(seriRenk)
                }
            }
            if let i = secilenIndex, cizilen.indices.contains(i) {
                RuleMark(x: .value("i", Double(i))).foregroundStyle(Tema.gri.opacity(0.5))
                PointMark(x: .value("i", Double(i)), y: .value("Fiyat", cizilen[i].kapanis)).foregroundStyle(Tema.turuncu)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yAralik)
        .chartXScale(domain: 0...Double(max(1, cizilen.count - 1)))
        .chartXSelection(value: Binding(
            get: { secilenIndex.map(Double.init) },
            set: { secilenIndex = $0.map { Int($0.rounded()) } }
        ))
    }

    private var yAralik: ClosedRange<Double> {
        let degerler = mum ? cizilen.flatMap { [$0.dusuk, $0.yuksek] } : cizilen.map(\.kapanis)
        guard let lo = degerler.min(), let hi = degerler.max(), hi > lo else { return 0...1 }
        let pay = (hi - lo) * 0.12
        return (lo - pay)...(hi + pay)
    }

    private var kontrolSatiri: some View {
        HStack(spacing: 5) {
            ForEach(ZamanAralik.allCases) { z in
                let secili = z == aralik
                Button { aralik = z; secilenIndex = nil } label: {
                    Text(z.rawValue)
                        .font(.system(size: 13, weight: secili ? .bold : .medium))
                        .foregroundColor(secili ? .white : Tema.metinIkincil)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(secili ? Tema.turuncu : Tema.yuzey))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 4)
            Button { mum.toggle() } label: {
                Image(systemName: mum ? "chart.xyaxis.line" : "chart.bar.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Tema.metinIkincil)
                    .frame(width: 32, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Tema.yuzey))
            }
        }
    }

    // MARK: - Veri

    private func seriYukle() async {
        guard seriler[aralik] == nil else { return }
        yukleniyorGrafik = true
        let (r, i, grup): (String, String, Int) = {
            switch aralik {
            case .gun1:   return ("1d", "5m", 1)
            case .hafta1: return ("5d", "30m", 1)
            case .ay1:    return ("1mo", "60m", 1)
            case .ay3:    return ("3mo", "60m", 4)
            case .yil1:   return ("1y", "1d", 1)
            case .yil5:   return ("5y", "1wk", 1)
            }
        }()
        if let s = try? await VeriMerkezi.cek(sembol: satir.sembol, aralik: r, interval: i) {
            seriler[aralik] = grup > 1 ? Self.grupla(s.mumlar, grup) : s.mumlar
        }
        yukleniyorGrafik = false
    }

    /// Çizilecek seriyi BİR KEZ hesapla (TL veya USD). Scrub sırasında tekrar hesaplanmaz.
    private func guncelleCizilen() {
        let ham = seriler[aralik] ?? []
        guard usd, !usdKur.isEmpty else { cizilen = ham; secilenIndex = nil; return }
        let gunler = usdKur.map(\.gun)
        cizilen = ham.map { m in
            let k = enYakinKur(m.tarih, gunler: gunler)
            guard k > 0 else { return m }
            return Mum(tarih: m.tarih, acilis: m.acilis / k, yuksek: m.yuksek / k,
                      dusuk: m.dusuk / k, kapanis: m.kapanis / k, hacim: m.hacim)
        }
        secilenIndex = nil
    }

    /// Verilen tarihe en yakın gün kuru (ikili arama; sadece toggle/yükleme anında çalışır).
    private func enYakinKur(_ tarih: Date, gunler: [Date]) -> Double {
        guard !gunler.isEmpty else { return 1 }
        if tarih <= gunler[0] { return usdKur[0].kur }
        if tarih >= gunler[gunler.count - 1] { return usdKur[gunler.count - 1].kur }
        var lo = 0, hi = gunler.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if gunler[mid] < tarih { lo = mid + 1 } else { hi = mid }
        }
        let yukari = lo, asagi = max(0, lo - 1)
        return abs(gunler[yukari].timeIntervalSince(tarih)) < abs(gunler[asagi].timeIntervalSince(tarih))
            ? usdKur[yukari].kur : usdKur[asagi].kur
    }

    private static func grupla(_ mumlar: [Mum], _ n: Int) -> [Mum] {
        stride(from: 0, to: mumlar.count, by: n).compactMap { i -> Mum? in
            let dilim = mumlar[i..<min(i + n, mumlar.count)]
            guard let ilk = dilim.first, let son = dilim.last else { return nil }
            return Mum(tarih: son.tarih, acilis: ilk.acilis,
                      yuksek: dilim.map(\.yuksek).max() ?? son.yuksek,
                      dusuk: dilim.map(\.dusuk).min() ?? son.dusuk,
                      kapanis: son.kapanis, hacim: dilim.map(\.hacim).reduce(0, +))
        }
    }

    // MARK: - Nirengi bileşik skoru (Konsey)

    /// Mars (faktör) — fiyat + (varsa) temel veri. Senkron hesaplanır.
    /// Finansallarda borç/özkaynak kalite bandına sokulmaz (bankada doğal olarak yüksek).
    private var marsSonuc: Mars.Sonuc? {
        guard !satir.endeksMi else { return nil }
        var t = temelVeri
        if BistEvren.finansalMi(satir.sembol) { t?.borcOzkaynak = nil }
        return Mars().degerlendir(satir.mumlar, temel: t)
    }

    /// Plüton (geri dönüş) — yalnızca fiyat. Senkron hesaplanır.
    private var plutonSonuc: Pluton.Sonuc? {
        guard !satir.endeksMi else { return nil }
        return Pluton().degerlendir(satir.mumlar)
    }

    /// Mevcut motor sonuçlarından Konsey katkı listesi.
    private var katkilar: [Katki] {
        var arr: [Katki] = [
            Katki(motor: "Merkür", skor: satir.sonuc.skor, guven: 0.8, gerekce: satir.sonuc.verdict)
        ]
        if let t = neptunTahmin {
            arr.append(Katki(motor: "Neptün", skor: max(0, min(100, 50 + t.degisimYuzde * 5)),
                             guven: t.guven / 100, gerekce: t.oneri.rawValue))
        }
        if !satir.endeksMi, let u = model.uranusSonucu(satir) {
            arr.append(Katki(motor: "Uranüs", skor: u.skor, guven: 0.7, gerekce: u.aciklama))
        }
        if let s = saturnSonuc {
            arr.append(Katki(motor: "Satürn", skor: s.skor, guven: s.guvenilir ? 0.8 : 0.3, gerekce: s.aciklama))
        }
        if let j = model.jupiterRejim {
            arr.append(Katki(motor: "Jüpiter", skor: j.skor, guven: 0.6, gerekce: j.rejim.rawValue))
        }
        if let v = venusSonuc {
            arr.append(Katki(motor: "Venüs", skor: v.skor, guven: v.guven, gerekce: v.gerekce))
        }
        if let mr = marsSonuc {
            arr.append(Katki(motor: "Mars", skor: mr.skor, guven: mr.guvenilir ? 0.7 : 0.45, gerekce: mr.aciklama))
        }
        if let p = plutonSonuc {
            arr.append(Katki(motor: "Plüton", skor: p.skor, guven: min(0.75, 0.4 + p.rKare * 0.5), gerekce: p.aciklama))
        }
        return arr
    }

    private var nirengiSkoru: some View {
        // Ay: öğrenilmiş ağırlıklarla harmanla. Güneş: skoru geçmiş isabete göre kalibre et.
        let b = Konsey.harmanla(katkilar, agirliklar: etkinAgirliklar)
        let skor = kalibrasyon.map { Gunes.uygula(b.skor, $0) } ?? b.skor
        let karar = Karar.skordan(skor)
        return HStack(spacing: 16) {
            Text("\(Int(skor.rounded()))")
                .font(.system(size: 34, weight: .heavy)).foregroundColor(.white)
                .frame(width: 76, height: 76)
                .background(Circle().fill(Tema.skorRengi(skor)))
            VStack(alignment: .leading, spacing: 4) {
                Text("Nirengi Skoru").font(.caption).foregroundColor(.white.opacity(0.7))
                Text(karar.rawValue)
                    .font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                Text("\(katkilar.count) motordan")
                    .font(.caption).foregroundColor(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Tema.lacivertAcik, Tema.lacivert],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Motorlar listesi

    /// Gezegen motorları (Merkür aktif; diğerleri eklendikçe dolacak).
    private let motorTanim: [(ad: String, rol: String)] = [
        ("Merkür", "Teknik analiz"),
        ("Neptün", "Fiyat tahmini"),
        ("Jüpiter", "Makro rejim"),
        ("Satürn", "Temel & kalite"),
        ("Venüs", "Haber & duygu"),
        ("Uranüs", "Sektör rotasyonu"),
        ("Ay", "Ağırlık öğrenme"),
        ("Mars", "Faktör"),
        ("Güneş", "Meta kalibrasyon"),
        ("Plüton", "Geri dönüş"),
    ]

    private var motorlarBolumu: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Tema.turuncu).frame(width: 4, height: 18)
                Text("Motorlar").font(.system(size: 20, weight: .bold)).foregroundColor(Tema.metin)
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(Array(motorTanim.enumerated()), id: \.offset) { idx, m in
                    motorSatiri(ad: m.ad, rol: m.rol, durum: motorDurumu(m.ad))
                    if idx < motorTanim.count - 1 {
                        Rectangle().fill(Tema.kenar).frame(height: 0.5).padding(.leading, 16)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Tema.kenar, lineWidth: 1))
        }
    }

    /// Motor satırının durumu: skor + kısa etiket, ya da nil (yakında/veri yok).
    private func motorDurumu(_ ad: String) -> (skor: Double, etiket: String)? {
        switch ad {
        case "Merkür":
            return (satir.sonuc.skor, satir.sonuc.verdict)
        case "Neptün":
            guard let t = neptunTahmin else { return nil }
            let skor = max(0, min(100, 50 + t.degisimYuzde * 5))
            return (skor, String(format: "%@ · %%%.1f tahmin", t.oneri.rawValue, t.degisimYuzde))
        case "Uranüs":
            guard !satir.endeksMi, let u = model.uranusSonucu(satir) else { return nil }
            return (u.skor, u.aciklama)
        case "Satürn":
            guard let s = saturnSonuc else { return nil }
            return (s.skor, s.aciklama)
        case "Jüpiter":
            guard let j = model.jupiterRejim else { return nil }
            return (j.skor, j.rejim.rawValue)
        case "Venüs":
            guard let v = venusSonuc else { return nil }
            return (v.skor, v.gerekce)
        case "Mars":
            guard let mr = marsSonuc else { return nil }
            return (mr.skor, mr.aciklama)
        case "Plüton":
            guard let p = plutonSonuc else { return nil }
            return (p.skor, p.aciklama)
        default:
            return nil
        }
    }

    private func motorSatiri(ad: String, rol: String, durum: (skor: Double, etiket: String)?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ad).font(.system(size: 16, weight: .semibold))
                    .foregroundColor(durum != nil ? Tema.metin : Tema.gri)
                Text(rol).font(.caption).foregroundColor(Tema.metinIkincil)
            }
            Spacer()
            if let d = durum {
                Text(d.etiket)
                    .font(.caption.weight(.semibold)).foregroundColor(Tema.skorRengi(d.skor))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(Int(d.skor.rounded()))")
                    .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .frame(width: 42, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Tema.skorRengi(d.skor)))
            } else {
                Text(motorNotu(ad))
                    .font(.caption).foregroundColor(Tema.gri)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Tema.arkaplan))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
    }

    /// Skor üretmeyen motor satırının açıklaması (dürüst etiket: neden yok?).
    private func motorNotu(_ ad: String) -> String {
        if ad == "Satürn", !satir.endeksMi, BistEvren.finansalMi(satir.sembol) {
            return "Kapalı · banka/sigorta"   // sanayi bantları finansal bilançoda yanıltıcı
        }
        if ad == "Ay" || ad == "Güneş" { return "Öğreniyor" }   // cihazda sicil biriktiriyor
        return "—"
    }

    // MARK: - İstatistikler

    private var istatistikBlogu: some View {
        let son252 = satir.mumlar.suffix(252)
        let y52 = son252.map(\.yuksek).max() ?? satir.fiyat
        let d52 = son252.map(\.dusuk).min() ?? satir.fiyat
        let hacim = satir.mumlar.last?.hacim ?? 0
        return VStack(spacing: 0) {
            istSatir("İşlem hacmi", NirengiBicim.hacim(hacim))
            ayrac
            istSatir("52 hafta en yüksek", "₺" + (NirengiBicim.fiyat.string(from: NSNumber(value: y52)) ?? ""))
            ayrac
            istSatir("52 hafta en düşük", "₺" + (NirengiBicim.fiyat.string(from: NSNumber(value: d52)) ?? ""))
        }
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Tema.yuzey))
    }

    private var ayrac: some View { Rectangle().fill(Tema.kenar).frame(height: 0.5) }

    private func istSatir(_ ad: String, _ deger: String) -> some View {
        HStack {
            Text(ad).font(.subheadline).foregroundColor(Tema.metinIkincil)
            Spacer()
            Text(deger).font(.subheadline.weight(.semibold)).foregroundColor(Tema.metin)
        }
        .padding(.vertical, 14)
    }

    // MARK: - Biçimleme

    private func fiyatStr(_ v: Double) -> String {
        let n = NirengiBicim.fiyat.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
        if usd { return "$" + n }
        return satir.endeksMi ? n : "₺" + n
    }
    private func yuzdeStr(_ v: Double) -> String {
        let n = String(format: "%.2f", abs(v)).replacingOccurrences(of: ".", with: ",")
        return (v < 0 ? "-%" : "%") + n
    }
    private func tarihStr(_ d: Date, intraday: Bool) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = intraday ? "d MMM HH:mm" : "d MMM yyyy"
        return f.string(from: d)
    }
}

/// Ortak sayı biçimleme yardımcıları.
enum NirengiBicim {
    static let fiyat: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "tr_TR")
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2; return f
    }()
    static func hacim(_ v: Double) -> String {
        switch v {
        case 1_000_000_000...: return String(format: "%.1f Mr", v / 1_000_000_000).replacingOccurrences(of: ".", with: ",")
        case 1_000_000...:     return String(format: "%.1f Mn", v / 1_000_000).replacingOccurrences(of: ".", with: ",")
        case 1_000...:         return String(format: "%.0f B", v / 1_000)
        default:               return String(format: "%.0f", v)
        }
    }
}
