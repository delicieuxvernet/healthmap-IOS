import XCTest
@testable import HealthMap

// MARK: - Teaser Engine Tests (Lot E — questionnaire premium & engageant)
// Valide les règles déterministes des teasers : déclencheurs, neutralisation
// par les compléments déjà pris, ordre de priorité, et silence sur profil vide.

final class TeaserEngineTests: XCTestCase {

    // MARK: - Profil vide

    /// Un profil vierge ne doit déclencher AUCUN teaser (les valeurs par
    /// défaut — dietType "omnivore", periodFlow "na" — ne sont pas des indices).
    func testEmptyProfile_producesNoTeasers() {
        let teasers = TeaserEngine.teasers(for: .empty)
        XCTAssertTrue(teasers.isEmpty, "Empty profile should not trigger any teaser, got: \(teasers.map(\.id))")
    }

    // MARK: - Vitamine D

    /// Travail intérieur + soleil rare → teaser vitamine D.
    func testVitD_firesOnIndoorWorkAndLowSun() {
        var p = UserProfile.empty
        p.indoorWork = "yes"
        p.sunExposure = "very_little"
        XCTAssertEqual(TeaserEngine.teasers(for: p).first?.id, "vitD")
    }

    /// Soleil suffisant → pas de teaser vitamine D.
    func testVitD_doesNotFireWithEnoughSun() {
        var p = UserProfile.empty
        p.indoorWork = "yes"
        p.sunExposure = "moderate"
        XCTAssertFalse(TeaserEngine.teasers(for: p).contains(where: { $0.id == "vitD" }))
    }

    /// Complément vitamine D déjà pris → teaser neutralisé.
    func testVitD_suppressedBySupplement() {
        var p = UserProfile.empty
        p.indoorWork = "yes"
        p.sunExposure = "none"
        p.supplementsCurrent = ["vitD"]
        XCTAssertFalse(TeaserEngine.teasers(for: p).contains(where: { $0.id == "vitD" }))
    }

    /// La multivitamine couvre tous les nutriments (convention RedFlagDetector).
    func testMultivitamin_suppressesAllTeasers() {
        var p = UserProfile.empty
        p.indoorWork = "yes"
        p.sunExposure = "none"
        p.stressLevel = "explode"
        p.wakeFeeling = "terrible"
        p.dietType = "vegan"
        p.fattyFish = "0"
        p.supplementsCurrent = ["multivitamin"]
        XCTAssertTrue(TeaserEngine.teasers(for: p).isEmpty)
    }

    // MARK: - Magnésium

    /// Stress élevé ("very" / "explode") → teaser magnésium.
    func testMagnesium_firesOnHighStress() {
        var p = UserProfile.empty
        p.stressLevel = "very"
        XCTAssertEqual(TeaserEngine.teasers(for: p).first?.id, "magnesium")
    }

    /// Stress modéré → pas de teaser magnésium.
    func testMagnesium_doesNotFireOnModerateStress() {
        var p = UserProfile.empty
        p.stressLevel = "somewhat"
        XCTAssertTrue(TeaserEngine.teasers(for: p).isEmpty)
    }

    // MARK: - Fer / B12

    /// Réveil difficile → teaser fer.
    func testIron_firesOnBadWakeFeeling() {
        var p = UserProfile.empty
        p.wakeFeeling = "bad"
        XCTAssertEqual(TeaserEngine.teasers(for: p).first?.id, "iron")
    }

    /// Fatigue persistante déclarée en symptôme → teaser fer.
    func testIron_firesOnChronicFatigueSymptom() {
        var p = UserProfile.empty
        p.symptoms = ["fatigue_chronic"]
        XCTAssertEqual(TeaserEngine.teasers(for: p).first?.id, "iron")
    }

    /// Complément fer déjà pris → teaser neutralisé.
    func testIron_suppressedBySupplement() {
        var p = UserProfile.empty
        p.wakeFeeling = "terrible"
        p.supplementsCurrent = ["iron"]
        XCTAssertTrue(TeaserEngine.teasers(for: p).isEmpty)
    }

    // MARK: - B12

    /// Régimes végétarien ET végan déclenchent le teaser B12.
    func testB12_firesForVegetarianAndVegan() {
        for diet in ["vegetarien", "vegan"] {
            var p = UserProfile.empty
            p.dietType = diet
            XCTAssertEqual(TeaserEngine.teasers(for: p).first?.id, "b12", "Diet \(diet) should trigger b12 teaser")
        }
    }

    /// Omnivore (défaut) → pas de teaser B12.
    func testB12_doesNotFireForOmnivore() {
        XCTAssertFalse(TeaserEngine.teasers(for: .empty).contains(where: { $0.id == "b12" }))
    }

    /// Complément B12 déjà pris → teaser neutralisé.
    func testB12_suppressedBySupplement() {
        var p = UserProfile.empty
        p.dietType = "vegan"
        p.supplementsCurrent = ["b12"]
        XCTAssertTrue(TeaserEngine.teasers(for: p).isEmpty)
    }

    // MARK: - Oméga-3

    /// Question non répondue (chaîne vide) → la règle NE tire PAS, même si
    /// fattyFishInt vaut 0 par défaut.
    func testOmega3_requiresAnsweredQuestion() {
        XCTAssertFalse(TeaserEngine.teasers(for: .empty).contains(where: { $0.id == "omega3" }))
    }

    /// Zéro poisson gras déclaré → teaser oméga-3.
    func testOmega3_firesOnZeroFattyFish() {
        var p = UserProfile.empty
        p.fattyFish = "0"
        XCTAssertEqual(TeaserEngine.teasers(for: p).first?.id, "omega3")
    }

    /// Consommation présente → pas de teaser.
    func testOmega3_doesNotFireWhenEating() {
        var p = UserProfile.empty
        p.fattyFish = "2"
        XCTAssertTrue(TeaserEngine.teasers(for: p).isEmpty)
    }

    // MARK: - Priorité & déterminisme

    /// Plusieurs règles actives → ordre de priorité stable
    /// (vitD > magnesium > iron > b12 > omega3) et résultat reproductible.
    func testPriorityOrder_isDeterministic() {
        var p = UserProfile.empty
        p.indoorWork = "yes"
        p.sunExposure = "none"
        p.stressLevel = "explode"
        p.wakeFeeling = "terrible"
        p.dietType = "vegan"
        p.fattyFish = "0"

        let ids = TeaserEngine.teasers(for: p).map(\.id)
        XCTAssertEqual(ids, ["vitD", "magnesium", "iron", "b12", "omega3"])
        XCTAssertEqual(ids, TeaserEngine.teasers(for: p).map(\.id), "Same profile must always produce the same teasers")
    }

    // MARK: - Conformité langage

    /// Aucun message de teaser ne doit contenir de vocabulaire interdit
    /// (même liste que VoiceComplianceTests) ni de caractère accentué
    /// (convention des libellés questionnaire).
    func testMessages_useCompliantAccentFreeLanguage() {
        var p = UserProfile.empty
        p.indoorWork = "yes"
        p.sunExposure = "none"
        p.stressLevel = "explode"
        p.wakeFeeling = "terrible"
        p.dietType = "vegan"
        p.fattyFish = "0"

        let forbidden = ["carence", "diagnostic", "patient", "maladie"]
        let accents = CharacterSet(charactersIn: "àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ")

        for teaser in TeaserEngine.teasers(for: p) {
            let lower = teaser.message.lowercased()
            for word in forbidden {
                XCTAssertFalse(lower.contains(word), "Teaser \(teaser.id) contains forbidden word \"\(word)\"")
            }
            XCTAssertNil(
                teaser.message.rangeOfCharacter(from: accents),
                "Teaser \(teaser.id) should not contain accented characters: \(teaser.message)"
            )
        }
    }
}
