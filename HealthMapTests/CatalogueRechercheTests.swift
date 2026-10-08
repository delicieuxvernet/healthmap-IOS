import XCTest
@testable import HealthMap

/// La recherche dans le téléphone (7 oct. 2026) : même classement que
/// `search_foods_rapide`, sans réseau.
final class CatalogueRechercheTests: XCTestCase {

    /// Un petit catalogue au format du script `generer-catalogue.mjs`.
    private let tsv = [
        "kiwio-catalogue\t1\t20261007120000",
        "c\t32003\tCéréales pour petit déjeuner (aliment moyen)\t\t389\t\t\t0\t0\tproduits sucrés\tcéréales de petit-déjeuner\tcereales pour petit dejeuner aliment moyen\t\t",
        "c\t32100\tCéréales instantanées, poudre à reconstituer\t\t395\t\t\t0\t0\taliments infantiles\tcéréales et biscuits infantiles\tcereales instantanees poudre a reconstituer\t\ti",
        "c\t13050\tPomme, pulpe et peau, crue\t\t54\t\t\t0\t0\tfruits, légumes, légumineuses et oléagineux\tfruits\tpomme pulpe et peau crue\t\t",
        "c\t22000\tOeuf, dur\t\t134\t\t\t0\t0\tviandes, œufs, poissons et assimilés\tœufs\toeuf dur\t\t",
        "o\t7613034626844\tCéréales Chocapic\tNestlé\t380\tB\t761/303/462/6844/front_fr.200.jpg\t0.996\t1\t\t\tcereales chocapic\tnestle\t",
        "o\t3290000000001\tCéréales Méditerranéennes\tTipiak\t360\tA\t\t0.937\t0.5\t\t\tcereales mediterraneennes\ttipiak\t",
        "o\t3290000000002\tCéréales Chocapic\tNestlé\t380\tB\t\t0.900\t1\t\t\tcereales chocapic\tnestle\t",
        "o\t3290000000003\tAmande sans sucre\tBjorg\t13\t\t\t0.800\t0.9\t\t\tamande sans sucre\tbjorg\t",
    ].joined(separator: "\n")

    private func index() throws -> IndexCatalogue {
        try IndexCatalogue(octets: Array(tsv.utf8))
    }

    private func cherche(_ q: String) throws -> [MealJournalService.FoodHit] {
        try index().chercher(CatalogueRecherche.mots(q), limite: 12)
    }

    func testLeCatalogueSeLit() throws {
        let idx = try index()
        XCTAssertEqual(idx.version, "20261007120000")
        XCTAssertEqual(idx.nombre, 8)
    }

    /// « céré » ouvre « Céréales » ; les marques connues passent devant ; un
    /// même produit en double n'apparaît qu'une fois.
    func testUnDebutDeMotTrouveEtClasse() throws {
        let hits = try cherche("céré")
        let produits = hits.filter { $0.source == "off" }
        XCTAssertEqual(produits.map(\.name), ["Céréales Chocapic", "Céréales Méditerranéennes"])
        XCTAssertEqual(produits.first?.id, "off:7613034626844")
        XCTAssertEqual(produits.first?.image,
                       "https://images.openfoodfacts.org/images/products/761/303/462/6844/front_fr.200.jpg")
        XCTAssertEqual(produits.first?.nutriscore, "B")
        // Les céréales infantiles passent derrière celles du petit-déjeuner.
        let aliments = hits.filter { $0.source == "ciqual" }
        XCTAssertEqual(aliments.first?.id, "ciqual:32003")
        XCTAssertEqual(aliments.first?.sousGroupe, "céréales de petit-déjeuner")
    }

    func testLaMarqueSeCherche() throws {
        XCTAssertEqual(try cherche("bjo").map(\.name), ["Amande sans sucre"])
    }

    func testAccentsMajusculesEtLigatures() throws {
        XCTAssertEqual(try cherche("ŒUF").map(\.id), ["ciqual:22000"])
        XCTAssertEqual(try cherche("Pomme crue").map(\.id), ["ciqual:13050"])
        // Chaque mot doit ouvrir un mot : « omme » ne trouve pas « Pomme ».
        XCTAssertTrue(try cherche("omme").isEmpty)
        XCTAssertEqual(CatalogueRecherche.normaliser("  Pâtes, cœur & Bœuf ! "), "pates coeur boeuf")
    }

    func testBebeGardeLesAlimentsInfantiles() throws {
        let hits = try cherche("céréales bébé")
        XCTAssertTrue(hits.isEmpty, "aucun nom ne contient « bébé » ici")
        let infantiles = try cherche("céréales instantanées").filter { $0.source == "ciqual" }
        XCTAssertEqual(infantiles.first?.id, "ciqual:32100")
    }

    /// Le fichier publié est compressé en deflate brut : la relecture iOS doit le décompresser.
    func testLeFichierCompresseSeRelit() throws {
        let compresse = try (Data(tsv.utf8) as NSData).compressed(using: .zlib) as Data
        let idx = try IndexCatalogue(compresse: compresse)
        XCTAssertEqual(idx.nombre, 8)
    }

    func testUnFichierAbimeEstRefuse() {
        XCTAssertThrowsError(try IndexCatalogue(octets: Array("pas un catalogue\n".utf8)))
        XCTAssertThrowsError(try IndexCatalogue(compresse: Data([1, 2, 3])))
    }
}
