import Foundation
import Supabase

/// Accès au journal alimentaire du jour — table `meal_scans` (partagée web↔iOS).
/// RLS : l'utilisateur lit / écrit / édite UNIQUEMENT ses propres repas
/// (`user_id = current_user_id()` = `profiles.id`). On passe donc l'id de profil
/// résolu (`AuthService.cachedCurrentUserIdString`).
final class MealJournalService {
    static let shared = MealJournalService()
    private init() {}

    private var client: SupabaseClient { SupabaseService.shared.client }

    // MARK: - Types

    /// Macros d'un repas, stockées dans la colonne jsonb `macros`.
    struct MealMacros: Codable, Equatable {
        var calories: Int = 0
        var proteins: Double = 0
        var carbs: Double = 0
        var fats: Double = 0
        var fiber: Double = 0

        init(calories: Int = 0, proteins: Double = 0, carbs: Double = 0,
             fats: Double = 0, fiber: Double = 0) {
            self.calories = calories
            self.proteins = proteins
            self.carbs = carbs
            self.fats = fats
            self.fiber = fiber
        }

        // Web/Edge peuvent écrire des décimaux ou omettre une clé (ex. fiber) —
        // décodage tolérant, aligné sur `MicroPct`. AVANT : une seule clé
        // manquante faisait échouer TOUT le décodage → macros silencieusement
        // remises à zéro par le `?? MealMacros()` de l'appelant.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let i = try? c.decode(Int.self, forKey: .calories) {
                calories = i
            } else {
                calories = Int(((try? c.decode(Double.self, forKey: .calories)) ?? 0).rounded())
            }
            proteins = (try? c.decode(Double.self, forKey: .proteins)) ?? 0
            carbs = (try? c.decode(Double.self, forKey: .carbs)) ?? 0
            fats = (try? c.decode(Double.self, forKey: .fats)) ?? 0
            fiber = (try? c.decode(Double.self, forKey: .fiber)) ?? 0
        }
    }

    /// Créneau du repas (colonne `meal_type`).
    enum MealSlot: String, Codable, CaseIterable {
        case breakfast, lunch, dinner, snack

        var label: String {
            switch self {
            case .breakfast: return "Matin"
            case .lunch:     return "Midi"
            case .dinner:    return "Soir"
            case .snack:     return "Encas"
            }
        }
        var emoji: String {
            switch self {
            case .breakfast: return "☀️"
            case .lunch:     return "🍽️"
            case .dinner:    return "🌙"
            case .snack:     return "🍎"
            }
        }
        /// Créneau déduit de l'heure (pour un scan ajouté automatiquement).
        static func from(date: Date, calendar: Calendar = .current) -> MealSlot {
            switch calendar.component(.hour, from: date) {
            case 5..<11:  return .breakfast
            case 11..<15: return .lunch
            case 15..<18: return .snack
            default:      return .dinner
            }
        }
    }

    /// Apport d'un repas à UN nutriment, persisté dans la colonne jsonb
    /// `micros` (format Edge/web : `[{id, amount, unit, pctRDA}]`).
    /// `amount`/`unit` sont CONSERVÉS quand ils existent : le backend
    /// `day_summary` (compteur calories) somme les `amount` — les perdre à la
    /// réécriture mettrait la contribution du repas à zéro (revue P1).
    struct MicroPct: Codable, Equatable {
        let id: String
        let pctRDA: Int
        /// Quantité absolue (µg/mg/g selon le nutriment) — écrite par l'Edge,
        /// recalculée à la réécriture (pct/100 × RDA canonique, miroir Edge).
        let amount: Double?
        let unit: String?

        init(id: String, pctRDA: Int, amount: Double? = nil, unit: String? = nil) {
            self.id = id
            self.pctRDA = pctRDA
            self.amount = amount
            self.unit = unit
        }

        // `pctRDA` peut arriver en décimal selon la source (web) — on arrondit.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            if let i = try? c.decode(Int.self, forKey: .pctRDA) {
                pctRDA = i
            } else {
                pctRDA = Int(((try? c.decode(Double.self, forKey: .pctRDA)) ?? 0).rounded())
            }
            amount = try? c.decode(Double.self, forKey: .amount)
            unit = try? c.decode(String.self, forKey: .unit)
        }
    }

    /// Un aliment d'un repas, tel que persisté dans la colonne jsonb
    /// `detected_foods`. DEUX formes coexistent en base :
    ///   • chaîne nue `"Poulet rôti"`            → ajouts manuels, lignes web/legacy
    ///   • objet `{name_fr, portion_g, macros, micros, …}` → scans photo (Edge ≥ v5)
    /// Décodage tolérant aux deux. À la RÉÉCRITURE, un item objet est réémis
    /// depuis son JSON BRUT (`raw`) : les clés que l'Edge écrit et que le web
    /// lit (`ciqual_code`, `confidence`, `nova_class`, `match_similarity`,
    /// `micros[].amount/.unit`…) sont conservées telles quelles (revue P1 :
    /// les perdre cassait le re-score web et le compteur `day_summary`).
    struct FoodEntry: Codable, Equatable {
        let name: String
        /// Portion en grammes — base du futur re-scaling de quantité.
        let portionG: Double?
        /// Macros de CET aliment (pas du repas). nil = détail indisponible.
        let macros: MealMacros?
        let micros: [MicroPct]?
        /// JSON brut de l'item objet (passthrough intégral à la réécriture).
        /// nil pour la forme chaîne nue et les items construits par iOS.
        let raw: [String: AnyJSON]?

        init(name: String, portionG: Double? = nil,
             macros: MealMacros? = nil, micros: [MicroPct]? = nil,
             raw: [String: AnyJSON]? = nil) {
            self.name = name
            self.portionG = portionG
            self.macros = macros
            self.micros = micros
            self.raw = raw
        }

        private enum CodingKeys: String, CodingKey {
            case nameFr = "name_fr"
            case name
            case portionG = "portion_g"
            case macros, micros
        }

        init(from decoder: Decoder) throws {
            if let s = try? decoder.singleValueContainer().decode(String.self) {
                name = s
                portionG = nil
                macros = nil
                micros = nil
                raw = nil
                return
            }
            // Élément inattendu (null, nombre…) → entrée vide, FILTRÉE en
            // aval — ne JAMAIS lever : une seule entrée corrompue viderait
            // tout le journal (incident historique du décodage strict).
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
                name = ""
                portionG = nil
                macros = nil
                micros = nil
                raw = nil
                return
            }
            name = (try? c.decode(String.self, forKey: .nameFr))
                ?? (try? c.decode(String.self, forKey: .name))
                ?? ""
            portionG = try? c.decode(Double.self, forKey: .portionG)
            macros = try? c.decode(MealMacros.self, forKey: .macros)
            micros = try? c.decode([MicroPct].self, forKey: .micros)
            raw = try? decoder.singleValueContainer().decode([String: AnyJSON].self)
        }

        func encode(to encoder: Encoder) throws {
            // Passthrough : l'item d'origine repart tel quel (nom garanti).
            if var dict = raw {
                dict["name_fr"] = .string(name)
                var c = encoder.singleValueContainer()
                try c.encode(dict)
                return
            }
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .nameFr)
            try c.encodeIfPresent(portionG, forKey: .portionG)
            try c.encodeIfPresent(macros, forKey: .macros)
            try c.encodeIfPresent(micros, forKey: .micros)
        }
    }

    /// Un repas du journal, prêt pour l'UI.
    struct MealRecord: Identifiable, Equatable {
        let id: String
        let consumedAt: Date
        let slot: MealSlot
        /// Aliments du repas — riches (portion/macros/micros) pour les scans
        /// photo Edge ≥ v5 et les écritures iOS récentes, nom seul sinon.
        let items: [FoodEntry]
        let macros: MealMacros
        /// Vide pour les repas antérieurs à la persistance des micros
        /// (scans d'avant juillet 2026, ajouts manuels, lignes web).
        var micros: [MicroPct] = []

        /// Noms seuls — compat call-sites historiques (listes, titres, tests).
        var foods: [String] { items.map(\.name).filter { !$0.isEmpty } }

        /// Détail PAR aliment exploitable ? (chaque item porte ses macros —
        /// condition pour supprimer/éditer par aliment ; sinon les opérations
        /// restent au niveau du repas entier.)
        var hasItemDetail: Bool {
            !items.isEmpty && items.allSatisfy { $0.macros != nil }
        }

        init(id: String, consumedAt: Date, slot: MealSlot,
             items: [FoodEntry], macros: MealMacros, micros: [MicroPct] = []) {
            self.id = id
            self.consumedAt = consumedAt
            self.slot = slot
            self.items = items
            self.macros = macros
            self.micros = micros
        }

        /// Compat : construction par noms seuls (ajouts manuels, tests).
        init(id: String, consumedAt: Date, slot: MealSlot,
             foods: [String], macros: MealMacros, micros: [MicroPct] = []) {
            self.init(id: id, consumedAt: consumedAt, slot: slot,
                      items: foods.map { FoodEntry(name: $0) },
                      macros: macros, micros: micros)
        }
    }

    // MARK: - Insert (un scan ou un ajout manuel rejoint la journée)

    func insertScan(userId: String,
                    foods: [String],
                    macros: MealMacros,
                    slot: MealSlot,
                    micros: [MicroPct] = [],
                    consumedAt: Date = Date()) async throws {
        struct InsertRow: Encodable {
            let userId: String
            let consumedAt: String
            let mealType: String
            let detectedFoods: [String]
            let macros: MealMacros
            let micros: [MicroPct]
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case consumedAt = "consumed_at"
                case mealType = "meal_type"
                case detectedFoods = "detected_foods"
                case macros, micros
            }
        }
        let row = InsertRow(
            userId: userId,
            consumedAt: Self.iso.string(from: consumedAt),
            mealType: slot.rawValue,
            detectedFoods: foods,
            macros: macros,
            micros: micros
        )
        try await client.from("meal_scans").insert(row).execute()
    }

    func insertManual(userId: String,
                      name: String,
                      calories: Int,
                      slot: MealSlot,
                      consumedAt: Date = Date()) async throws {
        try await insertScan(userId: userId,
                             foods: [name],
                             macros: MealMacros(calories: calories),
                             slot: slot,
                             consumedAt: consumedAt)
    }

    // MARK: - Lecture des repas (jour ou plage)

    func loadDay(userId: String, day: Date = Date(), calendar: Calendar = .current) async throws -> [MealRecord] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return try await loadRange(userId: userId, from: start, to: end, calendar: calendar)
    }

    /// Repas d'une plage `[from, to)` — nourrit le score de la semaine (14
    /// derniers jours : semaine courante + précédente pour la comparaison).
    func loadRange(userId: String, from: Date, to: Date, calendar: Calendar = .current) async throws -> [MealRecord] {
        // `detected_foods` a DEUX formes en base (voir `FoodEntry`) : chaînes
        // nues (manuel/web/legacy) ou objets riches (scans photo Edge ≥ v5).
        // `FoodEntry` décode les deux — et conserve portion/macros/micros des
        // objets riches (lignes par aliment du journal). Historique : un type
        // strict `[String]` faisait ÉCHOUER le décodage de TOUTE la page dès
        // qu'un scan photo (objet) était présent → journal VIDE partout (score
        // hebdo, « Ta journée », Suivi, Plan à 0). Rester tolérant, toujours.
        struct RemoteRow: Decodable {
            let id: String
            let consumedAt: String
            let mealType: String?
            let detectedFoods: [FoodEntry]?
            let macros: MealMacros?
            let micros: [MicroPct]?
            enum CodingKeys: String, CodingKey {
                case id
                case consumedAt = "consumed_at"
                case mealType = "meal_type"
                case detectedFoods = "detected_foods"
                case macros, micros
            }
        }

        // `deleted_at IS NULL` : sans ce filtre les repas supprimés (soft
        // delete) réapparaissaient au rechargement suivant du journal.
        let rows: [RemoteRow] = try await client
            .from("meal_scans")
            .select("id, consumed_at, meal_type, detected_foods, macros, micros")
            .eq("user_id", value: userId)
            .is("deleted_at", value: nil)
            .gte("consumed_at", value: Self.iso.string(from: from))
            .lt("consumed_at", value: Self.iso.string(from: to))
            .order("consumed_at", ascending: true)
            .execute()
            .value

        return rows.map { r in
            let date = Self.parseTimestamp(r.consumedAt) ?? from
            let slot = MealSlot(rawValue: r.mealType ?? "") ?? MealSlot.from(date: date, calendar: calendar)
            let items = (r.detectedFoods ?? []).filter { !$0.name.isEmpty }
            return MealRecord(id: r.id,
                              consumedAt: date,
                              slot: slot,
                              items: items,
                              macros: r.macros ?? MealMacros(),
                              micros: r.micros ?? [])
        }
    }

    // MARK: - Édition par aliment (suppression d'un item)

    /// RDA canoniques — MIROIR EXACT de la table `RDA` de l'Edge
    /// `analyze-meal-photo/index.ts` (sert à dériver `amount` depuis le
    /// pctRDA). Ne JAMAIS modifier sans changer l'Edge en même temps.
    static let canonRDA: [String: Double] = [
        "vitD": 15, "vitB12": 2.4, "iron": 18, "magnesium": 400, "omega3": 1.6,
        "vitC": 90, "calcium": 1000, "zinc": 11, "iodine": 150, "fiber": 30,
    ]

    /// Agrégats du repas RECOMPOSÉS depuis ses items — miroir exact de
    /// l'Edge (`buildMealFromVision`) : macros = Σ items (arrondi 0,1 g) ;
    /// micros par id = min(100, Σ pct des items) dans l'ordre de première
    /// apparition, `amount = round2(pct/100 × RDA)`, `unit = ""` (contrat
    /// Edge, consommé par `day_summary`). ⚠️ NE PAS soustraire ligne − item :
    /// le plafond à 100 rend la soustraction fausse (revue P1 : deux items à
    /// 80 % → ligne 100 ; en retirer un doit laisser 80, pas 20).
    /// Pure — testable sans I/O.
    static func aggregatesFromItems(_ items: [FoodEntry]) -> (macros: MealMacros, micros: [MicroPct]) {
        func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
        var m = MealMacros()
        for it in items {
            guard let im = it.macros else { continue }
            m.calories += im.calories
            m.proteins += im.proteins
            m.carbs += im.carbs
            m.fats += im.fats
            m.fiber += im.fiber
        }
        m.proteins = round1(m.proteins)
        m.carbs = round1(m.carbs)
        m.fats = round1(m.fats)
        m.fiber = round1(m.fiber)

        var order: [String] = []
        var sums: [String: Int] = [:]
        for it in items {
            for mp in it.micros ?? [] {
                if sums[mp.id] == nil { order.append(mp.id) }
                sums[mp.id, default: 0] += mp.pctRDA
            }
        }
        let micros = order.map { id -> MicroPct in
            let pct = max(0, min(100, sums[id] ?? 0))
            let amount = Self.canonRDA[id].map { (Double(pct) / 100 * $0 * 100).rounded() / 100 }
            return MicroPct(id: id, pctRDA: pct, amount: amount, unit: amount != nil ? "" : nil)
        }
        return (m, micros)
    }

    /// Supprime UN aliment d'un repas. La ligne est RELUE d'abord (état
    /// autoritatif) et l'item retiré par VALEUR — jamais par index sur un
    /// snapshot UI potentiellement périmé (revue P1 : deux suppressions
    /// rapprochées ressuscitaient l'aliment déjà retiré). Les agrégats
    /// `macros`/`micros` sont recomposés depuis les items restants (le Bilan
    /// hebdo et `day_summary` lisent ces colonnes). Dernier aliment réel →
    /// soft delete du repas. Retourne `false` si l'item n'existe plus dans la
    /// ligne fraîche ou si la recomposition serait malhonnête (item restant
    /// sans macros) — l'appelant recharge et n'écrit rien.
    func deleteItem(recordId: String, item: FoodEntry) async throws -> Bool {
        struct FreshRow: Decodable {
            let detectedFoods: [FoodEntry]?
            enum CodingKeys: String, CodingKey {
                case detectedFoods = "detected_foods"
            }
        }
        let fresh: [FreshRow] = try await client
            .from("meal_scans")
            .select("detected_foods")
            .eq("id", value: recordId)
            .is("deleted_at", value: nil)
            .execute()
            .value
        guard let row = fresh.first else { return false }

        // Les items « fantômes » (nom vide) sont évacués à la réécriture :
        // ils n'ont aucune ligne UI, les garder rendrait les agrégats
        // recomposés ≠ somme des lignes visibles.
        var items = (row.detectedFoods ?? []).filter { !$0.name.isEmpty }
        guard let idx = items.firstIndex(of: item) else { return false }
        items.remove(at: idx)

        if items.isEmpty {
            try await softDelete(id: recordId)
            return true
        }
        guard items.allSatisfy({ $0.macros != nil }) else { return false }

        let (m, mm) = Self.aggregatesFromItems(items)
        struct UpdateRow: Encodable {
            let detectedFoods: [FoodEntry]
            let macros: MealMacros
            let micros: [MicroPct]
            enum CodingKeys: String, CodingKey {
                case detectedFoods = "detected_foods"
                case macros, micros
            }
        }
        try await client
            .from("meal_scans")
            .update(UpdateRow(detectedFoods: items, macros: m, micros: mm))
            .eq("id", value: recordId)
            .execute()
        return true
    }

    // MARK: - Suppression douce (deleted_at)

    func softDelete(id: String) async throws {
        struct DelRow: Encodable {
            let deletedAt: String
            enum CodingKeys: String, CodingKey { case deletedAt = "deleted_at" }
        }
        try await client
            .from("meal_scans")
            .update(DelRow(deletedAt: Self.iso.string(from: Date())))
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Helpers

    private static let iso = ISO8601DateFormatter()

    /// `consumed_at` peut arriver avec ou sans fraction de seconde selon la source.
    private static func parseTimestamp(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
