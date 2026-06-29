import XCTest
@testable import HealthMap

// MARK: - HealthKit mapping tests
// Vérifie que les mesures Apple Santé sont traduites vers des valeurs d'option
// EXACTES du questionnaire (le scoring health.js en dépend). Fonctions pures,
// statiques — aucun runtime HealthKit requis.
final class HealthKitMappingTests: XCTestCase {

    func testActivityLevel_buckets() {
        XCTAssertEqual(HealthKitService.activityLevel(forSteps: 0), "none")
        XCTAssertEqual(HealthKitService.activityLevel(forSteps: 2999), "none")
        XCTAssertEqual(HealthKitService.activityLevel(forSteps: 3000), "light")
        XCTAssertEqual(HealthKitService.activityLevel(forSteps: 5999), "light")
        XCTAssertEqual(HealthKitService.activityLevel(forSteps: 6000), "moderate")
        XCTAssertEqual(HealthKitService.activityLevel(forSteps: 8999), "moderate")
        XCTAssertEqual(HealthKitService.activityLevel(forSteps: 9000), "regular")
        XCTAssertEqual(HealthKitService.activityLevel(forSteps: 11999), "regular")
        XCTAssertEqual(HealthKitService.activityLevel(forSteps: 12000), "intense")
        XCTAssertEqual(HealthKitService.activityLevel(forSteps: 30000), "intense")
    }

    func testSleepBucket_buckets() {
        XCTAssertEqual(HealthKitService.sleepBucket(forHours: 4.0), "4")
        XCTAssertEqual(HealthKitService.sleepBucket(forHours: 4.9), "4")
        XCTAssertEqual(HealthKitService.sleepBucket(forHours: 5.0), "5.5")
        XCTAssertEqual(HealthKitService.sleepBucket(forHours: 5.9), "5.5")
        XCTAssertEqual(HealthKitService.sleepBucket(forHours: 6.5), "6.5")
        XCTAssertEqual(HealthKitService.sleepBucket(forHours: 7.2), "7.5")
        XCTAssertEqual(HealthKitService.sleepBucket(forHours: 8.4), "8.5")
        XCTAssertEqual(HealthKitService.sleepBucket(forHours: 9.0), "10")
        XCTAssertEqual(HealthKitService.sleepBucket(forHours: 11.0), "10")
    }

    func testWeightString_usesDotAndTrimsWholeNumbers() {
        XCTAssertEqual(HealthKitService.weightString(forKilograms: 72.5), "72.5")
        XCTAssertEqual(HealthKitService.weightString(forKilograms: 70.0), "70")
        XCTAssertEqual(HealthKitService.weightString(forKilograms: 80.04), "80")
        XCTAssertEqual(HealthKitService.weightString(forKilograms: 65.96), "66")
        XCTAssertFalse(HealthKitService.weightString(forKilograms: 72.5).contains(","),
                       "Le poids ne doit jamais contenir de virgule (Double(_:) exige le point)")
    }

    /// Toute heure plausible doit mapper vers une option `sleepHours` valide.
    func testSleepBucket_alwaysValidOption() {
        let valid: Set<String> = ["4", "5.5", "6.5", "7.5", "8.5", "10"]
        for tenths in stride(from: 30, through: 120, by: 1) {
            let hours = Double(tenths) / 10.0
            XCTAssertTrue(valid.contains(HealthKitService.sleepBucket(forHours: hours)), "hours=\(hours)")
        }
    }

    /// Tout nombre de pas doit mapper vers un niveau d'activité valide.
    func testActivityLevel_alwaysValidOption() {
        let valid: Set<String> = ["none", "light", "moderate", "regular", "intense"]
        for steps in stride(from: 0, through: 25000, by: 500) {
            XCTAssertTrue(valid.contains(HealthKitService.activityLevel(forSteps: steps)))
        }
    }
}
