import XCTest
@testable import HealthMap

// MARK: - Réglages v3 (20 sept. 2026)
//
// Ce qui se teste sans StoreKit ni notification réelle : l'interrupteur des
// rappels, et ce que dit le bloc Premium tant que l'App Store n'a pas répondu.

final class ReglagesTests: XCTestCase {

    private var valeurInitiale: Any?

    override func setUp() {
        super.setUp()
        valeurInitiale = UserDefaults.standard.object(forKey: RappelsPersonnalises.cleActifs)
        UserDefaults.standard.removeObject(forKey: RappelsPersonnalises.cleActifs)
    }

    override func tearDown() {
        if let valeurInitiale {
            UserDefaults.standard.set(valeurInitiale, forKey: RappelsPersonnalises.cleActifs)
        } else {
            UserDefaults.standard.removeObject(forKey: RappelsPersonnalises.cleActifs)
        }
        super.tearDown()
    }

    // MARK: Interrupteur des rappels

    func testRappelsAllumesTantQuePersonneNeLesAEteints() {
        XCTAssertTrue(RappelsPersonnalises.actifs)
    }

    func testEteindreLesRappelsSeRetient() {
        RappelsPersonnalises.actifs = false
        XCTAssertFalse(RappelsPersonnalises.actifs)
        RappelsPersonnalises.actifs = true
        XCTAssertTrue(RappelsPersonnalises.actifs)
    }

    /// La clé part au changement de compte (préfixe balayé à la déconnexion) :
    /// un nouveau compte ne doit pas hériter du silence du précédent.
    func testLaCleSuitLePrefixeBalayeAuChangementDeCompte() {
        XCTAssertTrue(RappelsPersonnalises.cleActifs.hasPrefix("healthmap_"))
    }

    // MARK: Bloc Premium sans réponse de l'App Store

    /// Aucun montant inventé : sans formule chargée, la ligne de prix attend.
    func testSansFormuleLaLigneDePrixAttend() {
        XCTAssertEqual(PremiumOffre.lignePrix(offerings: nil, produits: []), .enAttente)
    }

    /// Pas d'essai promis tant qu'Apple ne l'a pas confirmé.
    func testSansFormuleAucunEssaiPromis() {
        XCTAssertNil(PremiumOffre.essaiPropose(offerings: nil, produits: []))
        XCTAssertEqual(PremiumOffre.titreEssai(offerings: nil, produits: []), "Découvrir Kiwio Premium")
    }
}
