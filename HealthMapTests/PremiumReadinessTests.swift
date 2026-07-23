import XCTest
@testable import HealthMap

final class PremiumReadinessTests: XCTestCase {

    func testPurchaseOutcomeRequiresActiveEntitlement() {
        XCTAssertEqual(
            PurchaseOutcome.resolve(userCancelled: false, entitlementIsActive: false),
            .entitlementPending
        )
        XCTAssertEqual(
            PurchaseOutcome.resolve(userCancelled: false, entitlementIsActive: true),
            .activated
        )
    }

    func testPurchaseCancellationNeverActivatesAccess() {
        XCTAssertEqual(
            PurchaseOutcome.resolve(userCancelled: true, entitlementIsActive: true),
            .cancelled
        )
    }

    func testQuotaPresentationUsesServerDailyLimit() {
        let quota = ScanQuotaPresentation(remaining: 24, dailyLimit: 30)

        XCTAssertEqual(quota.total, 30)
        XCTAssertEqual(quota.remaining, 24)
        XCTAssertEqual(quota.used, 6)
    }

    func testQuotaPresentationClampsInconsistentServerValues() {
        let quota = ScanQuotaPresentation(remaining: 42, dailyLimit: 30)

        XCTAssertEqual(quota.total, 30)
        XCTAssertEqual(quota.remaining, 30)
        XCTAssertEqual(quota.used, 0)
    }
}
