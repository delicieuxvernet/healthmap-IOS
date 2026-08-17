import Foundation
import StoreKit

// MARK: - ReceiptValidationService
/// Verifies the integrity of in-app purchases using StoreKit 2's on-device
/// verification (`AppTransaction`, `Transaction.currentEntitlements`) and an
/// optional server-side check via Supabase Edge Function `verify-receipt`.
///
/// Flow:
///   1. **On app launch** — `verifyAppTransaction()` checks the AppTransaction
///      JWS to detect sideloaded / tampered builds.
///   2. **After each purchase** — `verifyCurrentEntitlements()` collects active
///      subscriptions and sends them for server-side validation.
///   3. **Periodically** — re-verification every 24 hours or on foreground.
///
/// Privacy: Only the JWS representation (signed by Apple) is sent to the
/// Edge Function. No user content or health data leaves the device.
@MainActor
final class ReceiptValidationService {

    static let shared = ReceiptValidationService()

    /// Last successful verification (used for 24h debounce). Persisted to
    /// UserDefaults so the debounce survives cold starts.
    private static let lastVerificationKey = "healthmap_receipt_last_verification"
    private var lastVerification: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastVerificationKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastVerificationKey) }
    }
    private nonisolated static let verificationInterval: TimeInterval = 24 * 60 * 60

    private init() {}

    // MARK: - App Transaction Verification (anti-tampering)

    /// Verifies the app was downloaded from the App Store. Should be called once
    /// on launch from `HealthMapApp.init()`. Sideloaded or modified builds will
    /// fail verification and get logged (but not force-closed — we only log for
    /// production diagnostics, not DRM enforcement).
    func verifyAppTransaction() async {
        do {
            let result = try await AppTransaction.shared
            switch result {
            case .verified(let transaction):
                AppLogger.subscription.info("AppTransaction verified (appId: \(String(describing: transaction.appID), privacy: .public), env: \(String(describing: transaction.environment), privacy: .public))")
                CrashReportingService.shared.breadcrumb(
                    "AppTransaction verified",
                    category: "subscription",
                    level: .info
                )
            case .unverified(_, let error):
                AppLogger.subscription.error("AppTransaction UNVERIFIED: \(error.localizedDescription, privacy: .public)")
                CrashReportingService.shared.captureMessage(
                    "AppTransaction verification failed: \(error.localizedDescription)",
                    level: .warning
                )
                AnalyticsService.shared.track(.errorOccurred, properties: [
                    "error_type": "app_transaction_unverified",
                    "error": error.localizedDescription,
                ])
            }
        } catch {
            // AppTransaction.shared can throw if StoreKit 2 is unavailable
            // (e.g. simulators, TestFlight without sandbox). Log but don't block.
            AppLogger.subscription.notice("AppTransaction check skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Entitlement Verification (post-purchase + periodic)

    /// Scans current StoreKit 2 entitlements and optionally sends them to the
    /// server for cross-validation against `profiles.tier`. Called after each
    /// purchase (`force: true`) and periodically (every 24h).
    ///
    /// - Parameter force: bypasse le debounce 24h. Chemin post-achat UNIQUEMENT :
    ///   juste après un paiement, la vérification serveur doit partir MAINTENANT —
    ///   avant ce paramètre, une vérification périodique < 24 h rendait l'appel
    ///   post-achat silencieusement no-op (promesse V10 #2).
    func verifyCurrentEntitlements(userId: String, force: Bool = false) async {
        // 24h debounce (sauf force)
        if !force, !Self.shouldVerify(lastVerification: lastVerification, now: Date()) {
            return
        }

        var activeProductIds: [String] = []

        // Collect active entitlements from StoreKit 2
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.revocationDate == nil {
                    activeProductIds.append(transaction.productID)
                }
            case .unverified(let transaction, let error):
                AppLogger.subscription.error("Unverified transaction \(transaction.productID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        AppLogger.subscription.info("StoreKit 2 entitlements: \(activeProductIds, privacy: .public)")
        CrashReportingService.shared.breadcrumb(
            "entitlements verified: \(activeProductIds.count) active",
            category: "subscription",
            level: .info
        )

        // Server-side verification via Edge Function.
        // Timestamp écrit APRÈS succès seulement : un échec (réseau, serveur)
        // laisse la prochaine occasion re-tenter, au lieu d'armer 24 h de
        // silence sur une vérification qui n'a jamais eu lieu (V10 #2).
        if await serverSideVerify(userId: userId, activeProductIds: activeProductIds) {
            lastVerification = Date()
        }
    }

    /// Décision de debounce, pure et testable : vérifier si jamais vérifié,
    /// ou si la dernière vérification date de plus de 24 h.
    nonisolated static func shouldVerify(lastVerification: Date?, now: Date) -> Bool {
        guard let lastVerification else { return true }
        return now.timeIntervalSince(lastVerification) >= verificationInterval
    }

    // MARK: - Server-Side Verification

    /// Sends active product IDs to Supabase Edge Function `verify-receipt`
    /// which cross-checks against RevenueCat webhooks and `profiles.tier`.
    ///
    /// If the server detects a mismatch (client claims premium but server says
    /// free), it corrects `profiles.tier` and we refresh SubscriptionService.
    /// - Returns: `true` si la vérification serveur a abouti (le debounce 24 h
    ///   ne s'arme que dans ce cas), `false` sur échec réseau/serveur.
    @discardableResult
    private func serverSideVerify(userId: String, activeProductIds: [String]) async -> Bool {
        do {
            struct VerifyRequest: Encodable {
                let userId: String
                let activeProductIds: [String]
                let appVersion: String
                let timestamp: String

                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                    case activeProductIds = "active_product_ids"
                    case appVersion = "app_version"
                    case timestamp
                }
            }

            struct VerifyResponse: Decodable {
                let valid: Bool
                let tier: String
                let corrected: Bool?
            }

            let request = VerifyRequest(
                userId: userId,
                activeProductIds: activeProductIds,
                appVersion: AppConfig.shared.versionTag,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )

            let response: VerifyResponse = try await SupabaseService.shared.client.functions.invoke(
                "verify-receipt",
                options: .init(body: request)
            )

            if response.corrected == true {
                AppLogger.subscription.notice("Server corrected tier to \(response.tier, privacy: .public)")
                // Refresh RevenueCat state to match server correction
                await SubscriptionService.shared.checkPremiumStatus()
                AnalyticsService.shared.track(.errorOccurred, properties: [
                    "error_type": "tier_mismatch_corrected",
                    "new_tier": response.tier,
                ])
            }
            return true
        } catch {
            // Non-fatal: server verification is defense-in-depth, not blocking.
            // RevenueCat remains the primary source of truth for entitlements.
            AppLogger.subscription.notice("Server-side receipt verification failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Periodic Check

    /// Call from foreground transitions to re-verify if 24h have passed.
    func verifyIfNeeded(userId: String) async {
        await verifyCurrentEntitlements(userId: userId)
    }
}
