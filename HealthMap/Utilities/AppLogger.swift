import Foundation
import os.log

// MARK: - AppLogger
/// Centralized logging facade built on top of Apple's unified logging system (os.Logger).
/// Replaces all `print()` calls throughout the app.
///
/// Benefits vs print():
/// - Free: integrated with Console.app, Instruments, and sysdiagnose
/// - Privacy-aware: PII is stripped in release builds by default
/// - Filterable by category and subsystem
/// - Persistent: logs are available after crashes
///
/// Usage:
///     AppLogger.auth.info("User signed in")
///     AppLogger.database.error("Failed to load profile: \(error.localizedDescription, privacy: .public)")
///     AppLogger.analysis.debug("Generated scores: \(scores, privacy: .private)")
enum AppLogger {

    static let subsystem = Bundle.main.bundleIdentifier ?? "fr.healthmap.app"

    // MARK: - Categories

    static let app = Logger(subsystem: subsystem, category: "app")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let database = Logger(subsystem: subsystem, category: "database")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let analysis = Logger(subsystem: subsystem, category: "analysis")
    static let subscription = Logger(subsystem: subsystem, category: "subscription")
    static let analytics = Logger(subsystem: subsystem, category: "analytics")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let push = Logger(subsystem: subsystem, category: "push")
    static let crash = Logger(subsystem: subsystem, category: "crash")
}

// MARK: - Convenience extensions

extension Logger {
    /// Logs an error at `.error` level with a structured payload and forwards it to Sentry.
    func report(_ error: Error, context: String? = nil, file: String = #file, line: Int = #line) {
        let desc = error.localizedDescription
        if let context {
            self.error("[\(context, privacy: .public)] \(desc, privacy: .public) (file: \(file, privacy: .public):\(line))")
        } else {
            self.error("\(desc, privacy: .public) (file: \(file, privacy: .public):\(line))")
        }
        CrashReportingService.shared.capture(error: error, context: context, file: file, line: line)
    }
}
