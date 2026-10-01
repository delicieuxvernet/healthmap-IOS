import XCTest
@testable import HealthMap

/// L'eau du jour (gobelets gardés sur le téléphone) et l'offre annuelle
/// (économie lue chez Apple, rythme des rappels).
final class SuiviEauTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "SuiviEauTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testToucherUnGobeletLeRemplitAvecCeuxDAvant() {
        XCTAssertEqual(SuiviEau.apresToucher(index: 2, actuel: 0), 3)
        XCTAssertEqual(SuiviEau.apresToucher(index: 7, actuel: 3), 8)
        // Revenir en arrière : toucher un gobelet déjà plein s'y arrête.
        XCTAssertEqual(SuiviEau.apresToucher(index: 1, actuel: 5), 2)
    }

    func testToucherLeDernierRempliLeVide() {
        XCTAssertEqual(SuiviEau.apresToucher(index: 2, actuel: 3), 2)
        XCTAssertEqual(SuiviEau.apresToucher(index: 0, actuel: 1), 0)
    }

    func testHuitGobeletsFontDeuxLitres() {
        XCTAssertEqual(SuiviEau.litres(0), 0)
        XCTAssertEqual(SuiviEau.litres(3), 0.75)
        XCTAssertEqual(SuiviEau.litres(SuiviEau.gobeletsParJour), 2)
    }

    func testLeCompteEstGardeParJourEtParCompte() throws {
        let aujourdhui = Date()
        let hier = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: aujourdhui))

        SuiviEau.noter(3, userId: "a", jour: aujourdhui, defaults: defaults)
        SuiviEau.noter(6, userId: "a", jour: hier, defaults: defaults)

        XCTAssertEqual(SuiviEau.gobelets(userId: "a", jour: aujourdhui, defaults: defaults), 3)
        XCTAssertEqual(SuiviEau.gobelets(userId: "a", jour: hier, defaults: defaults), 6)
        XCTAssertEqual(SuiviEau.gobelets(userId: "b", jour: aujourdhui, defaults: defaults), 0)
    }

    func testLeCompteResteDansLesBornes() {
        let jour = Date()
        SuiviEau.noter(40, userId: "a", jour: jour, defaults: defaults)
        XCTAssertEqual(SuiviEau.gobelets(userId: "a", jour: jour, defaults: defaults), SuiviEau.gobeletsParJour)
        SuiviEau.noter(-2, userId: "a", jour: jour, defaults: defaults)
        XCTAssertEqual(SuiviEau.gobelets(userId: "a", jour: jour, defaults: defaults), 0)
    }

    func testLesJoursTropAnciensSontOublies() throws {
        let ancien = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -200, to: Date()))
        SuiviEau.noter(5, userId: "a", jour: ancien, defaults: defaults)
        XCTAssertEqual(SuiviEau.gobelets(userId: "a", jour: ancien, defaults: defaults), 0)
    }
}

final class OffrePremiumTests: XCTestCase {

    // MARK: - L'économie affichée

    func testLEconomieCompareUnAnAuTarifCourt() {
        // 39,99 par an face à 4,99 par semaine (259,48 par an) : 85 %.
        XCTAssertEqual(OffrePremium.economie(annuel: Decimal(string: "39.99")!, court: Decimal(string: "4.99")!, periodesParAn: 52), 85)
        // 30 par an face à 0,99 par semaine (51,48 par an) : 42 %.
        XCTAssertEqual(OffrePremium.economie(annuel: 30, court: Decimal(string: "0.99")!, periodesParAn: 52), 42)
    }

    func testPasDEconomieAnnonceeSiLAnnuelNEstPasMoinsCher() {
        XCTAssertNil(OffrePremium.economie(annuel: 300, court: Decimal(string: "4.99")!, periodesParAn: 52))
        XCTAssertNil(OffrePremium.economie(annuel: 0, court: Decimal(string: "4.99")!, periodesParAn: 52))
        XCTAssertNil(OffrePremium.economie(annuel: 30, court: 0, periodesParAn: 52))
    }

    func testLesTextesNeDisentQueCeQuiEstLu() {
        let complete = OffrePremium(pourcent: 85, prixAnnuel: "39,99 €", prixAnnuelAuTarifCourt: "259,48 €", essai: "7 jours")
        XCTAssertTrue(complete.titre.contains("85"))
        XCTAssertTrue(complete.detail.contains("39,99 €"))
        XCTAssertTrue(complete.detail.contains("259,48 €"))
        XCTAssertTrue(complete.detail.contains("7 jours d'essai gratuit"))

        // Sans essai chez Apple, aucun essai promis.
        let sansEssai = OffrePremium(pourcent: 42, prixAnnuel: "30,00 €", prixAnnuelAuTarifCourt: "51,48 €", essai: nil)
        XCTAssertFalse(sansEssai.detail.contains("gratuit"))

        // Sans économie notable, aucun pourcentage.
        let essaiSeul = OffrePremium(pourcent: nil, prixAnnuel: "30,00 €", prixAnnuelAuTarifCourt: nil, essai: "7 jours")
        XCTAssertTrue(essaiSeul.titre.contains("7 jours"))
        XCTAssertFalse(essaiSeul.titre.contains("%"))
    }

    // MARK: - Le rythme des rappels

    private let maintenant = Date(timeIntervalSince1970: 1_790_000_000)
    private func ilYA(jours: Double) -> Date { maintenant.addingTimeInterval(-jours * 86_400) }

    func testJamaisLePremierJour() {
        XCTAssertFalse(RythmeOffre.peutProposer(premierPassage: nil, derniere: nil, vues: 0, maintenant: maintenant))
        XCTAssertFalse(RythmeOffre.peutProposer(premierPassage: ilYA(jours: 0.5), derniere: nil, vues: 0, maintenant: maintenant))
        XCTAssertTrue(RythmeOffre.peutProposer(premierPassage: ilYA(jours: 1), derniere: nil, vues: 0, maintenant: maintenant))
    }

    func testTroisJoursEntreDeuxRappels() {
        let premier = ilYA(jours: 30)
        XCTAssertFalse(RythmeOffre.peutProposer(premierPassage: premier, derniere: ilYA(jours: 2), vues: 1, maintenant: maintenant))
        XCTAssertTrue(RythmeOffre.peutProposer(premierPassage: premier, derniere: ilYA(jours: 3), vues: 1, maintenant: maintenant))
    }

    func testApresTroisRefusLesRappelsSEspacent() {
        let premier = ilYA(jours: 60)
        XCTAssertFalse(RythmeOffre.peutProposer(premierPassage: premier, derniere: ilYA(jours: 5), vues: 3, maintenant: maintenant))
        XCTAssertTrue(RythmeOffre.peutProposer(premierPassage: premier, derniere: ilYA(jours: 14), vues: 3, maintenant: maintenant))
    }
}
