import XCTest
@testable import HealthMap

// MARK: - Grocery Catalog Tests
// Verrouille l'intégrité du catalogue "Faites vos courses" : ids uniques, tags
// nutriments valides, et SURTOUT la garantie de couverture issue de l'audit
// Ciqual (chaque nutriment doit garder >= 3 aliments-sources, sinon le score de
// ce nutriment serait famélique). Ce test échoue si une future modification du
// catalogue casse cette garantie.

final class GroceryCatalogTests: XCTestCase {

    func testItemIdsAreUnique() {
        let ids = GroceryCatalog.allItems.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Les ids du catalogue doivent être uniques")
    }

    func testItemsHaveNameAndEmoji() {
        for item in GroceryCatalog.allItems {
            XCTAssertFalse(item.id.isEmpty, "id vide")
            XCTAssertFalse(item.name.isEmpty, "nom vide pour \(item.id)")
            XCTAssertFalse(item.emoji.isEmpty, "emoji vide pour \(item.id)")
        }
    }

    func testCatalogVolumeAndAisles() {
        XCTAssertEqual(GroceryCatalog.aisles.count, 8, "8 rayons attendus")
        XCTAssertGreaterThanOrEqual(GroceryCatalog.allItems.count, 100,
                                    "catalogue exhaustif des best-sellers (>= 100 aliments)")
    }

    func testEveryNutrientHasAtLeastThreeSources() {
        for nutrient in GroceryNutrient.allCases {
            let sources = GroceryCatalog.items(providing: nutrient)
            XCTAssertGreaterThanOrEqual(
                sources.count, 3,
                "Le nutriment \(nutrient.rawValue) doit garder >= 3 sources (garantie audit Ciqual)"
            )
        }
    }

    func testItemLookupById() {
        XCTAssertEqual(GroceryCatalog.item(id: "saumon")?.name, "Saumon")
        XCTAssertNil(GroceryCatalog.item(id: "aliment_inexistant_xyz"))
    }

    func testAisleIdsAreUnique() {
        let ids = GroceryCatalog.aisles.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Les ids de rayons doivent être uniques")
    }
}
