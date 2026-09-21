import XCTest
@testable import HealthMap

// MARK: - Le registre du moteur « caddie » (22 sept. 2026)
//
// Le registre est un MIROIR de `NutrientEngine.applyNonFoodModifiers`. Ce
// fichier est son verrou : pour des profils qui font parler toutes les
// branches, le total nommé doit retomber EXACTEMENT sur le score du moteur,
// sans aucune ligne d'écart. Une pénalité ajoutée d'un seul côté le fait
// échouer — c'est voulu.

final class NutrientEngineLedgerTests: XCTestCase {

    private let courses: [String: Int] = [
        "bananes": 3, "pommes": 4, "oranges": 3, "epinards": 2, "brocoli": 2, "tomates": 3,
        "escalopes_poulet": 3, "saumon": 2, "oeufs": 5, "yaourt_nature": 5, "lait": 7,
        "pates": 3, "pain_complet": 5, "lentilles": 2, "amandes": 3,
    ]

    private func base() -> UserProfile {
        var p = UserProfile.empty
        p.age = "35"; p.gender = .homme; p.weight = "75"; p.height = "178"
        p.sleepHours = "7.5"; p.waterIntake = "1.75"
        p.groceries = courses
        return p
    }

    /// Des profils qui, ensemble, passent par chaque branche du moteur.
    private func profils() -> [(String, UserProfile)] {
        var lea = base()
        lea.age = "32"; lea.gender = .femme; lea.weight = "58"; lea.height = "165"
        lea.indoorWork = "yes"; lea.sunExposure = "very_little"; lea.skinType = "olive"
        lea.stressLevel = "very"; lea.sleepHours = "5.5"; lea.screenBeforeBed = "long"
        lea.caffeineIntake = "heavy"; lea.caffeineTiming = "with_meals"; lea.waterIntake = "0.75"
        lea.dietType = "vegetarien"; lea.cookingMethod = "boiled"; lea.homeCookedPct = "mostly_out"
        lea.fermentedFoods = "never"; lea.ultraProcessedFrequency = "often"; lea.snacking = "often"
        lea.iodizedSalt = "no"; lea.periodFlow = "very_heavy"; lea.bloating = "yes"; lea.antibiotics = "yes"
        lea.groceries = ["pates": 5, "baguette": 7, "pommes": 2]

        var rene = base()
        rene.age = "72"; rene.weight = "98"; rene.height = "170"
        rene.smoking = .yes; rene.alcohol = "heavy"; rene.lowCarbDiet = "yes"
        rene.medications = ["ppi", "metformin", "diuretics"]
        rene.digestiveConditions = ["acid_reflux", "celiac"]
        rene.surgicalHistory = ["bariatric"]; rene.allergies = ["nuts"]
        rene.sunExposure = "none"; rene.skinType = "dark"; rene.stressLevel = "explode"

        var ines = base()
        ines.age = "29"; ines.gender = .femme; ines.weight = "47"; ines.height = "170"
        ines.dietType = "vegan"; ines.pregnancyStatus = "pregnant"; ines.periodFlow = "heavy"
        ines.strengthTraining = "intense"; ines.alcohol = "regular"; ines.stressLevel = "zen"
        ines.sunExposure = "plenty"; ines.skinType = "fair"
        ines.iodizedSalt = "yes"; ines.saltLevel = "moderate"
        ines.medications = ["oral_contraceptive"]
        ines.supplementsCurrent = ["vitD", "omega3", "magnesium", "iron", "b12", "zinc", "folate", "probiotics", "multivitamin"]

        var paul = base()
        paul.age = "55"; paul.alcohol = "moderate"; paul.caffeineIntake = "moderate"
        paul.stressLevel = "somewhat"; paul.sunExposure = "moderate"; paul.skinType = "medium"
        paul.pregnancyStatus = "breastfeeding"; paul.dietType = "sans_gluten"
        paul.iodizedSalt = "yes"; paul.saltLevel = "none"
        paul.groceries = [:]
        paul.groceries["saumon"] = 9

        return [("marc", base()), ("lea", lea), ("rene", rene), ("ines", ines), ("paul", paul)]
    }

    // MARK: Le verrou

    func testLeTotalNommeRetombeSurLeScoreDuMoteur() {
        for (nom, profil) in profils() {
            let registre = NutrientEngine.registreApports(profile: profil)
            let scores = NutrientEngine.nutrientScores(profile: profil)
            XCTAssertEqual(registre.mapValues(\.score), scores, nom)
            XCTAssertEqual(registre.count, GroceryNutrient.allCases.count, nom)
            for (id, detail) in registre {
                XCTAssertEqual(detail.brut, NutrientEngine.scoresBruts(profile: profil)[id], "\(nom) · \(id)")
            }
        }
    }

    /// Aucune ligne d'écart : chaque point du moteur porte un nom.
    func testAucunPointNEstAnonyme() {
        for (nom, profil) in profils() {
            for (id, detail) in NutrientEngine.registreApports(profile: profil) {
                let ecart = detail.contributions.first { $0.libelle == NutrientEngine.libelleEcart }
                XCTAssertNil(ecart, "\(nom) · \(id) : \(ecart?.delta ?? 0) points sans nom — le registre a dérivé du moteur")
            }
        }
    }

    // MARK: Le branchement (ce que voyait Arthur)

    /// Avec un caddie rempli, l'anneau a désormais ses zones grises : des
    /// freins nommés, donc des parts de cause.
    func testUnCaddieRempliDonneDesCausesALAnneau() {
        let lea = profils()[1].1
        XCTAssertFalse(lea.groceries.isEmpty)
        let fer = HealthCalculator.registreApports(profile: lea)["iron"]
        XCTAssertNotNil(fer)
        XCTAssertGreaterThanOrEqual(fer?.freins.count ?? 0, 3)
        let causes = (fer?.parts ?? []).filter {
            if case .cause = $0.genre { return $0.valeur > 0 }
            return false
        }
        XCTAssertFalse(causes.isEmpty, "l'anneau du fer n'a aucune zone grise")
        XCTAssertEqual(fer?.parts.reduce(0) { $0 + $1.valeur }, 100)
    }

    func testLesCoursesOntLeurLigne() {
        let lea = profils()[1].1
        let vitD = NutrientEngine.registreApports(profile: lea)["vitD"]
        XCTAssertTrue(vitD?.contributions.contains { $0.libelle == "Aucune source dans tes courses" && $0.delta == -30 } == true)
        XCTAssertEqual(NutrientEngine.libelleDesCourses(delta: -5), "Peu de sources dans tes courses")
        XCTAssertEqual(NutrientEngine.libelleDesCourses(delta: 18), "Tes courses en apportent beaucoup")
    }

    /// Profil hors bornes : le registre se tait, comme le moteur.
    func testHorsBornesLeRegistreSeTait() {
        var p = base()
        p.weight = "5"
        XCTAssertTrue(NutrientEngine.registreApports(profile: p).isEmpty)
    }

    /// Aucun libellé ne porte un mot proscrit, et chacun a de quoi s'expliquer.
    func testChaqueLibelleSExplique() {
        let proscrits = ["carence", "diagnostic", "patient", "maladie"]
        for (_, profil) in profils() {
            for (_, detail) in NutrientEngine.registreApports(profile: profil) {
                for facteur in detail.contributions {
                    for mot in proscrits { XCTAssertFalse(facteur.libelle.lowercased().contains(mot), facteur.libelle) }
                    XCTAssertFalse(CauseApport.explication(pour: facteur).pourquoi.isEmpty, facteur.libelle)
                }
            }
        }
    }
}
