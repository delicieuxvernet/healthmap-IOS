import SwiftUI

// MARK: - Warm Background
/// Fond chaud statique unifié de l'app — remplace l'ancien ruban animé
/// (`AnimatedBackground`, retiré pour la perf : 3 bandes floutées redessinées
/// en continu). Ici : un simple dégradé chaud + un halo radial doux, **sans
/// animation ni blur** → coût GPU négligeable.
///
/// Dynamique light/dark via les tokens `healthMapWarm` / `healthMapWarmGlow`
/// (cf. `Color+Theme.swift`).
///
/// - Décoratif : `allowsHitTesting(false)` + `accessibilityHidden(true)`.
///
/// Usage (drop-in, comme l'ancien fond) :
/// ```swift
/// ZStack {
///     WarmBackground()
///     contenu
/// }
/// ```
struct WarmBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.healthMapWarm, Color.healthMapBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.healthMapWarmGlow.opacity(0.55), Color.healthMapWarmGlow.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.16),
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    WarmBackground()
}
