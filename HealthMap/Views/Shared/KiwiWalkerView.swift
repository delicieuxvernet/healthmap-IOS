import SwiftUI
import Foundation

// MARK: - Kiwi Walker (mascotte de chargement)
/// Le kiwi HealthMap personnifié qui marche lentement sur place, façon
/// personnage Foodvisor. 100 % vectoriel (`Canvas` SwiftUI, aucun asset binaire).
///
/// Design validé avec Arthur (17 juin 2026) :
/// - visage réduit à **2 yeux** (pas de bouche, pas de joues) ;
/// - **bras & jambes de la couleur de la peau** (intégrés, palette ultra-réduite :
///   peau brune · chair verte · pépins/yeux encre · cœur crème) ;
/// - marche **lente et fluide**, rebond + léger tangage + clignement.
///
/// Couleurs : tokens `mascot*` de `Color+Theme.swift` (source canonique — aucune
/// nouvelle teinte introduite).
///
/// - Reduce Motion : pose statique (aucune animation).
/// - Décorative : `accessibilityHidden(true)`.
struct KiwiWalkerView: View {
    var size: CGFloat = 160

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, canvasSize in
                    Self.draw(in: context, size: canvasSize, time: 0)
                }
            } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, canvasSize in
                        Self.draw(in: context, size: canvasSize, time: t)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // Palette (tokens canoniques, constants entre light/dark comme un asset).
    private static let skin = Color.mascotSkin
    private static let flesh = Color.mascotFlesh
    private static let fleshLight = Color.mascotFleshLight
    private static let core = Color.mascotCore
    private static let ink = Color.mascotInk

    /// Dessine la mascotte. `time` en secondes (0 = pose neutre / reduce motion).
    private static func draw(in context: GraphicsContext, size: CGSize, time: Double) {
        let sz = min(size.width, size.height)
        let cx = size.width / 2
        let cy = size.height * 0.40
        let bodyR = sz * 0.27

        // Cinématique : un cycle de marche lent (1,6 s).
        let omega = 2 * Double.pi / 1.6
        let swing = sin(omega * time)
        let legL = 14.0 * swing
        let legR = -14.0 * swing
        let armL = 40.0 + 12.0 * swing      // bras gauche : sortant (vers la gauche) + balancement
        let armR = -40.0 - 12.0 * swing     // bras droit : sortant (vers la droite)
        let bob = -sz * 0.03 * CGFloat(swing * swing)  // petit rebond (2× par cycle)
        let tilt = 1.2 * swing                         // léger tangage (degrés, Double)
        let shadowSquish = 1.0 - 0.12 * CGFloat(swing * swing)

        // Clignement bref ~ toutes les 3,6 s.
        let blinking = time.truncatingRemainder(dividingBy: 3.6) < 0.13
        let eyeScaleY: CGFloat = blinking ? 0.14 : 1.0

        // Dimensions des membres.
        let legLen = sz * 0.21
        let legW = sz * 0.055
        let footRX = sz * 0.05
        let footRY = sz * 0.03
        let hipDX = bodyR * 0.34
        let hipY = cy + bodyR * 0.74
        let armLen = sz * 0.22
        let armW = sz * 0.052
        let handR = sz * 0.03
        let shoulderDX = bodyR * 0.62
        let shoulderY = cy - bodyR * 0.15

        // 1) Ombre au sol (ne suit pas le rebond, se contracte au rebond).
        let shRX = bodyR * 0.74 * shadowSquish
        let shRY = bodyR * 0.13
        let shY = size.height * 0.88
        context.fill(
            Path(ellipseIn: CGRect(x: cx - shRX, y: shY - shRY, width: shRX * 2, height: shRY * 2)),
            with: .color(.black.opacity(0.10))
        )

        // 2) Contexte du personnage : rebond vertical + léger tangage autour du corps.
        var character = context
        character.translateBy(x: 0, y: bob)
        character.translateBy(x: cx, y: cy)
        character.rotate(by: .degrees(tilt))
        character.translateBy(x: -cx, y: -cy)

        // 3) Jambes puis bras (dessinés derrière le corps).
        drawLimb(in: character, pivotX: cx - hipDX, pivotY: hipY, angle: legL,
                 length: legLen, width: legW, capRX: footRX, capRY: footRY)
        drawLimb(in: character, pivotX: cx + hipDX, pivotY: hipY, angle: legR,
                 length: legLen, width: legW, capRX: footRX, capRY: footRY)
        drawLimb(in: character, pivotX: cx - shoulderDX, pivotY: shoulderY, angle: armL,
                 length: armLen, width: armW, capRX: handR, capRY: handR)
        drawLimb(in: character, pivotX: cx + shoulderDX, pivotY: shoulderY, angle: armR,
                 length: armLen, width: armW, capRX: handR, capRY: handR)

        // 4) Corps : tranche de kiwi (peau · chair · cœur pâle · pépins · centre crème).
        character.fill(circle(cx, cy, bodyR), with: .color(skin))
        character.fill(circle(cx, cy, bodyR * 0.94), with: .color(flesh))
        character.fill(circle(cx, cy, bodyR * 0.52), with: .color(fleshLight))

        let seedR = bodyR * 0.66
        let seedW = bodyR * 0.05
        let seedH = bodyR * 0.085
        for i in 0..<8 {
            var seedCtx = character
            seedCtx.translateBy(x: cx, y: cy)
            seedCtx.rotate(by: .degrees(Double(i) * 45))
            seedCtx.fill(
                Path(ellipseIn: CGRect(x: -seedW / 2, y: -seedR - seedH / 2, width: seedW, height: seedH)),
                with: .color(ink)
            )
        }

        character.fill(circle(cx, cy, bodyR * 0.20), with: .color(core))

        // 5) Yeux (2 points encre, clignement). Rien d'autre sur le visage.
        let eyeDX = bodyR * 0.30
        let eyeY = cy - bodyR * 0.24
        let eyeRX = bodyR * 0.095
        let eyeRY = bodyR * 0.13 * eyeScaleY
        character.fill(
            Path(ellipseIn: CGRect(x: cx - eyeDX - eyeRX, y: eyeY - eyeRY, width: eyeRX * 2, height: eyeRY * 2)),
            with: .color(ink)
        )
        character.fill(
            Path(ellipseIn: CGRect(x: cx + eyeDX - eyeRX, y: eyeY - eyeRY, width: eyeRX * 2, height: eyeRY * 2)),
            with: .color(ink)
        )
    }

    private static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    /// Membre (jambe ou bras) pivotant autour de (`pivotX`, `pivotY`), terminé par
    /// un pied/main arrondi. Dessiné dans une copie du contexte (transform isolé).
    private static func drawLimb(in context: GraphicsContext, pivotX: CGFloat, pivotY: CGFloat,
                                 angle: Double, length: CGFloat, width: CGFloat,
                                 capRX: CGFloat, capRY: CGFloat) {
        var c = context
        c.translateBy(x: pivotX, y: pivotY)
        c.rotate(by: .degrees(angle))
        c.fill(
            Path(roundedRect: CGRect(x: -width / 2, y: 0, width: width, height: length), cornerRadius: width / 2),
            with: .color(skin)
        )
        c.fill(
            Path(ellipseIn: CGRect(x: -capRX, y: length - capRY, width: capRX * 2, height: capRY * 2)),
            with: .color(skin)
        )
    }
}

#Preview {
    KiwiWalkerView(size: 180)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.healthMapBackground)
}
