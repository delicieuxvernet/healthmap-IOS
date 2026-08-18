import SwiftUI

// MARK: - Mini Score Ring (for nutrient rows)
struct MiniScoreRing: View {
    let score: Int
    let color: Color
    var size: CGFloat = 36
    /// Épaisseur de l'anneau. Défaut 3 (mini-anneau des listes) ; montée pour
    /// le héro de la fiche nutriment (grande jauge ~11 pt).
    var lineWidth: CGFloat = 3

    @State private var animatedProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))

            Text("\(score)")
                .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .onAppear {
            if reduceMotion {
                animatedProgress = CGFloat(score) / 100.0
            } else {
                withAnimation(.easeOut(duration: 0.8).delay(0.1)) {
                    animatedProgress = CGFloat(score) / 100.0
                }
            }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        MiniScoreRing(score: 85, color: .scoreGood)
        MiniScoreRing(score: 45, color: .scoreLow)
        MiniScoreRing(score: 25, color: .scoreDeficient)
    }
}
