import SwiftUI

// MARK: - Kiwi Contour Mark (splash épuré — direction validée juin 2026)
//
// Le logo kiwi (demi-fruit 3/4) réduit à ses CONTOURS, monochrome : ellipse
// extérieure (fruit), ellipse de la face coupée (crée le croissant de peau),
// anneau de pépins en pointillé, cœur. Aucun aplat de couleur, aucun détail
// (duvet, fibres, ombre retirés). Remplace le kiwi mascotte du LaunchScreen.
struct KiwiContourMark: View {
    var size: CGFloat = 96
    var color: Color = .kiwiCharcoal
    var lineWidth: CGFloat = 2.3

    /// Échelle depuis le repère de référence (viewBox 110) du logo en contour.
    private var s: CGFloat { size / 110 }

    var body: some View {
        ZStack {
            // Contour extérieur du fruit.
            Ellipse()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: 84 * s, height: 66 * s)
                .offset(x: 3 * s, y: 1 * s)

            // Face coupée (décalée vers le haut-gauche → croissant de peau bas-droite).
            Ellipse()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: 69 * s, height: 53 * s)
                .offset(x: -3 * s, y: -2 * s)

            // Anneau de pépins, en pointillé fin (ce qui fait lire « kiwi »).
            Ellipse()
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth * 1.15, lineCap: .round, dash: [0.6 * s, 6 * s]))
                .frame(width: 43 * s, height: 32 * s)
                .offset(x: -3 * s, y: -2 * s)

            // Cœur clair.
            Ellipse()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: 13 * s, height: 10 * s)
                .offset(x: -3 * s, y: -2 * s)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-16))
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Color(hex: "FBF6EF").ignoresSafeArea()
        VStack(spacing: 20) {
            KiwiContourMark(size: 96)
            Text("Kiwio").font(.system(size: 30, weight: .bold, design: .rounded))
        }
    }
}
