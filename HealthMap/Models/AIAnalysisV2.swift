import SwiftUI

// MARK: - AI Analysis v2 (contrat "v2" — generate-analysis, tache: "bilan")
//
// Nouveau contrat structuré qui nourrit l'écran Bilan v6. Les blocs `plan` et
// `complements` sont modélisés dès maintenant (Codable complet) mais ne seront
// consommés par l'UI qu'à la vague V4 — le flux v7 (AIAnalysis.swift) continue
// de nourrir Plan/Compléments d'ici là.
//
// ⚠️ DÉCODAGE TOLÉRANT (même doctrine que AIAnalysis.swift) : chaque champ est
// décodé indépendamment via les extensions en bas de fichier — un champ
// malformé → nil, une entrée de tableau malformée → skippée
// (LossyDecodableArray). On ne jette JAMAIS toute la réponse pour une seule
// entrée invalide. Les inits custom vivent en EXTENSION pour préserver les
// inits memberwise (mocks de tests, prévisualisations).
struct AIAnalysisV2: Codable {
    var contract: String?          // "v2"
    var score: Int?                // score global 0-100
    var besoinsNourris: Int?       // nb d'apports couverts
    var bilan: BilanV2?
    var plan: PlanV2?              // consommé à la vague V4
    var complements: ComplementsV2? // consommé à la vague V4
    var meta: MetaV2?

    enum CodingKeys: String, CodingKey {
        case contract, score, besoinsNourris, bilan, plan, complements, meta
    }

    /// Validation minimale : le bilan est exploitable si au moins un apport
    /// est présent (le contrat en garantit exactement 3).
    var isValidV2: Bool {
        bilan?.apports?.isEmpty == false
    }
}

// MARK: - Statut d'apport (enum tolérante + mapping couleur côté client)
/// Statut d'un apport : couvre le besoin / à renforcer / à combler.
/// Décodage tolérant : valeur inconnue ou absente → `.neutre`.
enum StatutV2: String, Codable, Hashable {
    case couvre = "couvre"
    case aRenforcer = "a_renforcer"
    case aCombler = "a_combler"
    case neutre = "neutre"

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = StatutV2(rawValue: raw) ?? .neutre
    }

    // Mapping couleur du contrat v2, côté client. Tokens existants de
    // Color+Theme.swift réutilisés quand ils existent :
    // - couvre      → .kiwiGreen (#5DA838), encre .kiwiGreenInk (#3B6D11)
    // - a_renforcer → .scoreLow (#FF9500), encre #D9820A (aucun token existant)
    // - a_combler   → .scoreDeficient (#FF3B30), encre #E0392B (aucun token)
    // - neutre      → #C2BDB0 (aucun token), encre .healthMapSecondary

    /// Couleur principale du statut (jauges, pastilles).
    var color: Color {
        switch self {
        case .couvre: return .kiwiGreen
        case .aRenforcer: return .scoreLow
        case .aCombler: return .scoreDeficient
        case .neutre: return Color(hex: "C2BDB0")
        }
    }

    /// Encre du statut (texte lisible sur fond teinté).
    var inkColor: Color {
        switch self {
        case .couvre: return .kiwiGreenInk
        case .aRenforcer: return Color(hex: "D9820A")
        case .aCombler: return Color(hex: "E0392B")
        case .neutre: return .healthMapSecondary
        }
    }
}

// MARK: - Bilan
struct BilanV2: Codable {
    var scoreInsight: String?      // ≤90 caractères
    var apportsInsight: String?    // ≤90 caractères
    var apports: [ApportV2]?       // exactement 3 côté serveur
    var symptomes: [SymptomeV2]?
    var interactions: [InteractionV2]?  // ≤2

    enum CodingKeys: String, CodingKey {
        case scoreInsight, apportsInsight, apports, symptomes, interactions
    }
}

// MARK: - Apport
struct ApportV2: Codable, Identifiable {
    var id: String?                // id de nutriment (ex. "iron")
    var nom: String?               // ex. "Fer"
    var statut: StatutV2 = .neutre
    var pctBesoin: Int?            // % du besoin couvert (0-100)
    var why: String?               // 2 phrases
    var tipBold: String?           // ≤55
    var tipRest: String?           // ≤80
    var aliments: [AlimentV2]?     // 3 aliments

    enum CodingKeys: String, CodingKey {
        case id, nom, statut, pctBesoin, why, tipBold, tipRest, aliments
    }
}

// MARK: - Aliment
struct AlimentV2: Codable, Hashable {
    var nom: String?
    /// Id d'icône NU de la liste fermée du contrat (ex. "fish") — l'asset iOS
    /// correspondant est `fluent_<id>`, résolu par `SafeFluent3DIcon`.
    var icone: String?

    enum CodingKeys: String, CodingKey {
        case nom, icone
    }
}

// MARK: - Symptôme
struct SymptomeV2: Codable, Identifiable {
    var id: String?
    var nom: String?
    /// Ids d'apports liés (ex. ["iron", "zinc"]) — pointent vers `ApportV2.id`.
    var causes: [String]?

    enum CodingKeys: String, CodingKey {
        case id, nom, causes
    }
}

// MARK: - Interaction (bilan)
struct InteractionV2: Codable, Identifiable {
    var tipBold: String?
    var tipRest: String?
    var icone: String?             // id nu du contrat (ex. "pill") → asset fluent_<id>

    var id: String { tipBold ?? tipRest ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case tipBold, tipRest, icone
    }
}

// MARK: - Plan (consommé à la vague V4)
struct PlanV2: Codable {
    var sections: [PlanSectionV2]?

    enum CodingKeys: String, CodingKey {
        case sections
    }
}

struct PlanSectionV2: Codable, Identifiable {
    /// "symptome" | "objectif" — String brut pour tolérer les valeurs futures.
    var type: String?
    var id: String?
    var titre: String?             // ≤30
    var causes: [PlanCauseV2]?     // ≤3
    var tipBold: String?
    var tipRest: String?
    var rituel: [RituelV2]?
    var solutions: SolutionsV2?

    enum CodingKeys: String, CodingKey {
        case type, id, titre, causes, tipBold, tipRest, rituel, solutions
    }
}

struct PlanCauseV2: Codable, Hashable {
    var label: String?             // ≤30
    var statut: StatutV2 = .neutre

    enum CodingKeys: String, CodingKey {
        case label, statut
    }
}

struct RituelV2: Codable, Identifiable {
    /// "matin" | "midi" | "soir"
    var moment: String?
    var actions: [String]?         // ≤2, chacune ≤30

    var id: String { moment ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case moment, actions
    }
}

struct SolutionsV2: Codable {
    var nutrition: [SolutionNutritionV2]?    // ≤3
    var habitudes: [SolutionHabitudeV2]?     // ≤2
    var complements: [SolutionComplementV2]? // ≤2

    enum CodingKeys: String, CodingKey {
        case nutrition, habitudes, complements
    }
}

struct SolutionNutritionV2: Codable, Identifiable {
    var aliment: String?
    var icone: String?             // id d'asset fluent_*
    var niveau2: String?
    var niveau3: String?

    var id: String { aliment ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case aliment, icone, niveau2, niveau3
    }
}

struct SolutionHabitudeV2: Codable, Identifiable {
    var tipBold: String?
    var tipRest: String?

    var id: String { tipBold ?? tipRest ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case tipBold, tipRest
    }
}

struct SolutionComplementV2: Codable, Identifiable {
    /// Pointe vers `ComplementV2.id`.
    var complementId: String?
    var phrase: String?

    var id: String { complementId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case complementId, phrase
    }
}

// MARK: - Compléments (consommés à la vague V4)
struct ComplementsV2: Codable {
    var insight: String?
    var complements: [ComplementV2]?

    enum CodingKeys: String, CodingKey {
        case insight, complements
    }
}

struct ComplementV2: Codable, Identifiable {
    var id: String?
    var nom: String?
    /// "essentiel" | "utile" — String brut (seule `statut` exige une enum).
    var badge: String?
    var momentPrise: String?
    var why: String?
    var formes: FormesV2?
    var interactions: [ComplementInteractionV2]?  // ≤2
    var alternativeAssiette: AlternativeAssietteV2?

    var isEssentiel: Bool { badge == "essentiel" }

    enum CodingKeys: String, CodingKey {
        case id, nom, badge, momentPrise, why, formes, interactions, alternativeAssiette
    }
}

struct FormesV2: Codable {
    var premium: FormeV2?
    var eco: FormeV2?

    enum CodingKeys: String, CodingKey {
        case premium, eco
    }
}

struct FormeV2: Codable {
    var forme: String?
    var dose: String?
    var prixMois: Int?
    var pourquoiMieux: String?     // renseigné côté premium uniquement

    enum CodingKeys: String, CodingKey {
        case forme, dose, prixMois, pourquoiMieux
    }
}

struct ComplementInteractionV2: Codable, Identifiable {
    var tipBold: String?
    var tipRest: String?
    var severite: String?

    var id: String { tipBold ?? tipRest ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case tipBold, tipRest, severite
    }
}

struct AlternativeAssietteV2: Codable {
    var resume: String?
    /// Pointe vers `PlanSectionV2.id`.
    var lienPlanSection: String?

    enum CodingKeys: String, CodingKey {
        case resume, lienPlanSection
    }
}

// MARK: - Meta
struct MetaV2: Codable {
    var schemaVersion: String?     // "v2.2"
    var promptVersion: String?
    var generatedAt: String?
    var model: String?
    var profileHash: String?
    var truncated: Bool?
    var structuredOutput: Bool?
    var complianceIssues: [String]?  // parfois omis par le serveur

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case promptVersion = "prompt_version"
        case generatedAt = "generated_at"
        case model
        case profileHash = "profile_hash"
        case truncated
        case structuredOutput = "structured_output"
        case complianceIssues = "compliance_issues"
    }
}

// MARK: - Helpers de décodage tolérant (copie locale — les helpers de
// AIAnalysis.swift sont `private` à leur fichier ; noms distincts pour
// éviter toute ambiguïté). `LossyDecodableArray` (internal) est réutilisé.
private extension KeyedDecodingContainer {
    /// Décodage indulgent : clé absente, valeur null OU type inattendu → nil.
    func v2Lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Tableau indulgent : les entrées malformées sont skippées une à une.
    func v2LenientArray<T: Decodable>(_ key: Key) -> [T]? {
        guard let lossy: LossyDecodableArray<T> = v2Lenient(key) else { return nil }
        return lossy.elements
    }

    /// Entier indulgent : accepte Int, Double (arrondi) ou String numérique.
    func v2LenientInt(_ key: Key) -> Int? {
        if let intValue: Int = v2Lenient(key) { return intValue }
        if let doubleValue: Double = v2Lenient(key) { return Int(doubleValue.rounded()) }
        if let stringValue: String = v2Lenient(key),
           let doubleValue = Double(stringValue.trimmingCharacters(in: .whitespaces)) {
            return Int(doubleValue.rounded())
        }
        return nil
    }
}

// MARK: - Décodage tolérant (init(from:) par type, en extension)

extension AIAnalysisV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contract = c.v2Lenient(.contract)
        score = c.v2LenientInt(.score)
        besoinsNourris = c.v2LenientInt(.besoinsNourris)
        bilan = c.v2Lenient(.bilan)
        plan = c.v2Lenient(.plan)
        complements = c.v2Lenient(.complements)
        meta = c.v2Lenient(.meta)
    }
}

extension BilanV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scoreInsight = c.v2Lenient(.scoreInsight)
        apportsInsight = c.v2Lenient(.apportsInsight)
        apports = c.v2LenientArray(.apports)
        symptomes = c.v2LenientArray(.symptomes)
        interactions = c.v2LenientArray(.interactions)
    }
}

extension ApportV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v2Lenient(.id)
        nom = c.v2Lenient(.nom)
        statut = c.v2Lenient(.statut) ?? .neutre
        pctBesoin = c.v2LenientInt(.pctBesoin)
        why = c.v2Lenient(.why)
        tipBold = c.v2Lenient(.tipBold)
        tipRest = c.v2Lenient(.tipRest)
        aliments = c.v2LenientArray(.aliments)
    }
}

extension AlimentV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nom = c.v2Lenient(.nom)
        icone = c.v2Lenient(.icone)
    }
}

extension SymptomeV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v2Lenient(.id)
        nom = c.v2Lenient(.nom)
        causes = c.v2LenientArray(.causes)
    }
}

extension InteractionV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tipBold = c.v2Lenient(.tipBold)
        tipRest = c.v2Lenient(.tipRest)
        icone = c.v2Lenient(.icone)
    }
}

extension PlanV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sections = c.v2LenientArray(.sections)
    }
}

extension PlanSectionV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.v2Lenient(.type)
        id = c.v2Lenient(.id)
        titre = c.v2Lenient(.titre)
        causes = c.v2LenientArray(.causes)
        tipBold = c.v2Lenient(.tipBold)
        tipRest = c.v2Lenient(.tipRest)
        rituel = c.v2LenientArray(.rituel)
        solutions = c.v2Lenient(.solutions)
    }
}

extension PlanCauseV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = c.v2Lenient(.label)
        statut = c.v2Lenient(.statut) ?? .neutre
    }
}

extension RituelV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moment = c.v2Lenient(.moment)
        actions = c.v2LenientArray(.actions)
    }
}

extension SolutionsV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nutrition = c.v2LenientArray(.nutrition)
        habitudes = c.v2LenientArray(.habitudes)
        complements = c.v2LenientArray(.complements)
    }
}

extension SolutionNutritionV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aliment = c.v2Lenient(.aliment)
        icone = c.v2Lenient(.icone)
        niveau2 = c.v2Lenient(.niveau2)
        niveau3 = c.v2Lenient(.niveau3)
    }
}

extension SolutionHabitudeV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tipBold = c.v2Lenient(.tipBold)
        tipRest = c.v2Lenient(.tipRest)
    }
}

extension SolutionComplementV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        complementId = c.v2Lenient(.complementId)
        phrase = c.v2Lenient(.phrase)
    }
}

extension ComplementsV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        insight = c.v2Lenient(.insight)
        complements = c.v2LenientArray(.complements)
    }
}

extension ComplementV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v2Lenient(.id)
        nom = c.v2Lenient(.nom)
        badge = c.v2Lenient(.badge)
        momentPrise = c.v2Lenient(.momentPrise)
        why = c.v2Lenient(.why)
        formes = c.v2Lenient(.formes)
        interactions = c.v2LenientArray(.interactions)
        alternativeAssiette = c.v2Lenient(.alternativeAssiette)
    }
}

extension FormesV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        premium = c.v2Lenient(.premium)
        eco = c.v2Lenient(.eco)
    }
}

extension FormeV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        forme = c.v2Lenient(.forme)
        dose = c.v2Lenient(.dose)
        prixMois = c.v2LenientInt(.prixMois)
        pourquoiMieux = c.v2Lenient(.pourquoiMieux)
    }
}

extension ComplementInteractionV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tipBold = c.v2Lenient(.tipBold)
        tipRest = c.v2Lenient(.tipRest)
        severite = c.v2Lenient(.severite)
    }
}

extension AlternativeAssietteV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resume = c.v2Lenient(.resume)
        lienPlanSection = c.v2Lenient(.lienPlanSection)
    }
}

extension MetaV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.v2Lenient(.schemaVersion)
        promptVersion = c.v2Lenient(.promptVersion)
        generatedAt = c.v2Lenient(.generatedAt)
        model = c.v2Lenient(.model)
        profileHash = c.v2Lenient(.profileHash)
        truncated = c.v2Lenient(.truncated)
        structuredOutput = c.v2Lenient(.structuredOutput)
        complianceIssues = c.v2LenientArray(.complianceIssues)
    }
}
