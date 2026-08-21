import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: - Published State

    @Published var profile: UserProfile = .empty
    @Published var aiAnalysis: MergedAnalysis?
    /// Bilan v2 (contrat v2) — nourrit le NOUVEL écran Bilan (v6). Le flux v7
    /// (`aiAnalysis`) continue de nourrir Plan/Compléments jusqu'à la vague V4.
    @Published var analysisV2: AIAnalysisV2?
    @Published var isLoadingProfile = false
    @Published var isLoadingAnalysis = false
    @Published var isLoadingAnalysisV2 = false
    @Published var healthScore: Int = 0
    @Published var nutrientScores: [String: Int] = [:]
    @Published var hasCompletedQuestionnaire = false
    /// Passe à `true` une fois le PREMIER `loadProfile` terminé (succès, échec
    /// ou pas de session) — succès OU échec. Tant qu'il est `false`, la racine
    /// (`MainTabView`) tient un écran de chargement propre AU LIEU de rendre
    /// une branche dont l'état n'est pas encore connu : sinon, au démarrage à
    /// froid, `hasCompletedQuestionnaire` valant `false` par défaut faisait
    /// clignoter le questionnaire (ou les onglets verrouillés) une fraction de
    /// seconde avant de basculer sur le Dashboard (« écrans faux » au réveil).
    @Published var didFinishInitialLoad = false
    /// Questionnaire présenté par-dessus les onglets (feuille plein écran de
    /// MainTabView). Piloté par `demarrerBilan()` ; remis à false à la
    /// fermeture (« Explorer d'abord », glissement, ou fin du questionnaire).
    @Published var questionnaireOuvert = false
    @Published var errorMessage: String?
    /// Erreur dédiée au bilan v2 (écran de chargement/gate onboarding).
    /// Distincte de `errorMessage` (v7, autre bandeau) pour ne pas faire
    /// courir de risque de course entre les deux tâches parallèles — un raté
    /// v7 ne doit jamais afficher/masquer une erreur qui concerne le v2 et
    /// inversement (incident bilan indisponible, 4 juillet : la gate bloquait
    /// sur `aiAnalysis`/v7 alors que le bilan RÉELLEMENT affiché est v2).
    @Published var errorMessageV2: String?
    /// L'utilisateur a demandé à explorer l'app pendant que le bilan se fait
    /// attendre : la gate plein écran (`AnalysisGateView`) ne se rouvre plus de
    /// la session. Le bilan continue d'arriver en tâche de fond.
    @Published var gateContournee = false
    /// Le récap animé attend le bilan pour se jouer.
    ///
    /// Armé UNIQUEMENT à la fin du questionnaire, jamais au lancement : sinon
    /// tout utilisateur déjà installé se serait pris la séquence en pleine
    /// figure à la première ouverture après mise à jour. Il se rejoue à la
    /// demande depuis le profil (« Revoir mon bilan animé »).
    @Published var recapArme = false

    // MARK: - Injected Services

    private let authService: AuthServiceProtocol
    private let databaseService: DatabaseServiceProtocol
    private let subscriptionService: SubscriptionServiceProtocol
    private let analyticsService: AnalyticsServiceProtocol
    private let aiAnalysisService: AIAnalysisServiceProtocol
    let gamificationService: GamificationService

    // MARK: - Entrée libre (V12a)

    /// Bilan complété — point d'observation UNIQUE pour toutes les vues.
    /// Source : `questionnaire_data.completed` du profil, portée par le
    /// @Published `hasCompletedQuestionnaire` (mis à jour immédiatement à la
    /// soumission du questionnaire, sans relance de l'app). Alias sémantique :
    /// le nouveau code lit `bilanComplete`, l'existant reste inchangé.
    var bilanComplete: Bool { hasCompletedQuestionnaire }

    /// Décision fondateur (V12a) : aucune porte premium tant que le bilan
    /// n'est pas fait. Toutes les cartes / pills / portes paywall se
    /// conditionnent ici plutôt que sur `!isPremium` copié partout.
    var premiumVisible: Bool { bilanComplete && !subscriptionService.isPremium }

    /// Lance (ou reprend) le bilan depuis n'importe quel onglet. Le draft du
    /// questionnaire est restauré par QuestionnaireViewModel — la reprise se
    /// fait à la question en cours. À la fermeture de la feuille,
    /// l'utilisateur retrouve l'onglet d'où il est parti.
    func demarrerBilan() {
        questionnaireOuvert = true
    }

    // MARK: - État d'affichage de l'onglet Bilan (V12b)

    /// Route du contenu de l'onglet Bilan — miroir EXACT du switch historique
    /// de `DashboardView.content`, extrait ici pour être testable sans UI.
    enum BilanAffichage {
        /// Bilan v2 valide → le dashboard v7 avec les vraies données.
        case bilan
        /// Questionnaire complété, bilan pas encore là (chargement / erreur).
        case attente
        /// Pas encore de bilan → le dashboard v7 en mode découverte (teaser
        /// in-situ V12b : stats France sourcées + CTA questionnaire).
        case decouverte
    }

    var bilanAffichage: BilanAffichage {
        if let v2 = analysisV2, v2.isValidV2 { return .bilan }
        if profile.completed { return .attente }
        return .decouverte
    }

    // MARK: - Computed (PhysicalMetrics)

    var physicalMetrics: PhysicalMetrics {
        PhysicalMetrics(profile: profile)
    }

    // MARK: - Computed (Analysis)

    /// Nutriments affichés par le Dashboard. L'analyse IA enrichit les scores
    /// locaux quand elle est disponible ; sinon on affiche les scores LOCAUX
    /// seuls (HealthCalculator) — le bilan ne doit JAMAIS être vide ou à 0
    /// quand le questionnaire est complété (incident TestFlight 28).
    var nutrients: [EnrichedNutrient] {
        if let merged = aiAnalysis { return merged.nutrients }
        return localNutrients
    }

    /// Nutriments construits uniquement à partir des scores locaux
    /// (déterministes) — affichés pendant le chargement de l'analyse IA
    /// ou quand elle échoue. Labels/emojis/couleurs : catalogue canonique.
    private var localNutrients: [EnrichedNutrient] {
        guard profile.completed, !nutrientScores.isEmpty else { return [] }
        return NutrientData.all.map { def in
            let score = nutrientScores[def.id.rawValue] ?? 50
            return EnrichedNutrient(
                id: def.id.rawValue,
                label: def.label,
                emoji: def.emoji,
                color: def.colorHex,
                score: score,
                status: NutrientStatus(score: score).rawValue,
                confidence: score < 40 ? "high" : score < 60 ? "moderate" : "low"
            )
        }
    }

    var topDeficiencies: [EnrichedNutrient] {
        Array(deficiencies.prefix(3))
    }

    /// Red flags : ceux du merge IA si disponible, sinon détection LOCALE
    /// (RedFlagDetector est un mirror déterministe de health.js — les alertes
    /// de sécurité ne doivent pas attendre l'analyse IA).
    var redFlags: [RedFlag] {
        if let merged = aiAnalysis { return merged.redFlags }
        guard profile.completed else { return [] }
        return RedFlagDetector.detect(profile: profile)
    }

    var summaryHeadline: String? {
        aiAnalysis?.summary?.headline
    }

    var overallScore: Int {
        aiAnalysis?.overallScore ?? (healthScore / 10)
    }

    var deficiencies: [EnrichedNutrient] {
        // Seuil aligné sur l'échelle unique HealthScale (loi 3) :
        // « Solide » commence à 70 — en dessous, le nutriment est à surveiller.
        nutrients.filter { $0.score < 70 }.sorted { $0.score < $1.score }
    }

    var goodNutrients: Int {
        nutrients.filter { $0.score >= 70 }.count
    }

    var interactionsCount: Int {
        aiAnalysis?.interactions.count ?? 0
    }

    var actionDuJour: (titre: String, description: String?)? {
        // Priority 1: AI action_du_jour (not in current model, use priority_actions)
        if let actions = aiAnalysis?.priorityActions, let first = actions.sorted(by: { ($0.rank ?? 0) < ($1.rank ?? 0) }).first {
            return (titre: first.action ?? "Consulte ton plan", description: first.expectedImpact)
        }
        // Priority 2: First deficiency solution
        if let def = deficiencies.first, let sol = def.solution?.action {
            return (titre: sol, description: "Pour ameliorer ton \(def.label)")
        }
        return nil
    }

    var pepiteDuJour: PracticalTip? {
        let pepites = aiAnalysis?.pepites ?? []
        guard !pepites.isEmpty else { return nil }
        // Deterministic daily rotation
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return pepites[dayOfYear % pepites.count]
    }

    var firstName: String {
        profile.firstName.isEmpty ? "" : profile.firstName
    }

    // MARK: - Private

    private var reconnectObserver: Any?
    private var initTask: Task<Void, Never>?
    /// Email du profil chargé — réutilisé lors des UPDATE ciblés (ex. avatar)
    /// pour ne pas écraser la colonne `email` avec une chaîne vide.
    private var loadedEmail: String = ""

    // MARK: - Init

    init(
        auth: AuthServiceProtocol = AuthService.shared,
        database: DatabaseServiceProtocol = DatabaseService.shared,
        subscription: SubscriptionServiceProtocol = SubscriptionService.shared,
        analytics: AnalyticsServiceProtocol = AnalyticsService.shared,
        aiAnalysis: AIAnalysisServiceProtocol = AIAnalysisService.shared,
        gamification: GamificationService = GamificationService.shared
    ) {
        self.authService = auth
        self.databaseService = database
        self.subscriptionService = subscription
        self.analyticsService = analytics
        self.aiAnalysisService = aiAnalysis
        self.gamificationService = gamification

        initTask = Task {
            await loadProfile()
        }
        // Filet de sécurité : ne JAMAIS piéger l'utilisateur sur l'écran de
        // chargement racine si le fetch profil traîne (réseau cassé, SDK bloqué).
        // Passé 8 s, on autorise le routing avec l'état dont on dispose — même
        // esprit que le garde-fou de 10 s d'`AuthViewModel.isLoading`.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.didFinishInitialLoad = true
        }
        observeReconnect()
    }

    deinit {
        initTask?.cancel()
        if let observer = reconnectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Reconnect Observer

    /// Re-triggers AI analysis when the network comes back after an offline period.
    /// Only fires if the bilan (v2, réellement affiché) n'a pas encore de résultat
    /// et que le questionnaire est complet, so a successful cached state is never
    /// disrupted. Gardé sur `analysisV2` (pas `aiAnalysis`/v7) depuis l'incident du
    /// 4 juillet — sinon un raté v7 seul peut redéclencher un appel inutile alors
    /// que le vrai bilan (v2) est déjà là.
    private func observeReconnect() {
        reconnectObserver = NotificationCenter.default.addObserver(
            forName: .healthmapDidReconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.hasCompletedQuestionnaire, self.analysisV2 == nil else { return }
            Task { @MainActor in
                AppLogger.analysis.info("Reconnect: retrying AI analysis")
                await self.triggerAnalysis()
            }
        }
    }

    // MARK: - Load Profile

    func loadProfile() async {
        // Re-entrancy guard: prevent concurrent loads from init Task +
        // explicit call from QuestionnaireContainerView or reconnect.
        guard !isLoadingProfile else { return }

        guard let session = await AuthService.shared.currentSession else {
            // Pas de session résolue : on a « essayé », on débloque le routing
            // pour ne pas rester coincé sur l'écran de chargement racine.
            didFinishInitialLoad = true
            return
        }

        let userId = session.user.id.uuidString
        isLoadingProfile = true
        errorMessage = nil

        do {
            if let profileRow = try await databaseService.loadProfile(userId: userId) {
                self.loadedEmail = profileRow.email ?? self.loadedEmail
                if let questionnaireData = profileRow.questionnaireData {
                    self.profile = questionnaireData
                    self.hasCompletedQuestionnaire = questionnaireData.completed
                } else {
                    self.profile = .empty
                    // Conserve le prénom déjà connu (signup email OU Sign in with
                    // Apple → profiles.first_name) même sans questionnaire, pour ne
                    // PAS le redemander dans l'onboarding (App Review Guideline 4).
                    self.profile.firstName = profileRow.firstName ?? ""
                    self.hasCompletedQuestionnaire = false
                }
                // `baseline_nutrient_scores` est une colonne sœur de
                // `questionnaire_data` (pas imbriquée dedans) : on la fusionne
                // manuellement dans le profil en mémoire.
                self.profile.baselineNutrientScores = profileRow.baselineNutrientScores
            }
        } catch {
            errorMessage = "Impossible de charger ton profil pour le moment."
            AppLogger.database.report(error, context: "Dashboard load profile")
        }

        isLoadingProfile = false

        // Hydrate le bilan v2 depuis le CACHE DB si le profil n'a pas changé
        // (hash identique) — AVANT de débloquer le routing et de lancer
        // l'analyse. Sinon `analysisV2` reste nil pendant le round-trip de
        // `fetchBilanV2`, et la gate de chargement plein écran (AnalysisGateView,
        // condition `analysisV2 == nil && isLoadingAnalysisV2`) CLIGNOTE à chaque
        // ouverture. En posant le bilan caché ici, la gate ne s'affiche plus que
        // pour un tout premier bilan (aucun cache) ou un profil modifié (hash
        // différent). Lecture DB pure — aucun appel IA. `triggerAnalysis()`
        // rafraîchira ensuite en arrière-plan sans re-vider `analysisV2`.
        if hasCompletedQuestionnaire, analysisV2 == nil {
            let hash = AIAnalysisService.hashProfile(profile)
            // `(try? …) ?? nil` aplatit le double-optionnel (la fonction rend déjà
            // `AIAnalysisV2?`) — même motif que dans AIAnalysisService.fetchBilanV2.
            if let cached = (try? await databaseService.loadAIAnalysisV2(userId: userId)) ?? nil,
               cached.meta?.profileHash == hash {
                analysisV2 = cached
            }
        }

        // Le statut de routing (`hasCompletedQuestionnaire`) est désormais
        // connu → on peut afficher la bonne branche sans clignotement.
        didFinishInitialLoad = true

        // Compute local scores immediately (deterministic, no async needed)
        computeLocalScores()

        // Cross-platform sync: merge streaks from web (healthmap.fr)
        // Runs concurrently — does not block AI analysis loading
        Task { await gamificationService.configure(userId: userId) }

        // If questionnaire completed, trigger AI analysis
        if hasCompletedQuestionnaire {
            await triggerAnalysis()
        }

        analyticsService.track(.dashboardViewed, properties: nil)
    }

    // MARK: - Compute Local Scores

    /// Computes health scores from the local profile without a server call.
    /// Called from `loadProfile()` and from the questionnaire submission
    /// flow to populate the dashboard immediately without waiting for a re-fetch.
    func computeLocalScores() {
        // Garde sur `profile.completed` (PAS sur hasCompletedQuestionnaire) :
        // à la soumission du questionnaire, le flag publié reste false tant
        // que la célébration est affichée (il pilote le switch d'onglet dans
        // MainTabView) — mais les scores doivent déjà être calculables.
        // Bug TestFlight 28 : l'ancienne garde laissait healthScore à 0 →
        // célébration « 0/100 » avec croix.
        guard profile.completed else {
            healthScore = 0
            nutrientScores = [:]
            return
        }

        healthScore = HealthCalculator.calculateHealthScore(profile: profile)
        nutrientScores = HealthCalculator.analyzeNutrientScores(profile: profile)

        captureBaselineIfNeeded()
    }

    // MARK: - Capture one-time de la baseline nutriments

    /// Fige la photo « départ » des scores nutriments au tout premier bilan.
    /// Le check `baselineNutrientScores == nil` garantit une exécution unique :
    /// une fois écrite, la colonne n'est jamais réécrite. Met aussi à jour la
    /// copie en mémoire du profil pour que la barre de couverture utilise la
    /// baseline dès le premier affichage. Non bloquant : un échec d'écriture
    /// n'est que loggué (l'utilisateur retentera au prochain chargement).
    private func captureBaselineIfNeeded() {
        guard profile.baselineNutrientScores == nil, !nutrientScores.isEmpty else { return }

        let baseline = nutrientScores
        // Copie en mémoire immédiate (la barre l'utilise tout de suite).
        profile.baselineNutrientScores = baseline

        Task { [databaseService] in
            guard let session = await AuthService.shared.currentSession else { return }
            let userId = session.user.id.uuidString
            do {
                try await databaseService.saveBaselineNutrientScores(userId: userId, scores: baseline)
            } catch {
                AppLogger.database.report(error, context: "Capture baseline nutrient scores")
            }
        }
    }

    // MARK: - Trigger AI Analysis

    func triggerAnalysis() async {
        // Même logique que computeLocalScores : l'analyse doit pouvoir démarrer
        // pendant la célébration post-questionnaire, avant le flip du flag UI.
        guard profile.completed else { return }
        // Re-entrancy guard: prevent concurrent analysis calls from
        // reconnect observer + loadProfile() + manual retry.
        guard !isLoadingAnalysis else { return }

        guard let session = await AuthService.shared.currentSession else {
            return
        }

        let userId = session.user.id.uuidString
        isLoadingAnalysis = true
        // Clear any previous error so the retry UI disappears immediately
        // when the user taps "Reessayer" — without this, the error card
        // would stay on screen overlapping the loading spinner.
        errorMessage = nil

        analyticsService.track(.analysisStarted, properties: nil)

        // Bilan v2 : part EN PARALLÈLE de l'appel v7 (deux tâches distinctes
        // sur le même endpoint). v2 nourrit le nouvel écran Bilan et n'est pas
        // bloqué par le v7 ; il gère son propre état (isLoadingAnalysisV2).
        Task { await self.fetchBilanV2(userId: userId, forceRefresh: false) }

        do {
            let merged = try await aiAnalysisService.fetchFullAnalysis(
                userId: userId,
                profile: profile
            )

            self.aiAnalysis = merged

            // Update scores from merged result (canonical source)
            if let merged {
                self.healthScore = merged.healthScore
                self.nutrientScores = merged.scores

                analyticsService.track(.analysisCompleted, properties: [
                    "health_score": healthScore,
                    "deficiencies_count": merged.topDeficiencies.count,
                ])
            } else {
                // Réponse IA inexploitable (nil après sanitization/validation) :
                // ce n'est PAS un succès. Les scores locaux restent affichés,
                // mais le bandeau de retry doit apparaître — jamais d'état
                // silencieux sans analyse ni erreur (incident TestFlight 28).
                errorMessage = "L'analyse n'a pas pu être générée. Tes scores restent disponibles, réessaie dans un instant."
                analyticsService.track(.analysisFailed, properties: [
                    "error": "nil_analysis_after_validation",
                ])
            }
        } catch {
            AppLogger.analysis.report(error, context: "Dashboard AI analysis")
            analyticsService.track(.analysisFailed, properties: [
                "error": error.localizedDescription,
            ])
            // Surface a user-facing message ONLY if we have nothing cached.
            // If `aiAnalysis` is non-nil (a previous successful run), the
            // user keeps seeing the cached dashboard and we silently fail.
            if aiAnalysis == nil {
                // Fallback: attempt to load the last cached analysis from Supabase.
                // The cached row is a raw AIAnalysisResponse. We can't re-merge it
                // here (mergeWithCanonical is internal to AIAnalysisService), but
                // loading via the service's own fetch path re-uses the cache check
                // that runs before hitting the edge function. If the DB itself is
                // unreachable we surface the user-facing error.
                do {
                    let cachedResponse = try await databaseService.loadAIAnalysis(userId: userId)
                    if cachedResponse != nil {
                        // The service will find the cached row and skip the edge call
                        // since the profile hash hasn't changed.
                        let retried = try await aiAnalysisService.fetchFullAnalysis(userId: userId, profile: profile)
                        if let retried {
                            self.aiAnalysis = retried
                            self.healthScore = retried.healthScore
                            self.nutrientScores = retried.scores
                            AppLogger.analysis.info("Loaded cached analysis as fallback after AI failure")
                        } else {
                            errorMessage = "Impossible de charger ton analyse pour le moment. Vérifie ta connexion puis réessaie."
                        }
                    } else {
                        errorMessage = "Impossible de charger ton analyse pour le moment. Vérifie ta connexion puis réessaie."
                    }
                } catch {
                    errorMessage = "Impossible de charger ton analyse pour le moment. Vérifie ta connexion puis réessaie."
                    AppLogger.analysis.report(error, context: "Dashboard fallback cache load")
                }
            }
            // Local scores remain available even if AI fails — the
            // deterministic computeLocalScores() in loadProfile already
            // populated `healthScore` so the score ring still works.
        }

        isLoadingAnalysis = false
    }

    // MARK: - Bilan v2 (contrat v2 — nouvel écran Bilan)

    /// Charge le bilan v2 : cache DB d'abord (géré par le service), sinon
    /// Edge Function (tache "bilan"). Tourne en parallèle du flux v7.
    private func fetchBilanV2(userId: String, forceRefresh: Bool) async {
        // Mêmes gardes que triggerAnalysis : l'analyse doit pouvoir démarrer
        // pendant la célébration post-questionnaire.
        guard profile.completed else { return }
        // Re-entrancy guard (reconnect + loadProfile + regenerate).
        guard !isLoadingAnalysisV2 else { return }
        isLoadingAnalysisV2 = true
        errorMessageV2 = nil
        defer { isLoadingAnalysisV2 = false }

        // Entrées déterministes — mêmes sources locales que le flux v7
        // (HealthCalculator / RedFlagDetector, mirrors de health.js).
        let localScores = HealthCalculator.analyzeNutrientScores(profile: profile)
        let localHealthScore = HealthCalculator.calculateHealthScore(profile: profile)
        let localFlags = RedFlagDetector.detect(profile: profile)
        let profileHash = AIAnalysisService.hashProfile(profile)

        do {
            analysisV2 = try await aiAnalysisService.fetchBilanV2(
                userId: userId,
                profileHash: profileHash,
                scores: localScores,
                healthScore: localHealthScore,
                redFlags: localFlags,
                forceRefresh: forceRefresh
            )
        } catch {
            AppLogger.analysis.report(error, context: "Dashboard bilan v2")
            // Surface une erreur exploitable par la gate onboarding UNIQUEMENT
            // si on n'a rien à montrer (pas de cache valide) — sinon le bilan
            // déjà affiché ne doit pas être remplacé par un bandeau d'erreur.
            if analysisV2 == nil {
                errorMessageV2 = (error as? AIAnalysisError)?.errorDescription
                    ?? "Impossible de charger ton bilan pour le moment. Réessaie dans un instant."
            }
        }
    }

    /// Relance le SEUL bilan v2 — celui que l'écran affiche réellement.
    ///
    /// ⚠️ Ne PAS rebrancher le « Réessayer » de la gate sur `triggerAnalysis()` :
    /// celui-ci commence par `guard !isLoadingAnalysis`, or les deux flux
    /// partent ensemble et le v7 tient jusqu'à 185 s. Le v2 pouvant échouer en
    /// deux secondes (429, circuit ouvert), le bouton restait un no-op
    /// totalement silencieux pendant tout ce temps.
    func retryBilanV2() async {
        guard let session = await AuthService.shared.currentSession else { return }
        await fetchBilanV2(userId: session.user.id.uuidString, forceRefresh: false)
    }

    // MARK: - Save Avatar Choice

    /// Persiste l'avatar morphologique choisi dans `questionnaire_data` (JSONB)
    /// sans toucher email/first_name. UPDATE uniquement (policy RLS).
    func saveAvatarKey(_ key: String) {
        profile.avatarKey = key
        Task {
            guard let session = await AuthService.shared.currentSession else { return }
            let userId = session.user.id.uuidString
            let email = session.user.email ?? loadedEmail
            do {
                try await databaseService.saveProfile(
                    userId: userId,
                    email: email,
                    firstName: profile.firstName,
                    questionnaireData: profile
                )
            } catch {
                AppLogger.database.report(error, context: "Save avatar key")
            }
        }
    }
}
