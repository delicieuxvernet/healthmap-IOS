import XCTest
@testable import HealthMap

/// Le tableau « Gratuit ou Premium ? » : ce qu'il promet, et quand il passe.
final class ComparatifPremiumTests: XCTestCase {

    private let maintenant = Date(timeIntervalSince1970: 1_790_000_000)
    private func ilYA(jours: Double) -> Date { maintenant.addingTimeInterval(-jours * 86_400) }

    private func ligne(_ id: String) -> LigneComparatif? {
        ComparatifPremium.lignes.first { $0.id == id }
    }

    // MARK: Contenu

    /// Le gratuit garde les dictées (limitées), les photos (limitées), les
    /// macros et les compléments — et rien d'autre.
    func testLeGratuitNOffreQueCeQuArthurAListe() {
        let offertes = ComparatifPremium.lignes
            .filter { $0.gratuit != .absent }
            .map(\.id)
        XCTAssertEqual(offertes, ["dictee", "photo", "macros", "complements"])
    }

    func testPremiumAToutes() {
        for ligne in ComparatifPremium.lignes {
            XCTAssertNotEqual(ligne.premium, .absent, ligne.id)
        }
    }

    /// Le plan n'est pas dans le gratuit (seules ses solutions sont floutées
    /// aujourd'hui, mais c'est ce qui le rend utile).
    func testLePlanEstPremium() {
        XCTAssertEqual(ligne("plan")?.gratuit, .absent)
        XCTAssertEqual(ligne("plan")?.premium, .inclus)
    }

    /// Les chiffres des dictées viennent du compteur de l'app : ils ne
    /// peuvent pas dériver l'un de l'autre.
    func testLesDicteesSuiventLeQuotaDeLApp() {
        let gratuites = VoiceMealService.QuotaStore.dictéesGratuitesParJour
        XCTAssertEqual(gratuites, 2)
        XCTAssertEqual(ligne("dictee")?.gratuit, .valeur("\(gratuites) / jour"))
    }

    func testLesPhotosSuiventLesQuotasDuServeur() {
        XCTAssertEqual(ligne("photo")?.gratuit, .valeur("3 / jour"))
        XCTAssertEqual(ligne("photo")?.premium, .valeur("30 / jour"))
    }

    func testIdentifiantsUniques() {
        let ids = ComparatifPremium.lignes.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: Rythme

    func testLaPremiereFoisToujours() {
        XCTAssertTrue(RythmeComparatif.doitMontrer(dernier: nil, maintenant: maintenant))
    }

    func testPuisAuPlusUneFoisParSemaine() {
        XCTAssertFalse(RythmeComparatif.doitMontrer(dernier: ilYA(jours: 1), maintenant: maintenant))
        XCTAssertFalse(RythmeComparatif.doitMontrer(dernier: ilYA(jours: 6.9), maintenant: maintenant))
        XCTAssertTrue(RythmeComparatif.doitMontrer(dernier: ilYA(jours: 7), maintenant: maintenant))
    }

    func testVuEstRetenu() {
        let suite = "ComparatifPremiumTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(RythmeComparatif.doitMontrer(defaults: defaults, maintenant: maintenant))
        RythmeComparatif.noterVu(defaults: defaults, maintenant: maintenant)
        XCTAssertFalse(RythmeComparatif.doitMontrer(defaults: defaults, maintenant: maintenant.addingTimeInterval(3_600)))
        XCTAssertTrue(RythmeComparatif.doitMontrer(defaults: defaults, maintenant: maintenant.addingTimeInterval(8 * 86_400)))
    }
}
