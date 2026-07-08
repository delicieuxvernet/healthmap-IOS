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

    /// Jour affiché par la page d'accueil Scan (jauge kcal / apports / macros /
    /// récents / dernier plat). Toujours borné à la fenêtre `fortnight` réellement
    /// chargée (≈ 2 semaines … aujourd'hui). Le SCAN, lui, agit toujours sur
    /// aujourd'hui — cette navigation ne concerne QUE l'affichage du journal.
    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date())

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

    // MARK: - Jour sélectionné (page d'accueil Scan)

    /// Repas du jour sélectionné : sous-ensemble de `fortnight`, trié
    /// chronologiquement. Recalculé à chaque accès → suit `selectedDay` et tout
    /// rechargement de `fortnight` (ex. après un scan).
    var dayMeals: [MealJournalService.MealRecord] {
        fortnight
            .filter { Calendar.current.isDate($0.consumedAt, inSameDayAs: selectedDay) }
            .sorted { $0.consumedAt < $1.consumedAt }
    }

    // MARK: - Totaux du jour sélectionné

    var dayCalories: Int { dayMeals.reduce(0) { $0 + $1.macros.calories } }
    var dayProteins: Double { dayMeals.reduce(0) { $0 + $1.macros.proteins } }
    var dayCarbs: Double { dayMeals.reduce(0) { $0 + $1.macros.carbs } }
    var dayFats: Double { dayMeals.reduce(0) { $0 + $1.macros.fats } }
    var dayFiber: Double { dayMeals.reduce(0) { $0 + $1.macros.fiber } }

    /// Part du besoin couverte aujourd'hui pour un micronutriment : somme des
    /// `pctRDA` des repas du jour portant cet id, plafonnée à 100 (formule
    /// canonique, alignée sur WeekScoreEngine / SuiviEngineV4).
    func dayMicroPct(_ id: String) -> Int {
        let sum = dayMeals
            .flatMap { $0.micros }
            .filter { $0.id == id }
            .reduce(0) { $0 + $1.pctRDA }
        return min(100, sum)
    }

    /// Ids des micronutriments présents dans les repas du jour, en ordre
    /// canonique (NutrientData.all) puis le reste (ids hors catalogue, triés).
    var dayNutrientIds: [String] {
        let present = Set(dayMeals.flatMap { $0.micros }.map(\.id))
        let canonical = NutrientData.all.map(\.id.rawValue).filter { present.contains($0) }
        let rest = present.subtracting(canonical).sorted()
        return canonical + rest
    }

    // MARK: - Navigation jour par jour (bornée à la fenêtre `fortnight`)

    /// Jour le plus ancien navigable = le SOL RÉEL de la fenêtre chargée par
    /// `load()` : `week.start − 7 j` (lundi de la semaine précédente). Aligné sur
    /// la même source que le chargement, pour ne jamais proposer un jour passé
    /// « vide » alors que ses repas existent en base mais hors de la requête.
    private var earliestDay: Date {
        let cal = Calendar.current
        let weekStart = WeekScoreEngine.currentWeekInterval(containing: Date()).start
        return cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: weekStart))
            ?? cal.startOfDay(for: Date())
    }

    /// Peut-on avancer d'un jour ? Faux si on est déjà sur aujourd'hui (pas de futur).
    var canGoNext: Bool {
        selectedDay < Calendar.current.startOfDay(for: Date())
    }

    func goPrevDay() {
        let cal = Calendar.current
        guard let prev = cal.date(byAdding: .day, value: -1, to: selectedDay) else { return }
        let clamped = cal.startOfDay(for: prev)
        if clamped >= earliestDay { selectedDay = clamped }
    }

    func goNextDay() {
        guard canGoNext else { return }
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .day, value: 1, to: selectedDay) else { return }
        selectedDay = min(cal.startOfDay(for: next), cal.startOfDay(for: Date()))
    }

    // MARK: - Libellés du jour

    /// Libellé principal : Aujourd'hui / Hier / Avant-hier / date courte.
    var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDay) { return "Aujourd'hui" }
        if cal.isDateInYesterday(selectedDay) { return "Hier" }
        if daysAgo == 2 { return "Avant-hier" }
        return Self.shortDayFormatter.string(from: selectedDay)
    }

    /// Sous-libellé : « il y a N jours » quand le libellé est déjà une date,
    /// sinon la date courte (ex. « dim. 5 juil. »).
    var daySub: String {
        if daysAgo >= 3 { return "il y a \(daysAgo) jours" }
        return Self.shortDayFormatter.string(from: selectedDay)
    }

    private var daysAgo: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: selectedDay, to: cal.startOfDay(for: Date())).day ?? 0
    }

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    // MARK: - Phrases de synthèse (pures — testables sans I/O)

    /// En-tête de la carte « apports du jour » : nomme les 1-2 apports les plus
    /// bas (< 60 % du besoin). Tout couvert → message positif. Aucun item →
    /// invite à scanner (aujourd'hui) ou constat neutre (jour passé). Formulation
    /// sans article de genre (« ton apport en … ») + relative au jour sélectionné.
    nonisolated static func dayMicroHeadline(_ items: [(id: String, pct: Int)], isToday: Bool) -> String {
        let low = items.filter { $0.pct < 60 }.sorted { $0.pct < $1.pct }
        func label(_ id: String) -> String { (NutrientData.definition(for: id)?.label ?? id).lowercased() }
        let quand = isToday ? "aujourd'hui" : "ce jour-là"
        switch low.count {
        case 0:
            if items.isEmpty {
                return isToday
                    ? "Scanne un repas pour suivre tes apports du jour."
                    : "Aucun repas enregistré ce jour-là."
            }
            return "Tes apports du jour sont bien couverts."
        case 1:
            return "Ton apport en \(label(low[0].id)) est en retard \(quand)."
        default:
            return "Tes apports en \(label(low[0].id)) et \(label(low[1].id)) sont en retard \(quand)."
        }
    }

    /// En-tête de la carte macros : nomme la macro la plus en retard (plus grand
    /// écart cible − apport, en grammes). Rien à combler → journée équilibrée.
    /// Prescriptif pour aujourd'hui (« vise … de plus »), rétrospectif pour un
    /// jour passé (« il manquait … »).
    nonisolated static func dayMacroHeadline(
        prot: (g: Double, target: Int?),
        carb: (g: Double, target: Int?),
        fat: (g: Double, target: Int?),
        fiber: (g: Double, target: Int?),
        isToday: Bool
    ) -> String {
        func gap(_ m: (g: Double, target: Int?)) -> Double {
            guard let t = m.target, t > 0 else { return 0 }
            return max(0, Double(t) - m.g)
        }
        let macros: [(name: String, gap: Double)] = [
            ("protéines", gap(prot)),
            ("glucides", gap(carb)),
            ("lipides", gap(fat)),
            ("fibres", gap(fiber)),
        ]
        guard let worst = macros.max(by: { $0.gap < $1.gap }), worst.gap >= 1 else {
            return isToday ? "Équilibré aujourd'hui." : "Journée équilibrée."
        }
        let g = Int(worst.gap.rounded())
        return isToday
            ? "Vise \(g) g de \(worst.name) de plus aujourd'hui."
            : "Il manquait \(g) g de \(worst.name) ce jour-là."
    }
}
