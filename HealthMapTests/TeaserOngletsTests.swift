import XCTest
import SwiftUI
@testable import HealthMap

// MARK: - Teaser in-situ des onglets (V12c)
//
// Invariant testé PAR onglet, hors UI : sans bilan (`!bilanComplete`), AUCUN
// appel IA ne part et la porte bilan a de quoi s'afficher — libellé canonique
// du CTA présent (sans tiret cadratin, décision typo du 1er août 2026) et
// données d'exemple issues des catalogues canoniques, jamais inventées.

@MainActor
final class TeaserOngletsTests: XCTestCase {

    /// VM « sans bilan » : profil vide, questionnaire non complété, tous les
    /// services mockés — aucun réseau, aucun Supabase.
    private func makeVMSansBilan(aiAnalysis: MockTeaserAIAnalysisService) -> DashboardViewModel {
        let vm = DashboardViewModel(
            auth: MockAuthService(),
            database: MockDatabaseService(),
            subscription: MockTeaserSubscriptionService(),
            analytics: MockAnalyticsService(),
            aiAnalysis: aiAnalysis,
            gamification: GamificationService.shared
        )
        vm.profile = .empty
        vm.hasCompletedQuestionnaire = false
        return vm
    }

    // MARK: - Onglet Plan

    /// Plan sans bilan : la couronne d'exemple est prête (invariant 3-6 nœuds,
    /// ids uniques, libellés canoniques), le CTA de la porte existe, et le seul
    /// déclencheur IA de l'onglet (`triggerAnalysis`, cf. le .task de
    /// RecommendationsView) ne part pas.
    func testPlan_sansBilan_couronneExempleEtCTASansAppelIA() async {
        let ai = MockTeaserAIAnalysisService()
        let vm = makeVMSansBilan(aiAnalysis: ai)
        XCTAssertFalse(vm.bilanComplete)

        let topics = planTopicsDecouverte()
        XCTAssertTrue((3...6).contains(topics.count), "Invariant couronne : 3 à 6 nœuds")
        XCTAssertEqual(Set(topics.map(\.id)).count, topics.count, "Ids uniques (ForEach)")

        // Apports : libellé + emoji du catalogue canonique, jamais inventés.
        let nutrientLabels = Set(NutrientData.all.map(\.label))
        let apports = topics.filter { $0.kind == .apport }
        XCTAssertFalse(apports.isEmpty)
        for topic in apports {
            XCTAssertTrue(nutrientLabels.contains(topic.name),
                          "\(topic.name) doit venir du catalogue NutrientData")
            XCTAssertNotNil(topic.emojiBadge, "Emoji canonique attendu sur un nœud apport")
        }

        // Symptôme / objectif : les libellés EXACTS des options du questionnaire.
        XCTAssertTrue(topics.contains { $0.kind == .symptome })
        XCTAssertTrue(topics.contains { $0.kind == .objectif })
        for topic in topics where topic.kind != .apport {
            let questionId = topic.kind == .symptome ? "symptoms" : "goals"
            let options = QuestionnaireSection.question(id: questionId)?.options?.map(\.label) ?? []
            XCTAssertTrue(options.contains(topic.name),
                          "\(topic.name) doit venir des options du questionnaire (\(questionId))")
        }

        // En découverte, la pop-up de solutions ne s'ouvre jamais : rien à montrer.
        for topic in topics {
            XCTAssertEqual(topic.solutionsCount, 0, "Aucune solution embarquée en découverte")
        }

        // La porte : CTA présent, sans tiret cadratin.
        XCTAssertFalse(BilanDoorButton.Libelle.plan.isEmpty)
        XCTAssertFalse(BilanDoorButton.Libelle.plan.contains("\u{2014}"))

        // Aucun appel IA sans bilan.
        await vm.triggerAnalysis()
        XCTAssertEqual(ai.fullAnalysisCallCount, 0, "generate-analysis (v7) ne doit pas partir")
        XCTAssertEqual(ai.bilanV2CallCount, 0, "generate-analysis (bilan v2) ne doit pas partir")
    }
}

// MARK: - Mocks minimaux (privés à ce fichier)

@MainActor
private final class MockTeaserSubscriptionService: SubscriptionServiceProtocol {
    var isPremium: Bool = false
    func checkPremiumStatus() async {}
    func loadOfferings() async {}
    func restorePurchases() async throws {}
    func identify(userId: String) async {}
}

/// Compte les appels IA — l'invariant « !bilanComplete → aucun appel » s'assert dessus.
private final class MockTeaserAIAnalysisService: AIAnalysisServiceProtocol {
    private(set) var fullAnalysisCallCount = 0
    private(set) var bilanV2CallCount = 0

    func fetchFullAnalysis(userId: String, profile: UserProfile) async throws -> MergedAnalysis? {
        fullAnalysisCallCount += 1
        return nil
    }

    func fetchBilanV2(userId: String, profileHash: String, scores: [String: Int], healthScore: Int, redFlags: [RedFlag], forceRefresh: Bool) async throws -> AIAnalysisV2 {
        bilanV2CallCount += 1
        return AIAnalysisV2(contract: "v2")
    }
}
