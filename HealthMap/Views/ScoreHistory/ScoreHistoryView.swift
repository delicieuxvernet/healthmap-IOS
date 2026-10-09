import SwiftUI
import Charts
import Accessibility

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
            // Page poussée : le fond de verre de l'app, sous son voile.
            VerrePageFond()

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
                    .dsPolice(16, .bold)
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
        .dsCard()
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
            // VoiceOver : une phrase qui résume la courbe, puis le graphique
            // audio (rotor « Graphique audio ») pour l'écouter point par point.
            // Le détail chiffré reste dans l'historique juste en dessous.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Courbe de ton score")
            .accessibilityValue(ScoreHistoriqueAudio.resume(history))
            .accessibilityChartDescriptor(ScoreHistoriqueAudio(points: history))
        }
        .padding(.vertical, Theme.spacingSM)
        .dsCard()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: Theme.spacingMD) {
            // Le signe Kiwio : l'état vide garde la marque
            KiwiSigne(taille: 72)

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
                        .dsPolice(13, .medium)
                        .foregroundStyle(Color.dsTexte)
                        .frame(minWidth: 60, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Verre.remplissage)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.globalScoreColor(for: snapshot.score))
                                .frame(width: geo.size.width * CGFloat(snapshot.score) / 100.0)
                        }
                    }
                    .frame(height: 16)

                    Text("\(snapshot.score)%")
                        .dsPolice(13, .bold)
                        .foregroundStyle(HealthScale.couleurTexte(for: snapshot.score))
                        .frame(minWidth: 40, alignment: .trailing)
                }
                // Une ligne = un élément VoiceOver : « 3 sept., 68 % ».
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Theme.spacingMD)
        .dsCard()
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

// MARK: - Courbe lue par VoiceOver

/// La courbe du score pour VoiceOver : un résumé parlé, et la description
/// qui alimente le graphique audio d'iOS.
private struct ScoreHistoriqueAudio: AXChartDescriptorRepresentable {
    let points: [ScoreSnapshot]

    private static func jour(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR")))
    }

    /// « De 52 le 3 septembre à 68 le 9 octobre. Plus haut 70, plus bas 48,
    /// sur 12 relevés. »
    static func resume(_ historique: [ScoreSnapshot]) -> String {
        let tries = historique.sorted { $0.date < $1.date }
        guard let premier = tries.first, let dernier = tries.last else {
            return "Aucun relevé."
        }
        let scores = tries.map(\.score)
        let haut = scores.max() ?? dernier.score
        let bas = scores.min() ?? dernier.score
        return "De \(premier.score) le \(jour(premier.date)) à \(dernier.score) le \(jour(dernier.date)). "
            + "Plus haut \(haut), plus bas \(bas), sur \(tries.count) relevés."
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let tries = points.sorted { $0.date < $1.date }
        let debut = tries.first?.date.timeIntervalSince1970 ?? 0
        // Un axe ne peut pas être réduit à un point : un jour de marge.
        let fin = max(tries.last?.date.timeIntervalSince1970 ?? 0, debut + 86_400)

        let axeDates = AXNumericDataAxisDescriptor(
            title: "Date",
            range: debut...fin,
            gridlinePositions: []
        ) { valeur in
            Self.jour(Date(timeIntervalSince1970: valeur))
        }
        let axeScore = AXNumericDataAxisDescriptor(
            title: "Score",
            range: 0...100,
            gridlinePositions: [50, 75]
        ) { valeur in
            "\(Int(valeur.rounded())) sur 100"
        }
        let serie = AXDataSeriesDescriptor(
            name: "Score",
            isContinuous: true,
            dataPoints: tries.map {
                AXDataPoint(x: $0.date.timeIntervalSince1970, y: Double($0.score))
            }
        )
        return AXChartDescriptor(
            title: "Évolution de ton score",
            summary: Self.resume(points),
            xAxis: axeDates,
            yAxis: axeScore,
            additionalAxes: [],
            series: [serie]
        )
    }
}

#Preview {
    NavigationStack {
        ScoreHistoryView()
            .environmentObject(DashboardViewModel())
    }
}
