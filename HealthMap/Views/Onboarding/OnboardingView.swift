import SwiftUI

// MARK: - Onboarding View (3 pages)
struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool
    @State private var currentPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "fork.knife",
            title: "Analyse ton alimentation",
            description: "Reponds a quelques questions sur ton mode de vie et ton alimentation. Notre algorithme evalue 10 nutriments essentiels."
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            title: "Detecte tes points faibles",
            description: "Decouvre ton score nutritionnel global, les nutriments a renforcer et les interactions entre tes habitudes."
        ),
        OnboardingPage(
            icon: "list.clipboard",
            title: "Plan d'action personnalise",
            description: "Recois un plan sur mesure : aliments a privilegier, complements recommandes et astuces pratiques."
        ),
    ]

    var body: some View {
        ZStack {
            Color.healthMapBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
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
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? .none : .healthMapSpring, value: currentPage)

                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.healthMapBlue : Color.healthMapMuted.opacity(0.4))
                            .frame(width: index == currentPage ? 10 : 8,
                                   height: index == currentPage ? 10 : 8)
                            .animation(reduceMotion ? .none : .healthMapQuick, value: currentPage)
                    }
                }
                .padding(.bottom, Theme.spacingLG)

                // Action button
                Button {
                    withAnimation(reduceMotion ? .none : .healthMapSpring) {
                        if currentPage < pages.count - 1 {
                            currentPage += 1
                        } else {
                            hasSeenOnboarding = true
                        }
                    }
                } label: {
                    Text(currentPage == pages.count - 1 ? "Commencer" : "Suivant")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.healthMapBlue)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.bottom, Theme.spacingXL)
            }
        }
    }
}

// MARK: - Data Model
private struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
}

// MARK: - Single Page View
private struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.healthMapBlueLight)
                    .frame(width: 120, height: 120)

                Image(systemName: page.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(Color.healthMapBlue)
            }
            .scaleEffect(appeared ? 1.0 : 0.6)
            .opacity(appeared ? 1.0 : 0)

            // Title
            Text(page.title)
                .font(Theme.titleFont)
                .foregroundStyle(Color.healthMapText)
                .multilineTextAlignment(.center)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1.0 : 0)

            // Description
            Text(page.description)
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1.0 : 0)

            Spacer()
            Spacer()
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.healthMapSpring.delay(0.1)) {
                    appeared = true
                }
            }
        }
        .onDisappear {
            appeared = false
        }
    }
}

#Preview {
    OnboardingView(hasSeenOnboarding: .constant(false))
}
