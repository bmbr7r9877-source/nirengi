import SwiftUI

/// Ayarlar — sade placeholder (içerik sonra dolacak).
struct AyarlarView: View {
    @State private var anthropicKey = UserDefaults.standard.string(forKey: "anthropic_key") ?? ""
    @State private var ogrenmeURL = UserDefaults.standard.string(forKey: "ogrenme_base_url") ?? ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    grup("Venüs · Haber AI") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "key").foregroundColor(Tema.turuncu).frame(width: 24)
                                SecureField("Anthropic API anahtarı", text: $anthropicKey)
                                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                                    .onChange(of: anthropicKey) { _, yeni in
                                        UserDefaults.standard.set(yeni.trimmingCharacters(in: .whitespaces), forKey: "anthropic_key")
                                    }
                            }
                            Text("Haber motoru (Venüs) için gerekli. console.anthropic.com'dan alınır.")
                                .font(.caption2).foregroundColor(Tema.gri)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 14)
                    }
                    grup("Ay · Güneş · Öğrenme") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "brain").foregroundColor(Tema.turuncu).frame(width: 24)
                                TextField("github raw kök URL'si", text: $ogrenmeURL)
                                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                                    .onChange(of: ogrenmeURL) { _, yeni in
                                        UserDefaults.standard.set(yeni.trimmingCharacters(in: .whitespaces), forKey: "ogrenme_base_url")
                                    }
                            }
                            Text("Öğrenme robotunun (GitHub Actions) ürettiği ağırlık/kalibrasyonu indirir. Örn: https://raw.githubusercontent.com/kullanici/nirengi/main")
                                .font(.caption2).foregroundColor(Tema.gri)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 14)
                    }
                    grup("Genel") {
                        satir(ikon: "bell", "Bildirimler")
                        satir(ikon: "paintbrush", "Görünüm")
                    }
                    grup("Hakkında") {
                        satir(ikon: "info.circle", "Nirengi hakkında")
                        satir(ikon: "doc.text", "Yatırım uyarısı")
                        satir(ikon: "envelope", "Geri bildirim")
                    }
                    Text("Nirengi v1.0 · Yatırım tavsiyesi değildir")
                        .font(.caption2).foregroundColor(Tema.gri)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Tema.arkaplan)
            .markaToolbar("Ayarlar")
        }
    }

    private func grup<Content: View>(_ baslik: String, @ViewBuilder _ icerik: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(baslik.uppercased())
                .font(.caption.weight(.semibold)).foregroundColor(Tema.metinIkincil)
                .padding(.leading, 6)
            VStack(spacing: 0) { icerik() }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Tema.kenar, lineWidth: 1))
        }
    }

    private func satir(ikon: String, _ baslik: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ikon).foregroundColor(Tema.turuncu).frame(width: 24)
            Text(baslik).foregroundColor(Tema.metin)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(Tema.gri)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}
