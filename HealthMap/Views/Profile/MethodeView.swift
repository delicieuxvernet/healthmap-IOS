import SwiftUI

// MARK: - Methode View (educational transparency page)
struct MethodeView: View {
    var body: some View {
        ZStack {
            Color.healthMapBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.spacingLG) {
                    headerSection
                    stepsSection
                    interactionsSection
                    scoringSection
                    limitationsSection
                }
                .padding(.vertical, Theme.spacingMD)
                .padding(.bottom, Theme.spacingXL)
            }
        }
        .navigationTitle("Notre methode")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: Theme.spacingSM) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40))
                .foregroundStyle(Color.healthMapBlue)
                .frame(width: 72, height: 72)
                .background(Color.healthMapBlue.opacity(0.12))
                .clipShape(Circle())

            Text("Comment ca marche ?")
                .font(Theme.titleFont)
                .foregroundStyle(Color.healthMapText)
                .multilineTextAlignment(.center)

            Text("Transparence totale sur notre algorithme")
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.top, Theme.spacingSM)
    }

    // MARK: - 4 Steps (vertical timeline)
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Les 4 etapes", icon: "arrow.triangle.swap")

            VStack(spacing: 0) {
                stepCard(
                    number: 1,
                    title: "Questionnaire",
                    icon: "clipboard.fill",
                    description: "Tu reponds a des questions sur ton alimentation, mode de vie et sante.",
                    color: .healthMapBlue,
                    isLast: false
                )
                stepCard(
                    number: 2,
                    title: "Calcul local",
                    icon: "function",
                    description: "Notre algorithme calcule tes scores NAR pour 10 nutriments essentiels, 100% deterministe.",
                    color: .nutrientOmega3,
                    isLast: false
                )
                stepCard(
                    number: 3,
                    title: "Analyse IA",
                    icon: "brain",
                    description: "Claude analyse ton profil et genere des recommandations personnalisees (temperature=0).",
                    color: .accentIndigo,
                    isLast: false
                )
                stepCard(
                    number: 4,
                    title: "Ton bilan",
                    icon: "chart.bar.fill",
                    description: "Tu recois un score global, tes nutriments a renforcer, et un plan d'action concret.",
                    color: .scoreGood,
                    isLast: true
                )
            }
            .padding(Theme.cardPadding)
            .background(Color.healthMapCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(Theme.cardShadowOpacity), radius: Theme.cardShadowRadius, x: 0, y: 2)
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    private func stepCard(number: Int, title: String, icon: String, description: String, color: Color, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM + 4) {
            // Timeline column
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Text("\(number)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.healthMapMuted.opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 36)

            // Content
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)
                }

                Text(description)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : Theme.spacingMD)
        }
    }

    // MARK: - 6 Coded Interactions
    private var interactionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "6 Interactions codees", icon: "link")

            VStack(spacing: Theme.spacingSM) {
                interactionCard(
                    emoji: "\u{2615}\u{1FA78}",
                    title: "Cafeine + Fer",
                    description: "Les tannins du cafe bloquent l'absorption du fer jusqu'a 60%",
                    source: "Morck et al., 1983"
                )
                interactionCard(
                    emoji: "\u{1F48A}\u{1F534}",
                    title: "IPP + B12",
                    description: "Les inhibiteurs de pompe a protons reduisent l'absorption de la B12",
                    source: "Lam et al., JAMA 2013"
                )
                interactionCard(
                    emoji: "\u{1F48A}\u{26A1}",
                    title: "Metformine + B12",
                    description: "La metformine reduit l'absorption intestinale de la B12 de 30%",
                    source: "Aroda et al., JCEM 2016"
                )
                interactionCard(
                    emoji: "\u{1F48A}\u{1F6E1}\u{FE0F}",
                    title: "Contraceptif + Zinc/Mag",
                    description: "La pilule augmente l'excretion du zinc et magnesium",
                    source: "Palmery et al., 2013"
                )
                interactionCard(
                    emoji: "\u{1F630}\u{26A1}",
                    title: "Stress + Magnesium",
                    description: "Le stress chronique augmente l'excretion urinaire du magnesium",
                    source: "Pickering et al., 2020"
                )
                interactionCard(
                    emoji: "\u{1F373}\u{1F34A}",
                    title: "Cuisson + VitC",
                    description: "La cuisson a haute temperature detruit 50-80% de la vitamine C",
                    source: "Lee & Kader, 2000"
                )
            }
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    private func interactionCard(emoji: String, title: String, description: String, source: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Text(emoji)
                .font(.system(size: 20))
                .frame(width: 36, alignment: .center)

            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(source)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.healthMapBlue)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.healthMapCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(Theme.cardShadowOpacity), radius: Theme.cardShadowRadius, x: 0, y: 2)
    }

    // MARK: - Scoring NAR
    private var scoringSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Scoring NAR", icon: "gauge.with.dots.needle.33percent")

            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                // Starting score
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.healthMapBlue)
                    Text("Chaque nutriment demarre a 70/100")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Color.healthMapText)
                }

                // Deductions
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scoreLow)
                    Text("Des deductions sont appliquees selon ton alimentation, mode de vie et interactions")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Color.healthMapText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Score ranges
                Divider()

                VStack(spacing: Theme.spacingSM) {
                    scoreRange(label: "Bon", range: ">= 75", color: .scoreExcellent)
                    scoreRange(label: "Adequat", range: "60 - 74", color: .scoreGood)
                    scoreRange(label: "Faible", range: "40 - 59", color: .scoreLow)
                    scoreRange(label: "A renforcer", range: "< 40", color: .scoreDeficient)
                }
            }
            .padding(Theme.cardPadding)
            .background(Color.healthMapCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(Theme.cardShadowOpacity), radius: Theme.cardShadowRadius, x: 0, y: 2)
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    private func scoreRange(label: String, range: String, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.healthMapText)

            Spacer()

            Text(range)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.healthMapSecondary)
        }
    }

    // MARK: - Limitations
    private var limitationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Limitations", icon: "exclamationmark.triangle")

            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                limitationRow(
                    icon: "stethoscope",
                    text: "Kiwio ne remplace pas un avis medical"
                )
                limitationRow(
                    icon: "chart.bar.xaxis",
                    text: "Les scores sont bases sur des estimations, pas des analyses sanguines"
                )
                limitationRow(
                    icon: "person.badge.shield.checkmark",
                    text: "Consulte un professionnel de sante pour toute decision medicale"
                )
            }
            .padding(Theme.cardPadding)
            .background(Color.scoreLow.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Color.scoreLow.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    private func limitationRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.scoreLow)
                .frame(width: 24, alignment: .center)

            Text(text)
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Section Header
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapBlue)
            Text(title)
                .font(Theme.headlineFont)
                .foregroundStyle(Color.healthMapText)
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.bottom, Theme.spacingSM)
    }
}

#Preview {
    NavigationStack {
        MethodeView()
    }
}
