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
            Color.kiwiCream
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
                                placeholder: "Prenom",
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
                                    Text("Mot de passe oublie ?")
                                        .font(Theme.captionBoldFont)
                                        .foregroundStyle(Color.kiwiGreenInk)
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.healthMapPressed)
                            }
                        }
                    }
                    .padding(Theme.spacingLG)
                    .cardStyle()
                    .padding(.horizontal, Theme.spacingLG)

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
                            Text(isSignUp ? "Creer mon compte" : "Se connecter")
                                .font(Theme.headlineFont)
                                .foregroundStyle(.white)
                                .opacity(authViewModel.isProcessing ? 0 : 1)

                            if authViewModel.isProcessing {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.kiwiGreen)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .shadow(color: Color.kiwiGreen.opacity(0.34), radius: 13, x: 0, y: 10)
                    }
                    .buttonStyle(.healthMapPressed)
                    .disabled(authViewModel.isProcessing)
                    .padding(.horizontal, Theme.spacingLG)

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(Color.healthMapMuted.opacity(0.3))
                            .frame(height: 1)
                        Text("ou")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapMuted)
                        Rectangle()
                            .fill(Color.healthMapMuted.opacity(0.3))
                            .frame(height: 1)
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
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .padding(.horizontal, Theme.spacingLG)

                    // Google sign in
                    Button {
                        Task {
                            await authViewModel.signInWithGoogle()
                        }
                    } label: {
                        HStack(spacing: Theme.spacingSM) {
                            Image(systemName: "globe")
                                .font(.system(size: 18))
                            Text("Continuer avec Google")
                                .font(Theme.headlineFont)
                        }
                        .foregroundStyle(Color.healthMapText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.healthMapCard)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .stroke(Color.healthMapMuted.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.healthMapPressed)
                    .padding(.horizontal, Theme.spacingLG)

                    // Toggle login/signup — typo subheadline (lisible) +
                    // zone de tap >= 44pt sur le bouton.
                    HStack(spacing: Theme.spacingXS) {
                        Text(isSignUp ? "Deja un compte ?" : "Pas encore de compte ?")
                            .font(Theme.subheadlineFont)
                            .foregroundStyle(Color.healthMapSecondary)
                        // frame+contentShape DANS le label (zone tappable 44pt
                        // réelle — voir bouton « Mot de passe oublié ? »).
                        Button {
                            withAnimation(reduceMotion ? .none : .healthMapSpring) {
                                isSignUp.toggle()
                                authViewModel.errorMessage = nil
                            }
                        } label: {
                            Text(isSignUp ? "Se connecter" : "Creer un compte")
                                .font(Theme.subheadlineFont.weight(.semibold))
                                .foregroundStyle(Color.kiwiGreenInk)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.healthMapPressed)
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
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                    Text("Connexion a Apple...")
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
                authViewModel.errorMessage = "Apple n'a pas renvoye de token. Reessaie."
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

            (Text("kiwi").foregroundStyle(Color.kiwiCharcoal)
             + Text("o").foregroundStyle(Color.kiwiGreen))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .brandTitleKerning()

            Text(isSignUp
                 ? "Gratuit — ton bilan nutritionnel t'attend."
                 : "Connecte-toi pour retrouver ton bilan.")
                .font(Theme.subheadlineFont)
                .foregroundStyle(Color.healthMapSecondary)
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
