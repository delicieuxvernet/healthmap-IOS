import SwiftUI
import Charts

// MARK: - Score History View (evolution du score)
struct ScoreHistoryView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var history: [ScoreSnapshot] = []
    @State private var isLoading = true
    @State private var scoreDeltaInfo: (delta: Int, weeks: Int, text: String)?
    // Observé pour re-rendre l'écran quand `isPremium` bascule (achat depuis
    // la porte) : `premiumVisible` est alors réévalué immédiatement.
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    /// Famille 2 (verrouillé) : le dernier delta reste net (le présent), la
    /// trajectoire (courbe + tableau) est l'ordonnance. Rien à gater tant qu'il
    /// n'y a pas d'historique traçable — ni tant que le bilan n'est pas fait
    /// (`premiumVisible`, décision fondateur V12a).
    private var gateTrajectory: Bool { dashboardVM.premiumVisible && history.count >= 2 }

    var body: some View {
        ZStack {
            WarmBackground()

            if isLoading {
                VStack(spacing: Theme.spacingMD) {
                    KiwiLoader(size: 52)
                    Text("Chargement de l'historique...")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.dsSecondaire)
                }
            } else {
                ScrollView {
                    VStack(spacing: Theme.spacingLG) {
                        // Delta card — le présent, toujours net.
                        if let info = scoreDeltaInfo, history.count >= 2 {
                            deltaCard(delta: info.delta, text: info.text)
                        }

                        if history.count >= 2 {
                            if gateTrajectory {
                                // Famille 2 : silhouette de la courbe + du tableau
                                // sous flou, la trajectoire chiffrée est gatée.
                                GatedOverlay(intensity: .locked) {
                                    VStack(spacing: Theme.spacingLG) {
                                        chartSection
                                        historyTable
                                    }
                                }
                                UnlockDoor(
                                    icon: "chart.xyaxis.line",
                                    title: "Vois ta trajectoire complète",
                                    subtitle: "Ta courbe et ton historique, semaine après semaine",
                                    zone: "historique_score"
                                )
                                .padding(.horizontal, Theme.spacingLG)
                            } else {
                                chartSection
                                if !history.isEmpty {
                                    historyTable
                                }
                            }
                        } else {
                            emptyState
                            if !history.isEmpty {
                                historyTable
                            }
                        }
                    }
                    .padding(.vertical, Theme.spacingMD)
                }
            }
        }
        .navigationTitle("Évolution du score")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHistory() }
    }

    // MARK: - Delta Card
    private func deltaCard(delta: Int, text: String) -> some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "minus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(delta > 0 ? Color.scoreGood : delta < 0 ? Color.scoreDeficient : Color.dsSecondaire)

            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(delta > 0 ? Color.scoreGood : delta < 0 ? Color.scoreDeficient : Color.dsSecondaire)

                if let first = history.sorted(by: { $0.date < $1.date }).first {
                    Text("Depuis le \(first.dateFormatted)")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.dsSecondaire)
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
            Text("Évolution")
                .font(Theme.captionBoldFont)
                .foregroundStyle(Color.dsSecondaire)
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
                    .foregroundStyle(Color.dsAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    PointMark(
                        x: .value("Date", snapshot.date),
                        y: .value("Score", snapshot.score)
                    )
                    .foregroundStyle(Color.dsAccent)
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
            // Mascotte kiwi en mode "réflexion" — humanise l'état vide
            MascotView(mood: .thinking, size: 72)

            Text("Pas encore assez de données")
                .font(Theme.headlineFont)
                .foregroundStyle(Color.dsTexte)

            Text("Complète tes suivis hebdomadaires pour voir l'évolution de ton score dans le temps.")
                .font(Theme.bodyFont)
                .foregroundStyle(Color.dsSecondaire)
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
                .foregroundStyle(Color.dsSecondaire)

            ForEach(history.sorted(by: { $0.date > $1.date }).prefix(12)) { snapshot in
                HStack(spacing: Theme.spacingSM) {
                    Text(snapshot.dateFormatted)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.dsTexte)
                        .frame(width: 60, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.dsSecondaire.opacity(0.1))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.globalScoreColor(for: snapshot.score))
                                .frame(width: geo.size.width * CGFloat(snapshot.score) / 100.0)
                        }
                    }
                    .frame(height: 16)

                    Text("\(snapshot.score)%")
                        .font(.system(size: 13, weight: .bold, design: .default))
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
