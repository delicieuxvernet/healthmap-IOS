import XCTest
@testable import HealthMap

// MARK: - Journal par aliment (P1) — décodage detected_foods + agrégats
// Pure logique : décodage tolérant des DEUX formes de `detected_foods`
// (chaînes nues / objets riches), soustraction d'agrégats à la suppression
// d'un item, et découpe en lignes affichables (MealJournalRow).

final class JournalItemsTests: XCTestCase {
    private typealias S = MealJournalService

    private func decodeEntries(_ json: String) throws -> [S.FoodEntry] {
        try JSONDecoder().decode([S.FoodEntry].self, from: Data(json.utf8))
    }

    private func record(items: [S.FoodEntry],
                        macros: S.MealMacros = .init(),
                        micros: [S.MicroPct] = []) -> S.MealRecord {
        S.MealRecord(id: "r1", consumedAt: Date(timeIntervalSince1970: 0),
                     slot: .lunch, items: items, macros: macros, micros: micros)
    }

    // MARK: - Décodage : forme legacy (chaînes nues)

    func testDecode_legacyStrings_namesOnly() throws {
        let entries = try decodeEntries(#"["Poulet rôti", "Riz"]"#)
        XCTAssertEqual(entries.map(\.name), ["Poulet rôti", "Riz"])
        XCTAssertNil(entries[0].portionG)
        XCTAssertNil(entries[0].macros)
        XCTAssertNil(entries[0].micros)
    }

    // MARK: - Décodage : forme riche (objets Edge ≥ v5)

    func testDecode_richObjects_keepPortionMacrosMicros() throws {
        let json = #"""
        [{"name_fr":"Saumon","portion_g":130,
          "macros":{"calories":270.4,"proteins":26,"carbs":0,"fats":16.9,"fiber":0},
          "micros":[{"id":"omega3","unit":"g","amount":2.1,"pctRDA":85.4}]}]
        """#
        let entries = try decodeEntries(json)
        XCTAssertEqual(entries.count, 1)
        let e = entries[0]
        XCTAssertEqual(e.name, "Saumon")
        XCTAssertEqual(e.portionG, 130)                    // entier JSON → Double
        XCTAssertEqual(e.macros?.calories, 270)            // décimal → arrondi
        XCTAssertEqual(e.macros?.fats ?? 0, 16.9, accuracy: 0.001)
        XCTAssertEqual(e.micros?.first?.id, "omega3")
        XCTAssertEqual(e.micros?.first?.pctRDA, 85)        // décimal → arrondi
        XCTAssertEqual(e.micros?.first?.amount ?? 0, 2.1, accuracy: 0.001)
        XCTAssertEqual(e.micros?.first?.unit, "g")
        XCTAssertNotNil(e.raw)                             // passthrough capturé
    }

    // MARK: - Passthrough : les clés annexes de l'Edge survivent à la réécriture

    func testEncode_richObject_preservesUnknownKeys() throws {
        // Clés réellement écrites par l'Edge et lues par le web/day_summary :
        // ciqual_code, confidence, nova_class, match_similarity, micros[].amount.
        let json = #"""
        [{"name_fr":"Poulet","portion_g":150,"ciqual_code":null,"confidence":0.9,
          "nova_class":4,"match_similarity":0.82,
          "macros":{"calories":248,"proteins":46.5,"carbs":0,"fats":5.4,"fiber":0},
          "micros":[{"id":"vitB12","amount":0.72,"unit":"","pctRDA":30}]}]
        """#
        let entries = try decodeEntries(json)
        let out = String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
        XCTAssertTrue(out.contains(#""confidence":0.9"#))
        XCTAssertTrue(out.contains(#""nova_class":4"#))
        XCTAssertTrue(out.contains(#""match_similarity":0.82"#))
        XCTAssertTrue(out.contains(#""ciqual_code":null"#))
        XCTAssertTrue(out.contains(#""amount":0.72"#))
        XCTAssertTrue(out.contains(#""name_fr":"Poulet""#))
        // Et le round-trip complet reste stable.
        XCTAssertEqual(try decodeEntries(out), entries)
    }

    func testDecode_mixedForms_bothSurvive() throws {
        let json = #"""
        ["Salade verte",
         {"name_fr":"Poulet","portion_g":150,
          "macros":{"calories":248,"proteins":46.5,"carbs":0,"fats":5.4,"fiber":0}}]
        """#
        let entries = try decodeEntries(json)
        XCTAssertEqual(entries.map(\.name), ["Salade verte", "Poulet"])
        XCTAssertNil(entries[0].macros)
        XCTAssertNotNil(entries[1].macros)
    }

    // MARK: - Encodage : toujours la forme objet (contrat Edge)

    func testEncode_writesObjectShape() throws {
        let entry = S.FoodEntry(name: "Poulet", portionG: 150,
                                macros: .init(calories: 248, proteins: 46.5),
                                micros: [.init(id: "b12", pctRDA: 30)])
        let data = try JSONEncoder().encode([entry])
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""name_fr":"Poulet""#))
        XCTAssertTrue(json.contains(#""portion_g":150"#))
        // Round-trip champ à champ (le décodage repeuple `raw`, comparer
        // l'entrée entière échouerait par construction).
        let back = try decodeEntries(json)
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].name, entry.name)
        XCTAssertEqual(back[0].portionG, entry.portionG)
        XCTAssertEqual(back[0].macros, entry.macros)
        XCTAssertEqual(back[0].micros?.map(\.id), ["b12"])
        XCTAssertEqual(back[0].micros?.map(\.pctRDA), [30])
    }

    // MARK: - MealMacros : décodage tolérant

    func testMealMacros_missingKeyAndDecimalCalories() throws {
        // fiber absent + calories décimales — ne doit PAS échouer (avant :
        // tout le décodage tombait et les macros étaient remises à zéro).
        let json = #"{"calories":248.6,"proteins":10,"carbs":20,"fats":5}"#
        let m = try JSONDecoder().decode(S.MealMacros.self, from: Data(json.utf8))
        XCTAssertEqual(m.calories, 249)
        XCTAssertEqual(m.fiber, 0)
    }

    // MARK: - hasItemDetail

    func testHasItemDetail_trueOnlyWhenEveryItemHasMacros() {
        let rich = S.FoodEntry(name: "A", portionG: 100, macros: .init(calories: 100))
        let bare = S.FoodEntry(name: "B")
        XCTAssertTrue(record(items: [rich, rich]).hasItemDetail)
        XCTAssertFalse(record(items: [rich, bare]).hasItemDetail)
        XCTAssertFalse(record(items: []).hasItemDetail)
    }

    func testFoods_compatMapping() {
        let rec = record(items: [S.FoodEntry(name: "A"), S.FoodEntry(name: "")])
        XCTAssertEqual(rec.foods, ["A"])                   // noms vides filtrés
        // Init de compat par noms seuls (tests historiques, ajouts manuels).
        let legacy = S.MealRecord(id: "x", consumedAt: Date(), slot: .snack,
                                  foods: ["Pomme"], macros: .init(calories: 52))
        XCTAssertEqual(legacy.items.map(\.name), ["Pomme"])
        XCTAssertFalse(legacy.hasItemDetail)
    }

    // MARK: - aggregatesFromItems : recomposition miroir Edge

    func testAggregatesFromItems_sumsMacrosAndDerivesAmounts() {
        let items = [
            S.FoodEntry(name: "A", portionG: 100,
                        macros: .init(calories: 248, proteins: 46.5, carbs: 0.05, fats: 5.4, fiber: 0),
                        micros: [.init(id: "iron", pctRDA: 30)]),
            S.FoodEntry(name: "B", portionG: 200,
                        macros: .init(calories: 260, proteins: 5.4, carbs: 56.02, fats: 0.6, fiber: 1.4),
                        micros: [.init(id: "iron", pctRDA: 25), .init(id: "zinc", pctRDA: 10)]),
        ]
        let (m, mm) = S.aggregatesFromItems(items)
        XCTAssertEqual(m.calories, 508)
        XCTAssertEqual(m.proteins, 51.9, accuracy: 0.001)  // arrondi 0,1 g
        XCTAssertEqual(m.carbs, 56.1, accuracy: 0.001)
        // iron : 30+25 = 55 % → amount = 0,55 × RDA(18 mg) = 9,9
        XCTAssertEqual(mm[0], S.MicroPct(id: "iron", pctRDA: 55, amount: 9.9, unit: ""))
        // zinc : 10 % → 1,1 mg (RDA 11)
        XCTAssertEqual(mm[1], S.MicroPct(id: "zinc", pctRDA: 10, amount: 1.1, unit: ""))
    }

    func testAggregatesFromItems_clampMirrorsEdge() {
        // Deux items à 80 % de vitD → la ligne plafonne à 100 (miroir Edge) ;
        // c'est POUR ÇA qu'on recompose au lieu de soustraire (retirer un
        // item doit laisser 80, pas 100 − 80 = 20).
        let it = { S.FoodEntry(name: "X", macros: .init(),
                               micros: [S.MicroPct(id: "vitD", pctRDA: 80)]) }
        let both = S.aggregatesFromItems([it(), it()])
        XCTAssertEqual(both.micros, [S.MicroPct(id: "vitD", pctRDA: 100, amount: 15, unit: "")])
        let one = S.aggregatesFromItems([it()])
        XCTAssertEqual(one.micros, [S.MicroPct(id: "vitD", pctRDA: 80, amount: 12, unit: "")])
    }

    func testAggregatesFromItems_orderZerosAndUnknownIds() {
        let items = [
            S.FoodEntry(name: "A", macros: .init(),
                        micros: [.init(id: "zinc", pctRDA: 0), .init(id: "mystery", pctRDA: 40)]),
            S.FoodEntry(name: "B", macros: .init(),
                        micros: [.init(id: "iron", pctRDA: 20)]),
        ]
        let (_, mm) = S.aggregatesFromItems(items)
        // Ordre de première apparition ; les 0 % restent (contrat Edge :
        // toutes les entrées présentes) ; id hors table RDA → pas d'amount.
        XCTAssertEqual(mm.map(\.id), ["zinc", "mystery", "iron"])
        XCTAssertEqual(mm[0], S.MicroPct(id: "zinc", pctRDA: 0, amount: 0, unit: ""))
        XCTAssertEqual(mm[1].pctRDA, 40)
        XCTAssertNil(mm[1].amount)
        XCTAssertNil(mm[1].unit)
    }

    func testAggregatesFromItems_skipsItemsWithoutMacros() {
        let (m, _) = S.aggregatesFromItems([
            S.FoodEntry(name: "riche", macros: .init(calories: 100)),
            S.FoodEntry(name: "nu"),
        ])
        XCTAssertEqual(m.calories, 100)
    }

    // MARK: - MealJournalRow (lignes affichables)

    func testRow_itemLevel_exposesItemValues() {
        let items = [
            S.FoodEntry(name: "Poulet", portionG: 150,
                        macros: .init(calories: 248, proteins: 46),
                        micros: [.init(id: "b12", pctRDA: 30)]),
            S.FoodEntry(name: "Riz", portionG: 200, macros: .init(calories: 260)),
        ]
        let rec = record(items: items, macros: .init(calories: 508))
        let row = MealJournalRow(record: rec, itemIndex: 0)
        XCTAssertEqual(row.id, "r1#0")
        XCTAssertEqual(row.name, "Poulet")
        XCTAssertEqual(row.grams, 150)
        XCTAssertEqual(row.calories, 248)
        XCTAssertEqual(row.iconMicroId, "b12")
        XCTAssertFalse(row.deletesWholeRecord)             // 2 items → item seul
        XCTAssertFalse(row.isAggregate)
    }

    func testRow_aggregate_fallsBackToRecord() {
        let rec = S.MealRecord(id: "r2", consumedAt: Date(), slot: .dinner,
                               foods: ["Salade", "Tomates", "Œufs", "Pain"],
                               macros: .init(calories: 420),
                               micros: [.init(id: "folate", pctRDA: 25)])
        let row = MealJournalRow(record: rec, itemIndex: nil)
        XCTAssertEqual(row.id, "r2")
        XCTAssertEqual(row.name, "Salade, Tomates, Œufs")  // 3 premiers noms
        XCTAssertNil(row.grams)                            // jamais inventé
        XCTAssertEqual(row.calories, 420)
        XCTAssertEqual(row.iconMicroId, "folate")
        XCTAssertTrue(row.deletesWholeRecord)
        XCTAssertTrue(row.isAggregate)
    }

    func testRow_lastItem_deletesWholeRecord() {
        let rec = record(items: [S.FoodEntry(name: "Solo", portionG: 100,
                                             macros: .init(calories: 90))])
        let row = MealJournalRow(record: rec, itemIndex: 0)
        XCTAssertTrue(row.deletesWholeRecord)              // dernier aliment
    }
}

// MARK: - rows(in:) — découpe par créneau (VM, @MainActor)

@MainActor
final class JournalRowsSplitTests: XCTestCase {
    private typealias S = MealJournalService

    func testRows_richRecordSplits_legacyStaysWhole() {
        let rich = S.MealRecord(
            id: "rich", consumedAt: Date(), slot: .lunch,
            items: [S.FoodEntry(name: "A", portionG: 100, macros: .init(calories: 100)),
                    S.FoodEntry(name: "B", portionG: 50, macros: .init(calories: 50))],
            macros: .init(calories: 150)
        )
        let legacy = S.MealRecord(id: "leg", consumedAt: Date(), slot: .lunch,
                                  foods: ["Ancien scan", "Autre"],
                                  macros: .init(calories: 300))
        let other = S.MealRecord(id: "oth", consumedAt: Date(), slot: .dinner,
                                 foods: ["Soir"], macros: .init(calories: 200))
        let vm = MealJournalViewModel()
        vm.meals = [rich, legacy, other]

        let lunchRows = vm.rows(in: .lunch)
        XCTAssertEqual(lunchRows.map(\.id), ["rich#0", "rich#1", "leg"])
        XCTAssertEqual(vm.rows(in: .dinner).map(\.id), ["oth"])
        XCTAssertTrue(vm.rows(in: .breakfast).isEmpty)
    }
}
