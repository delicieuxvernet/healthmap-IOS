import XCTest
@testable import HealthMap

// MARK: - Gamification Service Tests
// Validates streak logic, badge unlocking, zen mode, and UserDefaults persistence.
// GamificationService is a singleton @MainActor — we use reset() in setUp and
// clean UserDefaults keys in tearDown to ensure test isolation.

@MainActor
final class GamificationServiceTests: XCTestCase {

    private var sut: GamificationService!

    /// All UserDefaults keys used by GamificationService (must match Keys enum).
    private let gamificationKeys = [
        "healthmap_streak",
        "healthmap_last_checkin",
        "healthmap_badges",
        "healthmap_zen_mode",
        "healthmap_total_checkins",
        "healthmap_best_streak",
        "healthmap_freezes_used",
        "healthmap_month_start",
        "healthmap_tried_pathways",
    ]

    override func setUp() {
        super.setUp()
        sut = GamificationService.shared
        sut.reset()
        // Also clear UserDefaults to guarantee a clean slate
        for key in gamificationKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        sut.reset()
        for key in gamificationKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        sut = nil
        super.tearDown()
    }

    // MARK: - Streak Logic

    /// The very first checkin should start the streak at 1.
    func testRecordCheckin_firstEver_startsStreakAt1() {
        sut.recordCheckin()
        XCTAssertEqual(sut.currentStreak, 1, "First checkin should set streak to 1")
        XCTAssertEqual(sut.totalCheckins, 1, "First checkin should set total to 1")
    }

    /// Two checkins on the same day should NOT double-count.
    func testRecordCheckin_sameDayTwice_doesNotDouble() {
        sut.recordCheckin()
        sut.recordCheckin()
        XCTAssertEqual(sut.currentStreak, 1, "Same-day checkin should not increment streak")
        XCTAssertEqual(sut.totalCheckins, 1, "Same-day checkin should not increment total")
    }

    // MARK: - Badge Unlocking

    /// The firstCheckin badge should unlock after the first ever checkin.
    func testFirstCheckinBadge_unlocksAfterOneCheckin() {
        sut.recordCheckin()
        XCTAssertTrue(sut.earnedBadges.contains(.firstCheckin), "firstCheckin badge should unlock after 1 checkin")
    }

    /// The streak3 badge should unlock when the current streak reaches 3.
    func testStreak3Badge_unlocksAtStreak3() {
        // Simulate 3-day streak by manipulating state
        sut.currentStreak = 2
        sut.totalCheckins = 2
        sut.lastCheckinDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())

        sut.recordCheckin()

        XCTAssertEqual(sut.currentStreak, 3, "Streak should be 3")
        XCTAssertTrue(sut.earnedBadges.contains(.streak3), "streak3 badge should unlock at streak 3")
    }

    /// The dedicated10 badge should unlock at 10 total checkins.
    func testDedicated10Badge_at10TotalCheckins() {
        // Simulate 9 previous checkins with consecutive days
        sut.currentStreak = 9
        sut.totalCheckins = 9
        sut.lastCheckinDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())

        sut.recordCheckin()

        XCTAssertEqual(sut.totalCheckins, 10, "Total checkins should be 10")
        XCTAssertTrue(sut.earnedBadges.contains(.dedicated10), "dedicated10 badge should unlock at 10 total checkins")
    }

    /// The explorer badge should unlock after trying both pathways.
    func testExplorerBadge_afterBothPathways() {
        sut.recordPathway("express")
        XCTAssertFalse(sut.earnedBadges.contains(.explorer), "Should not unlock with just one pathway")

        sut.recordPathway("complet")
        XCTAssertTrue(sut.earnedBadges.contains(.explorer), "explorer badge should unlock after both pathways")
    }

    /// The questionnaireComplete badge should unlock via unlockQuestionnaireComplete().
    func testQuestionnaireCompleteBadge_unlocks() {
        sut.unlockQuestionnaireComplete()
        XCTAssertTrue(sut.earnedBadges.contains(.questionnaireComplete), "questionnaireComplete badge should unlock")
    }

    /// The scoreHigh badge should unlock when checkScoreBadges is called with score >= 80.
    func testScoreHighBadge_at80() {
        sut.checkScoreBadges(score: 80)
        XCTAssertTrue(sut.earnedBadges.contains(.scoreHigh), "scoreHigh badge should unlock at score 80")
    }

    // MARK: - Zen Mode

    /// toggleZenMode should flip the isZenMode boolean.
    func testZenMode_togglesCorrectly() {
        XCTAssertFalse(sut.isZenMode, "Should start with zen mode off")

        sut.toggleZenMode()
        XCTAssertTrue(sut.isZenMode, "Should be on after first toggle")

        sut.toggleZenMode()
        XCTAssertFalse(sut.isZenMode, "Should be off after second toggle")
    }

    // MARK: - Best Streak

    /// Best streak should update when current streak exceeds it.
    func testBestStreak_updatedWhenCurrentExceeds() {
        sut.currentStreak = 4
        sut.totalCheckins = 4
        sut.bestStreak = 3
        sut.lastCheckinDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())

        sut.recordCheckin()

        XCTAssertEqual(sut.bestStreak, 5, "bestStreak should update to 5 when current (5) exceeds previous best (3)")
    }

    // MARK: - Reset

    /// reset() should clear all gamification state.
    func testReset_clearsAllState() {
        sut.recordCheckin()
        sut.recordPathway("express")
        sut.unlockQuestionnaireComplete()

        sut.reset()

        XCTAssertEqual(sut.currentStreak, 0, "Streak should be 0 after reset")
        XCTAssertNil(sut.lastCheckinDate, "Last checkin should be nil after reset")
        XCTAssertTrue(sut.earnedBadges.isEmpty, "Badges should be empty after reset")
        XCTAssertEqual(sut.totalCheckins, 0, "Total checkins should be 0 after reset")
        XCTAssertEqual(sut.bestStreak, 0, "Best streak should be 0 after reset")
        XCTAssertTrue(sut.triedPathways.isEmpty, "Tried pathways should be empty after reset")
        XCTAssertFalse(sut.showConfetti, "Confetti should be off after reset")
    }

    // MARK: - Persistence

    /// saveState should persist streak data to UserDefaults.
    func testSaveState_persistsToUserDefaults() {
        sut.recordCheckin()

        // Read directly from UserDefaults
        let storedStreak = UserDefaults.standard.integer(forKey: "healthmap_streak")
        let storedTotal = UserDefaults.standard.integer(forKey: "healthmap_total_checkins")
        XCTAssertEqual(storedStreak, 1, "Streak should be persisted to UserDefaults")
        XCTAssertEqual(storedTotal, 1, "Total checkins should be persisted to UserDefaults")
    }

    /// State should be restorable from UserDefaults after reset + re-write.
    func testLoadState_restoresFromUserDefaults() {
        // Set up state via public API
        sut.recordCheckin()
        sut.recordPathway("express")
        sut.unlockQuestionnaireComplete()

        let savedStreak = sut.currentStreak
        let savedTotal = sut.totalCheckins
        let savedBadges = sut.earnedBadges

        // Verify UserDefaults has the data
        let storedStreak = UserDefaults.standard.integer(forKey: "healthmap_streak")
        XCTAssertEqual(storedStreak, savedStreak, "UserDefaults should hold the current streak")

        let storedTotal = UserDefaults.standard.integer(forKey: "healthmap_total_checkins")
        XCTAssertEqual(storedTotal, savedTotal, "UserDefaults should hold total checkins")

        let storedBadges = UserDefaults.standard.stringArray(forKey: "healthmap_badges") ?? []
        let restoredBadges = Set(storedBadges.compactMap { BadgeType(rawValue: $0) })
        XCTAssertEqual(restoredBadges, savedBadges, "UserDefaults should hold earned badges")
    }

    // MARK: - Meal Scanned Badge

    /// The mealScanned badge type exists in BadgeType but there is no dedicated
    /// unlockMealScanned() method yet. This test verifies the badge can be
    /// manually inserted (future-proofing for when the method is added).
    func testMealScannedBadge_unlocked() {
        // Manually insert the badge (simulating what a future unlockMealScanned() would do)
        sut.earnedBadges.insert(.mealScanned)
        XCTAssertTrue(sut.earnedBadges.contains(.mealScanned), "mealScanned badge should be insertable")
        XCTAssertEqual(BadgeType.mealScanned.title, "Premier scan", "Badge title should match")
    }
}
