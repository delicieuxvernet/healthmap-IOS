import SwiftUI
import UIKit

// MARK: - Dashboard View (main screen after analysis)
// Structure : DESIGN-PAGES.md §1 (blocs 0 → 9). Chaque section déclare son
// champ source, ses lignes max et sa couleur = f(score) (loi 13).
struct DashboardView: View {
    @EnvironmentObject var viewModel: DashboardViewModel
    @ObservedObject var gamification = GamificationService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var selectedNutrient: EnrichedNutrient?
    @State private var showNutrientDetail = false
    @State private var showAllNutrients = false
    @State private var showScoreInfo = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Fond lumineux + aurora animée à opacité réduite (DESIGN-PAGES
                // loi 2) : la base healthMapBackground reste pleine sous
                // l'aurora pour qu'elle ne domine jamais l'information.
                // AnimatedBackground gère déjà reduce-motion (statique).
                Color.healthMapBackground
                    .ignoresSafeArea()

                AnimatedBackground()
                    .opacity(0.5)

                // Le score LOCAL (HealthCalculator) doit TOUJOURS s'afficher
                // dès que le questionnaire est complété — jamais 0/100+croix,
                // jamais d'écran bloqué sur un spinner (incident TestFlight 28).
                // Le squelette et l'écran d'erreur plein écran ne servent que
                // quand on n'a RIEN de local à montrer (cas limite).
                if viewModel.nutrientScores.isEmpty && viewModel.isLoadingAnalysis {
                    // Skeleton d'abord pour montrer la structure (anti-flash)
                    DashboardSkeletonView()
                } else if viewModel.nutrientScores.isEmpty, viewModel.aiAnalysis == nil,
                          let errorMessage = viewModel.errorMessage {
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
            .sheet(isPresented: $showAllNutrients) {
                AllNutrientsSheet(
                    nutrients: viewModel.nutrients,
                    isPremium: subscriptionService.isPremium
                )
                .healthMapSheet(.large)
            }
            .sheet(isPresented: $showScoreInfo) {
                scoreInfoSheet
                    .healthMapActionSheet()
            }
            .refreshable {
                await viewModel.triggerAnalysis()
            }
        }
    }

    // MARK: - Red flags filtrés (DESIGN-PAGES §1 blocs 0 et 9)
    // Source : viewModel.redFlags (merge IA ou détection locale).
    // Seuls les `urgency == .immediate` passent AVANT le héro (sécurité) ;
    // les autres descendent en bas de page, après le disclaimer.
    private var immediateRedFlags: [RedFlag] {
        viewModel.redFlags.filter { $0.urgency == .immediate }
    }

    private var otherRedFlags: [RedFlag] {
        viewModel.redFlags.filter { $0.urgency != .immediate }
    }

    // MARK: - Priorité n°1 (bloc 2)
    // Source : aiAnalysis.priorityActions trié par rank (helper d'affichage pur).
    private var topPriorityAction: PriorityAction? {
        viewModel.aiAnalysis?.priorityActions
            .sorted { ($0.rank ?? Int.max) < ($1.rank ?? Int.max) }
            .first
    }

    // MARK: - Main Content
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: Theme.spacingLG) {
                // 0. Red flags URGENTS uniquement (sécurité avant tout —
                // jamais différés par le stagger d'apparition).
                if !immediateRedFlags.isEmpty {
                    RedFlagsCardView(flags: immediateRedFlags)
                        .padding(.horizontal, Theme.spacingLG)
                }

                // 1. Héro intégré : anneau + pill état + headline + métaphore
                heroSection
                    .staggeredAppear(index: 0)

                // 1b. Statut analyse IA — le score local reste affiché ;
                // on superpose un bandeau pendant le chargement, ou un bandeau
                // de retry si l'analyse a échoué (états : loading / succès /
                // échec IA avec score local + bouton réessayer).
                if viewModel.aiAnalysis == nil {
                    if viewModel.isLoadingAnalysis {
                        analysisLoadingBanner
                    } else if let errorMessage = viewModel.errorMessage {
                        AnalysisRetryBanner(
                            message: errorMessage,
                            isRetrying: viewModel.isLoadingAnalysis,
                            onRetry: {
                                Task { await viewModel.triggerAnalysis() }
                            }
                        )
                        .padding(.horizontal, Theme.spacingLG)
                    }
                }

                // 2. « Ta priorité n°1 » — carte teintée bleue pleine largeur
                if let action = topPriorityAction {
                    priorityCard(action)
                        .staggeredAppear(index: 1)
                }

                // 3. « À surveiller (N) » — top 3 en cartes jumelles
                if !viewModel.deficiencies.isEmpty {
                    watchSection
                        .staggeredAppear(index: 2)
                }

                // 4. Bouton glass vers la grille complète (sheet séparée —
                // la grille n'est PLUS sur l'écran principal).
                if !viewModel.nutrients.isEmpty {
                    GlassPillButton(
                        title: "Tous mes nutriments (\(viewModel.nutrients.count))",
                        systemImage: "square.grid.3x3"
                    ) {
                        HapticService.shared.tap()
                        showAllNutrients = true
                    }
                    .staggeredAppear(index: 3)
                }

                // 5. Rangée symétrique : Points forts / Interaction
                insightTilesRow
                    .staggeredAppear(index: 4)

                // 6. Pépite du jour (rotation quotidienne déterministe)
                if let pepite = viewModel.pepiteDuJour {
                    PepiteDuJourCard(pepite: pepite)
                        .staggeredAppear(index: 5)
                }

                // 7. Case premium floutée : le hack du nutriment prioritaire
                if let hackSection = premiumHackSection {
                    hackSection
                        .staggeredAppear(index: 6)
                }

                // 7b. Export + partage (premium uniquement — conservé du
                // Bilan existant, regroupé avec le contenu premium).
                if subscriptionService.isPremium {
                    premiumActionsSection
                        .staggeredAppear(index: 7)
                }

                // 8. Fin positive : le plan est prêt (peak-end — ne jamais
                // finir sur les manques).
                planReadyCard
                    .staggeredAppear(index: 8)

                // 8b. Refreshing indicator (refresh d'une analyse déjà
                // affichée — le premier chargement passe par le bandeau 1b)
                if viewModel.isLoadingAnalysis && viewModel.aiAnalysis != nil {
                    HStack(spacing: Theme.spacingSM) {
                        ProgressView()
                            .tint(Color.healthMapBlue)
                        Text("Mise a jour de l'analyse...")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                    .padding()
                }

                // 9. Disclaimer unique (1 ligne) + red flags non urgents
                disclaimerCard

                if !otherRedFlags.isEmpty {
                    RedFlagsCardView(flags: otherRedFlags)
                        .padding(.horizontal, Theme.spacingLG)
                }
            }
            .padding(.vertical, Theme.spacingMD)
        }
    }

    // MARK: - Héro intégré (bloc 1)
    // Sources : healthScore local (anneau, arc = score/100 — loi 5),
    // HealthScale.globalLabel (pill, vocabulaire contrôlé — lois 4 & 8),
    // summary.headline (2 lignes max) + summary.metaphore (2 lignes max, loi 9).
    // Le reveal anime déjà le trim (~1,2 s ease-out) et le count-up dans
    // ScoreRingView/AnimatedNumberView — gelés si reduce-motion.
    private var heroSection: some View {
        VStack(spacing: Theme.spacingMD) {
            ScoreRingView(score: viewModel.healthScore, size: 140, lineWidth: 12)

            // Pill état global + streak discret
            HStack(spacing: Theme.spacingSM) {
                Text(scoreLabel)
                    .pillStyle(color: Color.globalScoreColor(for: viewModel.healthScore))

                if gamification.currentStreak > 0 && !gamification.isZenMode {
                    HStack(spacing: Theme.spacingXS) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                        Text("\(gamification.currentStreak)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color.accentSky)
                    .padding(.horizontal, Theme.spacingSM)
                    .padding(.vertical, Theme.spacingXS)
                    .background(Color.accentSky.opacity(Theme.opacityMedium))
                    .clipShape(Capsule())
                    .accessibilityLabel("Série de \(gamification.currentStreak) \(gamification.currentStreak > 1 ? "jours" : "jour")")
                }
            }

            // Headline IA — texte libre : 2 lignes max (loi 9)
            if let headline = viewModel.aiAnalysis?.summary?.headline, !headline.isEmpty {
                Text(headline)
                    .font(Theme.headlineFont)
                    .foregroundStyle(Color.healthMapText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Métaphore en citation — texte libre : 2 lignes max (loi 9)
            if let metaphore = viewModel.aiAnalysis?.summary?.metaphore, !metaphore.isEmpty {
                HStack(alignment: .top, spacing: Theme.spacingSM) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.healthMapBlue.opacity(0.5))
                        .padding(.top, 2)
                        .accessibilityHidden(true)

                    Text(metaphore)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(Color.healthMapSecondary)
                        .italic()
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.spacingSM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.healthMapBlueLight.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
            }

            // Ligne discrète « Comment ce score est calculé » → petite sheet
            Button {
                HapticService.shared.selection()
                showScoreInfo = true
            } label: {
                HStack(spacing: Theme.spacingXS) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .accessibilityHidden(true)
                    Text("Comment ce score est calculé")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.healthMapSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityHint("Ouvre une courte explication du calcul du score.")
        }
        .padding(Theme.spacingLG)
        .frame(maxWidth: .infinity)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Sheet « Comment ce score est calculé »
    private var scoreInfoSheet: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "function")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.healthMapBlue)
                    .accessibilityHidden(true)

                Text("Comment ce score est calculé")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Color.healthMapText)
            }

            Text("Tes scores sont calculés localement, à partir de tes réponses au questionnaire\u{202F}: alimentation, mode de vie, besoins spécifiques. Chaque nutriment reçoit un score de 0 à 100, et le score global les combine. L\u{2019}analyse IA ajoute des explications personnalisées, mais ne modifie jamais tes scores. HealthMap ne remplace pas un avis médical.")
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(Theme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - « Ta priorité n°1 » (bloc 2)
    // Source : priority_actions[0] — action (2 lignes max), expected_impact
    // (1 ligne, ligne secondaire, PAS une pill — loi 9), pill difficulty en
    // vocabulaire contrôlé uniquement (loi 8).
    private func priorityCard(_ action: PriorityAction) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "target")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.healthMapBlue)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                Text("TA PRIORITÉ N°1")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.healthMapBlue)
                    .tracking(0.5)

                Spacer()

                if let difficulty = difficultyLabel(action.difficulty) {
                    Text(difficulty)
                        .pillStyle(color: Color.healthMapBlue)
                }
            }

            if let titre = action.action {
                Text(titre)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let impact = action.expectedImpact, !impact.isEmpty {
                Text(impact)
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.healthMapBlueLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Color.healthMapBlue.opacity(Theme.opacityMedium), lineWidth: 1)
        )
        .padding(.horizontal, Theme.spacingLG)
        .accessibilityElement(children: .combine)
    }

    /// Mapping difficulty → vocabulaire contrôlé (loi 8) : une valeur hors
    /// enum ne produit AUCUNE pill (jamais de texte libre IA dans une pill).
    private func difficultyLabel(_ raw: String?) -> String? {
        switch raw?.lowercased() {
        case "easy": return "Facile"
        case "medium": return "Modéré"
        case "hard": return "Exigeant"
        default: return nil
        }
    }

    // MARK: - « À surveiller (N) » (bloc 3)
    // Source : viewModel.deficiencies (échelle unique, score < 70), top 3 en
    // cartes JUMELLES (même structure exacte — loi 6). « Pourquoi ? » ouvre
    // la fiche nutriment existante (pattern universel — loi 10).
    private var watchSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.healthMapBlue)
                    .accessibilityHidden(true)

                Text("À surveiller (\(viewModel.deficiencies.count))")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Color.healthMapText)
            }
            .padding(.horizontal, Theme.spacingLG)

            VStack(spacing: Theme.spacingSM) {
                ForEach(Array(viewModel.deficiencies.prefix(3))) { nutrient in
                    NutrientWatchCard(nutrient: nutrient) {
                        HapticService.shared.tap()
                        selectedNutrient = nutrient
                        showNutrientDetail = true
                    }
                }
            }
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - Rangée symétrique Points forts / Interaction (bloc 5)
    // Sources : positive_findings[0].finding / interactions_detectees[0].titre
    // (2 lignes max chacun — loi 9). Tuiles strictement identiques (loi 6) ;
    // donnée manquante → état utile, jamais de coquille vide (loi 11).
    private var insightTilesRow: some View {
        HStack(spacing: Theme.spacingSM) {
            InsightTile(
                header: "Points forts",
                icon: "checkmark.seal.fill",
                text: strengthText,
                tint: Color.scoreExcellent
            )

            InsightTile(
                header: "Interaction",
                icon: "link",
                text: interactionText,
                tint: Color.accentIndigo
            )
        }
        // Hauteurs STRICTEMENT égales (loi 6) : le HStack prend la hauteur
        // de la tuile la plus haute, et chaque tuile (maxHeight: .infinity)
        // s'étire pour la remplir.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.spacingLG)
    }

    private var strengthText: String {
        if let finding = viewModel.aiAnalysis?.positiveFindings.first?.finding,
           !finding.isEmpty {
            return finding
        }
        // État utile sans analyse : compte local (pluriel dynamique, loi 15)
        let count = viewModel.goodNutrients
        if count == 0 {
            return "Chaque action de ton plan va te faire progresser"
        }
        let noun = count == 1 ? "nutriment solide" : "nutriments solides"
        return "\(count) \(noun) sur \(viewModel.nutrients.count)"
    }

    private var interactionText: String {
        if let titre = viewModel.aiAnalysis?.interactions.first?.titre,
           !titre.isEmpty {
            return titre
        }
        return viewModel.aiAnalysis != nil
            ? "Aucune interaction détectée"
            : "Disponible après l\u{2019}analyse"
    }

    // MARK: - Case premium floutée (bloc 7)
    // Source : hack du 1er deficiency (titre lisible qui tease, contenu réel
    // flouté — loi 11). Pas de hack disponible → pas de case (jamais vide).
    private var premiumHackSection: AnyView? {
        guard let first = viewModel.deficiencies.first,
              let hack = first.hack, !hack.isEmpty else { return nil }

        return AnyView(
            BlurredSection(isPremium: true, title: "Le hack \(first.label)") {
                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    HStack(spacing: Theme.spacingSM) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentSky)
                            .accessibilityHidden(true)

                        Text("Le hack \(first.label)")
                            .font(Theme.captionBoldFont)
                            .foregroundStyle(Color.healthMapText)
                    }

                    // Hack — texte libre IA : 3 lignes max (loi 9), hauteur
                    // bornée même floutée pour les non-premium.
                    Text(hack)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.healthMapText)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.spacingMD)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .padding(.horizontal, Theme.spacingLG)
        )
    }

    // MARK: - Fin positive (bloc 8)
    // « Ton plan est prêt → » ouvre l'onglet Plan via le mécanisme de
    // navigation existant (NotificationCenter → MainTabView.selectedTab).
    private var planReadyCard: some View {
        Button {
            HapticService.shared.tap()
            NotificationCenter.default.post(
                name: .healthmapNavigateToTab,
                object: NavCardDestination.plan.rawValue
            )
        } label: {
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                HStack(spacing: Theme.spacingSM) {
                    Text("Ton plan est prêt")
                        .font(Theme.headlineFont)
                        .foregroundStyle(Color.healthMapBlue)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.healthMapBlue)
                        .accessibilityHidden(true)
                }

                Text("Ton score évoluera à ton prochain bilan.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
            }
            .padding(Theme.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.healthMapBlueLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Color.healthMapBlue.opacity(Theme.opacityMedium), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.healthMapPressed)
        .padding(.horizontal, Theme.spacingLG)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ton plan est prêt. Ton score évoluera à ton prochain bilan.")
        .accessibilityHint("Ouvre l\u{2019}onglet Mon Plan.")
    }

    // MARK: - Bandeau chargement analyse IA
    /// Affiché pendant le premier chargement de l'analyse IA, sous le héro —
    /// le score déterministe reste visible et utilisable.
    private var analysisLoadingBanner: some View {
        HStack(spacing: Theme.spacingSM) {
            // Mascotte en réflexion pendant que l'IA travaille — plus
            // chaleureux qu'un spinner nu (l'activité reste signalée par
            // le texte et l'animation d'idle de la mascotte).
            MascotView(mood: .thinking, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Analyse IA en cours…")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapText)

                Text("Tes scores ci-dessous sont déjà calculés. Les explications personnalisées arrivent.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.healthMapBlueLight)
        )
        .padding(.horizontal, Theme.spacingLG)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyse IA en cours. Tes scores sont déjà calculés.")
    }

    // MARK: - Score Label
    // Mot d'état du score global : échelle unique HealthScale (loi 4).
    var scoreLabel: String {
        HealthScale.globalLabel(for: viewModel.healthScore)
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
            .offset(y: appeared ? 0 : 12)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.healthMapSpring.delay(Double(index) * 0.06)) {
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

#Preview {
    DashboardView()
        .environmentObject(DashboardViewModel())
}
