import SwiftUI

/// Menü — kısayollar / ekstra sayfalar (şimdilik placeholder).
struct MenuView: View {
    private let kisayollar: [(ikon: String, ad: String)] = [
        ("chart.pie", "Portföyüm"),
        ("checkmark.seal", "Asistan karnesi"),
        ("star", "Takip listem"),
        ("bell.badge", "Uyarılarım"),
        ("doc.text.magnifyingglass", "Analiz arşivi"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(kisayollar.indices, id: \.self) { i in
                        HStack(spacing: 14) {
                            Image(systemName: kisayollar[i].ikon)
                                .font(.system(size: 18)).foregroundColor(Tema.turuncu)
                                .frame(width: 28)
                            Text(kisayollar[i].ad).foregroundColor(Tema.metin)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(Tema.gri)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.yuzey))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Tema.kenar, lineWidth: 1))
                    }
                    Text("Yakında daha fazlası")
                        .font(.caption2).foregroundColor(Tema.gri).padding(.top, 12)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
            }
            .background(Tema.arkaplan)
            .markaToolbar()
        }
    }
}
