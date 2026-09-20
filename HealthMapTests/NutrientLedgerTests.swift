import XCTest
@testable import HealthMap

// MARK: - Registre des apports
//
// La parite arithmetique avec health.js est deja verrouillee par
// CrossRepoParityTests, qui compare `analyzeNutrientScores` (desormais une
// projection du registre) aux valeurs figees du fixture. Ce fichier teste ce
// que la parite ne voit pas : les invariants dont depend l'affichage de
// l'anneau et de la cascade.
final class NutrientLedgerTests: XCTestCase {

    private let motsProscrits = ["carence", "diagnostic", "patient", "maladie"]

    // MARK: - Profils

    /// Lea, 35 ans, vegetarienne, regles tres abondantes (compte audit-b).
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

    /// Profil deja tres supplemente : les appuis regonflent le score au point
    /// que les freins nommes ne tiennent plus dans l'arc manquant. C'est le cas
    /// limite ou l'anneau doit comprimer au prorata sans jamais depasser 100.
    private func profilTresSupplemente() -> UserProfile {
        var p = leaProfile()
        p.supplementsCurrent = ["vitD", "omega3", "magnesium", "iron", "b12", "zinc", "multivitamin"]
        return p
    }

    /// Profil hors bornes : le registre doit se taire, comme le calcul de score.
    private func profilHorsBornes() -> UserProfile {
        var p = leaProfile()
        p.weight = "0"
        return p
    }

    private var profils: [(String, UserProfile)] {
        [
            ("lea", leaProfile()),
            ("tres supplemente", profilTresSupplemente()),
            ("vide", UserProfile.empty),
        ]
    }

    // MARK: - Le registre EST le score

    /// Garde-fou anti-refork : si quelqu'un redonne un calcul autonome a
    /// `analyzeNutrientScores`, les deux se mettront a diverger en silence.
    func testLeScoreEstExactementLaProjectionDuRegistre() {
        for (nom, profil) in profils {
            let registre = HealthCalculator.registreApports(profile: profil)
            let scores = HealthCalculator.analyzeNutrientScores(profile: profil)
            XCTAssertEqual(
                registre.mapValues(\.score), scores,
                "\(nom) : le registre et analyzeNutrientScores ont diverge"
            )
        }
    }

    func testProfilHorsBornesRendUnRegistreVide() {
        XCTAssertTrue(HealthCalculator.registreApports(profile: profilHorsBornes()).isEmpty)
    }

    func testTousLesApportsSontPresents() {
        let registre = HealthCalculator.registreApports(profile: leaProfile())
        for n in NutrientData.all {
            XCTAssertNotNil(registre[n.id.rawValue], "apport \(n.id.rawValue) absent du registre")
        }
    }

    // MARK: - Invariants de la cascade

    func testLaCascadeRetombeSurLeTotalBrut() {
        for (nom, profil) in profils {
            for (id, detail) in HealthCalculator.registreApports(profile: profil) {
                let somme = detail.depart + detail.contributions.reduce(0) { $0 + $1.delta }
                XCTAssertEqual(somme, detail.brut, "\(nom)/\(id) : la cascade ne retombe pas sur brut")
                XCTAssertEqual(
                    detail.score, max(0, min(100, detail.brut)),
                    "\(nom)/\(id) : le score n'est pas le brut borne"
                )
                XCTAssertEqual(
                    detail.estBorne, detail.brut != detail.score,
                    "\(nom)/\(id) : estBorne ne dit pas la verite"
                )
            }
        }
    }

    func testLeTriConserveToutesLesContributions() {
        for (nom, profil) in profils {
            for (id, detail) in HealthCalculator.registreApports(profile: profil) {
                XCTAssertEqual(
                    detail.contributionsTriees.count, detail.contributions.count,
                    "\(nom)/\(id) : le tri de la cascade perd des lignes"
                )
                XCTAssertEqual(
                    detail.contributionsTriees.reduce(0) { $0 + $1.delta },
                    detail.contributions.reduce(0) { $0 + $1.delta },
                    "\(nom)/\(id) : le tri de la cascade change le total"
                )
            }
        }
    }

    func testChaqueContributionEstNommeeEtPese() {
        for (nom, profil) in profils {
            for (id, detail) in HealthCalculator.registreApports(profile: profil) {
                for c in detail.contributions {
                    XCTAssertFalse(c.libelle.isEmpty, "\(nom)/\(id) : contribution sans libelle")
                    XCTAssertNotEqual(c.delta, 0, "\(nom)/\(id) : contribution a zero point — « \(c.libelle) »")
                }
            }
        }
    }

    // MARK: - Invariant de l'anneau

    /// L'anneau ne doit JAMAIS laisser un trou ni deborder : c'est ce qui
    /// autorise a dire a la personne que les parts sont celles de son bilan.
    func testLAnneauFermeToujoursACent() {
        for (nom, profil) in profils {
            for (id, detail) in HealthCalculator.registreApports(profile: profil) {
                let total = detail.segments.reduce(0) { $0 + $1.valeur }
                XCTAssertEqual(total, 100, "\(nom)/\(id) : l'anneau totalise \(total) au lieu de 100")
                for part in detail.segments {
                    XCTAssertGreaterThan(part.valeur, 0, "\(nom)/\(id) : part vide « \(part.libelle) »")
                }
            }
        }
    }

    /// Cas courant : tant que les freins tiennent dans l'arc manquant, chaque
    /// part vaut EXACTEMENT son poids en points. C'est la promesse faite a
    /// l'ecran, elle ne doit pas se perdre dans un arrondi.
    func testLesPartsValentLesPointsQuandEllesTiennent() {
        let registre = HealthCalculator.registreApports(profile: leaProfile())
        for (id, detail) in registre {
            let poids = detail.freins.reduce(0) { $0 + abs($1.delta) }
            guard poids <= max(0, 100 - detail.score) else { continue }
            for frein in detail.freins {
                let part = detail.segments.first { $0.libelle == frein.libelle }
                XCTAssertEqual(
                    part?.valeur, abs(frein.delta),
                    "\(id) : la part « \(frein.libelle) » ne vaut pas ses points"
                )
            }
        }
    }

    func testLaPartCouverteVautLeScore() {
        for (nom, profil) in profils {
            for (id, detail) in HealthCalculator.registreApports(profile: profil) where detail.score > 0 {
                let couvert = detail.segments.first { $0.libelle == "Couvert" }
                XCTAssertEqual(couvert?.valeur, detail.score, "\(nom)/\(id) : la part couverte ment")
            }
        }
    }

    // MARK: - Ce que la personne lit

    func testLesFreinsDeLeaSontCeuxQuElleADeclares() {
        let registre = HealthCalculator.registreApports(profile: leaProfile())
        guard let fer = registre["iron"] else { return XCTFail("apport fer absent") }

        let libelles = Set(fer.contributions.map(\.libelle))
        for attendu in ["Règles très abondantes", "Pas de viande", "Alimentation végétarienne"] {
            XCTAssertTrue(libelles.contains(attendu), "le fer de Léa devrait nommer « \(attendu) » — trouvé : \(libelles)")
        }

        guard let vitD = registre["vitD"] else { return XCTFail("apport vitamine D absent") }
        XCTAssertTrue(
            Set(vitD.contributions.map(\.libelle)).contains("Travail en intérieur"),
            "la vitamine D de Léa devrait nommer son travail en intérieur"
        )
    }

    func testLesLibellesRespectentLeVocabulaire() {
        var vus = Set<String>()
        for (_, profil) in profils {
            for (_, detail) in HealthCalculator.registreApports(profile: profil) {
                for c in detail.contributions { vus.insert(c.libelle) }
                for part in detail.segments { vus.insert(part.libelle) }
            }
        }
        XCTAssertFalse(vus.isEmpty, "aucun libelle collecte — le test ne verifie rien")
        for libelle in vus {
            let bas = libelle.lowercased()
            for mot in motsProscrits {
                XCTAssertFalse(bas.contains(mot), "mot proscrit « \(mot) » dans le libelle « \(libelle) »")
            }
        }
    }
}
