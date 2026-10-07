import XCTest
@testable import HealthMap

// MARK: - Astuces de l'attente (7 octobre 2026)
// Les mises en garde passent toujours en premier ; un abonné Premium ne voit
// jamais de promotion de Premium.

final class AstucesAttenteTests: XCTestCase {

    /// Gratuit : avis médical, puis l'assiette, puis les cartes Premium.
    func testGratuit_misesEnGardeDAbordPuisPremium() {
        let suite = AstucesAttente.suite(estPremium: false)
        XCTAssertEqual(suite.map(\.id).prefix(2), ["avis-medical", "assiette-d-abord"])
        XCTAssertTrue(suite.dropFirst(2).allSatisfy { $0.genre == .premium })
        XCTAssertFalse(suite.dropFirst(2).isEmpty)
    }

    /// Premium : uniquement les mises en garde.
    func testPremium_aucunePromotion() {
        let suite = AstucesAttente.suite(estPremium: true)
        XCTAssertEqual(suite.map(\.id), ["avis-medical", "assiette-d-abord"])
        XCTAssertTrue(suite.allSatisfy { $0.genre == .bonASavoir })
    }

    /// Une carte toutes les 15 à 20 s, comme demandé.
    func testDuree_entre15Et20Secondes() {
        XCTAssertGreaterThanOrEqual(AstucesAttente.duree, .seconds(15))
        XCTAssertLessThanOrEqual(AstucesAttente.duree, .seconds(20))
    }

    /// Identifiants uniques : ils pilotent la transition de la carte.
    func testIdentifiantsUniques() {
        let ids = AstucesAttente.suite(estPremium: false).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
