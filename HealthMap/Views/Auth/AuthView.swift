import SwiftUI
import AuthenticationServices

// MARK: - Authentication View (Login / Signup)
struct AuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var isSignUp = false
    @State private var showForgotPassword = false

    /// Held across the async Sign in with Apple round-trip so we can pass
    /// the **raw** nonce to Supabase once Apple returns the identity token.
    @State private var currentAppleNonce: AppleSignInNonce.Pair?

    /// True between the moment Apple's sheet closes and the moment Supabase
    /// finishes exchanging the identity token. Drives a blocking overlay so
    /// the user gets feedback during the ~500-2000ms round-trip.
    @State private var isExchangingAppleToken = false

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case firstName, email, password
    }

    var body: some View {
        ZStack {
            Color.healthMapBackground
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
                                Button("Mot de passe oublie ?") {
                                    showForgotPassword = true
                                }
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.healthMapBlue)
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
                        .foregroundStyle(.red)
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
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .opacity(authViewModel.isLoading ? 0 : 1)

                            if authViewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.healthMapBlue)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    }
                    .disabled(authViewModel.isLoading)
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
                            currentAppleNonce = pair
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
                                .font(.system(size: 16, weight: .medium))
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
                    .padding(.horizontal, Theme.spacingLG)

                    // Toggle login/signup
                    HStack(spacing: 4) {
                        Text(isSignUp ? "Deja un compte ?" : "Pas encore de compte ?")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapSecondary)
                        Button(isSignUp ? "Se connecter" : "Creer un compte") {
                            withAnimation(.healthMapSpring) {
                                isSignUp.toggle()
                                authViewModel.errorMessage = nil
                            }
                        }
                        .font(Theme.captionBoldFont)
                        .foregroundStyle(Color.healthMapBlue)
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
        .animation(.healthMapSpring, value: isSignUp)
        .animation(.healthMapSpring, value: authViewModel.errorMessage)
        .animation(.easeInOut(duration: 0.2), value: isExchangingAppleToken)
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
                let nonce = currentAppleNonce
            else {
                authViewModel.errorMessage = "Apple n'a pas renvoye de token. Reessaie."
                return
            }

            let appleFirstName = credential.fullName?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let appleEmail = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines)

            currentAppleNonce = nil
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
    private var headerSection: some View {
        VStack(spacing: Theme.spacingSM) {
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(Color.healthMapBlue)

            Text("HealthMap")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color.healthMapText)

            Text(isSignUp ? "Cree ton compte gratuit" : "Content de te revoir")
                .font(Theme.subheadlineFont)
                .foregroundStyle(Color.healthMapSecondary)
        }
    }
}

// MARK: - Make Field conform to Hashable through the extension
extension AuthView.Field: Sendable {}

#Preview {
    AuthView()
        .environmentObject(AuthViewModel())
}
