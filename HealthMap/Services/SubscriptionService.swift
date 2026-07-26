import Foundation
import RevenueCat
import SwiftUI

enum PurchaseOutcome: Equatable {
    case cancelled
    case activated
    case entitlementPending

    static func resolve(userCancelled: Bool, entitlementIsActive: Bool) -> PurchaseOutcome {
        if userCancelled { return .cancelled }
        return entitlementIsActive ? .activated : .entitlementPending
    }
}

enum SubscriptionPurchaseError: LocalizedError {
    case entitlementNotActivated

    var errorDescription: String? {
        switch self {
        case .entitlementNotActivated:
            return "L’achat a été confirmé, mais l’accès Premium n’est pas encore actif."
        }
    }
}

// MARK: - Subscription Service (RevenueCat)
@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    @Published var isPremium = false
    @Published var offerings: Offerings?
    @Published var customerInfo: CustomerInfo?

    /// Repli : produits lus DIRECTEMENT depuis StoreKit par identifiant, quand
    /// l'offering RevenueCat ne renvoie rien d'exploitable (offering « current »
    /// absente, mal configurée, ou ne contenant pas toutes les formules).
    /// Sans ce repli, une erreur de configuration côté tableau de bord rendait
    /// le paywall VIDE dans l'app — c'est ce qu'App Review a constaté (2.1(b) :
    /// « In-app purchase products ... could not be found in the submitted
    /// binary », l'hebdo « Kiwio Hebdo » étant nommément cité).
    @Published var directProducts: [StoreProduct] = []

    /// Identifiants App Store Connect des abonnements (source de vérité ASC).
    /// Utilisés UNIQUEMENT pour le repli ci-dessus ; les prix, durées et essais
    /// restent lus depuis StoreKit, jamais codés en dur.
    static let subscriptionProductIds = [
        "healthmap_weekly",
        "healthmap_monthly",
        "healthmap_annual",
    ]

    private init() {
        // Listen to customer info changes
        Purchases.shared.delegate = HMPurchasesDelegate.shared
    }

    // MARK: - Check Premium Status
    func checkPremiumStatus() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            customerInfo = info
            isPremium = info.entitlements["premium"]?.isActive == true
        } catch {
            AppLogger.subscription.report(error, context: "checkPremiumStatus")
        }
    }

    // MARK: - Load Offerings (+ repli StoreKit par identifiant)
    func loadOfferings() async {
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            AppLogger.subscription.report(error, context: "loadOfferings")
        }

        // L'offering « current » couvre-t-elle bien les 3 formules ? Sinon on
        // complète depuis StoreKit : le paywall doit TOUJOURS pouvoir afficher
        // les abonnements actifs sur App Store Connect, quelle que soit la
        // configuration du tableau de bord RevenueCat.
        let packaged = Set((offerings?.current?.availablePackages ?? []).map(\.storeProduct.productIdentifier))
        let missing = Self.subscriptionProductIds.filter { !packaged.contains($0) }
        guard !missing.isEmpty else {
            directProducts = []
            return
        }

        let fetched = await Purchases.shared.products(missing)
        if !fetched.isEmpty {
            directProducts = fetched
            AppLogger.subscription.info(
                "Repli StoreKit : \(fetched.count, privacy: .public) produit(s) chargé(s) hors offering"
            )
        }
    }

    // MARK: - Purchase
    func purchase(package: Package) async throws -> PurchaseOutcome {
        try await finish(result: await Purchases.shared.purchase(package: package))
    }

    /// Achat d'un produit chargé hors offering (repli `directProducts`).
    /// Passe par RevenueCat comme l'achat par package : l'entitlement « premium »
    /// est donc suivi à l'identique.
    func purchase(product: StoreProduct) async throws -> PurchaseOutcome {
        try await finish(result: await Purchases.shared.purchase(product: product))
    }

    /// Suite commune aux deux chemins d'achat (entitlement, reprise, vérification).
    private func finish(result: PurchaseResultData) async throws -> PurchaseOutcome {
        customerInfo = result.customerInfo
        isPremium = result.customerInfo.entitlements["premium"]?.isActive == true

        var outcome = PurchaseOutcome.resolve(
            userCancelled: result.userCancelled,
            entitlementIsActive: isPremium
        )

        // RevenueCat peut confirmer la transaction quelques instants avant de
        // rafraîchir l'entitlement. Une seconde lecture évite de laisser l’utilisateur
        // dans un faux état d'échec, sans jamais accorder l'accès côté client.
        if outcome == .entitlementPending {
            let refreshed = try await Purchases.shared.customerInfo()
            customerInfo = refreshed
            isPremium = refreshed.entitlements["premium"]?.isActive == true
            outcome = PurchaseOutcome.resolve(
                userCancelled: false,
                entitlementIsActive: isPremium
            )
        }

        guard outcome != .entitlementPending else {
            throw SubscriptionPurchaseError.entitlementNotActivated
        }

        // Post-purchase StoreKit 2 verification (non-blocking).
        if outcome == .activated {
            let userId = result.customerInfo.originalAppUserId
            Task {
                await ReceiptValidationService.shared.verifyCurrentEntitlements(userId: userId)
            }
        }

        return outcome
    }

    // MARK: - Restore Purchases
    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        customerInfo = info
        isPremium = info.entitlements["premium"]?.isActive == true
    }

    // MARK: - Grace Period
    /// Returns true if the user has an active premium entitlement OR if
    /// the entitlement expired less than 3 days ago (grace period).
    /// This prevents users from losing access immediately due to payment
    /// processing delays or temporary billing issues.
    var isPremiumWithGrace: Bool {
        if isPremium { return true }

        // Check for grace period: entitlement expired within last 3 days
        guard let entitlement = customerInfo?.entitlements["premium"],
              let expirationDate = entitlement.expirationDate else {
            return false
        }

        let gracePeriod: TimeInterval = 3 * 24 * 60 * 60 // 3 days
        return Date().timeIntervalSince(expirationDate) < gracePeriod
    }

    // MARK: - Reset (for sign out)
    /// Clears the in-memory premium status and logs out of RevenueCat so
    /// the next user starts with a clean subscription state. Without this,
    /// User B would briefly see User A's premium entitlements after sign-out.
    func reset() async {
        isPremium = false
        customerInfo = nil
        offerings = nil
        do {
            // RevenueCat logOut resets to an anonymous user.
            let info = try await Purchases.shared.logOut()
            customerInfo = info
            isPremium = info.entitlements["premium"]?.isActive == true
        } catch {
            AppLogger.subscription.report(error, context: "reset/logOut")
        }
    }

    // MARK: - Link RevenueCat to Supabase User
    func identify(userId: String) async {
        do {
            let (info, _) = try await Purchases.shared.logIn(userId)
            customerInfo = info
            isPremium = info.entitlements["premium"]?.isActive == true
        } catch {
            AppLogger.subscription.report(error, context: "identify")
        }
    }
}

// MARK: - Purchases Delegate
private class HMPurchasesDelegate: NSObject, PurchasesDelegate {
    static let shared = HMPurchasesDelegate()

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        // Capture the singleton inside the MainActor task body so Swift 6
        // strict-concurrency does not flag a cross-actor reference: the closure
        // body itself is `@MainActor`, so `SubscriptionService.shared` (a
        // `@MainActor` property) is reachable without any nonisolated hop.
        Task { @MainActor in
            let service = SubscriptionService.shared
            service.customerInfo = customerInfo
            service.isPremium = customerInfo.entitlements["premium"]?.isActive == true
        }
    }
}
