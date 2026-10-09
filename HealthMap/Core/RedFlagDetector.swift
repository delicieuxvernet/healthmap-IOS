import Foundation

// MARK: - Red Flag Detector (exact translation of detectRedFlags in health.js)
//
// Mêmes règles de déclenchement que health.js. Les MESSAGES ont divergé le
// 9 octobre 2026 (audit de conformité, le web n'est plus maintenu) : un fait
// tiré des réponses, puis « parles-en à un professionnel de santé ». Aucun
// pronostic, aucun mot de risque, aucune promesse de ce qu'un suivi apporte.
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
                message: "Tu manges végé sans B12 en soutien, et la B12 ne se trouve pas dans les végétaux. Parles-en à un professionnel de santé."
            ))
        }

        // Pregnant without folate
        if profile.pregnancyStatus == "pregnant" && !hasSupplement("folate") {
            flags.append(RedFlag(
                id: .pregnantNoFolate, urgency: .immediate,
                message: "Enceinte, sans folate en soutien : parles-en dès maintenant à ton médecin ou à ta sage-femme."
            ))
        }

        // Pregnant + smoking
        if profile.pregnancyStatus == "pregnant" && profile.isSmoker {
            flags.append(RedFlag(
                id: .pregnantSmoking, urgency: .immediate,
                message: "Enceinte et fumeuse : parles-en sans attendre à ton médecin ou à ta sage-femme."
            ))
        }

        // Trying to conceive without folate
        if profile.pregnancyStatus == "trying_to_conceive" && !hasSupplement("folate") {
            flags.append(RedFlag(
                id: .tryingConceiveNoFolate, urgency: .soon,
                // Aucune dose dans Kiwio (doctrine du 20 sept. 2026) : la posologie
                // appartient au médecin ou au pharmacien.
                message: "Projet de grossesse, sans folate en soutien : parles-en à ton médecin ou à ton pharmacien."
            ))
        }

        // Very heavy periods without iron
        if profile.periodFlow == "very_heavy" && !hasSupplement("iron") {
            flags.append(RedFlag(
                id: .heavyPeriodsNoIron, urgency: .soon,
                message: "Règles abondantes et pas de fer en soutien : parles-en à un professionnel de santé."
            ))
        }

        // Very heavy periods + vegan/vegetarian
        if profile.periodFlow == "very_heavy" && ["vegan", "vegetarien", "vegetarian"].contains(diet) {
            flags.append(RedFlag(
                id: .heavyPeriodsPlantBased, urgency: .soon,
                message: "Règles abondantes et régime végétarien : le fer des végétaux s'absorbe moins bien que celui de la viande. Parles-en à un professionnel de santé."
            ))
        }

        // Unintentional weight loss
        if profile.weightTrend == "losing_unintentionally" {
            flags.append(RedFlag(
                id: .unintentionalWeightLoss, urgency: .soon,
                message: "Tu perds du poids sans le chercher : parles-en sans attendre à un professionnel de santé."
            ))
        }

        // Celiac / Crohn's / UC / pancreas = malabsorption
        if conditions.contains(where: { ["celiac", "crohns_uc", "pancreatic_insufficiency"].contains($0) }) {
            flags.append(RedFlag(
                id: .malabsorptionCondition, urgency: .routine,
                message: "Avec un intestin fragile, le fer, la B12, le calcium, le zinc, la vitamine D et les folates peuvent moins bien passer. Parles-en à un professionnel de santé."
            ))
        }

        // Opération lourde sur l'estomac ou l'intestin grêle : la B12 ne passe
        // plus par la voie normale, et ça ne se rattrape pas par l'assiette.
        let surgeries = profile.surgicalHistory
        if surgeries.contains(where: { ["bariatric", "gastrectomy", "small_bowel_resection"].contains($0) }) {
            flags.append(RedFlag(
                id: .majorDigestiveSurgery, urgency: .soon,
                message: "Après une opération qui touche l'estomac ou l'intestin grêle, la B12 peut moins bien s'absorber. Parles-en à ton médecin."
            ))
        }

        // Antécédents. Un traitement EN COURS ouvre une alerte ; un antécédent
        // ancien n'en ouvre pas — on n'alarme pas quelqu'un en rémission.
        let history = profile.medicalHistory
        if history.contains("cancer_treatment") {
            flags.append(RedFlag(
                id: .cancerFollowUp, urgency: .soon,
                message: "Pendant un traitement lourd, parles-en à ton équipe soignante avant de changer ton alimentation : ce que tu lis ici ne remplace pas son avis."
            ))
        }
        if history.contains("hemochromatosis") {
            flags.append(RedFlag(
                id: .hemochromatosisIron, urgency: .routine,
                message: "Avec une hémochromatose, Kiwio ne te propose jamais de fer. Les multivitamines en contiennent souvent : parles-en à ton médecin."
            ))
        }
        if history.contains("kidney_condition") {
            flags.append(RedFlag(
                id: .kidneySupplementCaution, urgency: .routine,
                message: "Avec des reins fragiles, demande l'avis de ton médecin avant de prendre un complément."
            ))
        }

        // PPI + metformin = double B12 depletion
        if medications.contains("ppi") && medications.contains("metformin") {
            flags.append(RedFlag(
                id: .ppiMetforminB12, urgency: .soon,
                message: "Ton anti-acide et ta metformine peuvent chacun freiner l'absorption de la B12 : parles-en à ton médecin ou à ton pharmacien."
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
                message: "Des fourmillements, et plusieurs de tes réponses qui pèsent sur la B12 : parles-en vite à un professionnel de santé."
            ))
        }

        // Hair loss + iron risk signals
        if symptoms.contains("hair_loss") &&
            (profile.periodFlow == "heavy" || profile.periodFlow == "very_heavy" || ["vegan", "vegetarien"].contains(diet)) {
            flags.append(RedFlag(
                id: .hairLossIronRisk, urgency: .soon,
                message: "Tes cheveux tombent, et plusieurs de tes réponses pèsent sur le fer : parles-en à un professionnel de santé."
            ))
        }

        // Digestive bleeding — red flag transversal majeur (melena/rectorragie).
        // Ne jamais conclure à un apport insuffisant en fer seul : cause sous-jacente à écarter
        // (ulcère, polype, néoplasie). Mirror exact de health.js (web).
        if symptoms.contains("digestive_bleeding") {
            flags.append(RedFlag(
                id: .digestiveBleeding, urgency: .immediate,
                message: "Selles noires ou du sang dans les selles : consulte un médecin sans attendre. Kiwio n'en tire aucune conclusion sur ton alimentation."
            ))
        }

        return flags
    }
}
