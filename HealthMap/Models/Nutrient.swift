import SwiftUI

// MARK: - Nutrient ID
enum NutrientID: String, Codable, CaseIterable, Identifiable {
    case vitD
    case vitB12
    case iron
    case magnesium
    case omega3
    case vitC
    case calcium
    case zinc
    case iodine
    case fiber

    var id: String { rawValue }
}

// MARK: - Nutrient Status
enum NutrientStatus: String, Codable {
    case deficient  // < 40
    case low        // 40-59
    case adequate   // 60-74
    case good       // >= 75

    init(score: Int) {
        if score < 40 { self = .deficient }
        else if score < 60 { self = .low }
        else if score < 75 { self = .adequate }
        else { self = .good }
    }
}

// MARK: - Nutrient Definition (static metadata)
struct NutrientDefinition: Identifiable {
    let id: NutrientID
    let label: String
    let emoji: String
    let unit: String
    let rda: Double
    let color: Color

    /// All nutrient swatches are blue-family nuances per the "tout bleu" brand rule.
    /// Kept in sync with `Color+Theme.swift` nutrient* tokens.
    var colorHex: String {
        switch id {
        case .vitD: return "007AFF"      // primary
        case .vitB12: return "0056CC"    // dark blue
        case .iron: return "5856D6"      // indigo
        case .magnesium: return "5AC8FA" // sky
        case .omega3: return "007AFF"    // primary
        case .vitC: return "64D2FF"      // light sky
        case .calcium: return "A8C5E8"   // powder
        case .zinc: return "4A90E2"      // steel
        case .iodine: return "5856D6"    // indigo
        case .fiber: return "6B8EAF"     // dusty
        }
    }
}

// MARK: - Nutrient Score (calculated result)
struct NutrientScore: Identifiable {
    let definition: NutrientDefinition
    let score: Int
    let status: NutrientStatus
    let reasons: [String]
    let solutions: [NutrientSolution]
    let timeline: String
    let science: String

    var id: NutrientID { definition.id }
    var label: String { definition.label }
    var emoji: String { definition.emoji }
    var color: Color { definition.color }
}

// MARK: - Nutrient Solution
struct NutrientSolution: Identifiable {
    let id = UUID()
    let text: String
    let type: SolutionType

    enum SolutionType: String {
        case food
        case supplement
        case lifestyle
    }
}

// MARK: - Enriched Nutrient (with AI explanation)
struct EnrichedNutrient: Identifiable, Codable {
    let id: String
    var label: String
    var emoji: String
    var color: String
    var score: Int
    var status: String
    var confidence: String?
    var signals: [String]?
    var verdict: String?
    var mecanisme: String?
    var comparaison: String?
    var signeManque: String?
    var solution: NutrientSolutionAI?
    var hack: String?
    var synergie: String?
    var pourquoiCeScore: String?
    /// Hypothèses v1 (pour la « Recherche approfondie »). Hors CodingKeys :
    /// peuplé au merge depuis AIRisk, pas (dé)sérialisé avec le nutriment.
    var hypotheses: [AIHypothesis]? = nil

    enum CodingKeys: String, CodingKey {
        case id, label, emoji, color, score, status, confidence, signals, verdict
        case mecanisme, comparaison
        case signeManque = "signe_manque"
        case solution, hack, synergie
        case pourquoiCeScore = "pourquoi_ce_score"
    }
}

struct NutrientSolutionAI: Codable {
    var action: String?
    var dosage: String?
    var quand: String?
    var pourquoi: String?
    var delai: String?
}
