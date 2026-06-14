import SwiftUI

// MARK: - Mon évolution (Bilan section)
//
// "Futur toi" : avatar actuel (selon la morphologie choisie) → projection à
// 2 mois si le plan est suivi. La projection se rapproche de la cible
// (lean-athletic) à mesure que l'adhésion au plan augmente (dopamine).
struct MonEvolutionSection: View {
    let profile: UserProfile
    /// Ouvre le sélecteur d'avatar (état vide ou bouton « Modifier »).
    var onChooseAvatar: () -> Void

    private var hasAvatar: Bool { !profile.avatarKey.isEmpty }

    private var bmi: Double {
        HealthCalculator.calculateBMI(weightKg: profile.weightDouble, heightCm: profile.heightDouble) ?? 24
    }

    private var current: AvatarVariant {
        AvatarVariant(key: profile.avatarKey)
            ?? AvatarLibrary.bestGuess(gender: profile.gender, bmi: bmi, activity: profile.strengthTraining)
    }

    private var adherence: Double { PlanProgressStore.adherence }

    /// Projection : on garantit une amélioration visible (plancher 0.4) qui
    /// s'accentue avec l'adhésion réelle au plan.
    private var projected: AvatarVariant {
        AvatarLibrary.projection(from: current, adherence: min(1.0, 0.4 + 0.6 * adherence))
    }

    private var improves: Bool { projected != current }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            header

            if hasAvatar {
                avatarsRow
                adherenceBlock
                suiviButton
            } else {
                emptyState
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: "figure.stand")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.healthMapBlue)
                .accessibilityHidden(true)

            Text("Mon évolution")
                .font(Theme.headlineFont)
                .foregroundStyle(Color.healthMapText)

            Spacer()

            if hasAvatar {
                Button {
                    HapticService.shared.selection()
                    onChooseAvatar()
                } label: {
                    Text("Modifier")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
            }
        }
    }

    // MARK: Empty state (avatar non choisi)
    private var emptyState: some View {
        VStack(spacing: Theme.spacingMD) {
            AvatarImageView(variant: current, height: 130)
                .opacity(0.45)

            Text("Choisis l'avatar qui te ressemble pour découvrir à quoi tu pourrais ressembler en suivant ton plan.")
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                HapticService.shared.primary()
                onChooseAvatar()
            } label: {
                Text("Choisir mon avatar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(LinearGradient.healthMapBrand)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            }
            .buttonStyle(.healthMapPressed)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Avatars row (aujourd'hui → projection)
    private var avatarsRow: some View {
        HStack(alignment: .center, spacing: Theme.spacingSM) {
            avatarColumn(title: "Aujourd'hui", variant: current, tint: Color.healthMapSecondary)

            VStack(spacing: 2) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.healthMapBlue)
                    .accessibilityHidden(true)
                Text("2 mois")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.healthMapMuted)
            }
            .frame(width: 46)

            avatarColumn(title: improves ? "Dans 2 mois" : "Ton objectif",
                         variant: projected, tint: Color.scoreExcellent)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(improves
            ? "Aujourd'hui à gauche, ta projection dans deux mois à droite si tu suis ton plan."
            : "Tu es déjà proche de ton objectif.")
    }

    private func avatarColumn(title: String, variant: AvatarVariant, tint: Color) -> some View {
        VStack(spacing: Theme.spacingXS) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
            AvatarImageView(variant: variant, height: 150)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                .fill(Color.healthMapBackground)
        )
    }

    // MARK: Adherence gauge
    private var adherenceBlock: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            HStack {
                Text("Adhésion à ton plan")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                Spacer()
                Text("\(Int((adherence * 100).rounded()))\u{202F}%")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapText)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.healthMapMuted.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient.healthMapBrand)
                        .frame(width: max(geo.size.width * adherence, 6))
                }
            }
            .frame(height: 10)

            Text(adherenceCaption)
                .font(.system(size: 11))
                .foregroundStyle(Color.healthMapMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var adherenceCaption: String {
        if adherence >= 0.8 { return "Tu es sur la bonne voie — continue comme ça\u{202F}!" }
        if adherence >= 0.4 { return "Plus tu suis ton plan, plus tu t'en rapproches." }
        return "Coche les actions de ton plan pour faire évoluer ta projection."
    }

    // MARK: CTA vers le Suivi
    private var suiviButton: some View {
        Button {
            HapticService.shared.tap()
            NotificationCenter.default.post(
                name: .healthmapNavigateToTab,
                object: NavCardDestination.suivi.rawValue
            )
        } label: {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Voir mon suivi")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.healthMapBlue)
            .padding(.horizontal, Theme.spacingMD)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.healthMapBlue.opacity(Theme.opacityLight))
            )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityHint("Ouvre l'onglet Suivi.")
    }
}
