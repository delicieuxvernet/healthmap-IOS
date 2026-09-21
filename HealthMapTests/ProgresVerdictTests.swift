import XCTest
@testable import HealthMap

// MARK: - Progrès v3 : le verdict de la semaine (20 sept. 2026)
//
// Moteur pur : on construit les évolutions et la couverture à la main, on lit
// les phrases. Deux garde-fous comptent plus que le reste : en gratuit la ligne
// ne donne JAMAIS la tendance (c'est ce que vendent les portes), et un apport
// ne se juge pas sur deux repas.

// `SuiviEngineV4` est isolé sur le MainActor : la classe de test aussi.
@MainActor
final class ProgresVerdictTests: XCTestCase {

    private func evolution(_ nom: String, ressentis: [Int]) -> SuiviEngineV4.SymptomEvolution {
        SuiviEngineV4.evolution(id: nom, nom: nom, trend: SymptomTrend.make(from: nom),
                                tracking: .real(feelings: ressentis), step: 3)
    }

    private func apport(_ id: String, _ nom: String, avant: Int, apres: Int) -> SuiviEngineV4.NutrientCoverage7d {
        SuiviEngineV4.NutrientCoverage7d(id: id, nom: nom, pct: apres, trendPct: 0, baselinePct: avant)
    }

    // MARK: Symptôme

    func testSymptomeQuiVaMieuxSeDitEnClair() {
        let ligne = ProgresVerdict.ligneSymptome([evolution("ongles cassants", ressentis: [0, 0, 0])], verrouille: false)
        XCTAssertEqual(ligne?.gras, "Tes ongles vont mieux")
        XCTAssertEqual(ligne?.genre, .symptome)
    }

    func testUnProblemeReculeIlNeVaPasMieux() {
        let ligne = ProgresVerdict.ligneSymptome([evolution("fatigue", ressentis: [0, 0, 0])], verrouille: false)
        XCTAssertEqual(ligne?.gras, "Ta fatigue recule")
    }

    func testSingulierEtPluriel() {
        XCTAssertEqual(ProgresVerdict.vaMieux(SymptomTrend.make(from: "ongles cassants")), "vont mieux")
        XCTAssertEqual(ProgresVerdict.vaMieux(SymptomTrend.make(from: "digestion difficile")), "va mieux")
    }

    func testSymptomeASurveiller() {
        let ligne = ProgresVerdict.ligneSymptome([evolution("ongles cassants", ressentis: [2, 2, 2])], verrouille: false)
        XCTAssertEqual(ligne?.gras, "Tes ongles : à surveiller")
    }

    /// La tendance d'un symptôme est ce que vend la porte `suivi_symptomes` :
    /// en gratuit la ligne nomme le suivi, sans dire dans quel sens il va.
    func testEnGratuitLaLigneNeDonnePasLaTendance() {
        let ligne = ProgresVerdict.ligneSymptome([evolution("ongles cassants", ressentis: [0, 0, 0])], verrouille: true)
        XCTAssertEqual(ligne?.gras, "Tes ongles")
        let phrase = (ligne?.gras ?? "") + (ligne?.suite ?? "")
        for mot in ["mieux", "recule", "stable", "surveiller"] {
            XCTAssertFalse(phrase.contains(mot), "« \(mot) » donne la tendance en gratuit")
        }
    }

    func testSansReponseLeSuiviDemarre() {
        let ligne = ProgresVerdict.ligneSymptome([evolution("ongles cassants", ressentis: [])], verrouille: false)
        XCTAssertEqual(ligne?.gras, "Tes ongles")
        XCTAssertTrue(ligne?.suite.contains("démarre") ?? false)
    }

    func testAucunSymptomeAucuneLigne() {
        XCTAssertNil(ProgresVerdict.ligneSymptome([], verrouille: false))
    }

    /// On parle du symptôme qui s'améliore avant celui qui stagne.
    func testLeSymptomeQuiSAmelioreEstRetenu() {
        let retenu = ProgresVerdict.symptomeRetenu([
            evolution("fatigue", ressentis: [1, 1]),
            evolution("ongles cassants", ressentis: [0, 0, 0]),
        ])
        XCTAssertEqual(retenu?.id, "ongles cassants")
    }

    // MARK: Crans

    func testCransGagnes() {
        XCTAssertEqual(ProgresVerdict.niveauxGagnes(ressentis: [0, 0, 1, 2, 0]), 2)
        XCTAssertEqual(ProgresVerdict.niveauxGagnes(ressentis: [2, 2, 1]), -2)
        XCTAssertEqual(ProgresVerdict.niveauxGagnes(ressentis: []), 0)
    }

    func testLibelleDesCrans() {
        XCTAssertEqual(ProgresVerdict.libelleNiveaux(2), "+2 niveaux")
        XCTAssertEqual(ProgresVerdict.libelleNiveaux(1), "+1 niveau")
        XCTAssertEqual(ProgresVerdict.libelleNiveaux(-1), "\u{2212}1 niveau")
        XCTAssertEqual(ProgresVerdict.libelleNiveaux(0), "stable")
    }

    // MARK: Apport

    func testLaPlusForteHausseEstRetenue() {
        let ligne = ProgresVerdict.ligneApport(
            couverture: [apport("vitD", "Vitamine D", avant: 24, apres: 31),
                         apport("iron", "Fer", avant: 42, apres: 61),
                         apport("calcium", "Calcium", avant: 58, apres: 55)],
            joursSuivis: 5, verrouille: false)
        XCTAssertEqual(ligne?.gras, "Fer en hausse")
        XCTAssertEqual(ligne?.suite, " : 42 → 61 %.")
        XCTAssertEqual(ligne?.genre, .apport(id: "iron"))
    }

    func testSansHausseLaPlusForteBaisseEstDite() {
        let ligne = ProgresVerdict.ligneApport(
            couverture: [apport("calcium", "Calcium", avant: 58, apres: 50),
                         apport("iron", "Fer", avant: 42, apres: 41)],
            joursSuivis: 5, verrouille: false)
        XCTAssertEqual(ligne?.gras, "Calcium en baisse")
    }

    /// Deux jours suivis sur sept : comparer la semaine au départ reviendrait à
    /// juger un apport sur deux repas.
    func testPasDeVerdictSurDeuxJours() {
        let ligne = ProgresVerdict.ligneApport(
            couverture: [apport("iron", "Fer", avant: 42, apres: 12)],
            joursSuivis: 2, verrouille: false)
        XCTAssertNil(ligne)
    }

    func testUnEcartDeBruitNEstPasUneTendance() {
        let ligne = ProgresVerdict.ligneApport(
            couverture: [apport("iron", "Fer", avant: 42, apres: 44)],
            joursSuivis: 6, verrouille: false)
        XCTAssertNil(ligne)
    }

    func testEnGratuitLApportEstNommeSansChiffre() {
        let ligne = ProgresVerdict.ligneApport(
            couverture: [apport("iron", "Fer", avant: 42, apres: 61)],
            joursSuivis: 5, verrouille: true)
        XCTAssertEqual(ligne?.gras, "Fer")
        XCTAssertFalse((ligne?.suite ?? "").contains("61"))
        XCTAssertFalse((ligne?.suite ?? "").contains("hausse"))
    }

    // MARK: Calories

    func testCaloriesDansLaCible() {
        let ligne = ProgresVerdict.ligneCalories(joursSuivis: 7, joursDansLaCible: 5, besoinConnu: true)
        XCTAssertEqual(ligne?.gras, "Calories : 5 jours sur 7")
        XCTAssertEqual(ProgresVerdict.ligneCalories(joursSuivis: 3, joursDansLaCible: 1, besoinConnu: true)?.gras,
                       "Calories : 1 jour sur 3")
    }

    func testSansBesoinConnuNiRepasPasDeLigne() {
        XCTAssertNil(ProgresVerdict.ligneCalories(joursSuivis: 5, joursDansLaCible: 3, besoinConnu: false))
        XCTAssertNil(ProgresVerdict.ligneCalories(joursSuivis: 0, joursDansLaCible: 0, besoinConnu: true))
    }

    // MARK: Check-in : la question va dans le sens du mieux

    func testLaQuestionDuCheckinVaVersLeMieux() {
        XCTAssertEqual(SymptomTrend.make(from: "ongles cassants").questionVersLeMieux, "Moins cassants qu'avant\u{00A0}?")
        XCTAssertEqual(SymptomTrend.make(from: "manque d'énergie").questionVersLeMieux, "Plus d'énergie qu'avant\u{00A0}?")
    }
}
