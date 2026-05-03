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

    /// Fresh ViewModel should start at section index 0.
    func testInitialState_isFirstSection() {
        XCTAssertEqual(vm.currentSectionIndex, 0, "Should start at section 0")
        XCTAssertTrue(vm.isFirstSection, "Should report isFirstSection = true")
    }

    // MARK: - Navigation

    /// nextSection should increment the section index by 1.
    func testNextSection_incrementsIndex() {
        vm.nextSection()
        XCTAssertEqual(vm.currentSectionIndex, 1, "Should advance to section 1")
    }

    /// nextSection at the last section should NOT overflow beyond the array bounds.
    func testNextSection_atLastSection_doesNotOverflow() {
        // Navigate to the last section
        for _ in 0..<(vm.totalSections - 1) {
            vm.nextSection()
        }
        XCTAssertTrue(vm.isLastSection, "Should be at last section")

        let lastIndex = vm.currentSectionIndex
        vm.nextSection()
        XCTAssertEqual(vm.currentSectionIndex, lastIndex, "Should not overflow past last section")
    }

    /// previousSection should decrement the section index by 1.
    func testPreviousSection_decrementsIndex() {
        vm.nextSection() // go to 1
        vm.previousSection()
        XCTAssertEqual(vm.currentSectionIndex, 0, "Should go back to section 0")
    }

    /// previousSection at section 0 should NOT underflow below 0.
    func testPreviousSection_atFirstSection_doesNotUnderflow() {
        vm.previousSection()
        XCTAssertEqual(vm.currentSectionIndex, 0, "Should not underflow below 0")
    }

    // MARK: - Progress

    /// Progress should be calculated as (currentSectionIndex + 1) / totalSections.
    func testProgress_calculatedCorrectly() {
        let total = Double(vm.totalSections)
        XCTAssertEqual(vm.progress, 1.0 / total, accuracy: 0.001, "Initial progress should be 1/total")

        vm.nextSection()
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

    // MARK: - visibleQuestions: Complet Pathway

    /// Complet pathway should show all questions (no express filter).
    func testVisibleQuestions_completPathway_showsAll() {
        vm.pathway = .complet
        vm.profile.pathway = .complet

        let allQuestions = vm.currentSection.questions
        let visibleQuestions = vm.visibleQuestions

        // Complet should show at least as many questions as express
        // (it shows ALL questions minus any showIf-filtered ones)
        let allWithoutShowIf = allQuestions.filter { $0.showIf == nil }
        XCTAssertGreaterThanOrEqual(
            visibleQuestions.count, allWithoutShowIf.count,
            "Complet pathway should show all non-conditional questions"
        )
    }

    // MARK: - visibleQuestions: showIf Conditions

    /// Questions with showIf conditions should be filtered by the condition.
    func testVisibleQuestions_showIfCondition_filters() {
        vm.pathway = .complet
        vm.profile.pathway = .complet

        // Navigate to the Medical section (section index 5)
        // which has periodFlow and pregnancyStatus with showIf: gender == .femme
        while vm.currentSection != .medical && !vm.isLastSection {
            vm.nextSection()
        }

        // As homme, gender-specific questions should be hidden
        vm.profile.gender = .homme
        let hommeQuestions = vm.visibleQuestions
        let hommeIDs = Set(hommeQuestions.map(\.id))
        XCTAssertFalse(hommeIDs.contains("periodFlow"), "periodFlow should be hidden for homme")
        XCTAssertFalse(hommeIDs.contains("pregnancyStatus"), "pregnancyStatus should be hidden for homme")

        // As femme, they should appear
        vm.profile.gender = .femme
        let femmeQuestions = vm.visibleQuestions
        let femmeIDs = Set(femmeQuestions.map(\.id))
        XCTAssertTrue(femmeIDs.contains("periodFlow"), "periodFlow should be visible for femme")
        XCTAssertTrue(femmeIDs.contains("pregnancyStatus"), "pregnancyStatus should be visible for femme")
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
}
