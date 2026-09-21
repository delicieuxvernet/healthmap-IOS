import XCTest
@testable import HealthMap

// MARK: - La fiche d'un repas (21 sept. 2026)
//
// Moteur pur : on fabrique les saisies d'un créneau, on lit la fiche. Ce qui
// compte : la part se mesure sur la CIBLE du jour (jamais inventée), les
// apports s'additionnent saisie par saisie, et le constat ne conclut pas du vide.

final class FicheRepasTests: XCTestCase {

    private typealias Micro = MealJournalService.MicroPct

    private func saisie(_ id: String, aliments: [String], kcal: Int = 300,
                        prot: Double = 0, gluc: Double = 0, lip: Double = 0, fibres: Double = 0,
                        micros: [(String, Int)] = []) -> MealJournalService.MealRecord {
        MealJournalService.MealRecord(
            id: id, consumedAt: Date(), slot: .lunch, foods: aliments,
            macros: .init(calories: kcal, proteins: prot, carbs: gluc, fats: lip, fiber: fibres),
            micros: micros.map { Micro(id: $0.0, pctRDA: $0.1) }
        )
    }

    private func fiche(_ repas: [MealJournalService.MealRecord], bas: [String] = [],
                       cibles: (Int?, Int?, Int?) = (90, 200, 60)) -> FicheRepas {
        FicheRepas.calculer(repas: repas, cibleProteines: cibles.0, cibleGlucides: cibles.1,
                            cibleLipides: cibles.2, apportsARenforcer: bas)
    }

    func testLesSaisiesDuCreneauSAdditionnent() {
        let f = fiche([saisie("a", aliments: ["Poulet rôti"], kcal: 400, prot: 30),
                       saisie("b", aliments: ["Yaourt"], kcal: 120, prot: 12)])
        XCTAssertEqual(f.calories, 520)
        XCTAssertEqual(f.macros.first { $0.id == "proteines" }?.grammes, 42)
    }

    func testLaPartSeMesureSurLaCibleDuJour() {
        let f = fiche([saisie("a", aliments: ["Poulet"], prot: 42, gluc: 58)])
        XCTAssertEqual(f.macros.first { $0.id == "proteines" }?.partDeLaCible, 47)   // 42 / 90
        XCTAssertEqual(f.macros.first { $0.id == "glucides" }?.partDeLaCible, 29)    // 58 / 200
    }

    /// Sans cible connue, on ne montre que les grammes : jamais un objectif inventé.
    func testSansCiblePasDePart() {
        let f = fiche([saisie("a", aliments: ["Poulet"], prot: 42)], cibles: (nil, nil, nil))
        XCTAssertNil(f.macros.first { $0.id == "proteines" }?.partDeLaCible)
        // Les fibres gardent leur référence canonique.
        XCTAssertNotNil(f.macros.first { $0.id == "fibres" }?.partDeLaCible)
    }

    func testUnePartNeDepassePasCent() {
        XCTAssertEqual(FicheRepas.part(250, 90), 100)
        XCTAssertNil(FicheRepas.part(10, 0))
    }

    func testLesApportsSAdditionnentEtSeClassent() {
        let f = fiche([saisie("a", aliments: ["Poulet"], micros: [("iron", 25), ("zinc", 35)]),
                       saisie("b", aliments: ["Lentilles"], micros: [("iron", 15), ("calcium", 9)])])
        XCTAssertEqual(f.apports.map(\.id), ["iron", "zinc", "calcium"])
        XCTAssertEqual(f.apports.first?.part, 40)
        XCTAssertEqual(f.apports.first?.nom, "Fer")
    }

    func testLeResumeNommeTroisAlimentsPuisCompte() {
        XCTAssertEqual(FicheRepas.resume(["Poulet rôti", "Pâtes", "Yaourt"]), "Poulet rôti, Pâtes, Yaourt")
        XCTAssertEqual(FicheRepas.resume(["A", "B", "C", "D", "E"]), "A, B, C et 2 autres")
        XCTAssertEqual(FicheRepas.resume(["A", "B", "C", "D"]), "A, B, C et 1 autre")
        XCTAssertEqual(FicheRepas.resume([]), "")
    }

    // MARK: Le constat

    func testLeConstatNommeLApportARenforcerLaisseDeCote() {
        let f = fiche([saisie("a", aliments: ["Poulet"], micros: [("iron", 40), ("calcium", 4)])],
                      bas: ["iron", "calcium"])
        XCTAssertEqual(f.note, "Ce repas couvre très peu un de tes apports à renforcer : calcium.")
    }

    func testPasDeConstatQuandToutEstCouvert() {
        let f = fiche([saisie("a", aliments: ["Poulet"], micros: [("iron", 40)])], bas: ["iron"])
        XCTAssertNil(f.note)
    }

    /// Un repas sans détail d'apports (ajout manuel, ancienne saisie) : on ne
    /// conclut pas du vide qu'il ne couvre rien.
    func testPasDeConstatSansDetailDApports() {
        let f = fiche([saisie("a", aliments: ["Sandwich"])], bas: ["iron"])
        XCTAssertNil(f.note)
        XCTAssertTrue(f.apports.isEmpty)
    }

    /// Le constat nomme un état, jamais un geste : il est lisible en gratuit.
    func testLeConstatNeDonnePasDeGeste() {
        let note = fiche([saisie("a", aliments: ["Poulet"], micros: [("iron", 40)])], bas: ["vitD"]).note ?? ""
        XCTAssertTrue(note.hasSuffix("vitamine D."))
        for mot in ["ajoute", "mange", "prends", "essaie", "remplace"] {
            XCTAssertFalse(note.lowercased().contains(mot), "« \(mot) » est un geste")
        }
    }
}
