import XCTest
@testable import HealthMap

// MARK: - Une cause, dépliée (21 sept. 2026)
//
// Ce qu'on regagnerait est le MÊME calcul rejoué sans le facteur — donc borné,
// donc parfois nul. Et un geste n'existe que pour ce qui se change : jamais
// pour le profil, la santé ou un traitement.

final class CauseApportTests: XCTestCase {

    private func contribution(_ libelle: String, _ delta: Int, _ section: SectionQuestionnaire) -> ContributionApport {
        ContributionApport(libelle: libelle, delta: delta, section: section)
    }

    private func detail(_ contributions: [ContributionApport]) -> DetailApport {
        let brut = DetailApport.pointDeDepart + contributions.reduce(0) { $0 + $1.delta }
        return DetailApport(contributions: contributions, score: max(0, min(100, brut)))
    }

    // MARK: Ce qu'on regagnerait

    func testSansUnFreinLeScoreRemonteDeSesPoints() {
        let cafe = contribution("Café ou thé pendant les repas", -12, .nutrition)
        let d = detail([contribution("Règles abondantes", -15, .sante), cafe])
        XCTAssertEqual(d.score, 43)
        XCTAssertEqual(d.scoreSans(cafe), 55)
    }

    func testSansUnAppuiLeScoreBaisse() {
        let legumineuses = contribution("Légumineuses plusieurs fois par semaine", 8, .nutrition)
        let d = detail([legumineuses])
        XCTAssertEqual(d.score, 78)
        XCTAssertEqual(d.scoreSans(legumineuses), 70)
    }

    /// Quand tes réponses pèsent plus que l'échelle, retirer un facteur peut ne
    /// rien changer au score affiché : on ne promet pas des points qui n'existent pas.
    func testLeScoreSimuleResteDansLEchelle() {
        let petit = contribution("Pain blanc", -5, .nutrition)
        let d = detail([contribution("A", -40, .sante), contribution("B", -40, .medical), petit])
        XCTAssertEqual(d.score, 0)
        XCTAssertEqual(d.scoreSans(petit), 0)
    }

    func testLesPointsModifiablesNeComptentQueCeQuiSeChange() {
        let d = detail([contribution("Règles abondantes", -15, .sante),
                        contribution("Café ou thé pendant les repas", -12, .nutrition),
                        contribution("Stress élevé", -8, .modeDeVie),
                        contribution("Plus de 50 ans", -5, .profil),
                        contribution("Viande et œufs réguliers", 6, .nutrition)])
        XCTAssertEqual(d.pointsModifiables, -20)
    }

    // MARK: Le pourquoi, le geste, l'avis

    func testUneHabitudeAUnMecanismeEtUnGeste() {
        let e = CauseApport.explication(pour: contribution("Café ou thé pendant les repas", -12, .nutrition))
        XCTAssertTrue(e.pourquoi.contains("tanins"))
        XCTAssertNotNil(e.geste)
        XCTAssertNil(e.avis)
    }

    /// Un traitement : jamais de geste, et jamais un arrêt de traitement.
    func testUnTraitementRenvoieVersUnProfessionnel() {
        let e = CauseApport.explication(pour: contribution("Metformine", -15, .medical))
        XCTAssertNil(e.geste)
        XCTAssertTrue(e.avis?.contains("Ne modifie jamais un traitement") == true)
    }

    func testLeProfilSitueUnPointDeDepart() {
        let e = CauseApport.explication(pour: contribution("Plus de 65 ans", -5, .profil))
        XCTAssertNil(e.geste)
        XCTAssertNil(e.avis)
        XCTAssertTrue(e.pourquoi.contains("point de départ"))
    }

    func testUnAppuiEstAGarder() {
        XCTAssertTrue(CauseApport.explication(pour: contribution("Oléagineux quotidiens", 6, .nutrition)).pourquoi.contains("À garder"))
        XCTAssertTrue(CauseApport.explication(pour: contribution("Tu prends déjà du fer", 20, .medical)).pourquoi.contains("en tient compte"))
    }

    /// « Ni viande, ni œufs, ni poisson » parle du végétal, pas du poisson gras.
    func testLaFamilleLaPlusSpecifiqueGagne() {
        let e = CauseApport.explication(pour: contribution("Ni viande, ni œufs, ni poisson", -18, .nutrition))
        XCTAssertTrue(e.pourquoi.contains("végétaux"))
    }

    /// Chaque facteur du registre, pour les trois profils de référence, a une
    /// explication ; un geste n'existe que pour les habitudes et l'assiette ;
    /// aucun texte ne porte un mot proscrit.
    func testToutFacteurDuRegistreADeQuoiSExpliquer() {
        let proscrits = ["carence", "diagnostic", "patient", "maladie"]
        for profil in profilsDeReference() {
            for (_, detailApport) in HealthCalculator.registreApports(profile: profil) {
                for facteur in detailApport.contributions {
                    let e = CauseApport.explication(pour: facteur)
                    XCTAssertFalse(e.pourquoi.isEmpty, facteur.libelle)
                    if !CauseApport.seChange(facteur.section) || facteur.delta >= 0 {
                        XCTAssertNil(e.geste, "geste inattendu pour « \(facteur.libelle) »")
                    }
                    let tout = ([e.pourquoi, e.geste, e.avis].compactMap { $0 }).joined(separator: " ").lowercased()
                    for mot in proscrits { XCTAssertFalse(tout.contains(mot), "« \(mot) » dans « \(facteur.libelle) »") }
                }
            }
        }
    }

    /// Léa (végétarienne, règles très abondantes, café, stress), puis la même
    /// sous traitements, puis très supplémentée : de quoi faire parler toutes
    /// les sections du registre, freins et appuis.
    private func profilsDeReference() -> [UserProfile] {
        var lea = UserProfile.empty
        lea.completed = true
        lea.age = "35"; lea.gender = .femme; lea.height = "165"; lea.weight = "58"
        lea.weightTrend = "stable"; lea.strengthTraining = "light"; lea.indoorWork = "yes"
        lea.sunExposure = "very_little"; lea.skinType = "fair"; lea.stressLevel = "very"
        lea.sleepHours = "5.5"; lea.sleepDuration = "5.5"; lea.wakeFeeling = "bad"
        lea.screenBeforeBed = "long"; lea.caffeineIntake = "heavy"; lea.waterIntake = "0.75"
        lea.smoking = .no; lea.alcohol = "moderate"; lea.bloating = "yes"; lea.antibiotics = "no"
        lea.dietType = "vegetarien"; lea.mealsPerDay = "2"; lea.homeCookedPct = "half"
        lea.cookingMethod = "boiled"; lea.vegetableServings = "3"; lea.fruitServings = "4"
        lea.fattyFish = "0"; lea.meatPoultry = "0"; lea.eggsPerWeek = "2"; lea.dairyServings = "3"
        lea.legumesPerWeek = "1"; lea.nutsPerWeek = "1"; lea.seedsPerDay = "0"
        lea.wholegrainPerWeek = "2"; lea.breadType = "white"; lea.fermentedFoods = "never"
        lea.ultraProcessedFrequency = "often"; lea.snacking = "souvent"; lea.saltLevel = "moderate"
        lea.iodizedSalt = "no"; lea.eatLiver = "no"; lea.lowCarbDiet = "no"
        lea.supplementsCurrent = []; lea.symptoms = ["fatigue", "hair_loss"]; lea.medications = []
        lea.digestiveConditions = []; lea.periodFlow = "very_heavy"; lea.pregnancyStatus = "na"

        var sousTraitements = lea
        sousTraitements.medications = ["ppi", "metformin", "oral_contraceptive"]

        var supplementee = lea
        supplementee.supplementsCurrent = ["vitD", "omega3", "magnesium", "iron", "b12", "zinc"]

        return [lea, sousTraitements, supplementee]
    }

    // MARK: Le nom dans la phrase

    func testLePossessifSuitLArticle() {
        XCTAssertEqual(NomApport.possessif(NomApport.avecArticle(id: "iron", repli: "Fer")), "ton fer")
        XCTAssertEqual(NomApport.possessif(NomApport.avecArticle(id: "vitD", repli: "")), "ta vitamine D")
        XCTAssertEqual(NomApport.possessif(NomApport.avecArticle(id: "omega3", repli: "")), "tes oméga-3")
        XCTAssertEqual(NomApport.possessif(NomApport.avecArticle(id: "iodine", repli: "")), "ton iode")
    }
}
