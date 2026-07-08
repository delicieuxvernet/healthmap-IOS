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
}
