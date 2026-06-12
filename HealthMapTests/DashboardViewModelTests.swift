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
    private func makeVM(profile: UserProfile) -> DashboardViewModel {
        let vm = DashboardViewModel(
            auth: MockAuthService(),
            database: MockDatabaseService(),
            subscription: MockSubscriptionService(),
            analytics: MockAnalyticsService(),
            aiAnalysis: MockAIAnalysisService(),
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
private final class MockAIAnalysisService: AIAnalysisServiceProtocol {
    func fetchFullAnalysis(userId: String, profile: UserProfile) async throws -> MergedAnalysis? { nil }
    func regenerate(userId: String, profile: UserProfile) async throws -> MergedAnalysis? { nil }
}
