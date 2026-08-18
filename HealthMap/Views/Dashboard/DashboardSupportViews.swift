import SwiftUI

// MARK: - Analysis Error Retry View
/// Shown on the Dashboard when the very first AI analysis call fails and we
/// have nothing cached to display. Replaces the blank-dashboard failure mode
/// with an actionable retry card so the user always has a clear next step.
///
/// Brand rules:
///   - Icon `wifi.exclamationmark` is muted blue (Color.healthMapBlue) -- the
///     error state is recoverable, not dangerous, so we deliberately do NOT
///     use `Color.urgencyImmediate` (red is reserved for safety/medical
///     warnings per the audit checklist).
///   - The retry button is the standard primary blue, matching the rest of
///     the app -- keeps the visual language tight on the failure path.
struct AnalysisErrorRetryView: View {
    let message: String
    let isRetrying: Bool
    let onRetry: () -> Void
    /// Sortie de secours, quand cet écran est présenté en plein écran par la
    /// gate de première analyse : sans elle, un échec enferme l'utilisateur
    /// dans l'app. Absente sur la version affichée DANS l'onglet Bilan, où la
    /// barre d'onglets fait déjà office de sortie.
    var onExplorer: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(Color.healthMapBlue)
                .accessibilityHidden(true)

            VStack(spacing: Theme.spacingSM) {
                Text("Analyse indisponible")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.healthMapText)

                Text(message)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.spacingXL)
            }

            Button {
                onRetry()
            } label: {
                HStack(spacing: Theme.spacingSM) {
                    if isRetrying {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(isRetrying ? "Nouvel essai..." : "Réessayer")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(minWidth: 160)
                .padding(.vertical, 14)
                .padding(.horizontal, Theme.spacingLG)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .fill(Color.healthMapBlue)
                )
            }
            .disabled(isRetrying)
            .accessibilityHint("Relance le chargement de ton analyse nutritionnelle.")

            if let onExplorer {
                Button(action: onExplorer) {
                    Text("Explorer l'app en attendant")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.healthMapBlue)
                        .frame(minHeight: 44)
                        .padding(.horizontal, Theme.spacingLG)
                }
                .accessibilityHint("Ferme cet écran. Ton bilan continue de se préparer en arrière-plan.")
            }

            Spacer()
        }
        .padding(.horizontal, Theme.spacingLG)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}


// MARK: - All Nutrients Sheet (Bilan bloc 4)
/// Sheet « Tous mes nutriments » : la grille complète des 10 nutriments,
/// DÉPLACÉE depuis le mainContent du Bilan (DESIGN-PAGES §1 bloc 4 — la
/// grille n'est plus sur l'écran principal). Tap → fiche nutriment.
struct AllNutrientsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let nutrients: [EnrichedNutrient]

    @State private var selectedNutrient: EnrichedNutrient?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Theme.spacingSM), count: 3),
                    spacing: Theme.spacingSM
                ) {
                    ForEach(nutrients) { nutrient in
                        Button {
                            HapticService.shared.tap()
                            selectedNutrient = nutrient
                        } label: {
                            VStack(spacing: Theme.spacingXS) {
                                MiniScoreRing(
                                    score: nutrient.score,
                                    color: Color.nutrientColor(for: nutrient.id),
                                    size: 52
                                )

                                Text(nutrient.emoji)
                                    .font(.system(size: 16))

                                Text(nutrient.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.healthMapSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.spacingSM)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                                    .fill(Color.healthMapCard)
                            )
                        }
                        .buttonStyle(.healthMapPressed)
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.vertical, Theme.spacingMD)
            }
            .background(Color.healthMapBackground)
            .navigationTitle("Tous mes nutriments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.healthMapMuted)
                            // Zone tactile ≥ 44 pt RÉELLE (loi 20) — même fix
                            // que PaywallView : l'icône seule fait ~20 pt.
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel("Fermer")
                }
            }
        }
        .sheet(item: $selectedNutrient) { nutrient in
            // Premium : la fiche observe elle-même SubscriptionService.
            NutrientDetailSheet(nutrient: nutrient)
                .healthMapSheet(.large)
        }
    }
}
