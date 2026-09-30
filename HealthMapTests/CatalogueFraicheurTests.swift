import XCTest
@testable import HealthMap

// MARK: - Cohérence interne du catalogue
//
// L'audit du 30 septembre 2026 a trouvé six écarts entre le catalogue et les
// fiches officielles : deux prix faux du simple au double, deux adresses en
// 404, une référence en rupture. Les prix, eux, ne se vérifient que sur le web.
//
// Ce que ces tests attrapent, c'est la dérive INTERNE : un prix corrigé dans
// un champ et pas dans la phrase qui l'annonce. C'est le genre d'incohérence
// qui survit à un audit parce qu'on regarde la fiche du fabricant, pas la
// nôtre.

final class CatalogueFraicheurTests: XCTestCase {

    /// « ~0,13 €/jour » dans le « pourquoi cette forme » doit correspondre au
    /// coût réellement calculé à partir du prix, des prises et du conditionnement.
    func testLesCoutsAnnoncesCorrespondentAuCalcul() {
        let motif = #"([0-9]+)[.,]([0-9]+)\s*€\s*(/|par)\s*jour"#
        var verifies = 0

        for produit in SupplementEngine.catalog {
            guard let plage = produit.whyBrand.range(of: motif, options: .regularExpression) else { continue }
            let extrait = String(produit.whyBrand[plage])
            let chiffres = extrait.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted)
                .filter { !$0.isEmpty }
            guard chiffres.count >= 2,
                  let entier = Double(chiffres[0]),
                  let decimales = Double(chiffres[1]) else {
                XCTFail("\(produit.id) : coût annoncé illisible — « \(extrait) »")
                continue
            }
            let annonce = entier + decimales / pow(10, Double(chiffres[1].count))
            XCTAssertEqual(
                annonce, produit.dailyCost, accuracy: 0.02,
                "\(produit.id) annonce \(extrait) mais coûte \(produit.dailyCost) €/jour"
            )
            verifies += 1
        }

        XCTAssertGreaterThan(verifies, 0, "aucun coût annoncé trouvé : le motif a dû changer")
    }

    /// Une durée d'autonomie annoncée doit correspondre au conditionnement.
    func testLesAutonomiesAnnonceesCorrespondentAuConditionnement() {
        for produit in SupplementEngine.catalog {
            guard let plage = produit.whyBrand.range(of: #"([0-9]+) mois d'autonomie"#, options: .regularExpression),
                  let mois = Int(String(produit.whyBrand[plage]).components(separatedBy: " ")[0].filter(\.isNumber))
            else { continue }
            let moisReels = Double(produit.daysPerPackage) / 30.0
            XCTAssertEqual(
                Double(mois), moisReels, accuracy: 1.0,
                "\(produit.id) annonce \(mois) mois mais tient \(produit.daysPerPackage) jours"
            )
        }
    }

    /// Chaque fiche pointe vers une adresse plausible et sûre.
    func testChaqueFichePointeVersUneAdresseSure() {
        for produit in SupplementEngine.catalog {
            XCTAssertTrue(produit.productURL.hasPrefix("https://"), "\(produit.id) : adresse non chiffrée")
            XCTAssertNotNil(URL(string: produit.productURL), "\(produit.id) : adresse invalide")
            XCTAssertFalse(produit.productURL.hasSuffix("/"), "\(produit.id) : adresse sans fiche produit")
        }
    }

    /// La date d'audit doit être lisible et plausible — pas un champ libre.
    func testLaDateDAuditEstUneVraieDate() {
        let formateur = DateFormatter()
        formateur.dateFormat = "yyyy-MM-dd"
        formateur.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formateur.date(from: SupplementEngine.catalogVerifiedAt) else {
            XCTFail("`catalogVerifiedAt` illisible : \(SupplementEngine.catalogVerifiedAt)"); return
        }
        XCTAssertLessThanOrEqual(date, Date(), "date d'audit dans le futur")
    }

    /// Chaque nutriment recommandable a au moins une référence, et le tier
    /// `value` n'est jamais plus cher que le `premium` du même nutriment.
    func testAucunEcoPlusCherQueSonPremium() {
        let parNutriment = Dictionary(grouping: SupplementEngine.catalog, by: { $0.nutrientID })
        for (nutriment, produits) in parNutriment {
            let premium = produits.first { $0.tier == .premium }
            let eco = produits.first { $0.tier == .value }
            guard let premium, let eco else { continue }
            XCTAssertLessThanOrEqual(
                eco.monthlyCost, premium.monthlyCost,
                "\(nutriment.rawValue) : l'éco (\(eco.id)) coûte plus cher que le premium"
            )
        }
    }
}
