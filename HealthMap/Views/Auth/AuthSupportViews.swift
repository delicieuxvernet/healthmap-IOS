import SwiftUI

// MARK: - Auth Text Field
struct AuthTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    let contentType: UITextContentType
    let keyboardType: UIKeyboardType
    var focused: FocusState<AuthView.Field?>.Binding
    let field: AuthView.Field

    var body: some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.healthMapMuted)
                .frame(width: 24)

            TextField(placeholder, text: $text)
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused(focused, equals: field)
        }
        .padding(.horizontal, Theme.spacingMD)
        .frame(height: 50)
        .background(Color.healthMapBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
    }
}

// MARK: - Auth Secure Field
struct AuthSecureField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    let contentType: UITextContentType
    var focused: FocusState<AuthView.Field?>.Binding
    let field: AuthView.Field
    @State private var showPassword = false

    var body: some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.healthMapMuted)
                .frame(width: 24)

            Group {
                if showPassword {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textContentType(contentType)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused(focused, equals: field)

            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .padding(.horizontal, Theme.spacingMD)
        .frame(height: 50)
        .background(Color.healthMapBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
    }
}

// MARK: - Forgot Password Sheet
//
// Flow Clerk en 2 étapes :
//   1. email -> Clerk envoie un code à 6 chiffres par mail
//   2. user entre le code + son nouveau mot de passe -> session active
struct ForgotPasswordSheet: View {
    enum Step { case email, codeAndPassword, success }
    private enum Field: Hashable { case code, newPassword, confirmPassword }

    @FocusState private var focusedField: Field?

    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var step: Step = .email

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacingLG) {
                    switch step {
                    case .email:
                        emailStep
                    case .codeAndPassword:
                        codeStep
                    case .success:
                        successStep
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.bottom, Theme.spacingXL)
            }
            .navigationTitle("Mot de passe oublie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Color.healthMapBlue)
                }
            }
            .onChange(of: step) { _, newStep in
                if newStep == .codeAndPassword {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        focusedField = .code
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emailStep: some View {
        Text("Entre ton adresse email pour recevoir un code de reinitialisation.")
            .font(Theme.bodyFont)
            .foregroundStyle(Color.healthMapSecondary)
            .multilineTextAlignment(.center)
            .padding(.top, Theme.spacingMD)

        TextField("Email", text: $email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, Theme.spacingMD)
            .frame(height: 50)
            .background(Color.healthMapBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))

        if let err = authVM.errorMessage {
            Text(err)
                .font(Theme.captionFont)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }

        Button {
            Task {
                HapticService.shared.primary()
                let ok = await authVM.resetPassword(email: email)
                if ok {
                    withAnimation(.healthMapSpring) { step = .codeAndPassword }
                } else {
                    HapticService.shared.warning()
                }
            }
        } label: {
            HStack {
                if authVM.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Envoyer le code")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.healthMapBlue)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .disabled(email.isEmpty || authVM.isLoading)
    }

    @ViewBuilder
    private var codeStep: some View {
        Text("Un code à 6 chiffres a ete envoye à \(email). Verifie tes mails (et les spams).")
            .font(Theme.bodyFont)
            .foregroundStyle(Color.healthMapSecondary)
            .multilineTextAlignment(.center)
            .padding(.top, Theme.spacingMD)

        TextField("Code à 6 chiffres", text: $code)
            .textContentType(.oneTimeCode)
            .keyboardType(.numberPad)
            .focused($focusedField, equals: .code)
            .padding(.horizontal, Theme.spacingMD)
            .frame(minHeight: 50)
            .background(Color.healthMapBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))

        SecureField("Nouveau mot de passe", text: $newPassword)
            .textContentType(.newPassword)
            .focused($focusedField, equals: .newPassword)
            .padding(.horizontal, Theme.spacingMD)
            .frame(minHeight: 50)
            .background(Color.healthMapBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))

        SecureField("Confirme le mot de passe", text: $confirmPassword)
            .textContentType(.newPassword)
            .focused($focusedField, equals: .confirmPassword)
            .padding(.horizontal, Theme.spacingMD)
            .frame(minHeight: 50)
            .background(Color.healthMapBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))

        // Live password validation issues
        if !newPassword.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(PasswordValidator.validate(newPassword), id: \.self) { issue in
                    Label(issue.message, systemImage: "xmark.circle.fill")
                        .font(Theme.captionFont)
                        .foregroundStyle(.red)
                }
                if !confirmPassword.isEmpty && confirmPassword != newPassword {
                    Label("Les deux mots de passe ne correspondent pas.", systemImage: "xmark.circle.fill")
                        .font(Theme.captionFont)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let err = authVM.errorMessage {
            Text(err)
                .font(Theme.captionFont)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }

        Button {
            Task {
                HapticService.shared.primary()
                let ok = await authVM.completeResetPassword(code: code, newPassword: newPassword)
                if ok {
                    withAnimation(.healthMapSpring) { step = .success }
                } else {
                    HapticService.shared.warning()
                }
            }
        } label: {
            HStack {
                if authVM.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Reinitialiser le mot de passe")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background(Color.healthMapBlue)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .disabled(!canSubmitReset || authVM.isLoading)

        Button {
            Task {
                HapticService.shared.selection()
                _ = await authVM.resendResetPasswordCode()
            }
        } label: {
            Text("Renvoyer le code")
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapBlue)
                .frame(minHeight: 44)
        }
        .disabled(authVM.isLoading)
    }

    /// True when code is exactly 6 digits, password meets PasswordValidator,
    /// and confirm matches. C2 : `==` au lieu de `>=` pour éviter qu'un
    /// copier-coller accidentel de 7+ chiffres bloque le submit silencieusement
    /// (le filtre numberPad cap déjà à 6 mais belt-and-braces).
    private var canSubmitReset: Bool {
        code.count == 6
            && PasswordValidator.validate(newPassword).isEmpty
            && newPassword == confirmPassword
    }

    @ViewBuilder
    private var successStep: some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.scoreGood)
            Text("Mot de passe reinitialise !")
                .font(Theme.headlineFont)
            Text("Tu peux maintenant te connecter avec ton nouveau mot de passe.")
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.spacingXL)
        .onAppear { HapticService.shared.success() }
    }
}

// MARK: - Email Code Verification Sheet (Clerk signup step 2)
//
// Présenté automatiquement après `AuthViewModel.signUp()` quand Clerk a envoyé
// un code à 6 chiffres par email. L'user entre son code, on appelle
// `verifySignUpCode()` qui bascule Clerk en `.complete` et pose la session.
// Ne PAS exposer de dismiss manuel tant que le code n'est pas validé : sinon
// l'user pourrait fermer le sheet et se retrouver dans un état "compte créé
// mais pas de session active" — confus et irrécupérable côté UI.
struct EmailCodeVerificationSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    let email: String
    @State private var code = ""
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacingLG) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.healthMapBlue)
                    .padding(.top, Theme.spacingXL)

                Text("Verifie ton email")
                    .font(Theme.headlineFont)

                Text("On t'a envoye un code a 6 chiffres sur \(email). Saisis-le ci-dessous pour finaliser ton compte.")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacingMD)

                TextField("Code a 6 chiffres", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacingMD)
                    .frame(height: 60)
                    .background(Color.healthMapBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
                    .focused($isCodeFocused)
                    .onChange(of: code) { _, newValue in
                        // Cap à 6 chiffres, strip tout ce qui n'est pas numérique.
                        let digits = newValue.filter(\.isNumber)
                        if digits != newValue || digits.count > 6 {
                            code = String(digits.prefix(6))
                        }
                    }

                if let err = authVM.errorMessage {
                    Text(err)
                        .font(Theme.captionFont)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        HapticService.shared.primary()
                        await authVM.verifySignUpCode(code)
                        if authVM.errorMessage != nil {
                            HapticService.shared.warning()
                        }
                    }
                } label: {
                    HStack {
                        if authVM.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Valider")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.healthMapBlue)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                .disabled(code.count != 6 || authVM.isLoading)

                // B1 : bouton "Renvoyer le code" — utile si l'user a raté l'email,
                // s'il a expiré, ou s'il est tombé en spam. Plafonné à 3 envois
                // côté ViewModel pour éviter le spam (resendAttempts).
                Button {
                    Task {
                        HapticService.shared.selection()
                        let ok = await authVM.resendSignUpCode()
                        if ok {
                            // Reset le champ + refocus pour que l'user puisse
                            // saisir le nouveau code immédiatement.
                            code = ""
                            isCodeFocused = true
                        }
                    }
                } label: {
                    Text("Renvoyer le code")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapBlue)
                        .frame(minHeight: 44)
                }
                .disabled(authVM.isLoading)

                Spacer()
            }
            .padding(.horizontal, Theme.spacingLG)
            .navigationTitle("Verification email")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
            .onAppear {
                isCodeFocused = true
            }
        }
    }
}
