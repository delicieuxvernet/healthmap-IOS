import Foundation
import UserNotifications
import UIKit

// MARK: - PushNotificationService
/// Handles the full lifecycle of push notifications:
/// - Requesting permission at the right moment (NOT at launch — wait for the first value-delivery screen)
/// - Registering with APNs
/// - Persisting the token in Supabase so the backend can target the user
/// - Handling incoming notifications (foreground + background taps)
///
/// Apple Review requirement: NEVER ask for notification permission on first launch.
/// Wait until the user has completed onboarding + has a reason to care (e.g. right before the
/// dashboard appears for the first time). We expose `requestAuthorizationIfNeeded()` for that.
@MainActor
final class PushNotificationService: NSObject, ObservableObject {

    static let shared = PushNotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?

    /// The latest deep-link requested by a notification tap.
    /// Views can observe this to route to the matching screen
    /// (e.g. `.dashboard`, `.recommendations`, `.checkin`, `.mealScan`).
    @Published var pendingRoute: DeepLinkRoute?

    /// Deep-link routes supported by push payloads AND Universal Links.
    /// Edge Functions send `userInfo["screen"]` as one of these raw values;
    /// Universal Links from `https://healthmap.fr/<path>` are mapped via
    /// `fromURLPath(_:)` below. Both pipelines feed `pendingRoute`, which
    /// `MainTabView.consumePendingRoute()` reads on cold start (`.onAppear`)
    /// and warm start (`.onChange`).
    enum DeepLinkRoute: String, Equatable {
        case dashboard
        case recommendations
        case checkin
        case mealScan = "meal_scan"
        case profile
        case paywall

        /// Maps a URL path component to a `DeepLinkRoute`. Used by the
        /// Universal Links handler in `ContentView` to translate
        /// `https://healthmap.fr/<path>` into the same routing primitive
        /// that push payloads use.
        ///
        /// Path matching is intentionally forgiving so marketing URLs and
        /// hand-typed shortcuts both work:
        ///   - leading and trailing slashes are stripped
        ///   - matching is case-insensitive
        ///   - both English (`profile`, `recommendations`) and French
        ///     (`profil`, `mon-plan`) slugs resolve to the same route, so
        ///     a localized newsletter link doesn't break the app
        ///   - unknown paths fall back to `.dashboard` rather than dropping
        ///     the navigation silently — the user always lands SOMEWHERE
        ///     they recognize, even if the link was malformed
        static func fromURLPath(_ path: String) -> DeepLinkRoute {
            let normalized = path
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            switch normalized {
            case "", "dashboard", "home", "bilan":
                return .dashboard
            case "checkin", "check-in", "suivi":
                return .checkin
            case "scanner", "scan", "meal-scan", "mealscan":
                return .mealScan
            case "plan", "recommendations", "mon-plan":
                return .recommendations
            case "profil", "profile":
                return .profile
            case "premium", "paywall", "abonnement":
                return .paywall
            default:
                return .dashboard
            }
        }
    }

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.authorizationStatus = settings.authorizationStatus
    }

    /// Call from the first screen that benefits from notifications (e.g. Dashboard after first bilan).
    /// Returns `true` if the user granted permission.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorizationStatus()
        guard authorizationStatus == .notDetermined else {
            return authorizationStatus == .authorized
        }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            if granted {
                AppLogger.push.info("Push authorization granted")
                await registerForRemoteNotifications()
            } else {
                AppLogger.push.notice("Push authorization declined")
            }
            AnalyticsService.shared.track(.screenViewed, properties: ["push_auth": granted ? "granted" : "declined"])
            return granted
        } catch {
            AppLogger.push.report(error, context: "requestAuthorization")
            return false
        }
    }

    /// Triggers APNs registration. Must be called on the main thread.
    private func registerForRemoteNotifications() async {
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - APNs token callbacks (wired from AppDelegate / App lifecycle)

    func handleAPNsRegistrationSuccess(deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = tokenString
        AppLogger.push.info("APNs token received (\(tokenString.count, privacy: .public) chars)")

        // Persist token in Supabase `profiles.push_token` so backend can target this device.
        Task {
            do {
                try await DatabaseService.shared.updatePushToken(tokenString)
                CrashReportingService.shared.breadcrumb("push token saved", category: "push", level: .info)
            } catch {
                AppLogger.push.report(error, context: "save push token")
            }
        }
    }

    func handleAPNsRegistrationFailure(error: Error) {
        AppLogger.push.report(error, context: "APNs registration failed")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: UNUserNotificationCenterDelegate {

    /// Called when a notification arrives while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Called when the user taps a notification.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            AnalyticsService.shared.track(.screenViewed, properties: ["from_notification": "true"])
            AppLogger.push.info("User tapped notification: \(String(describing: userInfo), privacy: .private)")

            // Deep-link routing: map userInfo["screen"] → DeepLinkRoute
            if let screen = userInfo["screen"] as? String,
               let route = DeepLinkRoute(rawValue: screen) {
                PushNotificationService.shared.pendingRoute = route
                AppLogger.push.info("Deep-link route set: \(route.rawValue, privacy: .public)")
            }
        }
        completionHandler()
    }
}
