import XCTest
@testable import HealthMap

// MARK: - AIAnalysisService.hashProfile — regression tests
// groceries was excluded from the cache hash (non-deterministic dict
// serialization) even though the AI prompt treats it as a priority source and
// NutrientEngine consumes it for scoring — a changed grocery cart never
// invalidated the cached bilan. Fixed 2026-07-05 (architecture audit) via a
// sorted-key serialization of the groceries dictionary.
@MainActor
final class AIAnalysisServiceHashTests: XCTestCase {
    func testExpectedAIContractVersionsInvalidateLegacyCaches() {
        XCTAssertEqual(AIAnalysisService.expectedSchemaVersionV7, 8)
        XCTAssertEqual(AIAnalysisService.expectedSchemaVersionV2, "v2.2")
    }


    func testHashIsDeterministicAcrossRepeatedCalls() {
        var profile = UserProfile.empty
        profile.groceries = ["pomme": 3, "riz": 1, "poulet": 2]

        let hashes = (0..<20).map { _ in AIAnalysisService.hashProfile(profile) }
        XCTAssertEqual(Set(hashes).count, 1, "hashProfile must be deterministic regardless of dictionary iteration order")
    }

    func testGroceriesChangeInvalidatesHash() {
        var base = UserProfile.empty
        base.groceries = ["pomme": 3]

        var changed = base
        changed.groceries = ["pomme": 5]

        XCTAssertNotEqual(
            AIAnalysisService.hashProfile(base),
            AIAnalysisService.hashProfile(changed),
            "Changing the grocery cart quantities must invalidate the AI analysis cache"
        )
    }

    func testEmptyGroceriesStillHashesDeterministically() {
        let profile = UserProfile.empty
        let hashes = (0..<10).map { _ in AIAnalysisService.hashProfile(profile) }
        XCTAssertEqual(Set(hashes).count, 1, "An empty groceries dict must not introduce non-determinism")
    }

    // MARK: - Poids réglé depuis le Journal (1er octobre 2026)

    /// Le poids souhaité règle les calories du jour, pas le bilan : le régler
    /// ne doit jamais relancer une analyse.
    func testLePoidsSouhaiteNeChangePasLeHash() {
        var base = UserProfile.empty
        base.weight = "74"

        var avecObjectif = base
        avecObjectif.targetWeight = "70"

        XCTAssertEqual(AIAnalysisService.hashProfile(base), AIAnalysisService.hashProfile(avecObjectif))
    }

    /// Un pas de 100 g ne relance pas un bilan ; un demi-kilo, si.
    func testLePoidsEntreDansLeHashAuDemiKilo() {
        var base = UserProfile.empty
        base.weight = "74"

        var unPas = base
        unPas.weight = "74.2"
        XCTAssertEqual(AIAnalysisService.hashProfile(base), AIAnalysisService.hashProfile(unPas))

        var unDemiKilo = base
        unDemiKilo.weight = "74.5"
        XCTAssertNotEqual(AIAnalysisService.hashProfile(base), AIAnalysisService.hashProfile(unDemiKilo))
    }

    /// Ce qu'écrit le questionnaire ressort caractère pour caractère : aucun
    /// profil existant ne change de hash.
    func testUnPoidsDejaAuDemiKiloResteTelQuel() {
        XCTAssertEqual(AIAnalysisService.poidsPourLeHash("74"), "74")
        XCTAssertEqual(AIAnalysisService.poidsPourLeHash("74.0"), "74.0")
        XCTAssertEqual(AIAnalysisService.poidsPourLeHash("74.5"), "74.5")
        XCTAssertEqual(AIAnalysisService.poidsPourLeHash(""), "")
        XCTAssertEqual(AIAnalysisService.poidsPourLeHash("abc"), "abc")

        XCTAssertEqual(AIAnalysisService.poidsPourLeHash("74.2"), "74")
        XCTAssertEqual(AIAnalysisService.poidsPourLeHash("74.3"), "74.5")
        XCTAssertEqual(AIAnalysisService.poidsPourLeHash("74.8"), "75")
    }
}
