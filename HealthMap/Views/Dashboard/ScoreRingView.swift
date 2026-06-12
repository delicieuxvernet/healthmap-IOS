import SwiftUI

// MARK: - Score Ring (animated circular progress)
struct ScoreRingView: View {
    let score: Int
    var size: CGFloat = 180
    var lineWidth: CGFloat = 14

    @State private var animatedProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: CGFloat {
        CGFloat(score) / 100.0
    }

    private var scoreColor: Color {
        Color.globalScoreColor(for: score)
    }

    /// SF Symbol overlay for color-blind users — conveys the score bracket
    /// without relying on hue alone.
    private var scoreSymbol: String {
        // Aligné sur l'échelle unique HealthScale (loi 3) :
        // ≥ 70 « Solide » · 45-69 « Limite » · < 45 « À renforcer ».
        if score >= 70 { return "checkmark.circle" }
        if score >= 45 { return "arrow.up.circle" }
        return "exclamationmark.triangle"
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.healthMapMuted.opacity(0.15), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Animated progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [scoreColor.opacity(0.6), scoreColor],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))

            // Score text in center
            VStack(spacing: 2) {
                AnimatedNumberView(
                    targetValue: score,
                    font: .system(size: size * 0.22, weight: .bold, design: .rounded),
                    color: scoreColor
                )

                Text("/100")
                    .font(.system(size: size * 0.08, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.healthMapMuted)
            }

            // Color-blind safe symbol overlay (bottom-right)
            Image(systemName: scoreSymbol)
                .font(.system(size: size * 0.1, weight: .semibold))
                .foregroundStyle(scoreColor)
                .padding(4)
                .background(
                    Circle()
                        .fill(Color.healthMapCard)
                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                )
                .offset(x: size * 0.32, y: size * 0.32)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score global")
        .accessibilityValue("\(score) sur 100")
        .onAppear {
            if reduceMotion {
                animatedProgress = progress
            } else {
                withAnimation(.easeOut(duration: 1.2).delay(0.2)) {
                    animatedProgress = progress
                }
            }
        }
        .onChange(of: score) { _, _ in
            if reduceMotion {
                animatedProgress = progress
            } else {
                withAnimation(.easeOut(duration: 0.8)) {
                    animatedProgress = progress
                }
            }
        }
    }
}

// MARK: - Mini Score Ring (for nutrient rows)
struct MiniScoreRing: View {
    let score: Int
    let color: Color
    var size: CGFloat = 36

    @State private var animatedProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 3)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
    VStack(spacing: 32) {
        ScoreRingView(score: 72)
        HStack(spacing: 16) {
            MiniScoreRing(score: 85, color: .scoreGood)
            MiniScoreRing(score: 45, color: .scoreLow)
            MiniScoreRing(score: 25, color: .scoreDeficient)
        }
    }
}
