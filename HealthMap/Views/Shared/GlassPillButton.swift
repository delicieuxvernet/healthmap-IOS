import SwiftUI

// MARK: - Glass Pill Button (bouton secondaire « glass » partagé)
/// Bouton secondaire universel (DESIGN-PAGES loi 7) : fond `.ultraThinMaterial`
/// en capsule + liseré fin, jamais de fond opaque. Utilisé sur le Bilan pour
/// « Pourquoi ? » (cartes nutriments) et « Tous mes nutriments (N) ».
///
/// - Touch target : `minHeight: 44` appliqué DANS le label (loi 20 / HIG) —
///   la zone tappable rendue fait bien 44 pt, pas seulement le padding déclaré.
/// - Feedback : `.healthMapPressed` (scale 0.97) ; le haptic léger est déclenché
///   par le call-site via `HapticService` (loi 18).
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
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.healthMapBlue)
            .padding(.horizontal, Theme.spacingMD)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.healthMapBlue.opacity(Theme.opacityMedium), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    VStack(spacing: 16) {
        GlassPillButton(title: "Pourquoi\u{202F}?") {}
        GlassPillButton(title: "Tous mes nutriments (10)", systemImage: "square.grid.3x3") {}
    }
    .padding()
    .background(Color.healthMapBackground)
}
