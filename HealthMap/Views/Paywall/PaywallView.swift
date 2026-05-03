import SwiftUI
import RevenueCatUI

// MARK: - Paywall View (RevenueCatUI integration)
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            Color.healthMapBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom header
                paywallHeader

                // RevenueCat paywall
                PaywallContent()
            }
        }
    }

    // MARK: - Custom Header
    private var paywallHeader: some View {
        VStack(spacing: Theme.spacingMD) {
            // Close button
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.healthMapMuted)
                }
                .accessibilityLabel("Fermer")
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.top, Theme.spacingSM)

            // Branding
            VStack(spacing: Theme.spacingSM) {
                Image(systemName: "heart.text.clipboard")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.healthMapBlue)

                Text("HealthMap Premium")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.healthMapText)

                Text("Deverrouille ton potentiel sante complet")
                    .font(Theme.subheadlineFont)
                    .foregroundStyle(Color.healthMapSecondary)
            }

            // Features list
            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                featureRow(icon: "chart.bar.fill", text: "Analyse complete des 10 nutriments")
                featureRow(icon: "sparkles", text: "Analyse IA personnalisee")
                featureRow(icon: "list.bullet.clipboard.fill", text: "Plan d'action sur mesure")
                featureRow(icon: "pills.fill", text: "Planning complements optimise")
                featureRow(icon: "arrow.triangle.merge", text: "Detection des interactions")
            }
            .padding(.horizontal, Theme.spacingXL)
            .padding(.vertical, Theme.spacingSM)

            // Legal links (CGU / Privacy)
            HStack(spacing: 8) {
                Link("Conditions d'utilisation", destination: URL(string: "https://healthmap.fr/terms")!)
                Text("\u{00B7}")
                    .foregroundStyle(Color.healthMapMuted)
                Link("Politique de confidentialite", destination: URL(string: "https://healthmap.fr/privacy")!)
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.healthMapMuted)
            .padding(.bottom, Theme.spacingSM)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapBlue)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.healthMapText)

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.scoreGood)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Paywall Content (uses RevenueCatUI)
private struct PaywallContent: View {
    var body: some View {
        // RevenueCatUI will display the paywall configured in the RevenueCat dashboard
        // This is a placeholder that integrates with RevenueCat's PaywallView
        RevenueCatUI.PaywallView()
    }
}

// MARK: - Paywall Modifier (for presenting paywall conditionally)
struct PaywallModifier: ViewModifier {
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showPaywall = false

    let checkOnAppear: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                if checkOnAppear && !subscriptionService.isPremium {
                    showPaywall = true
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .healthMapFullSheet()
            }
    }
}

extension View {
    func presentPaywallIfNeeded(checkOnAppear: Bool = true) -> some View {
        modifier(PaywallModifier(checkOnAppear: checkOnAppear))
    }
}

#Preview {
    PaywallView()
}
