import XCTest
@testable import HealthMap

// MARK: - Audit de personnalisation, étape 1 : réparer le calcul (22 sept. 2026)
//
// Arthur : « est-ce que toutes les données du questionnaire sont bien prises en
// compte ? ». L'audit a trouvé des réponses mal lues ; ces tests tiennent les
// corrections :
//   · une quantité jamais posée (courses sautées) n'est plus un zéro ;
//   · le moteur « caddie » lit le type de pain, les abats et le bonus fer +
//     vitamine C, quand le caddie ne dit rien de lui-même ;
//   · l'Express pose la grossesse et les règles aux femmes ;
//   · le cache du bilan suit la version du calcul.

final class CalculEtape1Tests: XCTestCase {

    private func adulte(femme: Bool = false) -> UserProfile {
        var p = UserProfile.empty
        p.gender = femme ? .femme : .homme
        p.age = "30"; p.weight = "70"; p.height = "175"
        return p
    }

    private func libelles(_ registre: [String: DetailApport], _ id: String) -> [String] {
        registre[id]?.contributions.map(\.libelle) ?? []
    }

    // MARK: Les courses sautées

    /// Personne n'a répondu aux dix anciennes quantités : aucun « zéro » inventé.
    func testUneQuantiteJamaisPoseeNEstPasUnZero() {
        let registre = HealthCalculator.registreApports(profile: adulte())
        let tous = registre.values.flatMap(\.contributions).map(\.libelle)
        for inventee in ["Ni viande, ni œufs, ni poisson", "Très peu de produits animaux", "Pas de viande",
                         "Pas de poisson gras", "Très peu de fruits", "Très peu de légumes",
                         "Très peu de produits laitiers"] {
            XCTAssertFalse(tous.contains(inventee), inventee)
        }
        // Un adulte sans réponse particulière reste au point de départ sur ces six apports.
        for id in ["vitB12", "iron", "omega3", "vitC", "calcium", "zinc"] {
            XCTAssertEqual(registre[id]?.score, DetailApport.pointDeDepart, id)
        }
    }

    /// Un zéro DÉCLARÉ compte toujours.
    func testUnZeroDeclareCompteToujours() {
        var p = adulte()
        p.meatPoultry = "0"; p.fattyFish = "0"; p.eggsPerWeek = "0"
        p.dairyServings = "0"; p.fruitServings = "0"; p.vegetableServings = "0"
        let registre = HealthCalculator.registreApports(profile: p)
        XCTAssertTrue(libelles(registre, "vitB12").contains("Ni viande, ni œufs, ni poisson"))
        XCTAssertTrue(libelles(registre, "iron").contains("Pas de viande"))
        XCTAssertTrue(libelles(registre, "omega3").contains("Pas de poisson gras"))
        XCTAssertTrue(libelles(registre, "vitC").contains("Très peu de fruits"))
        XCTAssertTrue(libelles(registre, "calcium").contains("Très peu de produits laitiers"))
        XCTAssertTrue(libelles(registre, "zinc").contains("Pas de viande"))
    }

    // MARK: Le moteur caddie

    private func avecCaddie(_ caddie: [String: Int]) -> UserProfile {
        var p = adulte()
        p.groceries = caddie
        return p
    }

    func testLeTypeDePainCompteQuandLeCaddieNEnDitRien() {
        var p = avecCaddie(["pommes": 3, "lentilles": 2])
        p.breadType = "sourdough"
        let registre = NutrientEngine.registreApports(profile: p)
        XCTAssertTrue(registre["fiber"]?.contributions.contains { $0.libelle == "Pain complet ou au levain" && $0.delta == 10 } == true)
        XCTAssertTrue(registre["zinc"]?.contributions.contains { $0.libelle == "Pain au levain" && $0.delta == 5 } == true)
        // Le caddie contient du pain : c'est lui qui parle, la réponse se tait.
        p.groceries["pain_levain"] = 4
        let avecPain = NutrientEngine.registreApports(profile: p)
        XCTAssertFalse(avecPain["fiber"]?.contributions.contains { $0.libelle == "Pain complet ou au levain" } == true)
    }

    func testLesAbatsComptentQuandLeCaddieNEnDitRien() {
        var p = avecCaddie(["pommes": 3])
        p.eatLiver = "yes"
        let registre = NutrientEngine.registreApports(profile: p)
        XCTAssertTrue(registre["vitB12"]?.contributions.contains { $0.libelle == "Abats au menu" && $0.delta == 15 } == true)
        p.groceries["foie_volaille"] = 1
        XCTAssertFalse(NutrientEngine.registreApports(profile: p)["vitB12"]?.contributions.contains { $0.libelle == "Abats au menu" } == true)
    }

    func testLaVitamineCDuCaddieAideLeFer() {
        var caddie: [String: Int] = [:]
        for item in GroceryCatalog.items(providing: .vitC).prefix(2) { caddie[item.id] = 4 }
        let fer = NutrientEngine.registreApports(profile: avecCaddie(caddie))["iron"]
        XCTAssertTrue(fer?.contributions.contains { $0.libelle == "Fruits et légumes riches en vitamine C" && $0.delta == 5 } == true)
    }

    /// Les listes « pain » et « abats » du moteur existent dans le catalogue.
    func testLesPainsEtLesAbatsDuMoteurSontAuCatalogue() {
        let catalogue = Set(GroceryCatalog.aisles.flatMap(\.items).map(\.id))
        for id in NutrientEngine.painsDuCaddie + NutrientEngine.abatsDuCaddie {
            XCTAssertTrue(catalogue.contains(id), id)
        }
    }

    // MARK: L'Express

    func testLExpressPoseLaGrossesseEtLesReglesAuxFemmes() {
        let femme = adulte(femme: true)
        let homme = adulte()
        for id in ["pregnancyStatus", "periodFlow"] {
            XCTAssertTrue(QuestionnaireSection.expressKeys.contains(id), id)
            let question = QuestionnaireSection.question(id: id)
            XCTAssertEqual(question?.showIf?(femme), true, id)
            XCTAssertEqual(question?.showIf?(homme), false, id)
        }
    }

    // MARK: Le cache du bilan

    func testLeCacheDuBilanSuitLaVersionDuCalcul() {
        let p = adulte()
        XCTAssertEqual(AIAnalysisService.hashProfile(p), AIAnalysisService.hashProfile(p, calcul: CalculApports.version))
        XCTAssertNotEqual(AIAnalysisService.hashProfile(p, calcul: "ancien"), AIAnalysisService.hashProfile(p, calcul: "nouveau"))
    }
}
