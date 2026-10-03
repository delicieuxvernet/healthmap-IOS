import SwiftUI
import UIKit

// MARK: - Journal du jour : libellés de catégorie
//
// Verre liquide (2 octobre 2026) : chaque catégorie garde UNE teinte, et sa
// version foncée pour le texte posé sur le verre. Un libellé de catégorie
// (« Énergie », « Micronutriments », « Eau ») s'écrit en 15 / 600 dans la
// teinte foncée, précédé de son icône dans la teinte : c'est `ScanCardHeader`.
// Aucun chiffre inventé, aucune logique ici : la logique (bindings) reste dans
// MealScanView ; ces composants ne sont que de l'habillage.
//
// Hiérarchie (charte du 17 août 2026, toujours valable) : un titre de section
// n'est jamais à l'encre neutre, et les chiffres qui justifient une carte
// (kcal restantes, % de couverture) sont des données-héros : jamais sous
// 15 pt, arrondis et à chasse fixe.

// MARK: - Encres de domaine des titres de section
/// Un titre de section n'est jamais neutre (règle 1 de la charte) : il porte
/// l'encre de son domaine. Les deux domaines de l'onglet sont l'ÉNERGIE
/// (kcal, budget du jour, repas comptés) et les APPORTS (micronutriments).
/// L'encre de l'énergie est la version foncée de sa teinte (`#A94620`) : elle
/// tient 4,5:1 sur le verre clair, ce que la teinte elle-même ne fait pas.
enum ScanDomaine {
    static let energie = Color.teinteEnergieTexte
    static let apports = Color.dsTexte
}

// MARK: - Libellé de catégorie (icône + titre)
/// Le libellé d'une catégorie en tête de carte : icône de 16 pt dans la teinte
/// de la catégorie, titre en 15 / 600 dans sa version foncée.
struct ScanCardHeader: View {
    let icon: String
    let title: String
    /// Encre du titre : la version foncée de la teinte de la catégorie.
    var color: Color = ScanDomaine.apports
    /// Teinte de l'icône. `nil` : la même encre que le titre.
    var teinte: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(teinte ?? color)
                .accessibilityHidden(true)
            // Libellé de catégorie 15 / 600 sans approche, comme partout dans
            // la maquette.
            Text(title)
                .font(.dsSousTitreFort)
                .foregroundStyle(color)
        }
    }
}
