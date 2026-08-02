import XCTest
@testable import HealthMap

// MARK: - Nutrient Engine Tests
// Valide le moteur de score "Faites vos courses" sur 3 profils types :
//  - prouve que le 100/100 est corrigé (un bon profil non supplémenté ne maxe
//    pas tout, car la contribution alimentaire est plafonnée à +18) ;
//  - prouve que les scores sont DIFFÉRENCIÉS (végane B12 bas, poisson -> oméga3,
//    régime pauvre -> fibre/vitC bas) ;
//  - prouve le repli : sans caddie, HealthCalculator garde son calcul.

final class NutrientEngineTests: XCTestCase {

    // MARK: Profils

    /// Omnivore équilibré, actif modéré, non-fumeur, IMC normal.
    private func makeMarc() -> UserProfile {
        var p = UserProfile.empty
        p.age = "35"; p.gender = .homme; p.weight = "75"; p.height = "178"
        p.strengthTraining = "moderate"; p.sleepHours = "7.5"; p.waterIntake = "1.75"
        p.groceries = [
            "bananes": 3, "pommes": 4, "oranges": 3, "epinards": 2, "brocoli": 2,
            "tomates": 3, "carottes": 3, "steak_hache": 1, "escalopes_poulet": 3,
            "saumon": 2, "oeufs": 5, "yaourt_nature": 5, "emmental": 3, "lait": 7,
            "pates": 3, "pain_complet": 5, "lentilles": 2, "flocons_avoine": 4,
            "amandes": 3, "noix": 2, "huile_olive": 7, "avocat": 2,
        ]
        return p
    }

    /// Végane (régime déclaré + caddie 100% végétal), femme jeune.
    private func makeLea() -> UserProfile {
        var p = UserProfile.empty
        p.age = "28"; p.gender = .femme; p.weight = "60"; p.height = "168"
        p.dietType = "vegan"; p.sleepHours = "7.5"; p.waterIntake = "1.75"
        p.groceries = [
            "bananes": 4, "pommes": 3, "oranges": 4, "epinards": 4, "brocoli": 3,
            "tomates": 3, "lentilles": 5, "pois_chiches": 3, "haricots_rouges": 2,
            "tofu": 4, "flocons_avoine": 5, "quinoa": 3, "pain_complet": 5,
            "amandes": 4, "noix": 3, "graines_courge": 2, "graines_chia": 3,
            "boisson_soja": 7, "avocat": 3, "huile_colza": 5,
        ]
        return p
    }

    /// Alimentation pauvre : féculents raffinés + charcuterie, fumeur, ultra-transformés.
    private func makeTom() -> UserProfile {
        var p = UserProfile.empty
        p.age = "40"; p.gender = .homme; p.weight = "95"; p.height = "175"
        p.strengthTraining = "none"; p.smoking = .yes; p.ultraProcessedFrequency = "often"
        p.groceries = [
            "pates": 5, "riz_blanc": 4, "baguette": 7, "jambon_blanc": 3,
            "saucisses": 2, "cordons_bleus": 2, "surimi": 2, "mayonnaise": 3,
            "pate_tartiner": 4, "confiture": 3, "beurre": 5,
        ]
        return p
    }

    // MARK: Tests

    func testAllScoresWithinBounds() {
        for profile in [makeMarc(), makeLea(), makeTom()] {
            let scores = NutrientEngine.nutrientScores(profile: profile)
            XCTAssertEqual(scores.count, GroceryNutrient.allCases.count)
            for (k, v) in scores {
                XCTAssertTrue((0...100).contains(v), "\(k)=\(v) hors [0;100]")
            }
        }
    }

    /// Le fix du 100/100 : un bon profil NON supplémenté ne maxe pas ses nutriments.
    func testBalancedProfileDoesNotMaxEverything() {
        let scores = NutrientEngine.nutrientScores(profile: makeMarc())
        let maxScore = scores.values.max() ?? 0
        XCTAssertLessThan(maxScore, 95,
            "Sans complément, la contribution alimentaire est plafonnée : aucun nutriment ne doit friser 100")
    }

    func testVeganHasVeryLowB12() {
        let vegan = NutrientEngine.nutrientScores(profile: makeLea())
        let omni = NutrientEngine.nutrientScores(profile: makeMarc())
        XCTAssertLessThan(vegan["vitB12"] ?? 100, 30, "Végane sans B12 alimentaire ni complément -> très bas")
        XCTAssertLessThan(vegan["vitB12"] ?? 100, omni["vitB12"] ?? 0)
    }

    func testFishDrivesOmega3() {
        let omni = NutrientEngine.nutrientScores(profile: makeMarc()) // mange du poisson
        let poor = NutrientEngine.nutrientScores(profile: makeTom())  // aucune source oméga-3
        XCTAssertGreaterThan(omni["omega3"] ?? 0, poor["omega3"] ?? 100)
        XCTAssertLessThan(poor["omega3"] ?? 100, 50)
    }

    func testPoorDietHasLowFiberAndVitC() {
        let poor = NutrientEngine.nutrientScores(profile: makeTom())
        XCTAssertLessThan(poor["fiber"] ?? 100, 50)
        XCTAssertLessThan(poor["vitC"] ?? 100, 50)
    }

    func testWellnessScoreIsPlausibleAndOrdered() {
        let marc = NutrientEngine.wellnessScore(profile: makeMarc())
        let tom = NutrientEngine.wellnessScore(profile: makeTom())
        XCTAssertTrue((0...100).contains(marc))
        XCTAssertTrue((0...100).contains(tom))
        XCTAssertGreaterThan(marc, tom, "Profil équilibré non-fumeur > alimentation pauvre fumeur")
    }

    /// Sans caddie, on garde le calcul historique (pas de bascule moteur).
    func testEmptyCaddieKeepsLegacyEngine() {
        var p = UserProfile.empty
        p.age = "35"; p.weight = "75"; p.height = "178"
        XCTAssertTrue(p.groceries.isEmpty)
        let legacy = HealthCalculator.analyzeNutrientScores(profile: p)
        XCTAssertFalse(legacy.isEmpty, "Profil valide sans caddie -> scores legacy non vides")
    }

    // MARK: - Parité avec HealthCalculator (régressions du 2 août 2026)

    /// Le sel iodé est une question du parcours COMPLET. Non renseignée, elle
    /// doit rester neutre : la traiter comme « no » retirait 12 points d'iode
    /// à tout utilisateur Express pour une question jamais posée.
    /// `HealthCalculator` portait déjà ce correctif (5 juillet 2026).
    func testSelIodeNonRenseigneNePenalisePas() {
        var renseigneNon = makeMarc()
        renseigneNon.iodizedSalt = "no"
        var nonRenseigne = makeMarc()
        nonRenseigne.iodizedSalt = ""

        let scoreNon = NutrientEngine.nutrientScores(profile: renseigneNon)["iodine"] ?? 0
        let scoreVide = NutrientEngine.nutrientScores(profile: nonRenseigne)["iodine"] ?? 0

        XCTAssertGreaterThan(
            scoreVide, scoreNon,
            "Sel iodé non renseigné doit être neutre, pas pénalisé comme un « non »."
        )
    }

    /// `sleepDuration` est la clé v6 de `sleepHours`. Les deux étaient scorées
    /// ensemble : « 7.5 » valait +10 au lieu de +5, et comme `sleepHoursDouble`
    /// vaut 7 par défaut, un sommeil NON renseigné offrait +5 gratuits.
    func testSommeilNonRenseigneNeDonnePasDeBonusGratuit() {
        var renseigne = makeMarc()
        renseigne.sleepHours = "7.5"        // palier optimal
        var absent = makeMarc()
        absent.sleepHours = ""              // rien de déclaré
        absent.sleepDuration = ""

        let avec = NutrientEngine.wellnessScore(profile: renseigne)
        let sans = NutrientEngine.wellnessScore(profile: absent)

        XCTAssertGreaterThan(
            avec, sans,
            "Déclarer un bon sommeil doit rapporter plus que ne rien déclarer."
        )
    }
}
