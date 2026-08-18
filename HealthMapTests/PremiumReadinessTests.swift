import RevenueCat
import XCTest
@testable import HealthMap

final class PremiumReadinessTests: XCTestCase {

    // MARK: - Catalogue vendu : hebdo + annuel, et rien d'autre (18 août 2026)

    // `subscriptionProductIds` vit dans un service @MainActor : les deux tests
    // ci-dessous s'y isolent aussi (le reste du fichier lit du `nonisolated`).
    @MainActor
    func testOnlyWeeklyAndAnnualAreOffered() {
        XCTAssertEqual(
            SubscriptionService.subscriptionProductIds,
            ["healthmap_weekly", "healthmap_annual"]
        )
    }

    @MainActor
    func testMonthlyProductIsNeverLoaded() {
        // Le mensuel n'a jamais été approuvé par Apple : s'il revenait dans le
        // repli StoreKit, le paywall pourrait proposer un achat qui échoue.
        XCTAssertFalse(SubscriptionService.subscriptionProductIds.contains("healthmap_monthly"))
    }

    // MARK: - Achat différé (Ask to Buy / SCA, V10 #5)

    func testDeferredPurchaseErrorIsRecognized() {
        XCTAssertTrue(SubscriptionService.isPurchaseDeferred(ErrorCode.paymentPendingError))
    }

    func testOtherErrorsAreNotTreatedAsDeferred() {
        XCTAssertFalse(SubscriptionService.isPurchaseDeferred(ErrorCode.networkError))
        XCTAssertFalse(SubscriptionService.isPurchaseDeferred(ErrorCode.purchaseCancelledError))
        XCTAssertFalse(SubscriptionService.isPurchaseDeferred(URLError(.notConnectedToInternet)))
    }

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

    // MARK: - Filet hors-ligne : persistance + grâce (PremiumSnapshot, V10 #4)

    func testSnapshotGrantsAccessWhileSubscriptionRuns() {
        let active = PremiumSnapshot(isPremium: true, expirationDate: Date().addingTimeInterval(3600))
        XCTAssertTrue(active.grantsAccess())
    }

    func testSnapshotWithoutExpirationTrustsLastKnownState() {
        // Achat optimiste ou donnée absente : le dernier mot connu fait foi.
        XCTAssertTrue(PremiumSnapshot(isPremium: true, expirationDate: nil).grantsAccess())
        XCTAssertFalse(PremiumSnapshot(isPremium: false, expirationDate: nil).grantsAccess())
    }

    func testSnapshotGraceCoversThreeDaysAfterExpiration() {
        let now = Date()
        let day: TimeInterval = 24 * 60 * 60
        // Expiré depuis 2 jours : encore couvert (retard de facturation, avion).
        XCTAssertTrue(
            PremiumSnapshot(isPremium: true, expirationDate: now.addingTimeInterval(-2 * day))
                .grantsAccess(now: now)
        )
        // Expiré depuis 4 jours : la grâce est finie.
        XCTAssertFalse(
            PremiumSnapshot(isPremium: true, expirationDate: now.addingTimeInterval(-4 * day))
                .grantsAccess(now: now)
        )
        // Plus signalé actif mais expiration récente : la grâce couvre aussi.
        XCTAssertTrue(
            PremiumSnapshot(isPremium: false, expirationDate: now.addingTimeInterval(-1 * day))
                .grantsAccess(now: now)
        )
        // Plus actif avec une date FUTURE (révocation, remboursement) : refusé.
        XCTAssertFalse(
            PremiumSnapshot(isPremium: false, expirationDate: now.addingTimeInterval(day))
                .grantsAccess(now: now)
        )
    }

    func testSnapshotRoundTripsThroughUserDefaults() throws {
        let suiteName = "PremiumSnapshotTests"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        defer { suite.removePersistentDomain(forName: suiteName) }

        let expiration = Date(timeIntervalSince1970: 1_900_000_000)
        PremiumSnapshot(isPremium: true, expirationDate: expiration).save(to: suite)
        let loaded = PremiumSnapshot.load(from: suite)
        XCTAssertTrue(loaded.isPremium)
        XCTAssertEqual(loaded.expirationDate, expiration)

        // Un reset (sign out) efface l'expiration : le cache d'un utilisateur
        // ne doit jamais couvrir le suivant.
        PremiumSnapshot(isPremium: false, expirationDate: nil).save(to: suite)
        let cleared = PremiumSnapshot.load(from: suite)
        XCTAssertFalse(cleared.isPremium)
        XCTAssertNil(cleared.expirationDate)
    }
}
