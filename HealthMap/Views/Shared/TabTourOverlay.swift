import SwiftUI

// MARK: - Tab Tour Step Model
private struct TourStep {
    let tabIndex: Int
    let icon: String
    let title: String
    let description: String
}

// MARK: - Tab Tour Overlay
struct TabTourOverlay: View {
    @Binding var isShowing: Bool
    @State private var currentStep = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Les cinq onglets, dans l'ORDRE de la barre (refonte 23 août 2026) :
    /// Journal · Progrès · Plan · Compléments · Réglages. Des objets, pas des
    /// concepts : c'est ce qu'un compte neuf doit lire en premier.
    private let steps: [TourStep] = [
        TourStep(tabIndex: 0, icon: "book.closed", title: "Journal",
                 description: "Ta journée en un regard : calories, macros, apports à renforcer et tes repas. Le bouton + ajoute un repas à la voix, en photo ou par recherche."),
        TourStep(tabIndex: 1, icon: "chart.xyaxis.line", title: "Progrès",
                 description: "Tes besoins couverts semaine après semaine, tes apports face à tes besoins et l'évolution de ce que tu ressens."),
        TourStep(tabIndex: 2, icon: "map", title: "Plan",
                 description: "Ce que tu veux régler, avec ses causes et ses solutions : nutrition, compléments, habitudes."),
        TourStep(tabIndex: 3, icon: "pills", title: "Compléments",
                 description: "Ce qu'il te faut vraiment : par l'assiette d'abord, en gélule si besoin, avec la bonne dose et le bon moment."),
        TourStep(tabIndex: 4, icon: "gearshape", title: "Réglages",
                 description: "Ton profil, ton abonnement, tes données et notre méthode, toujours au même endroit."),
    ]

    private var isLastStep: Bool { currentStep == steps.count - 1 }

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { } // Block taps through overlay

            VStack {
                Spacer()

                // Tooltip card
                VStack(spacing: Theme.spacingMD) {
                    // Progress indicator
                    HStack(spacing: 6) {
                        ForEach(0..<steps.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentStep ? Color.dsAccent : Color.white.opacity(0.3))
                                .frame(width: index == currentStep ? 10 : 7,
                                       height: index == currentStep ? 10 : 7)
                                .animation(reduceMotion ? .none : .healthMapQuick, value: currentStep)
                        }
                    }
                    .padding(.top, Theme.spacingSM)

                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.dsRemplissage)
                            .frame(width: 72, height: 72)

                        Image(systemName: steps[currentStep].icon)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Color.dsTexte)
                    }

                    // Title
                    Text(steps[currentStep].title)
                        .font(Theme.sheetTitleFont)
                        .foregroundStyle(Color.dsTexte)

                    // Description
                    Text(steps[currentStep].description)
                        .font(.system(.subheadline))
                        .foregroundStyle(Color.dsSecondaire)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.spacingMD)

                    // Step counter
                    Text("\(currentStep + 1) sur \(steps.count)")
                        .font(Theme.dataSecondaryFont)
                        .foregroundStyle(Color.dsSecondaire)

                    // Navigation buttons
                    HStack(spacing: Theme.spacingMD) {
                        // Skip button
                        Button {
                            dismiss()
                        } label: {
                            Text("Passer")
                                .font(Theme.ctaFont)
                                .foregroundStyle(Color.dsSecondaire)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }

                        // Next / Done button
                        Button {
                            if isLastStep {
                                dismiss()
                            } else {
                                withAnimation(reduceMotion ? .none : .healthMapSpring) {
                                    currentStep += 1
                                }
                            }
                        } label: {
                            Text(isLastStep ? "C'est parti !" : "Suivant")
                                .font(Theme.ctaFont)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.dsAccent)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        }
                    }
                    .padding(.horizontal, Theme.spacingSM)
                    .padding(.bottom, Theme.spacingSM)
                }
                .padding(Theme.spacingLG)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusLG, style: .continuous)
                        .fill(Color.dsCarte)
                        // (ombre retirée, refonte 23 août 2026)
                )
                .padding(.horizontal, Theme.spacingLG)
                .padding(.bottom, 100) // Above tab bar
            }
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Guide de navigation, étape \(currentStep + 1) sur \(steps.count)")
    }

    private func dismiss() {
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.25)) {
            isShowing = false
        }
    }
}
