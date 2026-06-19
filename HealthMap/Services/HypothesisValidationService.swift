import Foundation
import Supabase

// MARK: - Hypothesis Validation Service (Q2 + recherche web approfondie)
/// Appelle l'Edge Function `validate-hypotheses` avec `webSearch:true` : le
/// serveur arbitre les hypothèses v1 du nutriment ET va chercher des articles
/// scientifiques réels (PubMed, EFSA, Cochrane…) pour étayer. Le profil
/// (questionnaire + bilan) est relu côté serveur ; on n'envoie que le nutriment,
/// ses hypothèses v1 et son score.
///
/// @MainActor comme les autres services appelés depuis les vues.
@MainActor
final class HypothesisValidationService {
    static let shared = HypothesisValidationService()
    private var client: SupabaseClient { SupabaseService.shared.client }

    /// Borne client : la fonction plafonne déjà à 160 s côté serveur (plusieurs
    /// allers-retours de recherche), on laisse une marge.
    private let timeoutSeconds: Double = 175

    private init() {}

    func deepSearch(
        nutrientId: String,
        hypotheses: [AIHypothesis],
        score: Int
    ) async throws -> ValidateHypothesesResponse {
        let v1: [V1HypothesisDTO] = hypotheses.compactMap { h in
            guard let id = h.hypId, let label = h.label else { return nil }
            return V1HypothesisDTO(id: id, label: label, likelihood: h.likelihood, mechanism: h.mechanism)
        }
        guard !v1.isEmpty else { throw AIAnalysisError.invalidResponse }

        let body = ValidateHypothesesRequest(
            nutrientId: nutrientId,
            q2Answers: [:],          // iOS n'a pas de questionnaire Q2 : la fonction arbitre depuis le profil + le web
            v1Hypotheses: v1,
            score: score,
            webSearch: true
        )

        return try await withThrowingTaskGroup(of: ValidateHypothesesResponse.self) { group in
            group.addTask {
                try await self.client.functions.invoke(
                    "validate-hypotheses",
                    options: .init(body: body)
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(self.timeoutSeconds))
                throw AIAnalysisError.timeout
            }
            guard let result = try await group.next() else {
                group.cancelAll()
                throw AIAnalysisError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}
