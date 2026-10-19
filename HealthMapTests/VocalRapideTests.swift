import XCTest
@testable import HealthMap

/// Audit vocal du 19 oct. 2026 : la dictée rate les mots rares de l'assiette
/// (« skyr au soja » non reconnu) et une analyse longue était relancée d'office.
final class VocalRapideTests: XCTestCase {

    // MARK: - Vocabulaire de la dictée

    func testLeVocabulaireResteSousLaCentaineConseillee() {
        XCTAssertLessThanOrEqual(VocabulaireDictee.termes.count, 100)
        XCTAssertGreaterThan(VocabulaireDictee.termes.count, 50)
    }

    func testLeVocabulaireNeSeRepetePas() {
        let normalises = VocabulaireDictee.termes.map { $0.lowercased() }
        XCTAssertEqual(Set(normalises).count, normalises.count)
    }

    func testLesMotsRatesParLaDicteeSontDonnes() {
        for mot in ["skyr", "skyr au soja", "kéfir", "tofu", "houmous", "quinoa", "Alpro"] {
            XCTAssertTrue(VocabulaireDictee.termes.contains(mot), "« \(mot) » manque au vocabulaire")
        }
    }

    // MARK: - Pas de seconde analyse après une longue attente

    @MainActor
    func testUnRateRapideMeriteUneSecondeTentative() {
        XCTAssertTrue(VoiceMealService.relanceUtile(apres: 1.2))
        XCTAssertTrue(VoiceMealService.relanceUtile(apres: 14))
    }

    @MainActor
    func testUnRateApresUneLongueAttenteNEstPasRelance() {
        // 19 oct. 2026 : échec au bout de 102 s, relancé d'office (50 s de plus).
        XCTAssertFalse(VoiceMealService.relanceUtile(apres: 102))
        XCTAssertFalse(VoiceMealService.relanceUtile(apres: VoiceMealService.relanceAvant))
    }
}
