import XCTest
@testable import HealthMap

// MARK: - AIAnalysisService.hashProfile — regression tests
// groceries was excluded from the cache hash (non-deterministic dict
// serialization) even though the AI prompt treats it as a priority source and
// NutrientEngine consumes it for scoring — a changed grocery cart never
// invalidated the cached bilan. Fixed 2026-07-05 (architecture audit) via a
// sorted-key serialization of the groceries dictionary.
@MainActor
final class AIAnalysisServiceHashTests: XCTestCase {

    func testHashIsDeterministicAcrossRepeatedCalls() {
        var profile = UserProfile.empty
        profile.groceries = ["pomme": 3, "riz": 1, "poulet": 2]

        let hashes = (0..<20).map { _ in AIAnalysisService.hashProfile(profile) }
        XCTAssertEqual(Set(hashes).count, 1, "hashProfile must be deterministic regardless of dictionary iteration order")
    }

    func testGroceriesChangeInvalidatesHash() {
        var base = UserProfile.empty
        base.groceries = ["pomme": 3]

        var changed = base
        changed.groceries = ["pomme": 5]

        XCTAssertNotEqual(
            AIAnalysisService.hashProfile(base),
            AIAnalysisService.hashProfile(changed),
            "Changing the grocery cart quantities must invalidate the AI analysis cache"
        )
    }

    func testEmptyGroceriesStillHashesDeterministically() {
        let profile = UserProfile.empty
        let hashes = (0..<10).map { _ in AIAnalysisService.hashProfile(profile) }
        XCTAssertEqual(Set(hashes).count, 1, "An empty groceries dict must not introduce non-determinism")
    }
}
