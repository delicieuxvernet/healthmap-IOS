import XCTest
@testable import HealthMap

/// Audit de fiabilité (8 oct. 2026) : la carte Micronutriments du Journal
/// affichait « Ta vitamine D est basse » sur un seuil de 60 % alors que la
/// fiche disait « à affiner ». Avec l'estimateur, le chiffre et le statut des
/// micros sont ceux de la fiche.
final class MicrosEstimesTests: XCTestCase {

    private func contexte(_ p: ProfilEstimation) throws -> ContexteMicros {
        let r = try XCTUnwrap(EstimateurApports.partage).estimer(p)
        return ContexteMicros(besoins: [:], depense: 2000, scores: [:], couvertureJournal: [:], joursJournal: [:],
                              symptomes: [], estimations: r.apports, statuts: r.apports.mapValues(\.statut), profil: p)
    }

    private var neufAliments: ProfilEstimation {
        var p = ProfilEstimation(gender: "homme", age: "28", weight: "75", height: "178", strengthTraining: "moderate",
                                 caffeineIntake: "moderate", waterIntake: "1.75", alcohol: "rarely", mealsPerDay: "3")
        p.groceries = Dictionary(uniqueKeysWithValues: ["baguette", "pates", "steak_hache", "escalopes_poulet",
                                                        "yaourt_nature", "pommes", "oeufs", "tomates", "courgettes"].map { ($0, 3) })
        return p
    }

    func testLeChiffreEtLeStatutSontCeuxDeLEstimateur() throws {
        let c = try contexte(neufAliments)
        let t = MicrosDuJour.tableau(repas: [], jourAffiche: Date(), compositions: [:], contexte: c, registre: [:])
        let vitD = try XCTUnwrap(t.toutes.first { $0.id == "vitD" })
        let e = try XCTUnwrap(c.estimations["vitD"])
        XCTAssertEqual(vitD.niveau, LectureEstimation.couverture(e))
        XCTAssertEqual(vitD.statutApport, .peuPrecise)
        XCTAssertFalse(vitD.statut.estUneAlerte)
        XCTAssertTrue(t.alertes.isEmpty, "caddie insuffisant : aucune alerte")
    }

    func testLesFaitsCitentLesSourcesPasDesPoints() throws {
        let c = try contexte(neufAliments)
        let t = MicrosDuJour.tableau(repas: [], jourAffiche: Date(), compositions: [:], contexte: c, registre: [:])
        let mg = try XCTUnwrap(t.toutes.first { $0.id == "magnesium" })
        let textes = mg.faits.map(\.texte)
        XCTAssertTrue(textes.contains { $0.hasPrefix("Ta plus grosse source") }, textes.joined(separator: " | "))
        XCTAssertFalse(textes.contains { $0.contains("point") }, textes.joined(separator: " | "))
        XCTAssertTrue(textes.contains { $0.contains("pas un résultat d'analyse") })
    }

    func testUnApportCouvertNePasseJamaisDevantDansLesPriorites() throws {
        var p = neufAliments
        p.supplementsCurrent = ["vitD"]
        let c = try contexte(p)
        let t = MicrosDuJour.tableau(repas: [], jourAffiche: Date(), compositions: [:], contexte: c, registre: [:])
        XCTAssertFalse(t.priorites.contains { $0.id == "vitD" }, "couverte par son complément, la vitamine D n'est plus une priorité")
    }
}
