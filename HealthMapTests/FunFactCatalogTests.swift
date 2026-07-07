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

    // MARK: - Exactitude par valeur (régression du bug signalé)

    /// Valeur pile sur un repère : formulation « Pile la taille de X ».
    func testHeight_170_exactMatch_saysPile() {
        let fact = FunFactCatalog.fact(for: "height", value: 170)
        XCTAssertTrue(
            fact?.contains("Pile la taille de") == true && fact?.contains("Messi") == true,
            "170 cm should be an exact Messi match, got: \(fact ?? "nil")"
        )
    }

    /// Bug signalé : 181 cm affichait « comme Zidane 185 » (fourchette 181-187).
    /// Désormais 181 ne doit PLUS revendiquer 185 ni Zidane, mais un écart
    /// honnête vers le repère le plus proche (Mbappé 178).
    func testHeight_181_isNotFalselyZidane() {
        let fact = FunFactCatalog.fact(for: "height", value: 181)
        XCTAssertEqual(fact?.contains("185"), false, "181 cm must not claim 185 cm, got: \(fact ?? "nil")")
        XCTAssertEqual(fact?.contains("Zidane"), false, "181 cm must not claim Zidane, got: \(fact ?? "nil")")
        XCTAssertTrue(fact?.contains("Mbappe") == true, "181 cm should anchor on nearest ref Mbappe, got: \(fact ?? "nil")")
    }

    /// Invariant fort : une affirmation « Pile la taille de X (H cm) » ne peut
    /// exister que si H == la valeur choisie. On n'attribue JAMAIS à une valeur
    /// la taille exacte d'une célébrité qui n'est pas la sienne — cœur de la
    /// demande d'Arthur : zéro information fausse par centimètre.
    func testHeight_exactClaimIsAlwaysTrue() {
        for cm in 140...216 {
            guard let fact = FunFactCatalog.fact(for: "height", value: Double(cm)) else {
                XCTFail("No fact for \(cm) cm"); continue
            }
            guard fact.hasPrefix("Pile la taille de") else { continue }
            guard let open = fact.lastIndex(of: "("),
                  let cmMark = fact.range(of: " cm)") else {
                XCTFail("Malformed exact claim at \(cm): \(fact)"); continue
            }
            let claimed = Int(fact[fact.index(after: open)..<cmMark.lowerBound]) ?? -1
            XCTAssertEqual(claimed, cm, "Exact claim height mismatch at \(cm): \(fact)")
        }
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
