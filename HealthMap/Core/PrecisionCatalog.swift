import Foundation

// MARK: - Precision Catalog
// Mirrors web Home.jsx precisions.* multi-select options (legumes, fruits,
// meat, dairy, grains). Hardcoded to guarantee parity with the web reference
// without requiring a backend round-trip. Payload is serialised into
// `precisions.*` keys expected by the generate-analysis Edge Function.

struct PrecisionOption: Identifiable, Hashable {
    let id: String
    let emoji: String
    let label: String
}

enum PrecisionCatalog {
    // 8 options — mirrors Home.jsx line 235
    static let vegetables: [PrecisionOption] = [
        .init(id: "raw_salads",    emoji: "🥗", label: String(localized: "Crudités / salades")),
        .init(id: "cooked_veg",    emoji: "🥦", label: String(localized: "Légumes cuits")),
        .init(id: "leafy_greens",  emoji: "🥬", label: String(localized: "Feuilles vertes")),
        .init(id: "cruciferous",   emoji: "🥦", label: String(localized: "Choux, brocolis")),
        .init(id: "root_veg",      emoji: "🥕", label: String(localized: "Racines")),
        .init(id: "nightshades",   emoji: "🍅", label: String(localized: "Tomates, poivrons")),
        .init(id: "starchy_veg",   emoji: "🥔", label: String(localized: "Féculents")),
        .init(id: "squash",        emoji: "🎃", label: String(localized: "Courges")),
    ]

    // 7 options — mirrors Home.jsx line 242
    static let fruits: [PrecisionOption] = [
        .init(id: "fresh_citrus",  emoji: "🍊", label: String(localized: "Agrumes")),
        .init(id: "berries",       emoji: "🫐", label: String(localized: "Baies")),
        .init(id: "tropical",      emoji: "🥭", label: String(localized: "Tropicaux")),
        .init(id: "apples_pears",  emoji: "🍎", label: String(localized: "Pommes, poires")),
        .init(id: "banana",        emoji: "🍌", label: String(localized: "Bananes")),
        .init(id: "dried",         emoji: "🍇", label: String(localized: "Fruits secs")),
        .init(id: "juice_100",     emoji: "🧃", label: String(localized: "Jus 100%")),
    ]

    // 5 options — mirrors Home.jsx line 250
    static let meat: [PrecisionOption] = [
        .init(id: "red_meat",      emoji: "🥩", label: String(localized: "Viande rouge")),
        .init(id: "poultry",       emoji: "🍗", label: String(localized: "Volaille")),
        .init(id: "pork",          emoji: "🐷", label: String(localized: "Porc")),
        .init(id: "processed",     emoji: "🌭", label: String(localized: "Charcuterie")),
        .init(id: "plant_protein", emoji: "🌱", label: String(localized: "Protéines végé")),
    ]

    // 3 options — mirrors Home.jsx line 257
    static let dairy: [PrecisionOption] = [
        .init(id: "milk",   emoji: "🥛", label: String(localized: "Lait")),
        .init(id: "yogurt", emoji: "🥣", label: String(localized: "Yaourts")),
        .init(id: "cheese", emoji: "🧀", label: String(localized: "Fromages")),
    ]

    // 3 options — mirrors Home.jsx line 265
    static let grains: [PrecisionOption] = [
        .init(id: "whole_grain", emoji: "🌾", label: String(localized: "Céréales complètes")),
        .init(id: "refined",     emoji: "🍚", label: String(localized: "Céréales raffinées")),
        .init(id: "whole_bread", emoji: "🍞", label: String(localized: "Pain complet")),
    ]

    /// Lookup catalog by questionnaire key.
    static func options(for key: String) -> [PrecisionOption] {
        switch key {
        case "vegetableServings":  return vegetables
        case "fruitServings":      return fruits
        case "meatPoultry":        return meat
        case "dairyServings":      return dairy
        case "wholegrainPerWeek":  return grains
        default:                   return []
        }
    }

    /// User-facing title for each precision picker.
    static func title(for key: String) -> String {
        switch key {
        case "vegetableServings":  return String(localized: "Coche les légumes que tu manges")
        case "fruitServings":      return String(localized: "Coche les fruits que tu manges")
        case "meatPoultry":        return String(localized: "Coche tes protéines")
        case "dairyServings":      return String(localized: "Coche tes produits laitiers")
        case "wholegrainPerWeek":  return String(localized: "Coche tes céréales")
        default:                   return ""
        }
    }
}
