import XCTest
@testable import HealthMap

// MARK: - Envoi fiable (7 oct. 2026)
// Une annulation n'est pas une erreur ; seules les coupures d'avant l'envoi
// méritent un second essai.

final class EnvoiFiableTests: XCTestCase {

    func testAnnulations() {
        XCTAssertTrue(EnvoiFiable.estAnnulation(CancellationError()))
        XCTAssertTrue(EnvoiFiable.estAnnulation(URLError(.cancelled)))
        XCTAssertFalse(EnvoiFiable.estAnnulation(URLError(.networkConnectionLost)))
        XCTAssertFalse(EnvoiFiable.estAnnulation(URLError(.timedOut)))
    }

    func testCoupuresAvantEnvoi() {
        XCTAssertTrue(EnvoiFiable.estCoupureAvantEnvoi(URLError(.networkConnectionLost)))
        XCTAssertTrue(EnvoiFiable.estCoupureAvantEnvoi(URLError(.notConnectedToInternet)))
        XCTAssertTrue(EnvoiFiable.estCoupureAvantEnvoi(URLError(.cannotConnectToHost)))
        // Un délai dépassé a pu être traité (et décompté) par le serveur.
        XCTAssertFalse(EnvoiFiable.estCoupureAvantEnvoi(URLError(.timedOut)))
        XCTAssertFalse(EnvoiFiable.estCoupureAvantEnvoi(URLError(.cancelled)))
        XCTAssertFalse(EnvoiFiable.estCoupureAvantEnvoi(CancellationError()))
    }

    func testCodeHTTPAbsentHorsEdgeFunction() {
        XCTAssertNil(EnvoiFiable.codeHTTP(URLError(.networkConnectionLost)))
        XCTAssertNil(EnvoiFiable.codeHTTP(CancellationError()))
    }
}
