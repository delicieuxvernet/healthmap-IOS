import SwiftUI

// MARK: - Barre d'onglets (langage v7 — maquette « Kiwio - Bilan (standalone) »)
//
// Barre pleine largeur translucide (`.ultraThinMaterial` teinté crème) avec
// hairline haute de 0.5 pt, posée en overlay bas de `MainTabView` (la barre
// native est masquée par onglet via `.toolbar(.hidden, for: .tabBar)`).
// Onglet actif = vert kiwi, inactif = gris #9AA0A6.
//
// Le Scan est un BOUTON CENTRAL SURÉLEVÉ : cercle 56 pt vert plein, icône
// caméra blanche, ombre portée + anneau crème de 5 pt (effet « bouton qui
// dépasse »). Il est posé en overlay du haut de la barre pour déborder sans
// être rogné, et garde sa propre zone tactile de 56 pt.
struct KiwiFloatingTabBar: View {
    @Binding var selected: MainTabView.Tab

    /// Hauteur de la barre elle-même (hors safe area basse).
    static let barHeight: CGFloat = 58

    private struct Item: Identifiable {
        var id: MainTabView.Tab { tab }
        let tab: MainTabView.Tab
        let icon: String
        let label: String
    }

    /// Ordre maquette : Bilan · Suivi · [Scan] · Plan · Compléments.
    /// Le Scan n'est pas dans cette liste : il occupe la colonne centrale via
    /// `scanLabelColumn` + l'overlay du cercle surélevé.
    private let leading: [Item] = [
        Item(tab: .bilan, icon: "heart.text.square", label: "Bilan"),
        Item(tab: .suivi, icon: "checkmark.circle", label: "Suivi"),
    ]

    private let trailing: [Item] = [
        Item(tab: .plan, icon: "list.clipboard", label: "Plan"),
        Item(tab: .complements, icon: "pills", label: "Compléments"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(leading) { tabButton($0) }
            scanLabelColumn
            ForEach(trailing) { tabButton($0) }
        }
        .padding(.top, 9)
        .padding(.horizontal, 6)
        .frame(height: Self.barHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.kiwiCream.opacity(0.5))
                Rectangle()
                    .fill(Color.kiwiCharcoal.opacity(0.14))
                    .frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        // Bouton Scan surélevé : posé en overlay (centré horizontalement) pour
        // déborder au-dessus de la barre sans être rogné, zone tactile intacte.
        .overlay(alignment: .top) {
            scanButton.offset(y: -26)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Onglet standard
    private func tabButton(_ item: Item) -> some View {
        let active = selected == item.tab
        return Button {
            HapticService.shared.selection()
            selected = item.tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: active ? 23 : 22, weight: active ? .semibold : .regular))
                Text(item.label)
                    .font(.system(size: 9.5, weight: active ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(active ? Color.kiwiGreen : Color(hex: "9AA0A6"))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Colonne centrale (réserve la place du cercle + porte le label)
    private var scanLabelColumn: some View {
        VStack(spacing: 3) {
            Spacer(minLength: 0)
            Text("Scan")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(Color.kiwiGreen)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .padding(.bottom, 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Bouton Scan central surélevé
    private var scanButton: some View {
        Button {
            HapticService.shared.selection()
            selected = .scanner
        } label: {
            Circle()
                .fill(Color.kiwiGreen)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .overlay(
                    Circle().stroke(Color.kiwiCream, lineWidth: 5)
                )
                .shadow(color: Color.kiwiGreen.opacity(0.4), radius: 10, x: 0, y: 8)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan")
        .accessibilityAddTraits(selected == .scanner ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Réservation d'espace pour la barre
/// Réserve la hauteur de la barre (58 pt) pour que le contenu défilant
/// s'arrête AU-DESSUS. Le cercle Scan déborde volontairement par-dessus le
/// contenu (effet « bouton qui dépasse » de la maquette).
/// ⚠️ À appliquer au CONTENU RACINE, À L'INTÉRIEUR du NavigationStack de
/// chaque onglet : un inset posé sur le TabView ou autour du NavigationStack
/// ne se propage pas à la safe area du scroll (hébergement UIKit) — c'était
/// la cause du contenu masqué sous la barre (builds 179→202).
extension View {
    func kiwiTabBarBottomInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: KiwiFloatingTabBar.barHeight)
        }
    }
}
