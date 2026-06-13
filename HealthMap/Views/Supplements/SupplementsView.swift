import SwiftUI

// MARK: - Supplements View (engine-driven recommendations + matin/midi/soir schedule)
struct SupplementsView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel

    // Engine result computed from current scores + profile
    private var engineResult: SupplementEngineResult? {
        let scores = dashboardVM.nutrientScores
        guard !scores.isEmpty else { return nil }
        return SupplementEngine.generateRecommendations(
            scores: scores,
            profile: dashboardVM.profile
        )
    }

    // Fallback: AI schedule from analysis
    private var aiSchedule: SupplementsSchedule? {
        dashboardVM.aiAnalysis?.supplementsSchedule
    }

    private var hasEngineResults: Bool {
        guard let result = engineResult else { return false }
        return !result.topRecommendations.isEmpty
    }

    private var hasAISchedule: Bool {
        guard let schedule = aiSchedule else { return false }
        return !(schedule.morning ?? []).isEmpty
            || !(schedule.afternoon ?? []).isEmpty
            || !(schedule.evening ?? []).isEmpty
    }

    private var hasContent: Bool {
        hasEngineResults || hasAISchedule
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()
                    .ignoresSafeArea()

                if hasContent {
                    mainContent
                } else if dashboardVM.isLoadingAnalysis {
                    VStack(spacing: Theme.spacingMD) {
                        ProgressView()
                            .tint(Color.healthMapBlue)
                        Text("Chargement...")
                            .font(Theme.bodyFont)
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                } else {
                    emptyState
                }
            }
            .navigationTitle("Complements")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: Theme.spacingLG) {

                // Top 3 Recommendation Cards
                if let result = engineResult, !result.topRecommendations.isEmpty {
                    recommendationsSection(result.topRecommendations)
                }

                // Cost Summary
                if let result = engineResult, !result.topRecommendations.isEmpty {
                    costSummaryCard(result.cost)
                }

                // Interaction Warnings
                if let result = engineResult, !result.warnings.isEmpty {
                    interactionWarningsCard(result.warnings)
                }

                // Daily Schedule (engine-based or AI fallback)
                scheduleSection

                // Info card
                infoCard
            }
            .padding(.vertical, Theme.spacingMD)
        }
    }

    // MARK: - Recommendations Section
    private func recommendationsSection(_ recommendations: [SupplementRecommendation]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            // Section header
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.healthMapBlue)
                Text("Recommandations prioritaires")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapBlue)
            }
            .padding(.horizontal, Theme.spacingLG)

            ForEach(recommendations) { rec in
                recommendationCard(rec)
            }
        }
    }

    // MARK: - Recommendation Card
    private func recommendationCard(_ rec: SupplementRecommendation) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            // Header: emoji + nutrient name + score donut
            HStack(spacing: Theme.spacingSM) {
                Text(rec.nutrientEmoji)
                    .font(.system(size: 24))

                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.nutrientLabel)
                        .font(Theme.headlineFont)
                        .foregroundStyle(Color.healthMapText)

                    if let product = rec.bestProduct {
                        Text(product.name)
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                }

                Spacer()

                // Score donut
                scoreDonut(score: rec.score, color: rec.nutrientColor)
            }

            // Why text
            Text(rec.whyText)
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Product details
            if let product = rec.bestProduct {
                HStack(spacing: Theme.spacingSM) {
                    // Brand pill
                    Text(product.brand)
                        .pillStyle(color: rec.nutrientColor)

                    // Dosage
                    Text(product.dosage)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapMuted)

                    Spacer()

                    // Daily cost
                    Text(String(format: "%.2f EUR/j", product.dailyCost))
                        .font(Theme.captionBoldFont)
                        .foregroundStyle(Color.healthMapSecondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Score Donut
    private func scoreDonut(score: Int, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 4)
                .frame(width: 44, height: 44)

            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 44, height: 44)

            Text("\(score)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    // MARK: - Cost Summary Card
    private func costSummaryCard(_ cost: CostSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "eurosign.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.healthMapBlue)

                Text("Estimation cout mensuel")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapText)

                Spacer()
            }

            HStack(spacing: Theme.spacingMD) {
                // Value option
                VStack(spacing: 4) {
                    Text("Economique")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                    Text(String(format: "%.0f EUR", cost.valueTotal))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.healthMapText)
                    Text("/ mois")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapMuted)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.healthMapMuted.opacity(0.2))
                    .frame(width: 1, height: 50)

                // Premium option
                VStack(spacing: 4) {
                    Text("Premium")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                    Text(String(format: "%.0f EUR", cost.premiumTotal))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.healthMapBlue)
                    Text("/ mois")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Interaction Warnings Card
    private func interactionWarningsCard(_ warnings: [InteractionWarning]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentSky)

                Text("Interactions detectees")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.accentSky)
            }

            ForEach(warnings) { warning in
                HStack(alignment: .top, spacing: Theme.spacingSM) {
                    Text(warning.emoji)
                        .font(.system(size: 14))
                    Text(warning.message)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.accentSky.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Color.accentSky.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Schedule Section (engine or AI fallback)
    @ViewBuilder
    private var scheduleSection: some View {
        // Section header
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: "clock.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapBlue)
            Text("Planning quotidien")
                .font(Theme.captionBoldFont)
                .foregroundStyle(Color.healthMapBlue)
        }
        .padding(.horizontal, Theme.spacingLG)

        if let result = engineResult, !result.schedule.isEmpty {
            // Engine-based schedule
            ForEach(result.schedule) { group in
                engineTimeSlotCard(group: group)
            }
        } else if hasAISchedule {
            // AI fallback schedule — les entrées serveur sont des objets
            // {name, dose, ...} ou des chaînes : displayText gère les deux.
            if let morning = aiSchedule?.morning, !morning.isEmpty {
                timeSlotCard(
                    title: "Matin",
                    subtitle: "Au petit-dejeuner",
                    icon: "sunrise.fill",
                    color: .accentSky,
                    supplements: morning.map(\.displayText)
                )
            }
            if let afternoon = aiSchedule?.afternoon, !afternoon.isEmpty {
                timeSlotCard(
                    title: "Midi",
                    subtitle: "Au dejeuner",
                    icon: "sun.max.fill",
                    color: .healthMapBlue,
                    supplements: afternoon.map(\.displayText)
                )
            }
            if let evening = aiSchedule?.evening, !evening.isEmpty {
                timeSlotCard(
                    title: "Soir",
                    subtitle: "Au diner ou avant le coucher",
                    icon: "moon.fill",
                    color: .accentIndigo,
                    supplements: evening.map(\.displayText)
                )
            }

            // AI warnings
            if let aiWarnings = aiSchedule?.warnings, !aiWarnings.isEmpty {
                aiWarningsCard(aiWarnings)
            }
        }
    }

    // MARK: - Engine Time Slot Card
    private func engineTimeSlotCard(group: ScheduleGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            // Header
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: group.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(group.color)

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.label)
                        .font(Theme.headlineFont)
                        .foregroundStyle(Color.healthMapText)

                    Text(timingSubtitle(for: group.label))
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                }

                Spacer()

                Text("\(group.products.count)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(group.color)
                    .frame(width: 28, height: 28)
                    .background(group.color.opacity(0.12))
                    .clipShape(Circle())
            }

            // Product list
            VStack(spacing: 6) {
                ForEach(group.products) { product in
                    HStack(spacing: Theme.spacingSM) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(group.color.opacity(0.6))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(product.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.healthMapText)
                            Text(product.dosage)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.healthMapMuted)
                        }

                        Spacer()

                        Image(systemName: "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.healthMapMuted.opacity(0.3))
                    }
                    .padding(.vertical, 6)

                    if product.id != group.products.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.top, Theme.spacingSM)
        }
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    private func timingSubtitle(for group: String) -> String {
        switch group {
        case "Matin": return "Au petit-dejeuner"
        case "Midi": return "Au dejeuner"
        case "Soir": return "Au diner ou avant le coucher"
        default: return ""
        }
    }

    // MARK: - AI Fallback Time Slot Card
    private func timeSlotCard(title: String, subtitle: String, icon: String, color: Color, supplements: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            // Header
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.headlineFont)
                        .foregroundStyle(Color.healthMapText)

                    Text(subtitle)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                }

                Spacer()

                Text("\(supplements.count)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12))
                    .clipShape(Circle())
            }

            // Supplement list
            VStack(spacing: 6) {
                ForEach(supplements, id: \.self) { supp in
                    HStack(spacing: Theme.spacingSM) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(color.opacity(0.6))

                        Text(supp)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.healthMapText)

                        Spacer()

                        Image(systemName: "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.healthMapMuted.opacity(0.3))
                    }
                    .padding(.vertical, 6)

                    if supp != supplements.last {
                        Divider()
                    }
                }
            }
            .padding(.top, Theme.spacingSM)
        }
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - AI Warnings Card (fallback)
    private func aiWarningsCard(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentSky)

                Text("Precautions")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.accentSky)
            }

            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: Theme.spacingSM) {
                    Text("•")
                        .foregroundStyle(Color.accentSky)
                    Text(warning)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.accentSky.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Color.accentSky.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Info Card
    private var infoCard: some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.healthMapBlue)

            Text("Ce planning est une suggestion basee sur ton profil. Consulte toujours un professionnel de sante avant de commencer une supplementation.")
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.healthMapBlueLight.opacity(0.5))
        )
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "pills")
                .font(.system(size: 48))
                .foregroundStyle(Color.healthMapMuted)

            Text("Aucun complement recommande")
                .font(Theme.headlineFont)
                .foregroundStyle(Color.healthMapText)

            Text("Ton analyse n'a pas identifie de complements necessaires, ou l'analyse IA n'a pas encore ete effectuee.")
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)
        }
    }
}

#Preview {
    SupplementsView()
        .environmentObject(DashboardViewModel())
}
