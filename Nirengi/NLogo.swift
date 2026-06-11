import SwiftUI

/// Nirengi "N" logosu — app ikonundaki stilize (ayrık köşegen) N.
/// Çerçevesini doldurur; istediğin renkle .fill() edilir.
struct NSekli: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let bw = 0.224 * w          // bar kalınlığı
        let g  = 0.15 * h           // köşegen uç boşluğu (ayrık görünüm)
        var p = Path()
        // sol dikey bar
        p.addRect(CGRect(x: 0, y: 0, width: bw, height: h))
        // sağ dikey bar
        p.addRect(CGRect(x: w - bw, y: 0, width: bw, height: h))
        // köşegen (sol-üst → sağ-alt), uçlarda boşluklu
        p.move(to: CGPoint(x: bw, y: g))
        p.addLine(to: CGPoint(x: 2 * bw, y: g))
        p.addLine(to: CGPoint(x: w - bw, y: h - g))
        p.addLine(to: CGPoint(x: w - 2 * bw, y: h - g))
        p.closeSubpath()
        return p
    }
}

/// Marka üst barı — BEYAZ şerit, solda DÜZ turuncu N logosu (buton değil, yazı yok).
struct MarkaToolbar: ViewModifier {
    var baslik: String
    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    NSekli().fill(Tema.turuncu).frame(width: 22, height: 23)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Tema.arkaplan.ignoresSafeArea(edges: .top))
            }
    }
}

extension View {
    func markaToolbar(_ baslik: String = "Nirengi") -> some View {
        modifier(MarkaToolbar(baslik: baslik))
    }
}

/// Gradyan turuncu daire/kare zemin üstünde N (logo bloğu olarak kullanılabilir).
struct NirengiLogo: View {
    var boyut: CGFloat = 80
    var beyaz: Bool = true
    var body: some View {
        NSekli()
            .fill(beyaz ? Color.white : Tema.metin)
            .frame(width: boyut * 0.78, height: boyut * 0.82)
    }
}
