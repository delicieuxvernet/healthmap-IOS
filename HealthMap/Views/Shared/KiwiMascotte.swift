import SwiftUI

// MARK: - Mascotte « Le regard » (maquette « Kiwio - Mascotte clay », variante B1)
//
// La tranche de kiwi du signe, avec deux yeux et un sourire. Elle n'apparaît
// qu'à trois endroits (maquette « Motion v3 - Verre liquide ») :
//
//   - Réglages, ligne « Kiwio Premium » : petite et immobile (44 pt) ;
//   - feuille Premium : grande (84 pt) et animée — un petit saut avec l'ombre
//     qui suit, un clignement, et un halo qui tourne derrière elle ;
//   - le questionnaire (décision d'Arthur, 3 octobre 2026, « questionnaire
//     ludique ») : c'est elle qui parle, en haut de chaque écran, et qui fête
//     la fin d'une étape.
//
// Partout ailleurs, l'identité reste le signe (`KiwiSigne`).
//
// Dessinée dans un repère de 200 × 200, comme la maquette : peau `#2F5A16`
// (rayon 80), chair `#5DA838` (72), halo `#9FD46F` (46), cœur `#EAF3DE` (33),
// douze graines sur un rayon de 59, deux yeux à ± 12 du centre.
struct KiwiMascotte: View {
    /// Saut et clignement. Immobile sinon, et toujours immobile sous
    /// « Réduire les animations ».
    var animee: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.estOngletActif) private var estOngletActif

    var body: some View {
        Group {
            if animee && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !estOngletActif)) { chrono in
                    dessin(temps: chrono.date.timeIntervalSinceReferenceDate)
                }
            } else {
                dessin(temps: nil)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func dessin(temps: Double?) -> some View {
        Canvas { contexte, taille in
            KiwiMascotte.peindre(&contexte, taille: taille, temps: temps)
        }
    }

    // MARK: Couleurs

    private static let peau = Color(hex: "2F5A16")
    private static let chair = Color(hex: "5DA838")
    private static let halo = Color(hex: "9FD46F")
    private static let coeur = Color(hex: "EAF3DE")
    private static let encre = Color(hex: "1E2A14")

    // MARK: Pose

    /// La pose de la tête à un instant du saut (cycle de 2,8 s) : immobile
    /// jusqu'à 62 %, elle s'écrase, décolle de 12, retombe en s'écrasant.
    struct Pose: Equatable {
        var y: Double
        var sx: Double
        var sy: Double

        static let repos = Pose(y: 0, sx: 1, sy: 1)

        func vers(_ autre: Pose, _ p: Double) -> Pose {
            Pose(y: y + (autre.y - y) * p, sx: sx + (autre.sx - sx) * p, sy: sy + (autre.sy - sy) * p)
        }
    }

    private static func adoucir(_ p: Double) -> Double {
        let borne = min(1, max(0, p))
        return borne * borne * (3 - 2 * borne)
    }

    /// Pose du saut pour une phase 0…1 du cycle.
    static func pose(phase: Double) -> Pose {
        let elan = Pose(y: 0, sx: 1.06, sy: 0.94)
        let envol = Pose(y: -12, sx: 0.97, sy: 1.03)
        let retombee = Pose(y: 0, sx: 1.03, sy: 0.97)
        switch phase {
        case ..<0.62:
            return .repos
        case ..<0.70:
            return Pose.repos.vers(elan, adoucir((phase - 0.62) / 0.08))
        case ..<0.80:
            return elan.vers(envol, adoucir((phase - 0.70) / 0.10))
        case ..<0.90:
            return envol.vers(retombee, adoucir((phase - 0.80) / 0.10))
        default:
            return retombee.vers(.repos, adoucir((phase - 0.90) / 0.10))
        }
    }

    /// Ouverture des yeux (1 = ouverts) pour une phase 0…1 du cycle de 4,6 s :
    /// un clignement bref à 94 %.
    static func ouvertureYeux(phase: Double) -> Double {
        switch phase {
        case ..<0.90:
            return 1
        case ..<0.94:
            return 1 + (0.08 - 1) * adoucir((phase - 0.90) / 0.04)
        default:
            return 0.08 + (1 - 0.08) * adoucir((phase - 0.94) / 0.06)
        }
    }

    // MARK: Dessin

    static func peindre(_ contexte: inout GraphicsContext, taille: CGSize, temps: Double?) {
        let k = Double(min(taille.width, taille.height)) / 200
        guard k > 0 else { return }

        var pose = Pose.repos
        var yeux = 1.0
        if let temps {
            pose = Self.pose(phase: (temps / 2.8).truncatingRemainder(dividingBy: 1))
            yeux = ouvertureYeux(phase: (temps / 4.6).truncatingRemainder(dividingBy: 1))
        }

        // Ombre au sol : elle rétrécit et pâlit quand la tête décolle.
        let hauteur = min(1, max(0, -pose.y / 12))
        var sol = contexte
        sol.translateBy(x: 100 * k, y: 190 * k)
        sol.scaleBy(x: 1 - 0.2 * hauteur, y: 1 - 0.2 * hauteur)
        sol.fill(
            Path(ellipseIn: CGRect(x: -46 * k, y: -5.5 * k, width: 92 * k, height: 11 * k)),
            with: .color(Color.black.opacity(0.12 - 0.05 * hauteur))
        )

        // Tête : elle se déforme autour de son point d'appui (100, 180).
        var tete = contexte
        tete.translateBy(x: 100 * k, y: (180 + pose.y) * k)
        tete.scaleBy(x: pose.sx, y: pose.sy)
        tete.translateBy(x: -100 * k, y: -180 * k)

        let disques: [(Double, Color)] = [(80, peau), (72, chair), (46, halo), (33, coeur)]
        for (rayon, couleur) in disques {
            tete.fill(
                Path(ellipseIn: CGRect(x: (100 - rayon) * k, y: (100 - rayon) * k, width: 2 * rayon * k, height: 2 * rayon * k)),
                with: .color(couleur)
            )
        }

        for i in 0..<12 {
            let angle = Double(i) * 30 * Double.pi / 180
            var graine = tete
            graine.translateBy(x: (100 + 59 * sin(angle)) * k, y: (100 - 59 * cos(angle)) * k)
            graine.rotate(by: .radians(angle))
            graine.fill(
                Path(ellipseIn: CGRect(x: -3.2 * k, y: -6.8 * k, width: 6.4 * k, height: 13.6 * k)),
                with: .color(peau)
            )
        }

        for cote in [-1.0, 1.0] {
            var oeil = tete
            oeil.translateBy(x: (100 + cote * 12) * k, y: 97 * k)
            oeil.scaleBy(x: 1, y: yeux)
            oeil.fill(
                Path(ellipseIn: CGRect(x: -5.2 * k, y: -6.4 * k, width: 10.4 * k, height: 12.8 * k)),
                with: .color(encre)
            )
            oeil.fill(
                Path(ellipseIn: CGRect(x: (2 - 1.9) * k, y: (-2.6 - 1.9) * k, width: 3.8 * k, height: 3.8 * k)),
                with: .color(.white)
            )
        }

        var sourire = Path()
        sourire.move(to: CGPoint(x: 94 * k, y: 108 * k))
        sourire.addQuadCurve(to: CGPoint(x: 106 * k, y: 108 * k), control: CGPoint(x: 100 * k, y: 114 * k))
        tete.stroke(sourire, with: .color(encre), style: StrokeStyle(lineWidth: 2.6 * k, lineCap: .round))
    }
}

// MARK: - Halo tournant de la feuille Premium

/// Le halo derrière la mascotte de la feuille Premium : un arc de lumière
/// verte, flou, qui fait un tour en 3,6 s. Il déborde de 14 pt autour d'elle.
/// Immobile sous « Réduire les animations ».
struct KiwiMascotteHalo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.estOngletActif) private var estOngletActif

    private var arc: some View {
        Circle()
            .fill(
                AngularGradient(
                    stops: [
                        Gradient.Stop(color: Color(hex: "9FD46F").opacity(0), location: 0),
                        Gradient.Stop(color: Color(hex: "9FD46F").opacity(0.9), location: 0.225),
                        Gradient.Stop(color: Color(hex: "5DA838").opacity(0), location: 0.45),
                        Gradient.Stop(color: Color(hex: "5DA838").opacity(0), location: 1),
                    ],
                    center: .center,
                    angle: .degrees(-90)
                )
            )
            .padding(-14)
            .blur(radius: 8)
    }

    var body: some View {
        Group {
            if reduceMotion {
                arc
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !estOngletActif)) { chrono in
                    let tour = (chrono.date.timeIntervalSinceReferenceDate / 3.6).truncatingRemainder(dividingBy: 1)
                    arc.rotationEffect(.degrees(tour * 360))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
