import SwiftUI

// MARK: - Carte de l'offre annuelle (1er octobre 2026)
//
// Monte du bas de l'écran, par-dessus la barre d'onglets. Une pastille, ce que
// l'annuel fait économiser, le prix, et deux sorties : « Voir l'offre » ouvre
// le paywall (c'est lui qui porte les mentions d'abonnement), « Plus tard »
// referme. Ton calme, sans capitales ni compte à rebours, comme le paywall.
//
// Surcouche de la racine, pas une `.sheet` : voir `OffreCentre`.

struct OffreAnnuelleOverlay: View {
    let offre: OffrePremium
    let onFermer: () -> Void
    /// « Voir l'offre » : la carte redescend, puis le paywall s'ouvre.
    let onVoir: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var montee = false
    @State private var ferme = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(montee ? 0.28 : 0)
                .ignoresSafeArea()
                .onTapGesture { fermer(puis: onFermer) }
                .accessibilityHidden(true)

            if montee {
                carte
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86), value: montee)
        .onAppear { montee = true }
        .accessibilityAddTraits(.isModal)
    }

    private var carte: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.dsTrait)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .accessibilityHidden(true)

            HStack {
                Text("Premium")
                    .font(.dsLegendeMoyenne)
                    .foregroundStyle(Color.dsAccent)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.dsAccent.opacity(0.12)))
                Spacer(minLength: 8)
                DSCloseButton { fermer(puis: onFermer) }
            }
            .padding(.top, 8)

            Text(offre.titre)
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)

            Text(offre.detail)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            DSCapsuleButton(titre: "Voir l'offre") { fermer(puis: onVoir) }
                .padding(.top, 20)

            Button {
                fermer(puis: onFermer)
            } label: {
                Text("Plus tard")
                    .font(.dsSousTitreMoyen)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)
            .padding(.top, 6)
        }
        .padding(.horizontal, DS.marge)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous)
                .fill(Color.dsFond)
                .ignoresSafeArea(edges: .bottom)
        }
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
