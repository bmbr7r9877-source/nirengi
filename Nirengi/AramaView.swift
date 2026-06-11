import SwiftUI
import Cekirdek

/// Arama — sembol/şirket adına göre filtreler.
struct AramaView: View {
    @EnvironmentObject var model: PiyasaModel
    @State private var sorgu = ""

    private var sonuclar: [HisseSatiri] {
        guard !sorgu.isEmpty else { return model.hisseler }
        let q = sorgu.localizedLowercase
        return model.hisseler.filter {
            $0.sembol.localizedLowercase.contains(q) || $0.ad.localizedLowercase.contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    aramaKutusu
                    if sonuclar.isEmpty {
                        Text("Sonuç yok")
                            .font(.subheadline).foregroundColor(Tema.gri)
                            .padding(.top, 40)
                    } else {
                        ForEach(sonuclar) { satir in
                            NavigationLink {
                                DetayView(satir: satir)
                            } label: { HisseKart(satir: satir) }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Tema.arkaplan)
            .markaToolbar()
        }
    }

    private var aramaKutusu: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(Tema.gri)
            TextField("Hisse ara (örn. THYAO)", text: $sorgu)
                .foregroundColor(Tema.metin)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            if !sorgu.isEmpty {
                Button { sorgu = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Tema.gri)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.yuzey))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Tema.kenar, lineWidth: 1))
        .padding(.bottom, 4)
    }
}
