import XCTest
@testable import HealthMap

// MARK: - Grammaire du geste de dictée (bulle vocale de l'accueil Scan)
//
// Les seuils décident de ce que vaut un mouvement du doigt pendant la dictée
// maintenue : annuler (gauche), verrouiller (haut), ou continuer. Testés ici
// parce qu'un seuil décalé d'un signe ne se voit pas à la relecture — et que
// l'annulation doit TOUJOURS primer sur le verrou en diagonale.

final class DicteeGesteTests: XCTestCase {

    func testGlisserAGaucheAnnule() {
        XCTAssertEqual(DicteeGeste.decision(pour: CGSize(width: -80, height: 0)), .annuler)
        XCTAssertEqual(DicteeGeste.decision(pour: CGSize(width: -120, height: -20)), .annuler)
    }

    func testGlisserEnHautVerrouille() {
        XCTAssertEqual(DicteeGeste.decision(pour: CGSize(width: 0, height: -70)), .verrouiller)
        XCTAssertEqual(DicteeGeste.decision(pour: CGSize(width: -30, height: -110)), .verrouiller)
    }

    /// Diagonale franche : jeter doit rester possible, l'annulation prime.
    func testAnnulationPrimeSurLeVerrouEnDiagonale() {
        XCTAssertEqual(DicteeGeste.decision(pour: CGSize(width: -90, height: -90)), .annuler)
    }

    func testPetitsMouvementsContinuent() {
        XCTAssertEqual(DicteeGeste.decision(pour: .zero), .continuer)
        XCTAssertEqual(DicteeGeste.decision(pour: CGSize(width: -79, height: -69)), .continuer)
        // Vers la droite ou vers le bas : jamais d'action, quel que soit l'écart.
        XCTAssertEqual(DicteeGeste.decision(pour: CGSize(width: 200, height: 150)), .continuer)
    }
}
