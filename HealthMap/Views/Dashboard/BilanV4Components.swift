import SwiftUI

// MARK: - Bilan « v4 » (refonte 3D — direction validée juin 2026)
//
// Composants de l'onglet Bilan dans le langage v4 : cartes arrondies, anneaux
// pleins, illustrations 3D (Fluent3D), pop-up bottom-sheet. Couleur = sens
// partout (échelle unique HealthScale).
// Source maquette : « Bilan v4 - 3D » (Corrections design et interface app).
//
// Verre liquide (2 octobre 2026) : la feuille est en verre, la liste des
// fruits est une carte de verre dont les lignes arrivent en cascade, la série
// porte la teinte « énergie » (flamme) et son compte est en SF Pro Rounded.


// MARK: - Pop-up détail de la récolte (au tap sur le bloc récolte)
/// Détail de la gamification « récolte » : série en cours + chaque fruit, son
/// palier de jours d'affilée et s'il est obtenu. N'altère pas l'affichage au
/// repos du bloc récolte (retour Arthur : « si on ne clique pas, ça reste tel quel »).
struct RecolteDetailSheet: View {
    let streak: Int
    @Environment(\.dismiss) private var dismiss
    /// Les lignes de fruits arrivent en cascade une fois la feuille ouverte.
    @State private var arrive = false

    private var ladder: [Fluent3D.HarvestRung] { Fluent3D.harvestLadder }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Ta récolte")
                        .font(.dsSection)
                        .tracking(DSTracking.section)
                        .foregroundStyle(Color.dsTexte)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    DSCloseButton { dismiss() }
                }

                // Série en cours (le « trophée » de jours d'affilée)
                HStack(spacing: 14) {
                    VerrePastilleIcone(
                        symbole: "flame.fill",
                        teinte: Color.teinteEnergie,
                        taille: 56,
                        tailleIcone: 26
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        (Text(DS.entier(streak))
                            .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                            + Text(streak > 1 ? " jours d'affilée" : " jour d'affilée")
                                .font(.dsHeadline))
                            .tracking(-0.4)
                            .foregroundStyle(Color.dsTexte)
                        Text("Chaque palier de série débloque un fruit.")
                            .font(.dsLegende)
                            .tracking(DSTracking.legende)
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DS.paddingCarte)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard()
                .padding(.top, 12)
                .accessibilityElement(children: .combine)

                Text("Tes fruits")
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .padding(.horizontal, 4)
                    .padding(.top, 22)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    ForEach(Array(ladder.enumerated()), id: \.element.id) { idx, rung in
                        if idx > 0 {
                            // Le filet arrive avec sa ligne.
                            DSSeparator(retrait: 0)
                                .verreCascade(arrive, delai: 0.2 + Double(min(idx, 8)) * 0.05, decalage: 0)
                        }
                        rungRow(rung)
                            .verreCascade(arrive, delai: 0.2 + Double(min(idx, 8)) * 0.05, decalage: 10)
                    }
                }
                .padding(.horizontal, DS.paddingCarte)
                .frame(maxWidth: .infinity)
                .dsCard()
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // La feuille ne peint plus d'aplat : fond de verre et coins de 38.
        .verreFeuille()
        .onAppear { arrive = true }
    }

    @ViewBuilder
    private func rungRow(_ rung: Fluent3D.HarvestRung) -> some View {
        let earned = streak >= rung.threshold
        let left = max(0, rung.threshold - streak)
        HStack(spacing: 13) {
            Fluent3DIcon(name: rung.asset, size: 40)
                .grayscale(earned ? 0 : 1)
                .opacity(earned ? 1 : 0.35)
            VStack(alignment: .leading, spacing: 2) {
                Text(rung.name)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                Text("Débloqué à \(rung.threshold) jour\(rung.threshold > 1 ? "s" : "") d'affilée")
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
            }
            Spacer(minLength: 8)
            if earned {
                // Étiquette d'état : vert foncé du kiwi sur la teinte à 14 %.
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Obtenu")
                        .font(.dsLegende.weight(.semibold))
                }
                .foregroundStyle(Color.teinteKiwiTexte)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.teinteKiwi.opacity(0.14)))
            } else {
                Text("Dans \(left) j")
                    .font(.dsLegende.weight(.semibold))
                    .foregroundStyle(Color.dsSecondaire)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Verre.remplissage))
            }
        }
        .padding(.vertical, 12)
    }
}
