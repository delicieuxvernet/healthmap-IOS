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

    // MARK: - Load Questionnaire Data
    // NOTE 10 juin 2026 : les colonnes `questionnaire_data_encrypted` /
    // `ai_analysis_encrypted` n'ont JAMAIS existé dans le schéma — les
    // sélectionner faisait répondre PostgREST 400 à CHAQUE lecture (vu en
    // logs sur les builds 27-29 : le cache du bilan était illisible et
    // forçait un appel edge inutile). Le chiffrement de transit associé
    // (SecureStorageService) a été retiré avec.
    func loadQuestionnaireData(userId: String) async throws -> UserProfile? {
        struct QRow: Codable {
            let questionnaireData: UserProfile?
            enum CodingKeys: String, CodingKey {
                case questionnaireData = "questionnaire_data"
            }
        }

        let row: QRow = try await client
            .from("profiles")
            .select("questionnaire_data")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        return row.questionnaireData
    }

    // MARK: - Load AI Analysis (cache lu avant tout appel edge)
    func loadAIAnalysis(userId: String) async throws -> AIAnalysisResponse? {
        struct AnalysisRow: Codable {
            let aiAnalysis: AIAnalysisResponse?
            enum CodingKeys: String, CodingKey {
                case aiAnalysis = "ai_analysis"
            }
        }

        let row: AnalysisRow = try await client
            .from("profiles")
            .select("ai_analysis")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        return row.aiAnalysis
    }

    // MARK: - Load AI Analysis v2 (cache du Bilan v6 — lecture symétrique de
    // loadAIAnalysis, colonne distincte `ai_analysis_v2`)
    func loadAIAnalysisV2(userId: String) async throws -> AIAnalysisV2? {
        struct AnalysisRow: Codable {
            let aiAnalysisV2: AIAnalysisV2?
            enum CodingKeys: String, CodingKey {
                case aiAnalysisV2 = "ai_analysis_v2"
            }
        }

        let row: AnalysisRow = try await client
            .from("profiles")
            .select("ai_analysis_v2")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        return row.aiAnalysisV2
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
        // Apple ne fournit `firstName` / `email` que dans le ASAuthorizationAppleIDCredential
        // (côté iOS), JAMAIS dans le idToken envoyé à Supabase. Le trigger
        // `handle_new_user` ne peut donc pas les écrire au signup Apple
        // (`raw_user_meta_data` ne contient ni first_name ni un email custom).
        //
        // BUG corrigé 2026-06-08 : la version précédente faisait un upsert avec
        // `ignoreDuplicates: true`. Avec Supabase Auth + le trigger, le profile
        // existe DÉJÀ à ce stade → l'upsert était un no-op → first_name restait
        // null à jamais. Maintenant on fait un UPDATE conditionnel `IS NULL`
        // qui ne touche QUE les colonnes vides — l'user qui a déjà renseigné
        // son prénom dans le questionnaire n'est jamais écrasé.

        if firstName?.isEmpty == false {
            struct UpdateFirstName: Codable {
                let firstName: String
                let updatedAt: String
                enum CodingKeys: String, CodingKey {
                    case firstName = "first_name"
                    case updatedAt = "updated_at"
                }
            }
            let row = UpdateFirstName(
                firstName: firstName!,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            try await client
                .from("profiles")
                .update(row)
                .eq("id", value: userId)
                .is("first_name", value: nil)
                .execute()
        }

        if email?.isEmpty == false {
            struct UpdateEmail: Codable {
                let email: String
                let updatedAt: String
                enum CodingKeys: String, CodingKey {
                    case email
                    case updatedAt = "updated_at"
                }
            }
            let row = UpdateEmail(
                email: email!,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            try await client
                .from("profiles")
                .update(row)
                .eq("id", value: userId)
                .is("email", value: nil)
                .execute()
        }
    }

    // MARK: - Save Profile (update) — the row always exists, created by the
    // `handle_new_user` DB trigger at signup.
    func saveProfile(userId: String, email: String, firstName: String, questionnaireData: UserProfile) async throws {
        // UPDATE et non upsert : la policy RLS d'INSERT exige `auth_user_id`
        // ou `clerk_id` dans la ligne proposée — Postgres évalue ce WITH CHECK
        // AVANT la résolution `on conflict`, donc un upsert sans ces champs est
        // rejeté 403 même quand la ligne existe déjà (bug "Erreur lors de la
        // sauvegarde" à la soumission du questionnaire, 9 juin 2026).
        struct UpdateRow: Codable {
            let email: String
            let firstName: String
            let questionnaireData: UserProfile
            let updatedAt: String

            enum CodingKeys: String, CodingKey {
                case email
                case firstName = "first_name"
                case questionnaireData = "questionnaire_data"
                case updatedAt = "updated_at"
            }
        }

        let row = UpdateRow(
            email: email,
            firstName: firstName,
            questionnaireData: questionnaireData,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        // `.select("id").single()` force une erreur si aucune ligne ne matche :
        // un profil manquant doit remonter comme erreur, pas passer en silence.
        struct UpdatedRow: Decodable { let id: String }
        try await NetworkService.shared.withRetry {
            let _: UpdatedRow = try await self.client
                .from("profiles")
                .update(row)
                .eq("id", value: userId)
                .select("id")
                .single()
                .execute()
                .value
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

    // MARK: - Save AI Analysis v2 (cache du Bilan v6 — écriture symétrique de
    // saveAIAnalysis, colonne distincte `ai_analysis_v2`)
    func saveAIAnalysisV2(userId: String, analysis: AIAnalysisV2) async throws {
        struct UpdateRow: Codable {
            let aiAnalysisV2: AIAnalysisV2
            enum CodingKeys: String, CodingKey {
                case aiAnalysisV2 = "ai_analysis_v2"
            }
        }

        try await client
            .from("profiles")
            .update(UpdateRow(aiAnalysisV2: analysis))
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - Save Baseline Nutrient Scores (capture one-time du 1er bilan)
    // UPDATE de la seule colonne `baseline_nutrient_scores` (jsonb) — jamais
    // upsert/insert (la ligne existe déjà, créée par le trigger handle_new_user ;
    // règle absolue profiles = UPDATE only). Symétrique de saveAIAnalysis.
    func saveBaselineNutrientScores(userId: String, scores: [String: Int]) async throws {
        struct UpdateRow: Codable {
            let baselineNutrientScores: [String: Int]
            enum CodingKeys: String, CodingKey {
                case baselineNutrientScores = "baseline_nutrient_scores"
            }
        }

        try await client
            .from("profiles")
            .update(UpdateRow(baselineNutrientScores: scores))
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
