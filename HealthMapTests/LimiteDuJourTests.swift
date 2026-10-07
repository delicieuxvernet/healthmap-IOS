import XCTest
@testable import HealthMap

/// Limite du jour atteinte → feuille Premium « Oups ! » (7 octobre 2026), et
/// carte Micronutriments verrouillée sans flou (chiffres brouillés seulement).
final class LimiteDuJourTests: XCTestCase {

    // MARK: - Les phrases sous « Oups ! »

    func testPhraseScansDitLaLimiteDuServeur() {
        XCTAssertEqual(LimiteDuJour.scans(limite: 3).phrase, "Tu as utilisé tes 3 scans photo du jour.")
        XCTAssertEqual(LimiteDuJour.scans(limite: 1).phrase, "Tu as utilisé ton scan photo du jour.")
    }

    /// Dictée et texte partagent leur quota : la phrase le dit, et elle est la
    /// même quel que soit le bouton qui a buté sur la limite.
    func testDicteeEtTexteDisentLeQuotaPartage() {
        let n = VoiceMealService.QuotaStore.dictéesGratuitesParJour
        XCTAssertEqual(LimiteDuJour.dictees.phrase, LimiteDuJour.ecrits.phrase)
        XCTAssertTrue(LimiteDuJour.dictees.phrase.contains("\(n) analyses"))
        XCTAssertTrue(LimiteDuJour.dictees.phrase.contains("comptent ensemble"))
    }

    func testSourcesDeTrackingDistinctes() {
        let sources = Set([LimiteDuJour.scans(limite: 3), .dictees, .ecrits].map(\.source))
        XCTAssertEqual(sources, ["limite_scans", "limite_dictees", "limite_ecrits"])
    }

    /// Le rapport oméga-6 / oméga-3 n'est pas un micronutriment de plus.
    func testNombreDeMicrosSansLeRapport() {
        XCTAssertEqual(LimiteDuJour.nombreDeMicros, Micronutriments.tous.count - 1)
    }

    // MARK: - Compteur local aligné sur le 429 du serveur

    func testMarquerEpuiseesBloqueLaProchaineDictee() {
        let uid = "test-limite-\(UUID().uuidString)"
        XCTAssertTrue(VoiceMealService.QuotaStore.peutDicter(userId: uid, isPremium: false))
        VoiceMealService.QuotaStore.marquerEpuisees(userId: uid)
        XCTAssertFalse(VoiceMealService.QuotaStore.peutDicter(userId: uid, isPremium: false))
        // Un abonné n'est jamais bloqué par le compteur local.
        XCTAssertTrue(VoiceMealService.QuotaStore.peutDicter(userId: uid, isPremium: true))
    }

    /// Ne fait jamais REDESCENDRE un compteur déjà plus haut.
    func testMarquerEpuiseesNeBaisseJamaisLeCompteur() {
        let uid = "test-limite-\(UUID().uuidString)"
        let limite = VoiceMealService.QuotaStore.dictéesGratuitesParJour
        for _ in 0..<(limite + 2) { VoiceMealService.QuotaStore.enregistrerUneDictée(userId: uid) }
        VoiceMealService.QuotaStore.marquerEpuisees(userId: uid)
        XCTAssertEqual(VoiceMealService.QuotaStore.utiliséesAujourdhui(userId: uid), limite + 2)
    }

    // MARK: - Jauge factice des micros verrouillés

    func testPartFacticeStableEtBornee() {
        for micro in Micronutriments.tous {
            let part = MicroVerrouille.partFactice(id: micro.id)
            XCTAssertGreaterThanOrEqual(part, 0.25, micro.id)
            XCTAssertLessThanOrEqual(part, 0.90, micro.id)
            XCTAssertEqual(part, MicroVerrouille.partFactice(id: micro.id), micro.id)
        }
    }

    /// Les jauges ne sont pas toutes de la même longueur : sinon la carte
    /// verrouillée aurait l'air vide, pas brouillée.
    func testPartFacticeVarieDUnMicroALAutre() {
        let parts = Set(Micronutriments.tous.map { MicroVerrouille.partFactice(id: $0.id) })
        XCTAssertGreaterThan(parts.count, Micronutriments.tous.count / 2)
    }
}
