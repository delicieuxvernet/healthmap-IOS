import SwiftUI

// MARK: - Animated Background
/// Fond animé réutilisable façon hero du site web : trois blobs de couleur
/// (bleu / violet / ciel) très flous qui dérivent lentement au-dessus du fond.
///
/// - GPU-friendly : pas de `TimelineView`. Le `blur` est appliqué AVANT
///   l'`offset`/`scaleEffect`, donc Core Animation déplace une couche déjà
///   floutée (le flou n'est jamais recalculé pendant l'animation).
/// - Animations longues (11–17 s) en `repeatForever(autoreverses:)` : dérive
///   douce, jamais de mouvement brusque.
/// - Reduce Motion : les blobs restent à leur position de repos → gradient
///   statique, zéro animation.
/// - Décoratif : `allowsHitTesting(false)` + `accessibilityHidden(true)`.
///
/// Usage :
/// ```swift
/// ZStack {
///     AnimatedBackground()
///     contenu
/// }
/// ```
struct AnimatedBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                // Fond de base (token canonique, adaptive light/dark)
                Color.healthMapBackground

                // Blob bleu — haut droite (miroir du radial-gradient du hero web)
                Circle()
                    .fill(Color.healthMapAuroraBlue)
                    .frame(width: w * 0.95, height: w * 0.95)
                    .blur(radius: 70)
                    .opacity(0.55)
                    .scaleEffect(drift ? 1.12 : 1.0)
                    .offset(x: drift ? w * 0.32 : w * 0.42,
                            y: drift ? -h * 0.30 : -h * 0.36)
                    .animation(driftAnimation(duration: 13), value: drift)

                // Blob violet — gauche, mi-hauteur
                Circle()
                    .fill(Color.healthMapAuroraViolet)
                    .frame(width: w * 0.85, height: w * 0.85)
                    .blur(radius: 75)
                    .opacity(0.45)
                    .scaleEffect(drift ? 1.0 : 1.10)
                    .offset(x: drift ? -w * 0.38 : -w * 0.30,
                            y: drift ? -h * 0.02 : h * 0.06)
                    .animation(driftAnimation(duration: 17), value: drift)

                // Blob ciel — bas, centré
                Circle()
                    .fill(Color.healthMapAuroraSky)
                    .frame(width: w * 0.9, height: w * 0.9)
                    .blur(radius: 80)
                    .opacity(0.40)
                    .scaleEffect(drift ? 1.08 : 1.0)
                    .offset(x: drift ? w * 0.12 : -w * 0.05,
                            y: drift ? h * 0.40 : h * 0.34)
                    .animation(driftAnimation(duration: 11), value: drift)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            // Reduce Motion → on ne déclenche jamais la dérive : composition statique.
            guard !reduceMotion else { return }
            drift = true
        }
    }

    /// Animation de dérive douce, ou `nil` si Reduce Motion est actif.
    private func driftAnimation(duration: Double) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }
}

#Preview("Light") {
    AnimatedBackground()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AnimatedBackground()
        .preferredColorScheme(.dark)
}
