import SwiftUI

// MARK: - Barre d'onglets (verre liquide, 2 octobre 2026)
//
// Capsule de verre flottante : marges 12 à gauche, à droite et en bas,
// hauteur 62, verre `VerreMatiere.barre` (blanc 62 → 40 %, flou vivant, reflet
// haut et bas, liseré). Onglet actif : une PASTILLE de verre blanc (62 × 52)
// qui GLISSE d'un onglet à l'autre sur un ressort, en s'étirant à 80 pendant
// le trajet ; l'icône touchée rebondit à 1,22 ; icône et libellé verts.
// Inactif : `secondaryLabel`. Libellés en 10 pt (600 actif, 500 sinon).
// Haptique `.selection` au changement d'onglet.
//
// Cinq onglets qui nomment des OBJETS, pas des concepts :
// Journal · Progrès · Plan · Compléments · Réglages.
// Le Scan n'est plus un onglet : toute la saisie vit sur la page du Journal
// (`JournalSaisieBloc` : Dicter · Photographier · autres façons d'ajouter).
//
// Posée en overlay bas de `MainTabView`. Les écrans réservent la place
// eux-mêmes via `.kiwiTabBarBottomInset()` (voir plus bas).
struct KiwiFloatingTabBar: View {
    @Binding var selected: MainTabView.Tab
    /// Onglets estompés (`tertiaryLabel`) : avant le questionnaire, Progrès,
    /// Plan et Compléments n'ont aucune donnée perso. Ils restent ouverts
    /// (entrée libre), seule leur présence dans la barre s'efface.
    var estompes: Set<MainTabView.Tab> = []

    /// Hauteur de la capsule.
    static let barHeight: CGFloat = 62
    /// Largeur de la pastille de l'onglet actif, au repos puis en trajet.
    static let largeurPastille: CGFloat = 62
    static let largeurPastilleEtiree: CGFloat = 80
    /// Marge de la pastille en haut et en bas de la capsule.
    static let margePastille: CGFloat = 5
    /// Marge entre la capsule et le bord bas de la zone sûre.
    static let margeBas: CGFloat = 12
    /// Marge latérale de la capsule.
    static let margeLaterale: CGFloat = 12
    /// Hauteur totale à réserver sous le contenu d'un onglet.
    static var insetBas: CGFloat { barHeight + margeBas }

    private struct Item: Identifiable {
        var id: MainTabView.Tab { tab }
        let tab: MainTabView.Tab
        let icon: String
        let label: String
    }

    private let items: [Item] = [
        Item(tab: .journal, icon: "book.closed", label: "Journal"),
        Item(tab: .progres, icon: "chart.xyaxis.line", label: "Progrès"),
        Item(tab: .plan, icon: "map", label: "Plan"),
        Item(tab: .complements, icon: "pills", label: "Compléments"),
        Item(tab: .reglages, icon: "gearshape", label: "Réglages"),
    ]

    /// Onglet dont l'icône rebondit (celui qu'on vient de toucher).
    @State private var rebond: MainTabView.Tab? = nil
    /// La pastille s'étire pendant le trajet.
    @State private var etiree = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { tabButton($0) }
        }
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geo in
                let pas = geo.size.width / CGFloat(max(1, items.count))
                let largeur = etiree ? Self.largeurPastilleEtiree : Self.largeurPastille
                Color.clear
                    .frame(width: largeur, height: max(0, geo.size.height - 2 * Self.margePastille))
                    .verre(.pastille, forme: Capsule(style: .continuous))
                    .position(
                        x: (CGFloat(selected.position) + 0.5) * pas,
                        y: geo.size.height / 2
                    )
                    .animation(reduceMotion ? nil : Animation.kiwiPastille, value: selected)
                    .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.22), value: etiree)
            }
        }
        .verre(.barre, forme: Capsule(style: .continuous))
        .padding(.horizontal, Self.margeLaterale)
        .padding(.bottom, Self.margeBas)
        .accessibilityElement(children: .contain)
        .onChange(of: selected) { _, nouvel in
            // Le changement peut venir d'ailleurs que d'un toucher (lien
            // interne, notification) : la barre le joue de la même façon.
            HapticService.shared.selection()
            guard !reduceMotion else { return }
            rebond = nouvel
            etiree = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(190))
                etiree = false
                try? await Task.sleep(for: .milliseconds(30))
                if rebond == nouvel { rebond = nil }
            }
        }
    }

    // MARK: - Onglet

    private func tabButton(_ item: Item) -> some View {
        let actif = selected == item.tab
        return Button {
            selected = item.tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: item.icon)
                    .font(.system(size: 21, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(rebond == item.tab ? KiwiEchelle.iconeOnglet : 1)
                    .animation(reduceMotion ? nil : Animation.kiwiRebond, value: rebond)
                Text(item.label)
                    .font(.dsOnglet(actif: actif))
                    .lineLimit(1)
                    // « Compléments » actif (semibold) dépassait son cinquième
                    // de barre et s'affichait « Complém… » (audit captures).
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(actif ? Color.dsAccent : (estompes.contains(item.tab) ? Color.dsTertiaire : Color.dsSecondaire))
            .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.2), value: selected)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DS.cibleTactile)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityIdentifier("tab.\(String(describing: item.tab))")
        .accessibilityAddTraits(actif ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Réservation d'espace pour la barre
/// Réserve la hauteur de la capsule + sa marge (74 pt) pour que le contenu
/// défilant s'arrête AU-DESSUS de la barre.
/// ⚠️ À appliquer au CONTENU RACINE, À L'INTÉRIEUR du NavigationStack de
/// chaque onglet : un inset posé sur le conteneur d'onglets ne se propage pas
/// à la safe area du scroll (hébergement UIKit) — c'était la cause du contenu
/// masqué sous la barre (builds 179→202).
extension View {
    func kiwiTabBarBottomInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: KiwiFloatingTabBar.insetBas)
        }
    }
}
