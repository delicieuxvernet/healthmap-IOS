import SwiftUI

// MARK: - Glass Pill Button (bouton secondaire « glass » partagé)
/// Bouton secondaire universel (DESIGN-PAGES loi 7). Verre liquide (2 octobre
/// 2026) : c'est désormais un VRAI verre clair en capsule (`.verreClair()` :
/// blanc 74 → 40 %, reflet haut et bas, liseré, ombre découpée), et non plus
/// un `Material` cerclé de vert. Le libellé passe à l'encre, comme sur toutes
/// les puces de verre de la maquette ; le vert reste sur l'icône, qui dit
/// « ça se touche ».
///
/// - Touch target : `minHeight: 44` appliqué DANS le label (loi 20 / HIG) —
///   la zone tappable rendue fait bien 44 pt, pas seulement le padding déclaré.
/// - Feedback : `.dsPress` (échelle 0,96, ressort vif) ; le haptic léger est
///   déclenché par le call-site via `HapticService` (loi 18).
struct GlassPillButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacingXS) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.dsAccent)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTexte)
            }
            .padding(.horizontal, Theme.spacingMD)
            .frame(minHeight: 44)
            .verreClair()
            .contentShape(Capsule())
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ZStack {
        VerreFond()
        VStack(spacing: 16) {
            GlassPillButton(title: "Pourquoi\u{202F}?") {}
            GlassPillButton(title: "Tous mes nutriments (10)", systemImage: "square.grid.3x3") {}
        }
        .padding()
    }
}
