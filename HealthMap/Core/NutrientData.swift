import SwiftUI

// MARK: - Nutrient Data (canonical source — matches NUTRIENTS in health.js)
// RULE: Labels, emojis, colors ALWAYS from here, NEVER from AI response

enum NutrientData {
    static let all: [NutrientDefinition] = [
        NutrientDefinition(id: .vitD, label: "Vitamine D", emoji: "☀️", unit: "UI", rda: 1000, color: .nutrientVitD),
        NutrientDefinition(id: .vitB12, label: "Vitamine B12", emoji: "🔴", unit: "µg", rda: 2.4, color: .nutrientVitB12),
        NutrientDefinition(id: .iron, label: "Fer", emoji: "🩸", unit: "mg", rda: 18, color: .nutrientIron),
        NutrientDefinition(id: .magnesium, label: "Magnésium", emoji: "⚡", unit: "mg", rda: 400, color: .nutrientMagnesium),
        NutrientDefinition(id: .omega3, label: "Oméga-3", emoji: "🐟", unit: "g", rda: 1.6, color: .nutrientOmega3),
        NutrientDefinition(id: .vitC, label: "Vitamine C", emoji: "🍊", unit: "mg", rda: 90, color: .nutrientVitC),
        NutrientDefinition(id: .calcium, label: "Calcium", emoji: "🦴", unit: "mg", rda: 1000, color: .nutrientCalcium),
        NutrientDefinition(id: .zinc, label: "Zinc", emoji: "🛡️", unit: "mg", rda: 11, color: .nutrientZinc),
        NutrientDefinition(id: .iodine, label: "Iode", emoji: "🌊", unit: "µg", rda: 150, color: .nutrientIodine),
        NutrientDefinition(id: .fiber, label: "Fibres", emoji: "🌾", unit: "g", rda: 30, color: .nutrientFiber),
    ]

    static func definition(for id: NutrientID) -> NutrientDefinition {
        if let def = all.first(where: { $0.id == id }) {
            return def
        }
        // Fallback défensif : un NutrientID a été ajouté à l'enum sans entrée dans `all`.
        assertionFailure("NutrientData.all manque une entrée pour \(id.rawValue). Ajouter la définition.")
        return NutrientDefinition(id: id, label: id.rawValue, emoji: "❓", unit: "", rda: 0, color: .healthMapBlue)
    }

    static func definition(for idString: String) -> NutrientDefinition? {
        guard let id = NutrientID(rawValue: idString) else { return nil }
        return definition(for: id)
    }

    static let validIDs = Set(NutrientID.allCases.map(\.rawValue))
}
