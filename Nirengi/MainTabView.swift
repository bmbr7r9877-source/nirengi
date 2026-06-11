import SwiftUI

/// Ana sekme yapısı — alta yapışık (dock'lu) özel şerit tab bar.
struct MainTabView: View {
    @StateObject private var model = PiyasaModel()
    @State private var secili = 2   // açılış: Ana Sayfa (ortadaki)

    var body: some View {
        Group {
            switch secili {
            case 0: MenuView()
            case 1: AnaListeView()   // Keşfet
            case 2: AnaSayfaView()   // Ana Sayfa
            case 3: AramaView()      // Arama
            default: AyarlarView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NirengiTabBar(secili: $secili)
        }
        .environmentObject(model)
        .onAppear { model.yukle() }
    }
}

/// Alta yapışık dolu şerit tab bar (Argus tarzı — havada durmaz).
struct NirengiTabBar: View {
    @Binding var secili: Int

    private let sekmeler: [(ad: String, ikon: String)] = [
        ("Menü", "line.3.horizontal"),
        ("Keşfet", "safari"),
        ("Ana Sayfa", "house.fill"),
        ("Arama", "magnifyingglass"),
        ("Ayarlar", "gearshape.fill"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(sekmeler.indices, id: \.self) { i in
                Button {
                    secili = i
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: sekmeler[i].ikon)
                            .font(.system(size: 20, weight: .medium))
                        Text(sekmeler[i].ad)
                            .font(.system(size: 10, weight: secili == i ? .semibold : .regular))
                    }
                    .foregroundColor(secili == i ? Tema.turuncu : Tema.gri)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(
            Tema.arkaplan
                .overlay(
                    Rectangle().fill(Tema.kenar).frame(height: 0.5),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
