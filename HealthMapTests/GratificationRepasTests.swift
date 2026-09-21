import XCTest
@testable import HealthMap

// MARK: - Gratification après un ajout (20 sept. 2026)
//
// Moteur pur : on fabrique les repas à la main, on fixe « maintenant ». Ce qui
// compte : ne jamais fêter à vide, dire la vérité sur l'avant / après du JOUR,
// et ne nommer un aliment que s'il porte vraiment le gain.

final class GratificationRepasTests: XCTestCase {

    private let cal = Calendar.current
    private typealias Micro = MealJournalService.MicroPct

    private func date(jour: Int, heure: Int = 12) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = jour; c.hour = heure
        return cal.date(from: c)!
    }

    private func repas(_ id: String, jour: Int = 20, heure: Int = 12,
                       slot: MealJournalService.MealSlot = .lunch,
                       items: [MealJournalService.FoodEntry] = [],
                       micros: [(String, Int)]) -> MealJournalService.MealRecord {
        MealJournalService.MealRecord(id: id, consumedAt: date(jour: jour, heure: heure), slot: slot,
                                      items: items, macros: .init(calories: 500),
                                      micros: micros.map { Micro(id: $0.0, pctRDA: $0.1) })
    }

    private func aliment(_ nom: String, _ micros: [(String, Int)]) -> MealJournalService.FoodEntry {
        MealJournalService.FoodEntry(name: nom, micros: micros.map { Micro(id: $0.0, pctRDA: $0.1) })
    }

    private func calculer(_ nouveau: MealJournalService.MealRecord,
                          jour: [MealJournalService.MealRecord] = [],
                          bas: [String] = [],
                          quinzaine: [MealJournalService.MealRecord] = []) -> GratificationRepas? {
        GratificationRepas.calculer(nouveau: nouveau, repasDuJour: jour + [nouveau],
                                    apportsARenforcer: bas, quinzaine: quinzaine,
                                    maintenant: date(jour: 20, heure: 13), calendrier: cal)
    }

    // MARK: Avant → après

    func testLeGainPartDeCeQueLeJourCouvraitDeja() {
        let matin = repas("matin", heure: 8, slot: .breakfast, micros: [("iron", 42)])
        let resultat = calculer(repas("midi", micros: [("iron", 40)]), jour: [matin])
        XCTAssertEqual(resultat?.gains.first?.avant, 42)
        XCTAssertEqual(resultat?.gains.first?.apres, 82)
        XCTAssertEqual(resultat?.gains.first?.nom, "Fer")
    }

    func testLeBesoinDuJourPlafonneACent() {
        let matin = repas("matin", heure: 8, micros: [("vitC", 90)])
        let resultat = calculer(repas("midi", micros: [("vitC", 60)]), jour: [matin])
        XCTAssertEqual(resultat?.gains.first?.apres, 100)
    }

    /// Un besoin déjà couvert ne « bouge » plus : on ne fête pas un +0.
    func testRienAFeterQuandLeBesoinEtaitDejaCouvert() {
        let matin = repas("matin", heure: 8, micros: [("vitC", 100)])
        XCTAssertNil(calculer(repas("midi", micros: [("vitC", 60)]), jour: [matin]))
    }

    func testUnCafeNeDeclencheRien() {
        XCTAssertNil(calculer(repas("cafe", micros: [("magnesium", 2)])))
        XCTAssertNil(calculer(repas("sans-detail", micros: [])))
    }

    // MARK: Choix des deux lignes

    func testLesApportsARenforcerPassentDevant() {
        let resultat = calculer(repas("midi", micros: [("vitC", 60), ("iron", 12), ("zinc", 30)]), bas: ["iron"])
        XCTAssertEqual(resultat?.gains.map(\.id), ["iron", "vitC"])
    }

    func testDeuxLignesAuPlus() {
        let resultat = calculer(repas("midi", micros: [("vitC", 60), ("iron", 12), ("zinc", 30), ("calcium", 25)]))
        XCTAssertEqual(resultat?.gains.count, 2)
        XCTAssertEqual(resultat?.gains.map(\.id), ["vitC", "zinc"])
    }

    // MARK: D'où vient le gain

    func testLAlimentQuiPorteLeGainEstNomme() {
        let midi = repas("midi", items: [aliment("Poulet rôti", [("iron", 30)]), aliment("Riz", [("iron", 5)])],
                         micros: [("iron", 35)])
        XCTAssertEqual(calculer(midi)?.gains.first?.source, "poulet rôti, surtout")
    }

    func testGainPartageAucunAlimentNomme() {
        let midi = repas("midi", items: [aliment("Lentilles", [("iron", 10)]), aliment("Épinards", [("iron", 9)]),
                                         aliment("Tofu", [("iron", 9)])],
                         micros: [("iron", 28)])
        XCTAssertNil(calculer(midi)?.gains.first?.source)
    }

    /// Un seul aliment : le nommer « surtout » n'apprend rien.
    func testRepasDUnSeulAlimentRienANommer() {
        let midi = repas("midi", items: [aliment("Poulet rôti", [("iron", 30)])], micros: [("iron", 30)])
        XCTAssertNil(calculer(midi)?.gains.first?.source)
    }

    // MARK: La phrase

    func testLaPhraseCompteEtNommeLeRepas() {
        XCTAssertEqual(calculer(repas("midi", micros: [("vitC", 60), ("zinc", 30)]))?.phrase,
                       "Ce déjeuner fait bouger deux de tes apports.")
        XCTAssertEqual(calculer(repas("soir", slot: .dinner, micros: [("vitC", 60)]))?.phrase,
                       "Ce dîner fait bouger un de tes apports.")
    }

    // MARK: La série

    func testSerieDeJoursSuivis() {
        let quinzaine = [18, 19].map { repas("j\($0)", jour: $0, micros: []) }
        let resultat = calculer(repas("midi", micros: [("vitC", 60)]), quinzaine: quinzaine)
        XCTAssertEqual(resultat?.serie, 3)
        XCTAssertEqual(resultat?.libelleSerie, "3 jours d'affilée")
    }

    func testUnTrouCasseLaSerie() {
        let quinzaine = [17, 18].map { repas("j\($0)", jour: $0, micros: []) }
        XCTAssertNil(calculer(repas("midi", micros: [("vitC", 60)]), quinzaine: quinzaine)?.serie)
    }

    /// La fenêtre chargée s'arrête à deux semaines : on ne prétend pas en savoir plus.
    func testLaSerieNePretendPasAuDelaDeLaFenetre() {
        let quinzaine = (7...19).map { repas("j\($0)", jour: $0, micros: []) }
        let resultat = calculer(repas("midi", micros: [("vitC", 60)]), quinzaine: quinzaine)
        XCTAssertEqual(resultat?.serie, 14)
        XCTAssertEqual(resultat?.libelleSerie, "Deux semaines d'affilée")
    }
}
