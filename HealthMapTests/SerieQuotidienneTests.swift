import XCTest
@testable import HealthMap

/// Série quotidienne des courbes symptômes (retour d'appareil du 24 août :
/// « les points vont sur le même endroit, on a une droite »). Un point par
/// JOUR : deux réponses à deux jours différents avancent sur l'axe, une
/// deuxième réponse le même jour remplace la première.
final class SerieQuotidienneTests: XCTestCase {

    private let calendrier = Calendar(identifier: .gregorian)

    private func jour(_ decalage: Int, depuis reference: Date) -> Date {
        calendrier.date(byAdding: .day, value: decalage, to: reference)!
    }

    func testUnPointParJour_lAxeAvance() {
        let depart = calendrier.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let maintenant = jour(3, depuis: depart)
        let serie = SuiviEngineV4.serieQuotidienne(
            depart: depart,
            reponses: [(jour: depart, ressenti: 0),
                       (jour: jour(1, depuis: depart), ressenti: 0),
                       (jour: jour(3, depuis: depart), ressenti: 0)],
            dir: .lowerBetter,
            now: maintenant,
            calendar: calendrier
        )
        XCTAssertEqual(serie.count, 4, "un point par JOUR, répondu ou non")
        XCTAssertEqual(serie.map(\.repondu), [true, true, false, true])
        // lowerBetter + « mieux » (0) : le niveau descend de `step` (3) à
        // chaque jour répondu, et tient son palier le jour sans réponse.
        XCTAssertEqual(serie.map(\.niveau), [47, 44, 44, 41])
        // Les jours sont tous distincts : plus jamais deux points superposés.
        XCTAssertEqual(Set(serie.map(\.jour)).count, 4)
    }

    func testDeuxReponsesLeMemeJour_laDerniereFaitFoi() {
        let depart = calendrier.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let serie = SuiviEngineV4.serieQuotidienne(
            depart: depart,
            reponses: [(jour: depart, ressenti: 2),
                       (jour: depart.addingTimeInterval(3600), ressenti: 0)],
            dir: .lowerBetter,
            now: depart,
            calendar: calendrier
        )
        XCTAssertEqual(serie.count, 1)
        XCTAssertEqual(serie[0].niveau, 47, "la réponse « mieux » de l'après-midi remplace celle du matin")
        XCTAssertTrue(serie[0].repondu)
    }

    func testPareilCompteCommeRepondu_pointPoseAuMemeNiveau() {
        let depart = calendrier.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let serie = SuiviEngineV4.serieQuotidienne(
            depart: depart,
            reponses: [(jour: depart, ressenti: 1)],
            dir: .lowerBetter,
            now: jour(1, depuis: depart),
            calendar: calendrier
        )
        XCTAssertEqual(serie.map(\.niveau), [50, 50])
        XCTAssertEqual(serie.map(\.repondu), [true, false])
    }

    func testFenetreBorneAuxDerniersJours() {
        let depart = calendrier.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let maintenant = jour(29, depuis: depart)
        let serie = SuiviEngineV4.serieQuotidienne(
            depart: depart, reponses: [], dir: .higherBetter,
            fenetre: 14, now: maintenant, calendar: calendrier
        )
        XCTAssertEqual(serie.count, 14)
        XCTAssertEqual(serie.last?.jour, calendrier.startOfDay(for: maintenant))
    }

    func testHigherBetter_mieuxMonte() {
        let depart = calendrier.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let serie = SuiviEngineV4.serieQuotidienne(
            depart: depart,
            reponses: [(jour: depart, ressenti: 0), (jour: jour(1, depuis: depart), ressenti: 2)],
            dir: .higherBetter,
            now: jour(1, depuis: depart),
            calendar: calendrier
        )
        XCTAssertEqual(serie.map(\.niveau), [53, 50])
    }

    func testDepartDansLeFutur_serieDuJourSeul() {
        let maintenant = calendrier.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let serie = SuiviEngineV4.serieQuotidienne(
            depart: jour(5, depuis: maintenant), reponses: [], dir: .lowerBetter,
            now: maintenant, calendar: calendrier
        )
        XCTAssertEqual(serie.count, 1, "un départ mal daté ne vide pas la courbe")
    }
}
