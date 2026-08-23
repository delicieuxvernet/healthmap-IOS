import SwiftUI

// MARK: - Carrousel de courbes (blocs Macros / Micros / Symptômes)
//
// Un bloc = une carte crème avec un en-tête (icône + titre + flèches ‹ ›),
// le nom de la courbe courante + des pastilles de position, puis les pages
// paginées (swipe latéral + flèches). Chaque page rend sa propre courbe + son
// insight honnête. Générique sur le type de page → un bloc par famille (les
// pages d'un même bloc partagent le même type de vue).

struct SuiviCarouselBlock<Content: View>: View {
    let title: String
    let systemIcon: String
    let tint: Color
    /// Encre du titre de section (charte, règle 1 : un titre de section porte la
    /// couleur de son domaine, jamais l'encre neutre). Certains aplats de domaine
    /// sont trop clairs pour tenir 4.5:1 en texte sur la carte crème : on passe
    /// alors ici la déclinaison foncée du même domaine. `nil` = le tint suffit.
    var titleInk: Color? = nil
    let pageTitles: [String]
    let pageHeight: CGFloat
    var isLocked = false
    @ViewBuilder var page: (Int) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    private var count: Int { max(1, pageTitles.count) }

    /// Encre effective du titre et de son icône.
    private var ink: Color { titleInk ?? tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Titre de section : 13 / bold / couleur du domaine + icône 15
            // semibold. Il annonce le bloc, il ne rivalise pas avec le nom de
            // la courbe (17 / heavy) qui, lui, est la donnée.
            HStack(spacing: 8) {
                Image(systemName: systemIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.14)))
                Text(title)
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(ink)
                Spacer(minLength: 8)
                if count > 1 {
                    arrow("chevron.left", delta: -1)
                    arrow("chevron.right", delta: 1)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                // Donnée-héros textuelle du bloc : le nom de la courbe affichée.
                Text(pageTitles.indices.contains(index) ? pageTitles[index] : "")
                    .font(Theme.heroTextFont)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if count > 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<count, id: \.self) { i in
                            Capsule()
                                .fill(i == index ? tint : Color(hex: "E4DDD0"))
                                .frame(width: i == index ? 16 : 6, height: 6)
                        }
                    }
                }
            }
            .padding(.top, 8)

            if isLocked {
                GatedOverlay(intensity: .locked) {
                    pageDeck
                }
            } else {
                pageDeck
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .kiwiCard()
        // Un id stable évite que SwiftUI réinitialise l'index quand le contenu
        // des pages change (nouveau scan, nouveau check-in).
        .onChange(of: count) { _, newCount in
            if index >= newCount { index = max(0, newCount - 1) }
        }
    }

    private var pageDeck: some View {
        TabView(selection: $index) {
            ForEach(0..<count, id: \.self) { i in
                page(i).tag(i).padding(.top, 6)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: pageHeight)
    }

    private func arrow(_ icon: String, delta: Int) -> some View {
        Button {
            let next = (index + delta + count) % count
            if reduceMotion { index = next }
            else { withAnimation(.easeInOut(duration: 0.28)) { index = next } }
            HapticService.shared.selection()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.dsTexte)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.dsTexte.opacity(0.10), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel(delta < 0 ? "Courbe précédente" : "Courbe suivante")
    }
}
