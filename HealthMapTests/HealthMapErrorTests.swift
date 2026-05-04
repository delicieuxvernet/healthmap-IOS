import XCTest
@testable import HealthMap

/// Exercises the typed error surface and the `from(_:)` mapping.
/// These tests guard against accidental regressions that would cause
/// Sentry to lose error grouping or the UI to lose its French messages.
final class HealthMapErrorTests: XCTestCase {

    func testAuthErrorHasFrenchDescription() {
        let err = HealthMapError.auth(.invalidCredentials)
        XCTAssertNotNil(err.errorDescription)
        XCTAssertFalse(err.errorDescription!.isEmpty)
    }

    func testIdentifierIsStableForSameCase() {
        let a = HealthMapError.network(.timeout)
        let b = HealthMapError.network(.timeout)
        XCTAssertEqual(a.identifier, b.identifier)
    }

    func testIdentifierDiffersBetweenCases() {
        XCTAssertNotEqual(
            HealthMapError.network(.timeout).identifier,
            HealthMapError.network(.offline).identifier
        )
    }

    func testOfflineShouldNotBeReported() {
        // Offline is an expected, user-recoverable state — don't flood Sentry.
        XCTAssertFalse(HealthMapError.network(.offline).shouldReport)
    }

    func testServerErrorShouldBeReported() {
        XCTAssertTrue(HealthMapError.network(.serverError(statusCode: 500)).shouldReport)
    }

    func testFromMapsURLErrorToNetwork() {
        let urlErr = URLError(.notConnectedToInternet)
        let mapped = HealthMapError.from(urlErr)
        if case .network = mapped { } else {
            XCTFail("Expected .network case, got \(mapped)")
        }
    }
}
