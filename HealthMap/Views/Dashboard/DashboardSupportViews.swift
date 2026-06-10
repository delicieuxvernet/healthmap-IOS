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

// MARK: - Highlight Card
struct HighlightCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.healthMapText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
