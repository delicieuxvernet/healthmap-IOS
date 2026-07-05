import XCTest
@testable import HealthMap

// MARK: - Cross-Repo Parity (health.js <-> HealthCalculator.swift)
//
// Aucun test ne comparait auparavant les deux implementations : chaque cote
// verifiait des valeurs cablees en dur dans son propre langage, si bien qu'une
// divergence de formule pouvait passer les deux suites de tests en meme temps
// (cas reel : double comptage sommeil/repas cote iOS, corrige 2026-07-05).
//
// Le fixture JSON (Fixtures/health-score-parity.json) est genere par
// `node scripts/generate-health-fixtures.mjs` dans le repo web, en executant
// health.js sur les 3 profils des comptes de test (audit-a/b/c) + un profil
// sentinelle. Ce test construit les MEMES profils en Swift et compare son
// propre calcul aux valeurs "expected" ecrites par health.js — si les deux
// divergent, ce test echoue (au lieu de laisser passer silencieusement).
//
// A regenerer le fixture (cote web) puis re-copier le JSON ici si health.js
// evolue sur calculateHealthScore/analyzeNutrientDeficiencies.
final class CrossRepoParityTests: XCTestCase {

    private struct FixtureEntry: Decodable {
        let healthScore: Int
        let nutrientScores: [String: Int]
    }

    private func loadFixture() throws -> [String: FixtureEntry] {
        guard let url = Bundle(for: CrossRepoParityTests.self)
            .url(forResource: "health-score-parity", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle(for: CrossRepoParityTests.self)
                .url(forResource: "health-score-parity", withExtension: "json")
        else {
            XCTFail("Fixture health-score-parity.json introuvable dans le bundle de tests")
            return [:]
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: FixtureEntry].self, from: data)
    }

    private func assertParity(_ profile: UserProfile, against entry: FixtureEntry, name: String) {
        let iosScore = HealthCalculator.calculateHealthScore(profile: profile)
        XCTAssertEqual(iosScore, entry.healthScore, "\(name): healthScore iOS (\(iosScore)) != health.js (\(entry.healthScore))")

        let iosNutrients = HealthCalculator.analyzeNutrientScores(profile: profile)
        for (nutrient, expected) in entry.nutrientScores {
            guard let actual = iosNutrients[nutrient] else {
                XCTFail("\(name): nutriment \(nutrient) absent du resultat iOS")
                continue
            }
            XCTAssertEqual(actual, expected, "\(name)/\(nutrient): iOS (\(actual)) != health.js (\(expected))")
        }
    }

    // MARK: - Profil A: Thomas, 28 ans, sportif omnivore

    private func thomasProfile() -> UserProfile {
        var p = UserProfile.empty
        p.completed = true
        p.age = "28"; p.gender = .homme; p.height = "180"; p.weight = "75"
        p.weightTrend = "stable"; p.strengthTraining = "regular"; p.indoorWork = "no"
        p.sunExposure = "moderate"; p.skinType = "medium"; p.stressLevel = "relaxed"
        p.sleepHours = "7.5"; p.sleepDuration = "7.5"; p.wakeFeeling = "great"
        p.screenBeforeBed = "short"; p.caffeineIntake = "light"; p.waterIntake = "2.25"
        p.smoking = .no; p.alcohol = "rarely"; p.bloating = "no"; p.antibiotics = "no"
        p.dietType = "omnivore"; p.mealsPerDay = "3"; p.homeCookedPct = "mostly"
        p.cookingMethod = "mixed"; p.vegetableServings = "10"; p.fruitServings = "14"
        p.fattyFish = "3"; p.meatPoultry = "5"; p.eggsPerWeek = "5"; p.dairyServings = "7"
        p.legumesPerWeek = "3"; p.nutsPerWeek = "5"; p.seedsPerDay = "1"
        p.wholegrainPerWeek = "5"; p.breadType = "whole_grain"; p.fermentedFoods = "sometimes"
        p.ultraProcessedFrequency = "rarely"; p.snacking = "parfois"; p.saltLevel = "moderate"
        p.iodizedSalt = "yes"; p.eatLiver = "no"; p.lowCarbDiet = "no"
        p.supplementsCurrent = []; p.symptoms = []; p.medications = []; p.digestiveConditions = []
        return p
    }

    // MARK: - Profil B: Lea, 35 ans, vegetarienne regles abondantes

    private func leaProfile() -> UserProfile {
        var p = UserProfile.empty
        p.completed = true
        p.age = "35"; p.gender = .femme; p.height = "165"; p.weight = "58"
        p.weightTrend = "stable"; p.strengthTraining = "light"; p.indoorWork = "yes"
        p.sunExposure = "very_little"; p.skinType = "fair"; p.stressLevel = "very"
        p.sleepHours = "5.5"; p.sleepDuration = "5.5"; p.wakeFeeling = "bad"
        p.screenBeforeBed = "long"; p.caffeineIntake = "heavy"; p.waterIntake = "0.75"
        p.smoking = .no; p.alcohol = "moderate"; p.bloating = "yes"; p.antibiotics = "no"
        p.dietType = "vegetarien"; p.mealsPerDay = "2"; p.homeCookedPct = "half"
        p.cookingMethod = "boiled"; p.vegetableServings = "3"; p.fruitServings = "4"
        p.fattyFish = "0"; p.meatPoultry = "0"; p.eggsPerWeek = "2"; p.dairyServings = "3"
        p.legumesPerWeek = "1"; p.nutsPerWeek = "1"; p.seedsPerDay = "0"
        p.wholegrainPerWeek = "2"; p.breadType = "white"; p.fermentedFoods = "never"
        p.ultraProcessedFrequency = "often"; p.snacking = "souvent"; p.saltLevel = "moderate"
        p.iodizedSalt = "no"; p.eatLiver = "no"; p.lowCarbDiet = "no"
        p.supplementsCurrent = []; p.symptoms = ["fatigue", "hair_loss"]; p.medications = []
        p.digestiveConditions = []; p.periodFlow = "very_heavy"; p.pregnancyStatus = "na"
        return p
    }

    // MARK: - Profil C: Rene, 67 ans, fumeur PPI+metformin

    private func reneProfile() -> UserProfile {
        var p = UserProfile.empty
        p.completed = true
        p.age = "67"; p.gender = .homme; p.height = "170"; p.weight = "85"
        p.weightTrend = "stable"; p.strengthTraining = "none"; p.indoorWork = "yes"
        p.sunExposure = "none"; p.skinType = "medium"; p.stressLevel = "somewhat"
        p.sleepHours = "5.5"; p.sleepDuration = "5.5"; p.wakeFeeling = "bad"
        p.screenBeforeBed = "very_long"; p.caffeineIntake = "heavy"; p.waterIntake = "0.75"
        p.smoking = .yes; p.alcohol = "regular"; p.bloating = "yes"; p.antibiotics = "yes"
        p.dietType = "omnivore"; p.mealsPerDay = "2"; p.homeCookedPct = "mostly_out"
        p.cookingMethod = "boiled"; p.vegetableServings = "1"; p.fruitServings = "2"
        p.fattyFish = "0"; p.meatPoultry = "3"; p.eggsPerWeek = "2"; p.dairyServings = "2"
        p.legumesPerWeek = "0"; p.nutsPerWeek = "0"; p.seedsPerDay = "0"
        p.wholegrainPerWeek = "0"; p.breadType = "white"; p.fermentedFoods = "never"
        p.ultraProcessedFrequency = "daily"; p.snacking = "souvent"; p.saltLevel = "a_lot"
        p.iodizedSalt = "no"; p.eatLiver = "no"; p.lowCarbDiet = "no"
        p.supplementsCurrent = []; p.symptoms = ["fatigue", "tingling"]
        p.medications = ["ppi", "metformin", "diuretics"]; p.digestiveConditions = []
        return p
    }

    // MARK: - Sentinelle : sleepHours+sleepDuration ET mealsPerDay+mealFrequency
    // renseignes simultanement — detecte un futur double comptage meme si les
    // 3 profils ci-dessus ne le revelent pas.

    private func doubleKeyGuardSentinelProfile() -> UserProfile {
        var p = UserProfile.empty
        p.completed = true
        p.age = "30"; p.gender = .homme; p.height = "175"; p.weight = "70"
        p.strengthTraining = "none"; p.stressLevel = "somewhat"; p.wakeFeeling = "ok"
        p.sleepHours = "7.5"; p.sleepDuration = "7.5"; p.screenBeforeBed = "short"
        p.caffeineIntake = "none"; p.waterIntake = "1.75"; p.smoking = .no
        p.alcohol = "none"; p.bloating = "no"; p.antibiotics = "no"; p.dietType = "omnivore"
        p.mealsPerDay = "3"; p.mealFrequency = "three"; p.ultraProcessedFrequency = "sometimes"
        p.snacking = "sometimes"; p.vegetableServings = "5"; p.fruitServings = "8"
        p.supplementsCurrent = []; p.symptoms = []; p.medications = []; p.digestiveConditions = []
        return p
    }

    // MARK: - Tests

    func testThomasParity() throws {
        let fixture = try loadFixture()
        guard let entry = fixture["thomas"] else { return XCTFail("Entree 'thomas' absente du fixture") }
        assertParity(thomasProfile(), against: entry, name: "thomas")
    }

    func testLeaParity() throws {
        let fixture = try loadFixture()
        guard let entry = fixture["lea"] else { return XCTFail("Entree 'lea' absente du fixture") }
        assertParity(leaProfile(), against: entry, name: "lea")
    }

    func testReneParity() throws {
        let fixture = try loadFixture()
        guard let entry = fixture["rene"] else { return XCTFail("Entree 'rene' absente du fixture") }
        assertParity(reneProfile(), against: entry, name: "rene")
    }

    func testDoubleKeyGuardSentinelParity() throws {
        let fixture = try loadFixture()
        guard let entry = fixture["doubleKeyGuardSentinel"] else { return XCTFail("Entree 'doubleKeyGuardSentinel' absente du fixture") }
        assertParity(doubleKeyGuardSentinelProfile(), against: entry, name: "doubleKeyGuardSentinel")
    }
}
