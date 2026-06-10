import Foundation
import Supabase

// MARK: - Protocol conformance
extension DatabaseService: DatabaseServiceProtocol {}

// MARK: - Push tokens
extension DatabaseService {
    /// Stores the APNs device token in `profiles.push_token` for the currently signed-in user.
    /// Called from `PushNotificationService` after a successful APNs registration.
    func updatePushToken(_ token: String) async throws {
        guard let userId = await AuthService.shared.currentUser?.id.uuidString else {
            throw HealthMapError.auth(.sessionExpired)
        }
        struct Row: Encodable {
            let push_token: String
            let push_token_updated_at: String
        }
        let row = Row(
            push_token: token,
            push_token_updated_at: ISO8601DateFormatter().string(from: Date())
        )
        try await NetworkService.shared.withRetry {
            try await SupabaseService.shared.client
                .from("profiles")
                .update(row)
                .eq("id", value: userId)
                .execute()
        }
        AppLogger.database.info("Push token updated for user \(userId, privacy: .public)")
    }
}

// MARK: - Account deletion (RGPD + Apple requirement)
extension DatabaseService {
    /// Full user data erasure, required by:
    ///   1. Apple App Store guideline 5.1.1 (v) — in-app account deletion
    ///   2. RGPD Article 17 — right to erasure
    ///
    /// Deletes: profile row, analytics events, score history. Auth user is deleted separately
    /// via the `delete-user` Supabase Edge Function (requires service_role privileges).
    ///
    /// Every network call is wrapped in `NetworkService.withRetry` because a
    /// user who just tapped "Supprimer definitivement" cannot be asked to
    /// retry on a flaky 3G connection — the operation has to either succeed
    /// or fail loud enough that we route them to support. Transient 5xx and
    /// connection drops are invisible thanks to the exponential backoff.
    func deleteAllUserData(userId: String) async throws {
        AppLogger.database.notice("Deleting all data for user \(userId, privacy: .public)")

        // L'Edge Function `delete-user` (service_role) fait TOUTE la
        // suppression côté serveur : audit_log, annulation Stripe, DELETE
        // profiles (les tables user-scoped suivent par FK ON DELETE CASCADE,
        // vérifié en DB le 10 juin 2026 ; analytics_events est anonymisée
        // par SET NULL, audit_log conservé volontairement), puis
        // admin.deleteUser sur auth.users.
        //
        // BUG corrigé 10 juin 2026 : l'ancien code envoyait {"user_id": ...}
        // alors que la fonction exige {"confirm": "DELETE_MY_ACCOUNT"} → 400
        // systématique, ET faisait des DELETE côté client qui étaient des
        // no-ops silencieux (aucune policy RLS DELETE sur profiles /
        // analytics_events → 200 avec 0 ligne). Résultat : l'app affichait
        // « compte supprimé » sans RIEN supprimer (violation RGPD Art. 17).
        // Désormais : un seul chemin de suppression (l'edge function), et
        // son échec REMONTE à l'UI — jamais de faux succès.
        try await NetworkService.shared.withRetry {
            let _: Data = try await SupabaseService.shared.client.functions.invoke(
                "delete-user",
                options: .init(body: ["confirm": "DELETE_MY_ACCOUNT"])
            )
        }

        AppLogger.database.info("User data deletion complete for \(userId, privacy: .public)")
    }
}
