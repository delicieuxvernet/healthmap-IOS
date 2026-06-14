import SwiftUI

// MARK: - Avatar image
/// Renders a morphology avatar from the asset catalog (transparent PNG).
struct AvatarImageView: View {
    let variant: AvatarVariant
    var height: CGFloat = 150

    var body: some View {
        Image(variant.imageName)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

// MARK: - Avatar picker
/// One-time (and re-pickable) screen asking the user which body matches them.
/// BMI alone can't tell muscle from fat, so we propose 3 candidates derived
/// from BMI + declared activity and let the user disambiguate.
struct AvatarPickerView: View {
    let profile: UserProfile
    /// Called with the chosen avatar key (e.g. "av_m_w45_m55").
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: AvatarVariant?

    private var bmi: Double {
        HealthCalculator.calculateBMI(weightKg: profile.weightDouble, heightCm: profile.heightDouble) ?? 24
    }
    private var candidates: [AvatarVariant] {
        AvatarLibrary.candidates(gender: profile.gender, bmi: bmi, activity: profile.strengthTraining)
    }

    var body: some View {
        ZStack {
            Color.healthMapBackground.ignoresSafeArea()

            VStack(spacing: Theme.spacingLG) {
                header

                Spacer(minLength: Theme.spacingMD)

                HStack(alignment: .top, spacing: Theme.spacingSM) {
                    ForEach(candidates, id: \.imageName) { variant in
                        candidateCard(variant)
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Theme.spacingMD)

                validateButton
            }
            .padding(.top, Theme.spacingXL)
        }
    }

    private var header: some View {
        VStack(spacing: Theme.spacingSM) {
            Text("Quel corps te ressemble le plus\u{202F}?")
                .font(Theme.titleFont)
                .brandTitleKerning()
                .foregroundStyle(Color.healthMapText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("D'après ta morphologie et ton activité, tu peux ressembler à l'un de ces trois. Choisis le plus proche — ton avatar évoluera ensuite avec toi.")
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    private func candidateCard(_ variant: AvatarVariant) -> some View {
        let isSelected = selected == variant
        return Button {
            HapticService.shared.selection()
            withAnimation(reduceMotion ? .none : .healthMapSpring) {
                selected = variant
            }
        } label: {
            VStack(spacing: Theme.spacingXS) {
                AvatarImageView(variant: variant, height: 150)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.healthMapBlue : Color.healthMapMuted.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.healthMapCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(isSelected ? Color.healthMapBlue : Color.healthMapMuted.opacity(Theme.opacityStrong),
                            lineWidth: isSelected ? 2.5 : 1)
            )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("Avatar \(variant.muscle >= 85 ? "musclé" : variant.muscle <= 25 ? "peu musclé" : "moyen"), corpulence \(variant.weight)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var validateButton: some View {
        Button {
            guard let selected else { return }
            HapticService.shared.success()
            onSelect(selected.imageName)
            dismiss()
        } label: {
            Text("C'est mon avatar")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    if selected == nil {
                        Color.healthMapMuted
                    } else {
                        LinearGradient.healthMapBrand
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .shadow(
                    color: selected == nil ? .clear : Color.healthMapBlue.opacity(Theme.shadowBrandGlow.opacity),
                    radius: Theme.shadowBrandGlow.radius, x: 0, y: Theme.shadowBrandGlow.y
                )
        }
        .buttonStyle(.healthMapPressed)
        .disabled(selected == nil)
        .padding(.horizontal, Theme.spacingLG)
        .padding(.bottom, Theme.spacingLG)
    }
}
