import XCTest
@testable import HealthMap

// MARK: - Affichage d'une ligne du planning de compléments
//
// La dose ne s'affiche plus (20 septembre 2026) : on conseille le complément,
// la posologie appartient au fabricant et à la personne. Celle-ci venait du
// modèle, donc différente d'un profil à l'autre, et elle partait jusque dans
// le PDF exporté.
//
// Elle reste en revanche décodée et ré-encodée : la ligne `profiles.ai_analysis`
// est partagée avec le web, on ne la mutile pas.

final class SupplementEntryDisplayTests: XCTestCase {

    private func schedule(_ json: String) throws -> SupplementsSchedule {
        try JSONDecoder().decode(SupplementsSchedule.self, from: Data(json.utf8))
    }

    /// Le nom seul, jamais la dose.
    func testAffichage_neMontrePasLaDose() throws {
        let s = try schedule(#"{"morning":[{"name":"Fer bisglycinate","dose":"25 mg","form":"gélule","priority":"essential"}]}"#)
        guard let entree = s.morning?.first else { XCTFail("ligne attendue"); return }
        XCTAssertEqual(entree.displayText, "Fer bisglycinate")
        XCTAssertFalse(entree.displayText.contains("25"))
    }

    /// Mais la dose reste dans la donnée, décodée et ré-encodée telle quelle.
    func testDonnee_laDoseSurvitAuRoundTrip() throws {
        let s = try schedule(#"{"morning":[{"name":"Fer bisglycinate","dose":"25 mg"}]}"#)
        XCTAssertEqual(s.morning?.first?.dose, "25 mg")

        let reencode = try JSONEncoder().encode(s)
        let relu = try JSONDecoder().decode(SupplementsSchedule.self, from: reencode)
        XCTAssertEqual(relu.morning?.first?.dose, "25 mg", "le cache est partagé avec le web")
    }

    /// Payload historique : une simple chaîne. On l'affiche telle quelle,
    /// faute de pouvoir en extraire la dose sans risque.
    func testPayloadLegacy_chaineBrute() throws {
        let s = try schedule(#"{"morning":["Fer bisglycinate 25 mg"]}"#)
        XCTAssertEqual(s.morning?.first?.displayText, "Fer bisglycinate 25 mg")
    }

    /// Le nom passe devant la chaîne brute quand les deux existent.
    func testNomPrioritaireSurLaChaineBrute() {
        var entree = SupplementEntry()
        entree.name = "Vitamine B12"
        entree.rawString = "Vitamine B12 1000 mcg"
        XCTAssertEqual(entree.displayText, "Vitamine B12")
    }

    /// Ni nom ni chaîne : un repli neutre, jamais une ligne vide.
    func testSansNom_repliNeutre() {
        XCTAssertEqual(SupplementEntry().displayText, "Complement")
    }

    /// Un nom vide ne doit pas produire une ligne vide.
    func testNomVide_repliNeutre() {
        var entree = SupplementEntry()
        entree.name = ""
        XCTAssertEqual(entree.displayText, "Complement")
    }
}
