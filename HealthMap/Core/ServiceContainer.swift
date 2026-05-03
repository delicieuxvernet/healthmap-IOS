import Foundation

/// Centralized dependency container that wires all service singletons.
///
/// Production code uses `ServiceContainer.shared` which resolves to the
/// real `.shared` singletons. Tests call `ServiceContainer.makeForTesting(...)`
/// to inject mock implementations without touching production code.
@MainActor
final class ServiceContainer: ObservableObject {

    let auth: AuthServiceProtocol
    let database: DatabaseServiceProtocol
    let subscription: SubscriptionServiceProtocol
    let analytics: AnalyticsServiceProtocol
    let aiAnalysis: AIAnalysisServiceProtocol
    let gamification: GamificationService

    // MARK: - Shared Singleton

    static let shared = ServiceContainer()

    // MARK: - Production Init

    private init() {
        self.auth = AuthService.shared
        self.database = DatabaseService.shared
        self.subscription = SubscriptionService.shared
        self.analytics = AnalyticsService.shared
        self.aiAnalysis = AIAnalysisService.shared
        self.gamification = GamificationService.shared
    }

    // MARK: - Testing Init

    /// Creates a container with injected mock services for unit tests.
    /// Parameters use the production singletons as defaults so callers
    /// only need to override the services under test.
    static func makeForTesting(
        auth: AuthServiceProtocol? = nil,
        database: DatabaseServiceProtocol? = nil,
        subscription: SubscriptionServiceProtocol? = nil,
        analytics: AnalyticsServiceProtocol? = nil,
        aiAnalysis: AIAnalysisServiceProtocol? = nil,
        gamification: GamificationService? = nil
    ) -> ServiceContainer {
        ServiceContainer(
            auth: auth ?? AuthService.shared,
            database: database ?? DatabaseService.shared,
            subscription: subscription ?? SubscriptionService.shared,
            analytics: analytics ?? AnalyticsService.shared,
            aiAnalysis: aiAnalysis ?? AIAnalysisService.shared,
            gamification: gamification ?? GamificationService.shared
        )
    }

    // MARK: - Internal Init (for testing factory)

    private init(
        auth: AuthServiceProtocol,
        database: DatabaseServiceProtocol,
        subscription: SubscriptionServiceProtocol,
        analytics: AnalyticsServiceProtocol,
        aiAnalysis: AIAnalysisServiceProtocol,
        gamification: GamificationService
    ) {
        self.auth = auth
        self.database = database
        self.subscription = subscription
        self.analytics = analytics
        self.aiAnalysis = aiAnalysis
        self.gamification = gamification
    }
}
