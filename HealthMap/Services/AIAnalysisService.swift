import Foundation
import Supabase

// MARK: - AI Analysis Service (mirrors aiAnalysis.js)
/// Note: tous les callers sont @MainActor (ViewModels). La classe est marquée @MainActor
/// pour garantir la thread-safety du circuit breaker (consecutiveFailures, circuitOpenUntil).
@MainActor
final class AIAnalysisService: AIAnalysisServiceProtocol {
    static let shared = AIAnalysisService()
    private var client: SupabaseClient { SupabaseService.shared.client }
    private let schemaVersion = 7

    // Circuit breaker: prevents hammering a failing Edge Function
    // Thread-safe via @MainActor isolation.
    private var consecutiveFailures = 0
    private var circuitOpenUntil: Date?
    private let maxConsecutiveFailures = 3
    private let circuitResetInterval: TimeInterval = 300 // 5 minutes

    private init() {}

    // MARK: - Fetch Full Analysis
    /// Main entry point — checks cache, calls Edge Function if needed, validates, merges
    func fetchFullAnalysis(userId: String, profile: UserProfile) async throws -> MergedAnalysis? {
        guard profile.completed else { return nil }

        // 1. Compute local scores (ALWAYS deterministic)
        let localScores = HealthCalculator.analyzeNutrientScores(profile: profile)
        let healthScore = HealthCalculator.calculateHealthScore(profile: profile)
        let redFlags = RedFlagDetector.detect(profile: profile)

        // 2. Check cache — AVANT le circuit breaker : une analyse déjà en base
        // doit toujours pouvoir s'afficher, même circuit ouvert (le breaker ne
        // protège que l'appel Edge Function, pas la lecture du cache DB).
        let currentHash = Self.hashProfile(profile)
        let cached = (try? await DatabaseService.shared.loadAIAnalysis(userId: userId))?.sanitized()

        if let cached, cached.isValidV7,
           cached.meta?.profileHash == currentHash {
            // Cache valid — merge with fresh local scores
            return mergeWithCanonical(aiData: cached, localScores: localScores, healthScore: healthScore, redFlags: redFlags)
        }

        // Circuit breaker: if too many consecutive failures, short-circuit
        if let openUntil = circuitOpenUntil, Date() < openUntil {
            throw AIAnalysisError.circuitOpen
        }
        // Reset circuit if the cooldown has elapsed
        if let openUntil = circuitOpenUntil, Date() >= openUntil {
            circuitOpenUntil = nil
            consecutiveFailures = 0
        }

        // 3. Validate numeric inputs
        let weight = profile.weightDouble
        let height = profile.heightDouble
        let age = profile.ageInt
        guard weight >= 20, weight <= 300, height >= 80, height <= 250, age >= 1, age <= 120 else {
            return nil
        }

        // 4. Call Edge Function with 130s timeout (matches web)
        let requestBody = EdgeFunctionRequest(
            scores: localScores,
            healthScore: healthScore,
            redFlags: redFlags.map { EdgeFlagDTO(id: $0.id.rawValue, urgency: $0.urgency.rawValue, message: $0.message) },
            profileHash: currentHash,
            forceRefresh: false
        )

        let rawAnalysis: AIAnalysisResponse
        do {
            rawAnalysis = try await withThrowingTaskGroup(of: AIAnalysisResponse.self) { group in
                group.addTask {
                    try await self.client.functions.invoke(
                        "generate-analysis",
                        options: .init(body: requestBody)
                    )
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(130))
                    throw AIAnalysisError.timeout
                }
                guard let result = try await group.next() else {
                    group.cancelAll()
                    throw AIAnalysisError.timeout
                }
                group.cancelAll()
                return result
            }
        } catch let error as FunctionsError {
            // Map Supabase Functions HTTP errors to typed AIAnalysisError
            // so the UI can show the right message and we can retry intelligently.
            switch error {
            case .httpError(let code, _):
                AppLogger.analysis.error("Edge Function HTTP \(code, privacy: .public)")
                switch code {
                case 429:
                    throw AIAnalysisError.rateLimited
                case 400...499:
                    throw AIAnalysisError.clientError(code)
                case 500...599:
                    throw AIAnalysisError.serverError(code)
                default:
                    throw AIAnalysisError.invalidResponse
                }
            case .relayError:
                AppLogger.analysis.error("Edge Function relay error")
                throw AIAnalysisError.serverError(0)
            @unknown default:
                throw AIAnalysisError.invalidResponse
            }
        } catch let error as URLError where error.code == .timedOut {
            recordFailure()
            throw AIAnalysisError.timeout
        } catch let error as URLError {
            AppLogger.analysis.error("AI network error: \(error.localizedDescription, privacy: .public)")
            recordFailure()
            throw AIAnalysisError.networkError(error)
        } catch let error as DecodingError {
            // Échec de DÉCODAGE (≠ réseau) : re-tenter le même payload est du
            // gaspillage — on log le champ exact en cause, on compte l'échec
            // (le circuit s'ouvre si ça se répète) et on remonte une erreur
            // NON-retryable. Le décodage tolérant (AIAnalysis.swift) rend ce
            // cas quasi impossible, mais on reste défensif.
            AppLogger.analysis.error("AI response undecodable: \(Self.describe(error), privacy: .public)")
            recordFailure()
            throw AIAnalysisError.invalidResponse
        } catch let error as AIAnalysisError {
            // Re-throw typed errors after recording the failure
            if error.isRetryable { recordFailure() }
            throw error
        }

        // Success: reset circuit breaker
        consecutiveFailures = 0
        circuitOpenUntil = nil

        // Nettoyage : ids hors catalogue skippés (ex. "folate"), confidence
        // inconnue remise à nil — on ne jette jamais toute l'analyse.
        let analysis = rawAnalysis.sanitized()

        guard analysis.isValidV7 else {
            AppLogger.analysis.error("AI response failed v7 validation (summary inexploitable)")
            return nil
        }

        // 5. Cache to Supabase (non-blocking)
        var toCache = analysis
        if toCache.meta == nil { toCache.meta = AnalysisMeta() }
        toCache.meta?.profileHash = currentHash
        toCache.meta?.schemaVersion = schemaVersion
        Task {
            do {
                try await DatabaseService.shared.saveAIAnalysis(userId: userId, analysis: toCache)
            } catch {
                AppLogger.database.notice("AI analysis cache save failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // 6. Merge with canonical
        return mergeWithCanonical(aiData: analysis, localScores: localScores, healthScore: healthScore, redFlags: redFlags)
    }

    // MARK: - Decoding Error Helper
    /// Décrit précisément le champ fautif d'une DecodingError pour les logs
    /// (ex. "typeMismatch(String) at 'supplements_schedule.morning[0]'").
    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .typeMismatch(let type, let context):
            return "typeMismatch(\(type)) at '\(path(context))': \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "valueNotFound(\(type)) at '\(path(context))'"
        case .keyNotFound(let key, let context):
            return "keyNotFound(\(key.stringValue)) at '\(path(context))'"
        case .dataCorrupted(let context):
            return "dataCorrupted at '\(path(context))': \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }

    // MARK: - Circuit Breaker Helper
    private func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= maxConsecutiveFailures {
            circuitOpenUntil = Date().addingTimeInterval(circuitResetInterval)
            AppLogger.analysis.warning("Circuit breaker opened after \(self.consecutiveFailures, privacy: .public) consecutive failures. Resetting in 5 minutes.")
        }
    }

    // MARK: - Force Regenerate
    func regenerate(userId: String, profile: UserProfile) async throws -> MergedAnalysis? {
        try? await DatabaseService.shared.clearAIAnalysis(userId: userId)
        return try await fetchFullAnalysis(userId: userId, profile: profile)
    }

    // MARK: - Hash Profile (same djb2 as web — excludes completed + firstName)
    static func hashProfile(_ profile: UserProfile) -> String {
        // Web: excludes "completed" and "firstName", sorts remaining keys
        var copy = profile
        copy.completed = false
        copy.firstName = ""
        guard let data = try? JSONEncoder().encode(copy),
              let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "0" }

        // Filter out metadata fields (same as web)
        let filtered = jsonObj.filter { $0.key != "completed" && $0.key != "firstName" }
        let sortedKeys = filtered.keys.sorted()

        // Build deterministic string (key=value pairs, sorted)
        var parts: [String] = []
        for key in sortedKeys {
            if let val = filtered[key] {
                parts.append("\(key):\(val)")
            }
        }
        let str = parts.joined(separator: "|")

        // djb2 hash (same as web)
        var h: Int64 = 5381
        for char in str.unicodeScalars {
            h = ((h << 5) &+ h) &+ Int64(char.value)
        }
        return String(abs(h), radix: 36)
    }

    // MARK: - Merge with Canonical (forces local labels/emojis/scores)
    private func mergeWithCanonical(
        aiData: AIAnalysisResponse,
        localScores: [String: Int],
        healthScore: Int,
        redFlags: [RedFlag]
    ) -> MergedAnalysis {
        // Build AI info lookup
        var aiInfoMap: [String: AIRisk] = [:]
        if let risks = aiData.nutrientRisks {
            for risk in risks {
                if let id = risk.id { aiInfoMap[id] = risk }
            }
        }

        // Build enriched nutrients array (local scores + AI explanations)
        let nutrients: [EnrichedNutrient] = NutrientData.all.map { def in
            let score = localScores[def.id.rawValue] ?? 50
            let status = NutrientStatus(score: score)
            let ai = aiInfoMap[def.id.rawValue]

            return EnrichedNutrient(
                id: def.id.rawValue,
                label: def.label,       // ALWAYS from local
                emoji: def.emoji,        // ALWAYS from local
                color: def.colorHex,     // ALWAYS from local
                score: score,            // ALWAYS from local (deterministic)
                status: status.rawValue,
                confidence: ai?.confidence ?? (score < 40 ? "high" : score < 60 ? "moderate" : "low"),
                signals: ai?.signals,
                verdict: ai?.verdict,
                mecanisme: ai?.mecanisme,
                comparaison: ai?.comparaison,
                signeManque: ai?.signeManque,
                solution: ai?.solution.map { NutrientSolutionAI(action: $0.action, dosage: $0.dosage, quand: $0.quand, pourquoi: $0.pourquoi, delai: $0.delai) },
                hack: ai?.hack,
                synergie: ai?.synergie,
                pourquoiCeScore: ai?.pourquoiCeScore,
                hypotheses: ai?.hypotheses
            )
        }

        // Normalize bilan
        let bilanDetail: BilanLegacy?
        if let summary = aiData.summary, aiData.bilan == nil {
            bilanDetail = BilanLegacy(
                synthese: summary.headline,
                profilType: summary.profilType,
                metaphoreGlobale: summary.metaphore,
                pointsForts: aiData.positiveFindings?.compactMap(\.finding),
                axesAmelioration: aiData.priorityActions?.compactMap(\.action)
            )
        } else {
            bilanDetail = aiData.bilan
        }

        // Normalize pepites (emoji fallback like web)
        let pepites: [PracticalTip] = (aiData.practicalTips ?? aiData.pepitesSante ?? []).map { tip in
            var normalized = tip
            if normalized.emoji == nil || normalized.emoji?.isEmpty == true {
                normalized.emoji = "💡"
            }
            return normalized
        }

        // Normalize interactions
        let interactions: [InteractionDetected] = (aiData.interactionsDetectees ?? []).map { inter in
            var normalized = inter
            if normalized.nutrimentsConcernes == nil {
                normalized.nutrimentsConcernes = inter.nutriments
            }
            return normalized
        }

        return MergedAnalysis(
            healthScore: healthScore,
            scores: localScores,
            nutrients: nutrients,
            redFlags: redFlags,
            summary: aiData.summary,
            bilanDetail: bilanDetail,
            interactions: interactions,
            pepites: pepites,
            priorityActions: aiData.priorityActions ?? [],
            positiveFindings: aiData.positiveFindings ?? [],
            supplementsSchedule: aiData.supplementsSchedule,
            bloodTests: aiData.bloodTests,
            symptomesAnalyse: aiData.symptomesAnalyse ?? [],
            objectifsAnalyse: aiData.objectifsAnalyse ?? [],
            meta: aiData.meta
        )
    }
}

// MARK: - Merged Analysis (final data for UI)
struct MergedAnalysis {
    let healthScore: Int
    let scores: [String: Int]
    let nutrients: [EnrichedNutrient]
    let redFlags: [RedFlag]
    let summary: AnalysisSummary?
    let bilanDetail: BilanLegacy?
    let interactions: [InteractionDetected]
    let pepites: [PracticalTip]
    let priorityActions: [PriorityAction]
    let positiveFindings: [PositiveFinding]
    let supplementsSchedule: SupplementsSchedule?
    let bloodTests: BloodTests?
    // Défaut [] → les call-sites existants (tests) restent compatibles ;
    // mergeWithCanonical les renseigne explicitement.
    var symptomesAnalyse: [SymptomeAnalyse] = []
    var objectifsAnalyse: [ObjectifAnalyse] = []
    let meta: AnalysisMeta?

    /// Overall score (1-10) from AI summary
    var overallScore: Int { summary?.overallScore ?? (healthScore / 10) }

    /// Top 3 deficient nutrients
    var topDeficiencies: [EnrichedNutrient] {
        nutrients.filter { $0.score < 60 }.sorted { $0.score < $1.score }.prefix(3).map { $0 }
    }

    /// Nutrients that are OK
    var goodNutrients: [EnrichedNutrient] {
        nutrients.filter { $0.score >= 75 }
    }
}

// MARK: - Edge Function Request DTO
private struct EdgeFunctionRequest: Encodable {
    let scores: [String: Int]
    let healthScore: Int
    let redFlags: [EdgeFlagDTO]
    let profileHash: String
    let forceRefresh: Bool
}

private struct EdgeFlagDTO: Encodable {
    let id: String
    let urgency: String
    let message: String
}

// MARK: - Errors
enum AIAnalysisError: LocalizedError {
    case timeout
    case invalidResponse
    case rateLimited                 // HTTP 429
    case clientError(Int)            // HTTP 4xx (not 429)
    case serverError(Int)            // HTTP 5xx or relay
    case networkError(Error)         // URLError (lost connection, etc.)
    case circuitOpen                 // Circuit breaker is open

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "L'analyse a pris trop de temps. Veuillez reessayer."
        case .invalidResponse:
            return "La reponse de l'IA est invalide."
        case .rateLimited:
            return "Trop de demandes. Veuillez patienter quelques minutes avant de reessayer."
        case .clientError(let code):
            return "Erreur lors de l'analyse (code \(code)). Verifiez vos donnees et reessayez."
        case .serverError(let code):
            return code > 0
                ? "Le serveur d'analyse est indisponible (code \(code)). Reessayez plus tard."
                : "Le serveur d'analyse est indisponible. Reessayez plus tard."
        case .networkError:
            return "Probleme de connexion. Verifiez votre reseau et reessayez."
        case .circuitOpen:
            return "Le service d'analyse est temporairement indisponible suite a plusieurs echecs. Reessayez dans quelques minutes."
        }
    }

    /// Whether an automatic retry is reasonable for this error type.
    var isRetryable: Bool {
        switch self {
        case .timeout, .serverError, .networkError: return true
        case .rateLimited, .clientError, .invalidResponse, .circuitOpen: return false
        }
    }
}
