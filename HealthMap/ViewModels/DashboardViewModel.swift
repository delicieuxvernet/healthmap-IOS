import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: - Published State

    @Published var profile: UserProfile = .empty
    @Published var aiAnalysis: MergedAnalysis?
    @Published var isLoadingProfile = false
    @Published var isLoadingAnalysis = false
    @Published var healthScore: Int = 0
    @Published var nutrientScores: [String: Int] = [:]
    @Published var hasCompletedQuestionnaire = false
    @Published var errorMessage: String?

    // MARK: - Injected Services

    private let authService: AuthServiceProtocol
    private let databaseService: DatabaseServiceProtocol
    private let subscriptionService: SubscriptionServiceProtocol
    private let analyticsService: AnalyticsServiceProtocol
    private let aiAnalysisService: AIAnalysisServiceProtocol
    let gamificationService: GamificationService

    // MARK: - Computed (PhysicalMetrics)

    var physicalMetrics: PhysicalMetrics {
        PhysicalMetrics(profile: profile)
    }

    // MARK: - Computed (Analysis)

    var nutrients: [EnrichedNutrient] {
        aiAnalysis?.nutrients ?? []
    }

    var topDeficiencies: [EnrichedNutrient] {
        aiAnalysis?.topDeficiencies ?? []
    }

    var redFlags: [RedFlag] {
        aiAnalysis?.redFlags ?? []
    }

    var summaryHeadline: String? {
        aiAnalysis?.summary?.headline
    }

    var overallScore: Int {
        aiAnalysis?.overallScore ?? (healthScore / 10)
    }

    var deficiencies: [EnrichedNutrient] {
        nutrients.filter { $0.score < 60 }.sorted { $0.score < $1.score }
    }

    var goodNutrients: Int {
        nutrients.filter { $0.score >= 60 }.count
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
    /// Only fires if the previous analysis failed (aiAnalysis is nil and questionnaire
    /// is completed), so a successful cached state is never disrupted.
    private func observeReconnect() {
        reconnectObserver = NotificationCenter.default.addObserver(
            forName: .healthmapDidReconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.hasCompletedQuestionnaire, self.aiAnalysis == nil else { return }
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
            return
        }

        let userId = session.user.id.uuidString
        isLoadingProfile = true
        errorMessage = nil

        do {
            if let profileRow = try await databaseService.loadProfile(userId: userId) {
                if let questionnaireData = profileRow.questionnaireData {
                    self.profile = questionnaireData
                    self.hasCompletedQuestionnaire = questionnaireData.completed
                } else {
                    self.profile = .empty
                    self.hasCompletedQuestionnaire = false
                }
            }
        } catch {
            errorMessage = "Impossible de charger votre profil."
            AppLogger.database.report(error, context: "Dashboard load profile")
        }

        isLoadingProfile = false

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
        guard hasCompletedQuestionnaire else {
            healthScore = 0
            nutrientScores = [:]
            return
        }

        healthScore = HealthCalculator.calculateHealthScore(profile: profile)
        nutrientScores = HealthCalculator.analyzeNutrientScores(profile: profile)
    }

    // MARK: - Trigger AI Analysis

    func triggerAnalysis() async {
        guard hasCompletedQuestionnaire else { return }
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
            }

            analyticsService.track(.analysisCompleted, properties: [
                "health_score": healthScore,
                "deficiencies_count": aiAnalysis?.topDeficiencies.count ?? 0,
            ])
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
                            errorMessage = "Impossible de charger ton analyse pour le moment. Verifie ta connexion puis reessaie."
                        }
                    } else {
                        errorMessage = "Impossible de charger ton analyse pour le moment. Verifie ta connexion puis reessaie."
                    }
                } catch {
                    errorMessage = "Impossible de charger ton analyse pour le moment. Verifie ta connexion puis reessaie."
                    AppLogger.analysis.report(error, context: "Dashboard fallback cache load")
                }
            }
            // Local scores remain available even if AI fails — the
            // deterministic computeLocalScores() in loadProfile already
            // populated `healthScore` so the score ring still works.
        }

        isLoadingAnalysis = false
    }

    // MARK: - Regenerate Analysis (force refresh)

    func regenerateAnalysis() async {
        guard hasCompletedQuestionnaire else { return }

        guard let session = await AuthService.shared.currentSession else {
            return
        }

        let userId = session.user.id.uuidString
        isLoadingAnalysis = true
        errorMessage = nil

        do {
            let merged = try await aiAnalysisService.regenerate(
                userId: userId,
                profile: profile
            )

            self.aiAnalysis = merged

            if let merged {
                self.healthScore = merged.healthScore
                self.nutrientScores = merged.scores
            }

            analyticsService.track(.analysisCompleted, properties: [
                "health_score": healthScore,
                "regenerated": true,
            ])
        } catch {
            errorMessage = "Impossible de regenerer l'analyse."
            AppLogger.analysis.report(error, context: "Dashboard regenerate")
            analyticsService.track(.analysisFailed, properties: [
                "error": error.localizedDescription,
                "regenerated": true,
            ])
        }

        isLoadingAnalysis = false
    }
}
