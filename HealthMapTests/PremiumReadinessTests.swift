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

    // MARK: - Matrice compteur × porte (ScanQuotaUI, V10 #1)

    func testMeterHiddenBeforeBilanOrWithoutServerQuota() {
        // Avant le bilan : rien, quel que soit le quota connu (V12a).
        XCTAssertFalse(ScanQuotaUI.meterVisible(bilanComplete: false, remaining: 3))
        XCTAssertFalse(ScanQuotaUI.meterVisible(bilanComplete: false, remaining: nil))
        // Bilan fait mais serveur muet : pas de compteur inventé.
        XCTAssertFalse(ScanQuotaUI.meterVisible(bilanComplete: true, remaining: nil))
    }

    func testMeterVisibleAfterBilanForFreeAndPremiumAlike() {
        // Le compteur est une info neutre : gratuit (x/3) comme premium (x/30),
        // y compris à 0 restant (le compteur plein remplace le mur pour un abonné).
        XCTAssertTrue(ScanQuotaUI.meterVisible(bilanComplete: true, remaining: 3))
        XCTAssertTrue(ScanQuotaUI.meterVisible(bilanComplete: true, remaining: 30))
        XCTAssertTrue(ScanQuotaUI.meterVisible(bilanComplete: true, remaining: 0))
    }

    func testGateOnlyForFreeUsersAfterBilan() {
        XCTAssertTrue(ScanQuotaUI.gateEnabled(bilanComplete: true, isPremium: false))
        // Un abonné ne voit JAMAIS de porte paywall.
        XCTAssertFalse(ScanQuotaUI.gateEnabled(bilanComplete: true, isPremium: true))
        // Avant le bilan, aucune porte pour personne (V12a).
        XCTAssertFalse(ScanQuotaUI.gateEnabled(bilanComplete: false, isPremium: false))
        XCTAssertFalse(ScanQuotaUI.gateEnabled(bilanComplete: false, isPremium: true))
    }
}
