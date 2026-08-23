import SwiftUI

// MARK: - Dashboard Skeleton View
/// Affiché pendant le premier chargement du Dashboard (avant que l'analyse IA
/// soit disponible). Reproduit la structure exacte du mainContent avec
/// `.redacted(reason: .placeholder)` — l'utilisateur voit immédiatement à
/// quoi s'attendre plutôt qu'un spinner générique, et zéro layout shift au
/// remplissage.
///
/// Pattern inspiré de Apple Health / Fitness / Music.
struct DashboardSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacingLG) {
                // 1. Hero Score Card skeleton (ring + label + subtitle)
                HStack(spacing: Theme.spacingMD) {
                    Circle()
                        .fill(Color.dsAccent.opacity(0.15))
                        .frame(width: 88, height: 88)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.dsSecondaire.opacity(0.2))
                            .frame(height: 14)
                            .frame(maxWidth: 140)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.dsSecondaire.opacity(0.15))
                            .frame(height: 10)
                            .frame(maxWidth: 180)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.dsSecondaire.opacity(0.1))
                            .frame(height: 10)
                            .frame(maxWidth: 100)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Theme.spacingMD)
                .cardStyle()
                .padding(.horizontal, Theme.spacingLG)

                // 2. Highlight Grid 2x2 skeleton
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            Circle()
                                .fill(Color.dsSecondaire.opacity(0.15))
                                .frame(width: 28, height: 28)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.dsSecondaire.opacity(0.2))
                                .frame(height: 12)
                                .frame(maxWidth: 60)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.dsSecondaire.opacity(0.1))
                                .frame(height: 10)
                                .frame(maxWidth: 90)
                        }
                        .padding(Theme.spacingMD)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                    }
                }
                .padding(.horizontal, Theme.spacingLG)

                // 3. Nutrient rows skeleton (3 rows)
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: Theme.spacingSM) {
                            Circle()
                                .fill(Color.dsSecondaire.opacity(0.15))
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.dsSecondaire.opacity(0.2))
                                    .frame(height: 12)
                                    .frame(maxWidth: 120)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.dsSecondaire.opacity(0.12))
                                    .frame(height: 6)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(Theme.spacingMD)
                        .cardStyle()
                    }
                }
                .padding(.horizontal, Theme.spacingLG)

                Spacer(minLength: 40)
            }
            .padding(.vertical, Theme.spacingMD)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement de ton bilan en cours")
        .accessibilityAddTraits(.updatesFrequently)
        .overlay(alignment: .center) {
            // Subtle shimmer sweep respectant reduce motion
            if !reduceMotion {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.35),
                        Color.white.opacity(0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 200)
                .blendMode(.overlay)
                .offset(x: shimmerPhase)
                .onAppear {
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                        shimmerPhase = 400
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .clipped()
    }
}

#Preview {
    DashboardSkeletonView()
        .background(Color.dsFond)
}
