import SwiftUI

// MARK: - Barre d'onglets (refonte « qualité Apple », 23 août 2026)
//
// Capsule flottante (pattern iOS 26 « Liquid Glass ») : marges 12 à gauche, à
// droite et en bas, hauteur 60, rayon 999, `.ultraThinMaterial`, hairline
// 0,5 pt à `rgba(60,60,67,.13)`, ombre `0 8 28 / 10 %`. Onglet actif :
// pastille `#EFEFF4` + icône et libellé verts. Inactif : `secondaryLabel`.
// Libellés en 10 pt.
//
// Cinq onglets qui nomment des OBJETS, pas des concepts :
// Journal · Progrès · Plan · Compléments · Réglages.
// Le Scan n'est plus un onglet : toute la saisie vit derrière le bouton
// d'ajout flottant du Journal (`DSAddButton` + `AjoutSheet`).
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
    static let barHeight: CGFloat = 60
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { tabButton($0) }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.dsCarte.opacity(0.55)))
                .overlay(Capsule().strokeBorder(Color.dsSeparateur.opacity(0.6), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 8)
        }
        .padding(.horizontal, Self.margeLaterale)
        .padding(.bottom, Self.margeBas)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Onglet

    private func tabButton(_ item: Item) -> some View {
        let actif = selected == item.tab
        return Button {
            // Aucun haptique sur la simple navigation (§5 du document).
            selected = item.tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 21, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(item.label)
                    .font(.dsOnglet(actif: actif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(actif ? Color.dsAccent : (estompes.contains(item.tab) ? Color.dsTertiaire : Color.dsSecondaire))
            .padding(.horizontal, actif ? 14 : 8)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(actif ? Color.dsRemplissage : Color.clear)
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: DS.cibleTactile)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(actif ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Bouton d'ajout flottant (60 pt, vert, coin bas droit)

/// Le seul point d'entrée de la saisie : il ouvre la feuille d'ajout. Posé
/// au-dessus de la tab bar, à 20 pt du bord droit. Ombre verte douce — la
/// seule ombre autorisée de la refonte, parce que le bouton FLOTTE.
struct DSAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Color.dsAccent))
                .shadow(color: Color.dsAccent.opacity(0.42), radius: 11, x: 0, y: 8)
                .contentShape(Circle())
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("Ajouter un repas")
        .accessibilityHint("Ouvre la feuille d'ajout : dicter, scanner, rechercher, code-barres.")
    }
}

// MARK: - Réservation d'espace pour la barre
/// Réserve la hauteur de la capsule + sa marge (72 pt) pour que le contenu
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
