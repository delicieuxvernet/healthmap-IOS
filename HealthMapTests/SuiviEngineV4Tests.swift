import XCTest
@testable import HealthMap

// MARK: - SuiviEngineV4 — vrai suivi par symptôme (déterministe)
//
// Le vrai suivi ne réagit QU'aux check-ins réels : baseline 50, puis un point
// par check-in, chaque ressenti déplaçant le niveau d'un pas dans son sens.
// « mieux » (0) va vers l'amélioration : DESCEND si lowerBetter, MONTE si
// higherBetter ; « moins bien » (2) inverse ; « pareil » (1) reste plat.

@MainActor
final class SuiviEngineV4Tests: XCTestCase {

    // MARK: - buildRealSeries

    func testBuildRealSeries_jourZero_estUniquementLaBaseline() {
        let lower = SuiviEngineV4.buildRealSeries(dir: .lowerBetter, feelings: [])
        let higher = SuiviEngineV4.buildRealSeries(dir: .higherBetter, feelings: [])
        XCTAssertEqual(lower, [50])
        XCTAssertEqual(higher, [50])
    }

    func testBuildRealSeries_mieuxRepete_descendEnLowerBetter() {
        // 3× « mieux » sur un problème (lowerBetter) → le niveau DESCEND de 6 à chaque fois.
        let series = SuiviEngineV4.buildRealSeries(dir: .lowerBetter, feelings: [0, 0, 0])
        XCTAssertEqual(series, [50, 44, 38, 32])
    }

    func testBuildRealSeries_mieuxRepete_monteEnHigherBetter() {
        // 3× « mieux » sur un objectif (higherBetter) → le niveau MONTE de 6 à chaque fois.
        let series = SuiviEngineV4.buildRealSeries(dir: .higherBetter, feelings: [0, 0, 0])
        XCTAssertEqual(series, [50, 56, 62, 68])
    }

    func testBuildRealSeries_pareilResteePlat_moinsBienInverse() {
        // pareil → plat ; moins bien sur lowerBetter → le niveau MONTE (aggravation).
        let series = SuiviEngineV4.buildRealSeries(dir: .lowerBetter, feelings: [1, 2])
        XCTAssertEqual(series, [50, 50, 56])
    }

    func testBuildRealSeries_clampeEntre0Et100() {
        // Beaucoup de « mieux » sur lowerBetter ne descend pas sous 0.
        let series = SuiviEngineV4.buildRealSeries(dir: .lowerBetter,
                                                   feelings: Array(repeating: 0, count: 20))
        XCTAssertEqual(series.first, 50)
        XCTAssertEqual(series.last, 0)
        XCTAssertTrue(series.allSatisfy { $0 >= 0 && $0 <= 100 })
    }

    // MARK: - evolution : mode exemple vs réel

    func testEvolution_example_estBadgeExemple_etVariationNeutre() {
        let trend = SymptomTrend.make(from: "ongles cassants")
        let evo = SuiviEngineV4.evolution(id: "s1", nom: "Ongles", trend: trend, tracking: .example)
        XCTAssertTrue(evo.isExample)
        XCTAssertEqual(evo.variationPct, 0)
        XCTAssertEqual(evo.verdict, "Stable")
        XCTAssertFalse(evo.reel.isEmpty)
        XCTAssertTrue(evo.potentielMax.isEmpty)
        XCTAssertGreaterThanOrEqual(evo.sansKiwio.count, 2)
    }

    func testEvolution_reel_jourZero_variationNulle_unSeulPoint() {
        let trend = SymptomTrend.make(from: "ongles cassants")
        let evo = SuiviEngineV4.evolution(id: "s1", nom: "Ongles", trend: trend,
                                          tracking: .real(feelings: []))
        XCTAssertFalse(evo.isExample)
        XCTAssertEqual(evo.reel, [50])
        XCTAssertEqual(evo.variationPct, 0)
        // « sans Kiwio » garde ≥ 2 points pour tracer la ligne de référence.
        XCTAssertGreaterThanOrEqual(evo.sansKiwio.count, 2)
    }

    func testEvolution_reel_ameliorationReelle_estEnAmelioration() {
        // Plusieurs « mieux » sur un problème → variation négative significative.
        let trend = SymptomTrend.make(from: "ongles cassants")
        let evo = SuiviEngineV4.evolution(id: "s1", nom: "Ongles", trend: trend,
                                          tracking: .real(feelings: [0, 0, 0]))
        XCTAssertFalse(evo.isExample)
        XCTAssertLessThan(evo.variationPct, 0)
        XCTAssertTrue(evo.improving)
        XCTAssertEqual(evo.verdict, "En amélioration")
    }

    // MARK: - Carrousel v2 : per-symptôme + séries quotidiennes macros/micros

    private func meal(daysAgo: Int, cals: Int = 0, prot: Double = 0,
                      micros: [(String, Int)] = [], now: Date,
                      cal: Calendar = .current) -> MealJournalService.MealRecord {
        let day = cal.date(byAdding: .day, value: -daysAgo, to: now)!
        return MealJournalService.MealRecord(
            id: UUID().uuidString, consumedAt: day, slot: .lunch, foods: ["x"],
            macros: MealJournalService.MealMacros(calories: cals, proteins: prot),
            micros: micros.map { MealJournalService.MicroPct(id: $0.0, pctRDA: $0.1) })
    }

    func testMacroDailySeries_sommeParJour_trousNil() {
        let now = Date()
        let meals = [
            meal(daysAgo: 0, cals: 500, prot: 30, now: now),
            meal(daysAgo: 0, cals: 300, prot: 10, now: now),   // même jour → somme
            meal(daysAgo: 2, cals: 700, prot: 40, now: now),
        ]
        let kcal = SuiviEngineV4.macroDailySeries(fortnight: meals, macro: .calories, days: 3, now: now)
        XCTAssertEqual(kcal.count, 3)          // il y a 2 j, 1 j, aujourd'hui
        XCTAssertEqual(kcal[0].value, 700)
        XCTAssertNil(kcal[1].value)            // aucun repas ce jour → trou honnête
        XCTAssertEqual(kcal[2].value, 800)     // 500 + 300
        let prot = SuiviEngineV4.macroDailySeries(fortnight: meals, macro: .proteins, days: 3, now: now)
        XCTAssertEqual(prot[2].value, 40)
    }

    func testMicroDailySeries_couvertureCapee100_trousNil() {
        let now = Date()
        let meals = [
            meal(daysAgo: 0, micros: [("iron", 60), ("iron", 70)], now: now), // 130 → cap 100
            meal(daysAgo: 1, micros: [("iron", 40)], now: now),
        ]
        let s = SuiviEngineV4.microDailySeries(fortnight: meals, id: "iron", days: 3, now: now)
        XCTAssertEqual(s.count, 3)
        XCTAssertNil(s[0].value)               // il y a 2 j : aucun repas
        XCTAssertEqual(s[1].value, 40)
        XCTAssertEqual(s[2].value, 100)        // plafonné
    }

    func testSeriesSummary_premierDernierReel_ecartJours() {
        let now = Date()
        let pts = SuiviEngineV4.microDailySeries(
            fortnight: [meal(daysAgo: 3, micros: [("iron", 20)], now: now),
                        meal(daysAgo: 0, micros: [("iron", 55)], now: now)],
            id: "iron", days: 4, now: now)
        let sum = SuiviEngineV4.seriesSummary(pts)
        XCTAssertEqual(sum?.first, 20)
        XCTAssertEqual(sum?.last, 55)
        XCTAssertEqual(sum?.gapDays, 3)
        XCTAssertEqual(sum?.delta, 35)
    }

    func testSeriesSummary_aucuneDonnee_estNil() {
        let pts = [SuiviEngineV4.DayPoint(date: Date(), value: nil)]
        XCTAssertNil(SuiviEngineV4.seriesSummary(pts))
    }

    func testSymptomEvolutions_parSymptome_courbesDivergent() {
        // 2 symptômes « lowerBetter » : l'un s'améliore (mieux répété → descend),
        // l'autre s'aggrave (moins bien → monte). Preuve que chaque courbe est
        // INDÉPENDANTE (fin du « tout bon ou tout mauvais »).
        let syms = [SymptomeV2(id: "hair", nom: "chute de cheveux", causes: nil),
                    SymptomeV2(id: "fat", nom: "fatigue", causes: nil)]
        let feels = ["hair": [0, 0, 0], "fat": [2, 2, 2]]
        let evos = SuiviEngineV4.symptomEvolutions(symptomes: syms, feelingsById: feels,
                                                   isTracking: true, step: 3)
        let hair = evos.first { $0.id == "hair" }!
        let fat = evos.first { $0.id == "fat" }!
        XCTAssertLessThan(hair.variationPct, 0)      // amélioration
        XCTAssertGreaterThan(fat.variationPct, 0)    // aggravation
        XCTAssertTrue(hair.improving)
        XCTAssertFalse(fat.improving)
        XCTAssertEqual(hair.reel, [50, 47, 44, 41])  // step 3
    }

    func testSymptomEvolutions_nonDemarre_estExemple() {
        let syms = [SymptomeV2(id: "hair", nom: "chute de cheveux", causes: nil)]
        let evos = SuiviEngineV4.symptomEvolutions(symptomes: syms, feelingsById: [:],
                                                   isTracking: false)
        XCTAssertEqual(evos.count, 1)
        XCTAssertTrue(evos[0].isExample)
    }
}
