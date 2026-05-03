import Foundation
@testable import HealthMap

/// In-memory mock for `DatabaseServiceProtocol`. Stores fake rows in dictionaries
/// so tests can verify reads/writes without hitting Supabase.
final class MockDatabaseService: DatabaseServiceProtocol {

    // MARK: - Fake storage
    var profilesByUserId: [String: ProfileRow] = [:]
    var questionnaireByUserId: [String: UserProfile] = [:]
    var analysisByUserId: [String: AIAnalysisResponse] = [:]
    var pushTokensByUserId: [String: String] = [:]
    var deletedUserIds: [String] = []

    // MARK: - Programmable errors
    var loadProfileError: Error?
    var loadQuestionnaireError: Error?
    var loadAnalysisError: Error?
    var saveProfileError: Error?
    var saveAnalysisError: Error?
    var clearAnalysisError: Error?
    var updatePushTokenError: Error?
    var deleteError: Error?

    // MARK: - Call counters
    private(set) var loadProfileCount = 0
    private(set) var saveProfileCount = 0
    private(set) var saveAnalysisCount = 0
    private(set) var deleteAllCount = 0

    // MARK: - DatabaseServiceProtocol

    func loadProfile(userId: String) async throws -> ProfileRow? {
        loadProfileCount += 1
        if let loadProfileError { throw loadProfileError }
        return profilesByUserId[userId]
    }

    func loadQuestionnaireData(userId: String) async throws -> UserProfile? {
        if let loadQuestionnaireError { throw loadQuestionnaireError }
        return questionnaireByUserId[userId]
    }

    func loadAIAnalysis(userId: String) async throws -> AIAnalysisResponse? {
        if let loadAnalysisError { throw loadAnalysisError }
        return analysisByUserId[userId]
    }

    func saveProfile(userId: String, email: String, firstName: String, questionnaireData: UserProfile) async throws {
        saveProfileCount += 1
        if let saveProfileError { throw saveProfileError }
        questionnaireByUserId[userId] = questionnaireData
    }

    func saveAIAnalysis(userId: String, analysis: AIAnalysisResponse) async throws {
        saveAnalysisCount += 1
        if let saveAnalysisError { throw saveAnalysisError }
        analysisByUserId[userId] = analysis
    }

    func clearAIAnalysis(userId: String) async throws {
        if let clearAnalysisError { throw clearAnalysisError }
        analysisByUserId.removeValue(forKey: userId)
    }

    func updatePushToken(_ token: String) async throws {
        if let updatePushTokenError { throw updatePushTokenError }
        // We don't have a userId argument by design (AuthService resolves current user),
        // so we key by a constant for test inspection.
        pushTokensByUserId["current"] = token
    }

    func deleteAllUserData(userId: String) async throws {
        deleteAllCount += 1
        if let deleteError { throw deleteError }
        profilesByUserId.removeValue(forKey: userId)
        questionnaireByUserId.removeValue(forKey: userId)
        analysisByUserId.removeValue(forKey: userId)
        deletedUserIds.append(userId)
    }
}
