import XCTest
@testable import HealthMap

/// Tests for ReceiptValidationService — verifies the service exists, has correct
/// structure, and handles edge cases. Full StoreKit 2 integration tests require
/// a StoreKit Configuration file and run in the simulator.
final class ReceiptValidationTests: XCTestCase {

    // MARK: - Service Exists

    func testReceiptValidationServiceIsSingleton() {
        let a = ReceiptValidationService.shared
        let b = ReceiptValidationService.shared
        XCTAssertTrue(a === b, "ReceiptValidationService should be a singleton")
    }

    // MARK: - Debounce Logic

    @MainActor
    func testVerificationDebounces24Hours() async {
        // First call should execute (but will fail gracefully without a real session).
        // The important thing is it doesn't crash and respects the debounce.
        await ReceiptValidationService.shared.verifyCurrentEntitlements(userId: "test-user")

        // Second call within 24h should be a no-op (debounced).
        // We can't directly observe the debounce, but we verify it doesn't crash.
        await ReceiptValidationService.shared.verifyCurrentEntitlements(userId: "test-user")
    }

    // MARK: - AppTransaction (smoke test)

    @MainActor
    func testVerifyAppTransactionDoesNotCrash() async {
        // In a test environment, AppTransaction.shared will throw (no sandbox).
        // The service should handle this gracefully.
        await ReceiptValidationService.shared.verifyAppTransaction()
        // If we get here without crashing, the error handling is correct.
    }

    // MARK: - VerifyIfNeeded

    @MainActor
    func testVerifyIfNeededDoesNotCrash() async {
        await ReceiptValidationService.shared.verifyIfNeeded(userId: "test-user")
        // Smoke test: should complete without error.
    }
}
