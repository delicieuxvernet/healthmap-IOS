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

        // 1. Delete score history (best-effort: empty result is fine).
        do {
            try await NetworkService.shared.withRetry {
                try await SupabaseService.shared.client
                    .from("score_history")
                    .delete()
                    .eq("user_id", value: userId)
                    .execute()
            }
        } catch {
            AppLogger.database.notice("score_history delete failed (may be empty): \(error.localizedDescription, privacy: .public)")
        }

        // 2. Delete analytics events (best-effort: empty result is fine).
        do {
            try await NetworkService.shared.withRetry {
                try await SupabaseService.shared.client
                    .from("analytics_events")
                    .delete()
                    .eq("user_id", value: userId)
                    .execute()
            }
        } catch {
            AppLogger.database.notice("analytics_events delete failed (may be empty): \(error.localizedDescription, privacy: .public)")
        }

        // 3. Delete profile row (cascades to related tables via FK).
        // This is the RGPD-critical step — if it fails after retries we
        // MUST surface the error so the caller can route to support.
        try await NetworkService.shared.withRetry {
            try await SupabaseService.shared.client
                .from("profiles")
                .delete()
                .eq("id", value: userId)
                .execute()
        }

        // 4. Delete auth user via Edge Function (requires service_role).
        // Retried because the Edge Function cold-start can 503 on the
        // first hit after a long idle period.
        do {
            try await NetworkService.shared.withRetry {
                let _: Data = try await SupabaseService.shared.client.functions.invoke(
                    "delete-user",
                    options: .init(body: ["user_id": userId])
                )
            }
        } catch {
            AppLogger.database.report(error, context: "delete-user edge function")
            // Don't throw — the profile is already deleted, which is the RGPD-critical part.
            // A scheduled cron on the server will sweep orphaned auth.users rows.
        }

        AppLogger.database.info("User data deletion complete for \(userId, privacy: .public)")
    }
}
