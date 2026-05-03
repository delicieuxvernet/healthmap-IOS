import SwiftUI

// MARK: - Interaction Card View ("ta cafeine bloque ton fer")
struct InteractionCardView: View {
    let interaction: InteractionDetected

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            // Header
            Button {
                withAnimation(reduceMotion ? .none : .healthMapSpring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Theme.spacingSM) {
                    Text(interaction.emoji ?? "⚠️")
                        .font(.system(size: 22))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(interaction.titre ?? "Interaction detectee")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.healthMapText)
                            .multilineTextAlignment(.leading)

                        // Nutrient pills
                        if !interaction.resolvedNutrients.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(interaction.resolvedNutrients, id: \.self) { nutrient in
                                    Text(nutrient)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.healthMapBlue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.healthMapBlueLight)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.healthMapMuted)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.healthMapPressed)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    if let explication = interaction.explication {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Explication", systemImage: "info.circle")
                                .font(Theme.captionBoldFont)
                                .foregroundStyle(Color.healthMapSecondary)

                            Text(explication)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Color.healthMapText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let solution = interaction.solution {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Solution", systemImage: "lightbulb.fill")
                                .font(Theme.captionBoldFont)
                                .foregroundStyle(Color.healthMapBlue)

                            Text(solution)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Color.healthMapText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, Theme.spacingSM)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.healthMapCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Color.healthMapMuted.opacity(0.12), lineWidth: 1)
        )
    }
}

#Preview {
    InteractionCardView(
        interaction: InteractionDetected(
            titre: "Ta cafeine bloque ton fer",
            emoji: "☕",
            nutriments: nil,
            nutrimentsConcernes: ["iron", "vitC"],
            explication: "La cafeine inhibe l'absorption du fer non-heminique de 60%.",
            solution: "Attends 2h apres un repas riche en fer avant de boire du cafe."
        )
    )
    .padding()
}
