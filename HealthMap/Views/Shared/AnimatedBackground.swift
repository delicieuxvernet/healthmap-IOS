import SwiftUI

// MARK: - Animated Background
/// Fond animé réutilisable — miroir 2D du ruban WebGL du site web
/// (`src/components/RibbonBackground.jsx`) : trois bandes-rubans diagonales
/// dont les bords sont des sinusoïdes déphasées, remplies des couleurs
/// canoniques du ruban (lavande → bleus ciel, reflet rose iridescent),
/// floutées et à faible opacité — le ruban se voit, mais ne domine jamais
/// les cartes blanches.
///
/// - GPU-friendly : pas de `TimelineView`. La phase des sinusoïdes est
///   l'`animatableData` de chaque `Shape`, pilotée par un unique `@State`
///   booléen et des animations linéaires très lentes (24–30 s,
///   `repeatForever(autoreverses: true)`) : dérive douce, jamais brusque.
/// - Torsion : l'épaisseur de chaque bande se pince périodiquement (|cos|)
///   pour évoquer les ~3,4 torsades du ruban web (`uTwists = 3.4`).
/// - Reduce Motion : phase figée à mi-course → ruban statique, zéro animation.
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

    /// Phase courante des sinusoïdes. Reduce Motion → mi-phase (pose
    /// naturelle du ruban, ni début ni fin de course), sinon 0 → 2π animé.
    private var phase: Double {
        if reduceMotion { return .pi }
        return drift ? 2 * .pi : 0
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                // Fond de base (token canonique, adaptive light/dark)
                Color.healthMapBackground

                // Bande principale — lavande → bleu → ciel (uColorA/B/C),
                // descend en diagonale dans le tiers haut de l'écran.
                RibbonBandShape(
                    phase: phase,
                    startY: 0.20, endY: 0.44,
                    thickness: 0.16, amplitude: 0.045,
                    twists: 3.4, edgePhase: 1.1, phaseSeed: 0
                )
                .fill(LinearGradient(
                    colors: [.healthMapRibbonLavender, .healthMapRibbonBlue, .healthMapRibbonSky],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .blur(radius: 10)
                .opacity(0.40)
                .animation(driftAnimation(duration: 26), value: drift)

                // Bande iridescente — reflet rose (uColorIridA) fondu vers la
                // lavande et le bleu, remonte en diagonale au centre.
                RibbonBandShape(
                    phase: phase,
                    startY: 0.72, endY: 0.52,
                    thickness: 0.13, amplitude: 0.04,
                    twists: 3.4, edgePhase: 1.2, phaseSeed: 2.1
                )
                .fill(LinearGradient(
                    colors: [.healthMapRibbonPink, .healthMapRibbonLavender, .healthMapRibbonBlue],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .blur(radius: 12)
                .opacity(0.32)
                .animation(driftAnimation(duration: 30), value: drift)

                // Voile fin — ciel, bas d'écran, presque subliminal.
                RibbonBandShape(
                    phase: phase,
                    startY: 0.86, endY: 0.94,
                    thickness: 0.10, amplitude: 0.03,
                    twists: 3.4, edgePhase: 1.0, phaseSeed: 4.2
                )
                .fill(LinearGradient(
                    colors: [.healthMapRibbonSky, .healthMapRibbonBlue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .blur(radius: 14)
                .opacity(0.24)
                .animation(driftAnimation(duration: 24), value: drift)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            // Reduce Motion → on ne déclenche jamais la dérive : ruban statique.
            guard !reduceMotion else { return }
            drift = true
        }
    }

    /// Dérive linéaire très lente (aller-retour), ou `nil` si Reduce Motion.
    private func driftAnimation(duration: Double) -> Animation? {
        reduceMotion ? nil : .linear(duration: duration).repeatForever(autoreverses: true)
    }
}

// MARK: - Ribbon Band Shape
/// Une bande-ruban traversant l'écran en diagonale. Les deux bords sont des
/// sinusoïdes déphasées (`edgePhase`) et l'épaisseur se pince en |cos| le
/// long de la bande pour évoquer la torsion du ruban web (le ruban « vu sur
/// la tranche » aux points de twist).
///
/// Invariant anti-croisement : le plancher d'épaisseur (0.45) doit rester
/// supérieur au resserrement max des bords, soit
/// `thickness × 0.45 > amplitude × 2 × sin(edgePhase / 2)` — vérifié pour
/// les trois jeux de paramètres utilisés ci-dessus.
private struct RibbonBandShape: Shape {
    /// Phase des sinusoïdes (0…2π) — seule valeur animée.
    var phase: Double
    /// Position verticale relative du centre de la bande au bord gauche (0…1).
    var startY: Double
    /// Position verticale relative du centre de la bande au bord droit (0…1).
    var endY: Double
    /// Épaisseur maximale de la bande, relative à la hauteur de l'écran.
    var thickness: Double
    /// Amplitude des sinusoïdes de bord, relative à la hauteur de l'écran.
    var amplitude: Double
    /// Nombre de torsades (pincements) le long de la bande (~3,4 comme le web).
    var twists: Double
    /// Déphasage du bord bas par rapport au bord haut (radians).
    var edgePhase: Double
    /// Décalage de phase propre à la bande (désynchronise les bandes).
    var phaseSeed: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = Double(rect.width)
        let h = Double(rect.height)
        guard w > 0, h > 0 else { return Path() }

        let samples = 64
        // La bande dépasse l'écran à gauche et à droite pour que le blur ne
        // révèle jamais une extrémité coupée.
        let overscan = 0.12
        let p = phase + phaseSeed

        // Ligne médiane : descente (ou montée) diagonale linéaire.
        func centerY(_ t: Double) -> Double {
            h * (startY + (endY - startY) * t)
        }
        // Sinusoïde de bord : ~1,3 période sur la longueur, translatée par la phase.
        func wave(_ t: Double, _ offset: Double) -> Double {
            amplitude * h * sin(2 * .pi * 1.3 * t + p + offset)
        }
        // Torsion : pincement périodique de l'épaisseur (|cos|), à fréquence
        // `twists`, dérivant à mi-vitesse de la phase.
        func halfThickness(_ t: Double) -> Double {
            (thickness * h / 2) * (0.45 + 0.55 * abs(cos(.pi * twists * t + p * 0.5)))
        }
        func xAt(_ t: Double) -> Double {
            (-overscan + (1 + 2 * overscan) * t) * w
        }
        func topY(_ t: Double) -> Double {
            centerY(t) - halfThickness(t) + wave(t, 0)
        }
        func bottomY(_ t: Double) -> Double {
            centerY(t) + halfThickness(t) + wave(t, edgePhase)
        }

        var path = Path()
        // Bord haut, de gauche à droite…
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            let point = CGPoint(x: xAt(t), y: topY(t))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        // …puis bord bas, de droite à gauche.
        for i in stride(from: samples, through: 0, by: -1) {
            let t = Double(i) / Double(samples)
            path.addLine(to: CGPoint(x: xAt(t), y: bottomY(t)))
        }
        path.closeSubpath()
        return path
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
