import Foundation
import Cekirdek

/// Cihaz içi öğrenme — sicil (tahmin günlüğü) TELEFONDA tutulur; Ay/Güneş burada öğrenir.
/// Sunucu/robot gerektirmez: uygulama her açılıp listeyi çektiğinde günde bir kez
/// tahminler kaydedilir, ufku (14 gün) dolanlar hissenin kendi mum geçmişinden
/// değerlendirilir, ağırlık + kalibrasyon yeniden hesaplanır. Veri Documents'ta JSON.
actor OgrenmeDeposu {
    static let shared = OgrenmeDeposu()

    private let ufukGun = 14

    private var sicil: [SicilKaydi] = []
    private var agirliklar: OgrenilmisAgirliklar?
    private var kalibrasyon: Kalibrasyon?
    private var yuklendi = false

    // MARK: - Dosyalar

    private var klasor: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var sicilURL: URL { klasor.appendingPathComponent("nirengi_sicil.json") }
    private var agirlikURL: URL { klasor.appendingPathComponent("nirengi_agirliklar.json") }
    private var kalibrasyonURL: URL { klasor.appendingPathComponent("nirengi_kalibrasyon.json") }

    private let kodlayici: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let cozucu: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func yukle() {
        guard !yuklendi else { return }
        yuklendi = true
        if let v = try? Data(contentsOf: sicilURL) {
            sicil = (try? cozucu.decode([SicilKaydi].self, from: v)) ?? []
        }
        if let v = try? Data(contentsOf: agirlikURL) {
            agirliklar = try? cozucu.decode(OgrenilmisAgirliklar.self, from: v)
        }
        if let v = try? Data(contentsOf: kalibrasyonURL) {
            kalibrasyon = try? cozucu.decode(Kalibrasyon.self, from: v)
        }
    }

    // MARK: - Günlük döngü

    /// PiyasaModel'in aktardığı hisse girdisi (aktör sınırından geçecek sade paket).
    struct HisseGirdisi: Sendable {
        let sembol: String
        let mumlar: [Mum]
        let merkur: Katki?
    }

    /// Liste yüklendikten sonra çağrılır: değerlendir → bugünü kaydet → öğren → diske yaz.
    /// Aynı gün ikinci çağrı yeni kayıt eklemez (idempotent).
    func gunlukDongu(hisseler: [HisseGirdisi], sektorMumlari: [String: [Mum]], jupiter: Katki?) {
        yukle()
        let takvim = Calendar.current
        let bugun = takvim.startOfDay(for: Date())

        // 1) Ufku dolan tahminleri değerlendir — sonraki fiyat hissenin kendi
        //    günlük mum geçmişinde zaten var, ek ağ isteği gerekmez.
        let mumHarita = Dictionary(uniqueKeysWithValues: hisseler.map { ($0.sembol, $0.mumlar) })
        for i in sicil.indices where !sicil[i].olgun {
            guard let hedef = takvim.date(byAdding: .day, value: ufukGun, to: sicil[i].tarih),
                  hedef <= Date(),
                  let mumlar = mumHarita[sicil[i].sembol],
                  let sonra = mumlar.first(where: { $0.tarih >= hedef }),
                  sicil[i].fiyat > 0
            else { continue }
            sicil[i].degerlendirmeTarihi = sonra.tarih
            sicil[i].fiyatSonra = sonra.kapanis
            sicil[i].getiriYuzde = (sonra.kapanis - sicil[i].fiyat) / sicil[i].fiyat * 100
        }

        // 2) Bugünün tahminlerini ekle (sembol başına günde bir).
        let bugunkuler = Set(sicil.filter { takvim.isDate($0.tarih, inSameDayAs: bugun) }.map(\.sembol))
        let xu100 = sektorMumlari["XU100"]
        for h in hisseler where !bugunkuler.contains(h.sembol) {
            guard let sonFiyat = h.mumlar.last?.kapanis, sonFiyat > 0 else { continue }
            var katkilar: [Katki] = []
            if let m = h.merkur { katkilar.append(m) }
            if let n = Neptun().degerlendir(h.mumlar) { katkilar.append(n) }
            if let mr = Mars().katki(h.mumlar) { katkilar.append(mr) }
            if let p = Pluton().katki(h.mumlar) { katkilar.append(p) }
            if let kod = BistEvren.sektorHaritasi[h.sembol],
               let sektor = sektorMumlari[kod], let bench = xu100,
               let u = Uranus().katki(hisse: h.mumlar, sektor: sektor, benchmark: bench) {
                katkilar.append(u)
            }
            if let j = jupiter { katkilar.append(j) }
            guard !katkilar.isEmpty else { continue }

            let bilesik = Konsey.harmanla(katkilar, agirliklar: Konsey.varsayilanAgirliklar)
            let oylar = Dictionary(uniqueKeysWithValues: katkilar.map {
                ($0.motor, MotorOyu(skor: $0.skor, guven: $0.guven))
            })
            sicil.append(SicilKaydi(tarih: bugun, sembol: h.sembol, fiyat: sonFiyat,
                                    nirengiSkor: bilesik.skor, karar: bilesik.karar.rawValue,
                                    motorlar: oylar))
        }

        // 3) Ay + Güneş öğrensin, sonuçlar diske.
        agirliklar = Ay().ogren(sicil)
        kalibrasyon = Gunes().kalibreEt(sicil)
        try? kodlayici.encode(sicil).write(to: sicilURL)
        if let a = agirliklar { try? kodlayici.encode(a).write(to: agirlikURL) }
        if let k = kalibrasyon { try? kodlayici.encode(k).write(to: kalibrasyonURL) }
    }

    // MARK: - Okuma

    func mevcutAgirliklar() -> OgrenilmisAgirliklar? { yukle(); return agirliklar }
    func mevcutKalibrasyon() -> Kalibrasyon? { yukle(); return kalibrasyon }

    /// Ayarlar ekranı için durum: toplam kayıt + sonucu belli olan kayıt sayısı.
    func durum() -> (kayit: Int, olgun: Int) {
        yukle()
        return (sicil.count, sicil.filter(\.olgun).count)
    }
}
