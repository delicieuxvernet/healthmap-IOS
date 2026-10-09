import XCTest
@testable import HealthMap

/// La prise de sang corrige les apports (30 sept. 2026) : une ligne nommée du
/// registre, bornée, qui s'efface avec le temps et ne dit rien quand le
/// laboratoire n'a pas imprimé de repère.
final class PriseDeSangApportsTests: XCTestCase {

    private let maintenant: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 30; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    private func marqueur(
        _ code: String, _ nutriment: String?, _ position: PositionRepere,
        valeur: Double = 10, basse: Double? = 5, haute: Double? = 50
    ) -> MarqueurSanguin {
        MarqueurSanguin(code: code, nutriment: nutriment, libelle: code, valeur: valeur, unite: "u",
                        borneBasse: basse, borneHaute: haute, position: position)
    }

    private func prise(_ date: String, _ markers: [MarqueurSanguin]) -> PriseDeSang {
        PriseDeSang(id: "p-\(date)", takenAt: date, dateLue: true, markers: markers)
    }

    private func registre(_ scores: [String: Int]) -> [String: DetailApport] {
        scores.mapValues { score in
            let delta = score - DetailApport.pointDeDepart
            let lignes = delta == 0 ? [] : [ContributionApport(libelle: "Questionnaire", delta: delta, section: .nutrition)]
            return DetailApport(contributions: lignes, score: score)
        }
    }

    // MARK: Correction

    func testSousLeRepereTireLeScoreVersLeBas() {
        let r = registre(["iron": 70, "vitD": 60])
        let p = prise("2026-09-12", [marqueur("ferritine", "iron", .sousRepere)])
        let sortie = PriseDeSangApports.appliquer(r, priseDeSang: p, maintenant: maintenant)

        // cible 30 : (30 - 70) × 0,7 = -28
        XCTAssertEqual(sortie["iron"]?.score, 42)
        let ligne = sortie["iron"]?.contributions.last
        XCTAssertEqual(ligne?.section, .priseDeSang)
        XCTAssertEqual(ligne?.delta, -28)
        XCTAssertEqual(ligne?.provenance, "mesuré dans ta prise de sang")
        XCTAssertEqual(ligne?.libelle, "Ta prise de sang du 12 sept.")
        // Un apport non mesuré ne bouge pas.
        XCTAssertEqual(sortie["vitD"], r["vitD"])
    }

    func testDansLeRepereRemonteUnScoreDeclareBas() {
        let r = registre(["vitB12": 40])
        let p = prise("2026-09-12", [marqueur("vit_b12", "vitB12", .dansRepere)])
        // cible 85 : (85 - 40) × 0,7 = 31,5 → 32 (plafond 35)
        XCTAssertEqual(PriseDeSangApports.appliquer(r, priseDeSang: p, maintenant: maintenant)["vitB12"]?.score, 72)
    }

    func testLaCorrectionEstPlafonnee() {
        XCTAssertEqual(PriseDeSangApports.correction(score: 100, cible: 30, fraicheur: 1), -35)
        XCTAssertEqual(PriseDeSangApports.correction(score: 0, cible: 95, fraicheur: 1), 35)
    }

    func testUnEffetMinusculeNEstPasEcrit() {
        let r = registre(["vitB12": 84])
        let p = prise("2026-09-12", [marqueur("vit_b12", "vitB12", .dansRepere)])
        XCTAssertEqual(PriseDeSangApports.appliquer(r, priseDeSang: p, maintenant: maintenant)["vitB12"], r["vitB12"])
    }

    // MARK: Garde-fous

    func testSansRepereImprimeAucunEffet() {
        let r = registre(["iron": 70])
        let p = prise("2026-09-12", [marqueur("ferritine", "iron", .sansRepere, basse: nil, haute: nil)])
        XCTAssertEqual(PriseDeSangApports.appliquer(r, priseDeSang: p, maintenant: maintenant)["iron"], r["iron"])
    }

    func testCalciumDansLeRepereNeDitRienDesApports() {
        let r = registre(["calcium": 50, "magnesium": 50])
        let dans = prise("2026-09-12", [
            marqueur("calcium", "calcium", .dansRepere),
            marqueur("magnesium", "magnesium", .basDuRepere),
        ])
        let sortie = PriseDeSangApports.appliquer(r, priseDeSang: dans, maintenant: maintenant)
        XCTAssertEqual(sortie["calcium"]?.score, 50)
        XCTAssertEqual(sortie["magnesium"]?.score, 50)

        let sous = prise("2026-09-12", [marqueur("calcium", "calcium", .sousRepere)])
        XCTAssertEqual(PriseDeSangApports.appliquer(r, priseDeSang: sous, maintenant: maintenant)["calcium"]?.score, 36)
    }

    func testUnePriseDeSangVieillitPuisSEfface() {
        let r = registre(["iron": 70])
        let m = [marqueur("ferritine", "iron", .sousRepere)]
        // 8 mois : moitié d'effet → -14
        XCTAssertEqual(PriseDeSangApports.appliquer(r, priseDeSang: prise("2026-01-20", m), maintenant: maintenant)["iron"]?.score, 56)
        // 14 mois : plus aucun effet
        XCTAssertEqual(PriseDeSangApports.appliquer(r, priseDeSang: prise("2025-07-20", m), maintenant: maintenant)["iron"], r["iron"])
    }

    func testLesFolatesSontMontresSansToucherLeCalcul() {
        let r = registre(["iron": 70, "fiber": 60])
        let p = prise("2026-09-12", [marqueur("folates", nil, .sousRepere)])
        XCTAssertEqual(PriseDeSangApports.appliquer(r, priseDeSang: p, maintenant: maintenant), r)
        XCTAssertEqual(PriseDeSangApports.etat(p.markers[0]), .sousIntervalle)
        XCTAssertTrue(PriseDeSangApports.rappelleLAssiette(p.markers[0]))
        XCTAssertFalse(PriseDeSangApports.aliments(pour: p.markers[0]).isEmpty)
    }

    func testSansPriseDeSangLeRegistreEstIntact() {
        let r = registre(["iron": 70])
        XCTAssertEqual(PriseDeSangApports.appliquer(r, priseDeSang: nil, maintenant: maintenant), r)
    }

    // MARK: Lecture de la réponse serveur

    /// Réponse réelle d'`analyze-blood-report` v1 (PDF fictif, 30 sept. 2026).
    func testDecodeLaReponseDuServeur() throws {
        let json = """
        {"id":"6218c916-82b5-4cf1-bf03-b4981bb71a99","taken_at":"2026-09-12","date_lue":true,"source_kind":"pdf",
         "markers":[
          {"code":"vit_d_25oh","unite":"ng/mL","valeur":17,"libelle":"Vitamine D","position":"sous_repere","nutriment":"vitD","libelle_lu":"25-OH Vitamine D (D2+D3)","borne_basse":30,"borne_haute":100},
          {"code":"folates","unite":"ng/mL","valeur":4.1,"libelle":"Vitamine B9","position":"sous_repere","nutriment":null,"libelle_lu":"Folates seriques","borne_basse":4.6,"borne_haute":18.7},
          {"code":"futur","valeur":"illisible"},
          {"code":"zinc","unite":"µmol/L","valeur":11.8,"libelle":"Zinc","position":"position_inconnue","nutriment":"zinc","libelle_lu":"Zinc","borne_basse":null,"borne_haute":null}
         ],
         "created_at":"2026-09-30T17:13:54.833202+00:00"}
        """
        let p = try JSONDecoder().decode(PriseDeSang.self, from: Data(json.utf8))
        XCTAssertEqual(p.takenAt, "2026-09-12")
        XCTAssertTrue(p.dateLue)
        // Le marqueur illisible est écarté sans emporter les autres.
        XCTAssertEqual(p.markers.map(\.code), ["vit_d_25oh", "folates", "zinc"])
        XCTAssertNil(p.markers[1].nutriment)
        XCTAssertEqual(p.markers[2].position, .sansRepere)
        XCTAssertNil(p.markers[2].borneBasse)
        // L'intervalle imprimé par le labo, cité comme tel (audit du 9 oct. 2026).
        XCTAssertEqual(PriseDeSangApports.repereLisible(p.markers[0]), "intervalle du labo : 30–100")
        XCTAssertEqual(PriseDeSangApports.valeurLisible(4.1), "4,1")
    }

    // MARK: La phrase de la fiche

    func testLaPriseDeSangConfirmeMaisNEstPasUneCause() {
        let detail = DetailApport(contributions: [
            ContributionApport(libelle: "Règles abondantes", delta: -8, section: .sante),
            ContributionApport(libelle: "Ta prise de sang du 12 sept.", delta: -28, section: .priseDeSang),
        ], score: 34)
        let phrase = LectureApport.verdict(id: "iron", nom: "Fer", detail: detail)
        XCTAssertTrue(phrase.contains("Ta prise de sang du 12 sept. va dans ce sens."), phrase)
        XCTAssertTrue(phrase.hasSuffix("Première cause : règles abondantes."), phrase)
    }

    // MARK: Le bilan se régénère

    @MainActor
    func testLaPriseDeSangEntreDansLeHashDuBilan() {
        let profil = UserProfile.empty
        XCTAssertEqual(AIAnalysisService.hashProfile(profil), AIAnalysisService.hashProfile(profil, sang: ""))
        XCTAssertNotEqual(AIAnalysisService.hashProfile(profil), AIAnalysisService.hashProfile(profil, sang: "iron-30"))
    }
}
