import Foundation

// MARK: - Scan v2 (contrat "v2" — analyze-meal-photo, opt-in body.contract = "v2")
//
// Bloc `scan_v2` renvoyé EN PLUS de la réponse existante par la fonction
// analyze-meal-photo (version 10) quand le client envoie `"contract": "v2"`.
// Le cache d'idempotence renvoie aussi ce bloc (self-healing). L'écran scan
// validé continue de se nourrir de la réponse historique — `scan_v2` ne fait
// qu'enrichir, il n'est jamais requis.
//
// ⚠️ DÉCODAGE TOLÉRANT (même doctrine que AIAnalysisV2.swift) : chaque champ
// est décodé indépendamment via les extensions en bas de fichier — un champ
// malformé → nil, une entrée de tableau malformée → skippée
// (LossyDecodableArray, réutilisé de AIAnalysis.swift). Un bloc `scan_v2`
// illisible ne fait JAMAIS échouer le décodage de la réponse de scan
// complète. Les inits custom vivent en EXTENSION pour préserver les inits
// memberwise (mocks de tests, prévisualisations).
//
// `StatutV2` (AIAnalysisV2.swift) est RÉUTILISÉ pour `statut` et `impact` :
// valeur inconnue/absente → `.neutre`, mapping couleur déjà en place.
// `AlimentV2` ({nom, icone}) est réutilisé pour `alimentsComplement`.
struct ScanV2: Codable {
    var plat: PlatV2?
    var couverture: CouvertureV2?
    var besoins: [BesoinScanV2]?       // ≤3 apports ciblés de l'utilisateur
    var aliments: [AlimentScanV2]?     // aliments détectés dans le plat
    var manques: [ManqueV2]?           // ≤2 suggestions de complément
    var courbeInsight: String?         // ≤90 caractères
    var meta: ScanV2Meta?

    enum CodingKeys: String, CodingKey {
        case plat, couverture, besoins, aliments, manques, courbeInsight, meta
    }

    /// Validation minimale : le bloc est exploitable si le plat ou au moins
    /// un besoin est présent.
    var hasContent: Bool {
        plat != nil || besoins?.isEmpty == false
    }
}

// MARK: - Plat
struct PlatV2: Codable {
    var nom: String?
    var description: String?
    var kcal: Int?
    var macros: PlatMacrosV2?

    enum CodingKeys: String, CodingKey {
        case nom, description, kcal, macros
    }
}

/// Macros du plat entier, en grammes.
struct PlatMacrosV2: Codable {
    var proteines: Int?
    var glucides: Int?
    var lipides: Int?

    enum CodingKeys: String, CodingKey {
        case proteines, glucides, lipides
    }
}

// MARK: - Couverture
struct CouvertureV2: Codable {
    /// Nombre d'apports à renforcer que ce repas fait avancer.
    var nbRenforces: Int?
    /// Nombre total de besoins suivis pour l'utilisateur.
    var totalBesoins: Int?
    var insight: String?               // ≤90 caractères

    enum CodingKeys: String, CodingKey {
        case nbRenforces, totalBesoins, insight
    }
}

// MARK: - Besoin (apport ciblé de l'utilisateur, vu par ce repas)
struct BesoinScanV2: Codable, Identifiable {
    var id: String?                    // id de nutriment (ex. "iron")
    var nom: String?                   // ex. "Fer"
    var pctApporte: Int?               // % du besoin apporté par ce repas (0-100)
    var statut: StatutV2 = .neutre     // couvre | a_renforcer | a_combler
    var why: String?
    /// Aliments qui complèteraient cet apport — réutilise `AlimentV2`
    /// ({nom, icone}) : icône = id NU du contrat (ex. "fish") → asset
    /// `fluent_<id>`, résolu par `SafeFluent3DIcon`.
    var alimentsComplement: [AlimentV2]?

    enum CodingKeys: String, CodingKey {
        case id, nom, pctApporte, statut, why, alimentsComplement
    }
}

// MARK: - Aliment détecté dans le plat
struct AlimentScanV2: Codable, Identifiable {
    var nom: String?
    var icone: String?                 // id NU du contrat (ex. "fish") → asset fluent_<id>
    /// Contrat : "couvre" | "neutre" — décodé via `StatutV2` (inconnu → .neutre).
    var impact: StatutV2 = .neutre
    /// Ids d'apports que cet aliment fait avancer (ex. ["iron"]) —
    /// pointent vers `BesoinScanV2.id`.
    var besoinsAides: [String]?

    var id: String { nom ?? icone ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case nom, icone, impact, besoinsAides
    }
}

// MARK: - Manque (suggestion pour compléter le repas)
struct ManqueV2: Codable, Identifiable {
    var suggestion: String?            // ≤90 caractères
    var apportId: String?              // pointe vers BesoinScanV2.id
    var icone: String?                 // id NU du contrat → asset fluent_<id>

    var id: String { apportId ?? suggestion ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case suggestion, apportId, icone
    }
}

// MARK: - Meta
struct ScanV2Meta: Codable {
    var schemaVersion: String?         // "scan-v2.0"
    var promptVersion: String?
    var redacted: Bool?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case promptVersion = "prompt_version"
        case redacted
    }
}

// MARK: - Helpers de décodage tolérant (copie locale — les helpers de
// AIAnalysis.swift et AIAnalysisV2.swift sont `private` à leur fichier ;
// noms distincts pour éviter toute ambiguïté). `LossyDecodableArray`
// (internal, AIAnalysis.swift) est réutilisé.
private extension KeyedDecodingContainer {
    /// Décodage indulgent : clé absente, valeur null OU type inattendu → nil.
    func scanLenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Tableau indulgent : les entrées malformées sont skippées une à une.
    func scanLenientArray<T: Decodable>(_ key: Key) -> [T]? {
        guard let lossy: LossyDecodableArray<T> = scanLenient(key) else { return nil }
        return lossy.elements
    }

    /// Entier indulgent : accepte Int, Double (arrondi) ou String numérique.
    func scanLenientInt(_ key: Key) -> Int? {
        if let intValue: Int = scanLenient(key) { return intValue }
        if let doubleValue: Double = scanLenient(key) { return Int(doubleValue.rounded()) }
        if let stringValue: String = scanLenient(key),
           let doubleValue = Double(stringValue.trimmingCharacters(in: .whitespaces)) {
            return Int(doubleValue.rounded())
        }
        return nil
    }
}

// MARK: - Décodage tolérant (init(from:) par type, en extension)

extension ScanV2 {
    init(from decoder: Decoder) throws {
        // Tolérance maximale au niveau racine : si `scan_v2` n'est pas un
        // objet JSON (serveur dégradé), on rend un bloc vide plutôt que de
        // faire échouer le décodage de la réponse de scan entière.
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        plat = c.scanLenient(.plat)
        couverture = c.scanLenient(.couverture)
        besoins = c.scanLenientArray(.besoins)
        aliments = c.scanLenientArray(.aliments)
        manques = c.scanLenientArray(.manques)
        courbeInsight = c.scanLenient(.courbeInsight)
        meta = c.scanLenient(.meta)
    }
}

extension PlatV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nom = c.scanLenient(.nom)
        description = c.scanLenient(.description)
        kcal = c.scanLenientInt(.kcal)
        macros = c.scanLenient(.macros)
    }
}

extension PlatMacrosV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proteines = c.scanLenientInt(.proteines)
        glucides = c.scanLenientInt(.glucides)
        lipides = c.scanLenientInt(.lipides)
    }
}

extension CouvertureV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nbRenforces = c.scanLenientInt(.nbRenforces)
        totalBesoins = c.scanLenientInt(.totalBesoins)
        insight = c.scanLenient(.insight)
    }
}

extension BesoinScanV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.scanLenient(.id)
        nom = c.scanLenient(.nom)
        pctApporte = c.scanLenientInt(.pctApporte)
        statut = c.scanLenient(.statut) ?? .neutre
        why = c.scanLenient(.why)
        alimentsComplement = c.scanLenientArray(.alimentsComplement)
    }
}

extension AlimentScanV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nom = c.scanLenient(.nom)
        icone = c.scanLenient(.icone)
        impact = c.scanLenient(.impact) ?? .neutre
        besoinsAides = c.scanLenientArray(.besoinsAides)
    }
}

extension ManqueV2 {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suggestion = c.scanLenient(.suggestion)
        apportId = c.scanLenient(.apportId)
        icone = c.scanLenient(.icone)
    }
}

extension ScanV2Meta {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.scanLenient(.schemaVersion)
        promptVersion = c.scanLenient(.promptVersion)
        redacted = c.scanLenient(.redacted)
    }
}
