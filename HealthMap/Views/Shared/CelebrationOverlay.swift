import SwiftUI

// MARK: - Celebration Overlay (gamification)
/// Overlay non bloquant de célébration, affiché à la racine (`MainTabView`)
/// quand `GamificationService.showConfetti` passe à `true` — déblocage de
/// badge, série, niveau supérieur, etc. Le kiwi saute, entouré d'étincelles,
/// avec un libellé adapté au type de réussite.
///
/// - `allowsHitTesting(false)` : ne bloque jamais l'interaction ni un tap ;
///   l'overlay se retire seul (le service repasse `showConfetti` à false ~3 s).
/// - Reduce Motion : pose statique + étincelles fixes (apparition sans ressort).
struct CelebrationOverlay: View {
    let type: ConfettiType

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            VStack(spacing: Theme.spacingMD) {
                ZStack {
                    SparkleBurst(size: 240)
                    KiwiWalkerView(size: 150, pose: .cheer)
                }
                .scaleEffect(appeared ? 1.0 : 0.5)
                .opacity(appeared ? 1.0 : 0)

                Text(caption)
                    .font(Theme.headlineFont)
                    .foregroundStyle(Color.healthMapText)
                    .padding(.horizontal, Theme.spacingLG)
                    .padding(.vertical, Theme.spacingSM)
                    .background(.ultraThinMaterial, in: Capsule())
                    .opacity(appeared ? 1.0 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(reduceMotion ? nil : .healthMapSpring) {
                appeared = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityAddTraits(.isStaticText)
    }

    private var caption: String {
        switch type {
        case .badge: return "Badge débloqué\u{202F}!"
        case .streak: return "Série en cours\u{202F}!"
        case .quest: return "Niveau supérieur\u{202F}!"
        case .nutrient: return "Bravo\u{202F}!"
        }
    }
}

#Preview {
    ZStack {
        Color.healthMapBackground.ignoresSafeArea()
        CelebrationOverlay(type: .badge)
    }
}
