import XCTest
@testable import HealthMap

/// Tests for ReceiptValidationService — verifies the service exists, has correct
/// structure, and handles edge cases. Full StoreKit 2 integration tests require
/// a StoreKit Configuration file and run in the simulator.
final class ReceiptValidationTests: XCTestCase {

    /// Clé UserDefaults du debounce 24h (mirror de
    /// `ReceiptValidationService.lastVerificationKey`, privée dans le service).
    private static let lastVerificationKey = "healthmap_receipt_last_verification"

    override func setUp() {
        super.setUp()
        // Ensemence le debounce AVANT chaque test : sans ça, le premier appel
        // déclenche une vraie traversée de `Transaction.currentEntitlements`,
        // qui PEND sur un simulateur CI sans App Store (vu le 10 juin 2026 :
        // test tué à 2 min par l'execution-time-allowance → session marquée
        // TEST FAILED alors que les 48 tests repassaient au rerun).
        UserDefaults.standard.set(Date(), forKey: Self.lastVerificationKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.lastVerificationKey)
        super.tearDown()
    }

    // MARK: - Service Exists

    func testReceiptValidationServiceIsSingleton() {
        let a = ReceiptValidationService.shared
        let b = ReceiptValidationService.shared
        XCTAssertTrue(a === b, "ReceiptValidationService should be a singleton")
    }

    // MARK: - Debounce Logic

    @MainActor
    func testVerificationDebounces24Hours() async {
        // Le debounce est ensemencé (setUp) : les deux appels doivent prendre
        // le chemin no-op et revenir immédiatement — c'est exactement le
        // comportement que ce test vérifie (jamais de StoreKit réel en CI).
        await ReceiptValidationService.shared.verifyCurrentEntitlements(userId: "test-user")
        await ReceiptValidationService.shared.verifyCurrentEntitlements(userId: "test-user")
    }

    // MARK: - Debounce force (promesse V10 #2)
    // La décision de debounce est extraite dans `shouldVerify` (pure) pour être
    // testable : `force: true` la court-circuite entièrement (chemin post-achat).
    // Pas d'appel réel `verifyCurrentEntitlements(force: true)` ici : il
    // traverserait `Transaction.currentEntitlements`, qui PEND sur le
    // simulateur CI sans App Store (incident du 10 juin 2026, cf. setUp) —
    // `force` court-circuite précisément la garde qui protège ce test.

    func testShouldVerifyWhenNeverVerified() {
        XCTAssertTrue(ReceiptValidationService.shouldVerify(lastVerification: nil, now: Date()))
    }

    func testShouldNotVerifyAgainWithin24Hours() {
        let now = Date()
        XCTAssertFalse(ReceiptValidationService.shouldVerify(
            lastVerification: now.addingTimeInterval(-60 * 60),
            now: now
        ))
        XCTAssertFalse(ReceiptValidationService.shouldVerify(
            lastVerification: now.addingTimeInterval(-23 * 60 * 60),
            now: now
        ))
    }

    func testShouldVerifyAfter24Hours() {
        let now = Date()
        XCTAssertTrue(ReceiptValidationService.shouldVerify(
            lastVerification: now.addingTimeInterval(-25 * 60 * 60),
            now: now
        ))
    }

    // MARK: - AppTransaction
    // Pas de smoke test sur `verifyAppTransaction()` : `AppTransaction.shared`
    // exige un App Store daemon absent du simulateur CI — l'appel réel PEND
    // (tué à 2 min par l'execution-time-allowance, run 3 de la PR #29, 10 juin
    // 2026). Un hang n'est pas un crash : ce test est invérifiable en CI, et
    // le debounce ne protège pas ce chemin (contrairement à verifyIfNeeded).

    // MARK: - VerifyIfNeeded

    @MainActor
    func testVerifyIfNeededDoesNotCrash() async {
        await ReceiptValidationService.shared.verifyIfNeeded(userId: "test-user")
        // Smoke test: should complete without error.
    }
}
