import XCTest
import RevenueCat
@testable import HealthMap

/// L'offre de lancement (17,99 € la 1re année au lieu de 30 €, 13 → 31 octobre
/// 2026) : rien ne s'annonce qu'Apple ne fera pas payer, et les deux rappels
/// ne partent qu'une fois.
final class OffreLancementTests: XCTestCase {

    private var paris: Calendar {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendrier
    }

    private func date(_ jour: Int, _ mois: Int = 10, _ heure: Int = 9, _ minute: Int = 0) -> Date {
        paris.date(from: DateComponents(year: 2026, month: mois, day: jour, hour: heure, minute: minute))!
    }

    private let remiseAnnuelle = OffreLancement.Remise(
        gratuite: false, prix: Decimal(string: "17.99")!, prixTexte: "17,99 €",
        unite: .year, valeur: 1, periodes: 1
    )

    private func lire(_ remise: OffreLancement.Remise?, le maintenant: Date) -> OffreLancement? {
        OffreLancement.lire(remise: remise, prixNormal: 30, prixNormalTexte: "30,00 €",
                            uniteAbonnement: .year, valeurAbonnement: 1, maintenant: maintenant)
    }

    func testLOffreAnnonceLePrixLuChezApple() throws {
        let offre = try XCTUnwrap(lire(remiseAnnuelle, le: date(14)))
        XCTAssertEqual(offre.prixReduit, "17,99 €")
        XCTAssertEqual(offre.prixNormal, "30,00 €")
        XCTAssertEqual(offre.pourcent, 40)
        XCTAssertEqual(offre.titre, "Premium à 17,99 €\nta première année")
        XCTAssertEqual(offre.detail, "Au lieu de 30,00 €. Jusqu'au 31 octobre.")
        XCTAssertEqual(offre.prixCarte, "17,99 € la 1re année")
        XCTAssertEqual(offre.detailCarte, "Puis 30,00 € / an")
        XCTAssertEqual(offre.noteAchat, "17,99 € pour la 1re année, puis 30,00 € / an.")
        XCTAssertEqual(offre.moment, .annonce)
    }

    func testUnEssaiGratuitNEstPasUneOffreDeLancement() {
        let essai = OffreLancement.Remise(gratuite: true, prix: 0, prixTexte: "0,00 €",
                                          unite: .week, valeur: 1, periodes: 1)
        XCTAssertNil(lire(essai, le: date(14)))
    }

    func testRienSansRemiseNiApresLe31Octobre() {
        XCTAssertNil(lire(nil, le: date(14)))
        XCTAssertNil(lire(remiseAnnuelle, le: date(1, 11, 0, 1)))
        XCTAssertNotNil(lire(remiseAnnuelle, le: date(31, 10, 23, 59)))
    }

    func testPasDeDroitPasDeRemise() {
        XCTAssertNil(SubscriptionService.remiseDeLancement(de: nil, autorise: true))
    }

    func testLesDerniersJoursCommencentLe29() throws {
        let offre = try XCTUnwrap(lire(remiseAnnuelle, le: date(29)))
        XCTAssertEqual(offre.moment, .derniersJours)
        XCTAssertEqual(offre.joursRestants, 3)
        XCTAssertEqual(offre.detail, "Au lieu de 30,00 €. Plus que 3 jours, jusqu'au 31 octobre.")
        let dernier = try XCTUnwrap(lire(remiseAnnuelle, le: date(31)))
        XCTAssertEqual(dernier.detail, "Au lieu de 30,00 €. Dernier jour pour en profiter.")
    }

    func testDureesEnFrancais() {
        XCTAssertEqual(OffreLancement.durees(unite: .month, total: 3).la, "les 3 premiers mois")
        XCTAssertEqual(OffreLancement.durees(unite: .month, total: 1).ta, "ton premier mois")
    }

    // MARK: Rappels

    func testAnnonceLeLendemainA12h30() throws {
        let quand = RappelsLancement.dates(maintenant: date(13, 10, 18), annoncePrevue: nil, calendar: paris)
        XCTAssertEqual(quand.annonce, date(14, 10, 12, 30))
        XCTAssertEqual(quand.derniersJours, date(29, 10, 12, 30))
    }

    func testLAnnonceNeGlissePasEtNeRevientPas() {
        let prevue = date(14, 10, 12, 30)
        // Rouverte avant l'heure : même date.
        XCTAssertEqual(RappelsLancement.dates(maintenant: date(14, 10, 8), annoncePrevue: prevue, calendar: paris).annonce, prevue)
        // Partie : plus jamais.
        XCTAssertNil(RappelsLancement.dates(maintenant: date(15), annoncePrevue: prevue, calendar: paris).annonce)
    }

    func testPasDAnnonceDansLesDerniersJours() {
        let quand = RappelsLancement.dates(maintenant: date(28, 10, 20), annoncePrevue: nil, calendar: paris)
        XCTAssertNil(quand.annonce)
        XCTAssertEqual(quand.derniersJours, date(29, 10, 12, 30))
        XCTAssertNil(RappelsLancement.dates(maintenant: date(30), annoncePrevue: nil, calendar: paris).derniersJours)
    }

    func testTextesDesRappelsDansLesLimites() throws {
        let offre = try XCTUnwrap(lire(remiseAnnuelle, le: date(14)))
        for moment in [OffreLancement.Moment.annonce, .derniersJours] {
            XCTAssertLessThanOrEqual(RappelsLancement.titre(offre, moment: moment).count, 48)
            XCTAssertLessThanOrEqual(RappelsLancement.corps(offre, moment: moment).count, 145)
        }
        XCTAssertEqual(RappelsLancement.titre(offre, moment: .annonce), "Premium à 17,99 € la 1re année")
    }
}
