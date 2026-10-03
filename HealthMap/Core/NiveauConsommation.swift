import Foundation

// MARK: - « Pas beaucoup, modérément, beaucoup » (1er octobre 2026)
//
// Sous un aliment coché, la personne dit combien elle en mange en TROIS MOTS,
// plus en fourchettes chiffrées : « plutôt que mettre des chiffres » (retour
// d'Arthur sur la maquette du questionnaire).
//
// La donnée, elle, ne change pas : `profile.groceries[id]` reste un nombre de
// portions par semaine, celui que lisent `NutrientEngine` et le prompt de
// `generate-analysis`. Ce fichier ne fait que traduire un mot en portions, et
// des portions en mot quand on relit un caddie déjà rempli.
//
// Les quatre fourchettes d'avant (`QuantityBracket` : 0–1, 2–3, 4–6, 7+)
// valaient 1, 2, 5 et 10 portions. Les trois mots en gardent les deux bouts et
// posent le milieu entre les deux fourchettes centrales.
enum NiveauConsommation: Int, CaseIterable, Identifiable {
    case pasBeaucoup
    case moderement
    case beaucoup

    var id: Int { rawValue }

    /// Le niveau posé quand on coche un aliment, avant tout réglage.
    static let parDefaut: NiveauConsommation = .moderement

    /// Le mot affiché sur le bouton.
    var libelle: String {
        switch self {
        case .pasBeaucoup: return "Pas beaucoup"
        case .moderement: return "Modérément"
        case .beaucoup: return "Beaucoup"
        }
    }

    /// Ce que le mot veut dire, pour que deux personnes ne l'entendent pas
    /// différemment.
    var precision: String {
        switch self {
        case .pasBeaucoup: return "de temps en temps"
        case .moderement: return "plusieurs fois par semaine"
        case .beaucoup: return "tous les jours ou presque"
        }
    }

    /// Portions par semaine écrites dans `profile.groceries`.
    var portions: Int {
        switch self {
        case .pasBeaucoup: return 1
        case .moderement: return 3
        case .beaucoup: return 10
        }
    }

    /// Le mot qui correspond à des portions déjà enregistrées (caddie rempli
    /// avec les anciennes fourchettes, brouillon repris).
    static func depuis(portions: Int) -> NiveauConsommation {
        if portions <= 1 { return .pasBeaucoup }
        if portions >= 7 { return .beaucoup }
        return .moderement
    }
}
