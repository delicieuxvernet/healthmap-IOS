import Foundation
@testable import HealthMap

/// In-memory mock for `GamificationService`. Records method calls for assertion
/// in tests without touching UserDefaults, the network, or any singleton state.
@MainActor
final class MockGamificationService: ObservableObject {

    // MARK: - Call counters (assertable from tests)
    private(set) var configureCallCount = 0
    private(set) var resetCallCount = 0
    private(set) var recordCheckinCallCount = 0
    private(set) var recordPathwayCalls: [String] = []
    private(set) var unlockQuestionnaireCompleteCalled = false
    private(set) var checkScoreBadgesCalls: [Int] = []
    private(set) var toggleZenModeCallCount = 0

    // MARK: - Programmable state
    var currentStreak: Int = 0
    var lastCheckinDate: Date?
    var earnedBadges: Set<BadgeType> = []
    var isZenMode: Bool = false
    var showConfetti: Bool = false
    var confettiType: ConfettiType = .badge
    var totalCheckins: Int = 0
    var bestStreak: Int = 0
    var freezesUsedThisMonth: Int = 0
    var monthStart: Date = Date()
    var triedPathways: Set<String> = []

    // MARK: - Methods

    func configure(userId: String) async {
        configureCallCount += 1
    }

    func reset() {
        resetCallCount += 1
        currentStreak = 0
        lastCheckinDate = nil
        earnedBadges = []
        totalCheckins = 0
        bestStreak = 0
        showConfetti = false
        triedPathways = []
    }

    func recordCheckin() {
        recordCheckinCallCount += 1
    }

    func recordPathway(_ pathway: String) {
        recordPathwayCalls.append(pathway)
    }

    func unlockQuestionnaireComplete() {
        unlockQuestionnaireCompleteCalled = true
    }

    func checkScoreBadges(score: Int) {
        checkScoreBadgesCalls.append(score)
    }

    func toggleZenMode() {
        toggleZenModeCallCount += 1
        isZenMode.toggle()
    }
}
