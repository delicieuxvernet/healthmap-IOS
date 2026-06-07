import Foundation
import Supabase

// MARK: - Database Service (Supabase PostgreSQL)
final class DatabaseService {
    static let shared = DatabaseService()
    private var client: SupabaseClient { SupabaseService.shared.client }

    private init() {}

    // MARK: - Load Profile
    func loadProfile(userId: String) async throws -> ProfileRow? {
        let response: ProfileRow = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        return response
    }

    // MARK: - Load Questionnaire Data (with transit decryption support)
    func loadQuestionnaireData(userId: String) async throws -> UserProfile? {
        struct QRow: Codable {
            let questionnaireData: UserProfile?
            let questionnaireDataEncrypted: String?
            enum CodingKeys: String, CodingKey {
                case questionnaireData = "questionnaire_data"
                case questionnaireDataEncrypted = "questionnaire_data_encrypted"
            }
        }

        let row: QRow = try await client
            .from("profiles")
            .select("questionnaire_data, questionnaire_data_encrypted")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        // Try decrypting the encrypted field first
        if let encryptedB64 = row.questionnaireDataEncrypted,
           let encryptedData = Data(base64Encoded: encryptedB64),
           let decrypted = SecureStorageService.shared.decryptFromTransit(encryptedData),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: decrypted) {
            return profile
        }

        // Fallback to plaintext field (pre-encryption data)
        return row.questionnaireData
    }

    // MARK: - Load AI Analysis (with transit decryption support)
    func loadAIAnalysis(userId: String) async throws -> AIAnalysisResponse? {
        struct AnalysisRow: Codable {
            let aiAnalysis: AIAnalysisResponse?
            let aiAnalysisEncrypted: String?
            enum CodingKeys: String, CodingKey {
                case aiAnalysis = "ai_analysis"
                case aiAnalysisEncrypted = "ai_analysis_encrypted"
            }
        }

        let row: AnalysisRow = try await client
            .from("profiles")
            .select("ai_analysis, ai_analysis_encrypted")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        // Try decrypting the encrypted field first
        if let encryptedB64 = row.aiAnalysisEncrypted,
           let encryptedData = Data(base64Encoded: encryptedB64),
           let decrypted = SecureStorageService.shared.decryptFromTransit(encryptedData),
           let analysis = try? JSONDecoder().decode(AIAnalysisResponse.self, from: decrypted) {
            return analysis
        }

        // Fallback to plaintext field (pre-encryption data)
        return row.aiAnalysis
    }

    // MARK: - Bootstrap Apple profile (first SIWA sign-in only)
    /// Upserts a minimal `profiles` row with `id`, `email`, `first_name` but
    /// **never overwrites** an existing row's fields.
    ///
    /// This exists because Sign in with Apple returns `fullName` and `email`
    /// only on the very first sign-in — if we don't capture them then, they're
    /// lost forever. We can't use `saveProfile` because that requires a full
    /// `questionnaireData` payload, and the Apple user hasn't filled it yet.
    ///
    /// Implementation detail: the upsert is configured to **ignore duplicates**
    /// on conflict so a returning SIWA user who already completed the
    /// questionnaire doesn't have their `first_name` wiped (Apple will send
    /// empty fields on subsequent sign-ins).
    func bootstrapAppleProfile(userId: String, email: String?, firstName: String?) async throws {
        struct BootstrapRow: Codable {
            let id: String
            let email: String?
            let firstName: String?
            let updatedAt: String

            enum CodingKeys: String, CodingKey {
                case id, email
                case firstName = "first_name"
                case updatedAt = "updated_at"
            }
        }

        // If we have nothing useful to write, skip entirely.
        if (email?.isEmpty ?? true) && (firstName?.isEmpty ?? true) {
            return
        }

        let row = BootstrapRow(
            id: userId,
            email: (email?.isEmpty == false) ? email : nil,
            firstName: (firstName?.isEmpty == false) ? firstName : nil,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        // `ignoreDuplicates: true` makes the upsert a no-op if the row already
        // exists. This is the correct semantics here: we only want to create
        // the row on the **first** Apple sign-in, never overwrite later ones.
        try await client
            .from("profiles")
            .upsert(row, onConflict: "id", ignoreDuplicates: true)
            .execute()
    }

    // MARK: - Save Profile (upsert) — with transit encryption for questionnaire data
    func saveProfile(userId: String, email: String, firstName: String, questionnaireData: UserProfile) async throws {
        // NOTE: `questionnaire_data_encrypted` n'existe pas dans la DB (mismatch
        // documenté CLAUDE.md §4.3) — fallback plaintext via `questionnaire_data`
        // (jsonb). Si la colonne encrypted est ajoutée plus tard, restaurer
        // SecureStorageService.encryptForTransit + champ dans le payload.
        struct UpsertRow: Codable {
            let id: String
            let email: String
            let firstName: String
            let questionnaireData: UserProfile
            let updatedAt: String

            enum CodingKeys: String, CodingKey {
                case id, email
                case firstName = "first_name"
                case questionnaireData = "questionnaire_data"
                case updatedAt = "updated_at"
            }
        }

        let row = UpsertRow(
            id: userId,
            email: email,
            firstName: firstName,
            questionnaireData: questionnaireData,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        try await NetworkService.shared.withRetry {
            try await self.client
                .from("profiles")
                .upsert(row, onConflict: "id")
                .execute()
        }
    }

    // MARK: - Save AI Analysis (cache) — with transit encryption
    func saveAIAnalysis(userId: String, analysis: AIAnalysisResponse) async throws {
        // NOTE: `ai_analysis_encrypted` n'existe pas dans la DB (mismatch
        // documenté CLAUDE.md §4.3) — fallback plaintext via `ai_analysis` jsonb.
        struct UpdateRow: Codable {
            let aiAnalysis: AIAnalysisResponse
            enum CodingKeys: String, CodingKey {
                case aiAnalysis = "ai_analysis"
            }
        }

        try await client
            .from("profiles")
            .update(UpdateRow(aiAnalysis: analysis))
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - Clear AI Analysis (force refresh)
    func clearAIAnalysis(userId: String) async throws {
        struct ClearRow: Codable {
            let aiAnalysis: String? = nil
            enum CodingKeys: String, CodingKey {
                case aiAnalysis = "ai_analysis"
            }
        }
        try await client
            .from("profiles")
            .update(ClearRow())
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - Web Score History (cross-platform sync with healthmap.fr)

    /// Reads the `score_history` JSONB column from the profiles table.
    /// This is where the WEB app stores score history, as opposed to the
    /// separate `score_history` TABLE that iOS uses.
    func loadWebScoreHistory(userId: String) async throws -> [WebScoreEntry] {
        struct Row: Codable {
            let scoreHistory: [WebScoreEntry]?
            enum CodingKeys: String, CodingKey {
                case scoreHistory = "score_history"
            }
        }

        let row: Row = try await client
            .from("profiles")
            .select("score_history")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        return row.scoreHistory ?? []
    }

    /// Writes the full score history array to `profiles.score_history` JSONB
    /// so the web app can read it. Called after each iOS score snapshot save.
    func saveWebScoreHistory(userId: String, history: [WebScoreEntry]) async throws {
        struct UpdateRow: Codable {
            let scoreHistory: [WebScoreEntry]
            enum CodingKeys: String, CodingKey {
                case scoreHistory = "score_history"
            }
        }

        try await client
            .from("profiles")
            .update(UpdateRow(scoreHistory: history))
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - Save Score Snapshot
    func saveScoreSnapshot(userId: String, healthScore: Int, topDeficiencies: [(id: String, score: Int)], trigger: String) async throws {
        struct DeficiencyEntry: Codable {
            let id: String
            let score: Int
        }
        struct ScoreHistoryRow: Codable {
            let userId: String
            let date: String
            let healthScore: Int
            let topDeficiencies: [DeficiencyEntry]
            let trigger: String

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case date
                case healthScore = "health_score"
                case topDeficiencies = "top_deficiencies"
                case trigger
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())

        let deficiencies = topDeficiencies.map { DeficiencyEntry(id: $0.id, score: $0.score) }

        let row = ScoreHistoryRow(
            userId: userId,
            date: dateStr,
            healthScore: healthScore,
            topDeficiencies: deficiencies,
            trigger: trigger
        )

        try await client
            .from("score_history")
            .upsert(row, onConflict: "user_id,date")
            .execute()
    }

    // MARK: - Load Score History
    func loadScoreHistory(userId: String) async throws -> [ScoreHistoryRemoteRow] {
        let rows: [ScoreHistoryRemoteRow] = try await client
            .from("score_history")
            .select()
            .eq("user_id", value: userId)
            .order("date", ascending: false)
            .limit(90)
            .execute()
            .value

        return rows
    }

    // MARK: - Streak Sync (cross-platform with healthmap.fr)

    /// Reads streak data from the profiles table. The web app writes
    /// `current_streak`, `longest_streak`, `last_activity_date` columns
    /// via `streaks.js`. iOS reads them here to stay in sync.
    func loadStreakData(userId: String) async throws -> (currentStreak: Int, longestStreak: Int, lastActivityDate: String?) {
        struct StreakRow: Codable {
            let currentStreak: Int?
            let longestStreak: Int?
            let lastActivityDate: String?

            enum CodingKeys: String, CodingKey {
                case currentStreak = "current_streak"
                case longestStreak = "longest_streak"
                case lastActivityDate = "last_activity_date"
            }
        }

        let row: StreakRow = try await client
            .from("profiles")
            .select("current_streak, longest_streak, last_activity_date")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        return (
            currentStreak: row.currentStreak ?? 0,
            longestStreak: row.longestStreak ?? 0,
            lastActivityDate: row.lastActivityDate
        )
    }

    /// Syncs streak data to the profiles table so the web app can see
    /// streaks earned on iOS.
    func syncStreakData(userId: String, currentStreak: Int, longestStreak: Int, lastActivityDate: String?) async throws {
        struct UpdateRow: Codable {
            let currentStreak: Int
            let longestStreak: Int
            let lastActivityDate: String?

            enum CodingKeys: String, CodingKey {
                case currentStreak = "current_streak"
                case longestStreak = "longest_streak"
                case lastActivityDate = "last_activity_date"
            }
        }

        try await client
            .from("profiles")
            .update(UpdateRow(
                currentStreak: currentStreak,
                longestStreak: longestStreak,
                lastActivityDate: lastActivityDate
            ))
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - Load Subscription Tier
    func loadTier(userId: String) async throws -> (tier: String, status: String?, cancelAtPeriodEnd: Bool) {
        struct TierRow: Codable {
            let tier: String?
            let subscriptionStatus: String?
            let cancelAtPeriodEnd: Bool?

            enum CodingKeys: String, CodingKey {
                case tier
                case subscriptionStatus = "subscription_status"
                case cancelAtPeriodEnd = "cancel_at_period_end"
            }
        }

        let row: TierRow = try await client
            .from("profiles")
            .select("tier, subscription_status, cancel_at_period_end")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        return (
            tier: row.tier ?? "free",
            status: row.subscriptionStatus,
            cancelAtPeriodEnd: row.cancelAtPeriodEnd ?? false
        )
    }
}

// MARK: - Score History Remote Row
struct ScoreHistoryRemoteRow: Codable {
    let id: String?
    let userId: String
    let date: String
    let healthScore: Int
    let topDeficiencies: [[String: String]]?
    let trigger: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case healthScore = "health_score"
        case topDeficiencies = "top_deficiencies"
        case trigger
        case createdAt = "created_at"
    }
}

// MARK: - Web Score Entry (profiles.score_history JSONB — cross-platform)
/// Matches the JavaScript object shape used by the web app in
/// `scoreHistory.js`. Keys are camelCase because the web client
/// writes them as-is into the JSONB column.
struct WebScoreEntry: Codable {
    let date: String                   // "YYYY-MM-DD"
    let healthScore: Int
    let topDeficiencies: [WebDeficiencyEntry]?
    let timestamp: Double?             // Unix ms (web includes this)
    let trigger: String?
}

struct WebDeficiencyEntry: Codable {
    let id: String
    let score: Int
}
