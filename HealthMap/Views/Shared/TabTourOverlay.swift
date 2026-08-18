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

    /// Les cinq onglets, dans l'ORDRE de la barre : Bilan · Suivi · Scan ·
    /// Plan · Compléments. Le 5e n'est plus « Profil » depuis que celui-ci est
    /// passé en feuille (P6) : décrire un onglet qui n'existe pas était la
    /// première chose que lisait un compte neuf.
    private let steps: [TourStep] = [
        TourStep(tabIndex: 0, icon: "heart.text.square", title: "Bilan",
                 description: "Ton bilan complet en un coup d'œil : score global, apports à renforcer et points d'attention personnalisés."),
        TourStep(tabIndex: 1, icon: "checkmark.circle", title: "Suivi",
                 description: "Enregistre tes habitudes quotidiennes (sommeil, hydratation, énergie) et suis ta progression semaine après semaine."),
        TourStep(tabIndex: 2, icon: "camera", title: "Scan",
                 description: "Maintiens le micro pour dicter ton repas, ou photographie ton assiette : tes calories et tes apports se comptent tout seuls."),
        TourStep(tabIndex: 3, icon: "list.clipboard", title: "Plan",
                 description: "Découvre les apports qui te manquent, avec des solutions alimentaires concrètes."),
        TourStep(tabIndex: 4, icon: "pills", title: "Compléments",
                 description: "Ce qu'il te faut vraiment : par l'assiette d'abord, en gélule si besoin, avec la bonne dose et le bon moment."),
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
                                .fill(index == currentStep ? Color.kiwiGreen : Color.white.opacity(0.3))
                                .frame(width: index == currentStep ? 10 : 7,
                                       height: index == currentStep ? 10 : 7)
                                .animation(reduceMotion ? .none : .healthMapQuick, value: currentStep)
                        }
                    }
                    .padding(.top, Theme.spacingSM)

                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.kiwiTint)
                            .frame(width: 72, height: 72)

                        Image(systemName: steps[currentStep].icon)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Color.kiwiGreenInk)
                    }

                    // Title
                    Text(steps[currentStep].title)
                        .font(Theme.sheetTitleFont)
                        .foregroundStyle(Color.kiwiCharcoal)

                    // Description
                    Text(steps[currentStep].description)
                        .font(.system(.subheadline))
                        .foregroundStyle(Color.healthMapSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.spacingMD)

                    // Step counter
                    Text("\(currentStep + 1) sur \(steps.count)")
                        .font(Theme.dataSecondaryFont)
                        .foregroundStyle(Color.healthMapMuted)

                    // Navigation buttons
                    HStack(spacing: Theme.spacingMD) {
                        // Skip button
                        Button {
                            dismiss()
                        } label: {
                            Text("Passer")
                                .font(Theme.ctaFont)
                                .foregroundStyle(Color.healthMapSecondary)
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
                                .background(Color.kiwiGreen)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        }
                    }
                    .padding(.horizontal, Theme.spacingSM)
                    .padding(.bottom, Theme.spacingSM)
                }
                .padding(Theme.spacingLG)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusLG, style: .continuous)
                        .fill(Color.healthMapCard)
                        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
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
