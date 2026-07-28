import XCTest
@testable import HealthMap

/// La dictée longue était refusée par le serveur (400 au-delà de 1 200
/// caractères), et l'app rendait « L'analyse n'a pas abouti » sans dire
/// pourquoi. On tronque désormais avant l'envoi : ces tests fixent le contrat.
final class VoiceTranscriptTests: XCTestCase {

    func testTexteCourtInchange() {
        let texte = "ce midi, du poulet rôti avec du riz et une compote"
        XCTAssertEqual(VoiceMealService.tronquerSiBesoin(texte), texte)
    }

    func testTexteALaLimiteInchange() {
        let texte = String(repeating: "a", count: VoiceMealService.maxTranscriptChars)
        XCTAssertEqual(VoiceMealService.tronquerSiBesoin(texte).count,
                       VoiceMealService.maxTranscriptChars)
    }

    func testTexteTropLongEstTronque() {
        let texte = String(repeating: "mot ", count: 1000)   // 4 000 caractères
        let coupe = VoiceMealService.tronquerSiBesoin(texte)
        XCTAssertLessThanOrEqual(coupe.count, VoiceMealService.maxTranscriptChars)
        XCTAssertGreaterThan(coupe.count, 0)
    }

    /// Couper en plein milieu d'un mot inventerait un aliment à l'extraction
    /// (« omel » au lieu d'« omelette »).
    func testCoupeSurUneFrontiereDeMot() {
        let texte = String(repeating: "omelette ", count: 400)
        let coupe = VoiceMealService.tronquerSiBesoin(texte)
        XCTAssertFalse(coupe.hasSuffix(" "), "la coupe ne doit pas laisser d'espace final")
        let dernierMot = coupe.split(separator: " ").last.map(String.init) ?? ""
        XCTAssertEqual(dernierMot, "omelette", "le dernier mot doit être entier")
    }

    /// Un texte sans aucun espace ne doit pas disparaître : on coupe net plutôt
    /// que de renvoyer une chaîne vide.
    func testTexteSansEspaceEstCoupeNet() {
        let texte = String(repeating: "a", count: 2000)
        let coupe = VoiceMealService.tronquerSiBesoin(texte)
        XCTAssertEqual(coupe.count, VoiceMealService.maxTranscriptChars)
    }
}
