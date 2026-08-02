import Foundation
import SwiftUI

// MARK: - Supplement Engine (ported from web supplementEngine.js)
// Reads nutrient scores + user profile to generate personalized supplement recommendations.
// Read-only: does not modify any existing data.
//
// Models are in SupplementModels.swift
// Catalog is in SupplementCatalog.swift (extension)

// MARK: - Supplement Engine
enum SupplementEngine {

    // ============================================================
    // CONSTANTS
    // ============================================================

    private static let maxTopRecommendations = 3

    /// Base diet difficulty (1-10, 10 = hardest to fix through food alone)
    private static let baseDietDifficulty: [NutrientID: Int] = [
        .vitD: 9,
        .vitB12: 8,
        .iron: 7,
        .omega3: 6,
        .iodine: 6,
        .calcium: 5,
        .zinc: 5,
        .magnesium: 4,
        .fiber: 3,
        .vitC: 2,
    ]

    // ============================================================
    // NUTRIENT METADATA HELPERS
    // ============================================================

    static func nutrientLabel(for id: NutrientID) -> String {
        switch id {
        case .vitD: return "Vitamine D"
        case .vitB12: return "Vitamine B12"
        case .iron: return "Fer"
        case .magnesium: return "Magnésium"
        case .omega3: return "Oméga-3"
        case .vitC: return "Vitamine C"
        case .calcium: return "Calcium"
        case .zinc: return "Zinc"
        case .iodine: return "Iode"
        case .fiber: return "Fibres"
        }
    }

    static func nutrientEmoji(for id: NutrientID) -> String {
        switch id {
        case .vitD: return "☀️"
        case .vitB12: return "🔴"
        case .iron: return "🩸"
        case .magnesium: return "⚡"
        case .omega3: return "🐟"
        case .vitC: return "🍊"
        case .calcium: return "🦴"
        case .zinc: return "🛡️"
        case .iodine: return "🌊"
        case .fiber: return "🌾"
        }
    }

    // ============================================================
    // 1. PROFILE HELPERS
    // ============================================================

    private static func getDietType(_ profile: UserProfile) -> String {
        let d = profile.dietType.lowercased()
        if d.contains("vegan") { return "vegan" }
        if d.contains("vegetar") || d.contains("végétar") { return "vegetarien" }
        if d.contains("pescet") || d.contains("pesco") { return "pescetarien" }
        return "omnivore"
    }

    private static func isPregnant(_ profile: UserProfile) -> Bool {
        let p = profile.pregnancyStatus.lowercased()
        return p == "pregnant" || p == "enceinte"
    }

    private static func hasHeavyPeriods(_ profile: UserProfile) -> Bool {
        let p = profile.periodFlow.lowercased()
        return p == "heavy" || p == "abondant" || p == "abondantes"
    }

    private static func isIndoorWorker(_ profile: UserProfile) -> Bool {
        let v = profile.indoorWork.lowercased()
        return v == "true" || v == "yes" || v == "oui"
    }

    private static func hasHighStress(_ profile: UserProfile) -> Bool {
        let s = profile.stressLevel.lowercased()
        return s == "high" || s == "eleve" || s == "tres_eleve"
    }

    private static func isSenior(_ profile: UserProfile) -> Bool {
        profile.ageInt >= 50
    }

    // ============================================================
    // 2. DIET DIFFICULTY ADJUSTMENTS
    // ============================================================

    private static func getAdjustedDifficulty(_ nutrientID: NutrientID, profile: UserProfile) -> Int {
        var diff = baseDietDifficulty[nutrientID] ?? 5
        let diet = getDietType(profile)

        switch nutrientID {
        case .vitB12:
            if diet == "vegan" { diff = 10 }
            else if diet == "vegetarien" { diff += 2 }
            if isSenior(profile) { diff += 1 }

        case .iron:
            if diet == "vegan" || diet == "vegetarien" { diff += 2 }
            if hasHeavyPeriods(profile) { diff += 2 }

        case .omega3:
            if diet == "vegan" { diff += 3 }
            else if diet == "vegetarien" { diff += 2 }

        case .vitD:
            if isIndoorWorker(profile) { diff += 1 }

        case .calcium:
            if diet == "vegan" { diff += 2 }

        default:
            break
        }

        return min(diff, 10)
    }

    // ============================================================
    // 3. WHY TEXT GENERATION
    // ============================================================

    private static func generateWhyText(nutrientID: NutrientID, score: Int, difficulty: Int, profile: UserProfile) -> String {
        let label = nutrientLabel(for: nutrientID)
        let isDeficient = score < 40
        let diet = getDietType(profile)

        var why = "Ton score \(label) est de \(score)/100"
        why += isDeficient ? ", à renforcer en priorité." : ", à surveiller."

        // Diet-specific context
        if difficulty >= 8 {
            if diet == "vegan" && nutrientID == .vitB12 {
                why += " La B12 est absente des aliments végétaux, un complément est indispensable."
            } else if nutrientID == .vitD {
                why += " La vitamine D est presque impossible à obtenir par l'alimentation seule."
            } else {
                why += " Ce nutriment est très difficile à rattraper par l'alimentation seule."
            }
        } else if difficulty >= 6 {
            why += " Ce nutriment est difficile à obtenir en quantité suffisante avec ton profil."
        }

        // Profile-specific reasons
        if nutrientID == .iron && hasHeavyPeriods(profile) {
            why += " Tes règles abondantes augmentent tes pertes de fer."
        }
        if nutrientID == .iron && (diet == "vegan" || diet == "vegetarien") {
            why += " Le fer des végétaux est moins bien absorbé."
        }
        if nutrientID == .vitB12 && isSenior(profile) {
            why += " L'absorption de la B12 diminue avec l'âge."
        }
        if nutrientID == .magnesium && hasHighStress(profile) {
            why += " Un stress qui dure épuise tes réserves de magnésium."
        }
        if nutrientID == .omega3 && (diet == "vegan" || diet == "vegetarien") {
            why += " Sans poisson, l'apport en oméga-3 marins est presque nul."
        }

        return why
    }

    // ============================================================
    // 4. PRODUCT SELECTION (filter by diet, contraindications)
    // ============================================================

    private static func filterByDiet(product: SupplementProduct, profile: UserProfile) -> Bool {
        let diet = getDietType(profile)

        // Poisson exclu pour vegan ET végétarien (le pescétarien garde le poisson).
        if (diet == "vegan" || diet == "vegetarien")
            && product.nutrientID == .omega3
            && !product.isVegan {
            return false
        }

        return true
    }

    // Les contre-indications ne sont PLUS un filtre silencieux : le profil ne
    // capte ni allergie, ni thyroïde, ni hémochromatose. On affiche le produit
    // AVEC une précaution (voir SupplementsV4.precautions) plutôt que de le
    // masquer. La grossesse déclenche une note « valide avec ton médecin »
    // (detectConditionWarnings) sans exclure le fer, dont le besoin augmente.

    /// Find matching products for a given nutrient.
    /// Le catalogue est ordonné pour que le premier produit d'un tier soit le
    /// meilleur (premium) / le moins cher (value) — sélection déterministe.
    private static func findProducts(for nutrientID: NutrientID, profile: UserProfile) -> (premium: SupplementProduct?, value: SupplementProduct?) {
        var premium: SupplementProduct?
        var value: SupplementProduct?

        for product in catalog {
            guard product.nutrientID == nutrientID else { continue }
            guard filterByDiet(product: product, profile: profile) else { continue }

            switch product.tier {
            case .premium where premium == nil:
                premium = product
            case .value where value == nil:
                value = product
            default:
                break
            }

            if premium != nil && value != nil { break }
        }

        return (premium, value)
    }

    // ============================================================
    // 5. TOP 3 RECOMMENDATIONS
    // ============================================================

    /// Main entry: selectProducts for nutrients with score < 60
    static func selectProducts(scores: [String: Int], profile: UserProfile) -> [SupplementRecommendation] {
        // Collect all nutrients with score < 60
        var concerns: [(id: NutrientID, score: Int)] = []

        for nutrient in NutrientID.allCases {
            let score = scores[nutrient.rawValue] ?? 100
            if score < 60 {
                concerns.append((id: nutrient, score: score))
            }
        }

        guard !concerns.isEmpty else { return [] }

        // Score & sort by priority = (100 - score) * difficulty / 10
        let scored = concerns.map { concern -> (id: NutrientID, score: Int, difficulty: Int, priority: Double) in
            let diff = getAdjustedDifficulty(concern.id, profile: profile)
            let priority = Double(100 - concern.score) * Double(diff) / 10.0
            return (id: concern.id, score: concern.score, difficulty: diff, priority: priority)
        }.sorted { $0.priority > $1.priority }

        // Take top 3
        let top = Array(scored.prefix(maxTopRecommendations))

        // Find products for each
        return top.compactMap { item in
            let products = findProducts(for: item.id, profile: profile)
            guard products.premium != nil || products.value != nil else { return nil }

            let whyText = generateWhyText(
                nutrientID: item.id,
                score: item.score,
                difficulty: item.difficulty,
                profile: profile
            )

            return SupplementRecommendation(
                id: item.id.rawValue,
                nutrientID: item.id,
                score: item.score,
                priorityScore: item.priority,
                dietDifficulty: item.difficulty,
                whyText: whyText,
                premiumProduct: products.premium,
                valueProduct: products.value
            )
        }
    }

    // ============================================================
    // 6. DAILY SCHEDULE (group products by timing display group)
    // ============================================================

    static func generateSchedule(from recommendations: [SupplementRecommendation]) -> [ScheduleGroup] {
        // Collect all recommended products (prefer premium, fallback value)
        let products = recommendations.compactMap { $0.bestProduct }
        guard !products.isEmpty else { return [] }

        // Group by display group (Matin / Midi / Soir)
        var groups: [String: [SupplementProduct]] = [:]

        for product in products {
            let group = product.timing.displayGroup
            groups[group, default: []].append(product)
        }

        // Build schedule groups in order
        let order = ["Matin", "Midi", "Soir"]

        return order.compactMap { groupName in
            guard let groupProducts = groups[groupName], !groupProducts.isEmpty else { return nil }
            let first = groupProducts[0]
            return ScheduleGroup(
                id: groupName,
                label: groupName,
                icon: first.timing.displayGroupIcon,
                color: first.timing.displayGroupColor,
                products: groupProducts
            )
        }
    }

    // ============================================================
    // 7. INTERACTION WARNINGS (supplement-supplement)
    // ============================================================

    /// Known anti-interaction pairs
    private static let knownInteractions: [(pair: Set<String>, emoji: String, message: String, severity: InteractionWarning.Severity)] = [
        (
            pair: ["calcium", "iron"],
            emoji: "🦴🩸",
            message: "Ne prends jamais le fer et le calcium en même temps : ils se gênent l'un l'autre. Espace les prises de 2h minimum.",
            severity: .moderate
        ),
        (
            pair: ["iron", "zinc"],
            emoji: "🩸🛡️",
            message: "Le fer et le zinc se gênent l'un l'autre. Prends le fer le matin et le zinc le soir.",
            severity: .moderate
        ),
        (
            pair: ["calcium", "zinc"],
            emoji: "🦴🛡️",
            message: "Le calcium réduit l'absorption du zinc. Espace les prises de 2h.",
            severity: .moderate
        ),
        (
            pair: ["calcium", "magnesium"],
            emoji: "🦴⚡",
            message: "À forte dose, le calcium et le magnésium se gênent l'un l'autre. Prends-les à des repas différents.",
            severity: .moderate
        ),
        // Zinc haute dose reduit l'absorption du cuivre
        (
            pair: ["zinc", "copper"],
            emoji: "🛡️🟤",
            message: "À forte dose (plus de 25 mg par jour), le zinc réduit l'absorption du cuivre. Préfère un complément zinc + cuivre, ou fais des cures plus courtes.",
            severity: .moderate
        ),
    ]

    static func detectInteractionWarnings(from recommendations: [SupplementRecommendation]) -> [InteractionWarning] {
        let products = recommendations.compactMap { $0.bestProduct }

        // Collect all nutrient IDs present in recommended products
        var presentNutrients: Set<String> = []
        for product in products {
            presentNutrients.insert(product.nutrientID.rawValue)
        }

        var warnings: [InteractionWarning] = []

        // Check known interaction pairs
        for interaction in knownInteractions {
            if interaction.pair.isSubset(of: presentNutrients) {
                warnings.append(InteractionWarning(
                    emoji: interaction.emoji,
                    message: interaction.message,
                    nutrients: Array(interaction.pair),
                    severity: interaction.severity
                ))
            }
        }

        // Check per-product antiInteractions
        for product in products {
            for anti in product.antiInteractions {
                if presentNutrients.contains(anti) {
                    let pair = Set([product.nutrientID.rawValue, anti])
                    let alreadyWarned = warnings.contains { Set($0.nutrients) == pair }
                    if !alreadyWarned {
                        let antiLabel = NutrientID(rawValue: anti).map { nutrientLabel(for: $0) } ?? anti
                        warnings.append(InteractionWarning(
                            emoji: "⚠️",
                            message: "\(product.name) : à ne pas prendre avec \(antiLabel). Espace les prises de 2h minimum.",
                            nutrients: Array(pair),
                            severity: .moderate
                        ))
                    }
                }
            }
        }

        return warnings
    }

    // ============================================================
    // 7b. MEDICATION INTERACTIONS
    // ============================================================

    /// Detects interactions between recommended supplements and the user's medications.
    /// Returns additional InteractionWarning items to merge into the final result.
    static func detectMedicationInteractions(
        recommendations: [SupplementRecommendation],
        medications: [String]
    ) -> [InteractionWarning] {
        guard !medications.isEmpty else { return [] }

        let recommendedNutrients = Set(recommendations.map { $0.nutrientID })
        var warnings: [InteractionWarning] = []

        let medicationSet = Set(medications.map { $0.lowercased() })

        // Anticoagulant + Omega-3 -> critical (risk of bleeding)
        if medicationSet.contains("anticoagulant") && recommendedNutrients.contains(.omega3) {
            warnings.append(InteractionWarning(
                emoji: "🩸⚠️",
                message: "Anticoagulant + oméga-3 : risque de saignement plus élevé. Demande l'avis de ton médecin avant de prendre des oméga-3.",
                nutrients: ["omega3", "anticoagulant"],
                severity: .critical
            ))
        }

        // PPI + Iron -> moderate (take iron 2h before PPI)
        if medicationSet.contains("ppi") && recommendedNutrients.contains(.iron) {
            warnings.append(InteractionWarning(
                emoji: "💊🩸",
                message: "IPP + fer : les IPP réduisent l'acidité de l'estomac, dont le fer a besoin pour être absorbé. Prends le fer 2h avant l'IPP.",
                nutrients: ["iron", "ppi"],
                severity: .moderate
            ))
        }

        // PPI + Calcium -> moderate
        if medicationSet.contains("ppi") && recommendedNutrients.contains(.calcium) {
            warnings.append(InteractionWarning(
                emoji: "💊🦴",
                message: "IPP + calcium : les IPP réduisent l'absorption du calcium. Préfère le citrate de calcium et espace les prises.",
                nutrients: ["calcium", "ppi"],
                severity: .moderate
            ))
        }

        // PPI + Magnesium -> moderate (long-term depletion)
        if medicationSet.contains("ppi") && recommendedNutrients.contains(.magnesium) {
            warnings.append(InteractionWarning(
                emoji: "💊⚡",
                message: "IPP + magnésium : pris longtemps, les IPP peuvent épuiser le magnésium. À surveiller avec ton médecin.",
                nutrients: ["magnesium", "ppi"],
                severity: .moderate
            ))
        }

        // Metformin + Vitamin B12 -> moderate
        if medicationSet.contains("metformin") && recommendedNutrients.contains(.vitB12) {
            warnings.append(InteractionWarning(
                emoji: "💉🔴",
                message: "Metformine + B12 : la metformine réduit l'absorption de la B12. Un complément est recommandé (méthylcobalamine, ou une forme à laisser fondre sous la langue).",
                nutrients: ["vitB12", "metformin"],
                severity: .moderate
            ))
        }

        return warnings
    }

    // ============================================================
    // 7c. CONDITION NOTES (profil : grossesse, etc.)
    // ============================================================

    /// Notes liées à l'état de l'utilisateur (pas à un médicament).
    /// La grossesse n'exclut plus le fer — elle ajoute une précaution de
    /// supervision médicale (les besoins en fer augmentent en grossesse).
    static func detectConditionWarnings(
        recommendations: [SupplementRecommendation],
        profile: UserProfile
    ) -> [InteractionWarning] {
        var warnings: [InteractionWarning] = []
        let recommendedNutrients = Set(recommendations.map { $0.nutrientID })

        if isPregnant(profile) && recommendedNutrients.contains(.iron) {
            warnings.append(InteractionWarning(
                emoji: "🤰🩸",
                message: "Grossesse : tes besoins en fer augmentent, mais valide le dosage avec ton médecin ou ta sage-femme avant de te supplémenter.",
                nutrients: ["iron", "grossesse"],
                severity: .moderate
            ))
        }

        return warnings
    }

    // ============================================================
    // 8. COST CALCULATION
    // ============================================================

    static func calculateCost(from recommendations: [SupplementRecommendation]) -> CostSummary {
        var premiumTotal: Double = 0
        var valueTotal: Double = 0

        for rec in recommendations {
            let premCost = rec.premiumProduct?.monthlyCost ?? 0
            let valCost = rec.valueProduct?.monthlyCost ?? 0

            // Premium scenario: use premium if available, else value
            premiumTotal += premCost > 0 ? premCost : valCost
            // Value scenario: use value if available, else premium
            valueTotal += valCost > 0 ? valCost : premCost
        }

        return CostSummary(
            premiumTotal: (premiumTotal * 100).rounded() / 100,
            valueTotal: (valueTotal * 100).rounded() / 100
        )
    }

    // ============================================================
    // 9. MAIN ENTRY POINT
    // ============================================================

    /// Generate complete supplement recommendations from scores + profile
    static func generateRecommendations(scores: [String: Int], profile: UserProfile) -> SupplementEngineResult {
        let recommendations = selectProducts(scores: scores, profile: profile)
        let schedule = generateSchedule(from: recommendations)
        let supplementWarnings = detectInteractionWarnings(from: recommendations)
        let medicationWarnings = detectMedicationInteractions(
            recommendations: recommendations,
            medications: profile.medications
        )
        let conditionWarnings = detectConditionWarnings(
            recommendations: recommendations,
            profile: profile
        )
        // Merge supplement-supplement, supplement-medication and condition warnings
        let warnings = supplementWarnings + medicationWarnings + conditionWarnings
        let cost = calculateCost(from: recommendations)

        return SupplementEngineResult(
            topRecommendations: recommendations,
            schedule: schedule,
            warnings: warnings,
            cost: cost
        )
    }
}
