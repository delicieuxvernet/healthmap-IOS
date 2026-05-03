import SwiftUI

// MARK: - Celebration View (post-questionnaire)
// Shown after the questionnaire is submitted and analysis is ready.
// Displays confetti (respecting reduce motion), the animated score ring,
// and a CTA to view the full report.

struct CelebrationView: View {
    let score: Int
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var confettiPieces: [ConfettiPiece] = []

    private let confettiColors: [Color] = [
        .healthMapBlue,
        Color(hex: "5AC8FA"),
        Color(hex: "64D2FF"),
        Color(hex: "0056CC"),
        Color(hex: "4A90E2"),
    ]

    var body: some View {
        ZStack {
            Color.healthMapBackground
                .ignoresSafeArea()

            // Confetti layer (only when motion is allowed)
            if !reduceMotion {
                ForEach(confettiPieces) { piece in
                    ConfettiParticle(piece: piece)
                }
            }

            VStack(spacing: Theme.spacingLG) {
                Spacer()

                // Title
                VStack(spacing: Theme.spacingSM) {
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.healthMapBlue)
                        .scaleEffect(appeared ? 1.0 : 0.3)
                        .opacity(appeared ? 1.0 : 0)

                    Text("Ton bilan est pret !")
                        .font(Theme.titleFont)
                        .brandTitleKerning()
                        .foregroundStyle(Color.healthMapText)
                        .opacity(appeared ? 1.0 : 0)
                        .offset(y: appeared ? 0 : 20)
                }

                // Score ring
                ScoreRingView(score: score, size: 160, lineWidth: 12)
                    .scaleEffect(appeared ? 1.0 : 0.5)
                    .opacity(appeared ? 1.0 : 0)
                    .padding(.vertical, Theme.spacingMD)

                // Score label
                Text(scoreMessage)
                    .font(Theme.subheadlineFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacingXL)
                    .opacity(appeared ? 1.0 : 0)

                Spacer()

                // CTA
                Button {
                    onContinue()
                } label: {
                    Text("Voir mon bilan")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.healthMapBlue)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.bottom, Theme.spacingXL)
                .opacity(appeared ? 1.0 : 0)
            }
        }
        .onAppear {
            if reduceMotion {
                // Static display — no animation
                appeared = true
            } else {
                // Animated entry
                withAnimation(.healthMapSpring.delay(0.2)) {
                    appeared = true
                }
                spawnConfetti()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bilan pret. Score global \(score) sur 100.")
        .accessibilityAddTraits(.isStaticText)
    }

    private var scoreMessage: String {
        if score >= 75 {
            return "Excellent ! Ton equilibre nutritionnel est tres bon."
        } else if score >= 50 {
            return "Bon debut ! Quelques ajustements peuvent faire la difference."
        } else if score >= 40 {
            return "Des points a renforcer. Decouvre ton plan personnalise."
        } else {
            return "Plusieurs axes d'amelioration identifies. Ton plan t'attend."
        }
    }

    private func spawnConfetti() {
        confettiPieces = (0..<40).map { i in
            ConfettiPiece(
                id: i,
                color: confettiColors[i % confettiColors.count],
                startX: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                startY: CGFloat.random(in: -100 ... -20),
                endY: UIScreen.main.bounds.height + 50,
                rotation: Double.random(in: 0...360),
                delay: Double.random(in: 0...1.5),
                duration: Double.random(in: 2.0...4.0),
                size: CGFloat.random(in: 6...12)
            )
        }
    }
}

// MARK: - Confetti Data
private struct ConfettiPiece: Identifiable {
    let id: Int
    let color: Color
    let startX: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let rotation: Double
    let delay: Double
    let duration: Double
    let size: CGFloat
}

// MARK: - Confetti Particle
private struct ConfettiParticle: View {
    let piece: ConfettiPiece
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(piece.color)
            .frame(width: piece.size, height: piece.size * 0.6)
            .rotationEffect(.degrees(animate ? piece.rotation + 360 : piece.rotation))
            .position(
                x: piece.startX + (animate ? CGFloat.random(in: -30...30) : 0),
                y: animate ? piece.endY : piece.startY
            )
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(
                    .easeIn(duration: piece.duration)
                    .delay(piece.delay)
                ) {
                    animate = true
                }
            }
    }
}

#Preview {
    CelebrationView(score: 72) {
        print("Continue tapped")
    }
}
