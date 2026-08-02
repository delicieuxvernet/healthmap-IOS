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
                message: "Tu manges végé sans B12 en soutien. Sur la durée, ça compte vraiment : la B12 ne se trouve pas dans les végétaux."
            ))
        }

        // Pregnant without folate
        if profile.pregnancyStatus == "pregnant" && !hasSupplement("folate") {
            flags.append(RedFlag(
                id: .pregnantNoFolate, urgency: .immediate,
                message: "Enceinte sans folate : parles-en à ton médecin dès maintenant. Le folate est essentiel au développement du bébé."
            ))
        }

        // Pregnant + smoking
        if profile.pregnancyStatus == "pregnant" && profile.isSmoker {
            flags.append(RedFlag(
                id: .pregnantSmoking, urgency: .immediate,
                message: "Enceinte et fumeuse : c'est un risque important pour le bébé. Parles-en à ton médecin sans attendre."
            ))
        }

        // Trying to conceive without folate
        if profile.pregnancyStatus == "trying_to_conceive" && !hasSupplement("folate") {
            flags.append(RedFlag(
                id: .tryingConceiveNoFolate, urgency: .soon,
                message: "Projet de grossesse sans folate. L'idéal est de commencer 3 mois avant, entre 400 et 600 µg par jour."
            ))
        }

        // Very heavy periods without iron
        if profile.periodFlow == "very_heavy" && !hasSupplement("iron") {
            flags.append(RedFlag(
                id: .heavyPeriodsNoIron, urgency: .soon,
                message: "Règles abondantes et pas de fer en soutien, tes réserves s'épuisent vite. Une prise de sang (ferritine) te donnera une réponse claire."
            ))
        }

        // Very heavy periods + vegan/vegetarian
        if profile.periodFlow == "very_heavy" && ["vegan", "vegetarien", "vegetarian"].contains(diet) {
            flags.append(RedFlag(
                id: .heavyPeriodsPlantBased, urgency: .soon,
                message: "Règles abondantes et régime végétarien, le fer est doublement sollicité. Celui des végétaux s'absorbe environ 3 fois moins bien."
            ))
        }

        // Unintentional weight loss
        if profile.weightTrend == "losing_unintentionally" {
            flags.append(RedFlag(
                id: .unintentionalWeightLoss, urgency: .soon,
                message: "Tu perds du poids sans le chercher. Ça mérite un avis médical, sans attendre."
            ))
        }

        // Celiac / Crohn's / UC = malabsorption
        if conditions.contains(where: { ["celiac", "crohns_uc"].contains($0) }) {
            flags.append(RedFlag(
                id: .malabsorptionCondition, urgency: .routine,
                message: "Avec un intestin fragile, le fer, la B12, le calcium, le zinc, la vitamine D et les folates passent moins bien. Un suivi médical fait la différence."
            ))
        }

        // PPI + metformin = double B12 depletion
        if medications.contains("ppi") && medications.contains("metformin") {
            flags.append(RedFlag(
                id: .ppiMetforminB12, urgency: .soon,
                message: "Ton anti-acide et ta metformine freinent chacun la B12. Un dosage sanguin permet de faire le point."
            ))
        }

        // Elderly polypharmacy (65+ with 3+ medications)
        if age >= 65 && medications.filter({ $0 != "none" }).count >= 3 {
            flags.append(RedFlag(
                id: .elderlyPolypharmacy, urgency: .routine,
                message: "Plusieurs médicaments en même temps, certains peuvent gêner l'absorption de tes nutriments. Ton pharmacien peut vérifier ça avec toi."
            ))
        }

        // Tingling + vegan/PPI/metformin = B12 neuropathy risk
        if symptoms.contains("tingling") &&
            (["vegan", "vegetarien"].contains(diet) || medications.contains("ppi") || medications.contains("metformin")) {
            flags.append(RedFlag(
                id: .tinglingB12Risk, urgency: .soon,
                message: "Des fourmillements alors que ta B12 est à risque, c'est à voir vite. Les nerfs récupèrent mal si on laisse traîner."
            ))
        }

        // Hair loss + iron risk signals
        if symptoms.contains("hair_loss") &&
            (profile.periodFlow == "heavy" || profile.periodFlow == "very_heavy" || ["vegan", "vegetarien"].contains(diet)) {
            flags.append(RedFlag(
                id: .hairLossIronRisk, urgency: .soon,
                message: "Tes cheveux tombent et plusieurs signaux pointent le fer. Fais doser ta ferritine, on vise plus de 50 µg/L pour les cheveux."
            ))
        }

        // Digestive bleeding — red flag transversal majeur (melena/rectorragie).
        // Ne jamais conclure à un apport insuffisant en fer seul : cause sous-jacente à écarter
        // (ulcère, polype, néoplasie). Mirror exact de health.js (web).
        if symptoms.contains("digestive_bleeding") {
            flags.append(RedFlag(
                id: .digestiveBleeding, urgency: .immediate,
                message: "Selles noires ou du sang dans les selles, consulte vite un médecin. Il faut chercher la cause côté digestif avant toute conclusion sur ton alimentation."
            ))
        }

        return flags
    }
}
