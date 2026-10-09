import SwiftUI

// MARK: - Standard ou Premium : la carte aux kiwis (maquette validée le 9 octobre 2026)
//
// Première étape de la feuille Premium, à chaque ouverture tant qu'on n'est
// pas abonné. Une carte de verre DÉTACHÉE des bords (comme la feuille de
// dictée), posée en bas, qui laisse voir l'écran au-dessus et tient sans
// défiler : le titre, puis dix lignes, la colonne Standard, puis la colonne
// Premium posée sur une bande vert pâle, la mascotte perchée en haut.
//
// Un kiwi frais (`fluent_kiwi`) : c'est inclus. Un kiwi raplapla
// (`fluent_kiwi_ecrase`, le même kiwi aplati, terni, sa chair et son jus
// répandus) : ça ne l'est pas. À l'arrivée, les frais apparaissent en
// tournant, les raplaplas tombent et s'écrasent, ligne après ligne.
//
// « Passer à Premium » mène aux formules de la même feuille (prix, essai et
// mentions restent lus chez Apple, dans PaywallView) ; « Plus tard » et la
// croix referment. Les lignes viennent de `ComparatifPremium.lignes` : rien
// n'est écrit ici. En très grande taille de texte, la carte défile.

struct ComparatifPremiumView: View {
    let onContinuer: () -> Void
    let onPlusTard: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Les kiwis se posent, une fois la carte montée.
    @State private var poses = false

    /// Marge entre la carte et les bords de l'écran.
    private static let marge: CGFloat = 8
    private static let largeurStandard: CGFloat = 68
    private static let largeurPremium: CGFloat = 76

    var body: some View {
        ViewThatFits(in: .vertical) {
            carte
            ScrollView { carte }
        }
        .padding(.horizontal, Self.marge)
        .padding(.bottom, Self.marge)
        // La carte se pose en bas, à la taille de ce qu'elle montre.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Au-dessus d'elle : presque rien, mais touchable, pour que le glissé
        // qui referme parte aussi de là.
        .background(Color.black.opacity(0.001))
        .ignoresSafeArea(.container, edges: .bottom)
        .task {
            guard !reduceMotion else {
                poses = true
                return
            }
            // La carte monte d'abord, les kiwis se posent ensuite.
            try? await Task.sleep(for: .milliseconds(250))
            poses = true
        }
    }

    // MARK: La carte

    private var carte: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Standard ou Premium ?")
                        .dsPolice(22, .bold)
                        .tracking(-0.6)
                        .foregroundStyle(Color.dsTexte)
                        .accessibilityAddTraits(.isHeader)
                    Text("Kiwi frais : c'est inclus. Kiwi raplapla : ça ne l'est pas.")
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                DSCloseButton { onPlusTard() }
            }

            tableau
                .padding(.top, 16)

            PremiumAction(titre: "Passer à Premium", action: onContinuer)
                .padding(.top, 20)
                .accessibilityIdentifier("comparatif.continuer")

            Button(action: onPlusTard) {
                Text("Plus tard")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .verreFeuilleDetachee()
    }

    // MARK: Le tableau

    private var tableau: some View {
        VStack(spacing: 0) {
            enTeteColonnes
            ForEach(Array(ComparatifPremium.lignes.enumerated()), id: \.element.id) { rang, ligne in
                if rang > 0 {
                    Rectangle()
                        .fill(Color.dsSeparateur)
                        .frame(height: 0.5)
                        .accessibilityHidden(true)
                }
                ligneVue(ligne, rang: rang)
            }
        }
        // La colonne Premium, sur toute la hauteur du tableau.
        .background(alignment: .trailing) { bandePremium }
    }

    private var bandePremium: some View {
        let forme = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VerrePlaque(forme: forme, matiere: VerreMatiere.clairActif)
            .overlay(forme.strokeBorder(Color.teinteKiwi.opacity(0.5), lineWidth: 1.5))
            .frame(width: Self.largeurPremium)
            .padding(.vertical, -4)
            .accessibilityHidden(true)
    }

    private var enTeteColonnes: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 0)
            Text("Standard")
                .font(Font.dsLegende.weight(.semibold))
                .foregroundStyle(Color.dsSecondaire)
                .frame(width: Self.largeurStandard)
                .padding(.bottom, 8)
            VStack(spacing: 2) {
                KiwiMascotte(animee: true)
                    .frame(width: 48, height: 48)
                Text("Premium")
                    .font(Font.dsLegende.weight(.bold))
                    .foregroundStyle(Color.teinteKiwiTexte)
            }
            .frame(width: Self.largeurPremium)
            .padding(.bottom, 6)
        }
        .frame(height: 76)
        .accessibilityHidden(true)
    }

    private func ligneVue(_ ligne: LigneComparatif, rang: Int) -> some View {
        HStack(spacing: 0) {
            Text(ligne.libelle)
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsTexte)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            cellule(ligne.standard, rang: rang, premium: false)
                .frame(width: Self.largeurStandard)
            cellule(ligne.premium, rang: rang, premium: true)
                .frame(width: Self.largeurPremium)
        }
        .frame(minHeight: 38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ComparatifPremium.descriptionVocale(ligne))
    }

    /// Une cellule : le kiwi frais, le kiwi raplapla ou un plafond par jour.
    /// Les kiwis se posent ligne après ligne, la colonne Premium juste après
    /// la colonne Standard.
    @ViewBuilder
    private func cellule(_ offre: OffreComparee, rang: Int, premium: Bool) -> some View {
        let delai = 0.1 + Double(rang) * 0.07 + (premium ? 0.12 : 0)
        switch offre {
        case .inclus:
            KiwiFrais(pose: poses, delai: delai)
        case .absent:
            KiwiRaplapla(pose: poses, delai: delai)
        case .parJour(let nombre):
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(nombre)")
                    .font(Font.dsSousTitreFort.monospacedDigit())
                Text("/j")
                    .font(.dsLegende)
            }
            .foregroundStyle(premium ? Color.teinteKiwiTexte : Color.dsSecondaire)
        }
    }
}

// MARK: - Les deux kiwis

/// Inclus : la tranche de kiwi 3D, qui arrive en tournant.
private struct KiwiFrais: View {
    let pose: Bool
    let delai: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Fluent3DIcon(name: Fluent3D.kiwi, size: 26)
            .shadow(color: Verre.encreOmbre.opacity(0.22), radius: 2, y: 2)
            .scaleEffect(pose ? 1 : 0.3)
            .rotationEffect(.degrees(pose ? 0 : -40))
            .opacity(pose ? 1 : 0)
            .animation(reduceMotion ? nil : Animation.kiwiRebond.delay(delai), value: pose)
    }
}

/// Pas inclus : le même kiwi, raplapla. Il tombe, s'étire en touchant la
/// table, s'écrase, puis se tasse. Sous « Réduire les animations », il est
/// posé d'emblée.
private struct KiwiRaplapla: View {
    let pose: Bool
    let delai: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// L'état de repos : posé, à plat, à sa taille.
    private struct Chute {
        var y: CGFloat = 0
        var largeur: CGFloat = 1
        var hauteur: CGFloat = 1
        var opacite: Double = 1
    }

    private var image: some View {
        Image("fluent_kiwi_ecrase")
            .resizable()
            .scaledToFit()
            .frame(width: 36)
            .accessibilityHidden(true)
    }

    var body: some View {
        if reduceMotion {
            image.opacity(pose ? 1 : 0)
        } else {
            image
                .keyframeAnimator(initialValue: Chute(), trigger: pose) { vue, chute in
                    vue
                        .scaleEffect(x: chute.largeur, y: chute.hauteur, anchor: .bottom)
                        .offset(y: chute.y)
                        .opacity(chute.opacite)
                } keyframes: { _ in
                    KeyframeTrack(\.y) {
                        MoveKeyframe(-22)
                        LinearKeyframe(-22, duration: delai)
                        CubicKeyframe(0, duration: 0.28)
                    }
                    KeyframeTrack(\.opacite) {
                        MoveKeyframe(0)
                        LinearKeyframe(0, duration: delai)
                        LinearKeyframe(1, duration: 0.12)
                    }
                    KeyframeTrack(\.largeur) {
                        MoveKeyframe(0.55)
                        LinearKeyframe(0.55, duration: delai)
                        CubicKeyframe(0.7, duration: 0.28)
                        CubicKeyframe(1.18, duration: 0.12)
                        SpringKeyframe(1, duration: 0.3)
                    }
                    KeyframeTrack(\.hauteur) {
                        MoveKeyframe(1.5)
                        LinearKeyframe(1.5, duration: delai)
                        CubicKeyframe(1.35, duration: 0.28)
                        CubicKeyframe(0.7, duration: 0.12)
                        SpringKeyframe(1, duration: 0.3)
                    }
                }
                // Avant que la carte ne soit montée : rien à voir.
                .opacity(pose ? 1 : 0)
        }
    }
}
