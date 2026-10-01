import XCTest
@testable import HealthMap

/// Le poids souhaité donne le SENS de l'objectif ; les calories et les macros
/// sortent des formules existantes. Ces tests verrouillent trois choses : sans
/// poids souhaité rien ne change, l'écart choisit le bon objectif, et les deux
/// réserves (corpulence, grossesse) retiennent le déficit.
final class ObjectifPoidsTests: XCTestCase {

    private func profil(
        poids: String,
        souhaite: String = "",
        taille: String = "175",
        genre: UserProfile.Gender = .homme,
        objectifs: [String] = ["energie"]
    ) -> UserProfile {
        var p = UserProfile()
        p.weight = poids
        p.targetWeight = souhaite
        p.height = taille
        p.age = "30"
        p.gender = genre
        p.goals = objectifs
        p.strengthTraining = "moderate"
        return p
    }

    // MARK: - Sans poids souhaité : comme avant

    func testSansPoidsSouhaiteLesCiblesSuiventLObjectifDuQuestionnaire() throws {
        let p = profil(poids: "80", objectifs: ["perte_poids"])
        XCTAssertNil(ObjectifPoids(profile: p))

        let mesures = PhysicalMetrics(profile: p)
        XCTAssertNil(mesures.objectifPoids)
        let attendu = try XCTUnwrap(HealthCalculator.calculateMacros(tdee: mesures.tdee, goal: "perte_poids", weightKg: 80))
        XCTAssertEqual(mesures.macros?.calories, attendu.calories)
        XCTAssertEqual(mesures.macros?.protein, attendu.protein)
    }

    func testUnPoidsSouhaiteVideOuNulNEstPasUnObjectif() {
        XCTAssertNil(profil(poids: "80", souhaite: "").targetWeightDouble)
        XCTAssertNil(profil(poids: "80", souhaite: "0").targetWeightDouble)
        XCTAssertNil(profil(poids: "80", souhaite: "abc").targetWeightDouble)
        XCTAssertEqual(profil(poids: "80", souhaite: "72.5").targetWeightDouble, 72.5)
    }

    // MARK: - Le sens

    func testViserPlusBasDonneUnDeficit() throws {
        let p = profil(poids: "80", souhaite: "75")
        let objectif = try XCTUnwrap(ObjectifPoids(profile: p))
        XCTAssertEqual(objectif.sens, .perdre)
        XCTAssertNil(objectif.reserve)
        XCTAssertEqual(objectif.objectifDeCalcul(principal: "energie"), "perte_poids")

        let mesures = PhysicalMetrics(profile: p)
        let tdee = try XCTUnwrap(mesures.tdee)
        XCTAssertEqual(mesures.macros?.calories, tdee - 400)
    }

    func testViserPlusHautDonneUnSurplus() throws {
        let p = profil(poids: "70", souhaite: "75")
        let objectif = try XCTUnwrap(ObjectifPoids(profile: p))
        XCTAssertEqual(objectif.sens, .prendre)
        XCTAssertEqual(objectif.objectifDeCalcul(principal: "perte_poids"), "prise_masse")

        let mesures = PhysicalMetrics(profile: p)
        let tdee = try XCTUnwrap(mesures.tdee)
        XCTAssertEqual(mesures.macros?.calories, tdee + 300)
    }

    func testMoinsDUnDemiKiloDEcartCEstLeMaintien() throws {
        let objectif = try XCTUnwrap(ObjectifPoids(profile: profil(poids: "75", souhaite: "75.3")))
        XCTAssertEqual(objectif.sens, .maintenir)
        // « Perdre du poids » n'a plus lieu d'être : la personne y est.
        XCTAssertNil(objectif.objectifDeCalcul(principal: "perte_poids"))
        // Les autres objectifs du questionnaire restent lus.
        XCTAssertEqual(objectif.objectifDeCalcul(principal: "muscle"), "muscle")

        let pile = try XCTUnwrap(ObjectifPoids(profile: profil(poids: "75", souhaite: "74.5")))
        XCTAssertEqual(pile.sens, .perdre, "Un demi-kilo pile est déjà un écart.")
    }

    func testLePoidsSouhaiteLEmporteSurLObjectifCoche() throws {
        // « Perdre du poids » coché, mais le poids souhaité est atteint.
        let p = profil(poids: "75", souhaite: "75", objectifs: ["perte_poids"])
        let mesures = PhysicalMetrics(profile: p)
        XCTAssertEqual(mesures.macros?.calories, mesures.tdee)
    }

    // MARK: - Les réserves

    func testPasDeDeficitVersUnPoidsSousLeRepereDeCorpulence() throws {
        // 55 kg pour 1,75 m : IMC 18,0.
        let p = profil(poids: "60", souhaite: "55")
        let objectif = try XCTUnwrap(ObjectifPoids(profile: p))
        XCTAssertEqual(objectif.reserve, .sousLeRepere)
        XCTAssertEqual(objectif.sens, .maintenir)

        let mesures = PhysicalMetrics(profile: p)
        XCTAssertEqual(mesures.macros?.calories, mesures.tdee)
        XCTAssertTrue(objectif.phrase(calories: mesures.macros?.calories, tdee: mesures.tdee).contains("professionnel de santé"))
    }

    func testPasDeDeficitEnceinteOuAllaitante() throws {
        for statut in ["pregnant", "breastfeeding"] {
            var p = profil(poids: "70", souhaite: "65", taille: "165", genre: .femme)
            p.pregnancyStatus = statut
            let objectif = try XCTUnwrap(ObjectifPoids(profile: p))
            XCTAssertEqual(objectif.reserve, .grossesse, statut)
            XCTAssertEqual(objectif.sens, .maintenir, statut)
        }
    }

    func testLesReservesNeRetiennentPasUnePrise() throws {
        var p = profil(poids: "50", souhaite: "54", taille: "175", genre: .femme)
        p.pregnancyStatus = "pregnant"
        let objectif = try XCTUnwrap(ObjectifPoids(profile: p))
        XCTAssertEqual(objectif.sens, .prendre)
        XCTAssertNil(objectif.reserve)
    }

    // MARK: - Le rythme

    func testLeRythmeVientDeLEcartDeCalories() throws {
        let objectif = try XCTUnwrap(ObjectifPoids(profile: profil(poids: "80", souhaite: "75")))
        let rythme = try XCTUnwrap(objectif.rythmeHebdo(calories: 2_100, tdee: 2_500))
        XCTAssertEqual(rythme, -0.3636, accuracy: 0.001)

        // 5 kg à 0,36 kg par semaine : un peu moins de 14 semaines.
        let depart = Date(timeIntervalSince1970: 1_790_000_000)
        let date = try XCTUnwrap(objectif.dateEstimee(calories: 2_100, tdee: 2_500, depuis: depart))
        let jours = Calendar.current.dateComponents([.day], from: depart, to: date).day
        XCTAssertEqual(jours, 96)

        // Des calories qui vont à contresens ne donnent pas de rythme.
        XCTAssertNil(objectif.rythmeHebdo(calories: 2_600, tdee: 2_500))
    }

    func testLaPhraseDitLeRythmeEtLEcheance() throws {
        let objectif = try XCTUnwrap(ObjectifPoids(profile: profil(poids: "80", souhaite: "75")))
        let phrase = objectif.phrase(calories: 2_100, tdee: 2_500)
        XCTAssertTrue(phrase.contains("0,4 kg de moins par semaine"), phrase)
        XCTAssertTrue(phrase.contains("75 kg vers le"), phrase)

        let maintien = try XCTUnwrap(ObjectifPoids(profile: profil(poids: "75", souhaite: "75")))
        XCTAssertTrue(maintien.phrase(calories: 2_500, tdee: 2_500).contains("maintien"))
    }

    // MARK: - Formats et réglage

    func testLesFormats() {
        XCTAssertEqual(ObjectifPoids.affichage(74), "74,0")
        XCTAssertEqual(ObjectifPoids.affichage(74.25), "74,3")
        XCTAssertEqual(ObjectifPoids.affichageCourt(70), "70")
        XCTAssertEqual(ObjectifPoids.affichageCourt(70.5), "70,5")
        // Ce qui part dans le profil se relit comme un nombre.
        XCTAssertEqual(ObjectifPoids.stockage(74), "74")
        XCTAssertEqual(ObjectifPoids.stockage(74.5), "74.5")
        XCTAssertEqual(Double(ObjectifPoids.stockage(73.9)), 73.9)
    }

    func testUnPasResteDansLesBornesEtSansPoussiereDeVirgule() {
        XCTAssertEqual(ObjectifPoids.decale(73.9, de: 0.1), 74.0)
        XCTAssertEqual(ObjectifPoids.decale(74.0, de: -0.1), 73.9)
        XCTAssertEqual(ObjectifPoids.decale(30, de: -0.1), 30)
        XCTAssertEqual(ObjectifPoids.decale(250, de: 0.1), 250)

        // Cent pas de 100 g font dix kilos, pas 9,99999.
        var kilos = 70.0
        for _ in 0..<100 { kilos = ObjectifPoids.decale(kilos, de: 0.1) }
        XCTAssertEqual(kilos, 80.0)
    }

    // MARK: - Profil enregistré

    func testLePoidsSouhaiteSurvitAUnAllerRetour() throws {
        var p = profil(poids: "80", souhaite: "72.5")
        p.completed = true
        let relu = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(relu.targetWeight, "72.5")
        XCTAssertEqual(relu.weight, "80")
        XCTAssertEqual(ObjectifPoids(profile: relu)?.sens, .perdre)
    }

    func testUnProfilDAvantSeLitSansPoidsSouhaite() throws {
        let ancien = Data(#"{"weight":"80","height":"175","completed":true}"#.utf8)
        let relu = try JSONDecoder().decode(UserProfile.self, from: ancien)
        XCTAssertEqual(relu.targetWeight, "")
        XCTAssertNil(ObjectifPoids(profile: relu))
    }
}
