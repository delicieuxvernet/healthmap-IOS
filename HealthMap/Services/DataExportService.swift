import Foundation
import UIKit

// MARK: - Data Export Service (RGPD Article 20 — Right to Data Portability)
/// Generates a machine-readable JSON export of all user data stored by HealthMap.
///
/// RGPD Article 20 requires that users can receive their personal data "in a
/// structured, commonly used and machine-readable format". This service
/// collects data from Supabase and UserDefaults, structures it as a single
/// JSON file, and presents a ShareSheet for delivery.
///
/// Privacy:
///   - Internal Supabase UUIDs are stripped (the user's data, not our schema)
///   - Dates are formatted as ISO 8601
///   - The file is named `healthmap-export-YYYY-MM-DD.json`
@MainActor
final class DataExportService {

    static let shared = DataExportService()
    private init() {}

    // MARK: - Export Models

    struct UserDataExport: Codable {
        let exportDate: String
        let appVersion: String
        let profile: ProfileExport?
        let questionnaire: UserProfile?
        let aiAnalysis: AIAnalysisExport?
        let scoreHistory: [ScoreSnapshotExport]
        let checkinHistory: [CheckinWeekExport]
        let gamification: GamificationExport
    }

    struct ProfileExport: Codable {
        let email: String?
        let firstName: String?
        let tier: String?
        let createdAt: String?
    }

    struct AIAnalysisExport: Codable {
        let healthScore: Int?
        let overallLabel: String?
        let headline: String?
        let nutrients: [NutrientExport]?
        let redFlags: [RedFlagExport]?
        let priorityActions: [String]?
        let practicalTips: [String]?
    }

    struct NutrientExport: Codable {
        let name: String
        let score: Int
        let status: String
        let verdict: String?
    }

    struct RedFlagExport: Codable {
        let name: String
        let urgency: String
        let message: String
    }

    struct ScoreSnapshotExport: Codable {
        let date: String
        let score: Int
        let source: String
    }

    struct CheckinWeekExport: Codable {
        let weekLabel: String
        let completed: Int
        let total: Int
        let date: String
    }

    struct GamificationExport: Codable {
        let currentStreak: Int
        let bestStreak: Int
        let totalCheckins: Int
        let badgesEarned: [String]
        let isZenMode: Bool
    }

    // MARK: - Generate Export

    /// Collects all user data and returns a JSON `Data` blob ready for sharing.
    func generateExport(userId: String, authEmail: String?) async throws -> (data: Data, filename: String) {
        // 1. Profile from Supabase
        let profileRow = try? await DatabaseService.shared.loadProfile(userId: userId)

        // 2. Questionnaire data
        let questionnaire = profileRow?.questionnaireData

        // 3. AI Analysis
        let aiRaw = try? await DatabaseService.shared.loadAIAnalysis(userId: userId)
        let aiExport: AIAnalysisExport?
        if let aiRaw {
            let localScores = questionnaire.map { HealthCalculator.analyzeNutrientScores(profile: $0) } ?? [:]

            aiExport = AIAnalysisExport(
                healthScore: questionnaire.map { HealthCalculator.calculateHealthScore(profile: $0) },
                overallLabel: aiRaw.summary?.overallLabel,
                headline: aiRaw.summary?.headline,
                nutrients: NutrientData.all.map { def in
                    NutrientExport(
                        name: def.label,
                        score: localScores[def.id.rawValue] ?? 50,
                        status: NutrientStatus(score: localScores[def.id.rawValue] ?? 50).rawValue,
                        verdict: aiRaw.nutrientRisks?.first(where: { $0.id == def.id.rawValue })?.verdict
                    )
                },
                redFlags: questionnaire.map { profile in
                    RedFlagDetector.detect(profile: profile).map {
                        RedFlagExport(name: $0.id.rawValue, urgency: $0.urgency.rawValue, message: $0.message)
                    }
                } ?? nil,
                priorityActions: aiRaw.priorityActions?.compactMap(\.action),
                practicalTips: (aiRaw.practicalTips ?? aiRaw.pepitesSante)?.compactMap(\.tip)
            )
        } else {
            aiExport = nil
        }

        // 4. Score history
        let history = await ScoreHistoryService.shared.loadHistory(userId: userId)
        let historyExport = history.map {
            ScoreSnapshotExport(
                date: ISO8601DateFormatter().string(from: $0.date),
                score: $0.score,
                source: $0.source
            )
        }

        // 5. Checkin week history (from UserDefaults)
        let checkinExport: [CheckinWeekExport] = {
            guard let entries = UserDefaults.standard.array(forKey: "healthmap_week_history") as? [[String: Any]] else { return [] }
            return entries.compactMap { dict in
                guard let label = dict["label"] as? String,
                      let completed = dict["completed"] as? Int,
                      let total = dict["total"] as? Int,
                      let timestamp = dict["date"] as? TimeInterval else { return nil }
                return CheckinWeekExport(
                    weekLabel: label,
                    completed: completed,
                    total: total,
                    date: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
                )
            }
        }()

        // 6. Gamification (from UserDefaults, in-memory state)
        let gamification = GamificationService.shared
        let gamificationExport = GamificationExport(
            currentStreak: gamification.currentStreak,
            bestStreak: gamification.bestStreak,
            totalCheckins: gamification.totalCheckins,
            badgesEarned: gamification.earnedBadges.map(\.rawValue).sorted(),
            isZenMode: gamification.isZenMode
        )

        // 7. Assemble
        let export = UserDataExport(
            exportDate: ISO8601DateFormatter().string(from: Date()),
            appVersion: AppConfig.shared.versionTag,
            profile: ProfileExport(
                email: authEmail ?? profileRow?.email,
                firstName: profileRow?.firstName,
                tier: profileRow?.tier,
                createdAt: profileRow?.createdAt
            ),
            questionnaire: questionnaire,
            aiAnalysis: aiExport,
            scoreHistory: historyExport,
            checkinHistory: checkinExport,
            gamification: gamificationExport
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)

        let dateStr = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        let filename = "healthmap-export-\(dateStr).json"

        AppLogger.app.info("Data export generated (\(data.count, privacy: .public) bytes)")
        AnalyticsService.shared.track(.dataExported, properties: ["type": "rgpd_data_export"])

        return (data: data, filename: filename)
    }

    // MARK: - Present Share Sheet

    /// Writes the export to a temp file and presents a UIActivityViewController.
    /// The temp file is cleaned up after the share sheet is dismissed.
    func presentShareSheet(data: Data, filename: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)

        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )

        // Clean up temp file after share sheet dismissal
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: tempURL)
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }

        // Walk to the topmost presented controller (for modals/sheets)
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        // iPad popover anchor
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
        }

        topVC.present(activityVC, animated: true)
    }
}

