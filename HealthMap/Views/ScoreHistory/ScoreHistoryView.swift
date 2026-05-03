import SwiftUI
import Charts

// MARK: - Score History View (evolution du score)
struct ScoreHistoryView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var history: [ScoreSnapshot] = []
    @State private var isLoading = true
    @State private var scoreDeltaInfo: (delta: Int, weeks: Int, text: String)?

    var body: some View {
        ZStack {
            Color.healthMapBackground.ignoresSafeArea()

            if isLoading {
                VStack(spacing: Theme.spacingMD) {
                    ProgressView()
                        .tint(Color.healthMapBlue)
                    Text("Chargement de l'historique...")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: Theme.spacingLG) {
                        // Delta card
                        if let info = scoreDeltaInfo, history.count >= 2 {
                            deltaCard(delta: info.delta, text: info.text)
                        }

                        // Chart
                        if history.count >= 2 {
                            chartSection
                        } else {
                            emptyState
                        }

                        // History table
                        if !history.isEmpty {
                            historyTable
                        }
                    }
                    .padding(.vertical, Theme.spacingMD)
                }
            }
        }
        .navigationTitle("Evolution du score")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHistory() }
    }

    // MARK: - Delta Card
    private func deltaCard(delta: Int, text: String) -> some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "minus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(delta > 0 ? Color.scoreGood : delta < 0 ? Color.scoreDeficient : Color.healthMapMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(delta > 0 ? Color.scoreGood : delta < 0 ? Color.scoreDeficient : Color.healthMapMuted)

                if let first = history.sorted(by: { $0.date < $1.date }).first {
                    Text("Depuis le \(first.dateFormatted)")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                }
            }

            Spacer()
        }
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Chart
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Evolution")
                .font(Theme.captionBoldFont)
                .foregroundStyle(Color.healthMapSecondary)
                .padding(.horizontal, Theme.spacingLG)

            Chart {
                // Reference lines
                RuleMark(y: .value("Excellent", 75))
                    .foregroundStyle(Color.scoreGood.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))

                RuleMark(y: .value("Moyen", 50))
                    .foregroundStyle(Color.scoreLow.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))

                // Score line
                ForEach(history.sorted(by: { $0.date < $1.date })) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.date),
                        y: .value("Score", snapshot.score)
                    )
                    .foregroundStyle(Color.healthMapBlue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    PointMark(
                        x: .value("Date", snapshot.date),
                        y: .value("Score", snapshot.score)
                    )
                    .foregroundStyle(Color.healthMapBlue)
                    .symbolSize(40)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100])
            }
            .frame(height: 200)
            .padding(.horizontal, Theme.spacingLG)
        }
        .padding(.vertical, Theme.spacingSM)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40))
                .foregroundStyle(Color.healthMapMuted)

            Text("Pas encore assez de donnees")
                .font(Theme.headlineFont)
                .foregroundStyle(Color.healthMapText)

            Text("Complete tes suivis hebdomadaires pour voir l'evolution de ton score dans le temps.")
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)
        }
        .padding(Theme.spacingXL)
    }

    // MARK: - History Table
    private var historyTable: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Historique")
                .font(Theme.captionBoldFont)
                .foregroundStyle(Color.healthMapSecondary)

            ForEach(history.sorted(by: { $0.date > $1.date }).prefix(12)) { snapshot in
                HStack(spacing: Theme.spacingSM) {
                    Text(snapshot.dateFormatted)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapText)
                        .frame(width: 60, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.healthMapMuted.opacity(0.1))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.globalScoreColor(for: snapshot.score))
                                .frame(width: geo.size.width * CGFloat(snapshot.score) / 100.0)
                        }
                    }
                    .frame(height: 16)

                    Text("\(snapshot.score)%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.globalScoreColor(for: snapshot.score))
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Load History
    private func loadHistory() async {
        isLoading = true

        // Get userId for Supabase fetch
        let userId: String?
        if let session = await AuthService.shared.currentSession {
            userId = session.user.id.uuidString
        } else {
            userId = nil
        }

        if let userId {
            history = await ScoreHistoryService.shared.loadHistory(userId: userId)
        } else {
            // No session — fallback to UserDefaults only
            history = await ScoreHistoryService.shared.loadHistory(userId: "")
        }

        // Always add current score as latest if not already present today
        if dashboardVM.healthScore > 0 {
            let today = Calendar.current.startOfDay(for: Date())
            let hasTodayEntry = history.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
            if !hasTodayEntry {
                history.append(ScoreSnapshot(date: Date(), score: dashboardVM.healthScore, source: "current"))
            }
        }

        // Compute delta
        scoreDeltaInfo = ScoreHistoryService.shared.getScoreDelta(history: history)

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        ScoreHistoryView()
            .environmentObject(DashboardViewModel())
    }
}
