import SwiftUI

// MARK: - Onboarding View (page de garde + 3 pages)
/// Refonte premium : fond animé (blobs lents, miroir du hero du site web),
/// page de garde avec la mascotte kiwi et le wordmark gradient, apparitions
/// douces étagées, CTA gradient avec ombre lumineuse.
/// Reduce Motion → tout est statique (fond figé, apparitions instantanées).
struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool
    @State private var currentPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let featurePages: [OnboardingPage] = [
        OnboardingPage(
            icon: "fork.knife",
            title: "Analyse ton alimentation",
            description: "Réponds à quelques questions sur ton mode de vie et ton alimentation. Notre algorithme évalue 10 nutriments essentiels."
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            title: "Détecte tes points faibles",
            description: "Découvre ton score nutritionnel global, les nutriments à renforcer et les interactions entre tes habitudes."
        ),
        OnboardingPage(
            icon: "list.clipboard",
            title: "Plan d'action personnalisé",
            description: "Reçois un plan sur mesure : aliments à privilégier, compléments recommandés et astuces pratiques."
        ),
    ]

    /// Page de garde + pages features
    private var pageCount: Int { featurePages.count + 1 }

    var body: some View {
        ZStack {
            // Fond chaud unifié, statique (WarmBackground)
            WarmBackground()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < pageCount - 1 {
                        Button("Passer") {
                            withAnimation(reduceMotion ? .none : .healthMapSpring) {
                                hasSeenOnboarding = true
                            }
                        }
                        .font(Theme.subheadlineFont)
                        .foregroundStyle(Color.healthMapSecondary)
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.top, Theme.spacingSM)
                .frame(height: 44)

                // Page content
                TabView(selection: $currentPage) {
                    OnboardingCoverPageView()
                        .tag(0)
                    ForEach(Array(featurePages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index + 1)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? .none : .healthMapSpring, value: currentPage)

                // Page indicators (capsule allongée pour la page active)
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage
                                  ? AnyShapeStyle(LinearGradient.healthMapBrand)
                                  : AnyShapeStyle(Color.healthMapMuted.opacity(0.35)))
                            .frame(width: index == currentPage ? 22 : 8, height: 8)
                            .animation(reduceMotion ? .none : .healthMapQuick, value: currentPage)
                    }
                }
                .padding(.bottom, Theme.spacingLG)

                // CTA — gradient brand + ombre lumineuse (miroir du CTA web)
                Button {
                    withAnimation(reduceMotion ? .none : .healthMapSpring) {
                        if currentPage < pageCount - 1 {
                            currentPage += 1
                        } else {
                            hasSeenOnboarding = true
                        }
                    }
                } label: {
                    HStack(spacing: Theme.spacingSM) {
                        Text(ctaLabel)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(LinearGradient.healthMapBrand)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .shadow(color: Color.healthMapBlue.opacity(Theme.shadowBrandGlow.opacity),
                            radius: Theme.shadowBrandGlow.radius,
                            x: 0,
                            y: Theme.shadowBrandGlow.y)
                }
                .buttonStyle(.healthMapPressed)
                .padding(.horizontal, Theme.spacingLG)
                .padding(.bottom, Theme.spacingXL)
            }
        }
    }

    private var ctaLabel: String {
        if currentPage == 0 { return "C'est parti" }
        return currentPage == pageCount - 1 ? "Commencer" : "Suivant"
    }
}

// MARK: - Data Model
private struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
}

// MARK: - Cover Page (page de garde)
/// Mascotte grande + wordmark gradient + promesse + marqueurs de confiance,
/// avec apparitions étagées douces.
private struct OnboardingCoverPageView: View {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            // Badge (miroir du badge hero web "Bilan nutritionnel personnalisé")
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                Text("Bilan nutritionnel personnalisé")
            }
            .pillStyle(color: .healthMapBlue)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(staged(0), value: appeared)

            // Mascotte kiwi — grande, joyeuse
            MascotView(mood: .happy, size: 160)
                .shadow(color: .black.opacity(Theme.opacityLight),
                        radius: Theme.shadowElevated.radius,
                        x: 0,
                        y: Theme.shadowElevated.y)
                .scaleEffect(appeared ? 1.0 : 0.7)
                .opacity(appeared ? 1 : 0)
                .animation(staged(0.08), value: appeared)

            // Wordmark — "Map" en gradient brand, comme le logo du site
            (Text("Kiwi").foregroundStyle(Color.healthMapText)
             + Text("o").foregroundStyle(LinearGradient.healthMapBrand))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .brandTitleKerning()
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(staged(0.16), value: appeared)

            // Promesse (copy du hero web)
            Text("Découvre la cause de tes symptômes. Réponds à quelques questions, reçois un plan micro-nutrition sur mesure.")
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(staged(0.24), value: appeared)

            // Marqueurs de confiance (miroir web : Gratuit / Données privées / 5 min)
            HStack(spacing: Theme.spacingMD) {
                trustMarker(icon: "shield.fill", text: "Gratuit")
                trustMarker(icon: "lock.fill", text: "Données privées")
                trustMarker(icon: "bolt.fill", text: "5 min")
            }
            .opacity(appeared ? 1 : 0)
            .animation(staged(0.32), value: appeared)

            Spacer()
            Spacer()
        }
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }

    private func trustMarker(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.healthMapMuted)
            Text(text)
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapSecondary)
        }
    }

    /// Apparition étagée — instantanée si Reduce Motion.
    private func staged(_ delay: Double) -> Animation? {
        reduceMotion ? nil : .healthMapSpring.delay(delay)
    }
}

// MARK: - Feature Page View
private struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            // Icône sur halo bleu, teinte gradient brand
            ZStack {
                Circle()
                    .fill(Color.healthMapBlueLight)
                    .frame(width: 120, height: 120)

                Image(systemName: page.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(LinearGradient.healthMapBrand)
            }
            .shadow(color: Color.healthMapBlue.opacity(Theme.opacityStrong),
                    radius: Theme.shadowFloating.radius,
                    x: 0,
                    y: Theme.shadowFloating.y)
            .scaleEffect(appeared ? 1.0 : 0.6)
            .opacity(appeared ? 1 : 0)
            .animation(staged(0), value: appeared)

            // Title
            Text(page.title)
                .font(Theme.titleFont)
                .brandTitleKerning()
                .foregroundStyle(Color.healthMapText)
                .multilineTextAlignment(.center)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .animation(staged(0.10), value: appeared)

            // Description
            Text(page.description)
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .animation(staged(0.18), value: appeared)

            Spacer()
            Spacer()
        }
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }

    /// Apparition étagée — instantanée si Reduce Motion.
    private func staged(_ delay: Double) -> Animation? {
        reduceMotion ? nil : .healthMapSpring.delay(delay)
    }
}

#Preview {
    OnboardingView(hasSeenOnboarding: .constant(false))
}
