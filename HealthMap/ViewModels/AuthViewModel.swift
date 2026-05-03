import Foundation

@MainActor
final class AuthViewModel: ObservableObject {

    // MARK: - Published State

    @Published var user: HMUser?
    @Published var session: HMSession?
    @Published var isAuthenticated = false
    /// Starts `true` so the launch screen shows while the Supabase auth state
    /// listener restores the persisted Keychain session. Without this, a
    /// returning user briefly sees AuthView before being routed to MainTabView.
    @Published var isLoading = true
    @Published var errorMessage: String?

    /// Set to `true` by `startRefreshTimer` when an automatic session refresh
    /// fails because the refresh token has expired or been revoked. Observed
    /// by `ContentView`, which surfaces a single-shot alert ("Votre session
    /// a expire...") so the user understands why they were just bounced back
    /// to the auth screen instead of seeing it as a mysterious app glitch.
    /// Reset to `false` when the user dismisses the alert.
    @Published var sessionExpiredNotice = false

    // MARK: - Computed

    var userEmail: String? {
        user?.email ?? session?.user.email
    }

    /// True dès qu'un code email est en attente de saisie après signUp().
    /// L'UI de signup doit afficher un champ "code à 6 chiffres" quand ce
    /// flag est actif, et appeler `verifySignUpCode(_:)` à la soumission.
    @Published var pendingEmailVerification = false

    // MARK: - Private

    private var authListenerTask: Task<Void, Never>?
    private var refreshTimer: Task<Void, Never>?

    /// Session refresh interval (matches web: 10 minutes)
    private static let sessionRefreshInterval: TimeInterval = 10 * 60

    // MARK: - Init

    init() {
        listenToAuthChanges()

        // Safety net: if the Supabase SDK never emits an auth event (e.g.
        // broken config, SDK internal error), the user would be stuck on
        // LaunchScreenView forever. After 10 seconds, force the loading
        // screen to dismiss so the user can at least reach AuthView.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.isLoading else { return }
            AppLogger.auth.notice("Auth state restoration timed out — dismissing launch screen")
            self.isLoading = false
        }
    }

    deinit {
        authListenerTask?.cancel()
        refreshTimer?.cancel()
    }

    // MARK: - Auth State Listener

    private func listenToAuthChanges() {
        authListenerTask = Task { [weak self] in
            for await (event, session) in AuthService.shared.authStateChanges() {
                guard let self, !Task.isCancelled else { return }

                self.session = session
                self.user = session?.user
                self.isAuthenticated = session != nil

                // First event (initialSession or signedIn) means session
                // restoration is complete — dismiss the launch screen.
                if self.isLoading {
                    self.isLoading = false
                }

                switch event {
                case .signedIn, .tokenRefreshed, .initialSession, .userUpdated:
                    startRefreshTimer()
                    if event == .signedIn {
                        // Clear any stale data from a previous user who may not
                        // have signed out explicitly (e.g. session expired, app
                        // force-closed). This is defense-in-depth on top of the
                        // sign-out cleanup — it guarantees the new user never
                        // inherits another user's cached streak, badges, or
                        // offline queue payloads.
                        self.clearLocalCaches()
                        GamificationService.shared.reset()

                        if let userId = session?.user.id.uuidString {
                            await SubscriptionService.shared.identify(userId: userId)
                        }
                        AnalyticsService.shared.track(.signInCompleted)
                    }

                case .signedOut:
                    stopRefreshTimer()
                    clearLocalCaches()
                    ClerkProfileResolver.shared.invalidate()
                    GamificationService.shared.reset()
                    AnalyticsService.shared.reset()
                    await SubscriptionService.shared.reset()
                    AnalyticsService.shared.track(.signOutCompleted)
                }
            }
        }
    }

    // MARK: - Auto Session Refresh (every 10 min, like web)

    private func startRefreshTimer() {
        refreshTimer?.cancel()
        refreshTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.sessionRefreshInterval))
                guard !Task.isCancelled else { return }
                do {
                    try await AuthService.shared.refreshSession()
                } catch {
                    let desc = error.localizedDescription.lowercased()
                    if desc.contains("invalid refresh token") || desc.contains("session_not_found") {
                        // Surface a user-facing notice BEFORE signing out so
                        // ContentView's alert is armed by the time the user
                        // sees AuthView. The Task body inherits the
                        // @MainActor context from `startRefreshTimer` (which
                        // lives on the @MainActor-isolated AuthViewModel),
                        // so this synchronous property write is safe.
                        // Without this notice, the user is bounced back to
                        // the login screen with zero context, which they
                        // perceive as a glitch.
                        self?.sessionExpiredNotice = true
                        AppLogger.auth.notice("Refresh token invalid — signing out and surfacing notice")
                        AnalyticsService.shared.track(.signOutCompleted, properties: [
                            "reason": "session_expired",
                        ])
                        await self?.signOut()
                    } else {
                        // Transient errors (network, timeout) — log and let
                        // the next 10-minute tick try again. We don't want
                        // a flaky cell signal to silently kick the user out.
                        AppLogger.auth.notice("Session refresh failed (transient): \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    // MARK: - Clear Local Caches (like web clears healthmap_* localStorage)

    private func clearLocalCaches() {
        let defaults = UserDefaults.standard
        let keysToRemove = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("healthmap_") }
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Veuillez remplir tous les champs."
            return
        }

        // Rate limiting check
        let throttle = LoginThrottleService.shared.canAttempt()
        if !throttle.allowed {
            errorMessage = LoginThrottleService.shared.throttleMessage()
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await AuthService.shared.signIn(email: email, password: password)

            let currentSession = await AuthService.shared.currentSession
            self.session = currentSession
            self.user = currentSession?.user
            self.isAuthenticated = currentSession != nil

            // Successful login — reset throttle
            LoginThrottleService.shared.reset()

            if let userId = currentSession?.user.id.uuidString {
                await SubscriptionService.shared.identify(userId: userId)
            }

            AnalyticsService.shared.track(.signInCompleted, properties: ["method": "email"])
        } catch {
            LoginThrottleService.shared.recordFailure()
            errorMessage = Self.mapAuthError(error)
        }

        isLoading = false
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, firstName: String) async {
        guard !email.isEmpty, !password.isEmpty, !firstName.isEmpty else {
            errorMessage = "Veuillez remplir tous les champs."
            return
        }

        // Enhanced password validation
        let validationIssues = PasswordValidator.validate(password)
        if !validationIssues.isEmpty {
            errorMessage = validationIssues.map(\.message).joined(separator: "\n")
            return
        }

        // Rate limiting check
        let throttle = LoginThrottleService.shared.canAttempt()
        if !throttle.allowed {
            errorMessage = LoginThrottleService.shared.throttleMessage()
            return
        }

        isLoading = true
        errorMessage = nil

        AnalyticsService.shared.track(.signUpStarted)

        do {
            // Clerk flow : signUpStart envoie un code email, puis l'UI bascule
            // vers un champ "entrez le code reçu" et appelle verifySignUpCode.
            try await AuthService.shared.signUpStart(email: email, password: password, firstName: firstName)
            pendingEmailVerification = true
            LoginThrottleService.shared.reset()
            AnalyticsService.shared.track(.signUpStarted, properties: ["method": "email"])
        } catch {
            LoginThrottleService.shared.recordFailure()
            errorMessage = Self.mapAuthError(error)
        }

        isLoading = false
    }

    /// Étape 2 du signup : valide le code email reçu par Clerk.
    /// À appeler depuis l'UI après que l'user a entré son code.
    func verifySignUpCode(_ code: String) async {
        guard !code.isEmpty else {
            errorMessage = "Veuillez saisir le code reçu par email."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            try await AuthService.shared.verifySignUpCode(code)
            pendingEmailVerification = false

            let currentSession = await AuthService.shared.currentSession
            self.session = currentSession
            self.user = currentSession?.user
            self.isAuthenticated = currentSession != nil

            if let userId = currentSession?.user.id.uuidString {
                await SubscriptionService.shared.identify(userId: userId)
            }
            AnalyticsService.shared.track(.signUpCompleted, properties: ["method": "email"])
        } catch {
            errorMessage = Self.mapAuthError(error)
        }
        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() async {
        isLoading = true
        errorMessage = nil

        do {
            try await AuthService.shared.signOut()
        } catch {
            // Log the error but DON'T bail out — local state MUST be cleaned
            // regardless of whether the server-side sign-out succeeded.
            // A failed server sign-out still means the user wants to leave:
            // keeping stale state leads to cross-user data leaks.
            AppLogger.auth.notice("Server sign-out failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Deconnexion partielle — tes donnees locales ont ete nettoyees."
        }

        // Always clear local state, even if server sign-out threw
        self.session = nil
        self.user = nil
        self.isAuthenticated = false

        clearLocalCaches()
        GamificationService.shared.reset()
        AnalyticsService.shared.reset()
        await SubscriptionService.shared.reset()
        // Note: .signOutCompleted is tracked by the auth listener's .signedOut
        // handler, not here — avoids double-counting in analytics.

        isLoading = false
    }

    // MARK: - Delete Account (Apple 5.1.1(v) + RGPD Art. 17)

    /// Permanently deletes the user account and all associated data.
    /// Returns `true` on success so the caller can dismiss the confirmation UI.
    ///
    /// Important timing contract:
    ///   - On success we return **without** flipping `isAuthenticated`. The
    ///     caller (ProfileView) needs a brief window to dismiss the confirmation
    ///     sheet before the root view switches from `MainTabView` to `AuthView`;
    ///     flipping too early caused a visible cross-fade flash over the open
    ///     sheet. `finaliseSignOut()` is the explicit follow-up call the caller
    ///     makes once its UI is settled.
    ///   - On failure we do NOT touch `isAuthenticated` either — the user must
    ///     stay in the flow so they can retry or contact support.
    func deleteAccount() async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            try await AuthService.shared.deleteAccount()
            isLoading = false
            return true
        } catch {
            AppLogger.auth.report(error, context: "AuthViewModel deleteAccount")
            errorMessage = "Erreur lors de la suppression du compte. Reessayez ou contactez le support."
            isLoading = false
            return false
        }
    }

    /// Second half of the delete-account flow: call this once the confirmation
    /// UI has been dismissed so `ContentView` routes back to `AuthView` without
    /// flashing across a still-open sheet.
    func finaliseSignOutAfterDeletion() {
        self.session = nil
        self.user = nil
        self.isAuthenticated = false

        // Belt-and-braces: if deleteAccount()'s internal signOut() failed or
        // the auth listener's .signedOut event raced, these caches might still
        // contain the deleted user's data. Wipe them now to guarantee the next
        // sign-in starts clean.
        clearLocalCaches()
        GamificationService.shared.reset()
        AnalyticsService.shared.reset()
        Task { await SubscriptionService.shared.reset() }
    }

    // MARK: - Reset Password

    func resetPassword(email: String) async -> Bool {
        guard !email.isEmpty else {
            errorMessage = "Veuillez saisir votre adresse email."
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            try await AuthService.shared.resetPassword(email: email)
            AnalyticsService.shared.track(.passwordResetRequested, properties: ["method": "email"])
            isLoading = false
            return true
        } catch {
            errorMessage = Self.mapAuthError(error)
            isLoading = false
            return false
        }
    }

    // MARK: - Sign In with Google (Clerk gère l'ASWebAuthenticationSession en interne)

    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil

        do {
            try await AuthService.shared.signInWithGoogleClerk()
            // Auth state listener (Clerk events) pousse .signedIn, qui met
            // à jour self.session via currentSession lookup.
            AnalyticsService.shared.track(.signInCompleted, properties: ["method": "google"])
        } catch {
            AppLogger.auth.report(error, context: "AuthViewModel signInWithGoogle")
            errorMessage = "Erreur de connexion avec Google."
        }

        isLoading = false
    }

    // MARK: - Sign In with Apple (Apple App Store guideline 4.8)

    /// Exchanges an Apple identity token for a Supabase session.
    /// The caller (typically `AuthView`) is responsible for running the
    /// `ASAuthorizationController` request and forwarding the raw nonce
    /// (the same one whose SHA256 was sent in the request).
    ///
    /// - Parameters:
    ///   - firstName / email: optional, **present only on the very first**
    ///     Sign in with Apple. Apple drops them on subsequent sign-ins, so
    ///     we persist them into `profiles` immediately — without these the
    ///     dashboard would show an empty "Bonjour, " greeting forever.
    func signInWithApple(idToken: String, rawNonce: String, firstName: String?, email: String?) async {
        isLoading = true
        errorMessage = nil

        do {
            // On a déjà un idToken du SignInWithAppleButton SwiftUI (AuthView).
            // On le forwarde à Clerk via `signInWithIdToken` — ça évite de
            // relancer une 2e ASAuthorizationController côté Clerk. Le `rawNonce`
            // est inchangé pour compat de signature (Clerk gère la validation
            // nonce côté serveur via le provider Apple configuré dans le Dashboard).
            // `firstName`/`email` ne sont dispo qu'au 1er signin — on les
            // repique ensuite via `bootstrapAppleProfile`.
            try await AuthService.shared.signInWithApple(idToken: idToken, rawNonce: rawNonce)

            let currentSession = await AuthService.shared.currentSession
            self.session = currentSession
            self.user = currentSession?.user
            self.isAuthenticated = currentSession != nil

            if let userId = currentSession?.user.id.uuidString {
                await SubscriptionService.shared.identify(userId: userId)

                // Bootstrap `profiles.first_name` / `email` si Apple les a
                // fournis (dispo uniquement au 1er signin — Apple les drop
                // ensuite). `ignoreDuplicates: true` évite d'overwrite un
                // profil déjà renseigné.
                do {
                    try await DatabaseService.shared.bootstrapAppleProfile(
                        userId: userId,
                        email: email ?? currentSession?.user.email,
                        firstName: firstName
                    )
                } catch {
                    AppLogger.auth.notice("bootstrapAppleProfile failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            AnalyticsService.shared.track(.signInCompleted, properties: ["method": "apple"])
        } catch {
            AppLogger.auth.report(error, context: "AuthViewModel signInWithApple")
            errorMessage = "Erreur de connexion avec Apple."
        }

        isLoading = false
    }

    // MARK: - Password Strength (for UI binding)

    /// Returns the strength of a password for real-time UI feedback.
    func passwordStrength(_ password: String) -> PasswordStrength {
        PasswordValidator.strength(of: password)
    }

    // MARK: - Error Mapping

    private static func mapAuthError(_ error: Error) -> String {
        let description = error.localizedDescription.lowercased()

        if description.contains("invalid login credentials") || description.contains("invalid_credentials") {
            return "Email ou mot de passe incorrect."
        }
        if description.contains("email not confirmed") {
            return "Veuillez confirmer votre email."
        }
        if description.contains("user already registered") || description.contains("already_exists") {
            return "Un compte existe deja avec cet email."
        }
        if description.contains("network") || description.contains("timeout") {
            return "Erreur reseau. Verifiez votre connexion."
        }
        if description.contains("weak password") || description.contains("password") {
            return "Le mot de passe doit contenir au moins 8 caracteres."
        }
        if description.contains("rate limit") || description.contains("too many requests") {
            return "Trop de tentatives. Reessayez dans quelques minutes."
        }

        return "Une erreur est survenue. Veuillez reessayer."
    }
}

