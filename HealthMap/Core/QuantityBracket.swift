import Foundation

// MARK: - Quantity Bracket & Family — saisie des quantités du caddie
//
// L'écran quantités de "Faites vos courses" demande, pour chaque aliment coché,
// une fourchette hebdomadaire en UN tap (au lieu d'un stepper ±1). La fourchette
// est convertie en médiane (portions/semaine) AVANT stockage : le contrat aval
// `UserProfile.groceries: [String: Int]` reste strictement inchangé — NutrientEngine,
// DB et prompt IA continuent de voir des entiers (portions/semaine).

/// Fourchette de consommation hebdomadaire, saisie en un seul tap.
enum QuantityBracket: Int, CaseIterable, Identifiable {
    case rare        // 0–1 / semaine
    case occasional  // 2–3
    case frequent    // 4–6
    case daily       // 7+

    var id: Int { rawValue }

    /// Libellé court affiché sur le bouton-fourchette.
    var label: String {
        switch self {
        case .rare: return "0–1"
        case .occasional: return "2–3"
        case .frequent: return "4–6"
        case .daily: return "7+"
        }
    }

    /// Médiane en portions/semaine effectivement stockée dans `groceries`.
    /// Table validée avec Arthur : 1 / 2 / 5 / 10.
    var medianPortionsPerWeek: Int {
        switch self {
        case .rare: return 1
        case .occasional: return 2
        case .frequent: return 5
        case .daily: return 10
        }
    }

    /// Retrouve la fourchette correspondant à une quantité déjà stockée
    /// (restauration de l'UI, modification du caddie). Stable : la médiane d'une
    /// fourchette retombe toujours sur cette même fourchette.
    static func from(portions: Int) -> QuantityBracket {
        switch portions {
        case ..<2: return .rare
        case 2...3: return .occasional
        case 4...6: return .frequent
        default: return .daily
        }
    }
}

/// Regroupement PRÉSENTATIONNEL des 8 rayons du caddie en 4 grandes familles,
/// uniquement pour alléger l'écran quantités (moins de sections, moins de friction).
///
/// ⚠️ Ne remplace JAMAIS `GroceryCatalog.aisles` : le moteur de score
/// (`NutrientEngine`, `aisleServings`, `diversityGroupCount`) continue d'utiliser
/// les 8 rayons. Cette structure n'est qu'une couche d'affichage en lecture seule.
struct QuantityFamily: Identifiable {
    let id: String
    let label: String
    let emoji: String
    /// Ids des rayons (`GroceryAisle.id`) regroupés sous cette famille.
    let aisleIds: [String]

    static let all: [QuantityFamily] = [
        QuantityFamily(id: "proteines", label: "Protéines", emoji: "🍗",
                       aisleIds: ["viandes", "poissons"]),
        QuantityFamily(id: "fruits_legumes", label: "Fruits & légumes", emoji: "🥦",
                       aisleIds: ["fruits", "legumes"]),
        QuantityFamily(id: "feculents", label: "Féculents & légumineuses", emoji: "🍞",
                       aisleIds: ["feculents"]),
        QuantityFamily(id: "laitiers_gras", label: "Laitiers, œufs & matières grasses", emoji: "🧀",
                       aisleIds: ["laitiers", "gras", "secs"]),
    ]

    /// Famille d'affichage d'un aliment, via son rayon d'origine. Fallback sur la
    /// dernière famille si le rayon est introuvable (jamais en pratique : les 8
    /// rayons sont tous mappés).
    static func family(forItemId itemId: String) -> QuantityFamily {
        let aisleId = GroceryCatalog.aisles.first { aisle in
            aisle.items.contains { $0.id == itemId }
        }?.id
        return all.first { $0.aisleIds.contains(aisleId ?? "") } ?? all[all.count - 1]
    }
}
