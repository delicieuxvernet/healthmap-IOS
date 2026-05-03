import Foundation

// MARK: - Red Flag Detector (exact translation of detectRedFlags in health.js)
enum RedFlagDetector {

    static func detect(profile: UserProfile) -> [RedFlag] {
        var flags: [RedFlag] = []

        let supplements = profile.supplementsCurrent
        let hasSupplement: (String) -> Bool = { name in
            supplements.contains(name) || supplements.contains("multivitamin")
        }
        let symptoms = profile.symptoms
        let medications = profile.medications
        let conditions = profile.digestiveConditions
        let age = profile.ageInt
        let diet = profile.dietType

        // Vegan/Vegetarian without B12 supplement
        if ["vegan", "vegetarien", "vegetarian"].contains(diet) && !hasSupplement("b12") {
            flags.append(RedFlag(
                id: .veganNoB12, urgency: .soon,
                message: "Régime végé sans supplément B12 — signal à prendre au sérieux à long terme. La B12 n'existe pas dans les végétaux."
            ))
        }

        // Pregnant without folate
        if profile.pregnancyStatus == "pregnant" && !hasSupplement("folate") {
            flags.append(RedFlag(
                id: .pregnantNoFolate, urgency: .immediate,
                message: "Enceinte sans folate — le folate est critique pour le développement neural du fœtus. Consultez votre médecin immédiatement."
            ))
        }

        // Pregnant + smoking
        if profile.pregnancyStatus == "pregnant" && profile.isSmoker {
            flags.append(RedFlag(
                id: .pregnantSmoking, urgency: .immediate,
                message: "Enceinte et fumeuse — risque majeur pour le fœtus. Parlez-en à votre médecin."
            ))
        }

        // Trying to conceive without folate
        if profile.pregnancyStatus == "trying_to_conceive" && !hasSupplement("folate") {
            flags.append(RedFlag(
                id: .tryingConceiveNoFolate, urgency: .soon,
                message: "Projet de grossesse sans folate — commencez la supplémentation 3 mois avant la conception (400-600µg/jour)."
            ))
        }

        // Very heavy periods without iron
        if profile.periodFlow == "very_heavy" && !hasSupplement("iron") {
            flags.append(RedFlag(
                id: .heavyPeriodsNoIron, urgency: .soon,
                message: "Règles très abondantes sans supplément de fer — risque élevé d'anémie. Faites un dosage de ferritine."
            ))
        }

        // Very heavy periods + vegan/vegetarian
        if profile.periodFlow == "very_heavy" && ["vegan", "vegetarien", "vegetarian"].contains(diet) {
            flags.append(RedFlag(
                id: .heavyPeriodsPlantBased, urgency: .soon,
                message: "Règles abondantes + régime végétarien = double risque fer. Le fer non-héminique (végétal) est 3x moins absorbé."
            ))
        }

        // Unintentional weight loss
        if profile.weightTrend == "losing_unintentionally" {
            flags.append(RedFlag(
                id: .unintentionalWeightLoss, urgency: .soon,
                message: "Perte de poids involontaire — consultez un médecin pour écarter une cause sous-jacente."
            ))
        }

        // Celiac / Crohn's / UC = malabsorption
        if conditions.contains(where: { ["celiac", "crohns_uc"].contains($0) }) {
            flags.append(RedFlag(
                id: .malabsorptionCondition, urgency: .routine,
                message: "Maladie digestive diagnostiquée — malabsorption probable de fer, B12, calcium, zinc, vitamine D, folate. Suivi médical recommandé."
            ))
        }

        // PPI + metformin = double B12 depletion
        if medications.contains("ppi") && medications.contains("metformin") {
            flags.append(RedFlag(
                id: .ppiMetforminB12, urgency: .soon,
                message: "PPI + Metformine = double risque d'insuffisance en B12. Demandez un dosage sanguin de B12."
            ))
        }

        // Elderly polypharmacy (65+ with 3+ medications)
        if age >= 65 && medications.filter({ $0 != "none" }).count >= 3 {
            flags.append(RedFlag(
                id: .elderlyPolypharmacy, urgency: .routine,
                message: "Plus de 65 ans avec plusieurs médicaments — risque d'interactions nutriment-médicament. Parlez-en à votre pharmacien."
            ))
        }

        // Tingling + vegan/PPI/metformin = B12 neuropathy risk
        if symptoms.contains("tingling") &&
            (["vegan", "vegetarien"].contains(diet) || medications.contains("ppi") || medications.contains("metformin")) {
            flags.append(RedFlag(
                id: .tinglingB12Risk, urgency: .soon,
                message: "Fourmillements + facteurs de risque B12 — la neuropathie liée à un manque de B12 peut devenir irréversible. Consultez rapidement."
            ))
        }

        // Hair loss + iron risk signals
        if symptoms.contains("hair_loss") &&
            (profile.periodFlow == "heavy" || profile.periodFlow == "very_heavy" || ["vegan", "vegetarien"].contains(diet)) {
            flags.append(RedFlag(
                id: .hairLossIronRisk, urgency: .soon,
                message: "Perte de cheveux + signaux de risque fer — faites doser votre ferritine (cible > 50 µg/L pour les cheveux)."
            ))
        }

        return flags
    }
}
