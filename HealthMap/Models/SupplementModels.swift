import Foundation
import SwiftUI

// MARK: - Supplement Models (extracted from SupplementEngine)
// Model structs used by the Supplement Engine for recommendations,
// scheduling, interactions, and cost calculation.

// MARK: - Timing Slot
enum TimingSlot: String, CaseIterable, Identifiable {
    case matinAJeun = "matin_a_jeun"
    case matinRepas = "matin_repas"
    case midiRepas = "midi_repas"
    case soirRepas = "soir_repas"
    case coucher = "coucher"
    case entreRepas = "entre_repas"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .matinAJeun: return "Matin a jeun"
        case .matinRepas: return "Matin avec petit-dejeuner"
        case .midiRepas: return "Midi avec repas"
        case .soirRepas: return "Soir avec diner"
        case .coucher: return "Au coucher"
        case .entreRepas: return "Entre les repas"
        }
    }

    var emoji: String {
        switch self {
        case .matinAJeun: return "🌅"
        case .matinRepas: return "☀️"
        case .midiRepas: return "🌞"
        case .soirRepas: return "🌆"
        case .coucher: return "🌙"
        case .entreRepas: return "⏳"
        }
    }

    var order: Int {
        switch self {
        case .matinAJeun: return 0
        case .matinRepas: return 1
        case .midiRepas: return 2
        case .soirRepas: return 3
        case .coucher: return 4
        case .entreRepas: return 5
        }
    }

    /// Grouped display slot (matin / midi / soir)
    var displayGroup: String {
        switch self {
        case .matinAJeun, .matinRepas: return "Matin"
        case .midiRepas, .entreRepas: return "Midi"
        case .soirRepas, .coucher: return "Soir"
        }
    }

    var displayGroupIcon: String {
        switch self {
        case .matinAJeun, .matinRepas: return "sunrise.fill"
        case .midiRepas, .entreRepas: return "sun.max.fill"
        case .soirRepas, .coucher: return "moon.fill"
        }
    }

    var displayGroupColor: Color {
        switch self {
        case .matinAJeun, .matinRepas: return .accentSky
        case .midiRepas, .entreRepas: return .healthMapBlue
        case .soirRepas, .coucher: return .accentIndigo
        }
    }
}

// MARK: - Supplement Product
struct SupplementProduct: Identifiable, Equatable {
    let id: String           // slug
    let name: String
    let nutrientID: NutrientID
    let brand: String
    let dosage: String
    let timing: TimingSlot
    let price: Double        // EUR
    let unitsPerPackage: Int
    let isVegan: Bool
    let contraindications: [String]
    let antiInteractions: [String]
    let tier: ProductTier
    let whyBrand: String

    var dailyCost: Double {
        price / Double(unitsPerPackage)
    }

    var monthlyCost: Double {
        dailyCost * 30
    }

    enum ProductTier: String {
        case premium
        case value
    }
}

// MARK: - Recommendation
struct SupplementRecommendation: Identifiable {
    let id: String           // nutrient raw value
    let nutrientID: NutrientID
    let score: Int
    let priorityScore: Double
    let dietDifficulty: Int
    let whyText: String
    let premiumProduct: SupplementProduct?
    let valueProduct: SupplementProduct?

    var bestProduct: SupplementProduct? {
        premiumProduct ?? valueProduct
    }

    var nutrientLabel: String {
        SupplementEngine.nutrientLabel(for: nutrientID)
    }

    var nutrientEmoji: String {
        SupplementEngine.nutrientEmoji(for: nutrientID)
    }

    var nutrientColor: Color {
        Color.nutrientColor(for: nutrientID.rawValue)
    }
}

// MARK: - Interaction Warning
struct InteractionWarning: Identifiable {
    let id = UUID()
    let emoji: String
    let message: String
    let nutrients: [String]
    let severity: Severity

    enum Severity: String {
        case moderate
        case critical
    }
}

// MARK: - Cost Summary
struct CostSummary {
    let premiumTotal: Double
    let valueTotal: Double

    var minEstimate: Double { min(premiumTotal, valueTotal) }
    var maxEstimate: Double { max(premiumTotal, valueTotal) }

    var displayRange: String {
        let minStr = String(format: "%.0f", minEstimate)
        let maxStr = String(format: "%.0f", maxEstimate)
        if minStr == maxStr {
            return "\(minStr) EUR/mois"
        }
        return "\(minStr) - \(maxStr) EUR/mois"
    }
}

// MARK: - Schedule Group
struct ScheduleGroup: Identifiable {
    let id: String
    let label: String
    let icon: String
    let color: Color
    let products: [SupplementProduct]
}

// MARK: - Engine Result
struct SupplementEngineResult {
    let topRecommendations: [SupplementRecommendation]
    let schedule: [ScheduleGroup]
    let warnings: [InteractionWarning]
    let cost: CostSummary
}
