import SwiftUI

// MARK: - Blurred Section (PaywallGuard equivalent)
// Shows blurred preview of premium content with upgrade CTA
//
// Verre liquide (2 octobre 2026) : même grammaire que le contenu verrouillé de
// la maquette — flou 8, opacité 0,5, et la pastille de verre vert de 36 pt
// (cadenas + libellé) posée dessus. La feuille Premium grandit depuis elle.

struct BlurredSection<Content: View>: View {
    let isPremium: Bool
    let title: String
    @ViewBuilder let content: () -> Content

    @ObservedObject private var subscriptionService = SubscriptionService.shared

    private var shouldBlur: Bool {
        isPremium && !subscriptionService.isPremium
    }

    var body: some View {
        if shouldBlur {
            content()
                .blur(radius: 8)
                .opacity(0.5)
                .allowsHitTesting(false)
                .overlay {
                    // `title` dit ce que la zone débloque : c'est lui que porte
                    // la pastille (« Voir ta courbe » sur la maquette).
                    PremiumPastille(titre: title, zone: "generic")
                        .padding(.horizontal, Theme.spacingMD)
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
                    .blur(radius: 8)
                    .opacity(0.5)
                    .overlay {
                        HStack(spacing: 6) {
                            Image(systemName: "lock")
                                .font(.system(size: 15, weight: .semibold))
                                .accessibilityHidden(true)
                            Text("Premium")
                                .font(.dsSousTitreFort)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .verrePrincipal()
                    }
            }
            .buttonStyle(.plain)
            .feuillePremium(isPresented: $showPaywall)
        }
    }
}

extension View {
    func premiumGated(feature: String) -> some View {
        modifier(PremiumGateModifier(featureName: feature))
    }
}
