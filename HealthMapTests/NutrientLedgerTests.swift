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
    /// limite ou l'anneau doit tronquer sans jamais depasser 100.
    private func profilTresSupplemente() -> UserProfile {
        var p = leaProfile()
        p.supplementsCurrent = ["vitD", "omega3", "magnesium", "iron", "b12", "zinc", "multivitamin"]
        return p
    }

    /// Operation de l'estomac + allergie aux fruits a coque : le bloc partage
    /// avec NutrientEngine (`applyMedicalHistoryPenalties`) doit traverser le
    /// registre sans y etre recopie.
    private func profilAvecAntecedents() -> UserProfile {
        var p = leaProfile()
        p.surgicalHistory = ["bariatric"]
        p.allergies = ["nuts"]
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
            ("avec antecedents", profilAvecAntecedents()),
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
        XCTAssertTrue(HealthCalculator.analyzeNutrientScores(profile: profilHorsBornes()).isEmpty)
    }

    func testTousLesApportsSontPresents() {
        let registre = HealthCalculator.registreApports(profile: leaProfile())
        for n in NutrientData.all {
            XCTAssertNotNil(registre[n.id.rawValue], "apport \(n.id.rawValue) absent du registre")
        }
    }

    // MARK: - Le bloc partage avec NutrientEngine

    /// Le registre n'a pas le droit de recopier ces penalites : il execute le
    /// bloc partage et en lit l'effet. Pour chaque apport, la ligne agregee du
    /// registre doit valoir EXACTEMENT ce que le bloc retire a un score nu.
    func testLesAntecedentsTraversentLeRegistreSansEtreRecopies() {
        let profil = profilAvecAntecedents()
        let libelle = "Antécédents, opérations et allergies"

        var temoin: [String: Int] = [:]
        for n in NutrientData.all { temoin[n.id.rawValue] = 0 }
        NutrientEngine.applyMedicalHistoryPenalties(&temoin, profile: profil)
        XCTAssertTrue(temoin.values.contains { $0 != 0 }, "le profil de test ne declenche aucune penalite — le test ne verifie rien")

        let registre = HealthCalculator.registreApports(profile: profil)
        for n in NutrientData.all {
            let id = n.id.rawValue
            let ligne = registre[id]?.contributions.first { $0.libelle == libelle }
            XCTAssertEqual(ligne?.delta ?? 0, temoin[id] ?? 0, "\(id) : la ligne agregee ne vaut pas l'effet du bloc partage")
            if let ligne { XCTAssertEqual(ligne.section, .medical) }
        }

        // Et le profil sans antecedent ne porte pas la ligne du tout.
        for (id, detail) in HealthCalculator.registreApports(profile: leaProfile()) {
            XCTAssertFalse(detail.contributions.contains { $0.libelle == libelle }, "\(id) : ligne d'antecedents sans antecedent")
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
                XCTAssertEqual(
                    detail.brut + detail.correctionBornage, detail.score,
                    "\(nom)/\(id) : la ligne « ramene dans l'echelle » ne ferme pas la cascade"
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
                let freins = detail.freins.map(\.delta)
                XCTAssertEqual(freins, freins.sorted(), "\(nom)/\(id) : les freins ne sont pas du plus lourd au plus leger")
            }
        }
    }

    func testChaqueContributionEstNommeeEtPese() {
        for (nom, profil) in profils {
            for (id, detail) in HealthCalculator.registreApports(profile: profil) {
                for c in detail.contributions {
                    XCTAssertFalse(c.libelle.isEmpty, "\(nom)/\(id) : contribution sans libelle")
                    XCTAssertNotEqual(c.delta, 0, "\(nom)/\(id) : contribution a zero point — « \(c.libelle) »")
                    XCTAssertTrue(c.provenance.hasPrefix("déclaré dans "), "\(nom)/\(id) : provenance mal formee")
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
                let parts = detail.parts
                let total = parts.reduce(0) { $0 + $1.valeur }
                XCTAssertEqual(total, 100, "\(nom)/\(id) : l'anneau totalise \(total) au lieu de 100")
                for part in parts {
                    XCTAssertGreaterThanOrEqual(part.valeur, 0, "\(nom)/\(id) : part negative « \(part.libelle) »")
                }
                XCTAssertEqual(parts.first?.genre, .couvert, "\(nom)/\(id) : la premiere part n'est pas la part couverte")
                XCTAssertEqual(parts.last?.genre, .innomme, "\(nom)/\(id) : la derniere part n'est pas « autres facteurs »")
            }
        }
    }

    /// Une part de frein ne vaut jamais PLUS que ses points : quand l'arc
    /// manquant est plein, elle se tronque, elle ne s'invente pas.
    func testUnePartNeDepasseJamaisSesPoints() {
        for (nom, profil) in profils {
            for (id, detail) in HealthCalculator.registreApports(profile: profil) {
                for (rang, frein) in detail.freins.enumerated() {
                    let part = detail.parts.first { $0.id == frein.id }
                    XCTAssertNotNil(part, "\(nom)/\(id) : frein « \(frein.libelle) » sans part")
                    XCTAssertLessThanOrEqual(part?.valeur ?? 0, abs(frein.delta), "\(nom)/\(id) : la part « \(frein.libelle) » vaut plus que ses points")
                    XCTAssertEqual(part?.genre, .cause(rang: rang), "\(nom)/\(id) : rang de la part « \(frein.libelle) »")
                }
            }
        }
    }

    /// Cas courant : tant que les freins tiennent dans l'arc manquant, chaque
    /// part vaut EXACTEMENT son poids en points. C'est la promesse faite a
    /// l'ecran, elle ne doit pas se perdre.
    func testLesPartsValentLesPointsQuandEllesTiennent() {
        let registre = HealthCalculator.registreApports(profile: leaProfile())
        for (id, detail) in registre {
            let poids = detail.freins.reduce(0) { $0 + abs($1.delta) }
            guard poids <= max(0, 100 - detail.score) else { continue }
            for frein in detail.freins {
                let part = detail.parts.first { $0.id == frein.id }
                XCTAssertEqual(part?.valeur, abs(frein.delta), "\(id) : la part « \(frein.libelle) » ne vaut pas ses points")
            }
        }
    }

    func testLaPartCouverteVautLeScore() {
        for (nom, profil) in profils {
            for (id, detail) in HealthCalculator.registreApports(profile: profil) {
                let couvert = detail.parts.first { $0.genre == .couvert }
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
        let regles = fer.contributions.first { $0.libelle == "Règles très abondantes" }
        XCTAssertEqual(regles?.section, .sante, "les regles abondantes viennent de la section Santé")

        // Léa a dit combien de soleil elle prend : sa réponse compte, seule. Le
        // travail en intérieur ne se compte plus en plus (22 sept. 2026).
        guard let vitD = registre["vitD"] else { return XCTFail("apport vitamine D absent") }
        let soleil = vitD.contributions.first { $0.libelle == "Très peu de soleil" }
        XCTAssertNotNil(soleil, "la vitamine D de Léa devrait nommer son peu de soleil")
        XCTAssertEqual(soleil?.section, .modeDeVie)
        XCTAssertFalse(vitD.contributions.contains { $0.libelle == "Travail en intérieur" },
                       "le soleil ne se compte qu'une fois")
    }

    func testLesLibellesRespectentLeVocabulaire() {
        var vus = Set<String>()
        for (_, profil) in profils {
            for (_, detail) in HealthCalculator.registreApports(profile: profil) {
                for c in detail.contributions { vus.insert(c.libelle); vus.insert(c.provenance) }
                for part in detail.parts { vus.insert(part.libelle) }
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
