import XCTest
@testable import HealthMap

// MARK: - Dashboard ViewModel Tests
// Validates the deterministic local score computation and computed properties
// of DashboardViewModel. All tests use injected mocks — no network, no Supabase.
// DashboardViewModel is @MainActor, so all tests must be @MainActor too.

@MainActor
final class DashboardViewModelTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a "Thomas" profile: 28 y/o sportif omnivore (expect high scores).
    private func makeProfileThomas() -> UserProfile {
        var p = UserProfile.empty
        p.completed = true
        p.firstName = "Thomas"
        p.age = "28"
        p.gender = .homme
        p.height = "180"
        p.weight = "75"
        p.weightTrend = "stable"
        p.strengthTraining = "regular"
        p.indoorWork = "no"
        p.sunExposure = "moderate"
        p.skinType = "medium"
        p.stressLevel = "relaxed"
        p.sleepHours = "7.5"
        p.sleepDuration = "7.5"
        p.wakeFeeling = "great"
        p.screenBeforeBed = "short"
        p.caffeineIntake = "light"
        p.waterIntake = "2.25"
        p.smoking = .no
        p.alcohol = "rarely"
        p.bloating = "no"
        p.antibiotics = "no"
        p.dietType = "omnivore"
        p.mealsPerDay = "3"
        p.homeCookedPct = "mostly"
        p.cookingMethod = "mixed"
        p.vegetableServings = "10"
        p.fruitServings = "14"
        p.fattyFish = "3"
        p.meatPoultry = "5"
        p.eggsPerWeek = "5"
        p.dairyServings = "7"
        p.legumesPerWeek = "3"
        p.nutsPerWeek = "5"
        p.seedsPerDay = "1"
        p.wholegrainPerWeek = "5"
        p.breadType = "whole_grain"
        p.fermentedFoods = "sometimes"
        p.ultraProcessedFrequency = "rarely"
        p.snacking = "parfois"
        p.saltLevel = "moderate"
        p.iodizedSalt = "yes"
        p.eatLiver = "no"
        p.lowCarbDiet = "no"
        p.supplementsCurrent = []
        p.symptoms = []
        p.medications = []
        p.digestiveConditions = []
        return p
    }

    /// Builds a "Lea" profile: 35 y/o stressed vegetarian with deficiencies.
    private func makeProfileLea() -> UserProfile {
        var p = UserProfile.empty
        p.completed = true
        p.firstName = "Lea"
        p.age = "35"
        p.gender = .femme
        p.height = "165"
        p.weight = "58"
        p.weightTrend = "stable"
        p.strengthTraining = "light"
        p.indoorWork = "yes"
        p.sunExposure = "very_little"
        p.skinType = "fair"
        p.stressLevel = "very"
        p.sleepHours = "5.5"
        p.sleepDuration = "5.5"
        p.wakeFeeling = "bad"
        p.screenBeforeBed = "long"
        p.caffeineIntake = "heavy"
        p.waterIntake = "0.75"
        p.smoking = .no
        p.alcohol = "moderate"
        p.bloating = "yes"
        p.antibiotics = "no"
        p.dietType = "vegetarien"
        p.mealsPerDay = "2"
        p.homeCookedPct = "half"
        p.cookingMethod = "boiled"
        p.vegetableServings = "3"
        p.fruitServings = "4"
        p.fattyFish = "0"
        p.meatPoultry = "0"
        p.eggsPerWeek = "2"
        p.dairyServings = "3"
        p.legumesPerWeek = "1"
        p.nutsPerWeek = "1"
        p.seedsPerDay = "0"
        p.wholegrainPerWeek = "2"
        p.breadType = "white"
        p.fermentedFoods = "never"
        p.ultraProcessedFrequency = "often"
        p.snacking = "souvent"
        p.saltLevel = "moderate"
        p.iodizedSalt = "no"
        p.eatLiver = "no"
        p.lowCarbDiet = "no"
        p.supplementsCurrent = []
        p.symptoms = ["fatigue", "hair_loss"]
        p.medications = []
        p.digestiveConditions = []
        p.periodFlow = "very_heavy"
        p.pregnancyStatus = "na"
        return p
    }

    /// Creates a DashboardViewModel with the profile pre-injected,
    /// bypassing loadProfile() which requires Supabase auth.
    /// `subscription` / `aiAnalysis` sont injectables pour les tests
    /// d'entrée libre (premiumVisible, invariant generate-analysis).
    /// Défauts `nil` construits DANS le corps (MainActor) : un défaut
    /// d'argument s'évalue en contexte nonisolated → le mock @MainActor
    /// n'y est pas constructible (erreur CI Xcode 26).
    private func makeVM(
        profile: UserProfile,
        subscription: MockSubscriptionService? = nil,
        aiAnalysis: MockAIAnalysisService? = nil
    ) -> DashboardViewModel {
        let vm = DashboardViewModel(
            auth: MockAuthService(),
            database: MockDatabaseService(),
            subscription: subscription ?? MockSubscriptionService(),
            analytics: MockAnalyticsService(),
            aiAnalysis: aiAnalysis ?? MockAIAnalysisService(),
            gamification: GamificationService.shared
        )
        vm.profile = profile
        vm.hasCompletedQuestionnaire = profile.completed
        return vm
    }

    // MARK: - computeLocalScores

    /// A completed healthy profile should produce non-zero scores.
    func testComputeLocalScores_completedProfile_setsNonZeroScores() {
        let vm = makeVM(profile: makeProfileThomas())
        vm.computeLocalScores()

        XCTAssertGreaterThan(vm.healthScore, 0, "Thomas health score should be > 0")
        XCTAssertFalse(vm.nutrientScores.isEmpty, "Nutrient scores should be populated")
    }

    /// An incomplete questionnaire should reset scores to zero.
    func testComputeLocalScores_incompleteQuestionnaire_resetsToZero() {
        var incomplete = UserProfile.empty
        incomplete.completed = false
        let vm = makeVM(profile: incomplete)
        vm.hasCompletedQuestionnaire = false
        vm.computeLocalScores()

        XCTAssertEqual(vm.healthScore, 0, "Incomplete questionnaire should have zero health score")
        XCTAssertTrue(vm.nutrientScores.isEmpty, "Incomplete questionnaire should have empty nutrient scores")
    }

    /// A deficient profile (Lea) should produce lower scores than a healthy one.
    func testComputeLocalScores_deficientProfile_lowScore() {
        let vm = makeVM(profile: makeProfileLea())
        vm.computeLocalScores()

        XCTAssertLessThan(vm.healthScore, 50, "Lea (stressed vegetarian) should score < 50, got \(vm.healthScore)")
    }

    /// Calling computeLocalScores twice with the same data should produce identical results.
    func testComputeLocalScores_calledTwice_isIdempotent() {
        let vm = makeVM(profile: makeProfileThomas())
        vm.computeLocalScores()
        let firstScore = vm.healthScore
        let firstNutrients = vm.nutrientScores

        vm.computeLocalScores()
        XCTAssertEqual(vm.healthScore, firstScore, "Score should be idempotent")
        XCTAssertEqual(vm.nutrientScores, firstNutrients, "Nutrient scores should be idempotent")
    }

    // MARK: - overallScore

    /// When AI analysis provides an overallScore, it should be used.
    func testOverallScore_withAIAnalysis_usesAIScore() {
        let vm = makeVM(profile: makeProfileThomas())
        vm.computeLocalScores()

        // Simulate AI analysis with a specific overallScore
        let summary = AnalysisSummary(overallScore: 8, overallLabel: "Bon", headline: "Test")
        let merged = MergedAnalysis(
            healthScore: vm.healthScore,
            scores: vm.nutrientScores,
            nutrients: [],
            redFlags: [],
            summary: summary,
            bilanDetail: nil,
            interactions: [],
            pepites: [],
            priorityActions: [],
            positiveFindings: [],
            supplementsSchedule: nil,
            bloodTests: nil,
            meta: nil
        )
        vm.aiAnalysis = merged

        XCTAssertEqual(vm.overallScore, 8, "Should use AI overall score when available")
    }

    /// Without AI analysis, overallScore should fall back to local healthScore / 10.
    func testOverallScore_withoutAI_fallsBackToLocal() {
        let vm = makeVM(profile: makeProfileThomas())
        vm.computeLocalScores()

        // No AI analysis set
        let expected = vm.healthScore / 10
        XCTAssertEqual(vm.overallScore, expected, "Without AI, should use healthScore / 10")
    }

    // MARK: - BMI (via HealthCalculator, consumed by DashboardViewModel.physicalMetrics)

    /// Standard BMI calculation: 75kg / (1.80m)^2 = 23.15 rounded to 23.1
    func testBMI_computesCorrectly() {
        let bmi = HealthCalculator.calculateBMI(weightKg: 75, heightCm: 180)
        XCTAssertNotNil(bmi)
        XCTAssertEqual(bmi!, 23.1, accuracy: 0.1, "BMI for 75kg/180cm should be ~23.1")
    }

    /// Missing weight or height should return nil.
    func testBMI_withMissingData_returnsNil() {
        XCTAssertNil(HealthCalculator.calculateBMI(weightKg: 0, heightCm: 180), "Zero weight should return nil")
        XCTAssertNil(HealthCalculator.calculateBMI(weightKg: 75, heightCm: 0), "Zero height should return nil")
    }

    // MARK: - deficiencies / goodNutrients

    /// Nutrients below 60 should appear in the deficiencies list.
    func testDeficiencies_filtersBelowThreshold() {
        let vm = makeVM(profile: makeProfileThomas())
        vm.computeLocalScores()

        // Inject an AI analysis with a mix of scores
        let nutrients = [
            EnrichedNutrient(id: "vitD", label: "Vitamine D", emoji: "☀️", color: "#007AFF", score: 30, status: "deficient"),
            EnrichedNutrient(id: "vitB12", label: "Vitamine B12", emoji: "🔴", color: "#0056CC", score: 80, status: "good"),
            EnrichedNutrient(id: "iron", label: "Fer", emoji: "🩸", color: "#5856D6", score: 45, status: "low"),
        ]
        let merged = MergedAnalysis(
            healthScore: 60,
            scores: ["vitD": 30, "vitB12": 80, "iron": 45],
            nutrients: nutrients,
            redFlags: [],
            summary: nil,
            bilanDetail: nil,
            interactions: [],
            pepites: [],
            priorityActions: [],
            positiveFindings: [],
            supplementsSchedule: nil,
            bloodTests: nil,
            meta: nil
        )
        vm.aiAnalysis = merged

        // deficiencies = score < 70 (HealthScale : « Solide » commence à 70)
        XCTAssertEqual(vm.deficiencies.count, 2, "Should have 2 deficiencies (vitD=30, iron=45)")
        // Sorted by score ascending
        XCTAssertEqual(vm.deficiencies.first?.id, "vitD", "Lowest score should be first")
    }

    /// Counts nutrients at or above the HealthScale "Solide" boundary (70) —
    /// fixture straddles the boundary on purpose (69 excluded, 70 included).
    func testGoodNutrients_countsAboveThreshold() {
        let vm = makeVM(profile: makeProfileThomas())
        let nutrients = [
            EnrichedNutrient(id: "vitD", label: "D", emoji: "☀️", color: "#007AFF", score: 30, status: "deficient"),
            EnrichedNutrient(id: "vitB12", label: "B12", emoji: "🔴", color: "#0056CC", score: 80, status: "good"),
            EnrichedNutrient(id: "iron", label: "Fer", emoji: "🩸", color: "#5856D6", score: 69, status: "adequate"),
            EnrichedNutrient(id: "magnesium", label: "Mg", emoji: "⚡", color: "#5856D6", score: 70, status: "good"),
        ]
        let merged = MergedAnalysis(
            healthScore: 60, scores: [:], nutrients: nutrients, redFlags: [],
            summary: nil, bilanDetail: nil, interactions: [], pepites: [],
            priorityActions: [], positiveFindings: [],
            supplementsSchedule: nil, bloodTests: nil, meta: nil
        )
        vm.aiAnalysis = merged

        XCTAssertEqual(vm.goodNutrients, 2, "Should count only nutrients with score >= 70 (80 and 70; 69 and 30 excluded)")
    }

    // MARK: - actionDuJour

    /// When priority actions exist, the first one (sorted by rank) should be returned.
    func testActionDuJour_withPriorityActions_returnsFirst() {
        let vm = makeVM(profile: makeProfileThomas())
        let actions = [
            PriorityAction(rank: 2, action: "Second action", expectedImpact: "Impact B", difficulty: "medium"),
            PriorityAction(rank: 1, action: "First action", expectedImpact: "Impact A", difficulty: "easy"),
        ]
        let merged = MergedAnalysis(
            healthScore: 70, scores: [:], nutrients: [], redFlags: [],
            summary: nil, bilanDetail: nil, interactions: [], pepites: [],
            priorityActions: actions, positiveFindings: [],
            supplementsSchedule: nil, bloodTests: nil, meta: nil
        )
        vm.aiAnalysis = merged

        let action = vm.actionDuJour
        XCTAssertNotNil(action, "Should have an action du jour")
        XCTAssertEqual(action?.titre, "First action", "Should return the action with rank 1")
    }

    // MARK: - pepiteDuJour

    /// Pepite du jour should rotate deterministically based on the day of the year.
    func testPepiteDuJour_rotatesDeterministically() {
        let vm = makeVM(profile: makeProfileThomas())
        let pepites = [
            PracticalTip(tip: "Tip A"),
            PracticalTip(tip: "Tip B"),
            PracticalTip(tip: "Tip C"),
        ]
        let merged = MergedAnalysis(
            healthScore: 70, scores: [:], nutrients: [], redFlags: [],
            summary: nil, bilanDetail: nil, interactions: [],
            pepites: pepites, priorityActions: [], positiveFindings: [],
            supplementsSchedule: nil, bloodTests: nil, meta: nil
        )
        vm.aiAnalysis = merged

        let first = vm.pepiteDuJour
        let second = vm.pepiteDuJour
        XCTAssertNotNil(first, "Should return a pepite")
        XCTAssertEqual(first?.tip, second?.tip, "Same day should return the same pepite (deterministic)")
    }

    // MARK: - Initial State

    /// Fresh ViewModel should not be in a loading state.
    func testInitialState_isNotLoading() {
        let vm = DashboardViewModel(
            auth: MockAuthService(),
            database: MockDatabaseService(),
            subscription: MockSubscriptionService(),
            analytics: MockAnalyticsService(),
            aiAnalysis: MockAIAnalysisService(),
            gamification: GamificationService.shared
        )
        // isLoadingAnalysis starts as false (loading is triggered by loadProfile)
        XCTAssertFalse(vm.isLoadingAnalysis, "Initial state should not be loading analysis")
    }

    // MARK: - Entrée libre (V12a) — invariants

    /// Invariant serveur : `questionnaire_data` absent/incomplet ne doit JAMAIS
    /// coûter un appel `generate-analysis` (ni v7 ni bilan v2) — gaspillage de
    /// quota + 400 garanti côté Edge Function.
    func testTriggerAnalysis_sansQuestionnaireComplete_nAppellePasLIA() async {
        let aiMock = MockAIAnalysisService()
        // `.empty` → completed == false (le cas « compte créé, pas de bilan »).
        let vm = makeVM(profile: .empty, aiAnalysis: aiMock)

        await vm.triggerAnalysis()

        XCTAssertEqual(aiMock.fullAnalysisCallCount, 0,
                       "generate-analysis (v7) ne doit pas partir sans questionnaire complété")
        XCTAssertEqual(aiMock.bilanV2CallCount, 0,
                       "generate-analysis (bilan v2) ne doit pas partir sans questionnaire complété")
        XCTAssertFalse(vm.isLoadingAnalysis, "Aucun chargement ne doit démarrer")
        XCTAssertFalse(vm.isLoadingAnalysisV2, "Aucun chargement v2 ne doit démarrer")
    }

    /// `bilanComplete` est l'alias d'observation de `hasCompletedQuestionnaire`.
    func testBilanComplete_suitHasCompletedQuestionnaire() {
        let vm = makeVM(profile: .empty)
        XCTAssertFalse(vm.bilanComplete)

        vm.hasCompletedQuestionnaire = true
        XCTAssertTrue(vm.bilanComplete, "bilanComplete doit basculer immédiatement, sans relance")
    }

    /// Décision fondateur : aucune porte premium tant que le bilan n'est pas
    /// fait — même pour un utilisateur gratuit.
    func testPremiumVisible_fauxSansBilan_memePourUnGratuit() {
        let vm = makeVM(profile: .empty) // gratuit (mock isPremium = false)
        XCTAssertFalse(vm.premiumVisible, "premiumVisible doit être faux si !bilanComplete")
    }

    /// Bilan fait + utilisateur gratuit → les portes premium s'affichent.
    func testPremiumVisible_vraiAvecBilanPourUnGratuit() {
        let vm = makeVM(profile: makeProfileThomas())
        XCTAssertTrue(vm.bilanComplete)
        XCTAssertTrue(vm.premiumVisible)
    }

    /// Un abonné ne voit jamais de porte premium, bilan fait ou non.
    func testPremiumVisible_fauxPourUnAbonne() {
        let sub = MockSubscriptionService()
        sub.isPremium = true
        let vm = makeVM(profile: makeProfileThomas(), subscription: sub)
        XCTAssertFalse(vm.premiumVisible)
    }

    /// `demarrerBilan()` ouvre la feuille questionnaire (observable par la racine).
    func testDemarrerBilan_ouvreLaFeuilleQuestionnaire() {
        let vm = makeVM(profile: .empty)
        XCTAssertFalse(vm.questionnaireOuvert)

        vm.demarrerBilan()
        XCTAssertTrue(vm.questionnaireOuvert)
    }

    // MARK: - Mode découverte (V12b)

    /// Sans bilan, l'onglet route vers le teaser (mode découverte) et AUCUN
    /// appel IA ne part — les emplacements de données affichent le catalogue
    /// de stats France, pas une analyse.
    func testBilanAffichage_sansBilan_decouverteSansAppelIA() async {
        let aiMock = MockAIAnalysisService()
        let vm = makeVM(profile: .empty, aiAnalysis: aiMock)

        XCTAssertEqual(vm.bilanAffichage, .decouverte, "Sans bilan → teaser affiché")

        await vm.triggerAnalysis()

        XCTAssertEqual(vm.bilanAffichage, .decouverte, "Le teaser reste affiché")
        XCTAssertEqual(aiMock.fullAnalysisCallCount, 0, "Aucun appel IA en mode découverte")
        XCTAssertEqual(aiMock.bilanV2CallCount, 0, "Aucun appel bilan v2 en mode découverte")
    }

    /// Questionnaire complété mais bilan v2 pas encore là → gate d'attente
    /// (chargement / erreur), jamais le teaser.
    func testBilanAffichage_questionnaireComplete_attente() {
        let vm = makeVM(profile: makeProfileThomas())
        XCTAssertEqual(vm.bilanAffichage, .attente)
    }

    /// Réactivité V12b : à la complétion du bilan puis à l'arrivée d'un bilan
    /// v2 valide, le dashboard passe aux vraies données sans relance.
    func testBilanAffichage_basculeVersLesVraiesDonneesQuandLeBilanArrive() {
        let vm = makeVM(profile: .empty)
        XCTAssertEqual(vm.bilanAffichage, .decouverte)

        vm.profile = makeProfileThomas()
        vm.hasCompletedQuestionnaire = true
        XCTAssertEqual(vm.bilanAffichage, .attente, "Bilan complété → attente de l'analyse")

        vm.analysisV2 = AIAnalysisV2(
            contract: "v2",
            score: 72,
            bilan: BilanV2(apports: [ApportV2(id: "iron", nom: "Fer", pctBesoin: 45)])
        )
        XCTAssertEqual(vm.bilanAffichage, .bilan, "Bilan v2 valide → vraies données, sans relance")
    }

    /// Un bilan v2 invalide (aucun apport) ne doit pas faire basculer l'écran.
    func testBilanAffichage_bilanV2Invalide_resteEnAttente() {
        let vm = makeVM(profile: makeProfileThomas())
        vm.analysisV2 = AIAnalysisV2(contract: "v2")
        XCTAssertEqual(vm.bilanAffichage, .attente)
    }
}

// MARK: - Minimal Mocks for DashboardViewModel Dependencies

/// Minimal mock for SubscriptionServiceProtocol used by DashboardViewModel.
@MainActor
private final class MockSubscriptionService: SubscriptionServiceProtocol {
    var isPremium: Bool = false
    func checkPremiumStatus() async {}
    func loadOfferings() async {}
    func restorePurchases() async throws {}
    func identify(userId: String) async {}
}

/// Minimal mock for AIAnalysisServiceProtocol used by DashboardViewModel.
/// Compte les appels : l'invariant « aucun appel generate-analysis sans
/// questionnaire complété » (entrée libre V12a) s'assert dessus.
private final class MockAIAnalysisService: AIAnalysisServiceProtocol {
    private(set) var fullAnalysisCallCount = 0
    private(set) var bilanV2CallCount = 0

    func fetchFullAnalysis(userId: String, profile: UserProfile) async throws -> MergedAnalysis? {
        fullAnalysisCallCount += 1
        return nil
    }
    func fetchBilanV2(userId: String, profileHash: String, scores: [String: Int], healthScore: Int, redFlags: [RedFlag], forceRefresh: Bool) async throws -> AIAnalysisV2 {
        bilanV2CallCount += 1
        return AIAnalysisV2(contract: "v2")
    }
}
