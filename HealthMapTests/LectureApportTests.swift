import XCTest
@testable import HealthMap

// MARK: - La fiche d'un apport, lue dans le bon ordre (21 sept. 2026)
//
// Le verdict, les causes qui pèsent, les gestes : tout ce que la fiche affiche
// en premier se calcule dans `LectureApport`. Ces tests tiennent les phrases
// (accords compris) et la règle des gestes : seulement ce qui se change, un
// geste par famille, et jamais un chiffre quand il n'y a rien à annoncer.

final class LectureApportTests: XCTestCase {

    private func facteur(_ libelle: String, _ delta: Int, _ section: SectionQuestionnaire) -> ContributionApport {
        ContributionApport(libelle: libelle, delta: delta, section: section)
    }

    private func detail(_ facteurs: [ContributionApport]) -> DetailApport {
        let brut = DetailApport.pointDeDepart + facteurs.reduce(0) { $0 + $1.delta }
        return DetailApport(contributions: facteurs, score: max(0, min(100, brut)))
    }

    /// Léa : 70 − 15 − 12 − 8 = 35.
    private var ferDeLea: DetailApport {
        detail([
            facteur("Café ou thé pendant les repas", -12, .modeDeVie),
            facteur("Règles abondantes", -15, .sante),
            facteur("Alimentation végétarienne", -8, .nutrition),
        ])
    }

    // MARK: Le verdict

    func testLeVerdictNommeLEtatPuisLaPremiereCause() {
        XCTAssertEqual(LectureApport.verdict(id: "iron", nom: "Fer", detail: ferDeLea),
                       "Ton fer est bas. Première cause : règles abondantes.")
    }

    func testLeVerdictSAccorde() {
        let bas = detail([facteur("Travail en intérieur", -35, .modeDeVie)])
        XCTAssertEqual(LectureApport.verdict(id: "vitD", nom: "Vitamine D", detail: bas),
                       "Ta vitamine D est basse. Première cause : travail en intérieur.")
        let justes = detail([facteur("Pas de poisson gras", -15, .nutrition)])
        XCTAssertEqual(LectureApport.verdict(id: "omega3", nom: "Oméga-3", detail: justes),
                       "Tes oméga-3 sont un peu justes. Première cause : pas de poisson gras.")
        let basses = detail([facteur("Pain blanc", -40, .nutrition)])
        XCTAssertEqual(LectureApport.verdict(id: "fiber", nom: "Fibres", detail: basses),
                       "Tes fibres sont basses. Première cause : pain blanc.")
        XCTAssertEqual(LectureApport.verdict(id: "iodine", nom: "Iode", detail: justes),
                       "Ton iode est un peu juste. Première cause : pas de poisson gras.")
    }

    /// Couvert, ou sans cause nommée : la phrase s'arrête au constat.
    func testSansCauseLeVerdictSArreteAuConstat() {
        let couvert = detail([facteur("Produits laitiers quotidiens", 12, .nutrition)])
        XCTAssertEqual(LectureApport.verdict(id: "calcium", nom: "Calcium", detail: couvert),
                       "Ton calcium est couvert.")
        let muet = DetailApport(contributions: [], score: 38)
        XCTAssertEqual(LectureApport.verdict(id: "zinc", nom: "Zinc", detail: muet), "Ton zinc est bas.")
        XCTAssertEqual(LectureApport.verdict(id: "vitC", nom: "Vitamine C", detail: couvert),
                       "Ta vitamine C est couverte.")
    }

    /// Un sigle garde sa majuscule au milieu de la phrase.
    func testUnSigleGardeSaMajuscule() {
        XCTAssertEqual(LectureApport.enCoursDePhrase("IMC inférieur à 18,5"), "IMC inférieur à 18,5")
        XCTAssertEqual(LectureApport.enCoursDePhrase("Règles abondantes"), "règles abondantes")
        XCTAssertEqual(LectureApport.enCoursDePhrase(""), "")
    }

    // MARK: Ce qui pèse le plus

    func testLesCausesSontTrieesEtPeseesContreLaPlusLourde() {
        let causes = LectureApport.causesPrincipales(ferDeLea)
        XCTAssertEqual(causes.map(\.cause.libelle),
                       ["Règles abondantes", "Café ou thé pendant les repas", "Alimentation végétarienne"])
        XCTAssertEqual(causes.first?.poids, 1)
        XCTAssertEqual(causes[1].poids, 12.0 / 15.0, accuracy: 0.0001)
        // La même identité que la part de l'anneau : la toucher l'allume.
        XCTAssertEqual(causes.map(\.id), Array(ferDeLea.parts.dropFirst().prefix(3)).map(\.id))
    }

    func testTroisCausesAuPlusEtAucuneSansFrein() {
        let charge = detail((1...5).map { facteur("Facteur \($0)", -$0, .nutrition) })
        XCTAssertEqual(LectureApport.causesPrincipales(charge).count, LectureApport.causesAffichees)
        let porte = detail([facteur("Poisson gras 2 fois par semaine", 10, .nutrition)])
        XCTAssertTrue(LectureApport.causesPrincipales(porte).isEmpty)
    }

    // MARK: Ce que tu peux faire

    /// Seul ce qui se change donne un geste : les règles abondantes n'en ont pas.
    func testLesGestesNeViennentQueDeCeQuiSeChange() {
        let gestes = LectureApport.gestes(ferDeLea)
        XCTAssertEqual(gestes.map(\.cause), ["Café ou thé pendant les repas", "Alimentation végétarienne"])
        XCTAssertEqual(gestes.first?.regain, 12)
        XCTAssertEqual(gestes.last?.regain, 8)
        XCTAssertTrue(gestes.allSatisfy { !$0.texte.isEmpty })
    }

    /// Deux facteurs de la même famille n'appellent qu'un geste : le plus lourd.
    func testUnSeulGesteParFamille() {
        let cafe = detail([
            facteur("Beaucoup de café ou de thé", -10, .modeDeVie),
            facteur("Café ou thé pendant les repas", -12, .modeDeVie),
        ])
        let gestes = LectureApport.gestes(cafe)
        XCTAssertEqual(gestes.count, 1)
        XCTAssertEqual(gestes.first?.cause, "Café ou thé pendant les repas")
    }

    /// Le renvoi au questionnaire n'est pas un geste.
    func testLeGesteDeRepliNEstPasListe() {
        let inconnu = detail([facteur("Facteur que personne ne reconnaît", -9, .nutrition)])
        XCTAssertEqual(CauseApport.explication(pour: inconnu.freins[0]).geste, CauseApport.gesteDeRepli)
        XCTAssertTrue(LectureApport.gestes(inconnu).isEmpty)
    }

    /// Échelle saturée : retirer le facteur ne rend aucun point, on n'en annonce pas.
    func testAucunChiffreQuandIlNYARienAAnnoncer() {
        let sature = detail([
            facteur("Règles très abondantes", -60, .sante),
            facteur("Traitement contre les remontées acides", -30, .medical),
            facteur("Pain blanc", -5, .nutrition),
        ])
        XCTAssertEqual(sature.score, 0)
        let gestes = LectureApport.gestes(sature)
        XCTAssertEqual(gestes.first?.regain, 0)
        XCTAssertNil(LectureApport.libelleRegain(0))
        XCTAssertEqual(LectureApport.libelleRegain(1), "jusqu'à +1 point")
        XCTAssertEqual(LectureApport.libelleRegain(12), "jusqu'à +12 points")
    }

    func testTroisGestesAuPlus() {
        let charge = detail([
            facteur("Café ou thé pendant les repas", -12, .modeDeVie),
            facteur("Alimentation végétarienne", -8, .nutrition),
            facteur("Pain blanc", -6, .nutrition),
            facteur("Repas surtout pris dehors", -5, .nutrition),
            facteur("Alcool fréquent", -4, .modeDeVie),
        ])
        XCTAssertEqual(LectureApport.gestes(charge).count, LectureApport.gestesAffiches)
    }

    // MARK: Sur de vrais profils

    /// Les dix apports d'un vrai profil : une phrase pour chacun, sans mot
    /// proscrit, et jamais plus de points promis que le calcul n'en rend.
    func testSurUnVraiProfilChaqueApportASaPhrase() {
        var lea = UserProfile.empty
        lea.age = "32"; lea.gender = .femme; lea.weight = "58"; lea.height = "165"
        lea.sleepHours = "5.5"; lea.waterIntake = "0.75"
        lea.indoorWork = "yes"; lea.sunExposure = "very_little"
        lea.stressLevel = "very"; lea.screenBeforeBed = "long"
        lea.caffeineIntake = "heavy"; lea.caffeineTiming = "with_meals"
        lea.dietType = "vegetarien"; lea.periodFlow = "very_heavy"

        let registre = HealthCalculator.registreApports(profile: lea)
        XCTAssertFalse(registre.isEmpty)
        let proscrits = ["carence", "diagnostic", "patient", "maladie"]
        for (id, detail) in registre {
            let phrase = LectureApport.verdict(id: id, nom: id, detail: detail)
            XCTAssertTrue(phrase.hasSuffix("."), phrase)
            for mot in proscrits { XCTAssertFalse(phrase.lowercased().contains(mot), phrase) }
            for geste in LectureApport.gestes(detail) {
                XCTAssertLessThanOrEqual(detail.score + geste.regain, 100, "\(id) · \(geste.cause)")
                XCTAssertGreaterThanOrEqual(geste.regain, 0)
            }
        }
    }
}
