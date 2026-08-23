import SwiftUI

// MARK: - Landing View (page de garde non connecté)
/// Page de garde affichée à tout utilisateur NON connecté. Design « anneau
/// nutritionnel » (validé par Arthur, 5 juillet) : fond crème, wordmark en
/// haut, motif signature (anneau vert qui se remplit + leaf central + 4
/// pastilles nutriments flottantes couleur = sens), puis le pitch et les CTA.
/// L'auth s'ouvre en sheet via « C'est parti » (inscription) ou « J'ai déjà un
/// compte » (connexion).
///
/// - Reduce Motion → apparitions instantanées + aucune animation en boucle
///   (anneau posé rempli, pastilles fixes, pas de pulsation).
struct LandingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var ringProgress: CGFloat = 0
    @State private var floating = false

    /// Mode d'auth demandé — pilote le sheet (`nil` = pas de sheet).
    @State private var authMode: AuthView.Mode?

    // Couleurs du design (spec Arthur).
    private let cream = LinearGradient(
        colors: [Color(red: 0.984, green: 0.933, blue: 0.867),
                 Color(red: 0.984, green: 0.965, blue: 0.937),
                 Color(red: 0.992, green: 0.984, blue: 0.969)],
        startPoint: .top, endPoint: .bottom)
    private let kiwi = Color(red: 0.365, green: 0.659, blue: 0.220)      // #5DA838
    private let ink = Color(red: 0.129, green: 0.122, blue: 0.102)       // #211F1A
    private let greenDeep = Color(red: 0.231, green: 0.427, blue: 0.067) // #3B6D11
    private let greenSoft = Color(red: 0.918, green: 0.953, blue: 0.871) // #EAF3DE

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Wordmark en haut
                (Text("kiwi").foregroundStyle(ink) + Text("o").foregroundStyle(kiwi))
                    .font(.system(size: 24, weight: .bold))
                    .brandTitleKerning()
                    .padding(.top, Theme.spacingSM)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(staged(0), value: appeared)

                Spacer()

                heroMotif
                    .opacity(appeared ? 1 : 0)
                    .animation(staged(0.05), value: appeared)

                badge
                    .padding(.top, Theme.spacingMD)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(staged(0.12), value: appeared)

                Text("Découvre la cause de tes symptômes.")
                    .font(.system(size: 33, weight: .bold))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, Theme.spacingLG)
                    .padding(.top, Theme.spacingLG)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(staged(0.18), value: appeared)

                Text("Et reçois ton plan micro-nutrition sur mesure, en quelques minutes.")
                    .font(.system(size: 16.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacingXL)
                    .padding(.top, Theme.spacingMD)
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
        .onAppear {
            appeared = true
            floating = true
            withAnimation(reduceMotion ? nil : .timingCurve(0.3, 0.85, 0.3, 1, duration: 1.4).delay(0.3)) {
                ringProgress = 0.78
            }
        }
        .sheet(item: $authMode) { mode in
            AuthView(initialMode: mode)
                .healthMapFullSheet()
        }
    }

    // MARK: - Motif signature (anneau + pastilles)

    private var heroMotif: some View {
        ZStack {
            // Halo vert doux
            Circle()
                .fill(RadialGradient(colors: [kiwi.opacity(0.20), kiwi.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 90))
                .frame(width: 176, height: 176)
                .opacity(floating && !reduceMotion ? 0.85 : 0.5)
                .animation(reduceMotion ? nil : .easeInOut(duration: 3.6).repeatForever(autoreverses: true), value: floating)

            // Anneau + centre
            ZStack {
                Circle().stroke(kiwi.opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: reduceMotion ? 0.78 : ringProgress)
                    .stroke(kiwi, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(.white)
                    .frame(width: 56, height: 56)
                    .shadow(color: Color(red: 0.176, green: 0.353, blue: 0.078).opacity(0.14), radius: 8, x: 0, y: 6)
                    .overlay(Image(systemName: "leaf.fill").font(.system(size: 26)).foregroundStyle(kiwi))
                    .scaleEffect(floating && !reduceMotion ? 1.08 : 1.0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 3).repeatForever(autoreverses: true), value: floating)
            }
            .frame(width: 116, height: 116)

            // Pastilles nutriments aux 4 coins (couleur = sens)
            nutrientPill("Vitamine C", dot: kiwi, delay: 0).offset(x: -116, y: -82)
            nutrientPill("Fer", dot: Color(red: 1, green: 0.584, blue: 0), delay: 0.9).offset(x: 116, y: -82)
            nutrientPill("B12", dot: Color(red: 1, green: 0.231, blue: 0.188), delay: 1.8).offset(x: -120, y: 82)
            nutrientPill("Oméga-3", dot: Color(red: 0, green: 0.478, blue: 1), delay: 2.6).offset(x: 112, y: 82)
        }
        .frame(width: 358, height: 208)
        .accessibilityHidden(true)
    }

    private func nutrientPill(_ label: String, dot: Color, delay: Double) -> some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(label).font(.system(size: 12.5, weight: .bold)).foregroundStyle(ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.white).shadow(color: ink.opacity(0.10), radius: 8, x: 0, y: 6))
        .offset(y: floating && !reduceMotion ? -6 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 3.4).repeatForever(autoreverses: true).delay(delay), value: floating)
    }

    private var badge: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 14))
            Text("Bilan nutritionnel personnalisé").font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(greenDeep)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(greenSoft))
    }

    // MARK: - CTAs

    private var ctaSection: some View {
        VStack(spacing: Theme.spacingSM) {
            Button {
                authMode = .signUp
            } label: {
                HStack(spacing: Theme.spacingSM) {
                    Text("C'est parti")
                    Image(systemName: "arrow.right").font(.system(size: 17, weight: .semibold))
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(kiwi)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .shadow(color: kiwi.opacity(0.34), radius: 13, x: 0, y: 10)
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityHint("Ouvre la création de compte.")

            Button {
                authMode = .signIn
            } label: {
                Text("J'ai déjà un compte")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(greenDeep)
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
