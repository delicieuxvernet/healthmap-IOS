import XCTest
@testable import HealthMap

// MARK: - Journal en double (7 oct. 2026)
// Une archive chargée avant la quinzaine la recouvrait : chaque repas du jour
// s'affichait deux fois. La fusion garde chaque repas une seule fois.

final class JournalFusionTests: XCTestCase {

    private func repas(_ id: String, kcal: Int = 100) -> MealJournalService.MealRecord {
        MealJournalService.MealRecord(
            id: id, consumedAt: Date(), slot: .lunch, foods: ["Pomme"],
            macros: .init(calories: kcal, proteins: 0, carbs: 0, fats: 0, fiber: 0)
        )
    }

    func testUnRepasPresentDesDeuxCotesNeCompteQuUneFois() {
        let fusion = MealJournalViewModel.fusion([repas("a"), repas("b")], [repas("a"), repas("b"), repas("c")])
        XCTAssertEqual(fusion.map(\.id), ["a", "b", "c"])
    }

    func testLaQuinzaineFaitFoi() {
        let fusion = MealJournalViewModel.fusion([repas("a", kcal: 250)], [repas("a", kcal: 100)])
        XCTAssertEqual(fusion.count, 1)
        XCTAssertEqual(fusion.first?.macros.calories, 250)
    }

    func testUneArchiveEnDoubleElleMemeEstDedoublonnee() {
        let fusion = MealJournalViewModel.fusion([], [repas("x"), repas("x")])
        XCTAssertEqual(fusion.map(\.id), ["x"])
    }
}
