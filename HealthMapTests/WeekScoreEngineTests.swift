import XCTest
@testable import HealthMap

// MARK: - Week Score Engine Tests
// Le score de la semaine est 100 % déterministe : mêmes repas + mêmes apports
// à renforcer → même score. Dates fixes pour des tests reproductibles.

final class WeekScoreEngineTests: XCTestCase {

    private let cal = WeekScoreEngine.mondayFirst

    /// Jeudi 2 juillet 2026, 12:00 UTC (semaine du lundi 29 juin).
    private var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 2; c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func meal(daysAgo: Int, micros: [(String, Int)], at hour: Int = 12) -> MealJournalService.MealRecord {
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: now))!
        let date = cal.date(byAdding: .hour, value: hour, to: day)!
        return MealJournalService.MealRecord(
            id: UUID().uuidString,
            consumedAt: date,
            slot: .lunch,
            foods: ["test"],
            macros: MealJournalService.MealMacros(),
            micros: micros.map { MealJournalService.MicroPct(id: $0.0, pctRDA: $0.1) }
        )
    }

    // MARK: - Semaine vide

    func testEmptyWeek_hasNoScore() {
        let result = WeekScoreEngine.compute(meals: [], weakNutrients: ["iron"], now: now, calendar: cal)
        XCTAssertNil(result.score)
        XCTAssertNil(result.delta)
        XCTAssertEqual(result.mealCount, 0)
        XCTAssertEqual(result.days.count, 7)
        XCTAssertTrue(result.days.allSatisfy { $0.score == nil })
    }

    // MARK: - Score d'un jour

    func testSingleDay_averagesWeakNutrients_andCapsAt100() {
        // Fer : 60 + 70 = 130 → plafonné à 100 ; magnésium : 40. Moyenne = 70.
        let meals = [
            meal(daysAgo: 0, micros: [("iron", 60), ("magnesium", 40)]),
            meal(daysAgo: 0, micros: [("iron", 70)]),
        ]
        let result = WeekScoreEngine.compute(meals: meals, weakNutrients: ["iron", "magnesium"], now: now, calendar: cal)
        XCTAssertEqual(result.score, 70)
        XCTAssertEqual(result.mealCount, 2)
    }

    func testWeekScore_ignoresDaysWithoutData() {
        // Deux jours avec données (100 et 50) sur une semaine de 7 → moyenne 75,
        // les jours sans scan ne pénalisent pas.
        let meals = [
            meal(daysAgo: 0, micros: [("iron", 100)]),
            meal(daysAgo: 2, micros: [("iron", 50)]),
        ]
        let result = WeekScoreEngine.compute(meals: meals, weakNutrients: ["iron"], now: now, calendar: cal)
        XCTAssertEqual(result.score, 75)
    }

    func testMealWithoutMicros_countsInMealCount_notInScore() {
        let meals = [
            meal(daysAgo: 0, micros: [("iron", 80)]),
            meal(daysAgo: 1, micros: []),   // scan ancien / ajout manuel / ligne web
        ]
        let result = WeekScoreEngine.compute(meals: meals, weakNutrients: ["iron"], now: now, calendar: cal)
        XCTAssertEqual(result.mealCount, 2)
        XCTAssertEqual(result.score, 80)  // le jour sans micros ne compte pas
    }

    // MARK: - Comparaison vs semaine précédente

    func testDelta_positiveWhenImproving() {
        let meals = [
            meal(daysAgo: 0, micros: [("iron", 80)]),    // semaine courante : 80
            meal(daysAgo: 7, micros: [("iron", 50)]),    // semaine précédente : 50
        ]
        let result = WeekScoreEngine.compute(meals: meals, weakNutrients: ["iron"], now: now, calendar: cal)
        XCTAssertEqual(result.delta, 30)
        XCTAssertEqual(result.topMover?.id, "iron")
        XCTAssertEqual(result.topMover?.delta, 30)
    }

    func testDelta_nilWithoutPreviousWeekData() {
        let meals = [meal(daysAgo: 0, micros: [("iron", 80)])]
        let result = WeekScoreEngine.compute(meals: meals, weakNutrients: ["iron"], now: now, calendar: cal)
        XCTAssertNil(result.delta)
        XCTAssertNil(result.topMover)
    }

    func testTopMover_picksBiggestAbsoluteChange() {
        let meals = [
            meal(daysAgo: 0, micros: [("iron", 60), ("magnesium", 20)]),
            meal(daysAgo: 7, micros: [("iron", 50), ("magnesium", 70)]),
        ]
        // Fer : +10 ; magnésium : −50 → le magnésium bouge le plus.
        let result = WeekScoreEngine.compute(meals: meals, weakNutrients: ["iron", "magnesium"], now: now, calendar: cal)
        XCTAssertEqual(result.topMover?.id, "magnesium")
        XCTAssertEqual(result.topMover?.delta, -50)
    }

    // MARK: - Fallback sans apport à renforcer

    func testNoWeakNutrients_fallsBackToScannedNutrients() {
        let meals = [meal(daysAgo: 0, micros: [("vitC", 90), ("iron", 30)])]
        let result = WeekScoreEngine.compute(meals: meals, weakNutrients: [], now: now, calendar: cal)
        XCTAssertEqual(result.score, 60)  // (90 + 30) / 2
    }

    // MARK: - Bornes de semaine (lundi)

    func testWeekStartsOnMonday() {
        let week = WeekScoreEngine.currentWeekInterval(containing: now, calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: week.start), 2)  // lundi
        XCTAssertEqual(week.duration, 7 * 86_400, accuracy: 3_700)   // ±1 h (DST)
    }

    func testMealFromPreviousWeek_doesNotLeakIntoCurrentDays() {
        let meals = [meal(daysAgo: 7, micros: [("iron", 50)])]
        let result = WeekScoreEngine.compute(meals: meals, weakNutrients: ["iron"], now: now, calendar: cal)
        XCTAssertNil(result.score)
        XCTAssertEqual(result.mealCount, 0)
    }
}
