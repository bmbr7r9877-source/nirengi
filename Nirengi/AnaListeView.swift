import SwiftUI
import Cekirdek

/// Ana liste — hisseler Merkür skoruna göre sıralı.
struct AnaListeView: View {
    @EnvironmentObject var model: PiyasaModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    baslik
                    ForEach(model.hisseler) { satir in
                        NavigationLink {
                            DetayView(satir: satir)
                        } label: {
                            HisseKart(satir: satir)
                        }
                        .buttonStyle(.plain)
                    }
                    uyari
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Tema.arkaplan)
            .markaToolbar()
        }
    }

    private var baslik: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Tema.turuncu).frame(width: 4, height: 18)
            Text("Sinyaller")
                .font(.headline).foregroundColor(Tema.metin)
            Spacer()
            Text("Merkür skoruna göre")
                .font(.caption.weight(.medium)).foregroundColor(Tema.turuncu)
        }
        .padding(.bottom, 2)
    }

    private var uyari: some View {
        Text("Yatırım tavsiyesi değildir. Veriler örnektir (gerçek BIST verisi yakında).")
            .font(.caption2)
            .foregroundColor(Tema.gri)
            .multilineTextAlignment(.center)
            .padding(.vertical, 18)
    }
}

/// Tek hisse kartı.
struct HisseKart: View {
    let satir: HisseSatiri

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(satir.sembol)
                    .font(.system(size: 17, weight: .bold)).foregroundColor(Tema.metin)
                Text(satir.ad)
                    .font(.system(size: 12)).foregroundColor(Tema.metinIkincil)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.2f", satir.fiyat))
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(Tema.metin)
                Text(String(format: "%+.2f%%", satir.gunlukDegisim))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(satir.gunlukDegisim >= 0 ? Tema.yesil : Tema.kirmizi)
            }
            SkorRozeti(skor: satir.sonuc.skor, karar: satir.sonuc.verdict)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Tema.kenar, lineWidth: 1)
        )
    }
}

/// Skor rozeti — renkli daire + kısa karar.
struct SkorRozeti: View {
    let skor: Double
    let karar: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(skor.rounded()))")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Tema.skorRengi(skor)))
        }
        .frame(width: 54)
    }
}
