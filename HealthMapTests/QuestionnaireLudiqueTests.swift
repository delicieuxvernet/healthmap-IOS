import XCTest
@testable import HealthMap

// MARK: - Le questionnaire ludique (3 octobre 2026)
//
// La présentation change, pas les données : les résumés des pastilles se
// lisent dans les options de `QuestionnaireSection`, et le ciel des repas
// n'est qu'une teinte de fond.
final class QuestionnaireLudiqueTests: XCTestCase {

    func testResumeReprendLEmojiEtLeLibelleDeLOption() {
        XCTAssertEqual(BilanResume.de("sunExposure", "some"), "⛅ Un peu")
        XCTAssertEqual(BilanResume.de("sleepHours", "7.5"), "🙂 7 à 8 h")
        // Sans emoji, le libellé seul.
        XCTAssertEqual(BilanResume.de("homeCookedPct", "half"), "La moitié")
    }

    func testResumeVideTantQueRienNEstRepondu() {
        XCTAssertNil(BilanResume.de("sunExposure", ""))
    }

    func testLeCielPasseDuMatinAuSoir() {
        XCTAssertEqual(EcranBilan.petitDej.teinteVerre, .aube)
        XCTAssertEqual(EcranBilan.midi.teinteVerre, .ciel)
        XCTAssertEqual(EcranBilan.gouter.teinteVerre, .kiwi)
        XCTAssertEqual(EcranBilan.soir.teinteVerre, .orchidee)
        // Hors repas, la teinte reste celle de l'étape.
        XCTAssertEqual(EcranBilan.soleil.teinteVerre, EtapeBilan.quotidien.teinteVerre)
        XCTAssertEqual(EcranBilan.regime.teinteVerre, EtapeBilan.assiette.teinteVerre)
    }

    func testChaqueRepasASonEmoji() {
        XCTAssertEqual(Set(RepasBilan.allCases.map(\.emoji)).count, RepasBilan.allCases.count)
    }
}
