import XCTest
@testable import HealthMap

// MARK: - Étape 3 de l'audit : le journal corrige les apports (22 sept. 2026)
//
// Les repas notés des 14 derniers jours tirent chaque score vers ce qu'ils
// montrent, sans le remplacer. Ces tests tiennent les garde-fous : jours
// représentatifs seulement, trois jours au moins, besoin de la personne,
// correction bornée et nommée, bilan régénéré par paliers.

final class JournalApportsTests: XCTestCase {

    private let calendrier: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    private lazy var maintenant: Date = calendrier.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 18))!

    private func homme() -> UserProfile {
        var p = UserProfile.empty
        p.gender = .homme; p.age = "30"; p.weight = "75"; p.height = "178"
        return p
    }

    /// Un repas il y a `joursAvant` jours, à midi.
    private func repas(_ joursAvant: Int, kcal: Int, micros: [String: Int]) -> MealJournalService.MealRecord {
        let jour = calendrier.date(byAdding: .day, value: -joursAvant, to: calendrier.startOfDay(for: maintenant))!
        let midi = calendrier.date(byAdding: .hour, value: 12, to: jour)!
        return MealJournalService.MealRecord(
            id: UUID().uuidString, consumedAt: midi, slot: MealJournalService.MealSlot.from(date: midi, calendar: calendrier),
            foods: ["repas"], macros: MealJournalService.MealMacros(calories: kcal),
            micros: micros.map { MealJournalService.MicroPct(id: $0.key, pctRDA: $0.value) })
    }

    private func observations(_ repas: [MealJournalService.MealRecord], profil: UserProfile? = nil) -> ObservationsJournal? {
        JournalApports.observations(repas: repas, profil: profil ?? homme(), maintenant: maintenant, calendar: calendrier)
    }

    // MARK: Les jours qui comptent

    func testUneJourneeAssezNoteeSuffit() {
        XCTAssertNil(observations([]))
        let une = [repas(1, kcal: 2200, micros: ["iron": 50])]
        XCTAssertEqual(observations(une)?.joursRetenus, 1)
        XCTAssertEqual(observations(une)?.jours["iron"], 1)
        let trois = une + [repas(2, kcal: 2200, micros: ["iron": 50]), repas(3, kcal: 2200, micros: ["iron": 50])]
        XCTAssertEqual(observations(trois)?.joursPour("iron"), 3)
    }

    func testUnJourAMoitieNoteNeComptePas() {
        XCTAssertNil(observations([repas(3, kcal: 500, micros: ["iron": 10])]), "un jour à 500 kcal dirait « manque » à tort")
        let jours = [repas(1, kcal: 2200, micros: ["iron": 50]), repas(2, kcal: 2200, micros: ["iron": 50]),
                     repas(3, kcal: 500, micros: ["iron": 10])]
        XCTAssertEqual(observations(jours)?.joursRetenus, 2)
    }

    func testAujourdhuiCompteDesQuIlEstAssezNote() {
        // La journée en cours entre dans le calcul comme les autres : il lui
        // faut 60 % de la dépense notée.
        XCTAssertEqual(observations([repas(0, kcal: 2200, micros: ["iron": 50])])?.joursRetenus, 1)
        XCTAssertNil(observations([repas(0, kcal: 400, micros: ["iron": 10])]), "le petit déjeuner seul ne dit rien de la journée")
    }

    func testLesJoursHorsFenetreNeComptentPas() {
        // Quatorze jours, aujourd'hui compris : le plus ancien est il y a treize jours.
        XCTAssertEqual(observations([repas(13, kcal: 2200, micros: ["iron": 50])])?.joursRetenus, 1)
        XCTAssertNil(observations([repas(14, kcal: 2200, micros: ["iron": 50])]))
        XCTAssertNil(observations([repas(20, kcal: 2200, micros: ["iron": 50])]))
    }

    // MARK: Ce que montre un jour

    func testLaCouvertureSeLitSurLeBesoinDeLaPersonne() {
        // 50 % de la référence générique (18 mg) = 9 mg ; un homme a besoin de 11 mg.
        let jours = (1...3).map { repas($0, kcal: 2200, micros: ["iron": 50]) }
        XCTAssertEqual(observations(jours)?.couverture["iron"], Int((50.0 * 18 / 11).rounded()))
    }

    func testLesRepasNonRenseignesSontSupposesALImageDesAutres() {
        // 1 500 kcal renseignent le fer à 30 %, 700 kcal ne le renseignent pas :
        // la journée entière est estimée à 30 × 2 200 / 1 500 = 44 % (référence générique).
        let jours = (1...3).flatMap { [repas($0, kcal: 1500, micros: ["iron": 30]), repas($0, kcal: 700, micros: [:])] }
        let attendu = Int((30.0 * 2200 / 1500 * 18 / 11).rounded())
        XCTAssertEqual(observations(jours)?.couverture["iron"], attendu)
    }

    func testUnApportPeuRenseigneNestPasCorrige() {
        // Le fer n'est renseigné que par 20 % des calories : pas assez pour conclure.
        let jours = (1...3).flatMap { [repas($0, kcal: 400, micros: ["iron": 10, "vitC": 40]), repas($0, kcal: 1800, micros: ["vitC": 60])] }
        let obs = observations(jours)
        XCTAssertNil(obs?.couverture["iron"])
        XCTAssertNotNil(obs?.couverture["vitC"])
    }

    // MARK: La correction

    func testLePoidsDuJournalGranditAvecLesJourneesNotees() {
        // Le questionnaire pèse comme quatre journées.
        XCTAssertEqual(JournalApports.traction(jours: 0), 0)
        XCTAssertEqual(JournalApports.traction(jours: 1), 0.2, accuracy: 0.001)
        XCTAssertEqual(JournalApports.traction(jours: 4), 0.5, accuracy: 0.001)
        XCTAssertEqual(JournalApports.traction(jours: 14), 14.0 / 18.0, accuracy: 0.001)
        XCTAssertLessThan(JournalApports.traction(jours: 365), 1)

        // Même écart de 50 points : une journée en rattrape 10, quatre 25.
        XCTAssertEqual(JournalApports.correction(score: 70, couverture: 20, jours: 1), -10)
        XCTAssertEqual(JournalApports.correction(score: 70, couverture: 20, jours: 4), -25)
    }

    func testLaCorrectionResteBornee() {
        XCTAssertEqual(JournalApports.correction(score: 90, couverture: 10, jours: 14), -30, "jamais plus de 30 points")
        XCTAssertEqual(JournalApports.correction(score: 30, couverture: 160, jours: 14), 30, "plafonnée, et la couverture au-delà du besoin ne compte pas")
        XCTAssertEqual(JournalApports.correction(score: 60, couverture: 66, jours: 2), 2)
        XCTAssertEqual(JournalApports.correction(score: 50, couverture: 50, jours: 7), 0)
    }

    func testLaLigneDuJournalSEcritDansLaCascade() {
        let registre = HealthCalculator.registreApports(profile: homme())
        let avant = registre["iron"]?.score ?? 0
        let vitC = registre["vitC"]?.score ?? 0
        let obs = ObservationsJournal(joursRetenus: 5, couverture: ["iron": 20, "vitC": vitC + 2])
        let corrige = JournalApports.appliquer(registre, observations: obs)
        let ligne = corrige["iron"]?.contributions.last
        XCTAssertEqual(ligne?.libelle, JournalApports.libelle)
        XCTAssertEqual(ligne?.section, .journal)
        XCTAssertEqual(ligne?.provenance, "noté dans ton journal")
        XCTAssertEqual(corrige["iron"]?.score, avant + JournalApports.correction(score: avant, couverture: 20, jours: 5))
        // Un effet de moins de 2 points n'est pas écrit.
        XCTAssertEqual(corrige["vitC"], registre["vitC"])
        // Sans observations, le registre est intact.
        XCTAssertEqual(JournalApports.appliquer(registre, observations: nil), registre)
    }

    func testLeJournalAUneExplicationQuiLuiEstPropre() {
        let pese = ContributionApport(libelle: JournalApports.libelle, delta: -9, section: .journal)
        XCTAssertEqual(CauseApport.explication(pour: pese), CauseApport.journalPese)
        let aide = ContributionApport(libelle: JournalApports.libelle, delta: 6, section: .journal)
        XCTAssertEqual(CauseApport.explication(pour: aide), CauseApport.journalAide)
        XCTAssertTrue(CauseApport.seChange(.journal))
    }

    // MARK: Le bilan suit le journal, par paliers

    func testLaSignatureAvanceParPaliersDeDix() {
        let registre = HealthCalculator.registreApports(profile: homme())
        XCTAssertEqual(JournalApports.signature(avant: registre, apres: registre), "")
        let fer = registre["iron"]?.score ?? 0
        var petit = registre
        petit["iron"] = DetailApport(contributions: [], score: fer - 2)
        XCTAssertEqual(JournalApports.signature(avant: registre, apres: petit), "", "2 points : pas de nouveau bilan")
        var grand = registre
        grand["iron"] = DetailApport(contributions: [], score: fer - 9)
        XCTAssertEqual(JournalApports.signature(avant: registre, apres: grand), "iron-10")
    }

    @MainActor
    func testLeHashDuBilanSuitLaSignatureDuJournal() {
        let p = homme()
        XCTAssertEqual(AIAnalysisService.hashProfile(p), AIAnalysisService.hashProfile(p, journal: ""))
        XCTAssertNotEqual(AIAnalysisService.hashProfile(p), AIAnalysisService.hashProfile(p, journal: "iron-10"))
    }
}
