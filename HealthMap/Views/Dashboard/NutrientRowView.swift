import SwiftUI

// MARK: - Nutrient Row View (single nutrient with progress bar)
struct NutrientRowView: View {
    let nutrient: EnrichedNutrient
    var showChevron: Bool = true

    private var nutrientColor: Color {
        Color.nutrientColor(for: nutrient.id)
    }

    private var statusColor: Color {
        Color.scoreColor(for: nutrient.score)
    }

    // Mot d'état FR : mapping unique HealthScale (DESIGN-PAGES loi 4).
    private var statusLabel: String {
        HealthScale.nutrientLabel(for: nutrient.score)
    }

    var body: some View {
        HStack(spacing: Theme.spacingSM) {
            // Emoji
            Text(nutrient.emoji)
                .font(.system(size: 20))
                .frame(width: 28)

            // Name + progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(nutrient.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.healthMapText)

                    Spacer()

                    Text(statusLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.healthMapMuted.opacity(0.12))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(nutrientColor)
                            .frame(width: geo.size.width * CGFloat(nutrient.score) / 100.0, height: 6)
                            .overlay(
                                ColorBlindSafeOverlay(score: nutrient.score)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            )
                            .animation(.easeOut(duration: 0.8), value: nutrient.score)
                    }
                }
                .frame(height: 6)
            }

            // Score ring
            MiniScoreRing(score: nutrient.score, color: nutrientColor, size: 32)

            // Chevron
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .padding(.vertical, Theme.spacingSM)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nutrient.label), \(statusLabel)")
        .accessibilityValue("Score \(nutrient.score) sur 100")
        .accessibilityHint("Touche deux fois pour voir les details")
    }
}


#Preview {
    let sample = EnrichedNutrient(
        id: "vitD", label: "Vitamine D", emoji: "☀️", color: "FF9500",
        score: 45, status: "low", confidence: "high",
        signals: nil, verdict: nil, mecanisme: nil, comparaison: nil,
        signeManque: nil, solution: nil, hack: nil, synergie: nil
    )
    NutrientRowView(nutrient: sample)
        .padding()
}
