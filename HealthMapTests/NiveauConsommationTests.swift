import XCTest
@testable import HealthMap

// MARK: - « Pas beaucoup, modérément, beaucoup »
//
// Le mot remplace le chiffre à l'écran, pas dans la donnée : ce qui s'écrit
// dans `profile.groceries` reste un nombre de portions par semaine.
final class NiveauConsommationTests: XCTestCase {

    func testLesTroisMotsSontCeuxDemandesParArthur() {
        XCTAssertEqual(NiveauConsommation.allCases.map(\.libelle), ["Pas beaucoup", "Modérément", "Beaucoup"])
    }

    func testChaqueMotVautDesPortionsParSemaine() {
        XCTAssertEqual(NiveauConsommation.pasBeaucoup.portions, 1)
        XCTAssertEqual(NiveauConsommation.moderement.portions, 3)
        XCTAssertEqual(NiveauConsommation.beaucoup.portions, 10)
    }

    func testLesPortionsCroissentAvecLeMot() {
        let portions = NiveauConsommation.allCases.map(\.portions)
        XCTAssertEqual(portions, portions.sorted())
        XCTAssertEqual(Set(portions).count, portions.count, "Deux mots ne valent jamais la même chose")
    }

    /// Ce qu'on écrit se relit avec le même mot : sinon un aliment réglé sur
    /// « Beaucoup » reviendrait sur « Modérément » à la reprise.
    func testUnMotEcritSeRelitAvecLeMemeMot() {
        for niveau in NiveauConsommation.allCases {
            XCTAssertEqual(NiveauConsommation.depuis(portions: niveau.portions), niveau)
        }
    }

    /// Un caddie rempli avec les anciennes fourchettes (1, 2, 5, 10 portions)
    /// se relit sans erreur d'ordre de grandeur.
    func testLesAnciennesFourchettesSeRelisent() {
        XCTAssertEqual(NiveauConsommation.depuis(portions: 1), .pasBeaucoup, "fourchette 0–1")
        XCTAssertEqual(NiveauConsommation.depuis(portions: 2), .moderement, "fourchette 2–3")
        XCTAssertEqual(NiveauConsommation.depuis(portions: 5), .moderement, "fourchette 4–6")
        XCTAssertEqual(NiveauConsommation.depuis(portions: 10), .beaucoup, "fourchette 7+")
    }

    func testLesBornes() {
        XCTAssertEqual(NiveauConsommation.depuis(portions: 0), .pasBeaucoup)
        XCTAssertEqual(NiveauConsommation.depuis(portions: 2), .moderement)
        XCTAssertEqual(NiveauConsommation.depuis(portions: 6), .moderement)
        XCTAssertEqual(NiveauConsommation.depuis(portions: 7), .beaucoup)
        XCTAssertEqual(NiveauConsommation.depuis(portions: 21), .beaucoup)
    }

    func testUnAlimentCocheePartSurModerement() {
        XCTAssertEqual(NiveauConsommation.parDefaut, .moderement)
    }

    func testChaqueMotEstExplique() {
        for niveau in NiveauConsommation.allCases {
            XCTAssertFalse(niveau.precision.isEmpty)
        }
    }
}
