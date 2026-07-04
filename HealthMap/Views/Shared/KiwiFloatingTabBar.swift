import SwiftUI

// MARK: - Barre d'onglets flottante (langage v4 — maquette p-scanner)
//
// Pill blanche flottante posée en overlay bas de `MainTabView` (la barre native
// est masquée par onglet via `.toolbar(.hidden, for: .tabBar)`). Accent vert
// kiwi sur l'onglet actif. Pilote `MainTabView.Tab` (binding).
struct KiwiFloatingTabBar: View {
    @Binding var selected: MainTabView.Tab

    private struct Item: Identifiable {
        var id: MainTabView.Tab { tab }
        let tab: MainTabView.Tab
        let icon: String
        let label: String
    }

    private let items: [Item] = [
        Item(tab: .bilan, icon: "heart.text.clipboard", label: "Bilan"),
        Item(tab: .suivi, icon: "checkmark.circle", label: "Suivi"),
        Item(tab: .scanner, icon: "camera", label: "Scanner"),
        Item(tab: .plan, icon: "list.bullet.clipboard", label: "Plan"),
        Item(tab: .complements, icon: "pills", label: "Compléments"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let active = selected == item.tab
                Button {
                    HapticService.shared.selection()
                    selected = item.tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: active ? 23 : 22, weight: active ? .semibold : .regular))
                        Text(item.label)
                            .font(.system(size: 10, weight: active ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(active ? Color.kiwiGreen : Color(hex: "9AA0A6"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
        .background(
            Capsule(style: .continuous)
                .fill(Color.healthMapCard)
                .shadow(color: Color.kiwiCharcoal.opacity(0.12), radius: 24, x: 0, y: 6)
                .shadow(color: Color.kiwiCharcoal.opacity(0.06), radius: 3, x: 0, y: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Réservation d'espace pour la barre flottante
/// Réserve la hauteur de la pill (8 pt de marge haute + 64 pt + 2 pt basse
/// = 74 pt) pour que le contenu défilant s'arrête AU-DESSUS de la barre.
/// ⚠️ À appliquer au CONTENU RACINE, À L'INTÉRIEUR du NavigationStack de
/// chaque onglet : un inset posé sur le TabView ou autour du NavigationStack
/// ne se propage pas à la safe area du scroll (hébergement UIKit) — c'était
/// la cause du contenu masqué sous la barre (builds 179→202).
extension View {
    func kiwiTabBarBottomInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 74)
        }
    }
}
