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

    // MARK: - Navigation sans borne (11 sept. 2026)

    func testGoNext_ouvreLesJoursAVenir() {
        // Celui qui note son dîner à 00h30 est déjà « demain » : il doit pouvoir
        // reculer, mais aussi préparer les jours suivants. Plus aucun jour
        // interdit, dans un sens comme dans l'autre.
        let cal = Calendar.current
        let vm = MealJournalViewModel()
        XCTAssertTrue(vm.canGoNext)
        vm.goNextDay()
        XCTAssertEqual(vm.selectedDay, cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())))
        for _ in 0..<9 { vm.goNextDay() }
        XCTAssertEqual(vm.selectedDay, cal.date(byAdding: .day, value: 10, to: cal.startOfDay(for: Date())))
    }

    func testGoPrev_remonteAuDelaDeLaQuinzaine() {
        // L'ancienne borne (min(lundi précédent − 7 j, 14 jours glissants))
        // arrêtait les chevrons au bout de deux semaines : impossible de relire
        // un mois passé autrement qu'au calendrier.
        let cal = Calendar.current
        let vm = MealJournalViewModel()
        for _ in 0..<40 { vm.goPrevDay() }
        XCTAssertEqual(vm.selectedDay, cal.date(byAdding: .day, value: -40, to: cal.startOfDay(for: Date())))
    }

    func testLibelles_passeEtFutur() {
        let cal = Calendar.current
        let vm = MealJournalViewModel()
        XCTAssertEqual(vm.dayLabel, "Aujourd'hui")

        vm.goNextDay()
        XCTAssertEqual(vm.dayLabel, "Demain")
        vm.goNextDay()
        XCTAssertEqual(vm.dayLabel, "Après-demain")
        for _ in 0..<3 { vm.goNextDay() }
        XCTAssertEqual(vm.daySub, "dans 5 jours")

        vm.selectedDay = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        XCTAssertEqual(vm.dayLabel, "Hier")
        vm.selectedDay = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: Date()))!
        XCTAssertEqual(vm.dayLabel, "Avant-hier")
        vm.selectedDay = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))!
        XCTAssertEqual(vm.daySub, "il y a 6 jours")
    }

    // MARK: - Écriture sur le jour AFFICHÉ

    func testHorodatage_aujourdhuiGardeLHeureReelle() {
        // Sur aujourd'hui, l'heure réelle du repas vaut mieux qu'une heure de
        // convention : rien ne change par rapport à l'existant.
        let maintenant = Date()
        XCTAssertEqual(
            MealJournalService.horodatage(jour: maintenant, slot: .dinner, maintenant: maintenant),
            maintenant
        )
    }

    func testHorodatage_autreJourPoseLHeureCanoniqueDuCreneau() {
        // Le dîner de la veille saisi à 00h30 doit atterrir le SOIR de la veille,
        // pas à 00h30 — sinon la relecture (`MealSlot.from`) le range au dîner du
        // mauvais bout de journée.
        let cal = Calendar.current
        let minuitTrente = cal.date(bySettingHour: 0, minute: 30, second: 0, of: Date())!
        let veille = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: minuitTrente))!

        let ecrit = MealJournalService.horodatage(jour: veille, slot: .dinner, maintenant: minuitTrente)
        XCTAssertTrue(cal.isDate(ecrit, inSameDayAs: veille))
        XCTAssertEqual(cal.component(.hour, from: ecrit), 20)
        XCTAssertEqual(MealJournalService.MealSlot.from(date: ecrit), .dinner)
    }

    func testHorodatage_tousLesCreneauxFontLAllerRetour() {
        let cal = Calendar.current
        let demain = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        for slot in MealJournalService.MealSlot.ordreJournal {
            let ecrit = MealJournalService.horodatage(jour: demain, slot: slot, maintenant: Date())
            XCTAssertTrue(cal.isDate(ecrit, inSameDayAs: demain), "\(slot) posé sur le mauvais jour")
            XCTAssertEqual(MealJournalService.MealSlot.from(date: ecrit), slot, "\(slot) ne se relit pas")
        }
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
