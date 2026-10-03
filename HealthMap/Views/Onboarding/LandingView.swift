import SwiftUI

// MARK: - Landing View (page de garde non connecté)
/// Page de garde affichée à tout utilisateur NON connecté. Design « anneau
/// nutritionnel » (validé par Arthur, 5 juillet) : la barre de l'app en haut
/// (signe Kiwio + nom, maquette « Identité »), motif signature (anneau vert
/// qui se remplit autour du signe + 4 pastilles nutriments flottantes couleur
/// = sens), puis le pitch et les CTA.
/// L'auth s'ouvre en sheet via « C'est parti » (inscription) ou « J'ai déjà un
/// compte » (connexion).
///
/// - Reduce Motion → apparitions instantanées + aucune animation en boucle
///   (anneau posé rempli, pastilles fixes, pas de pulsation).
///
/// Verre liquide (2 octobre 2026) : la page est posée sur le fond de verre
/// (teinte kiwi, celle d'un écran hors onglets). Les pastilles d'apports sont
/// des puces de verre clair, chacune avec la teinte de SA catégorie ;
/// « C'est parti » est le verre teinté vert, « J'ai déjà un compte » un bouton
/// de verre clair, et la feuille de connexion porte le verre de feuille.
struct LandingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var ringProgress: CGFloat = 0
    @State private var floating = false

    /// Mode d'auth demandé — pilote le sheet (`nil` = pas de sheet).
    @State private var authMode: AuthView.Mode?

    // Couleurs du DS : accent vert réservé à l'interactif et à l'anneau
    // signature ; le fond est le verre qui respire (`DSPageBackground`).
    private let kiwi = Color.dsAccent
    private let ink = Color.dsTexte

    var body: some View {
        ZStack {
            DSPageBackground()

            VStack(spacing: 0) {
                // La barre de l'app : le signe 26 pt et le nom (maquette « Identité »).
                KiwiLockupBarre()
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
                    .font(.dsGrandTitre)
                    .tracking(DSTracking.grandTitre)
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, Theme.spacingLG)
                    .padding(.top, Theme.spacingLG)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(staged(0.18), value: appeared)

                Text("Et reçois ton plan micro-nutrition sur mesure, en quelques minutes.")
                    .font(.dsCorps)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsSecondaire)
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
                .verreFeuille()
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
                Circle().stroke(Verre.pisteAnneau, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: reduceMotion ? 0.78 : ringProgress)
                    .stroke(kiwi, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                // Au centre de l'anneau, le signe Kiwio (un seul logo, partout).
                KiwiSigne(taille: 60)
                    .scaleEffect(floating && !reduceMotion ? 1.08 : 1.0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 3).repeatForever(autoreverses: true), value: floating)
            }
            .frame(width: 116, height: 116)

            // Pastilles nutriments aux 4 coins : une teinte par catégorie, celle
            // de la palette du verre (la même que dans le Journal et le Plan).
            nutrientPill("Vitamine C", dot: Color.teinteVitamineC, delay: 0).offset(x: -116, y: -82)
            nutrientPill("Fer", dot: Color.teinteFer, delay: 0.9).offset(x: 116, y: -82)
            nutrientPill("B12", dot: Color.teinteB12, delay: 1.8).offset(x: -120, y: 82)
            nutrientPill("Oméga-3", dot: Color.teinteOmega3, delay: 2.6).offset(x: 112, y: 82)
        }
        .frame(width: 358, height: 208)
        .accessibilityHidden(true)
    }

    private func nutrientPill(_ label: String, dot: Color, delay: Double) -> some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(label).font(.dsLegendeMoyenne).foregroundStyle(ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .verreClair()
        .offset(y: floating && !reduceMotion ? -6 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 3.4).repeatForever(autoreverses: true).delay(delay), value: floating)
    }

    private var badge: some View {
        Text("Bilan nutritionnel personnalisé")
            .font(.dsLegendeMoyenne)
            .foregroundStyle(Color.dsSecondaire)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.dsRemplissage))
    }

    // MARK: - CTAs

    private var ctaSection: some View {
        VStack(spacing: Theme.spacingSM) {
            DSCapsuleButton(titre: "C'est parti") {
                authMode = .signUp
            }
            .accessibilityHint("Ouvre la création de compte.")

            // Action secondaire : verre clair, libellé à l'encre (le vert plein
            // reste à l'action principale, juste au-dessus).
            Button {
                authMode = .signIn
            } label: {
                Text("J'ai déjà un compte")
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.hauteurBouton)
                    .verreClair()
                    .contentShape(Capsule())
            }
            .buttonStyle(.dsPress)
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
