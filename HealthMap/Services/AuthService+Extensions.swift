import Foundation
import Supabase

// MARK: - Protocol conformance
extension AuthService: AuthServiceProtocol {}

// MARK: - Account deletion (Apple + RGPD)
extension AuthService {
    /// Deletes the current user's account AND all associated data.
    /// Required by Apple App Store guideline 5.1.1 (v) since iOS 16.
    ///
    /// Flow (depuis migration Supabase Auth du 2026-06-06) :
    /// 1. Résout le `profiles.id` (UUID) du user courant.
    /// 2. Appelle `DatabaseService.deleteAllUserData` (qui invoque l'Edge Function
    ///    `delete-user` côté Supabase — nettoie `profiles`, `score_history`, etc.).
    /// 3. Supprime également l'utilisateur Supabase Auth via l'Edge Function
    ///    `delete-user` (qui call admin.deleteUser côté serveur — le client ne peut
    ///    pas le faire directement sans service_role).
    /// 4. Sign out local (graceful-fail).
    /// 5. Reset analytics + crash reporting identity.
    func deleteAccount() async throws {
        guard let session = await currentSession else {
            throw HealthMapError.auth(.sessionExpired)
        }
        let userId = session.user.id.uuidString

        AppLogger.auth.notice("Deleting account profileId=\(userId, privacy: .public)")
        CrashReportingService.shared.breadcrumb("account delete started", category: "auth", level: .warning)

        // Step 2 — RGPD-critical delete côté Supabase. L'Edge Function delete-user
        // doit nettoyer toutes les rows user-scoped ET appeler
        // supabase.auth.admin.deleteUser(authUserId) pour supprimer aussi le
        // record auth.users. Any failure MUST propagate.
        try await DatabaseService.shared.deleteAllUserData(userId: userId)

        // Step 4 — sign out local. Graceful-fail : si la session est déjà
        // invalide (compte supprimé côté serveur), un throw ici laisserait
        // l'UI coincée. On log et on continue.
        do {
            try await signOut()
        } catch {
            AppLogger.auth.notice("signOut after delete failed (non-fatal): \(error.localizedDescription, privacy: .public)")
        }

        ProfileResolver.shared.invalidate()
        AnalyticsService.shared.reset()
        AnalyticsService.shared.track(.signOutCompleted, properties: ["reason": "account_deleted"])
        AppLogger.auth.info("Account \(userId, privacy: .public) deleted")
    }
}
