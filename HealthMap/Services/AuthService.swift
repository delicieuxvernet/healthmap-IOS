import Foundation
import Supabase

// MARK: - Auth Service (Supabase Auth-backed)
//
// HealthMap utilise Supabase Auth comme provider d'auth depuis 2026-06-06.
// Avant : Clerk (migration retirée pour simplification + bugs Apple/Google OAuth).
//
// Le flow signup standard Supabase est en 1 étape (pas de email code 2-step).
// Le profile row côté DB est créé automatiquement par le trigger Postgres
// `handle_new_user` (voir migration DB 2026-06-06), donc le client n'a rien
// à insérer manuellement → fin du bug RLS qui faisait planter chaque signup.
//
// Pour préserver la surface API existante consommée par AuthViewModel/AuthView,
// les fonctions Clerk-specific (signUpStart, verifySignUpCode, resendSignUpEmailCode)
// sont conservées mais leur comportement diffère :
//   - signUpStart() devient un signup direct (session active immédiatement)
//   - verifySignUpCode() devient no-op (la session est déjà active)
// Cela permet à l'UI de continuer à fonctionner sans modif majeure ; l'écran
// de saisie du code email peut être skippé en regardant `currentSession != nil`.
@MainActor
final class AuthService {
    static let shared = AuthService()

    private init() {}

    private var client: SupabaseClient {
        SupabaseService.shared.client
    }

    private var auth: AuthClient {
        client.auth
    }

    // MARK: - First name temp storage (UI ↔ trigger metadata bridge)
    //
    // Le `first_name` est passé via `data` à `signUp` → atteint le trigger
    // `handle_new_user` via `NEW.raw_user_meta_data->>'first_name'`. On garde
    // une copie locale pour compat avec ProfileResolver qui peut le lire si
    // jamais la metadata n'a pas été propagée à temps (race rare).
    private(set) var pendingSignUpFirstName: String?

    // MARK: - Sign Up
    //
    // Crée le compte Supabase Auth + pose la session. Le trigger DB
    // `handle_new_user` crée le profile row automatiquement (avec
    // `auth_user_id = NEW.id` + `email` + `first_name`).
    //
    // Si "Confirm email" est activé dans Supabase Dashboard, la session sera
    // inactive jusqu'au click magic link — gérer ce cas via authStateChanges.
    func signUp(email: String, password: String, firstName: String) async throws {
        pendingSignUpFirstName = firstName
        _ = try await auth.signUp(
            email: email,
            password: password,
            data: [
                "first_name": .string(firstName)
            ]
        )
    }

    /// Wrapper compat : avant l'UI faisait signUpStart → écran code → verifySignUpCode.
    /// Avec Supabase Auth (sans confirm email) on pose la session direct. L'UI
    /// peut toujours appeler ces deux fonctions, le résultat sera juste qu'on
    /// est déjà connecté à la fin de signUpStart.
    func signUpStart(email: String, password: String, firstName: String) async throws {
        try await signUp(email: email, password: password, firstName: firstName)
    }

    /// No-op compat — la session est déjà active après signUp.
    /// Lève `.signUpIncomplete` si la session n'est PAS active (= "Confirm email"
    /// activé côté Dashboard et user n'a pas encore cliqué le lien).
    func verifySignUpCode(_ code: String) async throws {
        _ = code  // unused — supabase Auth ne demande pas de code email user-side
        guard (try? await auth.session) != nil else {
            throw HealthMapError.auth(.signUpIncomplete)
        }
    }

    /// No-op compat — pas de code email en flow Supabase Auth standard.
    func resendSignUpEmailCode() async throws {
        // intentional no-op
    }

    // MARK: - Sign In
    func signIn(email: String, password: String) async throws {
        _ = try await auth.signIn(email: email, password: password)
    }

    // MARK: - Sign In with Apple
    //
    // L'idToken est produit par `SignInWithAppleButton` SwiftUI (voir AuthView).
    // Supabase Auth valide la signature Apple côté serveur — la chaîne `nonce`
    // doit matcher entre la request initiale et le token, sinon rejet.
    //
    // PRÉREQUIS Supabase Dashboard → Authentication → Providers → Apple :
    //   - Services ID (Apple Developer)
    //   - Team ID
    //   - Key ID + Private Key (.p8)
    func signInWithApple(idToken: String, rawNonce: String) async throws {
        _ = try await auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: rawNonce
            )
        )
    }

    // MARK: - Sign In with Google (OAuth)
    //
    // PRÉREQUIS Supabase Dashboard → Authentication → Providers → Google :
    //   - Client ID (Google Cloud Console — type "iOS application")
    //   - Client Secret (si type web ; pour iOS natif typiquement non requis)
    // PRÉREQUIS app : custom URL scheme `healthmap://` dans Info.plist (déjà OK).
    func signInWithGoogle() async throws {
        _ = try await auth.signInWithOAuth(
            provider: .google,
            redirectTo: URL(string: "healthmap://auth/callback")
        )
    }

    /// Legacy signature — garde la compat avec AuthViewModel.signInWithGoogle()
    func signInWithGoogleClerk() async throws {
        try await signInWithGoogle()
    }

    // MARK: - Sign Out
    func signOut() async throws {
        try await auth.signOut()
        pendingSignUpFirstName = nil
        ProfileResolver.shared.invalidate()
    }

    // MARK: - Current Session (HMSession-shaped)
    //
    // Résout `profiles.id` (UUID) depuis `auth.users.id` via `ProfileResolver`.
    // Cache local pour éviter un round-trip à chaque appel.
    var currentSession: HMSession? {
        get async {
            guard let session = try? await auth.session else { return nil }
            let authUserId = session.user.id

            let profileId: UUID
            do {
                profileId = try await ProfileResolver.shared.resolveProfileUUID(forAuthUserId: authUserId)
            } catch HealthMapError.auth(.profileResolutionTimeout) {
                AppLogger.auth.notice("Profile resolution timed out — Supabase auth session active mais profile non chargé")
                return nil
            } catch {
                AppLogger.auth.report(error, context: "AuthService.currentSession.resolveProfile")
                return nil
            }

            let firstName = session.user.userMetadata["first_name"]?.stringValue
                ?? pendingSignUpFirstName

            let user = HMUser(
                id: profileId,
                email: session.user.email,
                firstName: firstName,
                clerkId: ""  // unused; kept for API compat with legacy call-sites
            )
            return HMSession(user: user, accessToken: session.accessToken)
        }
    }

    var currentUser: HMUser? {
        get async { await currentSession?.user }
    }

    /// Accès synchrone au `profiles.id` (UUID) via le cache `ProfileResolver`.
    /// Retourne nil si le resolve async n'a jamais été invoqué pour cet utilisateur.
    var cachedCurrentUserIdString: String? {
        guard let authUserId = client.auth.currentUser?.id else { return nil }
        return ProfileResolver.shared.cachedProfileUUID(forAuthUserId: authUserId)?.uuidString
    }

    // MARK: - Refresh Session
    func refreshSession() async throws {
        _ = try await auth.refreshSession()
    }

    // MARK: - Reset Password
    func resetPassword(email: String) async throws {
        try await auth.resetPasswordForEmail(email)
    }

    /// Étape 2 du reset compat : applique le nouveau mot de passe.
    /// Avec Supabase Auth standard, le reset se fait via magic link → l'user
    /// arrive sur l'app via deep link + appelle `updateUser(password:)`.
    /// Pour rester compat avec l'API existante, on tente un update password
    /// direct (suppose qu'une session est active via le deep link).
    func completeResetPassword(code: String, newPassword: String) async throws {
        _ = code  // unused — Supabase reset utilise magic link, pas un code 6 chiffres
        try await updatePassword(newPassword: newPassword)
    }

    // MARK: - Update Password (user connecté)
    func updatePassword(newPassword: String) async throws {
        guard (try? await auth.session) != nil else {
            throw HealthMapError.auth(.sessionExpired)
        }
        _ = try await auth.update(user: UserAttributes(password: newPassword))
    }

    // MARK: - Auth State Changes
    //
    // Supabase Auth expose nativement un `AsyncStream<(AuthChangeEvent, Session?)>`.
    // On mappe ses événements vers `HMAuthChangeEvent` pour préserver la surface
    // historique consommée par AuthViewModel.listenToAuthChanges().
    func authStateChanges() -> AsyncStream<(event: HMAuthChangeEvent, session: HMSession?)> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }

                // Émet l'état initial immédiatement.
                let initial = await self.currentSession
                continuation.yield((event: HMAuthChangeEvent.initialSession, session: initial))

                for await (event, _) in self.client.auth.authStateChanges {
                    guard !Task.isCancelled else { break }

                    let mapped: HMAuthChangeEvent
                    switch event {
                    case .initialSession:         mapped = .initialSession
                    case .signedIn:               mapped = .signedIn
                    case .signedOut:              mapped = .signedOut
                    case .tokenRefreshed:         mapped = .tokenRefreshed
                    case .userUpdated:            mapped = .userUpdated
                    case .userDeleted:            mapped = .signedOut
                    case .mfaChallengeVerified:   mapped = .userUpdated
                    case .passwordRecovery:       continue
                    @unknown default:             continue
                    }

                    let session = await self.currentSession
                    continuation.yield((event: mapped, session: session))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
