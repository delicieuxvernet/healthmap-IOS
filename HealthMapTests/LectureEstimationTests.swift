import XCTest
@testable import HealthMap

/// La fiche validée le 8 oct. 2026 : un apport ESTIMÉ se lit en vraies
/// quantités, ses sources somment à la quantité, et le statut — jamais un
/// seuil sur le chiffre — décide des mots et des couleurs.
final class LectureEstimationTests: XCTestCase {

    private func estimation(_ p: ProfilEstimation, _ journees: [JourneeNotee] = []) throws -> ResultatEstimation {
        try XCTUnwrap(EstimateurApports.partage).estimer(p, journees: journees)
    }

    private var casDeLAudit: ProfilEstimation {
        var p = ProfilEstimation(gender: "homme", age: "28", weight: "75", height: "178", strengthTraining: "moderate",
                                 caffeineIntake: "moderate", waterIntake: "1.75", alcohol: "rarely", mealsPerDay: "3")
        p.groceries = Dictionary(uniqueKeysWithValues: ["baguette", "pates", "steak_hache", "escalopes_poulet",
                                                        "yaourt_nature", "pommes", "oeufs", "tomates", "courgettes"].map { ($0, 3) })
        return p
    }

    func testLeVerdictParleDUnApportJamaisDUnTaux() throws {
        let mg = try XCTUnwrap(try estimation(casDeLAudit).apports["magnesium"])
        XCTAssertEqual(LectureEstimation.verdict(nom: "Magnésium", estimation: mg, statut: .aSurveiller),
                       "Ton apport en magnésium semble proche de la référence.")
        let phrase = LectureEstimation.verdict(nom: "Magnésium", estimation: mg)
        XCTAssertEqual(mg.statut, .peuPrecise, "neuf aliments cochés : rien d'affirmé")
        XCTAssertTrue(phrase.contains("reste à préciser"), phrase)
        for statut in [StatutApport.couvert, .aSurveiller, .aRenforcer, .peuPrecise, .couvertParComplement] {
            let texte = LectureEstimation.verdict(nom: "Magnésium", estimation: mg, statut: statut)
            XCTAssertFalse(texte.lowercased().contains("taux"), texte)
            XCTAssertTrue(texte.contains("apport"), texte)
        }
    }

    func testLaQuantiteEstUneVraieQuantite() throws {
        let mg = try XCTUnwrap(try estimation(casDeLAudit).apports["magnesium"])
        let texte = LectureEstimation.quantite("magnesium", mg)
        XCTAssertTrue(texte.hasPrefix("≈ 379"), texte)
        XCTAssertTrue(texte.contains("sur 380"), "référence ANSES 2021 d'un homme : \(texte)")
    }

    func testLesSourcesSommentALaQuantite() throws {
        let r = try estimation(casDeLAudit)
        for id in ["magnesium", "iron", "calcium", "vitC"] {
            let e = try XCTUnwrap(r.apports[id])
            let total = LectureEstimation.sources(id, e, profil: casDeLAudit).reduce(0) { $0 + $1.valeur }
            XCTAssertEqual(total, LectureEstimation.quantiteAffichee(id, e), accuracy: LectureEstimation.quantiteAffichee(id, e) * 0.02, id)
        }
        let mg = try XCTUnwrap(r.apports["magnesium"])
        let ids = LectureEstimation.sources("magnesium", mg, profil: casDeLAudit).map(\.id)
        XCTAssertTrue(ids.contains("cafe"), "le café est une source de magnésium")
        XCTAssertEqual(LectureEstimation.sources("magnesium", mg, profil: casDeLAudit).first { $0.id == "cafe" }?.detail,
                       "3 à 4 tasses par jour")
    }

    func testLeDetailEstUnRegistreDeSources() throws {
        let mg = try XCTUnwrap(try estimation(casDeLAudit).apports["magnesium"])
        let d = LectureEstimation.detail("magnesium", mg, profil: casDeLAudit)
        XCTAssertEqual(d.depart, 0)
        XCTAssertTrue(d.freins.isEmpty)
        XCTAssertEqual(d.score, LectureEstimation.couverture(mg))
        XCTAssertEqual(d.parts.reduce(0) { $0 + $1.valeur }, 100)
        XCTAssertEqual(LectureApport.verdict(id: "magnesium", nom: "Magnésium", detail: d),
                       LectureEstimation.verdict(nom: "Magnésium", estimation: mg))
        XCTAssertTrue(LectureEstimation.sources("magnesium", mg, profil: casDeLAudit).contains { $0.id == "non_coches" },
                      "caddie insuffisant : les aliments non cochés sont une source nommée")
    }

    func testUnCaddieInsuffisantInviteACocher() throws {
        let r = try estimation(casDeLAudit)
        let caddie = try XCTUnwrap(LectureEstimation.alimentsACocher(r))
        XCTAssertEqual(caddie.coches, 9)
        XCTAssertEqual(caddie.minimum, 15)
    }

    func testLeStatutDecideDesCouleursPasLeChiffre() {
        XCTAssertEqual(StatutApport.aSurveiller.statutV2, .aRenforcer)
        XCTAssertEqual(StatutApport.aRenforcer.statutV2, .aCombler)
        XCTAssertEqual(StatutApport.peuPrecise.statutV2, .neutre)
        XCTAssertEqual(StatutApport.couvertParComplement.statutV2, .couvre)
        XCTAssertEqual(StatutV2.aRenforcer.displayLabel, "À surveiller")
        XCTAssertEqual(StatutV2.aCombler.displayLabel, "À renforcer")
        XCTAssertTrue(StatutApport.aRenforcer.estUneAlerte)
        XCTAssertFalse(StatutApport.peuPrecise.estUneAlerte)
        XCTAssertFalse(StatutApport.aSurveiller.estUneAlerte)
    }

    func testLesJourneesNoteesSontConvertiesEtJamaisInventees() {
        let jour = Calendar.current.startOfDay(for: Date())
        let mesuree = JourneeMesuree(
            jour: jour, kcal: 2000,
            quantites: ["vitD": 400, "iron": 6, "zinc": 4],
            kcalRenseignees: ["vitD": 2000, "iron": 1500, "zinc": 600],
            bouchees: []
        )
        let journees = LectureEstimation.journees([jour: mesuree])
        XCTAssertEqual(journees.count, 1)
        let j = journees[0]
        XCTAssertEqual(j.kcal, 2000)
        XCTAssertEqual(j.apports["vitD"] ?? -1, 10, accuracy: 1e-9, "400 UI = 10 µg")
        XCTAssertEqual(j.apports["iron"] ?? -1, 8, accuracy: 1e-9, "6 mg sur 75 % des calories, ramenés à la journée")
        XCTAssertNil(j.apports["zinc"], "moins de la moitié des calories renseignées : non renseigné, pas zéro")
        XCTAssertNil(j.apports["magnesium"])
    }

    func testUnRepasNoteDevientUneSource() throws {
        let p = casDeLAudit
        let riche = JourneeNotee(kcal: 3500, apports: ["magnesium": 600])
        let mg = try XCTUnwrap(try estimation(p, [riche, riche]).apports["magnesium"])
        XCTAssertEqual(mg.joursJournalRetenus, 2)
        let repas = LectureEstimation.sources("magnesium", mg, profil: p).first { $0.id == "repas" }
        XCTAssertEqual(repas?.detail, "2 journées notées")
        XCTAssertTrue(LectureEstimation.provenance(mg).contains("tes 2 journées notées"))
    }
}
