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
    ///
    /// IMPORTANT: this flag is owned exclusively by the session-restoration
    /// path (init + first auth event). Per-operation in-flight state
    /// (signIn, signUp, resetPassword…) lives in `isProcessing` instead —
    /// flipping `isLoading` from inside those methods would force
    /// ContentView to swap AuthView for LaunchScreenView mid-flow, which
    /// destroys any presented sheet (e.g. the password-reset sheet
    /// dismisses to login the moment the user taps "Envoyer le code").
    @Published var isLoading = true

    /// True while a user-triggered auth call (signIn, signUp, resetPassword,
    /// completeResetPassword, signInWithApple/Google, deleteAccount,
    /// updatePassword, resend codes…) is in flight. Buttons disable +
    /// show ProgressView based on this; ContentView ignores it.
    @Published var isProcessing = false

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

    /// Email de l'utilisateur en cours de reset password — set par
    /// `resetPassword(email:)` et utilisé par `completeResetPassword` pour
    /// auto-renvoyer un nouveau code si la session Clerk a été perdue entre
    /// les 2 étapes (app fermée, kill, time elapsed > token TTL). Sans ce
    /// flag, l'user voit "Session expirée" sans contexte ni recovery path.
    @Published var resetPasswordEmail: String?

    /// A4 : nonce Apple Sign In gardé au niveau ViewModel pour ne pas être
    /// perdu si AuthView rebuild en plein flow (rotation, multitasking).
    /// L'AuthView lit/écrit ce flag dans onRequest/onCompletion. Reset à nil
    /// dès que le flow est terminé (succès, erreur, ou cancel).
    @Published var pendingAppleNonce: AppleSignInNonce.Pair?

    /// Compteur local des renvois de code (signup OU reset password) pour
    /// éviter le spam. Reset après chaque succès de verify ou changement
    /// d'email. Plafond géré dans `resendSignUpCode()` / resend reset.
    @Published private(set) var resendAttempts: Int = 0
    private static let maxResendAttempts: Int = 3

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
                    // Mirror the cleanup in `signOut()` — when Clerk emits
                    // a sign-out we didn't initiate (token revoked,
                    // server-side delete), the per-flow flags must be
                    // cleared too so the next user can't see stale state.
                    self.pendingEmailVerification = false
                    self.resetPasswordEmail = nil
                    self.resendAttempts = 0
                    self.pendingAppleNonce = nil
                    PushNotificationService.shared.cancelInFlightTokenSave()
                    LoginThrottleService.shared.reset()
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
                    // Re-check cancellation after the await: the user may have
                    // signed out *during* the refresh round-trip; in that case
                    // we must not flip any user-facing flag, and we must not
                    // double-call signOut.
                    if Task.isCancelled { return }
                } catch {
                    if Task.isCancelled { return }
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

        isProcessing = true
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
            // session_exists recovery: Clerk already has an active session
            // (typical post-reset-password, post-OAuth, or stale local state).
            // Re-fetching `currentSession` flips `isAuthenticated` and routes
            // the user to MainTabView instead of throwing the generic error.
            // Don't increment the throttle on this branch — the user did not
            // type a wrong password, the system was just out of sync.
            let raw = error.localizedDescription.lowercased()
            if raw.contains("session_exists")
                || raw.contains("already signed in")
                || raw.contains("you're already signed in") {
                let fresh = await AuthService.shared.currentSession
                self.session = fresh
                self.user = fresh?.user
                self.isAuthenticated = fresh != nil
                LoginThrottleService.shared.reset()
                if let userId = fresh?.user.id.uuidString {
                    await SubscriptionService.shared.identify(userId: userId)
                }
                AnalyticsService.shared.track(.signInCompleted, properties: ["method": "session_recover"])
            } else {
                LoginThrottleService.shared.recordFailure()
                errorMessage = Self.mapAuthError(error)
            }
        }

        isProcessing = false
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

        // Note: deliberately *not* gated by LoginThrottleService — that
        // throttle exists to slow down credential-stuffing attacks against
        // an existing account, not to penalise legitimate users whose
        // signup attempt got rejected (network flake, "email already
        // taken", "password pwned" etc.). Counting signup failures
        // against the login throttle means a flaky signup locks the user
        // out of *real* sign-in attempts — the opposite of what the
        // throttle is for.

        isProcessing = true
        errorMessage = nil

        AnalyticsService.shared.track(.signUpStarted)

        do {
            // Clerk flow : signUpStart envoie un code email, puis l'UI bascule
            // vers un champ "entrez le code reçu" et appelle verifySignUpCode.
            try await AuthService.shared.signUpStart(email: email, password: password, firstName: firstName)
            pendingEmailVerification = true
            AnalyticsService.shared.track(.signUpStarted, properties: ["method": "email"])
        } catch {
            errorMessage = Self.mapAuthError(error)
        }

        isProcessing = false
    }

    /// Étape 2 du signup : valide le code email reçu par Clerk.
    /// À appeler depuis l'UI après que l'user a entré son code.
    func verifySignUpCode(_ code: String) async {
        guard !code.isEmpty else {
            errorMessage = "Veuillez saisir le code reçu par email."
            return
        }
        isProcessing = true
        errorMessage = nil
        do {
            try await AuthService.shared.verifySignUpCode(code)
            pendingEmailVerification = false
            resendAttempts = 0

            let currentSession = await AuthService.shared.currentSession
            self.session = currentSession
            self.user = currentSession?.user
            self.isAuthenticated = currentSession != nil

            if let userId = currentSession?.user.id.uuidString {
                await SubscriptionService.shared.identify(userId: userId)
            }
            AnalyticsService.shared.track(.signUpCompleted, properties: ["method": "email"])
        } catch HealthMapError.auth(.invalidEmailCode) {
            // A1 : message clair (pas un crash report Sentry — c'est une faute
            // de frappe utilisateur, signal/bruit). On ne reset PAS le throttle
            // resend ici : la 1re erreur est une simple typo, l'user peut juste
            // re-saisir le code reçu sans en demander un nouveau.
            errorMessage = HealthMapError.auth(.invalidEmailCode).errorDescription
        } catch HealthMapError.auth(.emailCodeExpired) {
            // A1 : code expiré → message + l'UI doit afficher le bouton
            // "Renvoyer le code". Pas de tracking erreur : c'est une situation
            // attendue (user qui revient le lendemain).
            errorMessage = HealthMapError.auth(.emailCodeExpired).errorDescription
        } catch HealthMapError.auth(.sessionExpired) {
            // B7 : le signUp Clerk a été recyclé (app fermée trop longtemps).
            // On clear `pendingEmailVerification` pour re-router l'user vers
            // le formulaire signup classique au lieu de le laisser bloqué sur
            // un sheet où aucun code ne marchera plus jamais.
            pendingEmailVerification = false
            resendAttempts = 0
            errorMessage = "Ta session d'inscription a expiré. Recommence l'inscription."
        } catch {
            errorMessage = Self.mapAuthError(error)
        }
        isProcessing = false
    }

    // MARK: - Sign Out

    func signOut() async {
        isProcessing = true
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

        // Cross-user state hygiene: clear every per-flow flag that the
        // previous user's auth journey may have left behind. Without this,
        // user B opening the app right after user A signed out would see
        // stale state (e.g. EmailCodeVerificationSheet auto-presenting,
        // resendResetPasswordCode silently sending to user A's email).
        self.pendingEmailVerification = false
        self.resetPasswordEmail = nil
        self.resendAttempts = 0
        self.pendingAppleNonce = nil
        self.errorMessage = nil

        clearLocalCaches()
        GamificationService.shared.reset()
        AnalyticsService.shared.reset()
        await SubscriptionService.shared.reset()
        // Cancel any in-flight push-token Supabase write so the token
        // doesn't get persisted onto the just-signed-out user's row.
        PushNotificationService.shared.cancelInFlightTokenSave()
        // The local LoginThrottle is per-device, not per-user — but a
        // successful sign-in already resets it (line 230) and a sign-out
        // is by definition not an attack surface, so clearing the
        // counter on sign-out unblocks user B from inheriting user A's
        // throttle state.
        LoginThrottleService.shared.reset()
        // Note: .signOutCompleted is tracked by the auth listener's .signedOut
        // handler, not here — avoids double-counting in analytics.

        isProcessing = false
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
        isProcessing = true
        errorMessage = nil

        do {
            try await AuthService.shared.deleteAccount()
            isProcessing = false
            return true
        } catch {
            AppLogger.auth.report(error, context: "AuthViewModel deleteAccount")
            errorMessage = "Erreur lors de la suppression du compte. Reessayez ou contactez le support."
            isProcessing = false
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

        isProcessing = true
        errorMessage = nil

        do {
            try await AuthService.shared.resetPassword(email: email)
            // A3 : on garde l'email pour pouvoir auto-redéclencher si la
            // session Clerk meurt avant que l'user n'entre le code.
            resetPasswordEmail = email
            resendAttempts = 0
            AnalyticsService.shared.track(.passwordResetRequested, properties: ["method": "email"])
            isProcessing = false
            return true
        } catch {
            errorMessage = Self.mapAuthError(error)
            isProcessing = false
            return false
        }
    }

    /// Étape 2 du reset : valide le code à 6 chiffres reçu par email + pose le nouveau mot de passe.
    /// Clerk n'expose pas de magic-link reset — c'est obligatoirement code + new password.
    func completeResetPassword(code: String, newPassword: String) async -> Bool {
        guard !code.isEmpty else {
            errorMessage = "Veuillez saisir le code reçu par email."
            return false
        }
        let validationIssues = PasswordValidator.validate(newPassword)
        if !validationIssues.isEmpty {
            errorMessage = validationIssues.map(\.message).joined(separator: "\n")
            return false
        }

        isProcessing = true
        errorMessage = nil

        do {
            try await AuthService.shared.completeResetPassword(code: code, newPassword: newPassword)
            // Succès : on nettoie l'état intermédiaire.
            resetPasswordEmail = nil
            resendAttempts = 0

            // Clerk auto-signs the user in once `signIn.resetPassword` succeeds
            // (Status becomes `.complete`, `Clerk.shared.session` is posted).
            // The auth-state listener should pick this up and flip
            // `isAuthenticated = true`, but on slow networks (or if the listener
            // hasn't drained yet) the user lands back on AuthView with empty
            // fields and is then rejected by Clerk's `session_exists` 400 when
            // they try to manually sign in. Force a session pull here so the
            // VM publishes the new state synchronously before the success
            // sheet auto-dismisses.
            let fresh = await AuthService.shared.currentSession
            self.session = fresh
            self.user = fresh?.user
            self.isAuthenticated = fresh != nil

            isProcessing = false
            return true
        } catch HealthMapError.auth(.sessionExpired) where resetPasswordEmail != nil {
            // A3 : la session Clerk de reset a expiré (app fermée trop longtemps,
            // ou Clerk a recyclé l'objet signIn). Au lieu de jeter "Session
            // expirée" et obliger l'user à recommencer depuis l'écran email,
            // on relance discrètement l'étape 1 avec l'email mémorisé et on
            // demande à l'user d'utiliser le NOUVEAU code (l'ancien ne marche
            // plus de toute façon).
            do {
                try await AuthService.shared.resetPassword(email: resetPasswordEmail!)
                errorMessage = "Le code précédent a expiré, un nouveau a été envoyé à \(resetPasswordEmail!). Saisis-le ci-dessous."
            } catch {
                errorMessage = "Le code a expiré et le renvoi a échoué. Recommence depuis l'écran email."
                resetPasswordEmail = nil
            }
            isProcessing = false
            return false
        } catch {
            errorMessage = Self.mapAuthError(error)
            isProcessing = false
            return false
        }
    }

    /// Renvoie un nouveau code de reset password à l'email mémorisé.
    /// À appeler depuis le bouton "Renvoyer le code" dans ForgotPasswordSheet.
    /// Plafond `maxResendAttempts` (3) pour éviter le spam — au-delà, message
    /// d'erreur clair invitant à patienter.
    func resendResetPasswordCode() async -> Bool {
        guard let email = resetPasswordEmail else {
            errorMessage = "Aucun reset en cours. Recommence depuis l'écran email."
            return false
        }
        guard resendAttempts < Self.maxResendAttempts else {
            errorMessage = HealthMapError.auth(.tooManyResendAttempts).errorDescription
            return false
        }
        isProcessing = true
        errorMessage = nil
        do {
            try await AuthService.shared.resetPassword(email: email)
            resendAttempts += 1
            isProcessing = false
            return true
        } catch {
            errorMessage = Self.mapAuthError(error)
            isProcessing = false
            return false
        }
    }

    /// Renvoie un nouveau code email pour un signup en cours (pendingEmailVerification == true).
    /// À appeler depuis le bouton "Renvoyer le code" dans EmailCodeVerificationSheet.
    func resendSignUpCode() async -> Bool {
        guard pendingEmailVerification else {
            errorMessage = "Aucune inscription en cours."
            return false
        }
        guard resendAttempts < Self.maxResendAttempts else {
            errorMessage = HealthMapError.auth(.tooManyResendAttempts).errorDescription
            return false
        }
        isProcessing = true
        errorMessage = nil
        do {
            try await AuthService.shared.resendSignUpEmailCode()
            resendAttempts += 1
            isProcessing = false
            return true
        } catch {
            errorMessage = Self.mapAuthError(error)
            isProcessing = false
            return false
        }
    }

    // MARK: - Sign In with Google (Clerk gère l'ASWebAuthenticationSession en interne)

    func signInWithGoogle() async {
        isProcessing = true
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

        isProcessing = false
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
        isProcessing = true
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

        isProcessing = false
    }

    // MARK: - Password Strength (for UI binding)

    /// Returns the strength of a password for real-time UI feedback.
    func passwordStrength(_ password: String) -> PasswordStrength {
        PasswordValidator.strength(of: password)
    }

    // MARK: - Error Mapping

    /// B2 — mapping exhaustif des erreurs auth en messages français lisibles.
    ///
    /// Stratégie en 3 couches :
    ///   1. Si l'erreur est déjà un `HealthMapError`, on prend son
    ///      `errorDescription` localisé (déjà en français).
    ///   2. Si c'est une `ClerkAPIError` ou similaire, on matche sur le `.code`
    ///      string (stable across SDK versions) plutôt que sur le message
    ///      anglais qui peut changer.
    ///   3. Fallback : message générique français + log Sentry du code original
    ///      pour pouvoir étendre le mapping si on observe un code récurrent.
    ///
    /// Codes Clerk de référence (cf. https://clerk.com/docs/errors) :
    ///   form_identifier_exists, form_identifier_not_found,
    ///   form_password_incorrect, form_password_pwned, form_password_validation_failed,
    ///   form_param_format_invalid, form_param_nil, form_code_incorrect,
    ///   form_code_expired, verification_expired, verification_failed,
    ///   session_token_expired, client_state_invalid, too_many_requests,
    ///   captcha_invalid, oauth_access_denied, oauth_callback_invalid.
    private static func mapAuthError(_ error: Error) -> String {
        // Couche 1 : HealthMapError déjà français
        if let hm = error as? HealthMapError, let desc = hm.errorDescription {
            return desc
        }

        // Couche 2 : pattern-match sur les codes Clerk via le bas du message.
        // On cherche le code dans deux formes possibles :
        //   - `(code: "form_identifier_exists")` (description par défaut)
        //   - `code: form_identifier_exists` (variante)
        let raw = error.localizedDescription
        let lower = raw.lowercased()

        let codeMatchers: [(needles: [String], message: String)] = [
            (["form_identifier_exists", "already registered", "already_exists",
              "that email address is taken"],
             "Un compte existe déjà avec cet email."),
            (["form_identifier_not_found", "user not found", "couldn't find your account"],
             "Aucun compte trouvé avec cet email."),
            (["form_password_incorrect", "invalid login", "invalid_credentials",
              "incorrect password"],
             "Email ou mot de passe incorrect."),
            (["form_password_pwned",
              "online data breach",
              "data breach",
              "use a different password"],
             "Ce mot de passe figure dans une fuite de données connue. Choisis-en un autre."),
            (["form_password_validation_failed", "password_too_short", "weak password"],
             "Le mot de passe ne respecte pas les règles (8 caractères min, majuscule, chiffre, spécial)."),
            (["form_code_incorrect", "verification_failed"],
             "Code incorrect. Vérifie tes mails et réessaie."),
            (["form_code_expired", "verification_expired"],
             "Ce code a expiré. Demande un nouveau code."),
            (["session_token_expired", "session_expired"],
             "Ta session a expiré. Reconnecte-toi."),
            (["session_exists", "you're already signed in", "already signed in"],
             "Tu es déjà connecté. Patiente un instant…"),
            (["client_state_invalid"],
             "État invalide. Recommence depuis l'écran de connexion."),
            (["too_many_requests", "rate limit"],
             "Trop de tentatives. Réessaie dans quelques minutes."),
            (["captcha_invalid", "captcha_failed"],
             "Vérification anti-bot échouée. Réessaie."),
            (["oauth_access_denied", "oauth_callback"],
             "Connexion sociale annulée ou refusée."),
            (["email not confirmed"],
             "Vérifie ton email pour activer ton compte."),
            (["network", "timeout", "could not connect"],
             "Erreur réseau. Vérifie ta connexion et réessaie."),
        ]

        for matcher in codeMatchers {
            if matcher.needles.contains(where: { lower.contains($0) }) {
                return matcher.message
            }
        }

        // Couche 3 : fallback. On log le message brut côté télémétrie pour
        // pouvoir enrichir le mapping si un nouveau code apparaît, mais on
        // n'expose JAMAIS la description anglaise à l'utilisateur — confusion.
        AppLogger.auth.notice("Unmapped auth error: \(raw, privacy: .public)")
        return "Une erreur d'authentification est survenue. Réessaie."
    }
}

