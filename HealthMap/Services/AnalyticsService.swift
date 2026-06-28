import Foundation

// MARK: - Analytics Events
enum AnalyticsEvent: String {
    // App lifecycle
    case appLaunched = "app_launched"
    case appBackgrounded = "app_backgrounded"

    // Onboarding
    case onboardingStarted = "onboarding_started"
    case onboardingCompleted = "onboarding_completed"
    case onboardingSkipped = "onboarding_skipped"

    // Auth
    case signUpStarted = "signup_started"
    case signUpCompleted = "signup_completed"
    case signInCompleted = "signin_completed"
    case signOutCompleted = "signout_completed"
    case passwordResetRequested = "password_reset_requested"
    case accountDeletionRequested = "account_deletion_requested"
    case accountDeletionCompleted = "account_deletion_completed"
    case accountDeletionFailed = "account_deletion_failed"

    // Questionnaire
    case questionnaireStarted = "questionnaire_started"
    case questionnaireSectionCompleted = "questionnaire_section_completed"
    case questionnaireCompleted = "questionnaire_completed"
    case questionnairePathwayChosen = "questionnaire_pathway_chosen"

    // Analysis
    case analysisStarted = "analysis_started"
    case analysisCompleted = "analysis_completed"
    case analysisFailed = "analysis_failed"
    case analysisFromCache = "analysis_from_cache"

    // Dashboard
    case dashboardViewed = "dashboard_viewed"
    case nutrientTapped = "nutrient_tapped"
    case actionOfTheDayTapped = "action_of_the_day_tapped"

    // Mon Plan
    case recommendationsViewed = "recommendations_viewed"
    case interactionViewed = "interaction_viewed"

    // Paywall
    case paywallShown = "paywall_shown"
    case paywallDismissed = "paywall_dismissed"
    case paywallConverted = "paywall_converted"

    // Subscription
    case subscriptionStarted = "subscription_started"
    case subscriptionCancelled = "subscription_cancelled"
    case subscriptionRestored = "subscription_restored"

    // Checkin & Gamification
    case checkinCompleted = "checkin_completed"
    case zenModeToggled = "zen_mode_toggled"

    // Scan
    case mealScanned = "meal_scanned"
    case productScanned = "product_scanned"

    // Export & Share
    case pdfExported = "pdf_exported"
    case dataExported = "data_exported"
    case scoreShared = "score_shared"

    // Errors
    case errorOccurred = "error_occurred"

    // Screens
    case screenViewed = "screen_viewed"
}

// MARK: - AnalyticsService
/// Fans events out to multiple sinks:
///   1. `os.Logger` — always, for local debugging + Console.app
///   2. `CrashReportingService` breadcrumbs — so Sentry captures the last ~100
///      events before a crash
///   3. Supabase `analytics_events` table — if `SupabaseService.client` is
///      configured (see step 8 of README-SETUP.md for the DDL)
///   4. PostHog EU (`https://eu.i.posthog.com`) — if `POSTHOG_API_KEY` is set
///      in `Config.xcconfig`. No PostHog SDK is embedded: we POST directly to
///      the `/capture/` endpoint to keep the binary small and to avoid the
///      App Store review friction of a 3rd-party analytics SDK.
///
/// Respects user privacy:
///   - Never sends `questionnaire_data`, `ai_analysis`, or free-text health content
///   - Event properties are whitelisted at the call site — don't pass arbitrary objects
///   - Can be fully reset on sign out via `reset()`
///   - PostHog host is pinned to the EU region for RGPD compliance
///
/// **Concurrency** : pinned to `@MainActor` because every call-site is either
/// a SwiftUI View, a `@MainActor` ViewModel, or another `@MainActor` service.
/// All mutable state (`isStarted`, `currentUserId`, `postHogDistinctId`) is
/// therefore protected by MainActor isolation rather than ad-hoc dispatch.
@MainActor
final class AnalyticsService: AnalyticsServiceProtocol {

    static let shared = AnalyticsService()
    private init() {}

    // MARK: - State

    private var isStarted = false
    private var currentUserId: String?

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        // PostHog has no SDK init step here: we call `eu.i.posthog.com/capture/`
        // directly via URLSession (see `postHogCapture`/`postHogIdentify`).
        // If `AppConfig.shared.posthogAPIKey` is nil, both methods early-return
        // and no network traffic is sent — zero dependency cost for installs
        // that haven't configured a key.
        AppLogger.analytics.info("AnalyticsService started (posthog_enabled=\(AppConfig.shared.posthogAPIKey != nil, privacy: .public))")
    }

    // MARK: - Tracking

    func track(_ event: AnalyticsEvent, properties: [String: any Sendable]? = nil) {
        // Sanitise to `[String: String]` *before* any actor hop so the values
        // we ship to async sinks are unconditionally `Sendable`.
        let safeProps: [String: String] = Self.sanitize(properties)

        // 1. Local log
        AppLogger.analytics.debug("\(event.rawValue, privacy: .public) \(String(describing: safeProps), privacy: .public)")

        // 2. Sentry breadcrumb (last N events before any crash/error will be attached)
        CrashReportingService.shared.breadcrumb(event.rawValue, category: "analytics", level: .info)

        // 3. Supabase analytics table — fire-and-forget. Capture user-id by
        // value so the detached Task does not need to hop back to MainActor.
        let snapshotUserId = currentUserId
        Task.detached { [safeProps] in
            await Self.supabaseCapture(
                event: event,
                userId: snapshotUserId,
                properties: safeProps
            )
        }

        // 4. PostHog
        postHogCapture(event: event, properties: safeProps)
    }

    func trackScreen(_ name: String) {
        track(.screenViewed, properties: ["screen": name])
    }

    // MARK: - Identity

    func identify(userId: String, traits: [String: any Sendable]? = nil) {
        currentUserId = userId
        CrashReportingService.shared.identify(userId: userId)
        postHogIdentify(userId: userId, traits: Self.sanitize(traits))
        AppLogger.analytics.info("Analytics identify userId=\(userId, privacy: .private(mask: .hash))")
    }

    func reset() {
        currentUserId = nil
        postHogDistinctId = nil
        CrashReportingService.shared.clearUser()
        AppLogger.analytics.info("Analytics reset")
    }

    // MARK: - Supabase sink

    /// Static (no-actor) helper so we don't have to hop back to MainActor for
    /// the network write. All inputs are `Sendable` value types — the only
    /// shared resource touched here is the global `SupabaseService.shared`
    /// client (which is itself thread-safe per Supabase SDK documentation)
    /// and the `OfflineQueueService` actor (which guards its own state).
    private static func supabaseCapture(
        event: AnalyticsEvent,
        userId: String?,
        properties: [String: String]
    ) async {
        guard SupabaseService.shared.safeClient != nil else { return }
        // RLS `events_self_insert` exige `user_id = current_user_id()` : les
        // événements anonymes (avant identify) seraient rejetés — ils ne
        // partent qu'à PostHog, jamais vers Supabase.
        guard let userId else { return }
        // Schéma DB réel : user_id / event_name / properties / occurred_at.
        // app_version et environment voyagent DANS `properties` (jsonb) —
        // l'ancien payload envoyait des colonnes inexistantes → 400 en boucle.
        struct Row: Encodable, Sendable {
            let user_id: String
            let event_name: String
            let properties: [String: String]
            let occurred_at: String
        }
        // `AppConfig` is a plain `final class` whose values are immutable
        // after init — safe to read from any actor.
        var props = properties
        props["app_version"] = AppConfig.shared.versionTag
        props["environment"] = AppConfig.shared.environment.rawValue
        let row = Row(
            user_id: userId,
            event_name: event.rawValue,
            properties: props,
            occurred_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await SupabaseService.shared.client
                .from("analytics_events")
                .insert(row)
                .execute()
        } catch {
            // Analytics failures must NEVER affect UX — queue for retry.
            AppLogger.analytics.notice("Supabase analytics insert failed, queuing: \(error.localizedDescription, privacy: .public)")
            let payload = AnalyticsEventPayload(
                userId: row.user_id,
                eventName: row.event_name,
                properties: row.properties,
                occurredAt: row.occurred_at
            )
            OfflineQueueService.shared.enqueue(type: .analyticsEvent, payload: payload)
        }
    }

    // MARK: - PostHog sink

    /// Direct HTTP implementation of the PostHog `/capture/` endpoint.
    /// We intentionally avoid the PostHog SDK to keep the dependency graph
    /// small and App Store review friendly. Payload shape matches
    /// https://posthog.com/docs/api/post-only-endpoints
    nonisolated private static let postHogHost = "https://eu.i.posthog.com"
    private var postHogDistinctId: String?

    private func postHogCapture(event: AnalyticsEvent, properties: [String: String]) {
        guard let apiKey = AppConfig.shared.posthogAPIKey else { return }

        // Snapshot all MainActor-isolated state into Sendable locals before
        // the detached Task fires.
        let distinctId = postHogDistinctId ?? "anonymous"

        var merged: [String: Any] = properties
        merged["$lib"] = "healthmap-ios"
        merged["$lib_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let payload: [String: Any] = [
            "api_key": apiKey,
            "event": event.rawValue,
            "distinct_id": distinctId,
            "properties": merged,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        guard
            let url = URL(string: "\(Self.postHogHost)/capture/"),
            let body = try? JSONSerialization.data(withJSONObject: payload)
        else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let request = req // immutable copy for the detached task

        Task.detached { [properties] in
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                AppLogger.analytics.notice("PostHog capture failed, queuing: \(error.localizedDescription, privacy: .public)")
                // API key intentionally excluded from queued payload — injected at flush time
                let queuePayload = PostHogEventPayload(
                    event: event.rawValue,
                    distinctId: distinctId,
                    properties: properties,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                OfflineQueueService.shared.enqueue(type: .analyticsPostHog, payload: queuePayload)
            }
        }
    }

    private func postHogIdentify(userId: String, traits: [String: String]) {
        guard let apiKey = AppConfig.shared.posthogAPIKey else { return }
        postHogDistinctId = userId

        let payload: [String: Any] = [
            "api_key": apiKey,
            "event": "$identify",
            "distinct_id": userId,
            "properties": ["$set": traits],
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        guard
            let url = URL(string: "\(Self.postHogHost)/capture/"),
            let body = try? JSONSerialization.data(withJSONObject: payload)
        else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let request = req

        Task.detached {
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    // MARK: - PII sanitisation

    /// Converts a loose `[String: Any]?` to a `[String: String]` while stripping
    /// any key that could contain PII or sensitive health data.
    nonisolated private static let forbiddenKeys: Set<String> = [
        "email", "password", "first_name", "last_name", "name",
        "questionnaire_data", "ai_analysis", "symptoms", "medications",
        "period_flow", "pregnancy_status", "height", "weight", "age", "phone"
    ]

    /// Test hook: exposes the sanitizer so unit tests can assert PII stripping
    /// without going through the full Supabase/PostHog pipeline.
    /// NOT for production call sites — use `track(_:properties:)` instead.
    nonisolated static func sanitizeForTesting(_ properties: [String: any Sendable]?) -> [String: String] {
        sanitize(properties)
    }

    nonisolated private static func sanitize(_ properties: [String: any Sendable]?) -> [String: String] {
        guard let properties else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in properties {
            if forbiddenKeys.contains(key.lowercased()) { continue }
            // Coerce to string, cap length to 256 chars to avoid huge payloads.
            let str = String(describing: value)
            result[key] = String(str.prefix(256))
        }
        return result
    }
}
