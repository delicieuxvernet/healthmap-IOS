import XCTest
@testable import HealthMap

/// Récents et favoris de la recherche (maquette validée le 7 oct. 2026).
final class AlimentsHabituelsTests: XCTestCase {

    /// Un aliment tel que le journal le relit (`meal_scans.detected_foods`).
    private func item(_ nom: String, id: String?, grammes: Double?, kcal: Int = 100) -> MealJournalService.FoodEntry {
        var objet: [String: Any] = ["name_fr": nom, "macros": ["calories": kcal]]
        if let id { objet["food_id"] = id }
        if let grammes { objet["portion_g"] = grammes }
        let data = try! JSONSerialization.data(withJSONObject: objet)
        return try! JSONDecoder().decode(MealJournalService.FoodEntry.self, from: data)
    }

    private func repas(_ id: String, ilYa heures: Double, _ items: [MealJournalService.FoodEntry]) -> MealJournalService.MealRecord {
        MealJournalService.MealRecord(id: id, consumedAt: Date().addingTimeInterval(-heures * 3600),
                                      slot: .breakfast, items: items,
                                      macros: MealJournalService.MealMacros())
    }

    // MARK: Les récents

    /// Le plus récent d'abord, un seul par aliment, avec la quantité de la dernière fois.
    func testLesRecentsGardentLaDerniereQuantite() {
        let recents = AlimentsHabituels.recents([
            repas("a", ilYa: 30, [item("Banane", id: "ciqual:13005", grammes: 120)]),
            repas("b", ilYa: 2, [item("Trésor chocolat noisettes · Kellogg's", id: "off:5053827167777", grammes: 40, kcal: 180),
                                 item("Banane", id: "ciqual:13005", grammes: 100)]),
        ])
        XCTAssertEqual(recents.map(\.id), ["off:5053827167777", "ciqual:13005"])
        XCTAssertEqual(recents[0].nom, "Trésor chocolat noisettes")
        XCTAssertEqual(recents[0].marque, "Kellogg's")
        XCTAssertEqual(recents[0].grammes, 40)
        XCTAssertEqual(recents[0].kcal100g ?? 0, 450, accuracy: 0.01)
        XCTAssertEqual(recents[1].grammes, 100)
        XCTAssertEqual(recents[0].sousTitre, "Kellogg's · 40 g")
        XCTAssertEqual(recents[1].sousTitre, "100 g")
    }

    /// Une saisie libre (sans `food_id`) ou sans quantité ne se remet pas d'un geste.
    func testLesRecentsIgnorentCeQueLaBaseNeConnaitPas() {
        let recents = AlimentsHabituels.recents([
            repas("a", ilYa: 1, [item("Plat de mamie", id: nil, grammes: 300),
                                 item("Pomme", id: "ciqual:13050", grammes: nil),
                                 item("Skyr", id: "off:123", grammes: 150)]),
        ])
        XCTAssertEqual(recents.map(\.id), ["off:123"])
    }

    func testLesRecentsSontBornes() {
        let items = (0..<10).map { item("Aliment \($0)", id: "ciqual:\($0)", grammes: 100) }
        XCTAssertEqual(AlimentsHabituels.recents([repas("a", ilYa: 1, items)], limite: 6).count, 6)
    }

    /// La marque ne se détache que pour un produit de marque.
    func testLaMarqueNeSeDetacheQuePourUnProduit() {
        XCTAssertEqual(AlimentsHabituels.separer("Pâtes · cuites", source: "ciqual").nom, "Pâtes · cuites")
        XCTAssertNil(AlimentsHabituels.separer("Pâtes · cuites", source: "ciqual").marque)
        XCTAssertEqual(AlimentsHabituels.separer("Skyr nature · Siggi's", source: "off").marque, "Siggi's")
    }

    // MARK: Tes aliments, pendant la frappe

    private func aliment(_ id: String, _ nom: String, marque: String? = nil) -> AlimentHabituel {
        AlimentHabituel(id: id, nom: nom, marque: marque, grammes: 100)
    }

    func testLaFrappeTrouveSesAlimentsSansAccentNiMajuscule() {
        let recents = [aliment("off:1", "Céréales Trésor", marque: "Kellogg's"), aliment("ciqual:2", "Banane")]
        XCTAssertEqual(AlimentsHabituels.correspondances("cere", favoris: [], recents: recents).map(\.id), ["off:1"])
        XCTAssertEqual(AlimentsHabituels.correspondances("KEL", favoris: [], recents: recents).map(\.id), ["off:1"])
        XCTAssertEqual(AlimentsHabituels.correspondances("tresor cer", favoris: [], recents: recents).map(\.id), ["off:1"])
        // Un mot doit OUVRIR un mot du nom : « nane » ne trouve pas « Banane ».
        XCTAssertTrue(AlimentsHabituels.correspondances("nane", favoris: [], recents: recents).isEmpty)
        XCTAssertTrue(AlimentsHabituels.correspondances("  ", favoris: [], recents: recents).isEmpty)
    }

    func testLesFavorisPassentDevantSansDoublon() {
        let skyr = aliment("off:9", "Skyr nature")
        let resultat = AlimentsHabituels.correspondances("s", favoris: [skyr],
                                                         recents: [aliment("ciqual:3", "Saumon"), skyr])
        XCTAssertEqual(resultat.map(\.id), ["off:9", "ciqual:3"])
    }

    // MARK: La mémoire

    @MainActor
    func testUnFavoriSeRetientParCompte() {
        let defaults = UserDefaults(suiteName: "AlimentsHabituelsTests")!
        defaults.removePersistentDomain(forName: "AlimentsHabituelsTests")
        let store = AlimentsHabituelsStore(defaults: defaults)
        store.charger(compte: "a")
        store.basculer(aliment("off:1", "Trésor"))
        XCTAssertTrue(store.estFavori("off:1"))

        let relu = AlimentsHabituelsStore(defaults: defaults)
        relu.charger(compte: "a")
        XCTAssertEqual(relu.favoris.map(\.id), ["off:1"])
        relu.charger(compte: "b")
        XCTAssertTrue(relu.favoris.isEmpty)

        store.basculer(aliment("off:1", "Trésor"))
        XCTAssertFalse(store.estFavori("off:1"))
    }

    /// Après un ajout, un favori garde la quantité de la dernière fois.
    @MainActor
    func testUnFavoriSuitLaDerniereQuantite() {
        let defaults = UserDefaults(suiteName: "AlimentsHabituelsTests2")!
        defaults.removePersistentDomain(forName: "AlimentsHabituelsTests2")
        let store = AlimentsHabituelsStore(defaults: defaults)
        store.charger(compte: "a")
        store.basculer(aliment("off:1", "Trésor"))
        let detail = MealJournalService.FoodDetail(id: "off:1", source: "off", name: "Trésor",
                                                   brand: "Kellogg's", kcal100g: 450)
        store.apresAjout(detail, grammes: 45)
        XCTAssertEqual(store.favoris.first?.grammes, 45)
    }
}
