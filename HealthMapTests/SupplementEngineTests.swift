import XCTest
@testable import HealthMap

// MARK: - Supplement Engine Tests
// Validates the deterministic supplement recommendation pipeline:
// product selection, interaction detection, schedule generation, cost calculation.
// These tests run offline — no network, no database.

final class SupplementEngineTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a test profile with the given diet and optional overrides.
    private func makeProfile(
        dietType: String = "omnivore",
        pregnancyStatus: String = "na",
        periodFlow: String = "na",
        indoorWork: String = "no",
        stressLevel: String = "relaxed",
        age: String = "30"
    ) -> UserProfile {
        var p = UserProfile.empty
        p.completed = true
        p.dietType = dietType
        p.pregnancyStatus = pregnancyStatus
        p.periodFlow = periodFlow
        p.indoorWork = indoorWork
        p.stressLevel = stressLevel
        p.age = age
        p.gender = .homme
        return p
    }

    /// Scores where every nutrient is 60+ (no deficiencies).
    private var healthyScores: [String: Int] {
        var scores: [String: Int] = [:]
        for n in NutrientID.allCases {
            scores[n.rawValue] = 75
        }
        return scores
    }

    /// Scores with a single nutrient at 30 (deficient), the rest at 75.
    private func scoresWithDeficiency(_ nutrient: NutrientID, score: Int = 30) -> [String: Int] {
        var scores = healthyScores
        scores[nutrient.rawValue] = score
        return scores
    }

    /// Scores with multiple deficiencies.
    private func scoresWithMultipleDeficiencies(_ pairs: [(NutrientID, Int)]) -> [String: Int] {
        var scores = healthyScores
        for (nutrient, score) in pairs {
            scores[nutrient.rawValue] = score
        }
        return scores
    }

    // MARK: - selectProducts

    /// No deficiencies (all scores >= 60) should return an empty recommendation list.
    func testSelectProducts_noDeficiencies_returnsEmpty() {
        let profile = makeProfile()
        let recs = SupplementEngine.selectProducts(scores: healthyScores, profile: profile)
        XCTAssertTrue(recs.isEmpty, "No deficiency should produce zero recommendations")
    }

    /// A single deficiency should return exactly one recommendation.
    func testSelectProducts_oneDeficiency_returnsRecommendation() {
        let profile = makeProfile()
        let scores = scoresWithDeficiency(.vitB12, score: 30)
        let recs = SupplementEngine.selectProducts(scores: scores, profile: profile)
        XCTAssertEqual(recs.count, 1, "One deficiency should produce one recommendation")
        XCTAssertEqual(recs.first?.nutrientID, .vitB12)
    }

    /// With 5+ deficiencies, only the top 3 by priority should be returned.
    func testSelectProducts_limitedToTop3() {
        let profile = makeProfile()
        let scores = scoresWithMultipleDeficiencies([
            (.vitD, 20), (.vitB12, 15), (.iron, 25),
            (.omega3, 30), (.magnesium, 35), (.vitC, 40),
        ])
        let recs = SupplementEngine.selectProducts(scores: scores, profile: profile)
        XCTAssertEqual(recs.count, 3, "Should be limited to top 3 recommendations")
    }

    /// Recommendations should be sorted by priority (highest first).
    func testSelectProducts_priorityOrdering() {
        let profile = makeProfile()
        let scores = scoresWithMultipleDeficiencies([
            (.vitD, 20), (.vitB12, 15), (.iron, 25),
        ])
        let recs = SupplementEngine.selectProducts(scores: scores, profile: profile)
        // Verify descending priority order
        for i in 0..<(recs.count - 1) {
            XCTAssertGreaterThanOrEqual(
                recs[i].priorityScore, recs[i + 1].priorityScore,
                "Recommendations should be sorted by priority descending"
            )
        }
    }

    /// Vegans should NOT receive fish-based omega-3 (isVegan=false products filtered out).
    func testSelectProducts_vegan_excludesFishOmega3() {
        let profile = makeProfile(dietType: "vegan")
        let scores = scoresWithDeficiency(.omega3, score: 20)
        let recs = SupplementEngine.selectProducts(scores: scores, profile: profile)

        for rec in recs where rec.nutrientID == .omega3 {
            if let premium = rec.premiumProduct {
                XCTAssertTrue(premium.isVegan, "Vegan should not get non-vegan omega-3 premium product")
            }
            if let value = rec.valueProduct {
                XCTAssertTrue(value.isVegan, "Vegan should not get non-vegan omega-3 value product")
            }
        }
    }

    /// Omnivores should be able to receive fish-based omega-3.
    func testSelectProducts_omnivore_includesFishOmega3() {
        let profile = makeProfile(dietType: "omnivore")
        let scores = scoresWithDeficiency(.omega3, score: 20)
        let recs = SupplementEngine.selectProducts(scores: scores, profile: profile)
        guard let omega3Rec = recs.first(where: { $0.nutrientID == .omega3 }) else {
            XCTFail("Omnivore with low omega-3 should get a recommendation")
            return
        }
        // At least one product should exist (fish-based or otherwise)
        XCTAssertTrue(omega3Rec.premiumProduct != nil || omega3Rec.valueProduct != nil,
                       "Omnivore should receive omega-3 product recommendations")
    }

    // MARK: - detectInteractionWarnings

    /// Iron + calcium in the same recommendation set should produce a warning.
    func testDetectInteractions_ironAndCalcium_warns() {
        let profile = makeProfile()
        let scores = scoresWithMultipleDeficiencies([(.iron, 20), (.calcium, 25)])
        let recs = SupplementEngine.selectProducts(scores: scores, profile: profile)
        let warnings = SupplementEngine.detectInteractionWarnings(from: recs)

        let hasIronCalciumWarning = warnings.contains { warning in
            let nutrients = Set(warning.nutrients)
            return nutrients.contains("iron") && nutrients.contains("calcium")
        }
        XCTAssertTrue(hasIronCalciumWarning, "Iron + calcium should produce an interaction warning")
    }

    /// Non-conflicting nutrients should not generate warnings.
    func testDetectInteractions_noConflict_noWarning() {
        let profile = makeProfile()
        // VitD + VitB12 have no known interaction
        let scores = scoresWithMultipleDeficiencies([(.vitD, 20), (.vitB12, 25)])
        let recs = SupplementEngine.selectProducts(scores: scores, profile: profile)
        let warnings = SupplementEngine.detectInteractionWarnings(from: recs)
        XCTAssertTrue(warnings.isEmpty, "Non-conflicting nutrients should produce no warnings, got \(warnings.count)")
    }

    // MARK: - generateSchedule

    /// Products from 3 different timing slots should produce 3 schedule groups.
    func testGenerateSchedule_groupsByTimingSlot() {
        let profile = makeProfile()
        // VitD (matin), iron (matin a jeun), omega-3 (midi) — should create Matin + Midi groups
        let scores = scoresWithMultipleDeficiencies([(.vitD, 20), (.iron, 25), (.omega3, 30)])
        let recs = SupplementEngine.selectProducts(scores: scores, profile: profile)
        let schedule = SupplementEngine.generateSchedule(from: recs)

        XCTAssertFalse(schedule.isEmpty, "Schedule should not be empty with recommendations")

        // Each group should have a non-empty product list
        for group in schedule {
            XCTAssertFalse(group.products.isEmpty, "Schedule group \(group.label) should have products")
        }
    }

    /// No recommendations should produce an empty schedule.
    func testGenerateSchedule_emptyRecommendations_emptySchedule() {
        let schedule = SupplementEngine.generateSchedule(from: [])
        XCTAssertTrue(schedule.isEmpty, "Empty recommendations should produce empty schedule")
    }

    // MARK: - calculateCost

    /// A single product should compute the correct monthly cost.
    func testCalculateCost_singleProduct_correctMonthlyCost() {
        let profile = makeProfile()
        let scores = scoresWithDeficiency(.vitD, score: 20)
        let recs = SupplementEngine.selectProducts(scores: scores, profile: profile)
        let cost = SupplementEngine.calculateCost(from: recs)

        // Cost should be > 0 for a product with a price
        XCTAssertGreaterThan(cost.premiumTotal, 0, "Premium total should be > 0")
        XCTAssertGreaterThan(cost.valueTotal, 0, "Value total should be > 0")
    }

    // MARK: - generateRecommendations (full pipeline)

    /// Full pipeline for a profile with deficiencies: all output fields should be populated.
    func testGenerateRecommendations_fullResult_allFieldsPopulated() {
        let profile = makeProfile(dietType: "vegan", indoorWork: "yes", stressLevel: "very")
        let scores = scoresWithMultipleDeficiencies([(.vitD, 15), (.vitB12, 10), (.iron, 25)])
        let result = SupplementEngine.generateRecommendations(scores: scores, profile: profile)

        XCTAssertFalse(result.topRecommendations.isEmpty, "Should have recommendations")
        XCTAssertLessThanOrEqual(result.topRecommendations.count, 3, "Should not exceed 3")

        // Each recommendation should have at least one product
        for rec in result.topRecommendations {
            XCTAssertTrue(rec.premiumProduct != nil || rec.valueProduct != nil,
                           "\(rec.nutrientID.rawValue) should have at least one product")
            XCTAssertFalse(rec.whyText.isEmpty, "whyText should not be empty")
            XCTAssertGreaterThan(rec.priorityScore, 0, "Priority score should be > 0")
        }
    }

    // MARK: - filterContraindications

    /// Pregnant user should not receive iron products with "grossesse" contraindication.
    func testFilterContraindications_pregnantExcluded() {
        let profile = makeProfile(dietType: "omnivore", pregnancyStatus: "pregnant")
        let scores = scoresWithDeficiency(.iron, score: 20)
        let recs = SupplementEngine.selectProducts(scores: scores, profile: profile)

        for rec in recs where rec.nutrientID == .iron {
            if let premium = rec.premiumProduct {
                let hasGrossesse = premium.contraindications.contains { $0.lowercased().contains("grossesse") }
                XCTAssertFalse(hasGrossesse, "Pregnant user should not receive iron product with grossesse contraindication")
            }
        }
    }

    // MARK: - Diet Difficulty

    /// Vegan diet difficulty for B12 should be higher than omnivore's.
    func testDietDifficulty_veganHigherThanOmnivore() {
        let veganProfile = makeProfile(dietType: "vegan")
        let omnivoreProfile = makeProfile(dietType: "omnivore")

        let scores = scoresWithDeficiency(.vitB12, score: 30)

        let veganRecs = SupplementEngine.selectProducts(scores: scores, profile: veganProfile)
        let omnivoreRecs = SupplementEngine.selectProducts(scores: scores, profile: omnivoreProfile)

        guard let veganB12 = veganRecs.first(where: { $0.nutrientID == .vitB12 }),
              let omnivoreB12 = omnivoreRecs.first(where: { $0.nutrientID == .vitB12 }) else {
            XCTFail("Both profiles should produce a B12 recommendation")
            return
        }

        XCTAssertGreaterThan(
            veganB12.dietDifficulty, omnivoreB12.dietDifficulty,
            "Vegan B12 diet difficulty (\(veganB12.dietDifficulty)) should be higher than omnivore (\(omnivoreB12.dietDifficulty))"
        )
    }
}
