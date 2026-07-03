import Foundation

// MARK: - Score de la semaine (Bilan v6 — remplace le score figé du bilan)
//
// Score 100 % déterministe, calculé sur les repas réellement scannés
// (meal_scans.micros) et les apports à renforcer de l'utilisateur
// (HealthCalculator.analyzeNutrientScores < 60, même seuil que le scan).
//
// Définition validée (maquette « Option B », 3 juillet 2026) :
// - couverture(jour, nutriment) = min(100, Σ pctRDA des repas du jour)
// - score(jour) = moyenne des couvertures sur les apports à renforcer
// - score(semaine) = moyenne des scores des jours AVEC données (un jour
//   sans scan ne pénalise pas — il ne compte simplement pas)
// - delta = score(semaine courante) − score(semaine précédente)
//
// ⚠️ Métrique propre à iOS (pas de mirror health.js : elle n'existe pas côté
// web). Les scores nutriments/BMI/TDEE restent, eux, des mirrors exacts.
enum WeekScoreEngine {

    struct DayScore: Equatable {
        let date: Date
        /// nil = aucun repas avec micros ce jour-là.
        let score: Int?
        let isToday: Bool
    }

    struct WeekScore: Equatable {
        /// Lundi → dimanche de la semaine courante.
        let days: [DayScore]
        /// Moyenne des jours avec données ; nil si semaine sans aucun scan.
        let score: Int?
        /// Nombre de repas comptés cette semaine (avec ou sans micros).
        let mealCount: Int
        /// Écart en points vs semaine précédente ; nil si pas de comparaison.
        let delta: Int?
        /// Apport à renforcer qui a le plus bougé vs semaine précédente
        /// (id nutriment + écart en points de couverture moyenne).
        let topMover: (id: String, delta: Int)?

        static func == (lhs: WeekScore, rhs: WeekScore) -> Bool {
            lhs.days == rhs.days && lhs.score == rhs.score
                && lhs.mealCount == rhs.mealCount && lhs.delta == rhs.delta
                && lhs.topMover?.id == rhs.topMover?.id && lhs.topMover?.delta == rhs.topMover?.delta
        }
    }

    /// Calendrier français : la semaine commence le lundi, quel que soit le
    /// réglage système.
    static var mondayFirst: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal
    }

    /// - Parameters:
    ///   - meals: repas des 14 derniers jours (semaine courante + précédente).
    ///   - weakNutrients: ids des apports à renforcer (score local < 60).
    ///     Si vide (profil très couvert), tous les nutriments présents dans
    ///     les micros sont utilisés pour que le score reste vivant.
    ///   - now: injectable pour les tests.
    static func compute(meals: [MealJournalService.MealRecord],
                        weakNutrients: [String],
                        now: Date = Date(),
                        calendar: Calendar = mondayFirst) -> WeekScore {
        let week = currentWeekInterval(containing: now, calendar: calendar)
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: week.start) ?? week.start

        let currentMeals = meals.filter { week.contains($0.consumedAt) }
        let previousMeals = meals.filter { $0.consumedAt >= previousWeekStart && $0.consumedAt < week.start }

        // Cibles du score : apports à renforcer, sinon tout ce que les scans
        // de la semaine mesurent (fallback profil sans point faible).
        var targets = weakNutrients
        if targets.isEmpty {
            targets = Array(Set(currentMeals.flatMap { $0.micros.map(\.id) })).sorted()
        }

        var days: [DayScore] = []
        for offset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: week.start) else { continue }
            if dayStart > now {
                days.append(DayScore(date: dayStart, score: nil, isToday: false))
                continue
            }
            let dayMeals = currentMeals.filter { calendar.isDate($0.consumedAt, inSameDayAs: dayStart) }
            days.append(DayScore(date: dayStart,
                                 score: dayScore(meals: dayMeals, targets: targets),
                                 isToday: calendar.isDate(dayStart, inSameDayAs: now)))
        }

        let scored = days.compactMap(\.score)
        let weekScore = scored.isEmpty ? nil : Int((Double(scored.reduce(0, +)) / Double(scored.count)).rounded())

        let previousScore = weekAverage(meals: previousMeals, targets: targets, calendar: calendar)
        let delta: Int? = {
            guard let weekScore, let previousScore else { return nil }
            return weekScore - previousScore
        }()

        return WeekScore(days: days,
                         score: weekScore,
                         mealCount: currentMeals.count,
                         delta: delta,
                         topMover: topMover(current: currentMeals, previous: previousMeals, targets: targets, calendar: calendar))
    }

    // MARK: - Briques internes

    /// Couverture moyenne d'un jour sur les nutriments cibles ; nil si aucun
    /// repas du jour ne porte de micros (scan ancien, ajout manuel, ligne web).
    private static func dayScore(meals: [MealJournalService.MealRecord], targets: [String]) -> Int? {
        guard !targets.isEmpty, meals.contains(where: { !$0.micros.isEmpty }) else { return nil }
        let total = targets.reduce(0.0) { acc, id in
            acc + min(100.0, Double(meals.flatMap(\.micros).filter { $0.id == id }.map(\.pctRDA).reduce(0, +)))
        }
        return Int((total / Double(targets.count)).rounded())
    }

    /// Score moyen d'une plage de repas, jour par jour (même règle que la
    /// semaine courante) ; nil si aucun jour n'a de données.
    private static func weekAverage(meals: [MealJournalService.MealRecord], targets: [String], calendar: Calendar) -> Int? {
        let byDay = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.consumedAt) }
        let scores = byDay.values.compactMap { dayScore(meals: Array($0), targets: targets) }
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    /// Nutriment cible dont la couverture moyenne quotidienne a le plus bougé
    /// entre les deux semaines — nourrit la phrase d'insight du Bilan.
    private static func topMover(current: [MealJournalService.MealRecord],
                                 previous: [MealJournalService.MealRecord],
                                 targets: [String],
                                 calendar: Calendar) -> (id: String, delta: Int)? {
        guard !previous.isEmpty, !current.isEmpty else { return nil }
        var best: (id: String, delta: Int)?
        for id in targets {
            let cur = averageDailyCoverage(of: id, in: current, calendar: calendar)
            let prev = averageDailyCoverage(of: id, in: previous, calendar: calendar)
            guard let cur, let prev else { continue }
            let d = cur - prev
            if abs(d) > abs(best?.delta ?? 0) { best = (id, d) }
        }
        return best
    }

    private static func averageDailyCoverage(of nutrientId: String,
                                             in meals: [MealJournalService.MealRecord],
                                             calendar: Calendar) -> Int? {
        let withMicros = meals.filter { !$0.micros.isEmpty }
        guard !withMicros.isEmpty else { return nil }
        let byDay = Dictionary(grouping: withMicros) { calendar.startOfDay(for: $0.consumedAt) }
        let daily = byDay.values.map { dayMeals in
            min(100, dayMeals.flatMap(\.micros).filter { $0.id == nutrientId }.map(\.pctRDA).reduce(0, +))
        }
        return Int((Double(daily.reduce(0, +)) / Double(daily.count)).rounded())
    }

    /// Intervalle lundi 00:00 → lundi suivant 00:00 contenant `date`.
    static func currentWeekInterval(containing date: Date, calendar: Calendar = mondayFirst) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86_400)
    }
}
