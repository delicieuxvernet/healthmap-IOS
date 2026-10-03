import XCTest
@testable import HealthMap

/// Ce que « Tes apports » et « Conseil du jour » écrivent sur l'écran
/// d'accueil : les chiffres du registre, les mots de la fiche, et rien de ce
/// qui ne doit pas se lire par-dessus l'épaule.
final class ResumeWidgetsTests: XCTestCase {

    private func detail(_ facteurs: [(String, Int, SectionQuestionnaire)]) -> DetailApport {
        let contributions = facteurs.map { ContributionApport(libelle: $0.0, delta: $0.1, section: $0.2) }
        let brut = DetailApport.pointDeDepart + contributions.reduce(0) { $0 + $1.delta }
        return DetailApport(contributions: contributions, score: max(0, min(100, brut)))
    }

    /// Vitamine D 58, magnésium 74, fer 79 : la journée de la maquette.
    private var registreMaquette: [String: DetailApport] {
        [
            "vitD": detail([("Tes repas notés ces 14 derniers jours", -7, .journal),
                            ("Travail en intérieur", -5, .modeDeVie)]),
            "magnesium": detail([("Sport régulier", 4, .modeDeVie)]),
            "iron": detail([("Viande rouge chaque semaine", 9, .nutrition)]),
        ]
    }

    // MARK: - Tes apports

    func testLaLectureDeLaMaquette() throws {
        let lecture = try XCTUnwrap(ResumeWidgets.lecture(
            registre: registreMaquette,
            ordreBilan: ["iron", "vitD", "magnesium"],
            alimentsDuBilan: ["vitD": [AlimentV2(nom: "Sardines", icone: "fish"),
                                       AlimentV2(nom: "Œufs", icone: "egg"),
                                       AlimentV2(nom: "Lait enrichi", icone: "milk")]]
        ))
        XCTAssertEqual(lecture.apports.map(\.id), ["vitD", "magnesium", "iron"], "Le plus bas d'abord")
        XCTAssertEqual(lecture.apports.map(\.score), [58, 74, 79], "Les chiffres du registre, tels quels")
        XCTAssertEqual(lecture.apports.map(\.court), ["Vit. D", "Mg", "Fer"])
        XCTAssertEqual(lecture.verdict, "Ta vitamine D est un peu juste.")
        XCTAssertEqual(lecture.autres, "Magnésium et fer sont couverts.")
        XCTAssertEqual(lecture.statut, "un peu juste")
        XCTAssertEqual(lecture.cause, "Première cause : tes repas notés ces 14 derniers jours.")
        XCTAssertEqual(lecture.titreAliments, "Ce qui la remonte")
        XCTAssertEqual(lecture.aliments, [AlimentW(nom: "Sardines", illustration: "fluent_fish"),
                                          AlimentW(nom: "Œufs", illustration: "fluent_egg"),
                                          AlimentW(nom: "Lait enrichi", illustration: "fluent_milk")])
    }

    func testLeVerdictEstCeluiDeLaFiche() {
        let registre = registreMaquette
        let lecture = ResumeWidgets.lecture(registre: registre, ordreBilan: ["vitD", "magnesium", "iron"],
                                            alimentsDuBilan: [:])
        let fiche = LectureApport.verdict(id: "vitD", nom: "Vitamine D", detail: registre["vitD"]!)
        XCTAssertTrue(fiche.hasPrefix(lecture?.verdict ?? "-"), "Mêmes mots que la fiche : \(fiche)")
    }

    func testSansBilanLesTroisPlusBasDuRegistre() {
        var registre = registreMaquette
        registre["zinc"] = detail([("Peu de produits animaux", -30, .nutrition)])
        registre["calcium"] = detail([])
        let ids = ResumeWidgets.apports(registre: registre, ordreBilan: []).map(\.id)
        XCTAssertEqual(ids, ["zinc", "vitD", "calcium"])
    }

    func testUneCausePriveeNeSAfficheJamais() {
        // Un traitement pèse le plus : on ne le nomme pas, et on ne le
        // remplace pas par la deuxième cause (ce ne serait plus la « première »).
        let traitement = detail([("Metformine", -15, .medical), ("Beaucoup de café", -6, .nutrition)])
        XCTAssertNil(ResumeWidgets.cause(traitement))

        for (libelle, section) in [("Grossesse", SectionQuestionnaire.sante), ("Plus de 70 ans", .profil),
                                   ("Tabac", .modeDeVie), ("Alcool fréquent", .modeDeVie)] {
            XCTAssertNil(ResumeWidgets.cause(detail([(libelle, -12, section)])), libelle)
        }
        XCTAssertEqual(ResumeWidgets.cause(detail([("Jamais au soleil", -12, .modeDeVie)])),
                       "Première cause : jamais au soleil.")
    }

    func testUnApportCouvertNADePasDeCause() {
        // 70 + 8 − 3 = 75 : couvert, malgré un frein qu'on pourrait montrer.
        // (Le café seul ferait 67, encore « un peu juste ».)
        XCTAssertNil(ResumeWidgets.cause(detail([("Sport régulier", 8, .modeDeVie),
                                                 ("Beaucoup de café", -3, .nutrition)])))
    }

    func testLesVoisinsSAccordent() {
        func apport(_ id: String, _ score: Int) -> ApportW {
            ApportW(id: id, nom: ResumeWidgets.nom(id), court: ResumeWidgets.nomCourt(id), score: score)
        }
        let principal = apport("vitD", 52)
        XCTAssertEqual(ResumeWidgets.autres(principal: principal, secondaires: [apport("iron", 60)]),
                       "Fer est un peu juste aussi.")
        XCTAssertEqual(ResumeWidgets.autres(principal: principal, secondaires: [apport("magnesium", 80), apport("iron", 61)]),
                       "Magnésium est couvert, fer un peu juste.")
        XCTAssertEqual(ResumeWidgets.autres(principal: principal, secondaires: [apport("vitC", 90), apport("vitB12", 75)]),
                       "Vitamine C et vitamine B12 sont couvertes.")
        XCTAssertEqual(ResumeWidgets.autres(principal: principal, secondaires: [apport("omega3", 30), apport("fiber", 20)]),
                       "Oméga-3 et fibres sont bas.")
        XCTAssertNil(ResumeWidgets.autres(principal: principal, secondaires: []))
    }

    func testCeQuiRemonteSuitLeGenre() {
        XCTAssertEqual(ResumeWidgets.titreAliments("vitD"), "Ce qui la remonte")
        XCTAssertEqual(ResumeWidgets.titreAliments("iron"), "Ce qui le remonte")
        XCTAssertEqual(ResumeWidgets.titreAliments("iodine"), "Ce qui le remonte")
        XCTAssertEqual(ResumeWidgets.titreAliments("omega3"), "Ce qui les remonte")
    }

    func testSansAlimentDuBilanCeuxDeLaFiche() {
        let aliments = ResumeWidgets.aliments("vitD", duBilan: nil)
        XCTAssertEqual(aliments.map(\.nom), Fluent3D.foodSources(for: "vitD").map(\.label))
        XCTAssertTrue(aliments.allSatisfy { $0.illustration.hasPrefix("fluent_") })
    }

    // MARK: - Conseil du jour

    func testLesConseilsViennentDesGestesDeLaFiche() {
        let conseils = ResumeWidgets.conseils(registre: registreMaquette)
        XCTAssertEqual(conseils.count, 1, "Le journal n'est pas un conseil ; magnésium et fer sont couverts")
        let soleil = conseils[0]
        XCTAssertEqual(soleil.apport, "vitD")
        XCTAssertEqual(soleil.apportCourt, "Vit. D")
        XCTAssertEqual(soleil.texte, "Un quart d'heure dehors, bras découverts, en milieu de journée quand c'est possible.")
        XCTAssertEqual(soleil.court, "15 min dehors, bras découverts")
        XCTAssertEqual(soleil.points, 5, "Ce que le calcul rendrait sans ce facteur")
    }

    func testUnGesteCommunADeuxApportsNeCompteQuUneFois() {
        let registre = [
            "iron": detail([("Beaucoup de café", -20, .nutrition)]),
            "magnesium": detail([("Beaucoup de café", -8, .nutrition)]),
        ]
        let conseils = ResumeWidgets.conseils(registre: registre)
        XCTAssertEqual(conseils.map(\.apport), ["iron"], "Pour l'apport le plus bas")
    }

    func testNiTabacNiAlcoolDansUnConseil() {
        let registre = ["vitC": detail([("Tabac", -20, .modeDeVie), ("Alcool fréquent", -10, .modeDeVie)])]
        XCTAssertTrue(ResumeWidgets.conseils(registre: registre).isEmpty)
    }

    func testChaqueGesteAUneVersionCourte() {
        let libelles = ["Courses pauvres en poisson", "Beaucoup de café", "Végétarien", "Cuisson longue à l'eau",
                        "Peu de poisson", "Peu de produits laitiers", "Sel non iodé", "Pain blanc",
                        "Repas souvent pris dehors", "Peu de fermentés", "Stress élevé",
                        "Travail en intérieur", "Sport régulier"]
        for libelle in libelles {
            let geste = CauseApport.gesteHorsApp(pour: ContributionApport(libelle: libelle, delta: -5, section: .nutrition))
            guard let geste else { continue }
            XCTAssertFalse(geste.court.isEmpty, libelle)
            XCTAssertLessThanOrEqual(geste.court.count, 36, "Tient sur deux lignes d'écran verrouillé : \(geste.court)")
            XCTAssertFalse(geste.court.contains("—"))
        }
    }
}
