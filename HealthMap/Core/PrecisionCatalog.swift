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
        .init(id: "raw_salads",    emoji: "🥗", label: "Crudités / salades"),
        .init(id: "cooked_veg",    emoji: "🥦", label: "Légumes cuits"),
        .init(id: "leafy_greens",  emoji: "🥬", label: "Feuilles vertes"),
        .init(id: "cruciferous",   emoji: "🥦", label: "Crucifères"),
        .init(id: "root_veg",      emoji: "🥕", label: "Racines"),
        .init(id: "nightshades",   emoji: "🍅", label: "Tomates, poivrons"),
        .init(id: "starchy_veg",   emoji: "🥔", label: "Féculents"),
        .init(id: "squash",        emoji: "🎃", label: "Courges"),
    ]

    // 7 options — mirrors Home.jsx line 242
    static let fruits: [PrecisionOption] = [
        .init(id: "fresh_citrus",  emoji: "🍊", label: "Agrumes"),
        .init(id: "berries",       emoji: "🫐", label: "Baies"),
        .init(id: "tropical",      emoji: "🥭", label: "Tropicaux"),
        .init(id: "apples_pears",  emoji: "🍎", label: "Pommes, poires"),
        .init(id: "banana",        emoji: "🍌", label: "Bananes"),
        .init(id: "dried",         emoji: "🍇", label: "Fruits secs"),
        .init(id: "juice_100",     emoji: "🧃", label: "Jus 100%"),
    ]

    // 5 options — mirrors Home.jsx line 250
    static let meat: [PrecisionOption] = [
        .init(id: "red_meat",      emoji: "🥩", label: "Viande rouge"),
        .init(id: "poultry",       emoji: "🍗", label: "Volaille"),
        .init(id: "pork",          emoji: "🐷", label: "Porc"),
        .init(id: "processed",     emoji: "🌭", label: "Charcuterie"),
        .init(id: "plant_protein", emoji: "🌱", label: "Protéines végé"),
    ]

    // 3 options — mirrors Home.jsx line 257
    static let dairy: [PrecisionOption] = [
        .init(id: "milk",   emoji: "🥛", label: "Lait"),
        .init(id: "yogurt", emoji: "🥣", label: "Yaourts"),
        .init(id: "cheese", emoji: "🧀", label: "Fromages"),
    ]

    // 3 options — mirrors Home.jsx line 265
    static let grains: [PrecisionOption] = [
        .init(id: "whole_grain", emoji: "🌾", label: "Céréales complètes"),
        .init(id: "refined",     emoji: "🍚", label: "Céréales raffinées"),
        .init(id: "whole_bread", emoji: "🍞", label: "Pain complet"),
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
        case "vegetableServings":  return "Coche les légumes que tu manges"
        case "fruitServings":      return "Coche les fruits que tu manges"
        case "meatPoultry":        return "Coche tes protéines"
        case "dairyServings":      return "Coche tes laitiers"
        case "wholegrainPerWeek":  return "Coche tes céréales"
        default:                   return ""
        }
    }
}
