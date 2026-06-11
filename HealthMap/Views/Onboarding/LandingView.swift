import SwiftUI

// MARK: - Landing View (page de garde non connecté)
/// Page de garde affichée à tout utilisateur NON connecté (après le carrousel
/// d'onboarding du tout premier lancement). L'utilisateur n'atterrit JAMAIS
/// directement sur un formulaire de connexion : il découvre la marque
/// (fond animé, mascotte kiwi, wordmark gradient), puis ouvre l'auth en sheet
/// via le CTA « C'est parti » (inscription) ou « J'ai déjà un compte »
/// (connexion).
///
/// - Reduce Motion → fond statique (géré par `AnimatedBackground`), mascotte
///   en pose statique (géré par `MascotView`), apparitions instantanées
///   (`staged()` renvoie `nil`).
/// - Quand l'auth réussit, `AuthViewModel.isAuthenticated` bascule :
///   `ContentView` remplace LandingView par MainTabView et le sheet est
///   automatiquement démonté avec sa vue de présentation.
struct LandingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Mode d'auth demandé — pilote le sheet (`nil` = pas de sheet).
    @State private var authMode: AuthView.Mode?

    var body: some View {
        ZStack {
            // Fond animé réutilisable (gradient statique si Reduce Motion)
            AnimatedBackground()

            VStack(spacing: Theme.spacingLG) {
                Spacer()

                // Badge (miroir du badge hero web)
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                    Text("Bilan nutritionnel personnalisé")
                }
                .pillStyle(color: .healthMapBlue)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(staged(0), value: appeared)

                // Mascotte kiwi — grande, joyeuse (décorative, déjà
                // accessibilityHidden dans MascotView)
                MascotView(mood: .happy, size: 150)
                    .shadow(color: .black.opacity(Theme.opacityLight),
                            radius: Theme.shadowElevated.radius,
                            x: 0,
                            y: Theme.shadowElevated.y)
                    .scaleEffect(appeared ? 1.0 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(staged(0.08), value: appeared)

                // Wordmark — « Map » en gradient brand, comme le logo du site
                (Text("Health").foregroundStyle(Color.healthMapText)
                 + Text("Map").foregroundStyle(LinearGradient.healthMapBrand))
                    .font(.system(.largeTitle, design: .rounded).weight(.black))
                    .brandTitleKerning()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(staged(0.16), value: appeared)

                // Baseline (copy du hero web)
                Text("Découvre la cause de tes symptômes et reçois ton plan micro-nutrition sur mesure.")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacingXL)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(staged(0.24), value: appeared)

                Spacer()

                ctaSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(staged(0.32), value: appeared)
            }
        }
        .onAppear { appeared = true }
        .sheet(item: $authMode) { mode in
            AuthView(initialMode: mode)
                .healthMapFullSheet()
        }
    }

    // MARK: - CTAs

    private var ctaSection: some View {
        VStack(spacing: Theme.spacingSM) {
            // CTA principal — gradient brand + ombre lumineuse (miroir du CTA web)
            Button {
                authMode = .signUp
            } label: {
                HStack(spacing: Theme.spacingSM) {
                    Text("C'est parti")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .font(Theme.headlineFont)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(LinearGradient.healthMapBrand)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .shadow(color: Color.healthMapBlue.opacity(Theme.shadowBrandGlow.opacity),
                        radius: Theme.shadowBrandGlow.radius,
                        x: 0,
                        y: Theme.shadowBrandGlow.y)
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityHint("Ouvre la création de compte.")

            // Secondaire discret — connexion à un compte existant
            Button {
                authMode = .signIn
            } label: {
                Text("J'ai déjà un compte")
                    .font(Theme.subheadlineFont)
                    .foregroundStyle(Color.healthMapBlue)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityHint("Ouvre la connexion avec un compte existant.")
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.bottom, Theme.spacingXL)
    }

    /// Apparition étagée — instantanée si Reduce Motion.
    private func staged(_ delay: Double) -> Animation? {
        reduceMotion ? nil : .healthMapSpring.delay(delay)
    }
}

#Preview {
    LandingView()
        .environmentObject(AuthViewModel())
}
