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
    /// PAS de retry automatique ici : la suppression n'est pas rejouable.
    /// Après un premier succès serveur, le même JWT ne résout plus aucun
    /// utilisateur → toute nouvelle tentative répond 401. Un retry « pour
    /// fiabiliser » transforme donc un succès en erreur affichée à tort
    /// (incident du 11 juin 2026, voir le commentaire dans le corps).
    /// En cas d'échec réseau réel, l'utilisateur retape le bouton —
    /// relancer est sans danger tant que la suppression n'a pas eu lieu.
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
        // BUG corrigé 11 juin 2026 (« erreur » affichée après une suppression
        // réussie) : `let _: Data = invoke(...)` sélectionnait l'overload
        // Decodable du SDK → JSONDecoder attend du base64 pour `Data` et
        // jetait une DecodingError alors que le serveur avait répondu 200 et
        // TOUT supprimé ; withRetry rejouait alors l'appel avec un JWT devenu
        // orphelin → 401 → erreur UI sur un compte pourtant bien effacé
        // (logs edge : chaque 200 suivi d'un 401 ~5-9 s après, 4/4
        // suppressions). D'où : overload SANS décodage de réponse (le corps
        // de la réponse ne nous sert à rien), et aucun retry.
        try await SupabaseService.shared.client.functions.invoke(
            "delete-user",
            options: .init(body: ["confirm": "DELETE_MY_ACCOUNT"])
        )

        AppLogger.database.info("User data deletion complete for \(userId, privacy: .public)")
    }
}
