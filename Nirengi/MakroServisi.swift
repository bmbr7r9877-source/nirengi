import Foundation
import Cekirdek

/// Jüpiter için makro proxy serilerini Yahoo'dan çeker (key gerektirmez).
/// Piyasa geneli olduğu için bir kez çekilip cache'lenir.
actor MakroServisi {
    static let shared = MakroServisi()
    private var sonuc: Jupiter.Sonuc?

    func rejim() async -> Jupiter.Sonuc? {
        if let s = sonuc { return s }
        // Sembol → MakroGirdi alanı. ^ = %5E (URL).
        async let vix   = seri("%5EVIX")
        async let spy   = seri("%5EGSPC")
        async let dxy   = seri("DX-Y.NYB")
        async let faiz  = seri("%5ETNX")
        async let altin = seri("GC=F")
        async let usdtry = seri("USDTRY=X")

        var g = MakroGirdi()
        g.vix = await vix; g.spy = await spy; g.dxy = await dxy
        g.faiz10y = await faiz; g.altin = await altin; g.usdtry = await usdtry

        let r = Jupiter().analiz(g)
        sonuc = r
        return r
    }

    private func seri(_ sembol: String) async -> [Double] {
        guard let s = try? await YahooBistServisi.cek(sembol: sembol, aralik: "6mo", interval: "1d", borsaIstanbul: false) else { return [] }
        return s.mumlar.map(\.kapanis)
    }
}
