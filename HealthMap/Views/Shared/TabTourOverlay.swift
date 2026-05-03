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

    private let steps: [TourStep] = [
        TourStep(tabIndex: 0, icon: "heart.text.clipboard", title: "Bilan",
                 description: "Ton bilan sante complet en un coup d'oeil : score global, carences detectees et alertes personnalisees."),
        TourStep(tabIndex: 1, icon: "checkmark.circle", title: "Suivi",
                 description: "Enregistre tes habitudes quotidiennes (sommeil, hydratation, energie) et suis ta progression semaine apres semaine."),
        TourStep(tabIndex: 2, icon: "camera", title: "Scanner",
                 description: "Prends en photo ton assiette et l'IA analyse instantanement les nutriments de ton repas."),
        TourStep(tabIndex: 3, icon: "list.bullet.clipboard", title: "Mon Plan",
                 description: "Decouvre les nutriments qui te manquent, avec des solutions alimentaires concretes."),
        TourStep(tabIndex: 4, icon: "person.crop.circle", title: "Profil",
                 description: "Ton profil, tes badges, tes preferences et l'export de tes donnees."),
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
                                .fill(index == currentStep ? Color.healthMapBlue : Color.white.opacity(0.3))
                                .frame(width: index == currentStep ? 10 : 7,
                                       height: index == currentStep ? 10 : 7)
                                .animation(reduceMotion ? .none : .healthMapQuick, value: currentStep)
                        }
                    }
                    .padding(.top, Theme.spacingSM)

                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.healthMapBlueLight)
                            .frame(width: 72, height: 72)

                        Image(systemName: steps[currentStep].icon)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Color.healthMapBlue)
                    }

                    // Title
                    Text(steps[currentStep].title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.healthMapText)

                    // Description
                    Text(steps[currentStep].description)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.healthMapSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.spacingMD)

                    // Step counter
                    Text("\(currentStep + 1) sur \(steps.count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapMuted)

                    // Navigation buttons
                    HStack(spacing: Theme.spacingMD) {
                        // Skip button
                        Button {
                            dismiss()
                        } label: {
                            Text("Passer")
                                .font(.system(size: 15, weight: .medium))
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
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.healthMapBlue)
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
        .accessibilityLabel("Guide de navigation, etape \(currentStep + 1) sur \(steps.count)")
    }

    private func dismiss() {
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.25)) {
            isShowing = false
        }
    }
}
