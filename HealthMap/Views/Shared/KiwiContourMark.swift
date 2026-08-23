import SwiftUI

// MARK: - Kiwi Contour Mark (splash épuré — refonte 6 juil. 2026)
//
// Le vrai logo de l'app (le demi-kiwi 3/4 de l'icône) réduit à un TRAIT
// monochrome, contours uniquement, zéro aplat : l'ovale de la face coupée,
// une couronne de PÉPINS discrets (ovales pleins, plus le pointillé raté de la
// version précédente), de fines fibres rayonnantes qui font lire « tranche de
// kiwi », et le cœur clair au centre. Légèrement incliné, comme l'icône.
//
// La disposition radiale utilise l'astuce « aiguille d'horloge » : chaque pépin
// / fibre est décalé vers le haut puis tourné autour du centre du repère (le
// `.offset` ne déplace pas le cadre de layout, donc `.rotationEffect` pivote
// bien autour du centre du ZStack).
struct KiwiContourMark: View {
    var size: CGFloat = 96
    var color: Color = .dsTexte
    var lineWidth: CGFloat = 2.3

    /// Échelle depuis le repère de référence (110 pt) du dessin.
    private var s: CGFloat { size / 110 }
    private let seedCount = 10

    var body: some View {
        ZStack {
            // Fibres rayonnantes (chair du kiwi) — fines et discrètes, glissées
            // entre les pépins (décalage de 18°).
            ForEach(0..<seedCount, id: \.self) { i in
                Capsule()
                    .fill(color.opacity(0.36))
                    .frame(width: lineWidth * 0.5, height: 22 * s)
                    .offset(y: -23 * s)
                    .rotationEffect(.degrees(18 + Double(i) / Double(seedCount) * 360))
            }

            // Couronne de pépins — ovales pleins orientés radialement (ce qui
            // fait immédiatement lire « kiwi »).
            ForEach(0..<seedCount, id: \.self) { i in
                Ellipse()
                    .fill(color)
                    .frame(width: 5 * s, height: 9.2 * s)
                    .offset(y: -25 * s)
                    .rotationEffect(.degrees(Double(i) / Double(seedCount) * 360))
            }

            // Contour de la face coupée (l'ovale du fruit tranché).
            Ellipse()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: 96 * s, height: 74 * s)

            // Cœur clair au centre.
            Ellipse()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: 17 * s, height: 13 * s)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-15))
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Color(hex: "FBF6EF").ignoresSafeArea()
        VStack(spacing: 20) {
            KiwiContourMark(size: 104)
            Text("Kiwio").font(.system(size: 30, weight: .bold, design: .default))
        }
    }
}
