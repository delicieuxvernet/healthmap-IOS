import SwiftUI

// MARK: - Blurred Section (PaywallGuard equivalent)
// Shows blurred preview of premium content with upgrade CTA

struct BlurredSection<Content: View>: View {
    let isPremium: Bool
    let title: String
    @ViewBuilder let content: () -> Content

    @State private var showPaywall = false
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    private var shouldBlur: Bool {
        isPremium && !subscriptionService.isPremium
    }

    var body: some View {
        if shouldBlur {
            ZStack {
                content()
                    .blur(radius: 8)
                    .allowsHitTesting(false)

                // Overlay
                VStack(spacing: Theme.spacingSM) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.healthMapBlue)

                    Text(title)
                        .font(Theme.captionBoldFont)
                        .foregroundStyle(Color.healthMapText)
                        .multilineTextAlignment(.center)

                    Button {
                        showPaywall = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 12))
                            Text("Debloquer Premium")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.healthMapBlue)
                        .clipShape(Capsule())
                    }
                }
                .padding(Theme.spacingLG)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .padding(.horizontal, Theme.spacingMD)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .healthMapFullSheet()
            }
        } else {
            content()
        }
    }
}

// MARK: - Premium Gate Modifier
struct PremiumGateModifier: ViewModifier {
    let featureName: String
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        if subscriptionService.isPremium {
            content
        } else {
            Button {
                showPaywall = true
            } label: {
                content
                    .blur(radius: 6)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 16))
                            Text("Premium")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.healthMapBlue)
                    )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .healthMapFullSheet()
            }
        }
    }
}

extension View {
    func premiumGated(feature: String) -> some View {
        modifier(PremiumGateModifier(featureName: feature))
    }
}
