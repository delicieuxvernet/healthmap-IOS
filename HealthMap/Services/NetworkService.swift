import Foundation

// MARK: - NetworkService
/// Thin wrapper that adds retry-with-exponential-backoff and typed errors
/// around async throwing work. Use it around any call that hits the network
/// (Supabase, Anthropic, Stripe) to get resilience for free.
///
/// Usage:
///     let profile = try await NetworkService.shared.withRetry(attempts: 3) {
///         try await DatabaseService.shared.loadProfile(userId: uid)
///     }
///
/// This service is intentionally stateless and is NOT a URLSession wrapper —
/// it simply provides retry semantics around any `() async throws -> T`.
final class NetworkService {

    static let shared = NetworkService()
    private init() {}

    // MARK: - Configuration

    struct RetryPolicy {
        /// Maximum number of attempts including the first.
        var maxAttempts: Int = 3
        /// Base delay applied before the first retry (doubles each subsequent attempt).
        var initialDelay: TimeInterval = 0.4
        /// Maximum delay between retries (clamps exponential growth).
        var maxDelay: TimeInterval = 6.0
        /// Multiplier applied each attempt (2.0 = exponential).
        var backoffMultiplier: Double = 2.0
        /// Jitter factor (0..1) applied to each delay to avoid thundering herd.
        var jitter: Double = 0.2

        static let `default` = RetryPolicy()
        static let aggressive = RetryPolicy(maxAttempts: 5, initialDelay: 0.5, maxDelay: 10.0)
        static let conservative = RetryPolicy(maxAttempts: 2, initialDelay: 0.3, maxDelay: 2.0)
    }

    // MARK: - Retry runner

    /// Runs the operation up to `policy.maxAttempts` times, retrying on transient errors only.
    /// Transient errors are: URLError (network), HealthMapError.network (except offline/rate limit).
    func withRetry<T>(
        policy: RetryPolicy = .default,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var currentDelay = policy.initialDelay
        var lastError: Error?

        while attempt < policy.maxAttempts {
            attempt += 1
            do {
                let value = try await operation()
                if attempt > 1 {
                    AppLogger.network.info("Operation succeeded on retry \(attempt, privacy: .public)")
                }
                return value
            } catch {
                lastError = error
                let mapped = HealthMapError.from(error)

                // Don't retry non-transient errors (auth failures, permission denied, etc.)
                guard Self.isTransient(mapped), attempt < policy.maxAttempts else {
                    AppLogger.network.report(error, context: "NetworkService.withRetry (non-transient)")
                    throw mapped
                }

                // Apply jitter to delay
                let jitterRange = currentDelay * policy.jitter
                let sleepDelay = currentDelay + Double.random(in: -jitterRange...jitterRange)

                AppLogger.network.notice("Transient error on attempt \(attempt, privacy: .public), retrying in \(sleepDelay, privacy: .public)s")
                CrashReportingService.shared.breadcrumb(
                    "retry attempt \(attempt) after \(String(format: "%.2f", sleepDelay))s",
                    category: "network",
                    level: .info
                )

                try? await Task.sleep(nanoseconds: UInt64(sleepDelay * 1_000_000_000))
                currentDelay = min(currentDelay * policy.backoffMultiplier, policy.maxDelay)
            }
        }

        throw HealthMapError.from(lastError ?? HealthMapError.network(.unknown("unknown")))
    }

    // MARK: - Transient classification

    private static func isTransient(_ error: HealthMapError) -> Bool {
        switch error {
        case .network(.offline), .network(.timeout):
            return true
        case .network(.serverError(let code)) where code >= 500:
            return true
        case .network(.rateLimited):
            return true
        case .network(.unknown):
            return true
        default:
            return false
        }
    }
}
