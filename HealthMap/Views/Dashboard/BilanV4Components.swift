import SwiftUI

// MARK: - Bilan « v4 » (refonte 3D — direction validée juin 2026)
//
// Composants de l'onglet Bilan dans le langage v4 : fond crème, cartes
// blanches arrondies, anneaux pleins, illustrations 3D (Fluent3D), pop-up
// bottom-sheet. Couleur = sens partout (échelle unique HealthScale).
// Source maquette : « Bilan v4 - 3D » (Corrections design et interface app).


// MARK: - Pop-up détail de la récolte (au tap sur le bloc récolte)
/// Détail de la gamification « récolte » : série en cours + chaque fruit, son
/// palier de jours d'affilée et s'il est obtenu. N'altère pas l'affichage au
/// repos du bloc récolte (retour Arthur : « si on ne clique pas, ça reste tel quel »).
struct RecolteDetailSheet: View {
    let streak: Int
    @Environment(\.dismiss) private var dismiss

    private var ladder: [Fluent3D.HarvestRung] { Fluent3D.harvestLadder }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Ta récolte")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.dsTexte)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.dsSecondaire)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.dsTexte.opacity(0.06)))
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel("Fermer")
                }

                // Série en cours (le « trophée » de jours d'affilée)
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.dsRemplissage).frame(width: 56, height: 56)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.dsAccent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(streak) jour\(streak > 1 ? "s" : "") d'affilée")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.dsTexte)
                        Text("Chaque palier de série débloque un fruit.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 18)

                Text("Tes fruits")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.dsTexte)
                    .padding(.top, 22)
                    .padding(.bottom, 10)

                VStack(spacing: 0) {
                    ForEach(Array(ladder.enumerated()), id: \.element.id) { idx, rung in
                        if idx > 0 {
                            Divider().background(Color.dsTexte.opacity(0.07))
                        }
                        rungRow(rung)
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .kiwiCard(radius: 18)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.dsFond)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
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
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.dsTexte)
                Text("Débloqué à \(rung.threshold) jour\(rung.threshold > 1 ? "s" : "") d'affilée")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.dsSecondaire)
            }
            Spacer(minLength: 8)
            if earned {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                    Text("Obtenu").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.dsTexte)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.dsRemplissage))
            } else {
                Text("Dans \(left) j")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.dsSecondaire)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.dsTexte.opacity(0.06)))
            }
        }
        .padding(.vertical, 12)
    }
}
