import SwiftUI
import RevenueCat
import UIKit

@main
struct HealthMapApp: App {
    // MARK: - Environment objects

    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var subscriptionService = SubscriptionService.shared
    @StateObject private var pushService = PushNotificationService.shared
    @StateObject private var connectivity = ConnectivityService.shared

    /// Device integrity warning shown as a persistent alert if jailbreak is detected.
    @State private var showIntegrityWarning = false
    @State private var integrityMessage = ""

    // MARK: - AppDelegate (needed for APNs callbacks)

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - Init

    init() {
        // 1. Crash reporting FIRST, so it captures every subsequent failure.
        CrashReportingService.shared.start()

        // 2. Structured logging is now ready.
        AppLogger.app.info("HealthMap launching (env: \(AppConfig.shared.environment.rawValue, privacy: .public), version: \(AppConfig.shared.versionTag, privacy: .public))")

        // 3. Configure Supabase (auth + DB + Edge Functions + Storage).
        //    Supabase Auth gère persistence Keychain + refresh token nativement.
        //    Migration depuis Clerk : 2026-06-06.
        SupabaseService.shared.configure()

        // 5. Configure RevenueCat (reads from AppConfig).
        Purchases.logLevel = AppConfig.shared.environment == .production ? .error : .info
        Purchases.configure(withAPIKey: AppConfig.shared.revenueCatAPIKey)

        // 6. Connectivity monitor. Needs to start before the first network
        //    call so the global offline banner can react to cold-start loss
        //    of signal (e.g. user in airplane mode on first launch).
        ConnectivityService.shared.start()

        // 7. Analytics (PostHog if configured, otherwise Supabase table, otherwise noop).
        AnalyticsService.shared.start()
        AnalyticsService.shared.track(.appLaunched, properties: [
            "version": AppConfig.shared.versionTag,
            "environment": AppConfig.shared.environment.rawValue
        ])

        // 8. StoreKit 2 AppTransaction verification (anti-tampering, non-blocking).
        Task { @MainActor in
            await ReceiptValidationService.shared.verifyAppTransaction()
        }
    }

    // MARK: - Scene

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(subscriptionService)
                .environmentObject(pushService)
                .environmentObject(connectivity)
                .tint(Color.healthMapBlue)
                // Dynamic Type: clamp to a readable range.
                // Accessibility users can still scale up, but we cap at
                // .accessibility3 so layouts don't break.
                .dynamicTypeSize(.large ... .accessibility3)
                .task {
                    await pushService.refreshAuthorizationStatus()

                    // 8. Device integrity check (jailbreak detection — non-blocking).
                    let integrityResult = DeviceIntegrityService.shared.check()
                    if integrityResult.isCompromised, let message = integrityResult.alertMessage {
                        integrityMessage = message
                        showIntegrityWarning = true

                        AnalyticsService.shared.track(.errorOccurred, properties: [
                            "type": "device_integrity",
                            "warnings_count": "\(integrityResult.warnings.count)"
                        ])
                    }
                }
                .alert("Avertissement de securite", isPresented: $showIntegrityWarning) {
                    Button("J'ai compris", role: .cancel) { }
                } message: {
                    Text(integrityMessage)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Re-verify entitlements every 24h when foregrounded
                        Task { @MainActor in
                            guard let session = await AuthService.shared.currentSession else { return }
                            await ReceiptValidationService.shared.verifyIfNeeded(userId: session.user.id.uuidString)
                        }
                    }
                }
        }
    }
}

// MARK: - AppDelegate

/// Minimal AppDelegate used only for APNs integration and background tasks.
/// Everything else lives in SwiftUI.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppLogger.app.info("didFinishLaunchingWithOptions")
        return true
    }

    // MARK: - APNs callbacks

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleAPNsRegistrationSuccess(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleAPNsRegistrationFailure(error: error)
        }
    }
}
