import XCTest
@testable import HealthMap

/// La dictée longue était refusée par le serveur (400 au-delà de 1 200
/// caractères), et l'app rendait « L'analyse n'a pas abouti » sans dire
/// pourquoi. On tronque désormais avant l'envoi : ces tests fixent le contrat.
///
/// Toutes les longueurs de test sont dérivées de `maxChars` : la limite a déjà
/// bougé une fois (1 200 → 4 000, quand l'edge function corrigée a été
/// déployée), et des tailles écrites en dur avaient rendu ces tests faussement
/// verts — un texte de 2 000 caractères ne dépasse plus rien.
final class VoiceTranscriptTests: XCTestCase {

    func testTexteCourtInchange() {
        let texte = "ce midi, du poulet rôti avec du riz et une compote"
        XCTAssertEqual(VoiceTranscript.tronquerSiBesoin(texte), texte)
    }

    func testTexteALaLimiteInchange() {
        let texte = String(repeating: "a", count: VoiceTranscript.maxChars)
        XCTAssertEqual(VoiceTranscript.tronquerSiBesoin(texte).count,
                       VoiceTranscript.maxChars)
    }

    func testTexteTropLongEstTronque() {
        // Quatre fois la limite, quelle qu'elle soit.
        let texte = String(repeating: "mot ", count: VoiceTranscript.maxChars)
        let coupe = VoiceTranscript.tronquerSiBesoin(texte)
        XCTAssertLessThanOrEqual(coupe.count, VoiceTranscript.maxChars)
        XCTAssertGreaterThan(coupe.count, 0)
    }

    /// Couper en plein milieu d'un mot inventerait un aliment à l'extraction
    /// (« omel » au lieu d'« omelette »).
    func testCoupeSurUneFrontiereDeMot() {
        // « omelette » + espace = 9 caractères : de quoi dépasser la limite,
        // avec de la marge pour que la coupe tombe bien au milieu du texte.
        let texte = String(repeating: "omelette ", count: VoiceTranscript.maxChars / 9 + 50)
        let coupe = VoiceTranscript.tronquerSiBesoin(texte)
        XCTAssertFalse(coupe.hasSuffix(" "), "la coupe ne doit pas laisser d'espace final")
        let dernierMot = coupe.split(separator: " ").last.map(String.init) ?? ""
        XCTAssertEqual(dernierMot, "omelette", "le dernier mot doit être entier")
    }

    /// Un texte sans aucun espace ne doit pas disparaître : on coupe net plutôt
    /// que de renvoyer une chaîne vide.
    func testTexteSansEspaceEstCoupeNet() {
        let texte = String(repeating: "a", count: VoiceTranscript.maxChars + 500)
        let coupe = VoiceTranscript.tronquerSiBesoin(texte)
        XCTAssertEqual(coupe.count, VoiceTranscript.maxChars)
    }
}
