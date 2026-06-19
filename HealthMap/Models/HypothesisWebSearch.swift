import Foundation

// MARK: - validate-hypotheses (Q2 + recherche web)
//
// Modèles d'E/S de l'Edge Function `validate-hypotheses`. La fonction lit des
// clés camelCase en entrée (body.nutrientId, body.q2Answers, body.v1Hypotheses,
// body.score, body.webSearch) et renvoie un mélange camel/snake en sortie —
// les CodingKeys ci-dessous reflètent EXACTEMENT le payload déployé.
//
// `webSearch:true` => la fonction passe sur Sonnet 4.6 + outil de recherche web
// et renvoie `web_evidence` (sources RÉELLES extraites des résultats de
// recherche, jamais inventées par le modèle).

// MARK: - Requête

struct ValidateHypothesesRequest: Encodable {
    let nutrientId: String
    let q2Answers: [String: String]
    let v1Hypotheses: [V1HypothesisDTO]
    let score: Int
    let webSearch: Bool
}

struct V1HypothesisDTO: Encodable {
    let id: String
    let label: String
    let likelihood: String?
    let mechanism: String?
}

// MARK: - Réponse

struct ValidateHypothesesResponse: Decodable {
    var nutrientId: String?
    var revisedScore: Int?
    var confirmedHypothesis: HypothesisVerdict?
    var eliminatedHypotheses: [HypothesisVerdict]?
    var uncertainHypotheses: [HypothesisVerdict]?
    var synthesis: String?
    var disclaimer: String?
    var webEvidence: [WebEvidenceItem]?
    var meta: HypothesisMeta?

    enum CodingKeys: String, CodingKey {
        case nutrientId
        case revisedScore = "revised_score"
        case confirmedHypothesis = "confirmed_hypothesis"
        case eliminatedHypotheses = "eliminated_hypotheses"
        case uncertainHypotheses = "uncertain_hypotheses"
        case synthesis, disclaimer
        case webEvidence = "web_evidence"
        case meta
    }
}

struct HypothesisVerdict: Decodable, Identifiable {
    var id: String { hypId ?? UUID().uuidString }
    var hypId: String?
    var label: String?
    var reason: String?
    var evidence: [String]?

    enum CodingKeys: String, CodingKey {
        case hypId = "id"
        case label, reason, evidence
    }
}

struct WebEvidenceItem: Decodable, Identifiable {
    var id: String { url ?? UUID().uuidString }
    var title: String?
    var url: String?
    var citedText: String?

    enum CodingKeys: String, CodingKey {
        case title, url
        case citedText = "cited_text"
    }

    /// Domaine lisible pour l'affichage (ex. « pubmed.ncbi.nlm.nih.gov »).
    var host: String {
        guard let url, let comps = URLComponents(string: url), let host = comps.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

struct HypothesisMeta: Decodable {
    var model: String?
    var webSearch: Bool?
    var webResults: Int?
    var searchesRun: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case webSearch = "web_search"
        case webResults = "web_results"
        case searchesRun = "searches_run"
    }
}
