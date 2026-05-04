import SwiftUI
import UIKit

// MARK: - Dashboard View (main screen after analysis)
struct DashboardView: View {
    @EnvironmentObject var viewModel: DashboardViewModel
    @ObservedObject var gamification = GamificationService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var selectedNutrient: EnrichedNutrient?
    @State private var showNutrientDetail = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.healthMapBackground
                    .ignoresSafeArea()

                if viewModel.isLoadingAnalysis && viewModel.aiAnalysis == nil {
                    // Skeleton d'abord pour montrer la structure (anti-flash)
                    // Si besoin de fallback spinner plein écran, LoadingView reste dispo
                    DashboardSkeletonView()
                } else if viewModel.aiAnalysis == nil, let errorMessage = viewModel.errorMessage {
                    AnalysisErrorRetryView(
                        message: errorMessage,
                        isRetrying: viewModel.isLoadingAnalysis,
                        onRetry: {
                            Task { await viewModel.triggerAnalysis() }
                        }
                    )
                } else {
                    mainContent
                }
            }
            .navigationTitle("Mon Bilan")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.regenerateAnalysis() }
                    } label: {
                        Group {
                            if #available(iOS 18.0, *) {
                                Image(systemName: "arrow.clockwise")
                                    .symbolEffect(.rotate.byLayer, options: .repeat(.continuous), isActive: viewModel.isLoadingAnalysis)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .symbolEffect(.pulse, options: .repeating, isActive: viewModel.isLoadingAnalysis)
                            }
                        }
                        .font(.system(size: 16))
                        .foregroundStyle(Color.healthMapBlue)
                    }
                    .disabled(viewModel.isLoadingAnalysis)
                }
            }
            .sheet(isPresented: $showNutrientDetail) {
                if let nutrient = selectedNutrient {
                    NutrientDetailSheet(nutrient: nutrient, isPremium: subscriptionService.isPremium)
                        .healthMapSheet(.large)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .healthMapFullSheet()
            }
            .refreshable {
                await viewModel.triggerAnalysis()
            }
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: Theme.spacingLG) {
                // 1. Red flags (safety first, always visible)
                if !viewModel.redFlags.isEmpty {
                    RedFlagsCardView(flags: viewModel.redFlags)
                        .padding(.horizontal, Theme.spacingLG)
                }

                // 2. Hero Score Card (free, always visible)
                heroScoreCard

                // 3. Highlight Cards 2x2 (free, always visible)
                highlightGrid

                // 4. Nutriments a renforcer (free, always visible)
                if !viewModel.deficiencies.isEmpty {
                    aRenforcerSection
                }

                // 4b. Full nutrient grid (all 10 nutrients)
                if !viewModel.nutrients.isEmpty {
                    allNutrientsGrid
                }

                // 5. Action du jour (free, always visible)
                if let action = viewModel.actionDuJour {
                    actionDuJourCard(action)
                }

                // 6. Navigation cards (quick links)
                navigationCards

                // 7. Pepite du jour (free preview, full premium)
                if let pepite = viewModel.pepiteDuJour {
                    pepiteDuJourCard(pepite)
                }

                // 8. Export + Share (premium only)
                if subscriptionService.isPremium {
                    premiumActionsSection
                }

                // 9. Badges
                if !gamification.isZenMode {
                    badgesPreview
                }

                // 10. Refreshing indicator
                if viewModel.isLoadingAnalysis {
                    HStack(spacing: Theme.spacingSM) {
                        ProgressView()
                            .tint(Color.healthMapBlue)
                        Text("Mise a jour de l'analyse...")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                    .padding()
                }

                // Medical disclaimer
                disclaimerCard
            }
            .padding(.vertical, Theme.spacingMD)
        }
    }

    // MARK: - Hero Score Card
    private var heroScoreCard: some View {
        HStack(spacing: Theme.spacingMD) {
            // Score ring (compact)
            ScoreRingView(score: viewModel.healthScore, size: 80, lineWidth: 6)

            VStack(alignment: .leading, spacing: 4) {
                // Greeting
                HStack(spacing: 6) {
                    Text("Bonjour \(viewModel.firstName)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .brandHeadlineKerning()
                        .foregroundStyle(Color.healthMapText)

                    // Streak badge inline
                    if gamification.currentStreak > 0 && !gamification.isZenMode {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10))
                            Text("\(gamification.currentStreak)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.accentSky)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentSky.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                // Score label
                Text(scoreLabel)
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.globalScoreColor(for: viewModel.healthScore))

                Text("Score global de sante")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.healthMapSecondary)
            }

            Spacer()
        }
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bonjour \(viewModel.firstName). Score global de sante : \(viewModel.healthScore) sur 100, \(scoreLabel)")
    }

    // MARK: - Highlight Grid 2x2
    private var highlightGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            HighlightCard(
                icon: "chart.line.uptrend.xyaxis",
                iconColor: .scoreGood,
                title: "Points forts",
                value: "\(viewModel.goodNutrients) nutriments",
                subtitle: "Score >= 60"
            )

            HighlightCard(
                icon: "exclamationmark.triangle",
                iconColor: .scoreLow,
                title: "A surveiller",
                value: "\(viewModel.deficiencies.count) a renforcer",
                subtitle: nil
            )

            HighlightCard(
                icon: "bolt.fill",
                iconColor: .accentIndigo,
                title: "Interactions",
                value: "\(viewModel.interactionsCount) detectees",
                subtitle: nil
            )

            HighlightCard(
                icon: "target",
                iconColor: .healthMapBlue,
                title: "Action prioritaire",
                value: String((viewModel.actionDuJour?.titre ?? "--").prefix(30)),
                subtitle: nil
            )
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - A Renforcer Section
    private var aRenforcerSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack {
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.scoreDeficient)

                    Text("Nutriments a renforcer")
                        .font(Theme.headlineFont)
                        .foregroundStyle(Color.healthMapText)
                }

                Spacer()

                Text("\(viewModel.deficiencies.count)")
                    .pillStyle(color: .scoreDeficient)
            }
            .padding(.horizontal, Theme.spacingLG)

            // Show top 3
            VStack(spacing: 6) {
                ForEach(Array(viewModel.deficiencies.prefix(3))) { nutrient in
                    Button {
                        selectedNutrient = nutrient
                        showNutrientDetail = true
                    } label: {
                        compactNutrientRow(nutrient)
                    }
                    .buttonStyle(.healthMapPressed)
                }
            }
            .padding(.horizontal, Theme.spacingLG)

            // "Voir les X nutriments a renforcer" link
            if viewModel.deficiencies.count > 3 {
                NavigationLink {
                    RecommendationsView()
                        .environmentObject(viewModel)
                } label: {
                    HStack {
                        Text("Voir les \(viewModel.deficiencies.count) nutriments")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.healthMapBlue)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.healthMapBlue)
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
            }
        }
    }

    // MARK: - Compact Nutrient Row
    private func compactNutrientRow(_ nutrient: EnrichedNutrient) -> some View {
        let needsAttention = nutrient.score < 60
        return HStack(spacing: Theme.spacingSM) {
            RoundedRectangle(cornerRadius: 2)
                .fill(needsAttention ? Color.scoreDeficient : Color.scoreGood)
                .frame(width: 4, height: 40)

            Text(nutrient.emoji)
                .font(.system(size: 20))
                .frame(width: 32, height: 32)
                .background(Color.nutrientColor(for: nutrient.id).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(nutrient.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.healthMapText)

            Spacer()

            Text("\(nutrient.score)%")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.scoreColor(for: nutrient.score))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.healthMapMuted.opacity(0.15))
                    .frame(width: 52, height: 5)
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.scoreColor(for: nutrient.score))
                    .frame(width: CGFloat(nutrient.score) / 100.0 * 52, height: 5)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Color.healthMapMuted)
        }
        .padding(Theme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                .fill(needsAttention ? Color.scoreDeficient.opacity(0.04) : Color.healthMapCard)
        )
    }

    // MARK: - All Nutrients Grid
    private var allNutrientsGrid: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.healthMapBlue)

                Text("Tous mes nutriments")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Color.healthMapText)
            }
            .padding(.horizontal, Theme.spacingLG)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(viewModel.nutrients) { nutrient in
                    Button {
                        selectedNutrient = nutrient
                        showNutrientDetail = true
                    } label: {
                        VStack(spacing: 6) {
                            MiniScoreRing(
                                score: nutrient.score,
                                color: Color.nutrientColor(for: nutrient.id),
                                size: 52
                            )

                            Text(nutrient.emoji)
                                .font(.system(size: 16))

                            Text(nutrient.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.healthMapSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                                .fill(Color.healthMapCard)
                        )
                    }
                    .buttonStyle(.healthMapPressed)
                }
            }
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - Action du jour
    private func actionDuJourCard(_ action: (titre: String, description: String?)) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.healthMapBlue)
                    .clipShape(Circle())

                Text("ACTION DU JOUR")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.healthMapBlue)
                    .tracking(0.5)
            }

            Text(action.titre)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.healthMapText)
                .fixedSize(horizontal: false, vertical: true)

            if let desc = action.description {
                Text(desc)
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.healthMapBlueLight)
        )
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Score Label
    var scoreLabel: String {
        let s = viewModel.healthScore
        if s >= 75 { return "Excellent" }
        if s >= 60 { return "Bon" }
        if s >= 40 { return "A ameliorer" }
        return "Critique"
    }
}

#Preview {
    DashboardView()
        .environmentObject(DashboardViewModel())
}
