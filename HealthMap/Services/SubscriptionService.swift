import Foundation
import RevenueCat
import SwiftUI

// MARK: - Subscription Service (RevenueCat)
@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    @Published var isPremium = false
    @Published var offerings: Offerings?
    @Published var customerInfo: CustomerInfo?

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

    // MARK: - Load Offerings
    func loadOfferings() async {
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            AppLogger.subscription.report(error, context: "loadOfferings")
        }
    }

    // MARK: - Purchase
    func purchase(package: Package) async throws -> Bool {
        let result = try await Purchases.shared.purchase(package: package)
        customerInfo = result.customerInfo
        isPremium = result.customerInfo.entitlements["premium"]?.isActive == true

        // Post-purchase StoreKit 2 verification (non-blocking).
        if !result.userCancelled, let userId = try? await Purchases.shared.customerInfo().originalAppUserId {
            Task {
                await ReceiptValidationService.shared.verifyCurrentEntitlements(userId: userId)
            }
        }

        return !result.userCancelled
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
        Task { @MainActor in
            SubscriptionService.shared.customerInfo = customerInfo
            SubscriptionService.shared.isPremium = customerInfo.entitlements["premium"]?.isActive == true
        }
    }
}
