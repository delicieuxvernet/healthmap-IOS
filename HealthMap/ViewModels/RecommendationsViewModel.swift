import Foundation

@MainActor
final class RecommendationsViewModel: ObservableObject {

    // MARK: - Source Data

    @Published private(set) var analysis: MergedAnalysis

    // MARK: - Init

    init(analysis: MergedAnalysis) {
        self.analysis = analysis
    }

    // MARK: - Interactions (nutrient-medication / nutrient-nutrient)

    var interactions: [InteractionDetected] {
        analysis.interactions
    }

    var hasInteractions: Bool {
        !interactions.isEmpty
    }

    // MARK: - Enquête par symptôme / par objectif (sections dédiées)

    var symptomesAnalyse: [SymptomeAnalyse] {
        analysis.symptomesAnalyse.filter { ($0.symptome?.isEmpty == false) && !($0.causesProbables ?? []).isEmpty }
    }

    var objectifsAnalyse: [ObjectifAnalyse] {
        analysis.objectifsAnalyse.filter { $0.objectif?.isEmpty == false && (!($0.freins ?? []).isEmpty || !($0.leviers ?? []).isEmpty) }
    }

    // MARK: - Top Deficiencies (nutrients with score < 60, sorted worst first)

    var topDeficiencies: [EnrichedNutrient] {
        analysis.topDeficiencies
    }

    var hasDeficiencies: Bool {
        !topDeficiencies.isEmpty
    }

    /// All nutrients below adequate threshold, not just top 3
    var allDeficientNutrients: [EnrichedNutrient] {
        analysis.nutrients
            .filter { $0.score < 60 }
            .sorted { $0.score < $1.score }
    }

    // MARK: - Pepites Sante (practical tips / health nuggets)

    var pepites: [PracticalTip] {
        analysis.pepites
    }

    var hasPepites: Bool {
        !pepites.isEmpty
    }

    // MARK: - Priority Actions (ranked 1-N by AI)

    var priorityActions: [PriorityAction] {
        analysis.priorityActions.sorted { ($0.rank ?? 0) < ($1.rank ?? 0) }
    }

    var hasPriorityActions: Bool {
        !priorityActions.isEmpty
    }

    /// Top 3 priority actions for quick display
    var topActions: [PriorityAction] {
        Array(priorityActions.prefix(3))
    }

    // MARK: - Supplements Schedule (morning / afternoon / evening)

    var supplementsSchedule: SupplementsSchedule? {
        analysis.supplementsSchedule
    }

    var hasSuppSchedule: Bool {
        guard let schedule = supplementsSchedule else { return false }
        let hasAny = !(schedule.morning ?? []).isEmpty
            || !(schedule.afternoon ?? []).isEmpty
            || !(schedule.evening ?? []).isEmpty
        return hasAny
    }

    // Les entrées du planning sont des objets {name, dose, ...} ou des
    // chaînes (legacy) — displayText normalise les deux pour l'affichage.
    var morningSupplements: [String] {
        (supplementsSchedule?.morning ?? []).map(\.displayText)
    }

    var afternoonSupplements: [String] {
        (supplementsSchedule?.afternoon ?? []).map(\.displayText)
    }

    var eveningSupplements: [String] {
        (supplementsSchedule?.evening ?? []).map(\.displayText)
    }

    var supplementWarnings: [String] {
        supplementsSchedule?.warnings ?? []
    }

    // MARK: - Blood Tests

    var bloodTests: BloodTests? {
        analysis.bloodTests
    }

    var shouldDoBloodTest: Bool {
        bloodTests?.recommended == true
    }

    var recommendedTests: [String] {
        bloodTests?.tests ?? []
    }

    var bloodTestReason: String? {
        bloodTests?.why
    }

    // MARK: - Positive Findings

    var positiveFindings: [PositiveFinding] {
        analysis.positiveFindings
    }

    var hasPositiveFindings: Bool {
        !positiveFindings.isEmpty
    }

    // MARK: - Red Flags

    var redFlags: [RedFlag] {
        analysis.redFlags
    }

    var hasRedFlags: Bool {
        !redFlags.isEmpty
    }

    var immediateFlags: [RedFlag] {
        redFlags.filter { $0.urgency == .immediate }
    }

    // MARK: - Summary

    var summaryHeadline: String? {
        analysis.summary?.headline
    }

    var profilType: String? {
        analysis.summary?.profilType
    }

    var metaphore: String? {
        analysis.summary?.metaphore
    }

    var healthScore: Int {
        analysis.healthScore
    }

    var overallScore: Int {
        analysis.overallScore
    }

    // MARK: - Physical Stats (computed from profile)

    /// Physical metrics computed from the associated dashboard profile.
    /// Accepts the profile explicitly so the ViewModel stays independent
    /// of DashboardViewModel.
    func physicalStats(for profile: UserProfile) -> PhysicalMetrics {
        PhysicalMetrics(profile: profile)
    }

    // MARK: - Update Analysis

    func updateAnalysis(_ newAnalysis: MergedAnalysis) {
        analysis = newAnalysis
    }
}
