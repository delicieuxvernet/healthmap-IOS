import XCTest
@testable import HealthMap

// MARK: - Fraîcheur du bilan (7 oct. 2026)
// Un bilan que seul le journal a rendu périmé attend 24 h avant d'être
// régénéré ; un questionnaire modifié le régénère tout de suite.

final class FraicheurBilanTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "FraicheurBilanTests"
    private let userId = "user-test"
    private let maintenant = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z")!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func bilan(hash: String, redigeIlYA heures: Double) -> AIAnalysisV2 {
        let formatteur = ISO8601DateFormatter()
        formatteur.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = maintenant.addingTimeInterval(-heures * 3600)
        return AIAnalysisV2(contract: "v2", meta: MetaV2(generatedAt: formatteur.string(from: date), profileHash: hash))
    }

    func testBilanRecentSurLeMemeQuestionnaireAttend() {
        let b = bilan(hash: "abc", redigeIlYA: 3)
        FraicheurBilan.memoriser(b, cleQuestionnaire: "q1", userId: userId, defaults: defaults)
        XCTAssertTrue(FraicheurBilan.peutAttendre(b, cleQuestionnaire: "q1", userId: userId, maintenant: maintenant, defaults: defaults))
    }

    func testQuestionnaireModifieRegenereToutDeSuite() {
        let b = bilan(hash: "abc", redigeIlYA: 3)
        FraicheurBilan.memoriser(b, cleQuestionnaire: "q1", userId: userId, defaults: defaults)
        XCTAssertFalse(FraicheurBilan.peutAttendre(b, cleQuestionnaire: "q2", userId: userId, maintenant: maintenant, defaults: defaults))
    }

    func testBilanDePlusDe24hRegenere() {
        let b = bilan(hash: "abc", redigeIlYA: 25)
        FraicheurBilan.memoriser(b, cleQuestionnaire: "q1", userId: userId, defaults: defaults)
        XCTAssertFalse(FraicheurBilan.peutAttendre(b, cleQuestionnaire: "q1", userId: userId, maintenant: maintenant, defaults: defaults))
    }

    func testBilanJamaisMemoriseRegenere() {
        let b = bilan(hash: "abc", redigeIlYA: 1)
        XCTAssertFalse(FraicheurBilan.peutAttendre(b, cleQuestionnaire: "q1", userId: userId, maintenant: maintenant, defaults: defaults))
    }

    func testAutreBilanQueCeluiMemoriseRegenere() {
        FraicheurBilan.memoriser(bilan(hash: "abc", redigeIlYA: 1), cleQuestionnaire: "q1", userId: userId, defaults: defaults)
        let autre = bilan(hash: "xyz", redigeIlYA: 1)
        XCTAssertFalse(FraicheurBilan.peutAttendre(autre, cleQuestionnaire: "q1", userId: userId, maintenant: maintenant, defaults: defaults))
    }

    func testLePoidsNeChangePasLaCleDuQuestionnaire() {
        var profil = UserProfile.empty
        profil.completed = true
        profil.weight = "72"
        let avant = FraicheurBilan.cleQuestionnaire(profil)
        profil.weight = "74.5"
        XCTAssertEqual(avant, FraicheurBilan.cleQuestionnaire(profil))
        profil.dietType = "vegetarian"
        XCTAssertNotEqual(avant, FraicheurBilan.cleQuestionnaire(profil))
    }

    func testDateSansFractionAcceptee() {
        XCTAssertNotNil(FraicheurBilan.date("2026-10-07T10:00:00Z"))
        XCTAssertNotNil(FraicheurBilan.date("2026-10-07T10:00:00.123Z"))
        XCTAssertNil(FraicheurBilan.date(nil))
    }
}
