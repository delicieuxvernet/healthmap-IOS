import XCTest
@testable import HealthMap

// MARK: - Opérations, antécédents et allergies : effet sur les scores
//
// Ajouté le 20 septembre 2026 avec les trois nouvelles questions médicales.
// Le risque principal n'est pas qu'une pénalité soit fausse, c'est qu'elle
// existe d'un côté du moteur et pas de l'autre : HealthCalculator sert les
// profils sans caddie, NutrientEngine ceux qui en ont un. Les deux passent
// désormais par la même fonction, et ces tests le vérifient plutôt que de
// faire confiance à la relecture.

final class MedicalHistoryPenaltiesTests: XCTestCase {

    private func profilNeutre() -> UserProfile {
        var p = UserProfile.empty
        p.completed = true
        p.age = "30"
        p.weight = "70"
        p.height = "175"
        p.gender = .homme
        p.dietType = "omnivore"
        return p
    }

    /// Applique le bloc partagé sur une base plate et renvoie les écarts.
    private func ecarts(_ modifier: (inout UserProfile) -> Void) -> [String: Int] {
        var profil = profilNeutre()
        modifier(&profil)

        var avec: [String: Int] = [:]
        NutrientEngine.applyMedicalHistoryPenalties(&avec, profile: profil)

        var sans: [String: Int] = [:]
        NutrientEngine.applyMedicalHistoryPenalties(&sans, profile: profilNeutre())

        var delta: [String: Int] = [:]
        for (nutriment, valeur) in avec {
            let base = sans[nutriment] ?? 70
            if valeur != base { delta[nutriment] = valeur - base }
        }
        return delta
    }

    // MARK: - Opérations

    func testEstomacDerive_coupeLaB12PlusFortQuUneInflammation() {
        let d = ecarts { $0.surgicalHistory = ["bariatric"] }
        XCTAssertEqual(d["vitB12"], -30)
        XCTAssertEqual(d["iron"], -20)
        XCTAssertEqual(d["calcium"], -15)
        XCTAssertEqual(d["vitD"], -15)
        XCTAssertEqual(d["zinc"], -15)
    }

    /// Estomac réduit ET estomac retiré, c'est le même mécanisme : on ne
    /// double pas la pénalité si les deux sont cochés.
    func testEstomacReduitEtRetire_nAdditionnentPas() {
        let seul = ecarts { $0.surgicalHistory = ["bariatric"] }
        let deux = ecarts { $0.surgicalHistory = ["bariatric", "gastrectomy"] }
        XCTAssertEqual(seul["vitB12"], deux["vitB12"])
        XCTAssertEqual(seul["iron"], deux["iron"])
    }

    func testIntestinGreleReseque_toucheB12VitDCalciumMagnesium() {
        let d = ecarts { $0.surgicalHistory = ["small_bowel_resection"] }
        XCTAssertEqual(d["vitB12"], -25)
        XCTAssertEqual(d["vitD"], -15)
        XCTAssertEqual(d["calcium"], -10)
        XCTAssertEqual(d["magnesium"], -10)
    }

    /// Une thyroïde retirée ne fabrique aucune pénalité : elle ouvre une
    /// précaution côté compléments, rien de plus.
    func testThyroideRetiree_neTouchePasLesScores() {
        XCTAssertTrue(ecarts { $0.surgicalHistory = ["thyroidectomy"] }.isEmpty)
    }

    // MARK: - Antécédents

    /// Cancer, reins et hémochromatose ne produisent AUCUN chiffre. C'est
    /// délibéré : le moteur n'a rien à calculer là-dessus.
    func testAntecedentsSensibles_neFabriquentAucunChiffre() {
        for antecedent in ["cancer_treatment", "cancer_history", "kidney_condition", "hemochromatosis"] {
            XCTAssertTrue(
                ecarts { $0.medicalHistory = [antecedent] }.isEmpty,
                "« \(antecedent) » ne doit toucher aucun score"
            )
        }
    }

    func testDiabete_retireDuMagnesium() {
        XCTAssertEqual(ecarts { $0.medicalHistory = ["diabetes"] }["magnesium"], -8)
    }

    // MARK: - Allergies

    func testAllergiePoisson_effondreLesOmega3() {
        let d = ecarts { $0.allergies = ["fish_shellfish"] }
        XCTAssertEqual(d["omega3"], -20)
        XCTAssertEqual(d["iodine"], -10)
        XCTAssertEqual(d["vitD"], -8)
    }

    func testAllergieLait_toucheLeCalciumEnPremier() {
        XCTAssertEqual(ecarts { $0.allergies = ["milk"] }["calcium"], -15)
    }

    /// Le blé se déclare de deux façons : régime « sans gluten » (choix unique
    /// historique) ou allergie. Les deux disent la même chose sur l'iode — la
    /// pénalité ne doit se compter qu'une fois.
    func testBleDeclareDeuxFois_neCompteLIodeQuUneSeuleFois() {
        var profil = profilNeutre()
        profil.dietType = "sans_gluten"
        profil.allergies = ["wheat_gluten"]

        var scores: [String: Int] = [:]
        NutrientEngine.applyMedicalHistoryPenalties(&scores, profile: profil)

        XCTAssertNil(
            scores["iodine"],
            "Le régime sans gluten porte déjà la pénalité iode en amont : le bloc allergies ne doit pas la reprendre"
        )
        XCTAssertEqual(scores["fiber"], 62)
        XCTAssertEqual(scores["iron"], 65)
    }

    /// Et sans régime sans gluten déclaré, l'allergie porte bien l'iode.
    func testBleEnAllergieSeule_porteLIode() {
        XCTAssertEqual(ecarts { $0.allergies = ["wheat_gluten"] }["iodine"], -5)
    }

    // MARK: - Parité des deux moteurs

    /// Le même profil, avec et sans caddie, doit encaisser l'opération des deux
    /// côtés. C'est le scénario qui a fait diverger les moteurs par le passé :
    /// une règle branchée d'un seul côté passe les deux suites de tests.
    func testLesDeuxMoteursEncaissentLOperation() {
        let caddie = ["oeufs": 6, "poulet": 3, "riz": 5]

        var refSansCaddie = profilNeutre()
        var refAvecCaddie = profilNeutre()
        refAvecCaddie.groceries = caddie

        var opSansCaddie = refSansCaddie
        opSansCaddie.surgicalHistory = ["bariatric"]
        var opAvecCaddie = refAvecCaddie
        opAvecCaddie.surgicalHistory = ["bariatric"]

        // Les profils de référence ne servent qu'à mesurer la baisse.
        refSansCaddie.surgicalHistory = []
        refAvecCaddie.surgicalHistory = []

        let baisseSansCaddie = (HealthCalculator.analyzeNutrientScores(profile: refSansCaddie)["vitB12"] ?? 0)
            - (HealthCalculator.analyzeNutrientScores(profile: opSansCaddie)["vitB12"] ?? 0)
        let baisseAvecCaddie = (HealthCalculator.analyzeNutrientScores(profile: refAvecCaddie)["vitB12"] ?? 0)
            - (HealthCalculator.analyzeNutrientScores(profile: opAvecCaddie)["vitB12"] ?? 0)

        XCTAssertGreaterThan(
            baisseSansCaddie, 0,
            "Sans caddie, l'opération doit faire baisser la B12 (HealthCalculator)"
        )
        XCTAssertGreaterThan(
            baisseAvecCaddie, 0,
            "Avec caddie, l'opération doit faire baisser la B12 (NutrientEngine)"
        )
    }

}
