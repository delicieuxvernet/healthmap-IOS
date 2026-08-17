import XCTest
@testable import HealthMap

// MARK: - Page d'accueil Scan (journal du jour) — logique déterministe
// Agrégation des macros/micros du jour sélectionné + phrases de synthèse.
// Aucune I/O : on injecte `fortnight` + `selectedDay` directement.

@MainActor
final class ScanHomeJournalTests: XCTestCase {

    /// Repas du 5 juillet 2026 à l'heure donnée (calendrier courant, comme la VM).
    private func meal(
        hour: Int,
        cals: Int = 0,
        prot: Double = 0, carbs: Double = 0, fats: Double = 0, fiber: Double = 0,
        micros: [(String, Int)] = []
    ) -> MealJournalService.MealRecord {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 5; c.hour = hour
        let date = Calendar.current.date(from: c)!
        return MealJournalService.MealRecord(
            id: UUID().uuidString,
            consumedAt: date,
            slot: .lunch,
            foods: ["repas"],
            macros: MealJournalService.MealMacros(calories: cals, proteins: prot, carbs: carbs, fats: fats, fiber: fiber),
            micros: micros.map { MealJournalService.MicroPct(id: $0.0, pctRDA: $0.1) }
        )
    }

    private func makeVM(_ meals: [MealJournalService.MealRecord]) -> MealJournalViewModel {
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 5; c.hour = 12
        let day = Calendar.current.date(from: c)!
        let vm = MealJournalViewModel()
        vm.fortnight = meals
        vm.selectedDay = Calendar.current.startOfDay(for: day)
        return vm
    }

    // MARK: - dayMicroPct : somme des pctRDA, plafonnée à 100

    func testDayMicroPct_sumsAndCapsAt100() {
        let vm = makeVM([
            meal(hour: 8, micros: [("iron", 60), ("magnesium", 40)]),
            meal(hour: 13, micros: [("iron", 70)]),
        ])
        XCTAssertEqual(vm.dayMicroPct("iron"), 100)      // 60 + 70 = 130 → cap 100
        XCTAssertEqual(vm.dayMicroPct("magnesium"), 40)
        XCTAssertEqual(vm.dayMicroPct("vitD"), 0)        // absent
    }

    func testDayMicroPct_ignoresOtherDays() {
        // Un repas hors du jour sélectionné ne doit pas compter.
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 3; c.hour = 12
        let otherDay = Calendar.current.date(from: c)!
        let past = MealJournalService.MealRecord(
            id: UUID().uuidString, consumedAt: otherDay, slot: .lunch, foods: ["x"],
            macros: MealJournalService.MealMacros(),
            micros: [MealJournalService.MicroPct(id: "iron", pctRDA: 90)]
        )
        let vm = makeVM([past, meal(hour: 9, micros: [("iron", 20)])])
        XCTAssertEqual(vm.dayMicroPct("iron"), 20)
    }

    // MARK: - Agrégation des macros du jour

    func testDayMacros_aggregateOverDayMeals() {
        let vm = makeVM([
            meal(hour: 8, cals: 300, prot: 25, carbs: 30, fats: 10, fiber: 4),
            meal(hour: 13, cals: 500, prot: 15, carbs: 60, fats: 20, fiber: 6),
        ])
        XCTAssertEqual(vm.dayCalories, 800)
        XCTAssertEqual(vm.dayProteins, 40, accuracy: 0.001)
        XCTAssertEqual(vm.dayCarbs, 90, accuracy: 0.001)
        XCTAssertEqual(vm.dayFats, 30, accuracy: 0.001)
        XCTAssertEqual(vm.dayFiber, 10, accuracy: 0.001)
    }

    func testDayNutrientIds_canonicalOrder() {
        // Fer (index 2) et Vitamine C (index 5) dans le catalogue → ordre Fer puis Vit C.
        let vm = makeVM([meal(hour: 12, micros: [("vitC", 40), ("iron", 30)])])
        XCTAssertEqual(vm.dayNutrientIds, ["iron", "vitC"])
    }

    // MARK: - Navigation bornée

    func testCanGoNext_falseOnToday() {
        let vm = MealJournalViewModel()  // selectedDay = aujourd'hui
        XCTAssertFalse(vm.canGoNext)
        vm.goNextDay()                   // no-op (pas de futur)
        XCTAssertFalse(vm.canGoNext)
    }

    func testGoPrev_clampsToLoadedWindow() {
        // La borne basse doit être le SOL RÉEL de la fenêtre chargée par load(),
        // DÉRIVÉ de la même règle que lui (jamais une date en dur) : union des
        // deux besoins, min(lundi précédent − 7 j hebdo, 14 jours glissants).
        // Sinon on proposerait des jours passés « vides » dont les repas
        // existent en base mais hors requête — ou l'inverse.
        let cal = Calendar.current
        let vm = MealJournalViewModel()
        for _ in 0..<20 { vm.goPrevDay() }
        let weekStart = WeekScoreEngine.currentWeekInterval(containing: Date()).start
        let solSemaine = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: weekStart))!
        let solAxe = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: Date()))!
        XCTAssertEqual(vm.selectedDay, min(solSemaine, solAxe))
        XCTAssertTrue(vm.canGoNext)
    }

    // MARK: - Phrase de synthèse micros (les 2 plus bas)

    func testMicroHeadline_namesTwoLowest() {
        let items = [(id: "iron", pct: 80), (id: "vitD", pct: 10), (id: "magnesium", pct: 25)]
        XCTAssertEqual(
            MealJournalViewModel.dayMicroHeadline(items, isToday: true),
            "Tes apports en vitamine d et magnésium sont en retard aujourd'hui."
        )
    }

    func testMicroHeadline_singleLow() {
        let items = [(id: "iron", pct: 80), (id: "vitD", pct: 20)]
        XCTAssertEqual(
            MealJournalViewModel.dayMicroHeadline(items, isToday: true),
            "Ton apport en vitamine d est en retard aujourd'hui."
        )
    }

    func testMicroHeadline_pastDayWording() {
        let items = [(id: "iron", pct: 80), (id: "vitD", pct: 20)]
        XCTAssertEqual(
            MealJournalViewModel.dayMicroHeadline(items, isToday: false),
            "Ton apport en vitamine d est en retard ce jour-là."
        )
        // Jour passé sans repas → constat neutre (pas d'invite à scanner le passé).
        XCTAssertEqual(
            MealJournalViewModel.dayMicroHeadline([], isToday: false),
            "Aucun repas enregistré ce jour-là."
        )
    }

    func testMicroHeadline_allCoveredAndEmpty() {
        XCTAssertEqual(
            MealJournalViewModel.dayMicroHeadline([(id: "iron", pct: 70), (id: "vitC", pct: 90)], isToday: true),
            "Tes apports du jour sont bien couverts."
        )
        XCTAssertEqual(
            MealJournalViewModel.dayMicroHeadline([], isToday: true),
            "Scanne un repas pour suivre tes apports du jour."
        )
    }

    // MARK: - Phrase de synthèse macros (la plus en retard)

    func testMacroHeadline_picksLargestGap() {
        let s = MealJournalViewModel.dayMacroHeadline(
            prot: (g: 50, target: 100),   // gap 50
            carb: (g: 200, target: 200),  // gap 0
            fat: (g: 60, target: 70),     // gap 10
            fiber: (g: 10, target: 30),   // gap 20
            isToday: true
        )
        XCTAssertEqual(s, "Vise 50 g de protéines de plus aujourd'hui.")
    }

    func testMacroHeadline_pastDayRetrospective() {
        let s = MealJournalViewModel.dayMacroHeadline(
            prot: (g: 50, target: 100),
            carb: (g: 200, target: 200),
            fat: (g: 60, target: 70),
            fiber: (g: 10, target: 30),
            isToday: false
        )
        XCTAssertEqual(s, "Il manquait 50 g de protéines ce jour-là.")
    }

    func testMacroHeadline_balancedWithoutTargets() {
        let s = MealJournalViewModel.dayMacroHeadline(
            prot: (g: 50, target: nil),
            carb: (g: 200, target: nil),
            fat: (g: 60, target: nil),
            fiber: (g: 30, target: 30),
            isToday: true
        )
        XCTAssertEqual(s, "Équilibré aujourd'hui.")
    }
}
