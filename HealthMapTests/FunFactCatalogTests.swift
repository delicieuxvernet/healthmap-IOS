import XCTest
@testable import HealthMap

// MARK: - Fun Fact Catalog Tests (Lot E — questionnaire premium & engageant)
// Valide la couverture totale des ranges des sliders, les repères clés
// (exemple fondateur : 184 cm → Zidane), et l'exclusion ABSOLUE du poids.

final class FunFactCatalogTests: XCTestCase {

    // MARK: - Exclusion du poids (sujet sensible)

    /// Le poids ne doit JAMAIS avoir de fun fact — aucune comparaison à des
    /// personnes, aucun jugement. C'est un choix produit délibéré.
    func testWeight_neverHasFunFact() {
        XCTAssertFalse(FunFactCatalog.hasFacts(for: "weight"))
        for value in stride(from: 35.0, through: 180.0, by: 0.5) {
            XCTAssertNil(FunFactCatalog.fact(for: "weight", value: value))
        }
    }

    /// Les questions sans catalogue (fréquences alimentaires...) renvoient nil.
    func testOtherSliders_haveNoFunFact() {
        for id in ["vegetableServings", "fruitServings", "fattyFish", "meatPoultry", "firstName"] {
            XCTAssertFalse(FunFactCatalog.hasFacts(for: id))
            XCTAssertNil(FunFactCatalog.fact(for: id, value: 7))
        }
    }

    // MARK: - Couverture des ranges

    /// Tout le range du slider taille (140-220 cm) doit produire un fait.
    func testHeight_coversFullSliderRange() {
        for cm in 140...220 {
            XCTAssertNotNil(FunFactCatalog.fact(for: "height", value: Double(cm)), "No height fact for \(cm) cm")
        }
    }

    /// Tout le range du slider âge (14-100 ans) doit produire un fait.
    func testAge_coversFullSliderRange() {
        for years in 14...100 {
            XCTAssertNotNil(FunFactCatalog.fact(for: "age", value: Double(years)), "No age fact for \(years) years")
        }
    }

    // MARK: - Repères clés

    /// Exemple verbatim du fondateur : 184 cm → « comme Zidane ».
    func testHeight_184_isZidane() {
        let fact = FunFactCatalog.fact(for: "height", value: 184)
        XCTAssertTrue(fact?.contains("Zidane") == true, "184 cm should reference Zidane, got: \(fact ?? "nil")")
    }

    /// Repère Mbappé à 178 cm (spécification produit).
    func testHeight_178_isMbappe() {
        let fact = FunFactCatalog.fact(for: "height", value: 178)
        XCTAssertTrue(fact?.contains("Mbappe") == true, "178 cm should reference Mbappe, got: \(fact ?? "nil")")
    }

    /// Humour tour Eiffel aux extrêmes hauts du slider.
    func testHeight_extreme_isEiffelTower() {
        let fact = FunFactCatalog.fact(for: "height", value: 220)
        XCTAssertTrue(fact?.contains("Eiffel") == true, "220 cm should joke about the Eiffel tower, got: \(fact ?? "nil")")
    }

    /// Les valeurs sont arrondies avant le choix de plage (slider en pas
    /// entiers, mais la fonction reste totale sur Double).
    func testFact_roundsValueBeforeBandLookup() {
        XCTAssertEqual(
            FunFactCatalog.fact(for: "height", value: 184.4),
            FunFactCatalog.fact(for: "height", value: 184)
        )
    }

    // MARK: - Conformité langage

    /// Aucun fun fact ne doit contenir de vocabulaire interdit (même liste
    /// que VoiceComplianceTests) ni de caractère accentué (convention des
    /// libellés questionnaire).
    func testFacts_useCompliantAccentFreeLanguage() {
        let forbidden = ["carence", "diagnostic", "patient", "maladie"]
        let accents = CharacterSet(charactersIn: "àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ")

        var allFacts: [String] = []
        for cm in 140...220 {
            if let fact = FunFactCatalog.fact(for: "height", value: Double(cm)) { allFacts.append(fact) }
        }
        for years in 14...100 {
            if let fact = FunFactCatalog.fact(for: "age", value: Double(years)) { allFacts.append(fact) }
        }

        for fact in allFacts {
            let lower = fact.lowercased()
            for word in forbidden {
                XCTAssertFalse(lower.contains(word), "Fun fact contains forbidden word \"\(word)\": \(fact)")
            }
            XCTAssertNil(
                fact.rangeOfCharacter(from: accents),
                "Fun fact should not contain accented characters: \(fact)"
            )
        }
    }
}
