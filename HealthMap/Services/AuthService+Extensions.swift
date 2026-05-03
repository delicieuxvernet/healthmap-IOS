import Foundation
import ClerkKit

// MARK: - Protocol conformance
extension AuthService: AuthServiceProtocol {}

// MARK: - Account deletion (Apple + RGPD)
extension AuthService {
    /// Deletes the current user's account AND all associated data.
    /// Required by Apple App Store guideline 5.1.1 (v) since iOS 16.
    ///
    /// Flow (depuis migration Clerk du 20 avril 2026) :
    /// 1. Résout le `profiles.id` (UUID) du user courant.
    /// 2. Appelle `DatabaseService.deleteAllUserData` (qui invoque l'Edge Function
    ///    `delete-user` en passant l'UUID — l'Edge Function côté Supabase nettoie
    ///    les rows `profiles`, `score_history`, `analytics_events`, etc.).
    /// 3. Supprime également l'utilisateur Clerk via `user.delete()`. Sans ça,
    ///    l'user garde son compte Clerk vivant et peut recréer un profil dessus.
    /// 4. Sign out local (graceful-fail : le compte est déjà effacé côté serveur,
    ///    l'erreur réseau à ce stade ne doit pas bloquer l'UI — `AuthViewModel.
    ///    finaliseSignOutAfterDeletion()` nettoie le view-model state dans tous les cas).
    /// 5. Reset analytics + crash reporting identity.
    func deleteAccount() async throws {
        guard let session = await currentSession else {
            throw HealthMapError.auth(.sessionExpired)
        }
        let userId = session.user.id.uuidString
        let clerkId = session.user.clerkId

        AppLogger.auth.notice("Deleting account profileId=\(userId, privacy: .public) clerkId=\(clerkId, privacy: .public)")
        CrashReportingService.shared.breadcrumb("account delete started", category: "auth", level: .warning)

        // Step 2 — RGPD-critical delete côté Supabase. Any failure MUST propagate
        // so the UI can show the retry/support CTA.
        try await DatabaseService.shared.deleteAllUserData(userId: userId)

        // Step 3 — suppression Clerk (best-effort : si ça échoue, l'user n'a plus
        // rien en DB de toute façon, donc on log et on continue).
        if let clerkUser = Clerk.shared.user {
            do {
                _ = try await clerkUser.delete()
            } catch {
                AppLogger.auth.notice("Clerk user.delete() failed (non-fatal): \(error.localizedDescription, privacy: .public)")
                CrashReportingService.shared.breadcrumb("clerk user.delete failed (non-fatal)", category: "auth", level: .warning)
            }
        }

        // Step 4 — sign out. Graceful-fail : le compte n'existe plus côté serveur,
        // un throw ici laisserait l'UI coincée. On log et on continue.
        do {
            try await signOut()
        } catch {
            AppLogger.auth.notice("signOut after delete failed (non-fatal): \(error.localizedDescription, privacy: .public)")
        }

        ClerkProfileResolver.shared.invalidate()
        AnalyticsService.shared.reset()
        AnalyticsService.shared.track(.signOutCompleted, properties: ["reason": "account_deleted"])
        AppLogger.auth.info("Account \(userId, privacy: .public) deleted")
    }
}
