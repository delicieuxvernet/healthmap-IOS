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
                    Text(isRetrying ? "Nouvel essai..." : "Reessayer")
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

            Spacer()
        }
        .padding(.horizontal, Theme.spacingLG)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Analysis Retry Banner (compact)
/// Bandeau compact affiché EN HAUT du dashboard quand l'analyse IA a échoué
/// mais que les scores locaux (HealthCalculator) sont disponibles : le bilan
/// reste entièrement utilisable, on propose simplement de relancer l'analyse.
/// (À la différence d'AnalysisErrorRetryView, qui remplace tout l'écran et ne
/// sert plus que lorsqu'on n'a RIEN de local à montrer.)
struct AnalysisRetryBanner: View {
    let message: String
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.healthMapBlue)
                    .accessibilityHidden(true)

                Text("Analyse IA indisponible")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapText)

                Spacer()
            }

            Text(message)
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onRetry()
            } label: {
                HStack(spacing: 6) {
                    if isRetrying {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(isRetrying ? "Nouvel essai..." : "Reessayer")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.spacingMD)
                .frame(minHeight: 44) // touch target HIG
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                        .fill(Color.healthMapBlue)
                )
            }
            .buttonStyle(.healthMapPressed)
            .disabled(isRetrying)
            .accessibilityHint("Relance le chargement de ton analyse nutritionnelle.")
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.healthMapBlueLight.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Color.healthMapBlue.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Nutrient Watch Card (Bilan bloc 3 — « À surveiller »)
/// Carte jumelle d'un nutriment à surveiller (DESIGN-PAGES §1 bloc 3).
/// Sources : label canonique (NutrientData) EN DÉBUT de titre (F-pattern),
/// mot d'état HealthScale.nutrientLabel + couleur HealthScale à droite
/// (lois 3 & 4), verdict IA 1 ligne max si disponible (loi 9), grande jauge
/// (largeur = score %, marqueur fixe « zone visée » à 70 % — loi 5), bouton
/// glass « Pourquoi ? » → fiche nutriment (loi 10).
struct NutrientWatchCard: View {
    let nutrient: EnrichedNutrient
    let onWhy: () -> Void

    private var statusColor: Color {
        Color.scoreColor(for: nutrient.score)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            // Nom EN DÉBUT + mot d'état coloré à droite
            HStack(spacing: Theme.spacingSM) {
                Text("\(nutrient.label) \(nutrient.emoji)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                    .lineLimit(1)

                Spacer()

                Text(HealthScale.nutrientLabel(for: nutrient.score))
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(statusColor)
            }

            // Verdict IA — texte libre : 1 ligne max en carte (loi 9)
            if let verdict = nutrient.verdict, !verdict.isEmpty {
                Text(verdict)
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Grande jauge animée 0 → score, marqueur zone visée à 70 %
            NutrientGaugeBar(score: nutrient.score)

            GlassPillButton(title: "Pourquoi\u{202F}?", action: onWhy)
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(nutrient.label), \(HealthScale.nutrientLabel(for: nutrient.score)), score \(nutrient.score) sur 100. Zone visée : 70.")
    }
}

// MARK: - Nutrient Gauge Bar (grande jauge — lois 5 & 17)
/// Jauge 10 pt (coins 5) : largeur = score %, couleur = échelle unique
/// (Color.scoreColor), marqueur vertical FIXE à 70 % (« zone visée »).
/// S'anime de 0 → score à l'apparition ; gelée si Reduce Motion.
struct NutrientGaugeBar: View {
    let score: Int

    @State private var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.healthMapMuted.opacity(Theme.opacityStrong))
                    .frame(height: 10)

                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.scoreColor(for: score))
                    .frame(
                        width: geo.size.width * CGFloat(score) / 100.0 * (animated ? 1 : 0),
                        height: 10
                    )

                // Marqueur « zone visée » fixe à 70 % (loi 5)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.healthMapText.opacity(Theme.opacityOverlay))
                    .frame(width: 2, height: 16)
                    .position(x: geo.size.width * 0.7, y: 5)
            }
        }
        .frame(height: 10)
        .padding(.vertical, Theme.spacingXS)
        .onAppear {
            if reduceMotion {
                animated = true
            } else {
                withAnimation(.easeOut(duration: 0.8).delay(0.1)) {
                    animated = true
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Insight Tile (Bilan bloc 5 — rangée symétrique)
/// Tuile de la rangée « Points forts » / « Interaction » : dimensions
/// strictement identiques (loi 6) via maxWidth .infinity + minHeight commun.
/// Texte : 2 lignes max (loi 9). Donnée manquante → le call-site fournit un
/// état utile, jamais une coquille vide (loi 11).
struct InsightTile: View {
    let header: String
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingXS) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Text(header)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .tracking(0.5)
            }

            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.healthMapText)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, minHeight: 88, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(tint.opacity(Theme.opacityLight))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(tint.opacity(Theme.opacityMedium), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(header). \(text)")
    }
}

// MARK: - All Nutrients Sheet (Bilan bloc 4)
/// Sheet « Tous mes nutriments » : la grille complète des 10 nutriments,
/// DÉPLACÉE depuis le mainContent du Bilan (DESIGN-PAGES §1 bloc 4 — la
/// grille n'est plus sur l'écran principal). Tap → fiche nutriment.
struct AllNutrientsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let nutrients: [EnrichedNutrient]
    let isPremium: Bool

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
            NutrientDetailSheet(nutrient: nutrient, isPremium: isPremium)
                .healthMapSheet(.large)
        }
    }
}
