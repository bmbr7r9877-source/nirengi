import SwiftUI
import Cekirdek

/// Zaman aralığı — yüzde değişim hangi döneme göre gösterilsin.
enum ZamanAralik: String, CaseIterable, Identifiable {
    case gun1 = "1G", hafta1 = "1H", ay1 = "1A", ay3 = "3A", yil1 = "1Y", yil5 = "5Y"
    var id: String { rawValue }
    var gun: Int {
        switch self {
        case .gun1: return 1
        case .hafta1: return 5
        case .ay1: return 22
        case .ay3: return 66
        case .yil1: return 252
        case .yil5: return 1260
        }
    }
}

/// "Son" kolonunda ne gösterilsin.
enum SonKolon: String, CaseIterable, Identifiable {
    case fiyat = "Son", hacim = "Hacim"
    var id: String { rawValue }
}

/// Liste sıralaması.
enum Siralama: String, CaseIterable, Identifiable {
    case sembol = "Ada göre (A-Z)"
    case skor = "Skora göre"
    case fiyat = "Fiyata göre"
    case degisim = "Değişime göre"
    var id: String { rawValue }
}

/// Ana sayfa — kolonlu liste: sembol+anlık saat · Merkür skoru · fiyat · %fark.
struct AnaSayfaView: View {
    @EnvironmentObject var model: PiyasaModel
    @State private var aralik: ZamanAralik = .gun1
    @State private var liste = 0   // 0: BIST 100, 1: BIST 30, 2: Endeksler, 3: Listem
    @State private var sonKolon: SonKolon = .fiyat
    @State private var siralama: Siralama = .sembol

    private var aktifSemboller: Set<String> {
        switch liste {
        case 1: return Set(model.bist30)
        case 2: return Set(model.endeksler)
        case 3: return model.listem
        default: return Set(model.bist100)
        }
    }

    private var siralilar: [HisseSatiri] {
        let set = aktifSemboller
        let liste = model.hisseler.filter { set.contains($0.sembol) }
        switch siralama {
        case .sembol:  return liste.sorted { $0.sembol < $1.sembol }
        case .skor:    return liste.sorted { $0.sonuc.skor > $1.sonuc.skor }
        case .fiyat:   return liste.sorted { $0.fiyat > $1.fiyat }
        case .degisim: return liste.sorted { $0.degisim(gunOnce: aralik.gun) > $1.degisim(gunOnce: aralik.gun) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ustBar
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 12)

                    basliklar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)

                    if liste == 3 && siralilar.isEmpty && !model.hisseler.isEmpty {
                        bosListe
                    } else {
                        ForEach(Array(siralilar.enumerated()), id: \.element.id) { idx, satir in
                            NavigationLink {
                                DetayView(satir: satir)
                            } label: {
                                satirGorunum(satir)
                            }
                            .buttonStyle(.plain)

                            if idx < siralilar.count - 1 {
                                Rectangle().fill(Tema.kenar).frame(height: 0.5)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .overlay {
                if model.yukleniyor && model.hisseler.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().tint(Tema.turuncu)
                        Text("BIST verileri çekiliyor…")
                            .font(.subheadline).foregroundColor(Tema.metinIkincil)
                    }
                } else if let hata = model.hata, model.hisseler.isEmpty {
                    VStack(spacing: 8) {
                        Text(hata).font(.subheadline).foregroundColor(Tema.metinIkincil)
                        Button("Tekrar dene") { model.yenile() }
                            .foregroundColor(Tema.turuncu)
                    }
                }
            }
            .background(Tema.arkaplan)
            .markaToolbar()
        }
    }

    private let listeAdlari = ["BIST 100", "BIST 30", "BIST Endeksler", "Listem"]

    // MARK: - Üst bar: sadece zaman aralıkları (sağa yaslı)

    private var ustBar: some View {
        HStack(spacing: 5) {
            // Sıralama butonu (zaman aralıklarıyla aynı boyut)
            Menu {
                ForEach(Siralama.allCases) { s in
                    Button {
                        siralama = s
                    } label: {
                        if siralama == s { Label(s.rawValue, systemImage: "checkmark") }
                        else { Text(s.rawValue) }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Tema.metinIkincil)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Tema.yuzey))
            }

            Spacer()
            ForEach(ZamanAralik.allCases) { z in
                let secili = z == aralik
                Button { aralik = z } label: {
                    Text(z.rawValue)
                        .font(.system(size: 11, weight: secili ? .bold : .medium))
                        .foregroundColor(secili ? .white : Tema.metinIkincil)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(secili ? Tema.turuncu : Tema.yuzey)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Boş liste

    private var bosListe: some View {
        VStack(spacing: 10) {
            Image(systemName: "star")
                .font(.system(size: 34)).foregroundColor(Tema.gri)
            Text("Listen boş")
                .font(.headline).foregroundColor(Tema.metin)
            Text("Bir hisseye girip sağ üstteki + ile listene ekle.")
                .font(.subheadline).foregroundColor(Tema.metinIkincil)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60).padding(.horizontal, 30)
    }

    // MARK: - Kolon başlıkları

    private var basliklar: some View {
        HStack(spacing: 10) {
            // "Kıymet" yerine liste açılır menüsü
            Menu {
                ForEach(listeAdlari.indices, id: \.self) { i in
                    Button {
                        liste = i
                    } label: {
                        if liste == i { Label(listeAdlari[i], systemImage: "checkmark") }
                        else { Text(listeAdlari[i]) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(listeAdlari[liste])
                        .font(.system(size: 14, weight: .bold)).foregroundColor(Tema.metin)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Tema.turuncu)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Skor").frame(width: 46)
            // "Son" yerine seçmeli kolon (Fiyat / İşlem Hacmi)
            Menu {
                ForEach(SonKolon.allCases) { k in
                    Button {
                        sonKolon = k
                    } label: {
                        if sonKolon == k { Label(k.rawValue, systemImage: "checkmark") }
                        else { Text(k.rawValue) }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(sonKolon.rawValue)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundColor(Tema.turuncu)
                }
            }
            .frame(width: 96, alignment: .trailing)
            Text("%Fark").frame(width: 74, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(Tema.metinIkincil)
    }

    // MARK: - Satır

    private func satirGorunum(_ satir: HisseSatiri) -> some View {
        let d = satir.degisim(gunOnce: aralik.gun)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(satir.sembol)
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(Tema.metin)
                Text(saatStr(satir.zaman))
                    .font(.system(size: 12)).foregroundColor(Tema.metinIkincil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            skorRozet(satir.sonuc.skor)
                .frame(width: 46)

            Text(sonKolonDeger(satir))
                .font(.system(size: 16, weight: .semibold)).foregroundColor(Tema.metin)
                .frame(width: 96, alignment: .trailing)

            Text(yuzdeStr(d))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(d > 0 ? Tema.yesil : (d < 0 ? Tema.kirmizi : Tema.gri))
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func skorRozet(_ skor: Double) -> some View {
        Text("\(Int(skor.rounded()))")
            .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            .frame(width: 42, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Tema.skorRengi(skor)))
    }

    // MARK: - Biçimleme

    private static let fiyatFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "tr_TR")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
    private static let saatFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func sonKolonDeger(_ satir: HisseSatiri) -> String {
        switch sonKolon {
        case .fiyat: return fiyatStr(satir.fiyat, paraBirimi: !satir.endeksMi)
        case .hacim: return NirengiBicim.hacim(satir.mumlar.last?.hacim ?? 0)
        }
    }

    private func fiyatStr(_ v: Double, paraBirimi: Bool = true) -> String {
        let n = Self.fiyatFmt.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
        return paraBirimi ? "₺" + n : n
    }
    private func saatStr(_ d: Date) -> String { Self.saatFmt.string(from: d) }
    private func yuzdeStr(_ v: Double) -> String {
        let n = String(format: "%.2f", abs(v)).replacingOccurrences(of: ".", with: ",")
        if v < 0 { return "-%\(n)" }
        return "%\(n)"
    }
}
