import SwiftUI

// MARK: - Carte de l'offre annuelle (1er octobre 2026)
//
// Monte du bas de l'écran, par-dessus la barre d'onglets. Une pastille, ce que
// l'annuel fait économiser, le prix, et deux sorties : « Voir l'offre » ouvre
// le paywall (c'est lui qui porte les mentions d'abonnement), « Plus tard »
// referme, « Ne plus me proposer » l'arrête pour de bon. Ton calme, sans
// capitales ni compte à rebours, comme le paywall.
//
// Surcouche de la racine, pas une `.sheet` : voir `OffreCentre`.
//
// Verre liquide (2 octobre 2026) : même grammaire que la feuille Premium de la
// maquette — voile vert-noir flouté, feuille de verre presque blanche aux
// coins de 38, titre 24 / 700, action principale en verre vert de 54 pt avec
// son reflet, « Plus tard » en vert. La mascotte, elle, reste réservée à la
// feuille Premium et à Réglages.

struct OffreAnnuelleOverlay: View {
    let offre: OffrePremium
    let onFermer: () -> Void
    /// « Voir l'offre » : la carte redescend, puis le paywall s'ouvre.
    let onVoir: () -> Void
    /// « Ne plus me proposer » : la carte redescend et ne reviendra plus.
    let onRefuser: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var montee = false
    @State private var ferme = false

    /// Titre de la feuille : 24 / 700, qui suit la taille de texte choisie.
    @ScaledMetric(relativeTo: .title2) private var tailleTitre: CGFloat = 24

    var body: some View {
        ZStack(alignment: .bottom) {
            VerreVoile()
                .opacity(montee ? 1 : 0)
                .onTapGesture { fermer(puis: onFermer) }

            if montee {
                carte
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: montee)
        .onAppear { montee = true }
        .accessibilityAddTraits(.isModal)
    }

    private var carte: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.dsSecondaire.opacity(0.4))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .accessibilityHidden(true)

            HStack {
                Text("Premium")
                    .font(.system(.footnote, design: .default).weight(.bold))
                    .foregroundStyle(Color.teinteKiwiTexte)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.teinteKiwi.opacity(0.12)))
                Spacer(minLength: 8)
                DSCloseButton { fermer(puis: onFermer) }
            }
            .padding(.top, 8)

            Text(offre.titre)
                .font(.system(size: tailleTitre, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)

            Text(offre.detail)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .lineSpacing(2)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            PremiumAction(titre: "Voir l'offre") { fermer(puis: onVoir) }
                .padding(.top, 24)

            Button {
                fermer(puis: onFermer)
            } label: {
                Text("Plus tard")
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsAccent)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)
            .padding(.top, 2)

            // Une sortie définitive, toujours visible (audit de conformité du
            // 9 octobre 2026) : la relance s'arrête quand on le demande.
            Button {
                fermer(puis: onRefuser)
            } label: {
                Text("Ne plus me proposer")
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)
            .accessibilityHint("Cette offre ne sera plus proposée.")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { fond }
    }

    /// Le verre de la feuille, découpé aux coins de 38. Le fond du socle ne
    /// capte pas les touches : la couche du dessous le fait, sinon un appui
    /// dans la carte traverserait jusqu'au voile et la refermerait.
    private var fond: some View {
        ZStack {
            Color.white.opacity(0.001)
            VerreFeuilleFond()
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Verre.rayonFeuille,
                topTrailingRadius: Verre.rayonFeuille,
                style: .continuous
            )
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private func fermer(puis suite: @escaping () -> Void) {
        guard !ferme else { return }
        ferme = true
        HapticService.shared.selection()
        guard !reduceMotion else { suite(); return }
        montee = false
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            suite()
        }
    }
}
