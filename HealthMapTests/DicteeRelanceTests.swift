import XCTest
@testable import HealthMap

// MARK: - Dictée : quels ratés méritent une seconde tentative (7 oct. 2026)
// Un raté réseau au retour dans l'app affichait directement « L'analyse n'a
// pas abouti ». Seuls les ratés passagers sont retentés : jamais un refus.
@MainActor
final class DicteeRelanceTests: XCTestCase {

    func testReseauCoupeOuEndormiEstRetente() {
        for code in [URLError.Code.networkConnectionLost, .notConnectedToInternet, .timedOut, .cannotConnectToHost] {
            XCTAssertTrue(VoiceMealService.estPassager(URLError(code)), "\(code) doit être retenté")
        }
    }

    func testAnnulationEtCertificatNeSontPasRetentes() {
        XCTAssertFalse(VoiceMealService.estPassager(URLError(.cancelled)))
        XCTAssertFalse(VoiceMealService.estPassager(URLError(.serverCertificateUntrusted)))
    }

    func testErreurInconnueNEstPasRetentee() {
        XCTAssertFalse(VoiceMealService.estPassager(VoiceMealService.VoiceError.rateLimited))
        XCTAssertFalse(VoiceMealService.estPassager(NSError(domain: "x", code: 1)))
    }

    // MARK: Quota aligné sur le serveur

    func testLimiteDuServeurEpuiseLeCompteurLocal() {
        let userId = "test-quota-\(UUID().uuidString)"
        XCTAssertTrue(VoiceMealService.QuotaStore.peutDicter(userId: userId, isPremium: false))
        VoiceMealService.QuotaStore.marquerÉpuisé(userId: userId)
        XCTAssertFalse(VoiceMealService.QuotaStore.peutDicter(userId: userId, isPremium: false))
        XCTAssertTrue(VoiceMealService.QuotaStore.peutDicter(userId: userId, isPremium: true), "un abonné dicte toujours")
    }

    func testChaqueEnvoiCompte() {
        let userId = "test-quota-\(UUID().uuidString)"
        for _ in 0..<VoiceMealService.QuotaStore.dictéesGratuitesParJour {
            VoiceMealService.QuotaStore.enregistrerUneDictée(userId: userId)
        }
        XCTAssertFalse(VoiceMealService.QuotaStore.peutDicter(userId: userId, isPremium: false))
    }
}
