import XCTest
@testable import HealthMap

/// Recollage des segments de dictée (correctif du 24 août) : une longue
/// dictée avec des pauses ne doit JAMAIS perdre ses premières phrases —
/// le recognizer sur appareil repart de zéro à chaque silence et son
/// « final » ne couvre que la dernière.
final class TranscriptionCumulTests: XCTestCase {

    /// Chemin serveur : partiels cumulés sur tout le fichier, un final complet.
    func testServeur_partielsCumules_pasDeDoublon() {
        let cumul = TranscriptionCumul()
        cumul.integrer("ce midi", final: false)
        cumul.integrer("ce midi cent cinquante grammes", final: false)
        cumul.integrer("ce midi cent cinquante grammes de poulet et un yaourt", final: true)
        XCTAssertEqual(cumul.texteFinal(), "ce midi cent cinquante grammes de poulet et un yaourt")
    }

    /// Chemin sur appareil : la transcription redémarre après chaque silence.
    /// C'est LE bug signalé : seule la dernière phrase survivait.
    func testAppareil_redemarrageApresSilence_toutEstRecolle() {
        let cumul = TranscriptionCumul()
        cumul.integrer("ce midi j'ai mangé du poulet rôti avec des haricots verts", final: false)
        // Silence → nouvelle phrase, le partiel retombe presque à zéro.
        cumul.integrer("une assiette", final: false)
        cumul.integrer("une assiette de pâtes et de la sauce tomate", final: false)
        // Deuxième silence.
        cumul.integrer("un yaourt", final: false)
        cumul.integrer("un yaourt et une banane", final: true)
        XCTAssertEqual(
            cumul.texteFinal(),
            "ce midi j'ai mangé du poulet rôti avec des haricots verts une assiette de pâtes et de la sauce tomate un yaourt et une banane"
        )
    }

    /// Un final qui ne couvre que la dernière phrase ne doit pas écraser les
    /// segments déjà archivés.
    func testAppareil_finalNeCouvreQueLaDernierePhrase() {
        let cumul = TranscriptionCumul()
        cumul.integrer("du saumon avec du riz complet et des courgettes", final: false)
        cumul.integrer("deux kiwis", final: false)
        cumul.integrer("deux kiwis", final: true)
        XCTAssertEqual(cumul.texteFinal(),
                       "du saumon avec du riz complet et des courgettes deux kiwis")
    }

    /// Une révision de fin de phrase (le recognizer réécrit en affinant) n'est
    /// pas un redémarrage : elle remplace, elle n'archive pas.
    func testRevision_neCreePasDeSegment() {
        let cumul = TranscriptionCumul()
        cumul.integrer("une salade de tomates avec du thon", final: false)
        cumul.integrer("une salade de tomates avec du thon et du maïs", final: false)
        cumul.integrer("une salade de tomates avec du thon et du maïs doux", final: true)
        XCTAssertEqual(cumul.texteFinal(), "une salade de tomates avec du thon et du maïs doux")
    }

    /// Un final cumulatif qui répète le segment précédent en préfixe le
    /// remplace (jamais « A A B »).
    func testFinalCumulatif_remplaceSonPrefixe() {
        let cumul = TranscriptionCumul()
        cumul.integrer("un œuf", final: false)
        cumul.integrer("un œuf et des épinards", final: true)
        XCTAssertEqual(cumul.texteFinal(), "un œuf et des épinards")
    }

    func testVide_resteVide() {
        let cumul = TranscriptionCumul()
        XCTAssertEqual(cumul.texteFinal(), "")
        cumul.integrer("   ", final: true)
        XCTAssertEqual(cumul.texteFinal(), "")
    }

    /// Deux finals successifs identiques (relance interne du recognizer) ne
    /// produisent qu'un segment.
    func testFinalsIdentiques_dedupliques() {
        let cumul = TranscriptionCumul()
        cumul.integrer("une pomme", final: true)
        cumul.integrer("une pomme", final: true)
        XCTAssertEqual(cumul.texteFinal(), "une pomme")
    }
}
