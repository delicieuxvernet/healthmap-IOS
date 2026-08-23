import SwiftUI
import AuthenticationServices

// MARK: - Authentication View (Login / Signup)
/// Formulaire d'authentification. Présenté en SHEET depuis `LandingView`
/// (mode piloté par `initialMode`), mais reste utilisable plein écran :
/// `AuthView()` sans argument est rétro-compatible (mode connexion).
struct AuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var isSignUp: Bool
    @State private var showForgotPassword = false

    // A4 : le nonce Apple est désormais détenu par AuthViewModel
    // (`authViewModel.pendingAppleNonce`) pour survivre aux rebuilds de view
    // pendant le round-trip async avec Apple. Ce @State local est retiré.

    /// True between the moment Apple's sheet closes and the moment Supabase
    /// finishes exchanging the identity token. Drives a blocking overlay so
    /// the user gets feedback during the ~500-2000ms round-trip.
    @State private var isExchangingAppleToken = false

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case firstName, email, password
    }

    /// Mode d'ouverture du formulaire. `Identifiable` pour pouvoir piloter
    /// un `.sheet(item:)` depuis LandingView.
    enum Mode: String, Identifiable {
        case signIn
        case signUp

        var id: String { rawValue }
    }

    /// `initialMode` ne fixe que l'état INITIAL (l'utilisateur peut toujours
    /// basculer via le toggle en bas). Valeur par défaut `.signIn` →
    /// rétro-compatible avec les call-sites existants `AuthView()`.
    init(initialMode: Mode = .signIn) {
        _isSignUp = State(initialValue: initialMode == .signUp)
    }

    var body: some View {
        ZStack {
            Color.dsFond
                .ignoresSafeArea()
                .onTapGesture { focusedField = nil }

            ScrollView {
                VStack(spacing: Theme.spacingLG) {
                    // Header
                    headerSection
                        .padding(.top, Theme.spacingXL)

                    // Form card
                    VStack(spacing: Theme.spacingMD) {
                        // First name (signup only)
                        if isSignUp {
                            AuthTextField(
                                icon: "person.fill",
                                placeholder: "Prénom",
                                text: $firstName,
                                contentType: .givenName,
                                keyboardType: .default,
                                focused: $focusedField,
                                field: .firstName
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Email
                        AuthTextField(
                            icon: "envelope.fill",
                            placeholder: "Email",
                            text: $email,
                            contentType: .emailAddress,
                            keyboardType: .emailAddress,
                            focused: $focusedField,
                            field: .email
                        )

                        // Password
                        AuthSecureField(
                            icon: "lock.fill",
                            placeholder: "Mot de passe",
                            text: $password,
                            contentType: isSignUp ? .newPassword : .password,
                            focused: $focusedField,
                            field: .password
                        )

                        // Forgot password
                        if !isSignUp {
                            HStack {
                                Spacer()
                                // frame+contentShape DANS le label : posés sur le
                                // Button ils n'étendraient pas la zone tappable
                                // (le hit-test resterait sur le texte, < 44pt HIG).
                                Button {
                                    showForgotPassword = true
                                } label: {
                                    Text("Mot de passe oublié\u{202F}?")
                                        .font(.dsLegendeMoyenne)
                                        .foregroundStyle(Color.dsAccent)
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.dsPress)
                            }
                        }
                    }
                    .padding(DS.paddingCarte)
                    .dsCard()
                    .padding(.horizontal, DS.marge)

                    // Error message
                    if let error = authViewModel.errorMessage {
                        HStack(spacing: Theme.spacingSM) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text(error)
                                .font(Theme.captionFont)
                        }
                        .foregroundStyle(Color.urgencyImmediate)
                        .padding(.horizontal, Theme.spacingLG)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Primary action button
                    Button {
                        focusedField = nil
                        Task {
                            if isSignUp {
                                await authViewModel.signUp(email: email, password: password, firstName: firstName)
                            } else {
                                await authViewModel.signIn(email: email, password: password)
                            }
                        }
                    } label: {
                        ZStack {
                            Text(isSignUp ? "Créer mon compte" : "Se connecter")
                                .font(.dsHeadline)
                                .tracking(DSTracking.corps)
                                .foregroundStyle(.white)
                                .opacity(authViewModel.isProcessing ? 0 : 1)

                            if authViewModel.isProcessing {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.hauteurBouton)
                        .background(Capsule().fill(Color.dsAccent))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.dsPress)
                    .disabled(authViewModel.isProcessing)
                    .padding(.horizontal, DS.marge)

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(Color.dsSeparateur)
                            .frame(height: 0.5)
                        Text("ou")
                            .font(.dsLegende)
                            .foregroundStyle(Color.dsSecondaire)
                        Rectangle()
                            .fill(Color.dsSeparateur)
                            .frame(height: 0.5)
                    }
                    .padding(.horizontal, Theme.spacingXL)

                    // Apple sign in (required by App Store guideline 4.8 whenever
                    // another third-party provider like Google is offered).
                    SignInWithAppleButton(
                        isSignUp ? .signUp : .signIn,
                        onRequest: { request in
                            let pair = AppleSignInNonce.make()
                            authViewModel.pendingAppleNonce = pair
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = pair.hashed
                        },
                        onCompletion: { result in
                            handleAppleSignInResult(result)
                        }
                    )
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: DS.hauteurBouton)
                    .clipShape(Capsule())
                    .padding(.horizontal, DS.marge)

                    // Google sign in
                    Button {
                        Task {
                            await authViewModel.signInWithGoogle()
                        }
                    } label: {
                        HStack(spacing: Theme.spacingSM) {
                            Image(systemName: "globe")
                                .font(.system(size: 18, weight: .medium))
                            Text("Continuer avec Google")
                                .font(.dsHeadline)
                                .tracking(DSTracking.corps)
                        }
                        .foregroundStyle(Color.dsTexte)
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.hauteurBouton)
                        .background(Capsule().fill(Color.dsCarte))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.dsPress)
                    .padding(.horizontal, DS.marge)

                    // Toggle login/signup — typo subheadline (lisible) +
                    // zone de tap >= 44pt sur le bouton.
                    HStack(spacing: Theme.spacingXS) {
                        Text(isSignUp ? "Déjà un compte\u{202F}?" : "Pas encore de compte\u{202F}?")
                            .font(.dsSousTitre)
                            .foregroundStyle(Color.dsSecondaire)
                        // frame+contentShape DANS le label (zone tappable 44pt
                        // réelle — voir bouton « Mot de passe oublié ? »).
                        Button {
                            withAnimation(reduceMotion ? .none : .healthMapSpring) {
                                isSignUp.toggle()
                                authViewModel.errorMessage = nil
                            }
                        } label: {
                            Text(isSignUp ? "Se connecter" : "Créer un compte")
                                .font(.dsSousTitreFort)
                                .foregroundStyle(Color.dsAccent)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.dsPress)
                    }
                    .padding(.bottom, Theme.spacingXL)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            // Blocking loader while we exchange Apple's identity token
            if isExchangingAppleToken {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: Theme.spacingMD) {
                    KiwiLoader(size: 56, color: .white)
                    Text("Connexion à Apple...")
                        .font(Theme.subheadlineFont)
                        .foregroundStyle(.white)
                }
                .padding(.vertical, Theme.spacingLG)
                .padding(.horizontal, Theme.spacingXL)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.6))
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(reduceMotion ? .none : .healthMapSpring, value: isSignUp)
        .animation(reduceMotion ? .none : .healthMapSpring, value: authViewModel.errorMessage)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: isExchangingAppleToken)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet()
                .healthMapActionSheet()
        }
        // Depuis la migration Clerk (20 avril 2026), le signup email est en 2
        // étapes : `signUp()` envoie un code, puis `pendingEmailVerification`
        // bascule à true et on présente `EmailCodeVerificationSheet` pour saisir
        // le code à 6 chiffres. Sans ce sheet, l'user serait stuck après le
        // signup car la session n'est posée qu'à la validation du code.
        .sheet(isPresented: Binding(
            get: { authViewModel.pendingEmailVerification },
            set: { newValue in
                if !newValue { authViewModel.pendingEmailVerification = false }
            }
        )) {
            EmailCodeVerificationSheet(email: email)
                .healthMapActionSheet()
        }
    }

    // MARK: - Sign in with Apple handler

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            AppLogger.auth.report(error, context: "SignInWithApple onCompletion")
            authViewModel.errorMessage = "Erreur de connexion avec Apple."

        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idTokenString = String(data: tokenData, encoding: .utf8),
                let nonce = authViewModel.pendingAppleNonce
            else {
                authViewModel.errorMessage = "Apple n'a pas renvoyé tes infos de connexion. Réessaie."
                authViewModel.pendingAppleNonce = nil
                return
            }

            let appleFirstName = credential.fullName?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let appleEmail = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines)

            authViewModel.pendingAppleNonce = nil
            isExchangingAppleToken = true

            Task {
                await authViewModel.signInWithApple(
                    idToken: idTokenString,
                    rawNonce: nonce.raw,
                    firstName: (appleFirstName?.isEmpty == false) ? appleFirstName : nil,
                    email: (appleEmail?.isEmpty == false) ? appleEmail : nil
                )
                isExchangingAppleToken = false
            }
        }
    }

    // MARK: - Header
    /// DA actuelle (crème + kiwi vert) : le VRAI logo de l'app (le kiwi 3D
    /// Fluent, celui de l'icône) + le wordmark « Kiwio ». L'ancien header
    /// (mascotte plate + titre bleu, dégradé indigo) jurait avec le reste de
    /// l'app — remplacé par le couple logo + nom, neutre et raccord. Un
    /// sous-titre discret rappelle l'action en cours (connexion vs inscription).
    private var headerSection: some View {
        VStack(spacing: Theme.spacingMD) {
            Image(Fluent3D.kiwi)
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)

            (Text("kiwi").foregroundStyle(Color.dsTexte)
             + Text("o").foregroundStyle(Color.dsAccent))
                .font(.dsGrandTitre)
                .tracking(DSTracking.grandTitre)

            Text(isSignUp
                 ? "Gratuit\u{202F}: ton bilan nutritionnel t'attend."
                 : "Connecte-toi pour retrouver ton bilan.")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Make Field conform to Hashable through the extension
extension AuthView.Field: Sendable {}

#Preview("Connexion") {
    AuthView()
        .environmentObject(AuthViewModel())
}

#Preview("Inscription") {
    AuthView(initialMode: .signUp)
        .environmentObject(AuthViewModel())
}
