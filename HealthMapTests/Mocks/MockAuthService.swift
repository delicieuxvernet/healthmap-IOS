import Foundation
@testable import HealthMap

/// In-memory mock for `AuthServiceProtocol`. Drives unit tests without any network.
/// Each method can be configured to succeed or fail by setting the matching `*Error` property.
///
/// Depuis la migration Clerk (20 avril 2026), les types exposés sont `HMSession` /
/// `HMUser` / `HMAuthChangeEvent` au lieu des types Supabase. Le mock ne dépend
/// plus du SDK Supabase ni de ClerkKit — il manipule uniquement les shims du
/// module principal (`Core/AuthTypes.swift`).
@MainActor
final class MockAuthService: AuthServiceProtocol {

    // MARK: - Recorded calls (assertable from tests)
    private(set) var signUpCalls: [(email: String, password: String, firstName: String)] = []
    private(set) var signInCalls: [(email: String, password: String)] = []
    private(set) var signOutCount = 0
    private(set) var refreshCount = 0
    private(set) var resetPasswordCalls: [String] = []
    private(set) var updatePasswordCalls: [String] = []

    private(set) var signInWithAppleCalls: [(idToken: String, rawNonce: String)] = []

    // MARK: - Programmable behavior
    var signUpError: Error?
    var signInError: Error?
    var signInWithAppleError: Error?
    var signOutError: Error?
    var refreshError: Error?
    var resetPasswordError: Error?
    var updatePasswordError: Error?
    var googleOAuthURL: URL = URL(string: "healthmap://auth/callback")!
    var googleOAuthError: Error?

    var stubbedUser: HMUser?
    var stubbedSession: HMSession?

    private var authStreamContinuation: AsyncStream<(event: HMAuthChangeEvent, session: HMSession?)>.Continuation?

    // MARK: - AuthServiceProtocol

    func signUp(email: String, password: String, firstName: String) async throws {
        signUpCalls.append((email, password, firstName))
        if let signUpError { throw signUpError }
    }

    func signIn(email: String, password: String) async throws {
        signInCalls.append((email, password))
        if let signInError { throw signInError }
    }

    func signInWithGoogle() async throws -> URL {
        if let googleOAuthError { throw googleOAuthError }
        return googleOAuthURL
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws {
        signInWithAppleCalls.append((idToken, rawNonce))
        if let signInWithAppleError { throw signInWithAppleError }
    }

    func signOut() async throws {
        signOutCount += 1
        if let signOutError { throw signOutError }
        stubbedUser = nil
        stubbedSession = nil
    }

    func refreshSession() async throws {
        refreshCount += 1
        if let refreshError { throw refreshError }
    }

    func resetPassword(email: String) async throws {
        resetPasswordCalls.append(email)
        if let resetPasswordError { throw resetPasswordError }
    }

    func updatePassword(newPassword: String) async throws {
        updatePasswordCalls.append(newPassword)
        if let updatePasswordError { throw updatePasswordError }
    }

    var currentSession: HMSession? {
        get async { stubbedSession }
    }

    var currentUser: HMUser? {
        get async { stubbedUser }
    }

    func authStateChanges() -> AsyncStream<(event: HMAuthChangeEvent, session: HMSession?)> {
        AsyncStream { continuation in
            self.authStreamContinuation = continuation
        }
    }

    /// Test helper: push a fake auth state change into any subscribed stream.
    func emitAuthEvent(_ event: HMAuthChangeEvent, session: HMSession? = nil) {
        authStreamContinuation?.yield((event, session))
    }
}
