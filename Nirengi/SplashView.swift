import SwiftUI

/// Açılış ekranı — turuncu gradyan zemin + ortada küçük N. Kısa süre sonra
/// uygulamayı açar (Midas/Argus tarzı sakin giriş).
struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Tema.lacivertAcik, Tema.lacivert],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // Sabit, vektörel logo — animasyon/gölge yok.
            NSekli()
                .fill(Tema.turuncu)
                .frame(width: 70, height: 74)
        }
    }
}

/// Kök görünüm — önce splash, sonra ana uygulama.
struct RootView: View {
    @State private var hazir = false

    var body: some View {
        ZStack {
            MainTabView()

            if !hazir {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_300_000_000)   // ~1.3 sn
            withAnimation(.easeInOut(duration: 0.45)) { hazir = true }
        }
    }
}
