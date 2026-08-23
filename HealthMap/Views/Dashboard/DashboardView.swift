import SwiftUI

// MARK: - Dashboard View (Bilan complet — refonte « v7 dashboard », 22 juillet 2026)
//
// Refonte 23 août 2026 : le Bilan n'est plus un onglet. Il a fusionné dans le
// Journal, qui en porte l'essentiel (apports à renforcer, interaction
// détectée). Cet écran reste le BILAN COMPLET, présenté en feuille depuis
// « Tout afficher » : score, apports, points d'attention, symptômes, série,
// repas, sources. Il ne vend plus rien : la carte et la pill Premium ont
// quitté le Bilan (le paywall vit uniquement dans Réglages).
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
    @State private var selectedAttention: InteractionV2?
    @State private var showTrophies = false
    @State private var showScoreDetail = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                DSPageBackground(voile: false)
                content
            }
            // Recharge le journal dès qu'un scan est persisté ailleurs (onglet
            // Scanner) — posé ICI (pas dans mainContent) pour rester vivant même
            // si le bilan v2 n'est pas encore chargé/valide (mainContent n'est
            // alors pas monté). journal/viewModel sont au niveau de la struct.
            .onReceive(NotificationCenter.default.publisher(for: .healthmapMealScanned)) { _ in
                Task { await journal.load() }
            }
            // L'en-tête de l'écran fait office de titre ; la barre ne porte
            // que le bouton de fermeture de la feuille.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .kiwiNavigationBarBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Color.dsAccent)
                        .accessibilityLabel("Fermer")
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
            // Pop-up détail d'un point d'attention (maquette V2a) : le tap
            // ouvre une sheet limpide au lieu de basculer sèchement vers Plan.
            .sheet(item: $selectedAttention) { interaction in
                AttentionDetailSheet(interaction: interaction) {
                    selectedAttention = nil
                    openTab(.plan)
                }
                .healthMapSheet()
            }
            // Trophées de la récolte (feuille existante, alimentée par la série).
            .sheet(isPresented: $showTrophies) {
                RecolteDetailSheet(streak: gamification.currentStreak)
            }
        }
    }

    // MARK: - Contenu (v7 si bilan v2 dispo, sinon attente ou découverte)
    // Route extraite dans `DashboardViewModel.bilanAffichage` (testable sans
    // UI) — même logique que le switch historique.
    @ViewBuilder
    private var content: some View {
        switch viewModel.bilanAffichage {
        case .bilan:
            if let v2 = viewModel.analysisV2 {
                mainContent(v2)
            }
        case .attente:
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
                        isRetrying: viewModel.isLoadingAnalysisV2,
                        onRetry: { Task { await viewModel.retryBilanV2() } }
                    )
                } else {
                    // Analyse pas encore déclenchée (transition post-questionnaire).
                    FullAnalysisLoadingView()
                }
            }
        case .decouverte:
            // Mode découverte (V12b) : le VRAI dashboard v7 en teaser in-situ
            // — remplace l'écran d'invitation provisoire de V12a.
            discoveryContent
        }
    }

    // MARK: - Mode découverte (V12b — pas encore de bilan)
    /// Le dashboard v7 en mode teaser : structure, sections et cartes
    /// STRICTEMENT identiques à `mainContent` ; seuls les emplacements de
    /// données changent (stats France sourcées + un CTA bilan par zone à
    /// forte valeur — Z3 apports et Z4 points d'attention). Les zones sans
    /// donnée réelle (symptômes, repas vides) restent masquées comme dans le
    /// dashboard réel ; la carte Premium Z7 et la pill restent masquées
    /// (`premiumVisible`, décision V12a). À la complétion du bilan,
    /// `bilanAffichage` bascule et le dashboard passe aux vraies données
    /// sans relance.
    private var discoveryContent: some View {
        ScrollView {
            VStack(spacing: BilanV7.cardGap) {
                // Sécurité : même garde que mainContent (vide sans profil).
                if !immediateRedFlags.isEmpty {
                    RedFlagsCardView(flags: immediateRedFlags)
                }

                // Z1 · En-tête (plus de pill Premium : le paywall vit dans Réglages)
                BilanV7Header(date: Date(), showsPremiumPill: false) { }
                    .staggeredAppear(index: 0)

                // Z2 · Hero : l'anneau attend le bilan (aucun bouton ici —
                // un CTA géant par zone, jamais trois empilés)
                BilanV7ScoreTeaserCard()
                    .staggeredAppear(index: 1)

                // Z3 · Grille des apports en stats France + CTA bilan
                BilanV7ApportsTeaserCard {
                    viewModel.demarrerBilan()
                }
                .staggeredAppear(index: 2)

                // Z4 · Points d'attention : exemple générique + CTA bilan
                BilanV7AttentionTeaserCard {
                    viewModel.demarrerBilan()
                }
                .staggeredAppear(index: 3)

                // Z5 · Ta série — état existant (donnée réelle du journal,
                // indépendante du bilan ; masquée en mode zen comme ailleurs)
                if !gamification.isZenMode {
                    BilanV7SerieCard(streak: gamification.currentStreak) {
                        showTrophies = true
                    }
                    .staggeredAppear(index: 4)
                }

                // Z6 · Tes derniers repas — état vide existant (masquée si vide)
                if !repasLines.isEmpty {
                    BilanV7RepasCard(lines: repasLines)
                        .staggeredAppear(index: 5)
                }

                // Z7 · Premium : jamais avant le bilan (`premiumVisible`, V12a)

                // Sources scientifiques (App Store guideline 1.4.1)
                BilanV7SourcesFooter()
                    .padding(.top, 4)
            }
            .padding(.horizontal, BilanV7.gutter)
            .padding(.top, Theme.spacingXS)
            .padding(.bottom, Theme.spacingLG)
            // Même verrou anti-dérive horizontale que mainContent.
            .containerRelativeFrame(.horizontal)
        }
        .task { await journal.load() }
        // Funnel découverte (V12f) : 1er affichage du dashboard sans bilan —
        // one-shot, dédupliqué par DecouverteFunnel (UserDefaults).
        .onAppear {
            DecouverteFunnel.arriveeDashboard(bilanComplete: viewModel.bilanComplete)
        }
    }

    // MARK: - Main Content (langage v7)
    private func mainContent(_ v2: AIAnalysisV2) -> some View {
        // UN SEUL passage du moteur hebdo par rendu : `todayScore` et
        // `weekScore.delta` le relançaient chacun de leur côté (deux filtres
        // sur la quinzaine, sept jours de sous-filtres, la semaine précédente
        // et le topMover, deux fois).
        let semaine = weekScore
        let scoreDuJour = semaine.days.first(where: { $0.isToday })?.score ?? semaine.score
        return ScrollView {
            VStack(spacing: BilanV7.cardGap) {
                if !immediateRedFlags.isEmpty {
                    RedFlagsCardView(flags: immediateRedFlags)
                }

                // Z1 · En-tête (plus de pill Premium : le paywall vit dans Réglages)
                BilanV7Header(date: Date(), showsPremiumPill: false) { }
                    .staggeredAppear(index: 0)

                // Z2 · Score du jour (anneau compact + tendance de la semaine)
                // `scoreInsight` commente le score GLOBAL du bilan (« 52/100 »),
                // pas le score du jour de l'anneau (couverture du journal) : les
                // deux côte à côte se contredisaient (audit captures 23 août).
                BilanV7ScoreCard(
                    score: scoreDuJour,
                    delta: semaine.delta,
                    insight: nil
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

                // Z3b · Points d'attention (interactions du contrat).
                // isPremium : en gratuit la carte nomme le problème (teasing
                // déterministe), le titre-solution IA reste premium.
                if !attentionItems.isEmpty {
                    BilanV7AttentionCard(
                        items: attentionItems,
                        isPremium: subscriptionService.isPremium
                    ) { item in
                        selectedAttention = item
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

                // Z7 (ex-carte Kiwio Premium) : retirée, le paywall vit
                // uniquement dans Réglages (refonte 23 août 2026).

                // Indicateur de rafraîchissement (bilan déjà présent)
                if viewModel.isLoadingAnalysis || viewModel.isLoadingAnalysisV2 {
                    HStack(spacing: Theme.spacingSM) {
                        ProgressView().tint(Color.dsAccent)
                        Text("Mise à jour de l'analyse…")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.dsSecondaire)
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
    /// ET que l'utilisateur est premium : le verdict d'évolution (« en
    /// amélioration ») est la trajectoire — exactement ce que les portes
    /// `suivi_symptomes` / `historique_score` vendent. En gratuit, la ligne
    /// nomme le symptôme (le problème), jamais son évolution.
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
                showsTrend: !evolution.isExample && subscriptionService.isPremium
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
    /// Le Bilan est une feuille : on la referme AVANT de changer d'onglet,
    /// sinon l'onglet visé s'ouvre derrière elle.
    private func openTab(_ destination: NavCardDestination) {
        HapticService.shared.tap()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(
                name: .healthmapNavigateToTab,
                object: destination.rawValue
            )
        }
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
                    .foregroundStyle(Color.dsTexte)

                Text(messages[messageIndex])
                    .font(Theme.bodyFont)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 48)
                    .id(messageIndex)
                    .transition(.opacity)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Color.dsAccent)
                .frame(maxWidth: 200)
                .animation(.easeInOut(duration: 0.4), value: progress)

            VStack(spacing: Theme.spacingSM) {
                Text("Compte 2 à 3 minutes")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.dsAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.dsAccent.opacity(0.12), in: Capsule())

                Text("Tu peux laisser l'app ouverte, on s'occupe de tout.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.dsSecondaire)
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
