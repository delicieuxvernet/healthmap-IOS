import Foundation
import RevenueCat
import SwiftUI

enum PurchaseOutcome: Equatable {
    case cancelled
    case activated
    /// Achat ABOUTI (transaction StoreKit confirmée) mais confirmation
    /// RevenueCat pas encore lisible (réseau, propagation). L'accès est
    /// considéré actif d'après le résultat d'achat — l'UI dit au pire
    /// « Achat confirmé — la synchronisation se termine… », JAMAIS un
    /// échec (promesse V10 #3).
    case activatedSyncPending
    /// Achat DIFFÉRÉ (Ask to Buy — approbation parentale — ou validation
    /// bancaire SCA) : la transaction attend une approbation externe.
    /// Ni un échec, ni un cas « Restaurer » : l'accès s'activera tout seul
    /// à l'approbation, via le push delegate RevenueCat (promesse V10 #5).
    case deferred
    /// État intermédiaire interne (avant relecture) — `finish` ne le
    /// retourne jamais tel quel.
    case entitlementPending

    static func resolve(userCancelled: Bool, entitlementIsActive: Bool) -> PurchaseOutcome {
        if userCancelled { return .cancelled }
        return entitlementIsActive ? .activated : .entitlementPending
    }
}

// MARK: - Filet hors-ligne (promesse V10 #4)
/// Dernier état premium CONNU, persisté à chaque mise à jour fraîche : au
/// cold start sans réseau, un abonné reste traité en abonné (grâce de 3 jours
/// après expiration — retards de facturation, avion, réseau coupé).
struct PremiumSnapshot: Equatable {
    static let premiumKey = "healthmap_premium_cached"
    static let expirationKey = "healthmap_premium_expiration"
    /// 3 jours — même valeur que la grâce historique d'`isPremiumWithGrace`.
    static let gracePeriod: TimeInterval = 3 * 24 * 60 * 60

    let isPremium: Bool
    let expirationDate: Date?

    /// L'accès est-il couvert par ce dernier état connu ?
    func grantsAccess(now: Date = Date()) -> Bool {
        if isPremium {
            // Sans date d'expiration connue, le dernier mot du serveur fait foi.
            guard let expirationDate else { return true }
            return now.timeIntervalSince(expirationDate) < Self.gracePeriod
        }
        // Plus signalé actif : la grâce ne couvre qu'une expiration RÉCENTE
        // (< 3 j) — jamais une date future incohérente (révocation, remboursement).
        guard let expirationDate else { return false }
        let sinceExpiration = now.timeIntervalSince(expirationDate)
        return sinceExpiration >= 0 && sinceExpiration < Self.gracePeriod
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(isPremium, forKey: Self.premiumKey)
        if let expirationDate {
            defaults.set(expirationDate, forKey: Self.expirationKey)
        } else {
            defaults.removeObject(forKey: Self.expirationKey)
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> PremiumSnapshot {
        PremiumSnapshot(
            isPremium: defaults.bool(forKey: premiumKey),
            expirationDate: defaults.object(forKey: expirationKey) as? Date
        )
    }
}

// MARK: - Subscription Service (RevenueCat)
@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    /// Identifiant de l'entitlement RevenueCat.
    nonisolated static let entitlementId = "premium"

    @Published var isPremium = false
    @Published var offerings: Offerings?
    @Published var customerInfo: CustomerInfo?

    /// Anti-course (V10 #4) : incrémentée à chaque écriture FRAÎCHE de l'état
    /// premium (achat, restore, push delegate, reset). Une lecture réseau
    /// lancée avant une écriture plus récente est jetée à son retour — un
    /// `true` frais n'est jamais écrasé par une réponse ancienne.
    private var premiumGeneration = 0

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
        // Filet hors-ligne (V10 #4) : au cold start, l'état premium repart du
        // dernier état CONNU via `isPremiumWithGrace` (cache persisté, grâce
        // de 3 j après expiration) au lieu de false — un abonné en avion reste
        // un abonné jusqu'à preuve réseau du contraire. `checkPremiumStatus`
        // (lancement, retour au premier plan, reconnexion) rafraîchit ensuite.
        isPremium = isPremiumWithGrace

        // Listen to customer info changes
        Purchases.shared.delegate = HMPurchasesDelegate.shared
    }

    // MARK: - Fresh state writes

    /// Écriture FRAÎCHE de l'état premium (achat, restore, push delegate,
    /// reset, lecture réseau aboutie). Incrémente la génération anti-course
    /// et persiste le filet hors-ligne.
    /// - Parameter isPremiumOverride: chemin optimiste post-achat (V10 #3) —
    ///   l'achat fait foi même sans confirmation lisible. Dans ce cas aucune
    ///   date d'expiration fiable n'existe : on n'en persiste pas plutôt
    ///   qu'une périmée.
    fileprivate func applyFresh(customerInfo info: CustomerInfo?, isPremiumOverride: Bool? = nil) {
        premiumGeneration += 1
        customerInfo = info
        let entitlement = info?.entitlements[Self.entitlementId]
        isPremium = isPremiumOverride ?? (entitlement?.isActive == true)
        PremiumSnapshot(
            isPremium: isPremium,
            expirationDate: isPremiumOverride == nil ? entitlement?.expirationDate : nil
        ).save()
    }

    // MARK: - Check Premium Status
    func checkPremiumStatus() async {
        let generation = premiumGeneration
        do {
            let info = try await Purchases.shared.customerInfo()
            // Anti-course (V10 #4) : une écriture plus fraîche (achat, push
            // delegate…) est passée pendant la lecture réseau — cette réponse
            // est périmée, on la jette.
            guard generation == premiumGeneration else { return }
            applyFresh(customerInfo: info)
        } catch {
            // Hors-ligne : on GARDE l'état courant (initialisé du cache au
            // cold start) — un échec de lecture ne dégrade jamais un abonné.
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
        do {
            return await finish(result: try await Purchases.shared.purchase(package: package))
        } catch let error where Self.isPurchaseDeferred(error) {
            return .deferred
        }
    }

    /// Achat d'un produit chargé hors offering (repli `directProducts`).
    /// Passe par RevenueCat comme l'achat par package : l'entitlement « premium »
    /// est donc suivi à l'identique.
    func purchase(product: StoreProduct) async throws -> PurchaseOutcome {
        do {
            return await finish(result: try await Purchases.shared.purchase(product: product))
        } catch let error where Self.isPurchaseDeferred(error) {
            return .deferred
        }
    }

    /// Ask to Buy / SCA : StoreKit met la transaction en attente d'approbation
    /// et RevenueCat le signale par `paymentPendingError`. Ce n'est PAS un
    /// échec d'achat — sans cette détection, l'utilisateur lisait un message
    /// d'erreur parlant de « Restaurer », faux sur toute la ligne (V10 #5).
    nonisolated static func isPurchaseDeferred(_ error: Error) -> Bool {
        (error as? ErrorCode) == .paymentPendingError
    }

    /// Suite commune aux deux chemins d'achat (entitlement, reprise, vérification).
    /// Ne THROW jamais : dès qu'un `PurchaseResultData` existe, l'achat a
    /// abouti — une relecture RevenueCat qui échoue (réseau) n'est pas un
    /// achat raté et ne doit JAMAIS s'afficher comme tel (promesse V10 #3).
    private func finish(result: PurchaseResultData) async -> PurchaseOutcome {
        applyFresh(customerInfo: result.customerInfo)

        var outcome = PurchaseOutcome.resolve(
            userCancelled: result.userCancelled,
            entitlementIsActive: isPremium
        )

        // RevenueCat peut confirmer la transaction quelques instants avant de
        // rafraîchir l'entitlement : 2 relectures espacées, cache contourné
        // (`.fetchCurrent`, la politique la plus fraîche du SDK), en `try?` —
        // un échec de lecture ne remonte jamais comme échec d'achat.
        if outcome == .entitlementPending {
            for attempt in 1...2 {
                if attempt > 1 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
                guard let refreshed = try? await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent) else {
                    continue
                }
                applyFresh(customerInfo: refreshed)
                if isPremium {
                    outcome = .activated
                    break
                }
            }
        }

        // Toujours pas de confirmation lisible ? L'achat, lui, a réussi : le
        // résultat d'achat fait foi, l'accès est accordé. Le webhook RevenueCat
        // + verify-receipt corrigeront côté serveur si besoin.
        if outcome == .entitlementPending {
            applyFresh(customerInfo: customerInfo, isPremiumOverride: true)
            outcome = .activatedSyncPending
        }

        // Post-purchase StoreKit 2 verification (non-blocking). `force: true` :
        // c'est LE moment où le serveur doit recouper l'achat — sans lui, une
        // vérification périodique < 24 h rendait cet appel no-op (V10 #2).
        if outcome == .activated || outcome == .activatedSyncPending {
            let userId = result.customerInfo.originalAppUserId
            Task {
                await ReceiptValidationService.shared.verifyCurrentEntitlements(userId: userId, force: true)
            }
        }

        return outcome
    }

    // MARK: - Restore Purchases
    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        applyFresh(customerInfo: info)
    }

    // MARK: - Grace Period
    /// Accès premium avec filet : entitlement actif, OU dernier état connu
    /// (RevenueCat en mémoire, sinon cache disque `PremiumSnapshot`) encore
    /// couvert par la grâce de 3 jours. Consultée au cold start pour
    /// initialiser `isPremium` (V10 #4) — un retard de facturation ou une
    /// absence de réseau ne dégrade pas un abonné.
    var isPremiumWithGrace: Bool {
        if isPremium { return true }
        if let entitlement = customerInfo?.entitlements[Self.entitlementId] {
            return PremiumSnapshot(
                isPremium: entitlement.isActive,
                expirationDate: entitlement.expirationDate
            ).grantsAccess()
        }
        return PremiumSnapshot.load().grantsAccess()
    }

    // MARK: - Reset (for sign out)
    /// Clears the in-memory premium status and logs out of RevenueCat so
    /// the next user starts with a clean subscription state. Without this,
    /// User B would briefly see User A's premium entitlements after sign-out.
    /// Le filet hors-ligne est purgé aussi (`applyFresh(nil)`) — le cache
    /// d'un utilisateur ne doit jamais couvrir le suivant.
    func reset() async {
        applyFresh(customerInfo: nil)
        offerings = nil
        do {
            // RevenueCat logOut resets to an anonymous user.
            let info = try await Purchases.shared.logOut()
            applyFresh(customerInfo: info)
        } catch {
            AppLogger.subscription.report(error, context: "reset/logOut")
        }
    }

    // MARK: - Link RevenueCat to Supabase User
    func identify(userId: String) async {
        do {
            let (info, _) = try await Purchases.shared.logIn(userId)
            applyFresh(customerInfo: info)
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
        // Push RevenueCat = source fraîche : passe par `applyFresh` (génération
        // anti-course + persistance du filet hors-ligne, V10 #4).
        Task { @MainActor in
            SubscriptionService.shared.applyFresh(customerInfo: customerInfo)
        }
    }
}
