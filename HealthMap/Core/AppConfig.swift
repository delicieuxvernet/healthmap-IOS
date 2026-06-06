import Foundation

// MARK: - AppConfig
/// Centralised runtime configuration read from Info.plist (which in turn gets populated from Config.xcconfig).
/// This replaces the `YOUR_SUPABASE_ANON_KEY` placeholder strings and prevents accidental commits of live keys.
///
/// Setup flow:
/// 1. Create `Resources/Config.xcconfig` (NOT committed — template provided at Config.xcconfig.example)
/// 2. In Xcode, set the project Configuration file to `Config`
/// 3. In Info.plist, add entries that reference the xcconfig variables (e.g. `$(SUPABASE_ANON_KEY)`)
/// 4. Access values via `AppConfig.shared.supabaseAnonKey`
///
/// All values are read once at startup.
final class AppConfig {

    static let shared = AppConfig()

    // MARK: - Environment

    enum Environment: String { case development, staging, production }

    let environment: Environment
    let versionTag: String

    // MARK: - Secrets

    let supabaseURL: URL
    let supabaseAnonKey: String
    let revenueCatAPIKey: String
    let sentryDSN: String?
    let posthogAPIKey: String?
    let posthogHost: String?

    // MARK: - Init

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]

        // Environment
        let envRaw = (info["APP_ENVIRONMENT"] as? String) ?? "development"
        self.environment = Environment(rawValue: envRaw) ?? .development

        // Version tag = "CFBundleShortVersionString (CFBundleVersion)"
        let short = (info["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        let build = (info["CFBundleVersion"] as? String) ?? "0"
        self.versionTag = "\(short) (\(build))"

        // Supabase — REQUIRED
        let supabaseURLString = info["SUPABASE_URL"] as? String ?? ""
        guard let url = URL(string: supabaseURLString), !supabaseURLString.isEmpty else {
            fatalError("[AppConfig] Missing SUPABASE_URL in Info.plist / Config.xcconfig")
        }
        self.supabaseURL = url

        let key = info["SUPABASE_ANON_KEY"] as? String ?? ""
        precondition(!key.isEmpty, "[AppConfig] Missing SUPABASE_ANON_KEY — vérifier Config.xcconfig")
        self.supabaseAnonKey = key

        // Supabase Auth is used directly (migration retirée de Clerk le 2026-06-06).
        // Plus de CLERK_PUBLISHABLE_KEY requise — l'auth passe par le supabaseAnonKey.

        // RevenueCat — REQUIRED for paywalls
        let rcKey = info["REVENUECAT_API_KEY"] as? String ?? ""
        precondition(!rcKey.isEmpty, "[AppConfig] Missing REVENUECAT_API_KEY — vérifier Config.xcconfig")
        self.revenueCatAPIKey = rcKey

        // Sentry — optional (crash reporting disabled if missing)
        let dsn = info["SENTRY_DSN"] as? String
        self.sentryDSN = (dsn?.isEmpty == false) ? dsn : nil

        // PostHog — optional (analytics forwarding disabled if missing)
        let ph = info["POSTHOG_API_KEY"] as? String
        self.posthogAPIKey = (ph?.isEmpty == false) ? ph : nil
        self.posthogHost = info["POSTHOG_HOST"] as? String ?? "https://eu.posthog.com"
    }
}
