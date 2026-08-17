import XCTest
@testable import HealthMap

// MARK: - Catalogue des stats France (mode découverte V12b)
//
// Garanties testées :
//   • couverture explicite des 10 nutriments canoniques ;
//   • chaque entrée porte un texte ET une source ;
//   • fractions simples validées (jamais de décimale, jamais de %) ;
//   • vocabulaire conforme (aucun mot proscrit) — test dédié du catalogue,
//     en PLUS du scan global de VoiceComplianceTests sur les sources ;
//   • repli prudent pour un id inconnu (on n'invente jamais un chiffre).
final class TeaserStatsCatalogTests: XCTestCase {

    private let motsProscrits = ["carence", "diagnostic", "patient", "maladie"]

    /// Les 10 nutriments canoniques ont chacun une entrée explicite.
    func testCatalogueCouvreLesDixNutrimentsCanoniques() {
        for def in NutrientData.all {
            XCTAssertNotNil(
                TeaserStatsCatalog.parNutriment[def.id.rawValue],
                "Entrée manquante dans le catalogue pour \(def.id.rawValue)"
            )
        }
        XCTAssertEqual(TeaserStatsCatalog.parNutriment.count, NutrientData.all.count,
                       "Le catalogue ne doit porter que les ids canoniques")
    }

    /// Chaque entrée (générique comprise) porte un texte ET une source.
    func testChaqueEntreePorteTexteEtSource() {
        for (id, stat) in TeaserStatsCatalog.parNutriment {
            XCTAssertFalse(stat.texte.isEmpty, "texte vide pour \(id)")
            XCTAssertFalse(stat.source.isEmpty, "source vide pour \(id)")
        }
        XCTAssertFalse(TeaserStatsCatalog.generique.texte.isEmpty)
        XCTAssertFalse(TeaserStatsCatalog.generique.source.isEmpty)
    }

    /// Les 5 nutriments documentés portent la fraction validée (ordres de
    /// grandeur d'études publiques françaises).
    func testFractionsValidees() {
        XCTAssertEqual(TeaserStatsCatalog.stat(for: "vitD").fraction, "7 sur 10")
        XCTAssertEqual(TeaserStatsCatalog.stat(for: "vitD").source, "Esteban")
        XCTAssertEqual(TeaserStatsCatalog.stat(for: "magnesium").fraction, "1 sur 3")
        XCTAssertEqual(TeaserStatsCatalog.stat(for: "iron").fraction, "1 sur 4")
        XCTAssertEqual(TeaserStatsCatalog.stat(for: "omega3").fraction, "9 sur 10")
        XCTAssertEqual(TeaserStatsCatalog.stat(for: "fiber").fraction, "9 sur 10")
    }

    /// Les 5 nutriments sans chiffre solide restent prudents : pas de
    /// fraction, formulation générique.
    func testNutrimentsSansChiffreSolide_restentGeneriques() {
        for id in ["vitB12", "vitC", "calcium", "zinc", "iodine"] {
            let stat = TeaserStatsCatalog.stat(for: id)
            XCTAssertNil(stat.fraction, "\(id) ne doit porter aucun chiffre inventé")
            XCTAssertEqual(stat.texte, TeaserStatsCatalog.generique.texte)
        }
    }

    /// Fractions simples : jamais de décimale, jamais de pourcentage.
    func testFractionsSimples_sansDecimaleNiPourcentage() {
        for (id, stat) in TeaserStatsCatalog.parNutriment {
            guard let fraction = stat.fraction else { continue }
            XCTAssertNil(
                fraction.range(of: #"\d[.,]\d"#, options: .regularExpression),
                "Décimale interdite dans la fraction de \(id) : \(fraction)"
            )
            XCTAssertFalse(fraction.contains("%"), "Pas de pourcentage dans la fraction de \(id)")
        }
    }

    /// Aucun mot proscrit dans aucun champ affiché (texte, fraction, source,
    /// phrase d'accessibilité).
    func testAucunMotProscritDansLesChampsAffiches() {
        var champs: [String] = [TeaserStatsCatalog.generique.accessibilite]
        for stat in TeaserStatsCatalog.parNutriment.values {
            champs.append(contentsOf: [stat.texte, stat.source, stat.fraction ?? "", stat.accessibilite])
        }
        for champ in champs {
            let lower = champ.lowercased()
            for mot in motsProscrits {
                XCTAssertNil(
                    lower.range(of: "\\b\(mot)\\b", options: .regularExpression),
                    "Mot proscrit « \(mot) » dans : \(champ)"
                )
            }
        }
    }

    /// Repli prudent : un id inconnu retombe sur la formulation générique.
    func testStatPourIdInconnu_retombeSurLeGenerique() {
        let stat = TeaserStatsCatalog.stat(for: "inconnu")
        XCTAssertNil(stat.fraction)
        XCTAssertEqual(stat.texte, TeaserStatsCatalog.generique.texte)
        XCTAssertEqual(stat.source, TeaserStatsCatalog.generique.source)
    }
}
