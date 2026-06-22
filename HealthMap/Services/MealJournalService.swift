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

    /// Un repas du journal, prêt pour l'UI.
    struct MealRecord: Identifiable, Equatable {
        let id: String
        let consumedAt: Date
        let slot: MealSlot
        let foods: [String]
        let macros: MealMacros
    }

    // MARK: - Insert (un scan ou un ajout manuel rejoint la journée)

    func insertScan(userId: String,
                    foods: [String],
                    macros: MealMacros,
                    slot: MealSlot,
                    consumedAt: Date = Date()) async throws {
        struct InsertRow: Encodable {
            let userId: String
            let consumedAt: String
            let mealType: String
            let detectedFoods: [String]
            let macros: MealMacros
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case consumedAt = "consumed_at"
                case mealType = "meal_type"
                case detectedFoods = "detected_foods"
                case macros
            }
        }
        let row = InsertRow(
            userId: userId,
            consumedAt: Self.iso.string(from: consumedAt),
            mealType: slot.rawValue,
            detectedFoods: foods,
            macros: macros
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

    // MARK: - Lecture des repas d'un jour

    func loadDay(userId: String, day: Date = Date(), calendar: Calendar = .current) async throws -> [MealRecord] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        struct RemoteRow: Decodable {
            let id: String
            let consumedAt: String
            let mealType: String?
            let detectedFoods: [String]?
            let macros: MealMacros?
            enum CodingKeys: String, CodingKey {
                case id
                case consumedAt = "consumed_at"
                case mealType = "meal_type"
                case detectedFoods = "detected_foods"
                case macros
            }
        }

        let rows: [RemoteRow] = try await client
            .from("meal_scans")
            .select("id, consumed_at, meal_type, detected_foods, macros")
            .eq("user_id", value: userId)
            .gte("consumed_at", value: Self.iso.string(from: start))
            .lt("consumed_at", value: Self.iso.string(from: end))
            .order("consumed_at", ascending: true)
            .execute()
            .value

        return rows.map { r in
            let date = Self.parseTimestamp(r.consumedAt) ?? start
            let slot = MealSlot(rawValue: r.mealType ?? "") ?? MealSlot.from(date: date, calendar: calendar)
            return MealRecord(id: r.id,
                              consumedAt: date,
                              slot: slot,
                              foods: r.detectedFoods ?? [],
                              macros: r.macros ?? MealMacros())
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
