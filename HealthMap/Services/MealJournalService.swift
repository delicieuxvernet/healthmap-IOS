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
    /// `micros` (format partagé avec le web : `[{id, unit, amount, pctRDA}]` —
    /// iOS n'écrit et ne lit que `id` + `pctRDA`, les clés en trop sont ignorées).
    struct MicroPct: Codable, Equatable {
        let id: String
        let pctRDA: Int

        init(id: String, pctRDA: Int) {
            self.id = id
            self.pctRDA = pctRDA
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
        }
    }

    /// Un repas du journal, prêt pour l'UI.
    struct MealRecord: Identifiable, Equatable {
        let id: String
        let consumedAt: Date
        let slot: MealSlot
        let foods: [String]
        let macros: MealMacros
        /// Vide pour les repas antérieurs à la persistance des micros
        /// (scans d'avant juillet 2026, ajouts manuels, lignes web).
        var micros: [MicroPct] = []
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
        // `detected_foods` a DEUX formes en base :
        //   • tableau de chaînes         → ajouts manuels + lignes web/legacy
        //   • tableau d'objets {name_fr…}→ scans photo (fonction Edge, depuis v5)
        // On extrait le nom dans les deux cas. AVANT ce fix, le type `[String]`
        // faisait ÉCHOUER le décodage de TOUTE la page dès qu'un scan photo
        // (objet) était présent → `loadRange` levait, `journal.load()` avalait
        // l'erreur, et le journal apparaissait VIDE partout (score hebdo, « Ta
        // journée », Suivi, Plan tous à 0). C'était la vraie cause racine.
        struct FlexibleFoodName: Decodable {
            let name: String
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) {
                    name = s
                } else {
                    struct Obj: Decodable { let name_fr: String? }
                    name = ((try? c.decode(Obj.self))?.name_fr) ?? ""
                }
            }
        }
        struct RemoteRow: Decodable {
            let id: String
            let consumedAt: String
            let mealType: String?
            let detectedFoods: [FlexibleFoodName]?
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
            let names = (r.detectedFoods ?? []).map(\.name).filter { !$0.isEmpty }
            return MealRecord(id: r.id,
                              consumedAt: date,
                              slot: slot,
                              foods: names,
                              macros: r.macros ?? MealMacros(),
                              micros: r.micros ?? [])
        }
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
