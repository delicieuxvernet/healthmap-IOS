import Foundation

// MARK: - Service Protocols
// These protocols exist for two reasons:
// 1. Dependency injection: ViewModels depend on the protocol, not the concrete class,
//    so tests can inject mocks without touching production code.
// 2. Future-proofing: swapping Clerk/Supabase for another backend only requires
//    implementing these protocols against the new SDK.

// MARK: - Auth
//
// Depuis la migration Clerk (20 avril 2026), les types de session sont
// `HMSession` / `HMUser` (définis dans `Core/AuthTypes.swift`) au lieu de
// `Supabase.Session` / `Supabase.User`. Cela évite de coupler le protocol
// à l'implémentation d'un provider spécifique.

protocol AuthServiceProtocol: AnyObject {
    func signUp(email: String, password: String, firstName: String) async throws
    func signIn(email: String, password: String) async throws
    func signInWithGoogle() async throws -> URL
    func signInWithApple(idToken: String, rawNonce: String) async throws
    func signOut() async throws
    func refreshSession() async throws
    func resetPassword(email: String) async throws
    func updatePassword(newPassword: String) async throws
    @MainActor var currentSession: HMSession? { get async }
    @MainActor var currentUser: HMUser? { get async }
    @MainActor func authStateChanges() -> AsyncStream<(event: HMAuthChangeEvent, session: HMSession?)>
}

// MARK: - Database

protocol DatabaseServiceProtocol: AnyObject {
    func loadProfile(userId: String) async throws -> ProfileRow?
    func loadQuestionnaireData(userId: String) async throws -> UserProfile?
    func loadAIAnalysis(userId: String) async throws -> AIAnalysisResponse?
    func saveProfile(userId: String, email: String, firstName: String, questionnaireData: UserProfile) async throws
    func saveAIAnalysis(userId: String, analysis: AIAnalysisResponse) async throws
    func clearAIAnalysis(userId: String) async throws
    func updatePushToken(_ token: String) async throws
    func deleteAllUserData(userId: String) async throws
}

// MARK: - Subscription

@MainActor
protocol SubscriptionServiceProtocol: AnyObject {
    var isPremium: Bool { get }
    func checkPremiumStatus() async
    func loadOfferings() async
    func restorePurchases() async throws
    func identify(userId: String) async
}

// MARK: - Analytics

protocol AnalyticsServiceProtocol: AnyObject {
    func track(_ event: AnalyticsEvent, properties: [String: Any]?)
    func trackScreen(_ name: String)
    func identify(userId: String, traits: [String: Any]?)
    func reset()
}

// MARK: - AI Analysis

protocol AIAnalysisServiceProtocol: AnyObject {
    func fetchFullAnalysis(userId: String, profile: UserProfile) async throws -> MergedAnalysis?
    func regenerate(userId: String, profile: UserProfile) async throws -> MergedAnalysis?
}

// MARK: - Gamification

@MainActor
protocol GamificationServiceProtocol: ObservableObject {
    var currentStreak: Int { get }
    var lastCheckinDate: Date? { get }
    var earnedBadges: Set<BadgeType> { get }
    var isZenMode: Bool { get }
    var showConfetti: Bool { get set }
    var confettiType: ConfettiType { get set }
    var totalCheckins: Int { get }
    var bestStreak: Int { get }
    var freezesUsedThisMonth: Int { get }
    var monthStart: Date { get }
    var triedPathways: Set<String> { get }

    func configure(userId: String) async
    func reset()
    func recordCheckin()
}
