import XCTest
@testable import HealthMap

// MARK: - Table symptôme → apport
// Valide le PRINCIPE autant que la table : le symptôme éclaire, il ne décide
// jamais. Une table qui trouve toujours quelque chose à dire n'est pas une
// table, c'est un horoscope — d'où les tests « ne dit rien ».

final class SymptomesApportsTests: XCTestCase {

    // MARK: - Ce qui se dit

    /// Lien fort : il se suffit à lui-même.
    func testLienFort_seDitSeul() {
        let phrase = SymptomesApports.explication(pour: .vitB12, symptomes: ["tingling"])
        XCTAssertNotNil(phrase)
        XCTAssertTrue(phrase!.contains("fourmillements"))
        XCTAssertTrue(phrase!.contains("Vitamine B12"))
    }

    /// Lien modéré : il se dit aussi, l'apport étant déjà établi comme bas.
    func testLienModere_seDit() {
        let phrase = SymptomesApports.explication(pour: .iron, symptomes: ["hair_loss"])
        XCTAssertNotNil(phrase)
        XCTAssertTrue(phrase!.contains("perte de cheveux"))
    }

    /// Un même symptôme peut éclairer plusieurs apports : on ne cite que
    /// celui dont on parle.
    func testMemeSymptome_plusieursApports() {
        for nutriment in [NutrientID.vitB12, .iron, .zinc] {
            let phrase = SymptomesApports.explication(pour: nutriment, symptomes: ["mouth_ulcers"])
            XCTAssertNotNil(phrase, "\(nutriment) devrait être éclairé par les aphtes")
            XCTAssertTrue(phrase!.contains("aphtes"))
        }
    }

    // MARK: - Ce qui ne se dit pas

    /// « Jamais seul » : un lien faible ne parle pas si rien d'autre ne parle.
    func testLienFaible_seul_neDitRien() {
        XCTAssertNil(SymptomesApports.explication(pour: .magnesium, symptomes: ["muscle_cramps"]))
        XCTAssertNil(SymptomesApports.explication(pour: .omega3, symptomes: ["dry_skin"]))
    }

    /// Accompagné d'un lien solide sur le même apport, il peut se joindre.
    func testLienFaible_accompagne_peutSeDire() {
        let phrase = SymptomesApports.explication(pour: .iron, symptomes: ["hair_loss", "brittle_nails"])
        XCTAssertNotNil(phrase)
        XCTAssertTrue(phrase!.contains("perte de cheveux"))
        XCTAssertTrue(phrase!.contains("ongles cassants"))
    }

    /// Les quatre symptômes volontairement muets.
    func testSymptomesMuets_neDeclenchentRien() {
        let muets = ["low_mood", "low_motivation", "digestive_bleeding", "none",
                     "bloating_frequent", "slow_digestion", "acid_reflux_feeling"]
        for nutriment in NutrientID.allCases {
            XCTAssertNil(
                SymptomesApports.explication(pour: nutriment, symptomes: muets),
                "\(nutriment) ne doit rien dire sur des symptômes muets"
            )
        }
    }

    func testAucunSymptome_neDitRien() {
        for nutriment in NutrientID.allCases {
            XCTAssertNil(SymptomesApports.explication(pour: nutriment, symptomes: []))
        }
    }

    // MARK: - Forme de la phrase

    /// On n'écrit jamais la causalité dans ce sens-là.
    func testPhrase_neDeduitJamaisDuSymptome() {
        let phrase = SymptomesApports.explication(pour: .iron, symptomes: ["hair_loss", "fatigue_chronic"])!
        XCTAssertTrue(phrase.contains("peut expliquer"))
        XCTAssertFalse(phrase.lowercased().contains("donc"))
        XCTAssertFalse(phrase.contains("  "))
        XCTAssertTrue(phrase.hasSuffix("."))
    }

    /// Deux symptômes au maximum : au-delà, le « pourquoi » devient une liste.
    func testPhrase_plafonneeADeuxSymptomes() {
        let phrase = SymptomesApports.explication(
            pour: .iron,
            symptomes: ["hair_loss", "fatigue_chronic", "mouth_ulcers", "brittle_nails", "feeling_cold"]
        )!
        XCTAssertEqual(phrase.components(separatedBy: " et ").count, 2, "une seule conjonction")
    }

    /// Un symptôme cité une fois, même s'il apparaît plusieurs fois en table.
    func testPhrase_pasDeDoublon() {
        let phrase = SymptomesApports.explication(pour: .iron, symptomes: ["mouth_ulcers"])!
        XCTAssertEqual(phrase.components(separatedBy: "aphtes").count, 2, "cité une seule fois")
    }

    // MARK: - Cohérence avec le questionnaire

    /// Anti-dérive : chaque symptôme de la table doit exister dans le
    /// questionnaire. Une liste recopiée finit toujours par diverger.
    func testTable_neReferenceQueDesSymptomesDuQuestionnaire() {
        let connus = Set(QuestionnaireSection.optionPairs(id: "symptoms").map { $0.0 })
        XCTAssertFalse(connus.isEmpty, "le questionnaire doit exposer ses symptômes")
        for lien in SymptomesApports.liens {
            XCTAssertTrue(connus.contains(lien.symptome), "\(lien.symptome) n'existe pas au questionnaire")
        }
    }

    /// Toute formulation est un groupe nominal non vide, en minuscule : elle
    /// s'insère dans « Tu as signalé … ».
    func testTable_formulationsInserables() {
        for lien in SymptomesApports.liens {
            XCTAssertFalse(lien.formulation.isEmpty)
            XCTAssertEqual(lien.formulation, lien.formulation.trimmingCharacters(in: .whitespaces))
            XCTAssertFalse(lien.formulation.hasSuffix("."))
            XCTAssertEqual(String(lien.formulation.prefix(1)), String(lien.formulation.prefix(1)).lowercased())
        }
    }

    /// Un même couple symptôme/apport ne figure qu'une fois.
    func testTable_pasDeLienEnDouble() {
        var vus = Set<String>()
        for lien in SymptomesApports.liens {
            let cle = "\(lien.symptome)|\(lien.nutriment.rawValue)"
            XCTAssertFalse(vus.contains(cle), "lien en double : \(cle)")
            vus.insert(cle)
        }
    }

    // MARK: - Intégration

    /// La phrase remonte bien dans le « pourquoi » de la recommandation.
    func testIntegration_leWhyPorteLExplication() {
        var profile = UserProfile.empty
        profile.completed = true
        profile.dietType = "omnivore"
        profile.age = "30"
        profile.gender = .homme
        profile.symptoms = ["tingling"]

        var scores: [String: Int] = [:]
        for n in NutrientID.allCases { scores[n.rawValue] = 75 }
        scores[NutrientID.vitB12.rawValue] = 25

        let recs = SupplementEngine.selectProducts(scores: scores, profile: profile)
        guard let b12 = recs.first(where: { $0.nutrientID == .vitB12 }) else {
            XCTFail("la B12 doit être recommandée"); return
        }
        XCTAssertTrue(b12.whyText.contains("fourmillements"), "le pourquoi doit porter le signal déclaré")
    }

    /// Sans symptôme déclaré, le « pourquoi » reste celui d'avant.
    func testIntegration_sansSymptome_leWhyNeChangePas() {
        var profile = UserProfile.empty
        profile.completed = true
        profile.dietType = "omnivore"
        profile.age = "30"
        profile.gender = .homme

        var scores: [String: Int] = [:]
        for n in NutrientID.allCases { scores[n.rawValue] = 75 }
        scores[NutrientID.vitB12.rawValue] = 25

        let recs = SupplementEngine.selectProducts(scores: scores, profile: profile)
        XCTAssertFalse(recs.first?.whyText.contains("Tu as signalé") ?? true)
    }
}
