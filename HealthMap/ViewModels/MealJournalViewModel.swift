import Foundation

/// Journal alimentaire du jour : charge les repas, calcule les totaux,
/// gère l'ajout manuel et la suppression. Lecture/écriture via
/// `MealJournalService` (table `meal_scans`).
@MainActor
final class MealJournalViewModel: ObservableObject {
    @Published var meals: [MealJournalService.MealRecord] = []
    /// 14 derniers jours (semaine courante + précédente) — nourrit le score
    /// de la semaine du Bilan (WeekScoreEngine). `meals` en reste le sous-
    /// ensemble « aujourd'hui », dérivé de la même requête.
    @Published var fortnight: [MealJournalService.MealRecord] = []
    @Published var isLoading = false

    private let service = MealJournalService.shared

    // MARK: - Chargement

    func load() async {
        guard let userId = AuthService.shared.cachedCurrentUserIdString else {
            meals = []
            fortnight = []
            return
        }
        isLoading = true
        do {
            let week = WeekScoreEngine.currentWeekInterval(containing: Date())
            let from = Calendar.current.date(byAdding: .day, value: -7, to: week.start) ?? week.start
            let all = try await service.loadRange(userId: userId, from: from, to: week.end)
            fortnight = all
            meals = all.filter { Calendar.current.isDateInToday($0.consumedAt) }
        } catch {
            AppLogger.database.warning("Journal load failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }

    // MARK: - Mutations

    func addManual(name: String, calories: Int, slot: MealJournalService.MealSlot) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let userId = AuthService.shared.cachedCurrentUserIdString else { return }
        do {
            try await service.insertManual(userId: userId, name: trimmed, calories: max(0, calories), slot: slot)
            await load()
        } catch {
            AppLogger.database.warning("Journal add failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func delete(_ meal: MealJournalService.MealRecord) async {
        do {
            try await service.softDelete(id: meal.id)
            meals.removeAll { $0.id == meal.id }
            fortnight.removeAll { $0.id == meal.id }
        } catch {
            AppLogger.database.warning("Journal delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Totaux du jour

    var totalCalories: Int { meals.reduce(0) { $0 + $1.macros.calories } }
    var totalProteins: Double { meals.reduce(0) { $0 + $1.macros.proteins } }
    var totalCarbs: Double { meals.reduce(0) { $0 + $1.macros.carbs } }
    var totalFats: Double { meals.reduce(0) { $0 + $1.macros.fats } }
    var totalFiber: Double { meals.reduce(0) { $0 + $1.macros.fiber } }

    // MARK: - Par créneau

    func meals(in slot: MealJournalService.MealSlot) -> [MealJournalService.MealRecord] {
        meals.filter { $0.slot == slot }
    }

    func calories(in slot: MealJournalService.MealSlot) -> Int {
        meals(in: slot).reduce(0) { $0 + $1.macros.calories }
    }
}
