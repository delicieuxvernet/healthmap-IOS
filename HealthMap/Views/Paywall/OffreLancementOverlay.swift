import SwiftUI

// MARK: - Pop-up de l'offre de lancement (12 octobre 2026)
//
// Maquette validée par Arthur le 12 octobre 2026 : même grammaire que la carte
// de l'offre annuelle (`OffreAnnuelleOverlay`) — voile, feuille de verre aux
// coins de 38, action principale en verre vert — avec la pastille « Offre de
// lancement », le signe Kiwio à côté du prix, et trois lignes de ce que
// Premium ajoute. Les mentions (prix normal, offre réservée aux nouveaux
// abonnés) restent visibles sous les boutons.
//
// Ne s'affiche que deux fois au plus (annonce, derniers jours) : voir
// `OffreLancementCentre`.

struct OffreLancementOverlay: View {
    let offre: OffreLancement
    let onFermer: () -> Void
    /// « Profiter de l'offre » : la feuille redescend, puis le paywall s'ouvre.
    let onVoir: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var montee = false
    @State private var ferme = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VerreVoile()
                .opacity(montee ? 1 : 0)
                .onTapGesture { fermer(puis: onFermer) }

            if montee {
                feuille
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: montee)
        .onAppear { montee = true }
        .accessibilityAddTraits(.isModal)
    }

    private var feuille: some View {
        ViewThatFits(in: .vertical) {
            contenu
            ScrollView { contenu }
                .scrollBounceBehavior(.basedOnSize)
        }
        .background(alignment: .top) { fond }
    }

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.dsSecondaire.opacity(0.4))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .accessibilityHidden(true)

            HStack {
                Text(offre.badge)
                    .font(.system(.footnote, design: .default).weight(.bold))
                    .foregroundStyle(Color.teinteAmbreEncre)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.teinteVitamineD.opacity(0.18)))
                Spacer(minLength: 8)
                DSCloseButton { fermer(puis: onFermer) }
            }
            .padding(.top, 8)

            HStack(alignment: .center, spacing: 12) {
                KiwiSigne(taille: 52)
                Text(offre.titre)
                    .dsPolice(24, .bold)
                    .tracking(-0.6)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.top, 12)

            Text(offre.detail)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(OffreLancement.atouts.enumerated()), id: \.offset) { index, atout in
                    HStack(spacing: 10) {
                        Image(systemName: atout.symbole)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(teinte(index))
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        Text(atout.texte)
                            .font(.dsSousTitreFort)
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 16)

            PremiumAction(titre: "Profiter de l'offre") { fermer(puis: onVoir) }
                .padding(.top, 22)

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

            Text(offre.mentions)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }

    /// Une teinte par atout : la dictée en vert Kiwio, les micronutriments en
    /// ambre, le plan en violet (les teintes de l'app, pas un arc-en-ciel).
    private func teinte(_ index: Int) -> Color {
        switch index {
        case 0: return .teinteKiwiTexte
        case 1: return .teinteVitamineDTexte
        default: return .teinteIodeTexte
        }
    }

    /// Le verre de la feuille, découpé aux coins de 38. Le fond capte les
    /// touches pour qu'un appui dans la feuille ne la referme pas.
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
