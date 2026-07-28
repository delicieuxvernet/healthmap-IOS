import SwiftUI

// MARK: - Dashboard View (onglet Bilan — refonte « v7 dashboard », 22 juillet 2026)
//
// Maquette de référence : « Kiwio - Bilan (standalone) » (iPhone 393 pt).
// Ordre de lecture Z1 → Z7 :
//   Z1 en-tête « Bilan » + date + pill Premium
//   Z2 score du jour compact (anneau 64 pt + phrase de tendance)
//   Z3 tes apports à renforcer — HÉROS (priorité + jauges)
//   Z3b points d'attention (interactions du contrat v2)
//   Z4 tes symptômes suivis (+ CTA « Voir mes solutions »)
//   Z5 ta série (streak + prochain trophée)
//   Z6 tes derniers repas
//   Z7 Kiwio Premium (grande carte verte, non-premium uniquement)
//   puis sources scientifiques (exigence App Review 1.4.1).
//
// Source de données : `DashboardViewModel.analysisV2` (contrat API v2) +
// journal `meal_scans` + `WeekScoreEngine` + `SuiviEngineV4` +
// `GamificationService`. Aucune valeur n'est inventée : une section sans
// donnée réelle est simplement masquée.
//
// Inchangé côté sécurité : les red flags URGENTS passent TOUJOURS au-dessus
// du contenu (une alerte ne doit pas attendre l'IA).
struct DashboardView: View {
    @EnvironmentObject var viewModel: DashboardViewModel
    @ObservedObject var gamification = GamificationService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    /// Journal du jour (table `meal_scans`) — nourrit le score du jour et
    /// « Tes derniers repas ». Lecture seule, aucun calcul touché.
    @StateObject private var journal = MealJournalViewModel()

    @State private var selectedApport: ApportV2?
    @State private var showPaywall = false
    @State private var showTrophies = false
    @State private var showScoreDetail = false

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                content
            }
            .kiwiTabBarBottomInset()
            // Recharge le journal dès qu'un scan est persisté ailleurs (onglet
            // Scanner) — posé ICI (pas dans mainContent) pour rester vivant même
            // si le bilan v2 n'est pas encore chargé/valide (mainContent n'est
            // alors pas monté). journal/viewModel sont au niveau de la struct.
            .onReceive(NotificationCenter.default.publisher(for: .healthmapMealScanned)) { _ in
                Task { await journal.load() }
            }
            // v7 : l'en-tête de l'écran fait office de titre — la barre reste
            // inline et vide, seul l'avatar Profil y demeure.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .kiwiNavigationBarBackground()
            .toolbar {
                // Avatar Profil en haut à droite (ouvre le Profil en sheet via
                // NotificationCenter, consommé par MainTabView). Accent vert kiwi.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        NotificationCenter.default.post(name: .healthmapOpenProfile, object: nil)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.kiwiGreen)
                    }
                    .accessibilityLabel("Profil")
                }
            }
            .navigationDestination(isPresented: $showScoreDetail) {
                ScoreHistoryView()
                    .environmentObject(viewModel)
            }
            // Pop-up détail d'un apport (contrat v2). .sheet(item:) garantit que
            // la feuille reçoit toujours l'apport courant.
            .sheet(item: $selectedApport) { apport in
                ApportV2DetailSheet(apport: apport) {
                    selectedApport = nil
                    openTab(.plan)
                }
            }
            // Trophées de la récolte (feuille existante, alimentée par la série).
            .sheet(isPresented: $showTrophies) {
                RecolteDetailSheet(streak: gamification.currentStreak)
            }
            // Paywall ouvert par la pill et la carte Premium du Bilan.
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .healthMapFullSheet()
            }
        }
    }

    // MARK: - Contenu (v7 si bilan v2 dispo, sinon flux chargement existant)
    @ViewBuilder
    private var content: some View {
        if let v2 = viewModel.analysisV2, v2.isValidV2 {
            mainContent(v2)
        } else if viewModel.profile.completed {
            VStack(spacing: 0) {
                if !immediateRedFlags.isEmpty {
                    RedFlagsCardView(flags: immediateRedFlags)
                        .padding(.horizontal, Theme.spacingLG)
                        .padding(.top, Theme.spacingMD)
                }
                if viewModel.isLoadingAnalysisV2 {
                    FullAnalysisLoadingView()
                } else if let errorMessageV2 = viewModel.errorMessageV2 {
                    // Le bilan RÉELLEMENT affiché (v2) a échoué sans repli en
                    // cache. Gardé sur errorMessageV2 (pas aiAnalysis/errorMessage,
                    // v7) depuis l'incident du 4 juillet : un échec v7 seul ne
                    // doit jamais bloquer l'affichage du vrai bilan v2.
                    AnalysisErrorRetryView(
                        message: errorMessageV2,
                        isRetrying: false,
                        onRetry: { Task { await viewModel.triggerAnalysis() } }
                    )
                } else {
                    // Analyse pas encore déclenchée (transition post-questionnaire).
                    FullAnalysisLoadingView()
                }
            }
        } else {
            DashboardSkeletonView()
        }
    }

    // MARK: - Main Content (langage v7)
    private func mainContent(_ v2: AIAnalysisV2) -> some View {
        ScrollView {
            VStack(spacing: BilanV7.cardGap) {
                if !immediateRedFlags.isEmpty {
                    RedFlagsCardView(flags: immediateRedFlags)
                }

                // Z1 · En-tête + pill Premium
                BilanV7Header(
                    date: Date(),
                    showsPremiumPill: !subscriptionService.isPremium
                ) {
                    HapticService.shared.tap()
                    showPaywall = true
                }
                .staggeredAppear(index: 0)

                // Z2 · Score du jour (anneau compact + tendance de la semaine)
                BilanV7ScoreCard(
                    score: todayScore,
                    delta: weekScore.delta,
                    insight: v2.bilan?.scoreInsight
                ) {
                    HapticService.shared.tap()
                    showScoreDetail = true
                }
                .staggeredAppear(index: 1)

                // Z3 · HÉROS — tes apports à renforcer
                if let apports = v2.bilan?.apports, !apports.isEmpty {
                    BilanV7ApportsCard(
                        apports: Array(apports.prefix(3)),
                        total: NutrientData.all.count
                    ) { apport in
                        selectedApport = apport
                    }
                    .staggeredAppear(index: 2)
                }

                // Z3b · Points d'attention (interactions du contrat)
                if !attentionItems.isEmpty {
                    BilanV7AttentionCard(items: attentionItems) { _ in
                        openTab(.plan)
                    }
                    .staggeredAppear(index: 3)
                }

                // Z4 · Tes symptômes suivis + CTA solutions
                let rows = symptomRows(v2)
                if !rows.isEmpty {
                    BilanV7SymptomesCard(
                        rows: rows,
                        solutionsCount: solutionsCount(v2),
                        onTapSymptom: { _ in openTab(.suivi) },
                        onSolutions: { openTab(.plan) }
                    )
                    .staggeredAppear(index: 4)
                }

                // Z5 · Ta série (masquée en mode zen, comme la récolte v6)
                if !gamification.isZenMode {
                    BilanV7SerieCard(streak: gamification.currentStreak) {
                        showTrophies = true
                    }
                    .staggeredAppear(index: 5)
                }

                // Z6 · Tes derniers repas (bilan du journal — masqué si vide)
                if !repasLines.isEmpty {
                    BilanV7RepasCard(lines: repasLines)
                        .staggeredAppear(index: 6)
                }

                // Z7 · Kiwio Premium (non-premium uniquement)
                if !subscriptionService.isPremium {
                    BilanV7PremiumCard {
                        HapticService.shared.tap()
                        showPaywall = true
                    }
                    .staggeredAppear(index: 7)
                }

                // Indicateur de rafraîchissement (bilan déjà présent)
                if viewModel.isLoadingAnalysis || viewModel.isLoadingAnalysisV2 {
                    HStack(spacing: Theme.spacingSM) {
                        ProgressView().tint(Color.kiwiGreen)
                        Text("Mise à jour de l'analyse…")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                    .padding(.vertical, Theme.spacingSM)
                }

                // Red flags non urgents (sécurité — inchangé)
                if !otherRedFlags.isEmpty {
                    RedFlagsCardView(flags: otherRedFlags)
                }

                // Sources scientifiques (App Store guideline 1.4.1)
                BilanV7SourcesFooter()
                    .padding(.top, 4)
            }
            .padding(.horizontal, BilanV7.gutter)
            .padding(.top, Theme.spacingXS)
            .padding(.bottom, Theme.spacingLG)
            // Verrou anti-dérive horizontale (même correctif que Suivi #134 et
            // Scan #120) : la largeur du contenu est épinglée à celle du
            // ScrollView → plus de slide latéral vers une marge vide.
            .containerRelativeFrame(.horizontal)
        }
        .task { await journal.load() }
        .refreshable {
            await viewModel.triggerAnalysis()
            await journal.load()
        }
    }

    // MARK: - Score du jour (déterministe, repas scannés)
    /// Recalculé à chaque rendu depuis le journal 14 jours + les apports à
    /// renforcer du profil (scores locaux < 60, même seuil que le scan).
    private var weekScore: WeekScoreEngine.WeekScore {
        WeekScoreEngine.compute(
            meals: journal.fortnight,
            weakNutrients: weakNutrientIds
        )
    }

    /// Anneau Z2 : la couverture du JOUR si des repas y ont été scannés ;
    /// à défaut la moyenne de la semaine (le chiffre reste réel), sinon rien.
    private var todayScore: Int? {
        weekScore.days.first(where: { $0.isToday })?.score ?? weekScore.score
    }

    private var weakNutrientIds: [String] {
        viewModel.nutrientScores
            .filter { $0.value < 60 }
            .map(\.key)
            .sorted()
    }

    // MARK: - Points d'attention (interactions du contrat v2, ≤2)
    private var attentionItems: [InteractionV2] {
        guard let interactions = viewModel.analysisV2?.bilan?.interactions else { return [] }
        return Array(
            interactions
                .filter { ($0.tipBold?.isEmpty == false) || ($0.tipRest?.isEmpty == false) }
                .prefix(2)
        )
    }

    // MARK: - Symptômes suivis (mêmes verdicts que l'onglet Suivi)
    /// La tendance n'est affichée QUE si le suivi a réellement démarré :
    /// sinon `SuiviEngineV4` renvoie une courbe d'exemple, qu'on ne présente
    /// jamais comme une évolution vécue.
    private func symptomRows(_ v2: AIAnalysisV2) -> [BilanV7SymptomRow] {
        let symptomes = v2.bilan?.symptomes ?? []
        guard !symptomes.isEmpty else { return [] }

        let isTracking = SuiviTrackingStore.isStarted()
        let ids = symptomes.compactMap { $0.id ?? $0.nom }
        let feelingsById = isTracking
            ? SuiviCheckinHistory.feelingsById(
                symptomIds: ids,
                since: SuiviTrackingStore.startDate() ?? Date()
            )
            : [:]

        return SuiviEngineV4.symptomEvolutions(
            symptomes: symptomes,
            feelingsById: feelingsById,
            isTracking: isTracking
        ).map { evolution in
            BilanV7SymptomRow(
                id: evolution.id,
                nom: capitalizedFirst(evolution.nom),
                verdict: evolution.verdict,
                improving: evolution.improving,
                showsTrend: !evolution.isExample
            )
        }
    }

    /// Badge bleu du CTA : nombre de solutions réellement présentes dans le plan.
    private func solutionsCount(_ v2: AIAnalysisV2) -> Int {
        (v2.plan?.sections ?? []).reduce(0) { total, section in
            let solutions = section.solutions
            return total
                + (solutions?.nutrition?.count ?? 0)
                + (solutions?.habitudes?.count ?? 0)
                + (solutions?.complements?.count ?? 0)
        }
    }

    // MARK: - Bilan des derniers repas (dérivé du journal réel)
    /// Deux lignes maximum, construites sur la couverture 7 jours calculée par
    /// `SuiviEngineV4` : le nutriment le mieux couvert et celui qui manque le
    /// plus. Aucune phrase inventée — les chiffres viennent des scans.
    private var repasLines: [BilanV7RepasLine] {
        guard !journal.fortnight.isEmpty else { return [] }
        let coverage = SuiviEngineV4.nutrientCoverage(
            fortnight: journal.fortnight,
            focusIds: weakNutrientIds
        )
        guard !coverage.isEmpty else { return [] }

        var lines: [BilanV7RepasLine] = []
        let best = coverage.max(by: { $0.pct < $1.pct })
        let worst = coverage.min(by: { $0.pct < $1.pct })

        if let best, best.pct >= 60 {
            lines.append(
                BilanV7RepasLine(
                    id: "positif-\(best.id)",
                    positive: true,
                    text: "\(best.nom) bien couvert sur tes 7 derniers jours (\(best.pct) % de ton besoin)."
                )
            )
        }
        if let worst, worst.pct < 60, worst.id != best?.id || lines.isEmpty {
            lines.append(
                BilanV7RepasLine(
                    id: "manque-\(worst.id)",
                    positive: false,
                    text: "Peu de \(worst.nom.lowercased()) ces 7 derniers jours (\(worst.pct) % de ton besoin)."
                )
            )
        }
        return lines
    }

    private func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: - Red flags (sécurité — inchangé)
    private var immediateRedFlags: [RedFlag] {
        viewModel.redFlags.filter { $0.urgency == .immediate }
    }

    private var otherRedFlags: [RedFlag] {
        viewModel.redFlags.filter { $0.urgency != .immediate }
    }

    // MARK: - Navigation onglets (mécanisme existant)
    private func openTab(_ destination: NavCardDestination) {
        HapticService.shared.tap()
        NotificationCenter.default.post(
            name: .healthmapNavigateToTab,
            object: destination.rawValue
        )
    }
}

// MARK: - Staggered Appear (loi 17)
/// Apparition des sections en léger stagger : fondu + petite montée, une
/// seule courbe (`.healthMapSpring`), délai croissant par index. Reduce
/// Motion → affichage immédiat sans animation.
private struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.healthMapSpring.delay(Double(index) * 0.04)) {
                        appeared = true
                    }
                }
            }
    }
}

private extension View {
    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

// MARK: - Écran de chargement plein (flux du 20 juin — inchangé)
// Tant que le bilan IA n'est pas prêt, on n'affiche AUCUN résultat : juste la
// mascotte kiwi qui marche + un message qui tourne. Référencé par
// ContentView (AnalysisGateView) : NE PAS retirer.
struct FullAnalysisLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var messageIndex = 0
    @State private var progress: Double = 0

    private let messages = [
        "On croise tes symptômes, ton alimentation et ton mode de vie.",
        "On cherche ce qui peut expliquer tes symptômes.",
        "On repère tes points forts et tes vraies priorités.",
        "On prépare des conseils personnalisés, rien que pour toi.",
    ]

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            KiwiWalkerView(size: 140)

            VStack(spacing: Theme.spacingSM) {
                Text("On analyse ton profil…")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Color.healthMapText)

                Text(messages[messageIndex])
                    .font(Theme.bodyFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 48)
                    .id(messageIndex)
                    .transition(.opacity)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Color.kiwiGreen)
                .frame(maxWidth: 200)
                .animation(.easeInOut(duration: 0.4), value: progress)

            VStack(spacing: Theme.spacingSM) {
                Text("Compte 2 à 3 minutes")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.kiwiGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.kiwiGreen.opacity(0.12), in: Capsule())

                Text("Tu peux laisser l'app ouverte, on s'occupe de tout.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapMuted)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Theme.spacingLG)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Analyse de ton profil en cours. Compte deux à trois minutes.")
        .task {
            // Progression calibrée sur la durée réelle (~2-3 min) : montée douce qui
            // plafonne vers 90 % et n'atteint JAMAIS 100 % — la barre disparaît quand
            // le vrai bilan arrive (la vue est remplacée par le contenu). Fini le
            // « 95 % figé en 25 s » suivi d'une fausse erreur réseau.
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                if Task.isCancelled { break }
                ticks += 1
                progress = min(0.9, progress + (0.9 - progress) * 0.012)
                if !reduceMotion && ticks % 8 == 0 {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        messageIndex = (messageIndex + 1) % messages.count
                    }
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(DashboardViewModel())
}
