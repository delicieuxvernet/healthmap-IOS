import SwiftUI

// MARK: - Sparkle Burst
/// Étincelles vectorielles (étoiles à 4 branches) qui scintillent autour d'un
/// point — utilisé pour les célébrations (CelebrationView, CelebrationOverlay).
/// 100 % `Canvas` SwiftUI, aucune ressource binaire.
///
/// - Reduce Motion : étincelles statiques (aucun scintillement).
/// - Décorative : `allowsHitTesting(false)` + `accessibilityHidden(true)`.
struct SparkleBurst: View {
    var size: CGFloat = 220

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Positions relatives (0→1), échelle et couleur de chaque étincelle.
    // hue : 0 = bleu brand, 1 = indigo, 2 = ambre.
    private static let sparkles: [(x: CGFloat, y: CGFloat, scale: CGFloat, hue: Int)] = [
        (0.12, 0.20, 1.30, 0),
        (0.86, 0.28, 1.00, 1),
        (0.22, 0.74, 0.80, 2),
        (0.80, 0.70, 0.72, 0),
        (0.50, 0.06, 0.62, 1),
        (0.96, 0.52, 0.55, 2),
        (0.05, 0.50, 0.60, 1),
    ]

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { ctx, canvasSize in
                    Self.draw(in: ctx, size: canvasSize, time: 0)
                }
            } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, canvasSize in
                        Self.draw(in: ctx, size: canvasSize, time: t)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let palette: [Color] = [.healthMapBlue, .accentIndigo, Color(hex: "EF9F27")]

    private static func draw(in context: GraphicsContext, size: CGSize, time: Double) {
        let sz = min(size.width, size.height)
        for (i, sp) in sparkles.enumerated() {
            // Scintillement : pulse 0,6→1,0, déphasé par étincelle (statique si time == 0).
            let phase = Double(i) * 0.7
            let pulse: CGFloat = time == 0
                ? 1.0
                : CGFloat(0.6 + 0.4 * (0.5 + 0.5 * sin(2 * Double.pi * time / 1.2 + phase)))
            let r = sz * 0.065 * sp.scale * pulse
            let cx = sp.x * size.width
            let cy = sp.y * size.height
            context.fill(
                sparklePath(cx: cx, cy: cy, r: r),
                with: .color(palette[sp.hue].opacity(0.9))
            )
        }
    }

    /// Étoile à 4 branches centrée en (cx, cy), rayon `r` (pointes), creux à 0,32·r.
    private static func sparklePath(cx: CGFloat, cy: CGFloat, r: CGFloat) -> Path {
        let ir = r * 0.32
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - r))
        p.addLine(to: CGPoint(x: cx + ir, y: cy - ir))
        p.addLine(to: CGPoint(x: cx + r, y: cy))
        p.addLine(to: CGPoint(x: cx + ir, y: cy + ir))
        p.addLine(to: CGPoint(x: cx, y: cy + r))
        p.addLine(to: CGPoint(x: cx - ir, y: cy + ir))
        p.addLine(to: CGPoint(x: cx - r, y: cy))
        p.addLine(to: CGPoint(x: cx - ir, y: cy - ir))
        p.closeSubpath()
        return p
    }
}

#Preview {
    SparkleBurst(size: 240)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.healthMapBackground)
}
