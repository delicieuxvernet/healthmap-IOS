import XCTest
@testable import HealthMap

// MARK: - Les mots du nouveau questionnaire
//
// Le nouvel écran peut changer un mot, jamais une valeur : ce qu'il écrit dans
// le profil doit rester une option de `QuestionnaireSection`.
final class LibellesBilanTests: XCTestCase {

    private var questionsAChoix: [Question] {
        QuestionnaireSection.allQuestions.filter { $0.options != nil }
    }

    func testChaqueSurchargeDesigneUneOptionQuiExiste() {
        for (question, valeurs) in LibellesBilan.surcharges {
            let options = Set(QuestionnaireSection.optionPairs(id: question).map { $0.0 })
            XCTAssertFalse(options.isEmpty, "surcharge pour une question inconnue : \(question)")
            for valeur in valeurs.keys {
                XCTAssertTrue(options.contains(valeur), "\(question) : « \(valeur) » n'est pas une option")
            }
        }
    }

    func testLesChoixSontExactementLesOptions() {
        for question in questionsAChoix {
            let attendues = question.options?.map(\.id) ?? []
            let affichees = LibellesBilan.choix(question.id).map(\.id)
            XCTAssertEqual(affichees.count, attendues.count, question.id)
            XCTAssertEqual(Set(affichees), Set(attendues), question.id)
        }
    }

    func testAucunTitreNEstVide() {
        for question in questionsAChoix {
            for choix in LibellesBilan.choix(question.id) {
                XCTAssertFalse(choix.titre.isEmpty, "\(question.id) / \(choix.id)")
            }
        }
    }

    func testAucunPasseEnDernierDansLesListesACocher() {
        for question in questionsAChoix {
            guard case .multiChoice = question.type else { continue }
            let ids = LibellesBilan.choix(question.id).map(\.id)
            if ids.contains("none") {
                XCTAssertEqual(ids.last, "none", question.id)
            }
        }
    }

    /// Hors « aucun », l'ordre reste celui du questionnaire : une échelle
    /// (stress, sommeil, eau) se lit toujours dans le même sens.
    func testLOrdreDesChoixUniquesEstCeluiDuQuestionnaire() {
        for question in questionsAChoix {
            guard case .singleChoice = question.type else { continue }
            XCTAssertEqual(LibellesBilan.choix(question.id).map(\.id), question.options?.map(\.id), question.id)
        }
    }

    func testUneQuestionInconnueNARien() {
        XCTAssertTrue(LibellesBilan.choix("inconnue").isEmpty)
        XCTAssertTrue(LibellesBilan.choix("firstName").isEmpty)
        XCTAssertEqual(LibellesBilan.titre("alcohol", "regular"), "Régulier")
        XCTAssertEqual(LibellesBilan.titre("alcohol", "???"), "???")
    }

    // MARK: Le poids

    func testLesCinqTendancesDuPoidsSontAtteignables() {
        var atteintes: Set<String> = []
        for sens in LibellesBilan.SensDuPoids.allCases {
            for voulu in [true, false] {
                if let valeur = LibellesBilan.tendance(sens, voulu: voulu) { atteintes.insert(valeur) }
            }
        }
        XCTAssertEqual(atteintes, Set(QuestionnaireSection.optionPairs(id: "weightTrend").map { $0.0 }))
    }

    func testLaTendanceAttendLaReponseAVoulu() {
        XCTAssertEqual(LibellesBilan.tendance(.stable, voulu: nil), "stable")
        XCTAssertNil(LibellesBilan.tendance(.baisse, voulu: nil))
        XCTAssertNil(LibellesBilan.tendance(.hausse, voulu: nil))
        XCTAssertEqual(LibellesBilan.tendance(.baisse, voulu: false), "losing_unintentionally")
        XCTAssertEqual(LibellesBilan.tendance(.hausse, voulu: true), "gaining_intentionally")
    }

    func testUneTendanceEnregistreeSeRelit() {
        for (valeur, _) in QuestionnaireSection.optionPairs(id: "weightTrend") {
            guard let sens = LibellesBilan.sens(de: valeur) else {
                XCTFail("sens inconnu pour \(valeur)")
                continue
            }
            XCTAssertEqual(LibellesBilan.tendance(sens, voulu: LibellesBilan.voulu(de: valeur)), valeur)
        }
        XCTAssertNil(LibellesBilan.sens(de: ""))
        XCTAssertNil(LibellesBilan.voulu(de: "stable"))
    }

    // MARK: La peau

    func testChaqueTypeDePeauASaNuance() {
        let types = Set(QuestionnaireSection.optionPairs(id: "skinType").map { $0.0 })
        XCTAssertEqual(Set(LibellesBilan.nuancesDePeau.keys), types)
    }
}
