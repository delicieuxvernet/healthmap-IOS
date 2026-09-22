import XCTest
@testable import HealthMap

// MARK: - Aucune dose affichée (décision du 20 septembre 2026, redite par Arthur le 22)
//
// On conseille le complément ; la posologie appartient au fabricant et à la
// personne. Le « pourquoi cette forme » (`whyBrand`) s'affiche tel quel dans la
// fiche d'un apport (onglet Compléments) : il ne doit porter ni quantité, ni
// rythme de prise, ni pourcentage des apports de référence. Le champ `dosage`
// du catalogue reste une donnée interne, jamais affichée.

final class ComplementsSansDoseTests: XCTestCase {

    private let motifs = [
        #"\d+([.,]\d+)?\s*(µg|mcg|mg|ui|g)\b"#,
        #"\d+\s*(gélule|gelule|comprimé|comprime|goutte|capsule|cuillère|dose)s?\s*(/|par)\s*jour"#,
        #"apports? de référence"#,
        #"\d+\s*%\s*des?\s*(apports|besoins|ar|vnr|ajr)"#,
    ]

    private func porteUneDose(_ texte: String) -> String? {
        let bas = texte.lowercased()
        for motif in motifs {
            if bas.range(of: motif, options: .regularExpression) != nil { return motif }
        }
        return nil
    }

    func testLePourquoiDUneFormeNePorteAucuneDose() {
        XCTAssertFalse(SupplementEngine.catalog.isEmpty)
        for produit in SupplementEngine.catalog {
            XCTAssertNil(porteUneDose(produit.whyBrand), "\(produit.id) : « \(produit.whyBrand) »")
            XCTAssertEqual(PlanTopicText.sansDose(produit.whyBrand), produit.whyBrand, produit.id)
        }
    }

    /// Le détecteur reconnaît bien ce qui a été retiré, et laisse passer un prix.
    func testLeDetecteurVoitLesDosesEtPasLesPrix() {
        XCTAssertNotNil(porteUneDose("Dose élevée (1000 µg) : au-delà de quelques microgrammes"))
        XCTAssertNotNil(porteUneDose("sans excipient. 1 gélule/jour."))
        XCTAssertNotNil(porteUneDose("+ sélénium. 100% des apports de référence."))
        XCTAssertNil(porteUneDose("Format gouttes économique (~0,13 €/jour, ~5 mois d'autonomie)."))
        XCTAssertNil(porteUneDose("Iode d'algue à dosage constant."))
    }
}
