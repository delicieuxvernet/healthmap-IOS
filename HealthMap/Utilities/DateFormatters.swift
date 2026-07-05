import Foundation

// MARK: - Shared cached DateFormatter instances
// DateFormatter creation is expensive (~1-2ms). Cache them for hot paths
// (Checkin, GamificationService, ScoreHistory, DatabaseService).
enum DateFormatters {

    /// "yyyy-MM-dd" — dates locales, clé primaire des checkins et scores quotidiens
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// ISO 8601 avec timezone — payloads Supabase et analytics
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// "yyyy-MM-dd'T'HH:mm:ssZ" — fallback pour timestamps sans fractions
    static let iso8601Simple: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// « il y a 12 min » / « hier » — recap dernier scan (écran Scan).
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .full
        return f
    }()
}
