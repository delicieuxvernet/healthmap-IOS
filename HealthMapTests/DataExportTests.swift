import XCTest
@testable import HealthMap

/// Tests for DataExportService — verifies the export structure, field presence,
/// and sanitization without requiring a live Supabase connection.
final class DataExportTests: XCTestCase {

    // MARK: - Export Model Structure

    func testUserDataExportEncodesAsJSON() throws {
        let export = DataExportService.UserDataExport(
            exportDate: "2026-04-12T10:00:00Z",
            appVersion: "1.0.0 (1)",
            profile: DataExportService.ProfileExport(
                email: "test@healthmap.fr",
                firstName: "Thomas",
                tier: "premium",
                createdAt: nil
            ),
            questionnaire: nil,
            aiAnalysis: nil,
            scoreHistory: [
                DataExportService.ScoreSnapshotExport(
                    date: "2026-04-10T08:00:00Z",
                    score: 72,
                    source: "questionnaire"
                ),
                DataExportService.ScoreSnapshotExport(
                    date: "2026-04-11T08:00:00Z",
                    score: 75,
                    source: "checkin"
                ),
            ],
            checkinHistory: [
                DataExportService.CheckinWeekExport(
                    weekLabel: "S15", completed: 5, total: 7,
                    date: "2026-04-07T00:00:00Z"
                ),
            ],
            gamification: DataExportService.GamificationExport(
                currentStreak: 5,
                bestStreak: 12,
                totalCheckins: 34,
                badgesEarned: ["firstCheckin", "weekStreak"],
                isZenMode: false
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(export)
        let json = String(data: data, encoding: .utf8)!

        // Verify top-level keys exist
        XCTAssertTrue(json.contains("\"exportDate\""), "Export should include exportDate")
        XCTAssertTrue(json.contains("\"appVersion\""), "Export should include appVersion")
        XCTAssertTrue(json.contains("\"profile\""), "Export should include profile")
        XCTAssertTrue(json.contains("\"scoreHistory\""), "Export should include scoreHistory")
        XCTAssertTrue(json.contains("\"gamification\""), "Export should include gamification")
    }

    func testExportContainsAllDataCategories() throws {
        let export = DataExportService.UserDataExport(
            exportDate: "2026-04-12T10:00:00Z",
            appVersion: "1.0.0 (1)",
            profile: DataExportService.ProfileExport(
                email: "test@healthmap.fr",
                firstName: "Thomas",
                tier: "free",
                createdAt: nil
            ),
            questionnaire: UserProfile.empty,
            aiAnalysis: DataExportService.AIAnalysisExport(
                healthScore: 72,
                overallLabel: "Bon",
                headline: "Profil equilibre",
                nutrients: [
                    DataExportService.NutrientExport(
                        name: "Vitamine D",
                        score: 35,
                        status: "deficient",
                        verdict: "Exposition solaire insuffisante"
                    ),
                ],
                redFlags: nil,
                priorityActions: ["Augmenter l'exposition au soleil"],
                practicalTips: ["15 min de marche par jour"]
            ),
            scoreHistory: [],
            checkinHistory: [],
            gamification: DataExportService.GamificationExport(
                currentStreak: 0,
                bestStreak: 0,
                totalCheckins: 0,
                badgesEarned: [],
                isZenMode: false
            )
        )

        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(DataExportService.UserDataExport.self, from: data)

        XCTAssertNotNil(decoded.profile, "Export must include profile")
        XCTAssertNotNil(decoded.questionnaire, "Export must include questionnaire")
        XCTAssertNotNil(decoded.aiAnalysis, "Export must include AI analysis")
        XCTAssertEqual(decoded.aiAnalysis?.healthScore, 72)
        XCTAssertEqual(decoded.aiAnalysis?.nutrients?.count, 1)
    }

    // MARK: - Empty Profile Exports Gracefully

    func testEmptyProfileExportsGracefully() throws {
        let export = DataExportService.UserDataExport(
            exportDate: "2026-04-12T10:00:00Z",
            appVersion: "1.0.0 (1)",
            profile: nil,
            questionnaire: nil,
            aiAnalysis: nil,
            scoreHistory: [],
            checkinHistory: [],
            gamification: DataExportService.GamificationExport(
                currentStreak: 0,
                bestStreak: 0,
                totalCheckins: 0,
                badgesEarned: [],
                isZenMode: false
            )
        )

        let data = try JSONEncoder().encode(export)
        XCTAssertGreaterThan(data.count, 0, "Empty export should still produce valid JSON")

        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"exportDate\""), "Even empty export must have exportDate")
        XCTAssertTrue(json.contains("\"gamification\""), "Even empty export must have gamification")
    }

    // MARK: - Export Date Format

    func testExportDateFormatISO8601() throws {
        let export = DataExportService.UserDataExport(
            exportDate: ISO8601DateFormatter().string(from: Date()),
            appVersion: "1.0.0 (1)",
            profile: nil,
            questionnaire: nil,
            aiAnalysis: nil,
            scoreHistory: [],
            checkinHistory: [],
            gamification: DataExportService.GamificationExport(
                currentStreak: 0, bestStreak: 0, totalCheckins: 0,
                badgesEarned: [], isZenMode: false
            )
        )

        // ISO 8601 format check
        let formatter = ISO8601DateFormatter()
        XCTAssertNotNil(
            formatter.date(from: export.exportDate),
            "exportDate must be valid ISO 8601: \(export.exportDate)"
        )
    }

    // MARK: - Sanitization

    func testExportDoesNotContainSupabaseInternalIds() throws {
        let export = DataExportService.UserDataExport(
            exportDate: "2026-04-12T10:00:00Z",
            appVersion: "1.0.0 (1)",
            profile: DataExportService.ProfileExport(
                email: "test@healthmap.fr",
                firstName: "Thomas",
                tier: "free",
                createdAt: nil
            ),
            questionnaire: nil,
            aiAnalysis: nil,
            scoreHistory: [
                DataExportService.ScoreSnapshotExport(
                    date: "2026-04-10T08:00:00Z",
                    score: 72,
                    source: "questionnaire"
                ),
            ],
            checkinHistory: [],
            gamification: DataExportService.GamificationExport(
                currentStreak: 5, bestStreak: 10, totalCheckins: 20,
                badgesEarned: ["firstCheckin"], isZenMode: false
            )
        )

        let data = try JSONEncoder().encode(export)
        let json = String(data: data, encoding: .utf8)!

        // Score history export should NOT contain internal UUIDs
        // (ScoreSnapshotExport has date/score/source, not id/userId)
        XCTAssertFalse(json.contains("\"userId\""), "Export should not expose internal userId field")
        XCTAssertFalse(json.contains("\"user_id\""), "Export should not expose internal user_id field")
    }

    // MARK: - Gamification Export

    func testGamificationExportFields() throws {
        let gamification = DataExportService.GamificationExport(
            currentStreak: 7,
            bestStreak: 21,
            totalCheckins: 45,
            badgesEarned: ["firstCheckin", "weekStreak", "monthStreak"],
            isZenMode: true
        )

        let data = try JSONEncoder().encode(gamification)
        let decoded = try JSONDecoder().decode(DataExportService.GamificationExport.self, from: data)

        XCTAssertEqual(decoded.currentStreak, 7)
        XCTAssertEqual(decoded.bestStreak, 21)
        XCTAssertEqual(decoded.totalCheckins, 45)
        XCTAssertEqual(decoded.badgesEarned.count, 3)
        XCTAssertTrue(decoded.isZenMode)
    }

    // MARK: - Service Singleton

    @MainActor
    func testDataExportServiceIsSingleton() {
        let a = DataExportService.shared
        let b = DataExportService.shared
        XCTAssertTrue(a === b, "DataExportService should be a singleton")
    }
}
