import XCTest
@testable import HealthMap

// MARK: - Questionnaire ViewModel Tests
// Validates navigation, answer binding, pathway filtering, and draft persistence.
// All tests are @MainActor because QuestionnaireViewModel is @MainActor.

@MainActor
final class QuestionnaireViewModelTests: XCTestCase {

    private var vm: QuestionnaireViewModel!

    override func setUp() {
        super.setUp()
        // Clear any stale draft from previous test runs
        UserDefaults.standard.removeObject(forKey: "healthmap_questionnaire_draft")
        vm = QuestionnaireViewModel()
    }

    override func tearDown() {
        // Clean up the draft key used by the ViewModel
        UserDefaults.standard.removeObject(forKey: "healthmap_questionnaire_draft")
        vm = nil
        super.tearDown()
    }

    // MARK: - Initial State

    /// Fresh ViewModel should start at question index 0.
    func testInitialState_isFirstQuestion() {
        XCTAssertEqual(vm.currentQuestionIndex, 0, "Should start at question 0")
        XCTAssertTrue(vm.isFirstQuestion, "Should report isFirstQuestion = true")
        XCTAssertEqual(vm.currentQuestion?.id, vm.visibleQuestions.first?.id, "Current question should be the first visible one")
    }

    // MARK: - Navigation (une question par écran)

    /// nextQuestion should increment the flat question index by 1.
    func testNextQuestion_incrementsIndex() {
        vm.nextQuestion()
        XCTAssertEqual(vm.currentQuestionIndex, 1, "Should advance to question 1")
    }

    /// nextQuestion at the last question should NOT overflow beyond the array bounds.
    func testNextQuestion_atLastQuestion_doesNotOverflow() {
        // Navigate to the last question
        for _ in 0..<(vm.totalQuestions - 1) {
            vm.nextQuestion()
        }
        XCTAssertTrue(vm.isLastQuestion, "Should be at last question")

        let lastIndex = vm.currentQuestionIndex
        vm.nextQuestion()
        XCTAssertEqual(vm.currentQuestionIndex, lastIndex, "Should not overflow past last question")
    }

    /// previousQuestion should decrement the flat question index by 1.
    func testPreviousQuestion_decrementsIndex() {
        vm.nextQuestion() // go to 1
        vm.previousQuestion()
        XCTAssertEqual(vm.currentQuestionIndex, 0, "Should go back to question 0")
    }

    /// previousQuestion at question 0 should NOT underflow below 0.
    func testPreviousQuestion_atFirstQuestion_doesNotUnderflow() {
        vm.previousQuestion()
        XCTAssertEqual(vm.currentQuestionIndex, 0, "Should not underflow below 0")
    }

    /// Crossing a section boundary should return the newly entered section
    /// (used by the view to display the section intro screen). Parcours
    /// adaptatif : avec tous les blocs profonds déverrouillés, marcher le flux
    /// entre dans chaque section une fois, dans l'ordre.
    func testNextQuestion_sectionBoundary_returnsEnteredSection() {
        unlockAllDeepSections()

        var enteredSections: [QuestionnaireSection] = []
        while !vm.isLastQuestion {
            if let entered = vm.nextQuestion() {
                enteredSections.append(entered)
            }
        }

        XCTAssertEqual(
            enteredSections,
            [.modeDeVie, .sante, .nutrition, .symptomes, .medical],
            "Walking the fully-unlocked flow should enter each section once, in order"
        )
    }

    // MARK: - Progress

    /// Progress should be calculated as (currentQuestionIndex + 1) / totalQuestions.
    func testProgress_calculatedCorrectly() {
        let total = Double(vm.totalQuestions)
        XCTAssertEqual(vm.progress, 1.0 / total, accuracy: 0.001, "Initial progress should be 1/total")

        vm.nextQuestion()
        XCTAssertEqual(vm.progress, 2.0 / total, accuracy: 0.001, "After next, progress should be 2/total")
    }

    // MARK: - updateAnswer: String Fields

    /// Setting dietType through updateAnswer should update the profile field.
    func testUpdateAnswer_stringField_setsProfileValue() {
        vm.updateAnswer(questionId: "dietType", value: "vegan")
        XCTAssertEqual(vm.profile.dietType, "vegan", "dietType should be updated to vegan")
    }

    // MARK: - updateAnswer: Array Fields

    /// Setting symptoms (array field) through updateAnswer should update the profile field.
    func testUpdateAnswer_arrayField_setsProfileValue() {
        let symptoms = ["fatigue", "hair_loss"]
        vm.updateAnswer(questionId: "symptoms", value: symptoms)
        XCTAssertEqual(vm.profile.symptoms, symptoms, "symptoms array should be updated")
    }

    // MARK: - updateAnswer: Unknown Key

    /// An unknown key should NOT crash — just log a warning.
    func testUpdateAnswer_unknownKey_doesNotCrash() {
        // Should not throw or crash
        vm.updateAnswer(questionId: "nonExistentField", value: "test")
        // If we reach here, the test passes (no crash)
    }

    // MARK: - updateAnswer: Smoking

    /// Smoking "yes" should convert to SmokingValue.yes (which is .bool(true)).
    func testUpdateAnswer_smokingField_convertsCorrectly() {
        vm.updateAnswer(questionId: "smoking", value: "yes")
        XCTAssertTrue(vm.profile.smoking.isSmoker, "smoking = 'yes' should make isSmoker true")

        vm.updateAnswer(questionId: "smoking", value: "no")
        XCTAssertFalse(vm.profile.smoking.isSmoker, "smoking = 'no' should make isSmoker false")
    }

    // MARK: - updateAnswer: Gender

    /// Gender string should be parsed to the Gender enum.
    func testUpdateAnswer_genderField_parsesEnum() {
        vm.updateAnswer(questionId: "gender", value: "femme")
        XCTAssertEqual(vm.profile.gender, .femme, "gender should be parsed to .femme")

        vm.updateAnswer(questionId: "gender", value: "homme")
        XCTAssertEqual(vm.profile.gender, .homme, "gender should be parsed to .homme")
    }

    // MARK: - visibleQuestions: Express Pathway

    /// Express pathway should filter out non-express questions.
    func testVisibleQuestions_expressPathway_filtersCorrectly() {
        vm.pathway = .express
        vm.profile.pathway = .express

        // The express keys are a known subset (21 keys)
        let visibleIDs = Set(vm.visibleQuestions.map(\.id))

        // All visible questions should be in the express keys set
        for id in visibleIDs {
            XCTAssertTrue(
                QuestionnaireSection.expressKeys.contains(id),
                "Express pathway should only show express keys, found: \(id)"
            )
        }
    }

    // MARK: - visibleQuestions: tous les blocs déverrouillés

    /// Déverrouiller les 3 carrefours révèle leurs questions profondes, MAIS
    /// les questions non-express de Profil/Mode de vie/Santé restent masquées :
    /// elles n'ont aucun carrefour (arbitrage assumé du parcours adaptatif —
    /// seuls alimentation/symptômes/médical sont approfondissables).
    func testVisibleQuestions_allDeepUnlocked_revealsDeepBlocksOnly() {
        unlockAllDeepSections()
        let visibleIDs = Set(vm.visibleQuestions.map(\.id))

        // Les blocs déverrouillés exposent leurs questions profondes.
        for id in ["mealsPerDay", "breadType", "supplementsCurrent", "symptoms", "medications", "digestiveConditions"] {
            XCTAssertTrue(visibleIDs.contains(id), "\(id) doit être visible (bloc profond déverrouillé)")
        }

        // Les questions non-express de Profil/Mode de vie/Santé n'ont pas de
        // carrefour → jamais atteignables, même tous blocs déverrouillés.
        for id in ["weightTrend", "skinType", "screenBeforeBed", "alcohol", "bloating", "antibiotics"] {
            XCTAssertFalse(visibleIDs.contains(id), "\(id) ne doit pas être visible (pas de carrefour)")
        }
    }

    // MARK: - visibleQuestions: showIf Conditions

    /// Questions with showIf conditions should be filtered by the condition.
    /// The flattened list recomputes on every access, so changing an answer
    /// reveals/hides the dependent questions immediately.
    func testVisibleQuestions_showIfCondition_filters() {
        // Le bloc médical doit être déverrouillé pour que periodFlow /
        // pregnancyStatus (showIf femme) entrent dans le périmètre visible.
        unlockAllDeepSections()

        // As homme, gender-specific questions should be hidden
        vm.profile.gender = .homme
        let hommeIDs = Set(vm.visibleQuestions.map(\.id))
        XCTAssertFalse(hommeIDs.contains("periodFlow"), "periodFlow should be hidden for homme")
        XCTAssertFalse(hommeIDs.contains("pregnancyStatus"), "pregnancyStatus should be hidden for homme")

        // As femme, they should appear (and the total adjusts accordingly)
        vm.profile.gender = .femme
        let femmeIDs = Set(vm.visibleQuestions.map(\.id))
        XCTAssertTrue(femmeIDs.contains("periodFlow"), "periodFlow should be visible for femme")
        XCTAssertTrue(femmeIDs.contains("pregnancyStatus"), "pregnancyStatus should be visible for femme")
        XCTAssertEqual(femmeIDs.count, hommeIDs.count + 2, "Femme flow should add exactly 2 questions")
    }

    // MARK: - section(of:) helper

    /// Every visible question should be attributed to the section it belongs to.
    func testSectionOfQuestion_mapsToOwningSection() {
        vm.pathway = .complet
        vm.profile.pathway = .complet

        for question in vm.visibleQuestions {
            let section = vm.section(of: question)
            XCTAssertTrue(
                section.questions.contains(where: { $0.id == question.id }),
                "section(of:) should return the section containing \(question.id)"
            )
        }
    }

    // MARK: - firstUnansweredQuestionIndex

    /// Draft restore lands on the first unanswered question. Fields with a
    /// non-empty default (gender, smoking, dietType...) count as answered —
    /// matching the existing display behavior (option preselected on screen).
    func testFirstUnansweredQuestionIndex_skipsAnsweredQuestions() {
        // Fresh profile → goals (multi-choice, empty) is the first unanswered
        XCTAssertEqual(vm.firstUnansweredQuestionIndex(), 0, "Fresh profile should resume at the first question")

        // Answer goals + firstName → next unanswered is age (flat index 2)
        vm.updateAnswer(questionId: "goals", value: ["energie"])
        vm.updateAnswer(questionId: "firstName", value: "Lea")
        XCTAssertEqual(vm.firstUnansweredQuestionIndex(), 2, "Should resume at the first unanswered question (age)")
    }

    // MARK: - clearDraft

    /// clearDraft should remove the draft from UserDefaults.
    func testClearDraft_removesFromUserDefaults() {
        // Write some draft data first
        vm.updateAnswer(questionId: "firstName", value: "TestUser")

        // Verify something is stored
        let beforeClear = UserDefaults.standard.data(forKey: "healthmap_questionnaire_draft")
        // Draft saving depends on Supabase session for userId — may or may not be saved.
        // Regardless, clearDraft should remove whatever is there.

        QuestionnaireViewModel.clearDraft()

        let afterClear = UserDefaults.standard.data(forKey: "healthmap_questionnaire_draft")
        XCTAssertNil(afterClear, "Draft should be nil after clearDraft()")
    }

    // MARK: - Parcours adaptatif (carrefours)

    /// Sans aucun bloc déverrouillé, seules les questions express sont visibles
    /// — c'est le tronc commun du parcours adaptatif (remplace l'express).
    func testVisibleQuestions_noUnlock_showsExpressOnly() {
        XCTAssertTrue(vm.unlockedDeepSections.isEmpty, "Fresh VM has no unlocked deep block")
        for question in vm.visibleQuestions {
            XCTAssertTrue(
                QuestionnaireSection.expressKeys.contains(question.id),
                "Tronc commun should be express-only, found: \(question.id)"
            )
        }
    }

    /// Le premier carrefour proposé est l'alimentation, puis les symptômes,
    /// puis le médical ; une fois les trois déverrouillés, plus de carrefour.
    func testNextLockedGate_progressesNutritionSymptomesMedical() {
        XCTAssertEqual(vm.nextLockedGate, .nutrition, "Premier carrefour = alimentation")

        vm.unlockDeep(.nutrition)
        XCTAssertEqual(vm.nextLockedGate, .symptomes, "Puis symptômes")

        vm.unlockDeep(.symptomes)
        XCTAssertEqual(vm.nextLockedGate, .medical, "Puis médical")

        vm.unlockDeep(.medical)
        XCTAssertNil(vm.nextLockedGate, "Plus de carrefour une fois tout déverrouillé")
    }

    /// Déverrouiller un bloc le rend visible ET repositionne le flux sur sa
    /// première question PROFONDE (non express).
    func testUnlockDeep_revealsAndRepositions() throws {
        let beforeCount = vm.visibleQuestions.count
        vm.unlockDeep(.nutrition)

        XCTAssertTrue(vm.unlockedDeepSections.contains(.nutrition), "Le bloc nutrition est déverrouillé")
        XCTAssertGreaterThan(vm.visibleQuestions.count, beforeCount, "Le bloc révèle de nouvelles questions")

        let current = try XCTUnwrap(vm.currentQuestion)
        XCTAssertEqual(vm.section(of: current), .nutrition, "Repositionné dans le bloc nutrition")
        XCTAssertFalse(
            QuestionnaireSection.expressKeys.contains(current.id),
            "Repositionné sur une question profonde (non express)"
        )
    }

    // MARK: - Helpers

    /// Déverrouille tous les blocs profonds — équivalent adaptatif de l'ancien
    /// parcours « complet » (qui révélait toutes les questions non-express).
    private func unlockAllDeepSections() {
        vm.unlockedDeepSections = [.nutrition, .symptomes, .medical]
    }
}
