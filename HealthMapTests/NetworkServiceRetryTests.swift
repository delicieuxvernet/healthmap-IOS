import XCTest
@testable import HealthMap

/// Verifies that NetworkService.withRetry actually retries transient failures
/// and gives up after maxAttempts, without retrying permanent errors.
final class NetworkServiceRetryTests: XCTestCase {

    func testRetriesTransientErrorAndEventuallySucceeds() async throws {
        var attempts = 0
        let fastPolicy = NetworkService.RetryPolicy(
            maxAttempts: 3, initialDelay: 0.01, maxDelay: 0.02,
            backoffMultiplier: 1.0, jitter: 0
        )
        let result: Int = try await NetworkService.shared.withRetry(policy: fastPolicy) {
            attempts += 1
            if attempts < 3 { throw HealthMapError.network(.timeout) }
            return 42
        }
        XCTAssertEqual(result, 42)
        XCTAssertEqual(attempts, 3)
    }

    func testDoesNotRetryPermanentError() async {
        var attempts = 0
        let fastPolicy = NetworkService.RetryPolicy(
            maxAttempts: 5, initialDelay: 0.01, maxDelay: 0.02,
            backoffMultiplier: 1.0, jitter: 0
        )
        do {
            let _: Int = try await NetworkService.shared.withRetry(policy: fastPolicy) {
                attempts += 1
                throw HealthMapError.auth(.invalidCredentials)
            }
            XCTFail("Expected error to be thrown")
        } catch {
            // Auth errors are not transient; should fire once.
            XCTAssertEqual(attempts, 1)
        }
    }

    func testGivesUpAfterMaxAttempts() async {
        var attempts = 0
        let fastPolicy = NetworkService.RetryPolicy(
            maxAttempts: 2, initialDelay: 0.01, maxDelay: 0.02,
            backoffMultiplier: 1.0, jitter: 0
        )
        do {
            let _: Int = try await NetworkService.shared.withRetry(policy: fastPolicy) {
                attempts += 1
                throw HealthMapError.network(.timeout)
            }
            XCTFail("Expected error after retries exhausted")
        } catch {
            XCTAssertEqual(attempts, 2)
        }
    }
}
