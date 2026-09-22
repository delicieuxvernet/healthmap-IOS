import XCTest
@testable import HealthMap

// MARK: - Audit de personnalisation, étape 2 : recalibrer (22 sept. 2026)
//
// L'audit a montré un calcul qui favorisait la vitamine D (en tête de 64 % des
// bilans) et qui ignorait ce que contient vraiment une portion. Ces tests
// tiennent les corrections :
//   · le soleil ne se compte qu'une fois (travail en intérieur OU exposition) ;
//   · une portion pèse selon sa richesse (sardines ≠ œufs, steak ≠ poulet) ;
//   · l'assiette pèse moitié moins pour la vitamine D, qui vient du soleil ;
//   · les besoins affichés sont ceux de la personne (sexe, âge, grossesse, règles).

final class CalculEtape2Tests: XCTestCase {

    private func adulte(femme: Bool = false, age: String = "30") -> UserProfile {
        var p = UserProfile.empty
        p.gender = femme ? .femme : .homme
        p.age = age; p.weight = "65"; p.height = "170"
        return p
    }

    private func libelles(_ detail: DetailApport?) -> [String] {
        detail?.contributions.map(\.libelle) ?? []
    }

    // MARK: Le soleil ne se compte qu'une fois

    func testLeTravailEnInterieurNeParleQueSansReponseSurLeSoleil() {
        var p = adulte()
        p.indoorWork = "yes"
        // Sans réponse sur le soleil : le travail en intérieur compte.
        XCTAssertTrue(libelles(HealthCalculator.registreApports(profile: p)["vitD"]).contains("Travail en intérieur"))
        // Avec une réponse : elle compte seule.
        p.sunExposure = "very_little"
        let vitD = HealthCalculator.registreApports(profile: p)["vitD"]
        XCTAssertFalse(libelles(vitD).contains("Travail en intérieur"))
        XCTAssertTrue(libelles(vitD).contains("Très peu de soleil"))
        XCTAssertEqual(vitD?.score, 50)
    }

    func testLeMoteurCaddieNeCompteLeSoleilQuUneFoisNonPlus() {
        var p = adulte()
        p.groceries = ["pommes": 3]
        p.indoorWork = "yes"
        p.sunExposure = "moderate"
        let vitD = NutrientEngine.registreApports(profile: p)["vitD"]
        XCTAssertFalse(libelles(vitD).contains("Travail en intérieur"))
        p.sunExposure = ""
        XCTAssertTrue(libelles(NutrientEngine.registreApports(profile: p)["vitD"]).contains("Travail en intérieur"))
    }

    // MARK: La richesse des aliments

    /// Chaque richesse désigne un aliment du catalogue, pour un apport dont il est
    /// bien une source, et vaut 0,5 ou 2 (1 est la valeur par défaut, jamais écrite).
    func testLaTableDesRichessesEstCoherenteAvecLeCatalogue() {
        for (id, poids) in GroceryCatalog.richesse {
            guard let item = GroceryCatalog.item(id: id) else { return XCTFail("\(id) absent du catalogue") }
            for (apport, valeur) in poids {
                XCTAssertTrue(item.nutrients.contains(apport), "\(id) n'est pas une source de \(apport)")
                XCTAssertTrue([0.5, 2].contains(valeur), "\(id).\(apport) = \(valeur)")
            }
        }
    }

    func testUnePortionPeseSelonSaRichesse() {
        XCTAssertEqual(GroceryCatalog.poids("sardines", .vitD), 2)
        XCTAssertEqual(GroceryCatalog.poids("oeufs", .vitD), 0.5)
        XCTAssertEqual(GroceryCatalog.poids("steak_hache", .vitB12), 1)
        XCTAssertEqual(GroceryCatalog.poids("escalopes_poulet", .vitB12), 0.5)
        XCTAssertEqual(GroceryCatalog.poids("lentilles", .fiber), 2)
        XCTAssertEqual(GroceryCatalog.poids("pommes", .fiber), 0.5)
        // Pas une source : aucun poids, quelle que soit la quantité.
        XCTAssertEqual(GroceryCatalog.poids("pates", .fiber), 0)
        XCTAssertEqual(GroceryCatalog.poids("inconnu", .iron), 0)
    }

    func testDesPortionsModestesNeValentPasDesPortionsRiches() {
        var poulet = adulte()
        poulet.groceries = ["escalopes_poulet": 5]
        var boeuf = adulte()
        boeuf.groceries = ["boeuf": 5]
        XCTAssertEqual(NutrientEngine.weeklyServings(poulet, .vitB12), 2.5)
        XCTAssertEqual(NutrientEngine.weeklyServings(boeuf, .vitB12), 5)
        XCTAssertLessThan(NutrientEngine.foodDelta(poulet, .vitB12), NutrientEngine.foodDelta(boeuf, .vitB12))
    }

    // MARK: Le poids de l'assiette pour la vitamine D

    func testLAssiettePeseMoitieMoinsPourLaVitamineD() {
        var p = adulte()
        p.groceries = ["pommes": 3]   // aucune source de vitamine D
        XCTAssertEqual(NutrientEngine.foodDeltaBrut(p, .vitD), -30)
        XCTAssertEqual(NutrientEngine.foodDelta(p, .vitD), -15)
        // Les autres apports gardent tout leur poids.
        XCTAssertEqual(NutrientEngine.foodDelta(p, .omega3), NutrientEngine.foodDeltaBrut(p, .omega3))
        // Deux poissons gras par semaine couvrent la cible de vitamine D.
        p.groceries = ["saumon": 1, "sardines": 1]
        XCTAssertGreaterThan(NutrientEngine.foodDelta(p, .vitD), 0)
    }

    // MARK: Les besoins de la personne

    func testLesBesoinsEnFerSuiventLeProfil() {
        XCTAssertEqual(BesoinsDeReference.besoin(.iron, profil: adulte()), 11)
        var femme = adulte(femme: true)
        femme.periodFlow = "normal"
        XCTAssertEqual(BesoinsDeReference.besoin(.iron, profil: femme), 11)
        femme.periodFlow = "very_heavy"
        XCTAssertEqual(BesoinsDeReference.besoin(.iron, profil: femme), 16)
        // Jamais posée (« na » par défaut) : on ne présume pas des règles légères.
        femme.periodFlow = "na"
        XCTAssertEqual(BesoinsDeReference.besoin(.iron, profil: femme), 16)
        var apres50 = adulte(femme: true, age: "58")
        apres50.periodFlow = "na"
        XCTAssertEqual(BesoinsDeReference.besoin(.iron, profil: apres50), 11)
        var enceinte = adulte(femme: true)
        enceinte.pregnancyStatus = "pregnant"
        XCTAssertEqual(BesoinsDeReference.besoin(.iron, profil: enceinte), 16)
    }

    func testLaGrossesseEtLAllaitementChangentLesBesoins() {
        var p = adulte(femme: true)
        XCTAssertEqual(BesoinsDeReference.besoin(.iodine, profil: p), 150)
        p.pregnancyStatus = "pregnant"
        XCTAssertEqual(BesoinsDeReference.besoin(.iodine, profil: p), 200)
        XCTAssertEqual(BesoinsDeReference.besoin(.vitB12, profil: p), 4.5)
        p.pregnancyStatus = "breastfeeding"
        XCTAssertEqual(BesoinsDeReference.besoin(.vitC, profil: p), 155)
        // Un homme n'est jamais « enceinte », même si la réponse traîne.
        var homme = adulte()
        homme.pregnancyStatus = "pregnant"
        XCTAssertEqual(BesoinsDeReference.besoin(.iodine, profil: homme), 150)
    }

    func testLeZincDependDeLAlimentation() {
        var p = adulte()
        XCTAssertEqual(BesoinsDeReference.besoin(.zinc, profil: p), 11.7, accuracy: 0.001)
        p.dietType = "vegan"
        XCTAssertEqual(BesoinsDeReference.besoin(.zinc, profil: p), 14, accuracy: 0.001)
    }

    /// Chaque apport a un besoin positif, et le facteur ramène la référence
    /// générique (celle des repas analysés) au besoin de la personne.
    func testChaqueApportAUnBesoinEtUnFacteur() {
        for profil in [adulte(), adulte(femme: true), adulte(femme: true, age: "70")] {
            for id in NutrientID.allCases {
                XCTAssertGreaterThan(BesoinsDeReference.besoin(id, profil: profil), 0, id.rawValue)
            }
        }
        XCTAssertEqual(BesoinsDeReference.facteur(.iron, profil: adulte()), 18.0 / 11.0, accuracy: 0.0001)
    }

    // MARK: Le cache du bilan

    func testLaVersionDuCalculAChangeAvecLEtape2() {
        XCTAssertNotEqual(CalculApports.version, "2026-09-22")
    }
}
