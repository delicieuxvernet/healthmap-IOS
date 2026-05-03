import XCTest
@testable import HealthMap

/// Verifies that the AnalyticsService sanitizer strips PII and health-sensitive keys.
/// Critical for RGPD Article 9 compliance: we must never leak health data to
/// third-party analytics, even by accident via a property dictionary.
final class AnalyticsPIIStrippingTests: XCTestCase {

    func testSanitizerStripsEmailAndName() throws {
        // Call through the public `track` API, then verify the value that
        // would have gone to downstream sinks. We use reflection via a
        // dedicated test-only helper exposed on AnalyticsService if available,
        // otherwise we test the static `sanitize` through a wrapper.
        let input: [String: Any] = [
            "email": "arthur@example.com",
            "first_name": "Arthur",
            "screen": "dashboard",
            "session_id": "abc123"
        ]
        let output = AnalyticsService.sanitizeForTesting(input)
        XCTAssertNil(output["email"])
        XCTAssertNil(output["first_name"])
        XCTAssertEqual(output["screen"], "dashboard")
        XCTAssertEqual(output["session_id"], "abc123")
    }

    func testSanitizerStripsHealthSensitiveKeys() {
        let input: [String: Any] = [
            "symptoms": "fatigue, migraine",
            "questionnaire_data": ["q1": "yes"],
            "ai_analysis": "long text",
            "pregnancy_status": "pregnant",
            "keep_me": "ok"
        ]
        let output = AnalyticsService.sanitizeForTesting(input)
        XCTAssertNil(output["symptoms"])
        XCTAssertNil(output["questionnaire_data"])
        XCTAssertNil(output["ai_analysis"])
        XCTAssertNil(output["pregnancy_status"])
        XCTAssertEqual(output["keep_me"], "ok")
    }

    func testLongValuesAreCapped() {
        let longString = String(repeating: "x", count: 1000)
        let output = AnalyticsService.sanitizeForTesting(["note": longString])
        XCTAssertLessThanOrEqual(output["note"]?.count ?? 0, 256)
    }
}
