import Foundation

// MARK: - AI Analysis Response (v7 schema — matches Edge Function output)
//
// ⚠️ DÉCODAGE TOLÉRANT (incident TestFlight 28, 9 juin 2026) :
// le serveur peut renvoyer un JSON tronqué puis réparé (meta.truncated=true)
// et le modèle peut produire des formes hors schéma (ex. supplements_schedule
// sous forme d'objets {name, dose, ...}, id de nutriment hors catalogue comme
// "folate"). Chaque champ est donc décodé indépendamment via les extensions
// en bas de fichier : un champ malformé → nil, une entrée de tableau
// malformée → skippée avec log. On ne jette JAMAIS toute l'analyse pour une
// seule entrée invalide.
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
    var symptomesAnalyse: [SymptomeAnalyse]?
    var objectifsAnalyse: [ObjectifAnalyse]?
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
        case symptomesAnalyse = "symptomes_analyse"
        case objectifsAnalyse = "objectifs_analyse"
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

    enum CodingKeys: String, CodingKey {
        case flag, message, urgency
    }
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
    /// Hypothèses explicatives v1 (id + label + mécanisme) — alimentent la
    /// « Recherche approfondie » (validate-hypotheses). Décodées depuis la
    /// même `ai_analysis` partagée avec le web ; étaient ignorées avant.
    var hypotheses: [AIHypothesis]?

    enum CodingKeys: String, CodingKey {
        case id, confidence, signals, verdict, mecanisme, comparaison
        case signeManque = "signe_manque"
        case solution, hack, synergie
        case pourquoiCeScore = "pourquoi_ce_score"
        case hypotheses
    }
}

// MARK: - AI Hypothesis (v1 — arbitrée par validate-hypotheses)
struct AIHypothesis: Codable, Identifiable {
    var id: String { hypId ?? UUID().uuidString }
    var hypId: String?
    var label: String?
    var mechanism: String?
    var likelihood: String?

    enum CodingKeys: String, CodingKey {
        case hypId = "id"
        case label, mechanism, likelihood
    }
}

struct AIRiskSolution: Codable {
    var action: String?
    var dosage: String?
    var quand: String?
    var pourquoi: String?
    var delai: String?

    enum CodingKeys: String, CodingKey {
        case action, dosage, quand, pourquoi, delai
    }
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

    enum CodingKeys: String, CodingKey {
        case tip, why, impact, emoji, hook, detail, hack, source, categorie
    }
}

// MARK: - Supplement Entry (chaîne OU objet — les deux formes existent)
/// Le prompt serveur (v33, exemples du schéma) fait générer des OBJETS
/// `{name, dose, form, reason, priority}` pour les créneaux du planning,
/// mais d'anciens payloads/caches peuvent contenir de simples chaînes.
/// On décode les deux formes et on ré-encode la forme d'origine (fidélité du
/// cache : la ligne `profiles.ai_analysis` est partagée avec le web).
struct SupplementEntry: Codable, Hashable {
    var name: String?
    var dose: String?
    var form: String?
    var reason: String?
    var priority: String?
    /// Forme chaîne brute (payloads legacy)
    var rawString: String?

    enum CodingKeys: String, CodingKey {
        case name, dose, form, reason, priority
    }

    /// Texte d'affichage : « Fer (bisglycinate) — 25-30 mg » ou la chaîne brute.
    var displayText: String {
        if let rawString, !rawString.isEmpty { return rawString }
        let base = name ?? "Complement"
        if let dose, !dose.isEmpty { return "\(base) — \(dose)" }
        return base
    }
}

// MARK: - Supplements Schedule
struct SupplementsSchedule: Codable {
    var morning: [SupplementEntry]?
    var afternoon: [SupplementEntry]?
    var evening: [SupplementEntry]?
    var warnings: [String]?

    enum CodingKeys: String, CodingKey {
        case morning, afternoon, evening, warnings
    }
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

// MARK: - Symptôme analysé (enquête par symptôme déclaré)
struct SymptomeAnalyse: Codable, Identifiable {
    var id: String { symptome ?? UUID().uuidString }
    var symptome: String?
    var causesProbables: [String]?
    var aVerifier: String?

    enum CodingKeys: String, CodingKey {
        case symptome
        case causesProbables = "causes_probables"
        case aVerifier = "a_verifier"
    }
}

// MARK: - Objectif analysé (freins + leviers par objectif déclaré)
struct ObjectifAnalyse: Codable, Identifiable {
    var id: String { objectif ?? UUID().uuidString }
    var objectif: String?
    var freins: [String]?
    var leviers: [String]?

    enum CodingKeys: String, CodingKey {
        case objectif, freins, leviers
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

// MARK: - Helpers de décodage tolérant

/// Tableau tolérant : une entrée indécodable est ignorée (avec log) au lieu
/// de faire échouer le décodage du tableau entier — indispensable quand le
/// serveur a tronqué puis réparé le JSON (meta.truncated).
struct LossyDecodableArray<Element: Decodable>: Decodable {
    let elements: [Element]

    /// Consomme l'élément courant quel que soit son type JSON, pour faire
    /// avancer l'index du container quand l'élément ne se décode pas en `Element`.
    private struct BlackHole: Decodable {
        init(from decoder: Decoder) throws {}
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Element] = []
        var skipped = 0
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                decoded.append(element)
            } else {
                // L'index n'avance pas sur un échec : on consomme la valeur
                // via BlackHole. S'il échoue aussi (impossible en pratique),
                // on sort pour éviter toute boucle infinie.
                if (try? container.decode(BlackHole.self)) == nil { break }
                skipped += 1
            }
        }
        if skipped > 0 {
            AppLogger.analysis.warning("Analyse IA : \(skipped, privacy: .public) entrée(s) \(String(describing: Element.self), privacy: .public) malformée(s) ignorée(s)")
        }
        elements = decoded
    }
}

private extension KeyedDecodingContainer {
    /// Décodage indulgent : clé absente, valeur null OU type inattendu → nil.
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Tableau indulgent : les entrées malformées sont skippées une à une.
    func lenientArray<T: Decodable>(_ key: Key) -> [T]? {
        guard let lossy: LossyDecodableArray<T> = lenient(key) else { return nil }
        return lossy.elements
    }

    /// Entier indulgent : accepte Int, Double (arrondi) ou String numérique —
    /// le modèle peut renvoyer "7" ou 7.0 au lieu de 7.
    func lenientInt(_ key: Key) -> Int? {
        if let intValue: Int = lenient(key) { return intValue }
        if let doubleValue: Double = lenient(key) { return Int(doubleValue.rounded()) }
        if let stringValue: String = lenient(key),
           let doubleValue = Double(stringValue.trimmingCharacters(in: .whitespaces)) {
            return Int(doubleValue.rounded())
        }
        return nil
    }
}

// MARK: - Décodage tolérant (init(from:) par type)
// Les inits custom vivent en EXTENSION pour préserver les inits memberwise
// (utilisés par AIAnalysisService.mergeWithCanonical et les tests).
// `encode(to:)` reste synthétisé : le ré-encodage du cache garde les clés v7.

extension AIAnalysisResponse {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = c.lenient(.summary)
        redFlags = c.lenientArray(.redFlags)
        nutrientRisks = c.lenientArray(.nutrientRisks)
        positiveFindings = c.lenientArray(.positiveFindings)
        priorityActions = c.lenientArray(.priorityActions)
        practicalTips = c.lenientArray(.practicalTips)
        supplementsSchedule = c.lenient(.supplementsSchedule)
        bloodTests = c.lenient(.bloodTests)
        interactionsDetectees = c.lenientArray(.interactionsDetectees)
        symptomesAnalyse = c.lenientArray(.symptomesAnalyse)
        objectifsAnalyse = c.lenientArray(.objectifsAnalyse)
        meta = c.lenient(.meta)
        bilan = c.lenient(.bilan)
        nutriments = c.lenient(.nutriments)
        pepitesSante = c.lenientArray(.pepitesSante)
    }
}

extension AnalysisSummary {
    init(from decoder: Decoder) throws {
        // Legacy : summary sous forme de simple chaîne → devient le headline.
        if let single = try? decoder.singleValueContainer(),
           let str = try? single.decode(String.self) {
            headline = str
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overallScore = c.lenientInt(.overallScore)
        overallLabel = c.lenient(.overallLabel)
        headline = c.lenient(.headline)
        metaphore = c.lenient(.metaphore)
        profilType = c.lenient(.profilType)
    }
}

extension AIRedFlag {
    /// Les red flags réinjectés par le serveur (fallback) utilisent la clé
    /// "id" du DTO client au lieu de "flag" — on accepte les deux.
    private enum LegacyKeys: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flag = c.lenient(.flag)
        message = c.lenient(.message)
        urgency = c.lenient(.urgency)
        if flag == nil, let legacy = try? decoder.container(keyedBy: LegacyKeys.self) {
            flag = legacy.lenient(.id)
        }
    }
}

extension AIRisk {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id)
        confidence = c.lenient(.confidence)
        signals = c.lenientArray(.signals)
        verdict = c.lenient(.verdict)
        mecanisme = c.lenient(.mecanisme)
        comparaison = c.lenient(.comparaison)
        signeManque = c.lenient(.signeManque)
        solution = c.lenient(.solution)
        hack = c.lenient(.hack)
        synergie = c.lenient(.synergie)
        pourquoiCeScore = c.lenient(.pourquoiCeScore)
        hypotheses = c.lenientArray(.hypotheses)
    }
}

extension AIHypothesis {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hypId = c.lenient(.hypId)
        label = c.lenient(.label)
        mechanism = c.lenient(.mechanism)
        likelihood = c.lenient(.likelihood)
    }
}

extension SymptomeAnalyse {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symptome = c.lenient(.symptome)
        causesProbables = c.lenientArray(.causesProbables)
        aVerifier = c.lenient(.aVerifier)
    }
}

extension ObjectifAnalyse {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        objectif = c.lenient(.objectif)
        freins = c.lenientArray(.freins)
        leviers = c.lenientArray(.leviers)
    }
}

extension AIRiskSolution {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = c.lenient(.action)
        dosage = c.lenient(.dosage)
        quand = c.lenient(.quand)
        pourquoi = c.lenient(.pourquoi)
        delai = c.lenient(.delai)
    }
}

extension PositiveFinding {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        finding = c.lenient(.finding)
        nutrientsCovered = c.lenientArray(.nutrientsCovered)
    }
}

extension PriorityAction {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = c.lenientInt(.rank)
        action = c.lenient(.action)
        expectedImpact = c.lenient(.expectedImpact)
        difficulty = c.lenient(.difficulty)
    }
}

extension PracticalTip {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tip = c.lenient(.tip)
        why = c.lenient(.why)
        impact = c.lenient(.impact)
        emoji = c.lenient(.emoji)
        hook = c.lenient(.hook)
        detail = c.lenient(.detail)
        hack = c.lenient(.hack)
        source = c.lenient(.source)
        categorie = c.lenient(.categorie)
    }
}

extension SupplementEntry {
    init(from decoder: Decoder) throws {
        // Forme chaîne ("Fer bisglycinate 25 mg")
        if let single = try? decoder.singleValueContainer(),
           let str = try? single.decode(String.self) {
            rawString = str
            return
        }
        // Forme objet {name, dose, form, reason, priority} — schéma v7 serveur
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenient(.name)
        dose = c.lenient(.dose)
        form = c.lenient(.form)
        reason = c.lenient(.reason)
        priority = c.lenient(.priority)
    }

    func encode(to encoder: Encoder) throws {
        if let rawString {
            var single = encoder.singleValueContainer()
            try single.encode(rawString)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(dose, forKey: .dose)
        try c.encodeIfPresent(form, forKey: .form)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encodeIfPresent(priority, forKey: .priority)
    }
}

extension SupplementsSchedule {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        morning = c.lenientArray(.morning)
        afternoon = c.lenientArray(.afternoon)
        evening = c.lenientArray(.evening)
        warnings = c.lenientArray(.warnings)
    }
}

extension BloodTests {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recommended = c.lenient(.recommended)
        tests = c.lenientArray(.tests)
        why = c.lenient(.why)
    }
}

extension InteractionDetected {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titre = c.lenient(.titre)
        emoji = c.lenient(.emoji)
        nutriments = c.lenientArray(.nutriments)
        nutrimentsConcernes = c.lenientArray(.nutrimentsConcernes)
        explication = c.lenient(.explication)
        solution = c.lenient(.solution)
    }
}

extension AnalysisMeta {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.lenientInt(.schemaVersion)
        profileHash = c.lenient(.profileHash)
        truncated = c.lenient(.truncated)
        structIssues = c.lenientArray(.structIssues)
        complianceChecked = c.lenient(.complianceChecked)
        complianceIssues = c.lenientArray(.complianceIssues)
    }
}

extension BilanLegacy {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        synthese = c.lenient(.synthese)
        profilType = c.lenient(.profilType)
        metaphoreGlobale = c.lenient(.metaphoreGlobale)
        pointsForts = c.lenientArray(.pointsForts)
        axesAmelioration = c.lenientArray(.axesAmelioration)
    }
}

// MARK: - Sanitization & Validation
extension AIAnalysisResponse {
    /// Copie nettoyée du payload IA :
    /// - les `nutrient_risks` dont l'id n'est pas dans le catalogue canonique
    ///   (NutrientData) sont SKIPPÉS avec un log — ex. "folate" généré hors
    ///   catalogue par le modèle (incident TestFlight 28 du 9 juin 2026) ;
    /// - une `confidence` inconnue est remise à nil (le merge la recalcule
    ///   localement à partir du score déterministe).
    /// Ne jette jamais : on garde tout ce qui est exploitable.
    func sanitized() -> AIAnalysisResponse {
        var copy = self
        if let risks = nutrientRisks {
            let validIDs = NutrientData.validIDs
            var kept: [AIRisk] = []
            for risk in risks {
                guard let riskID = risk.id, validIDs.contains(riskID) else {
                    AppLogger.analysis.warning("Analyse IA : nutrient_risk ignoré (id hors catalogue : \(risk.id ?? "nil", privacy: .public))")
                    continue
                }
                var cleaned = risk
                if let conf = cleaned.confidence, !["high", "moderate", "low"].contains(conf) {
                    AppLogger.analysis.notice("Analyse IA : confidence inconnue '\(conf, privacy: .public)' pour \(riskID, privacy: .public) — fallback local")
                    cleaned.confidence = nil
                }
                kept.append(cleaned)
            }
            copy.nutrientRisks = kept
        }
        return copy
    }

    /// Validation v7 ASSOUPLIE : on exige uniquement un summary exploitable.
    /// Les nutrient_risks peuvent être vides (profil sain, ou entrées toutes
    /// filtrées par `sanitized()`) — les scores affichés viennent de toute
    /// façon du calcul LOCAL (HealthCalculator), jamais de l'IA.
    var isValidV7: Bool {
        guard let summary else { return false }
        return summary.overallScore != nil || summary.headline?.isEmpty == false
    }
}
