import Foundation
import ClerkKit

// MARK: - Auth Service (Clerk-backed)
//
// Depuis le 20 avril 2026, HealthMap utilise Clerk comme unique provider d'auth
// (domaine custom `clerk.healthmap.fr`, instance PROD `pk_live_...`). Supabase
// Auth n'est PLUS utilisé : le `SupabaseClient` est configuré avec un
// `accessToken` closure qui pompe le JWT template "supabase" depuis la session
// Clerk courante — voir `SupabaseService.swift`.
//
// Cette classe expose la même surface que l'ancien `AuthService` Supabase
// (signUp/signIn/signOut/signInWithApple/resetPassword/refreshSession/
// currentSession/authStateChanges) pour minimiser la churn dans les ViewModels.
// Les retours sont typés `HMSession` (voir `Core/AuthTypes.swift`) au lieu de
// `Supabase.Session`, et le lookup `clerk_id → profiles.id (UUID)` est fait
// via `ClerkProfileResolver` (équivalent web `AuthContext.resolveProfile`).
@MainActor
final class AuthService {
    static let shared = AuthService()

    private init() {}

    // MARK: - Sign Up
    //
    // Flow Clerk : 2 étapes
    //   1. create(emailAddress, password, firstName) → prepare email code
    //   2. verifyEmailCode(code)                     → session active
    // Le `signupFirstName` est stocké temporairement pour bootstrapper
    // `profiles.first_name` lors du resolve.
    private(set) var pendingSignUpFirstName: String?

    /// Étape 1 : crée le compte Clerk + envoie le code email.
    /// L'UI doit ensuite afficher un champ code → appeler `verifySignUpCode`.
    func signUpStart(email: String, password: String, firstName: String) async throws {
        let signUp = try await Clerk.shared.auth.signUp(
            emailAddress: email,
            password: password,
            firstName: firstName
        )
        try await signUp.sendEmailCode()
        pendingSignUpFirstName = firstName
    }

    /// Étape 2 : vérifie le code email. Session active si `.complete`.
    func verifySignUpCode(_ code: String) async throws {
        guard var signUp = Clerk.shared.auth.currentSignUp else {
            throw HealthMapError.auth(.sessionExpired)
        }
        signUp = try await signUp.verifyEmailCode(code)
        guard signUp.status == .complete else {
            throw HealthMapError.auth(.signUpIncomplete)
        }
    }

    /// Legacy one-shot signUp — DEPRECATED : utiliser signUpStart + verifySignUpCode.
    /// Gardé pour compatibilité avec AuthViewModel existant ; lève une erreur
    /// "needs verification" pour forcer l'UI à basculer sur le flow en 2 étapes.
    func signUp(email: String, password: String, firstName: String) async throws {
        try await signUpStart(email: email, password: password, firstName: firstName)
        throw HealthMapError.auth(.signUpNeedsEmailCode)
    }

    // MARK: - Sign In (email + password)
    func signIn(email: String, password: String) async throws {
        let signIn = try await Clerk.shared.auth.signInWithPassword(
            identifier: email,
            password: password
        )
        guard signIn.status == .complete else {
            // 2FA / OTP / verification — la session n'est pas active.
            throw HealthMapError.auth(.signInIncomplete)
        }
    }

    // MARK: - Sign In with Google (OAuth via ASWebAuthenticationSession managed by Clerk)
    //
    // Clerk iOS SDK gère entièrement l'OAuth Google : pas besoin de monter
    // notre propre ASWebAuthenticationSession. La signature de retour reste
    // `URL` pour compat avec AuthViewModel, mais l'URL est bidon — la vraie
    // session est déjà posée sur Clerk.shared à ce stade. L'AuthViewModel
    // doit appeler `signInWithGoogleClerk()` à la place pour la nouvelle API.
    func signInWithGoogleClerk() async throws {
        _ = try await Clerk.shared.auth.signInWithOAuth(
            provider: .google,
            prefersEphemeralWebBrowserSession: true
        )
    }

    /// Legacy signature — garde la compat avec AuthViewModel.signInWithGoogle()
    /// existant. Lance le flow Clerk et retourne une URL placeholder.
    func signInWithGoogle() async throws -> URL {
        try await signInWithGoogleClerk()
        return URL(string: "healthmap://auth/callback")!
    }

    // MARK: - Sign In with Apple
    //
    // On consomme directement l'idToken produit par `SignInWithAppleButton`
    // SwiftUI (AuthView.swift). Pas besoin de relancer une 2e
    // `ASAuthorizationController` côté Clerk — `signInWithIdToken` valide
    // le token et pose la session. `rawNonce` est gardé dans la signature
    // pour la compat historique mais n'est pas transmis (le provider Apple
    // configuré dans Clerk Dashboard valide la chaîne nonce côté serveur).
    func signInWithApple(idToken: String, rawNonce: String) async throws {
        _ = try await Clerk.shared.auth.signInWithIdToken(idToken, provider: .apple)
    }

    // MARK: - Sign Out
    func signOut() async throws {
        try await Clerk.shared.auth.signOut()
    }

    // MARK: - Current Session (HMSession-shaped)
    //
    // Résout `profiles.id` (UUID) depuis `clerk_id = clerk.user.id` via
    // `ClerkProfileResolver`. Cache local pour éviter un round-trip à chaque
    // appel. `accessToken` est fetché à la volée (Clerk cache 10s par défaut).
    var currentSession: HMSession? {
        get async {
            guard Clerk.shared.session != nil, let clerkUser = Clerk.shared.user else {
                return nil
            }
            let profileId: UUID
            do {
                profileId = try await ClerkProfileResolver.shared.resolveProfileUUID(for: clerkUser)
            } catch {
                AppLogger.auth.report(error, context: "AuthService.currentSession.resolveProfile")
                return nil
            }
            // Clerk SDK >= 0.5: `getToken(_:)` returns `String?` directly
            // (was `TokenResource?` with `.jwt` in pre-1.0 builds).
            let token = try? await Clerk.shared.session?.getToken(.init(template: "supabase"))
            let email = clerkUser.primaryEmailAddress?.emailAddress
                ?? clerkUser.emailAddresses.first?.emailAddress
            let user = HMUser(
                id: profileId,
                email: email,
                firstName: clerkUser.firstName,
                clerkId: clerkUser.id
            )
            return HMSession(user: user, accessToken: token)
        }
    }

    var currentUser: HMUser? {
        get async { await currentSession?.user }
    }

    /// Accès synchrone au `profiles.id` (UUID) via le cache `ClerkProfileResolver`.
    /// Retourne nil si le resolve async n'a jamais été invoqué pour cet utilisateur
    /// (cold-start, sign-in juste posé mais pas encore consommé). Les call-sites
    /// synchrones (ex: `saveDraft` dans QuestionnaireVM) doivent tolérer nil.
    var cachedCurrentUserIdString: String? {
        guard let clerkUser = Clerk.shared.user else { return nil }
        return ClerkProfileResolver.shared.cachedProfileUUID(forClerkId: clerkUser.id)?.uuidString
    }

    // MARK: - Refresh Session
    //
    // Clerk gère le refresh automatiquement côté SDK. Ce call force un
    // nouveau fetch du JWT template "supabase" (skipCache: true) pour
    // garantir qu'on a un token frais.
    func refreshSession() async throws {
        guard let session = Clerk.shared.session else {
            throw HealthMapError.auth(.sessionExpired)
        }
        _ = try await session.getToken(.init(template: "supabase", skipCache: true))
    }

    // MARK: - Reset Password
    //
    // Flow Clerk :
    //   1. signIn(email) → prepareFirstFactor(.resetPasswordEmailCode)
    //   2. user entre code + new password → attemptFirstFactor + resetPassword
    // Cette méthode ne fait que l'étape 1. L'UI doit basculer vers un écran
    // "entre le code et ton nouveau mot de passe" et appeler `completeResetPassword`.
    func resetPassword(email: String) async throws {
        let signIn = try await Clerk.shared.auth.signIn(email)
        _ = try await signIn.sendResetPasswordEmailCode()
    }

    /// Étape 2 du reset : valide le code email + pose le nouveau mot de passe.
    func completeResetPassword(code: String, newPassword: String) async throws {
        guard let signIn = Clerk.shared.auth.currentSignIn else {
            throw HealthMapError.auth(.sessionExpired)
        }
        _ = try await signIn.verifyCode(code)
        _ = try await signIn.resetPassword(newPassword: newPassword)
    }

    // MARK: - Update Password (user connecté)
    func updatePassword(newPassword: String) async throws {
        guard let user = Clerk.shared.user else {
            throw HealthMapError.auth(.sessionExpired)
        }
        _ = try await user.updatePassword(.init(newPassword: newPassword))
    }

    // MARK: - Auth State Changes
    //
    // Clerk expose `clerk.events.authEventEmitter` via AsyncStream, mais sa
    // surface diffère de `Supabase.AuthStateChange`. On pond un stream dérivé
    // qui émet des `HMAuthChangeEvent` + `HMSession?` pour coller à l'API
    // historique consommée par AuthViewModel.listenToAuthChanges().
    func authStateChanges() -> AsyncStream<(event: HMAuthChangeEvent, session: HMSession?)> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                // Émet l'état initial immédiatement pour dismisser le launch screen.
                let initial = await self?.currentSession
                continuation.yield((event: HMAuthChangeEvent.initialSession, session: initial))

                for await event in Clerk.shared.auth.events {
                    guard !Task.isCancelled else { break }
                    let mapped: HMAuthChangeEvent
                    switch event {
                    case .signInCompleted:        mapped = .signedIn
                    case .signUpCompleted:        mapped = .signedIn
                    case .signedOut:              mapped = .signedOut
                    case .accountDeleted:         mapped = .signedOut
                    case .tokenRefreshed:         mapped = .tokenRefreshed
                    case .sessionChanged(let old, let new):
                        // Map session transitions to the closest legacy event.
                        mapped = (new == nil && old != nil) ? .signedOut
                               : (new != nil && old == nil) ? .signedIn
                               : .userUpdated
                    @unknown default:             continue
                    }
                    let session = await self?.currentSession
                    continuation.yield((event: mapped, session: session))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
