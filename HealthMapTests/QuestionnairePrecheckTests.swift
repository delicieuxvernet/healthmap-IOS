import XCTest
@testable import HealthMap

// Lot 2 (audit onboarding 2026-07-05) — garantit qu'aucune question à choix
// unique n'arrive pré-cochée : un champ à valeur par défaut (gender=homme,
// smoking=non, dietType=omnivore) ne doit PAS s'afficher comme sélectionné
// tant que l'utilisateur n'a pas fait un vrai choix.
@MainActor
final class QuestionnairePrecheckTests: XCTestCase {

    func testFreshProfileShowsNoSingleChoicePreselection() {
        let vm = QuestionnaireViewModel()
        // Profil neuf, aucun geste : rien n'est marqué « renseigné ».
        XCTAssertTrue(vm.interactedQuestionIds.isEmpty)
        // Même si le champ profil a une valeur par défaut, l'affichage ne montre
        // aucune sélection.
        XCTAssertNil(vm.displaySingleChoiceValue(for: "gender"))
        XCTAssertNil(vm.displaySingleChoiceValue(for: "smoking"))
        XCTAssertNil(vm.displaySingleChoiceValue(for: "dietType"))
    }

    func testAnsweringMarksInteractedAndRevealsSelection() {
        let vm = QuestionnaireViewModel()
        vm.updateAnswer(questionId: "gender", value: "femme")
        XCTAssertTrue(vm.interactedQuestionIds.contains("gender"))
        XCTAssertEqual(vm.displaySingleChoiceValue(for: "gender"), "femme")
        // Les autres questions non touchées restent sans sélection.
        XCTAssertNil(vm.displaySingleChoiceValue(for: "smoking"))
    }
}
