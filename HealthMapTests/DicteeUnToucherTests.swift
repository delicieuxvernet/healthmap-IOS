import XCTest
@testable import HealthMap

/// La dictée s'ajoute en un toucher (maquette validée par Arthur le 8 octobre
/// 2026 : « trop de freins, trop de clics »). Une quantité non dite ne bloque
/// plus : elle prend la portion standard, marquée « estimée », et les
/// pastilles posées sous la ligne la corrigent d'un toucher.
@MainActor
final class DicteeUnToucherTests: XCTestCase {

    private func item(_ json: String) throws -> VoiceMealService.Item {
        try JSONDecoder().decode(VoiceMealService.Item.self, from: Data(json.utf8))
    }

    /// La capture d'Arthur : « des pâtes à la bolognaise », sans quantité.
    private func pates() throws -> VoiceMealService.Item {
        try item("""
        {"index":0,"foodId":"ciqual:25453","nom":"Pâtes à la bolognaise (spaghetti, tagliatelles…)","g":null,
         "besoin_quantite":true,"confiance":0.9,"kcal":null,"portions":[],"libelle":"pâtes à la bolognaise",
         "statut":"compris","alternatives":[],
         "per100":{"kcal":134,"proteines":6.5,"glucides":17,"lipides":4.3,"fibres":1.4}}
        """)
    }

    func testDesPatesSansQuantitePrennentUneAssietteMoyenne() throws {
        let pates = try pates()
        let unite = VoiceMealSheet.unite(pour: pates)
        XCTAssertEqual(unite?.singulier, "assiette")
        XCTAssertEqual(VoiceMealSheet.portionEstimee(pour: pates, unite: unite), 200)
    }

    func testUnContenantProposeSesTroisTaillesDansUneAssiette() throws {
        let pates = try pates()
        let unite = VoiceMealSheet.unite(pour: pates)
        let choix = VoiceMealSheet.choixQuantite(pour: pates, unite: unite, taille: unite?.tailleParDefaut)
        XCTAssertEqual(choix.map(\.libelle), ["Petite", "Moyenne", "Grande"])
        XCTAssertEqual(choix.map(\.grammes), [150, 200, 300])
        XCTAssertEqual(choix.map(\.taille), [0, 1, 2])
        XCTAssertEqual(choix.map(\.detail), ["150 g", "200 g", "300 g"])
        // L'aliment grossit dans l'assiette, de la petite à la grande.
        XCTAssertEqual(choix.compactMap(\.echelle), [0, 0.5, 1])
        XCTAssertTrue(choix.allSatisfy(\.parUnite))
    }

    /// Ce qui se compte se propose en nombre, pas en taille : on mange deux
    /// œufs plus souvent qu'un « gros » œuf.
    func testCeQuiSeCompteSeProposeEnUnDeuxTrois() throws {
        let oeuf = try item("""
        {"index":1,"foodId":"ciqual:22010","nom":"Oeuf, dur","g":null,"besoin_quantite":true,
         "confiance":0.9,"kcal":null,"portions":[],"statut":"compris"}
        """)
        let unite = try XCTUnwrap(VoiceMealSheet.unite(pour: oeuf))
        XCTAssertEqual(VoiceMealSheet.portionEstimee(pour: oeuf, unite: unite), 50)
        let choix = VoiceMealSheet.choixQuantite(pour: oeuf, unite: unite, taille: unite.tailleParDefaut)
        XCTAssertEqual(choix.map(\.libelle), ["1 œuf", "2 œufs", "3 œufs"])
        XCTAssertEqual(choix.map(\.grammes), [50, 100, 150])
        XCTAssertTrue(choix.allSatisfy { $0.taille == nil && $0.echelle == nil })
    }

    /// Sans unité connue, les portions de la base : celle du milieu d'office.
    func testSansUniteLesPortionsDeLaBase() throws {
        let inconnu = try item("""
        {"index":2,"foodId":"ciqual:99999","nom":"Aliment test xq","g":null,"besoin_quantite":true,
         "confiance":0.8,"kcal":null,"statut":"compris",
         "portions":[{"label":"Petite portion","grammes":60},{"label":"Portion","grammes":90},{"label":"Grosse portion","grammes":150}]}
        """)
        let unite = VoiceMealSheet.unite(pour: inconnu)
        XCTAssertNil(unite)
        XCTAssertEqual(VoiceMealSheet.portionEstimee(pour: inconnu, unite: unite), 90)
        let choix = VoiceMealSheet.choixQuantite(pour: inconnu, unite: unite, taille: nil)
        XCTAssertEqual(choix.map(\.grammes), [60, 90, 150])
        XCTAssertFalse(choix.contains(where: \.parUnite))
    }

    /// Ni unité ni portion : 100 g, la référence des valeurs nutritionnelles,
    /// et aucune pastille (la règle graduée reste, dans le réglage fin).
    func testSansRienCentGrammesEtAucunePastille() throws {
        let inconnu = try item("""
        {"index":3,"foodId":null,"nom":"Aliment test xq","g":null,"besoin_quantite":true,
         "confiance":0.5,"kcal":null,"portions":[],"statut":"compris"}
        """)
        XCTAssertEqual(VoiceMealSheet.portionEstimee(pour: inconnu, unite: nil), VoiceMealSheet.portionParDefautG)
        XCTAssertEqual(VoiceMealSheet.portionParDefautG, 100)
        XCTAssertTrue(VoiceMealSheet.choixQuantite(pour: inconnu, unite: nil, taille: nil).isEmpty)
    }

    /// Un repas non dit n'est plus une question bloquante : celui de l'heure,
    /// affiché en titre et modifiable d'un toucher.
    func testLeRepasNonDitEstCeluiDeLHeure() {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "Europe/Paris")!
        let soir = calendrier.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 18, minute: 47))!
        XCTAssertNil(VoiceMealService.slotDit("inconnu"))
        XCTAssertEqual(MealJournalService.MealSlot.from(date: soir, calendar: calendrier), .dinner)
    }
}
