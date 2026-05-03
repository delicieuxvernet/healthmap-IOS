import Foundation
import Security

// MARK: - LoginThrottleService
/// Client-side rate limiting for authentication attempts.
///
/// Escalating delays:
///   - After 3 failures:  30 seconds
///   - After 5 failures:  60 seconds
///   - After 10 failures: 5 minutes
///   - After 15 failures: 15 minutes
///
/// The failure counter is persisted in the iOS Keychain (not UserDefaults)
/// so it survives app reinstalls and cannot be trivially reset by clearing
/// app data. Resets automatically on a successful login.
final class LoginThrottleService {

    static let shared = LoginThrottleService()

    // MARK: - Keychain Keys

    private static let keychainService = "fr.healthmap.loginthrottle"
    private static let failureCountAccount = "failure_count"
    private static let lastFailureAccount = "last_failure_timestamp"

    // MARK: - Throttle Tiers

    private struct ThrottleTier {
        let failureThreshold: Int
        let delay: TimeInterval
    }

    /// Sorted descending so the first match gives the strictest applicable tier.
    private static let tiers: [ThrottleTier] = [
        ThrottleTier(failureThreshold: 15, delay: 15 * 60),  // 15 min
        ThrottleTier(failureThreshold: 10, delay: 5 * 60),   // 5 min
        ThrottleTier(failureThreshold: 5,  delay: 60),       // 60 sec
        ThrottleTier(failureThreshold: 3,  delay: 30),       // 30 sec
    ]

    private init() {}

    // MARK: - Public API

    /// Checks whether a login attempt is currently allowed.
    /// - Returns: A tuple where `allowed` is true if the user can attempt login,
    ///   and `retryAfter` contains the remaining wait time in seconds if throttled.
    func canAttempt() -> (allowed: Bool, retryAfter: TimeInterval?) {
        let failures = loadFailureCount()
        guard let delay = delayForFailures(failures) else {
            // Under threshold — always allowed
            return (allowed: true, retryAfter: nil)
        }

        let lastFailure = loadLastFailureTimestamp()
        let elapsed = Date().timeIntervalSince1970 - lastFailure
        let remaining = delay - elapsed

        if remaining <= 0 {
            return (allowed: true, retryAfter: nil)
        }

        return (allowed: false, retryAfter: remaining)
    }

    /// Records a failed login attempt. Increments the counter and updates
    /// the last-failure timestamp.
    func recordFailure() {
        let current = loadFailureCount()
        let newCount = current + 1
        saveFailureCount(newCount)
        saveLastFailureTimestamp(Date().timeIntervalSince1970)

        AppLogger.auth.notice("LoginThrottle: failure #\(newCount, privacy: .public)")

        if let delay = delayForFailures(newCount) {
            AppLogger.auth.notice("LoginThrottle: next attempt blocked for \(Int(delay), privacy: .public)s")
        }
    }

    /// Resets the failure counter. Call on successful authentication.
    func reset() {
        saveFailureCount(0)
        saveLastFailureTimestamp(0)
        AppLogger.auth.info("LoginThrottle: counter reset (successful login)")
    }

    /// User-facing message for the current throttle state (in French).
    func throttleMessage() -> String? {
        let check = canAttempt()
        guard let remaining = check.retryAfter, !check.allowed else { return nil }

        if remaining >= 60 {
            let minutes = Int(ceil(remaining / 60))
            return "Trop de tentatives. Reessayez dans \(minutes) minute\(minutes > 1 ? "s" : "")."
        } else {
            let seconds = Int(ceil(remaining))
            return "Trop de tentatives. Reessayez dans \(seconds) seconde\(seconds > 1 ? "s" : "")."
        }
    }

    // MARK: - Throttle Logic

    private func delayForFailures(_ count: Int) -> TimeInterval? {
        for tier in Self.tiers {
            if count >= tier.failureThreshold {
                return tier.delay
            }
        }
        return nil
    }

    // MARK: - Keychain Persistence

    private func loadFailureCount() -> Int {
        guard let data = loadKeychainData(account: Self.failureCountAccount),
              let str = String(data: data, encoding: .utf8),
              let count = Int(str) else { return 0 }
        return count
    }

    private func saveFailureCount(_ count: Int) {
        let data = "\(count)".data(using: .utf8) ?? Data()
        saveKeychainData(data, account: Self.failureCountAccount)
    }

    private func loadLastFailureTimestamp() -> TimeInterval {
        guard let data = loadKeychainData(account: Self.lastFailureAccount),
              let str = String(data: data, encoding: .utf8),
              let ts = Double(str) else { return 0 }
        return ts
    }

    private func saveLastFailureTimestamp(_ timestamp: TimeInterval) {
        let data = "\(timestamp)".data(using: .utf8) ?? Data()
        saveKeychainData(data, account: Self.lastFailureAccount)
    }

    // MARK: - Keychain Helpers

    private func saveKeychainData(_ data: Data, account: String) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadKeychainData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}
