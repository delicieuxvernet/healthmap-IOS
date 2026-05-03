import Foundation
#if canImport(Sentry)
import Sentry
#endif

// MARK: - CrashReportingService
/// Wraps Sentry so the rest of the app never imports Sentry directly.
/// This lets us swap the SDK in the future (e.g. for TelemetryDeck or Bugsnag) without touching call sites.
///
/// Privacy & RGPD:
/// - `beforeSend` strips the user email from the event's `user` payload
/// - We never attach `questionnaire_data`, `ai_analysis`, or any free-text health content
/// - `sendDefaultPii` is explicitly disabled
/// - Breadcrumbs are filtered to drop PII-containing messages
///
/// Setup:
/// 1. Add Sentry via SPM: `https://github.com/getsentry/sentry-cocoa` (branch: main, or Up to Next Major from 8.0.0)
/// 2. Set `SENTRY_DSN` in Config.xcconfig
/// 3. Call `CrashReportingService.shared.start()` from HealthMapApp.init()
final class CrashReportingService {

    static let shared = CrashReportingService()
    private(set) var isStarted = false
    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        guard let dsn = AppConfig.shared.sentryDSN, !dsn.isEmpty, dsn != "YOUR_SENTRY_DSN" else {
            AppLogger.crash.notice("Sentry DSN missing, crash reporting disabled.")
            return
        }

        #if canImport(Sentry)
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = AppConfig.shared.environment.rawValue
            options.releaseName = AppConfig.shared.versionTag
            options.debug = false
            options.sendDefaultPii = false
            options.attachStacktrace = true
            options.enableAutoPerformanceTracing = true
            options.tracesSampleRate = AppConfig.shared.environment == .production ? 0.1 : 1.0
            options.enableAutoSessionTracking = true

            // Strip PII before every send.
            options.beforeSend = { event in
                event.user?.email = nil
                event.user?.ipAddress = nil
                event.extra?.removeValue(forKey: "questionnaire_data")
                event.extra?.removeValue(forKey: "ai_analysis")
                return event
            }

            // Filter breadcrumbs that might contain email or free-text health data.
            options.beforeBreadcrumb = { crumb in
                let sensitive = ["email", "password", "symptom", "medication"]
                if let message = crumb.message?.lowercased(),
                   sensitive.contains(where: message.contains) {
                    return nil
                }
                return crumb
            }
        }
        isStarted = true
        AppLogger.crash.info("Sentry started (env: \(AppConfig.shared.environment.rawValue, privacy: .public))")
        #else
        AppLogger.crash.notice("Sentry SDK not available at compile time. Add the package via SPM.")
        #endif
    }

    // MARK: - User identification

    /// Associates a user id with crash reports. NEVER pass email or personal info.
    func identify(userId: String) {
        #if canImport(Sentry)
        let user = Sentry.User(userId: userId)
        SentrySDK.setUser(user)
        #endif
    }

    func clearUser() {
        #if canImport(Sentry)
        SentrySDK.setUser(nil)
        #endif
    }

    // MARK: - Capture

    func capture(error: Error, context: String? = nil, file: String = #file, line: Int = #line) {
        // Respect the HealthMapError.shouldReport policy
        if let mapped = error as? HealthMapError, !mapped.shouldReport {
            return
        }
        #if canImport(Sentry)
        SentrySDK.capture(error: error) { scope in
            if let context {
                scope.setTag(value: context, key: "context")
            }
            scope.setTag(value: (file as NSString).lastPathComponent, key: "file")
            scope.setTag(value: "\(line)", key: "line")
            if let mapped = error as? HealthMapError {
                scope.setTag(value: mapped.identifier, key: "error_id")
            }
        }
        #endif
    }

    func captureMessage(_ message: String, level: CrashLevel = .info) {
        #if canImport(Sentry)
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level.sentryLevel)
        }
        #endif
    }

    /// Adds a breadcrumb to the current scope (will appear attached to the next captured event).
    func breadcrumb(_ message: String, category: String, level: CrashLevel = .info) {
        #if canImport(Sentry)
        let crumb = Breadcrumb()
        crumb.message = message
        crumb.category = category
        crumb.level = level.sentryLevel
        SentrySDK.addBreadcrumb(crumb)
        #endif
    }
}

// MARK: - Level abstraction (so callers don't import Sentry directly)

enum CrashLevel {
    case debug, info, warning, error, fatal

    #if canImport(Sentry)
    var sentryLevel: SentryLevel {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .fatal: return .fatal
        }
    }
    #endif
}
