import XCTest
@testable import HealthMap

// MARK: - Red Flag Detector Tests
// Each test isolates a single detection rule from RedFlagDetector.detect(profile:).
// The "why": confirms that every red-flag condition triggers (or does not trigger)
// independently, preventing regressions when new rules are added.

final class RedFlagDetectorTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a minimal profile with only the fields relevant to a specific flag.
    /// Starting from UserProfile.empty ensures unrelated defaults don't pollute the test.
    private func makeProfile(
        dietType: String = "omnivore",
        supplements: [String] = [],
        pregnancyStatus: String = "na",
        smoking: UserProfile.SmokingValue = .no,
        periodFlow: String = "na",
        weightTrend: String = "stable",
        digestiveConditions: [String] = [],
        medications: [String] = [],
        age: String = "30",
        symptoms: [String] = [],
        gender: UserProfile.Gender = .homme
    ) -> UserProfile {
        var p = UserProfile.empty
        p.completed = true
        p.dietType = dietType
        p.supplementsCurrent = supplements
        p.pregnancyStatus = pregnancyStatus
        p.smoking = smoking
        p.periodFlow = periodFlow
        p.weightTrend = weightTrend
        p.digestiveConditions = digestiveConditions
        p.medications = medications
        p.age = age
        p.symptoms = symptoms
        p.gender = gender
        return p
    }

    private func flagIDs(for profile: UserProfile) -> Set<RedFlag.RedFlagID> {
        Set(RedFlagDetector.detect(profile: profile).map(\.id))
    }

    // MARK: - Vegan / B12

    /// A vegan without B12 supplement should trigger the veganNoB12 flag
    /// because B12 is absent from all plant foods.
    func testVeganNoB12_triggered() {
        let profile = makeProfile(dietType: "vegan", supplements: [])
        let ids = flagIDs(for: profile)
        XCTAssertTrue(ids.contains(.veganNoB12), "Vegan without B12 should trigger veganNoB12 flag")
    }

    /// A vegan who already supplements B12 should NOT trigger the flag.
    func testVeganNoB12_notTriggered_withSupplement() {
        let profile = makeProfile(dietType: "vegan", supplements: ["b12"])
        let ids = flagIDs(for: profile)
        XCTAssertFalse(ids.contains(.veganNoB12), "Vegan with B12 supplement should not trigger veganNoB12 flag")
    }

    // MARK: - Pregnancy

    /// Pregnant without folate should raise an immediate urgency flag
    /// because folate is critical for neural tube development.
    func testPregnantNoFolate_triggered() {
        let profile = makeProfile(supplements: [], pregnancyStatus: "pregnant", gender: .femme)
        let ids = flagIDs(for: profile)
        XCTAssertTrue(ids.contains(.pregnantNoFolate), "Pregnant without folate should trigger pregnantNoFolate flag")
    }

    /// Pregnant + smoking combines two serious risk factors.
    func testPregnantSmoking_triggered() {
        let profile = makeProfile(pregnancyStatus: "pregnant", smoking: .yes, gender: .femme)
        let ids = flagIDs(for: profile)
        XCTAssertTrue(ids.contains(.pregnantSmoking), "Pregnant smoker should trigger pregnantSmoking flag")
    }

    /// Trying to conceive without folate — should start supplementation 3 months before.
    func testTryingConceiveNoFolate_triggered() {
        let profile = makeProfile(supplements: [], pregnancyStatus: "trying_to_conceive", gender: .femme)
        let ids = flagIDs(for: profile)
        XCTAssertTrue(ids.contains(.tryingConceiveNoFolate), "Trying to conceive without folate should trigger flag")
    }

    // MARK: - Heavy Periods

    /// Very heavy periods without iron supplement = high anaemia risk.
    func testHeavyPeriodsNoIron_triggered() {
        let profile = makeProfile(supplements: [], periodFlow: "very_heavy", gender: .femme)
        let ids = flagIDs(for: profile)
        XCTAssertTrue(ids.contains(.heavyPeriodsNoIron), "Very heavy periods without iron should trigger heavyPeriodsNoIron flag")
    }

    /// Very heavy periods + plant-based diet = double risk (non-heme iron is 3x less absorbed).
    func testHeavyPeriodsPlantBased_triggered() {
        let profile = makeProfile(dietType: "vegetarien", periodFlow: "very_heavy", gender: .femme)
        let ids = flagIDs(for: profile)
        XCTAssertTrue(ids.contains(.heavyPeriodsPlantBased), "Very heavy periods + vegetarian diet should trigger heavyPeriodsPlantBased flag")
    }

    // MARK: - Weight Loss

    /// Unintentional weight loss requires medical investigation.
    func testUnintentionalWeightLoss_triggered() {
        let profile = makeProfile(weightTrend: "losing_unintentionally")
        let ids = flagIDs(for: profile)
        XCTAssertTrue(ids.contains(.unintentionalWeightLoss), "Unintentional weight loss should trigger flag")
    }

    // MARK: - Malabsorption

    /// Celiac disease causes malabsorption of multiple nutrients.
    func testMalabsorptionCondition_triggered() {
        let profile = makeProfile(digestiveConditions: ["celiac"])
        let ids = flagIDs(for: profile)
        XCTAssertTrue(ids.contains(.malabsorptionCondition), "Celiac disease should trigger malabsorptionCondition flag")
    }

    // MARK: - Medications

    /// PPI + metformin combo doubles B12 depletion risk.
    func testPpiMetforminB12_triggered() {
        let profile = makeProfile(medications: ["ppi", "metformin"])
        let ids = flagIDs(for: profile)
        XCTAssertTrue(ids.contains(.ppiMetforminB12), "PPI + metformin should trigger ppiMetforminB12 flag")
    }

    /// 65+ with 3+ medications = polypharmacy risk for nutrient-drug interactions.
    func testElderlyPolypharmacy_triggered() {
        let profile = makeProfile(medications: ["ppi", "metformin", "diuretics"], age: "67")
        let ids = flagIDs(for: profile)
        XCTAssertTrue(ids.contains(.elderlyPolypharmacy), "Elderly with 3+ medications should trigger elderlyPolypharmacy flag")
    }

    // MARK: - Symptom Combos

    /// Tingling + vegan = B12 neuropathy risk (can become irreversible).
    func testTinglingB12Risk_triggered() {
        let profile = makeProfile(dietType: "vegan", symptoms: ["tingling"])
        let ids = flagIDs(for: profile)
        XCTAssertTrue(ids.contains(.tinglingB12Risk), "Tingling + vegan should trigger tinglingB12Risk flag")
    }

    /// Hair loss + very heavy periods = iron deficiency signal (ferritin target > 50).
    func testHairLossIronRisk_triggered() {
        let profile = makeProfile(periodFlow: "very_heavy", symptoms: ["hair_loss"], gender: .femme)
        let ids = flagIDs(for: profile)
        XCTAssertTrue(ids.contains(.hairLossIronRisk), "Hair loss + very heavy periods should trigger hairLossIronRisk flag")
    }

    // MARK: - Digestive Bleeding

    /// Selles noires/sang dans les selles = red flag transversal majeur, urgency immediate.
    /// Cause sous-jacente à écarter avant toute conclusion nutritionnelle.
    func testDigestiveBleeding_triggered_immediate() {
        let profile = makeProfile(symptoms: ["digestive_bleeding"])
        let flags = RedFlagDetector.detect(profile: profile)
        let bleedingFlag = flags.first(where: { $0.id == .digestiveBleeding })
        XCTAssertNotNil(bleedingFlag, "digestive_bleeding symptom should trigger digestiveBleeding flag")
        XCTAssertEqual(bleedingFlag?.urgency, .immediate, "digestiveBleeding flag must have urgency .immediate")
    }

    // MARK: - Edge Cases

    /// A healthy profile with no risk factors should produce zero flags.
    func testNoFlags_healthyProfile() {
        let profile = makeProfile(
            dietType: "omnivore",
            supplements: [],
            pregnancyStatus: "na",
            smoking: .no,
            periodFlow: "na",
            weightTrend: "stable",
            digestiveConditions: [],
            medications: [],
            age: "30",
            symptoms: [],
            gender: .homme
        )
        let flags = RedFlagDetector.detect(profile: profile)
        XCTAssertTrue(flags.isEmpty, "Healthy profile should have no red flags, got \(flags.map(\.id))")
    }
}
