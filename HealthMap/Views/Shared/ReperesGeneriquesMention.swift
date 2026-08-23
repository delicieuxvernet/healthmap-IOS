import SwiftUI

// MARK: - Mention « repères adulte moyen » (V12e — scan sans bilan)
//
// Sans bilan, la fonction scan n'a aucun score personnel à croiser : la
// couverture, les % des besoins et le score de repas rapportent l'assiette aux
// références nutritionnelles d'un adulte moyen (RDA standard, côté serveur).
// Cette mention le dit, en petit, LÀ où ces valeurs s'affichent — style des
// mentions secondaires existantes (11.5 medium, encre muted), rien de plus.
// La porte d'action reste `BilanDoorButton` (une seule, sur le résultat de
// scan) ; la mention, elle, n'est qu'une étiquette d'honnêteté.
struct ReperesGeneriquesMention: View {
    /// LA phrase canonique — testée (jamais vide, séparateurs conformes).
    static let texte = "Repères adulte moyen. Ton bilan (3 min) les personnalise."

    /// Visibilité : uniquement sans bilan (invariant testé hors UI —
    /// « étiquette présente sans bilan, absente avec »).
    static func estVisible(bilanComplete: Bool) -> Bool { !bilanComplete }

    var body: some View {
        Text(Self.texte)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color.dsSecondaire)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
