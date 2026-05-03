import Foundation

// MARK: - AI Analysis Response (v7 schema — matches Edge Function output)
struct AIAnalysisResponse: Codable {
    var summary: AnalysisSummary?
    var redFlags: [AIRedFlag]?
    var nutrientRisks: [AIRisk]?
    var positiveFindings: [PositiveFinding]?
    var priorityActions: [PriorityAction]?
    var practicalTips: [PracticalTip]?
    var supplementsSchedule: SupplementsSchedule?
    var bloodTests: BloodTests?
    var interactionsDetectees: [InteractionDetected]?
    var meta: AnalysisMeta?

    // Legacy v6 compat
    var bilan: BilanLegacy?
    var nutriments: [String: AIRisk]?
    var pepitesSante: [PracticalTip]?

    enum CodingKeys: String, CodingKey {
        case summary
        case redFlags = "red_flags"
        case nutrientRisks = "nutrient_risks"
        case positiveFindings = "positive_findings"
        case priorityActions = "priority_actions"
        case practicalTips = "practical_tips"
        case supplementsSchedule = "supplements_schedule"
        case bloodTests = "blood_tests"
        case interactionsDetectees = "interactions_detectees"
        case meta
        case bilan, nutriments
        case pepitesSante = "pepites_sante"
    }
}

// MARK: - Summary
struct AnalysisSummary: Codable {
    var overallScore: Int?
    var overallLabel: String?
    var headline: String?
    var metaphore: String?
    var profilType: String?

    enum CodingKeys: String, CodingKey {
        case overallScore = "overall_score"
        case overallLabel = "overall_label"
        case headline, metaphore
        case profilType = "profil_type"
    }
}

// MARK: - AI Red Flag
struct AIRedFlag: Codable, Identifiable {
    var id: String { flag ?? UUID().uuidString }
    var flag: String?
    var message: String?
    var urgency: String?
}

// MARK: - AI Nutrient Risk
struct AIRisk: Codable, Identifiable {
    var id: String?
    var confidence: String?
    var signals: [String]?
    var verdict: String?
    var mecanisme: String?
    var comparaison: String?
    var signeManque: String?
    var solution: AIRiskSolution?
    var hack: String?
    var synergie: String?
    var pourquoiCeScore: String?

    enum CodingKeys: String, CodingKey {
        case id, confidence, signals, verdict, mecanisme, comparaison
        case signeManque = "signe_manque"
        case solution, hack, synergie
        case pourquoiCeScore = "pourquoi_ce_score"
    }
}

struct AIRiskSolution: Codable {
    var action: String?
    var dosage: String?
    var quand: String?
    var pourquoi: String?
    var delai: String?
}

// MARK: - Positive Finding
struct PositiveFinding: Codable, Identifiable {
    var id: String { finding ?? UUID().uuidString }
    var finding: String?
    var nutrientsCovered: [String]?

    enum CodingKeys: String, CodingKey {
        case finding
        case nutrientsCovered = "nutrients_covered"
    }
}

// MARK: - Priority Action
struct PriorityAction: Codable, Identifiable {
    var id: Int { rank ?? 0 }
    var rank: Int?
    var action: String?
    var expectedImpact: String?
    var difficulty: String?

    enum CodingKeys: String, CodingKey {
        case rank, action
        case expectedImpact = "expected_impact"
        case difficulty
    }
}

// MARK: - Practical Tip (pepite sante)
struct PracticalTip: Codable, Identifiable {
    var id: String { tip ?? hook ?? UUID().uuidString }
    var tip: String?
    var why: String?
    var impact: String?
    var emoji: String?
    var hook: String?
    var detail: String?
    var hack: String?
    var source: String?
    var categorie: String?
}

// MARK: - Supplements Schedule
struct SupplementsSchedule: Codable {
    var morning: [String]?
    var afternoon: [String]?
    var evening: [String]?
    var warnings: [String]?
}

// MARK: - Blood Tests
struct BloodTests: Codable {
    var recommended: Bool?
    var tests: [String]?
    var why: String?

    enum CodingKeys: String, CodingKey {
        case recommended, tests, why
    }
}

// MARK: - Interaction Detected
struct InteractionDetected: Codable, Identifiable {
    var id: String { titre ?? UUID().uuidString }
    var titre: String?
    var emoji: String?
    var nutriments: [String]?
    var nutrimentsConcernes: [String]?
    var explication: String?
    var solution: String?

    enum CodingKeys: String, CodingKey {
        case titre, emoji, nutriments
        case nutrimentsConcernes = "nutriments_concernes"
        case explication, solution
    }

    /// Returns the nutrient IDs (prefers nutriments_concernes, falls back to nutriments)
    var resolvedNutrients: [String] {
        nutrimentsConcernes ?? nutriments ?? []
    }
}

// MARK: - Analysis Meta
struct AnalysisMeta: Codable {
    var schemaVersion: Int?
    var profileHash: String?
    var truncated: Bool?
    var structIssues: [String]?
    var complianceChecked: Bool?
    var complianceIssues: [String]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case profileHash = "profile_hash"
        case truncated
        case structIssues = "struct_issues"
        case complianceChecked = "compliance_checked"
        case complianceIssues = "compliance_issues"
    }
}

// MARK: - Legacy v6 Bilan
struct BilanLegacy: Codable {
    var synthese: String?
    var profilType: String?
    var metaphoreGlobale: String?
    var pointsForts: [String]?
    var axesAmelioration: [String]?

    enum CodingKeys: String, CodingKey {
        case synthese
        case profilType = "profil_type"
        case metaphoreGlobale = "metaphore_globale"
        case pointsForts = "points_forts"
        case axesAmelioration = "axes_amelioration"
    }
}

// MARK: - Validation
extension AIAnalysisResponse {
    var isValidV7: Bool {
        guard summary != nil else { return false }
        // Per web parity: overall_score may legitimately be 0 (deterministic local scoring).
        // Only require the field to be present, not > 0.
        guard summary?.overallScore != nil else { return false }
        guard let risks = nutrientRisks, !risks.isEmpty else { return false }
        let validIDs = Set(NutrientID.allCases.map(\.rawValue))
        for risk in risks {
            guard let id = risk.id, validIDs.contains(id) else { return false }
            guard let conf = risk.confidence, ["high", "moderate", "low"].contains(conf) else { return false }
        }
        return true
    }
}
