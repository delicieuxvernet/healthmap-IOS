import SwiftUI

// MARK: - Checkin View (daily/weekly nutrition tracker)
struct CheckinView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @StateObject private var viewModel = CheckinViewModel()
    @ObservedObject private var gamification = GamificationService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.healthMapBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.spacingLG) {
                        // Summary dashboard 2x2
                        summaryGrid

                        // Tab picker
                        Picker("", selection: $viewModel.selectedTab) {
                            ForEach(CheckinViewModel.CheckinTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, Theme.spacingLG)

                        // Tab content
                        switch viewModel.selectedTab {
                        case .aujourdhui:
                            dailyTab
                        case .semaine:
                            weeklyTab
                        case .alimentation:
                            alimentationTab
                        }
                    }
                    .padding(.vertical, Theme.spacingMD)
                }
            }
            .navigationTitle("Mon Suivi")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                viewModel.loadActions(from: dashboardVM.profile, analysis: dashboardVM.aiAnalysis)
            }
        }
    }

    // MARK: - Summary Grid
    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            // Today completion
            summaryCard(
                icon: "checkmark.circle.fill",
                color: viewModel.dailyProgress >= 1.0 ? .scoreGood : .healthMapBlue,
                title: "Aujourd'hui",
                value: "\(viewModel.dailyCompleted)/\(viewModel.dailyTotal)",
                progress: viewModel.dailyProgress
            )

            // Week trend
            summaryCard(
                icon: "chart.bar.fill",
                color: .accentSky,
                title: "Tendance 7j",
                value: "\(viewModel.activeDaysThisWeek)j actifs",
                progress: Double(viewModel.activeDaysThisWeek) / 7.0
            )

            // Streak
            if !gamification.isZenMode {
                summaryCard(
                    icon: "flame.fill",
                    color: .accentSky,
                    title: "Serie",
                    value: "\(gamification.currentStreak) jours",
                    progress: min(1.0, Double(gamification.currentStreak) / 7.0)
                )
            }

            // Score
            summaryCard(
                icon: "heart.fill",
                color: .healthMapBlue,
                title: "Score",
                value: "\(dashboardVM.healthScore)/100",
                progress: Double(dashboardVM.healthScore) / 100.0
            )
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    private func summaryCard(icon: String, color: Color, title: String, value: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Spacer()
            }

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.healthMapText)

            // Mini progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * min(1, progress))
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    // MARK: - Daily Tab
    private var dailyTab: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            // Date header
            HStack {
                Text(todayFormatted)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                Spacer()
                Text("\(viewModel.dailyCompleted)/\(viewModel.dailyTotal)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.healthMapBlue)
            }
            .padding(.horizontal, Theme.spacingLG)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.healthMapMuted.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: geo.size.width * viewModel.dailyProgress)
                        .animation(.spring(response: 0.4), value: viewModel.dailyProgress)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, Theme.spacingLG)

            // Actions list
            VStack(spacing: 6) {
                ForEach(viewModel.dailyItems) { item in
                    actionRow(item: item) {
                        viewModel.toggleDaily(item)
                    }
                }
            }
            .padding(.horizontal, Theme.spacingLG)

            // Celebration
            if viewModel.showCelebration {
                celebrationCard
            }
        }
    }

    // MARK: - Weekly Tab
    private var weeklyTab: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            // Week header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cette semaine")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)
                    Text(viewModel.currentWeekLabel)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                }
                Spacer()
                Text("\(viewModel.weeklyCompleted)/\(viewModel.weeklyTotal)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.healthMapBlue)
            }
            .padding(.horizontal, Theme.spacingLG)

            // Progress
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.healthMapMuted.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.healthMapBlue)
                        .frame(width: geo.size.width * viewModel.weeklyProgress)
                        .animation(.spring(response: 0.4), value: viewModel.weeklyProgress)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, Theme.spacingLG)

            // Weekly actions
            VStack(spacing: 6) {
                ForEach(viewModel.weeklyActions) { action in
                    weeklyActionRow(action: action) {
                        viewModel.toggleWeekly(action)
                    }
                }
            }
            .padding(.horizontal, Theme.spacingLG)

            // Submit button
            if !viewModel.weekSubmitted && viewModel.weeklyCompleted > 0 {
                Button {
                    viewModel.submitWeek()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Valider ma semaine")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.healthMapBlue)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }
                .padding(.horizontal, Theme.spacingLG)
            }

            // History
            if !viewModel.weekHistory.isEmpty {
                historySection
            }
        }
    }

    // MARK: - Alimentation Tab
    private var alimentationTab: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(alignment: .top, spacing: Theme.spacingSM) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.healthMapBlue)
                Text("Note ce que tu manges au quotidien. En fin de semaine, tu verras l'impact reel sur tes points a renforcer.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.spacingSM)
            .background(Color.healthMapBlueLight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
            .padding(.horizontal, Theme.spacingLG)

            // Nutrient-based food groups
            let deficiencies = dashboardVM.deficiencies
            if deficiencies.isEmpty {
                VStack(spacing: Theme.spacingMD) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.scoreGood)
                    Text("Felicitations !")
                        .font(Theme.headlineFont)
                        .foregroundStyle(Color.healthMapText)
                    Text("Tous tes nutriments sont au vert. Continue comme ca !")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Color.healthMapSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.spacingXL)
            } else {
                ForEach(deficiencies.prefix(5)) { nutrient in
                    foodGroupCard(nutrient: nutrient)
                }
            }
        }
    }

    // MARK: - Helpers

    private func actionRow(item: CheckinViewModel.DailyAction, onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.completed ? Color.scoreGood : Color.healthMapMuted.opacity(0.4))

                Text(item.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(item.completed ? Color.healthMapSecondary : Color.healthMapText)
                    .strikethrough(item.completed)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: item.category.icon)
                        .font(.system(size: 9))
                    Text(item.category.rawValue)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(item.category.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(item.category.color.opacity(0.1))
                .clipShape(Capsule())
            }
            .padding(Theme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                    .fill(item.completed ? Color.scoreGood.opacity(0.04) : Color.healthMapCard)
            )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.text), \(item.completed ? "termine" : "a faire")")
        .accessibilityHint("Touche deux fois pour cocher ou decocher")
        .accessibilityAddTraits(.isButton)
    }

    private func weeklyActionRow(action: CheckinViewModel.WeeklyAction, onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: action.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(action.completed ? Color.scoreGood : Color.healthMapMuted.opacity(0.4))

                Text(action.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(action.completed ? Color.healthMapSecondary : Color.healthMapText)
                    .strikethrough(action.completed)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(Theme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                    .fill(Color.healthMapCard)
            )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action.text), \(action.completed ? "termine" : "a faire")")
        .accessibilityHint("Touche deux fois pour cocher ou decocher")
        .accessibilityAddTraits(.isButton)
    }

    private func foodGroupCard(nutrient: EnrichedNutrient) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack {
                Text(nutrient.emoji)
                    .font(.system(size: 20))
                Text(nutrient.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                Spacer()
                Text("\(nutrient.score)/100")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.scoreColor(for: nutrient.score))
            }

            if let sol = nutrient.solution?.action {
                Text(sol)
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    private var celebrationCard: some View {
        VStack(spacing: Theme.spacingSM) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.healthMapBlue)
            Text("Bravo !")
                .font(Theme.headlineFont)
                .foregroundStyle(Color.healthMapText)
            Text("Tu as complete toutes tes actions du jour !")
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapSecondary)
        }
        .padding(Theme.spacingLG)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.healthMapBlueLight)
        )
        .padding(.horizontal, Theme.spacingLG)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Historique")
                .font(Theme.captionBoldFont)
                .foregroundStyle(Color.healthMapSecondary)
                .padding(.horizontal, Theme.spacingLG)

            ForEach(viewModel.weekHistory.prefix(5)) { entry in
                HStack(spacing: Theme.spacingSM) {
                    Text(entry.weekLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.healthMapText)
                        .frame(width: 30)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.healthMapMuted.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.healthMapBlue)
                                .frame(width: geo.size.width * entry.progress)
                        }
                    }
                    .frame(height: 12)

                    Text("\(entry.completed)/\(entry.total)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                }
                .padding(.horizontal, Theme.spacingLG)
            }
        }
    }

    private var progressColor: Color {
        if viewModel.dailyProgress >= 1.0 { return .scoreGood }
        if viewModel.dailyProgress >= 0.5 { return .healthMapBlue }
        return .scoreLow
    }

    private var todayFormatted: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: Date()).capitalized
    }
}

#Preview {
    CheckinView()
        .environmentObject(DashboardViewModel())
}
