import XCTest
@testable import HealthMap

// Verrouille la conversion fourchette → portions/semaine et le mapping rayon →
// famille de l'écran quantités du caddie. Le contrat aval (`groceries: [String:Int]`)
// ne doit jamais changer : ces tests garantissent que la couche de saisie reste
// transparente pour le moteur de score et le prompt IA.
final class QuantityBracketTests: XCTestCase {

    func testMedianConversionTable() {
        XCTAssertEqual(QuantityBracket.rare.medianPortionsPerWeek, 1)
        XCTAssertEqual(QuantityBracket.occasional.medianPortionsPerWeek, 2)
        XCTAssertEqual(QuantityBracket.frequent.medianPortionsPerWeek, 5)
        XCTAssertEqual(QuantityBracket.daily.medianPortionsPerWeek, 10)
    }

    func testBracketFromStoredPortions() {
        XCTAssertEqual(QuantityBracket.from(portions: 0), .rare)
        XCTAssertEqual(QuantityBracket.from(portions: 1), .rare)
        XCTAssertEqual(QuantityBracket.from(portions: 2), .occasional)
        XCTAssertEqual(QuantityBracket.from(portions: 3), .occasional)
        XCTAssertEqual(QuantityBracket.from(portions: 4), .frequent)
        XCTAssertEqual(QuantityBracket.from(portions: 6), .frequent)
        XCTAssertEqual(QuantityBracket.from(portions: 7), .daily)
        XCTAssertEqual(QuantityBracket.from(portions: 21), .daily)
    }

    /// La médiane d'une fourchette doit toujours retomber sur cette fourchette :
    /// garantit qu'un aller-retour saisie → stockage → réaffichage est stable.
    func testMedianRoundTripIsStable() {
        for bracket in QuantityBracket.allCases {
            XCTAssertEqual(QuantityBracket.from(portions: bracket.medianPortionsPerWeek), bracket)
        }
    }

    func testEveryAisleIsMappedToExactlyOneFamily() {
        for aisle in GroceryCatalog.aisles {
            let families = QuantityFamily.all.filter { $0.aisleIds.contains(aisle.id) }
            XCTAssertEqual(families.count, 1, "Le rayon \(aisle.id) doit appartenir à exactement une famille")
        }
    }

    func testEveryGroceryItemResolvesToAFamily() {
        for item in GroceryCatalog.allItems {
            let family = QuantityFamily.family(forItemId: item.id)
            XCTAssertTrue(QuantityFamily.all.contains { $0.id == family.id },
                          "L'aliment \(item.id) doit être rattaché à une famille connue")
        }
    }
}
