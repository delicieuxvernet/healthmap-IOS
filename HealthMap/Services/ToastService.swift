import Foundation
import SwiftUI

// MARK: - Toast Service (nutrient facts, motivational messages)
@MainActor
final class ToastService: ObservableObject {
    static let shared = ToastService()

    @Published var currentToast: String?
    @Published var isShowing: Bool = false

    private var dismissTask: Task<Void, Never>?

    private init() {}

    // MARK: - Nutrient Facts (French)
    static let nutrientFacts: [String: [String]] = [
        "vitD": [
            "La vitamine D se stocke dans le foie pendant 2 mois",
            "15 minutes de soleil par jour suffisent pour produire de la vitamine D",
            "La vitamine D aide a fixer le calcium sur les os",
            "Pres de 80% des Francais sont en deficit de vitamine D",
            "Les poissons gras sont la meilleure source alimentaire de vitamine D",
            "La vitamine D joue un role cle dans le systeme immunitaire",
        ],
        "vitC": [
            "La vitamine C est detruite par la chaleur au-dela de 60 degres",
            "Le corps humain ne peut pas stocker la vitamine C",
            "Un kiwi contient plus de vitamine C qu'une orange",
            "La vitamine C ameliore l'absorption du fer vegetal",
            "Le poivron rouge est le legume le plus riche en vitamine C",
            "La vitamine C contribue a la production de collagene",
        ],
        "iron": [
            "Le fer heminique (viande) est 5 fois mieux absorbe que le fer vegetal",
            "Le the et le cafe reduisent l'absorption du fer de 60%",
            "Les lentilles sont la meilleure source de fer vegetal",
            "Le manque de fer est le plus repandu dans le monde",
            "Le fer transporte l'oxygene dans le sang via l'hemoglobine",
            "Associer fer vegetal et vitamine C double son absorption",
        ],
        "calcium": [
            "Le calcium represente 2% du poids corporel total",
            "Les eaux minerales riches en calcium sont une source souvent oubliee",
            "Le brocoli contient du calcium mieux absorbe que celui du lait",
            "99% du calcium se trouve dans les os et les dents",
            "La vitamine D est indispensable pour absorber le calcium",
            "Les amandes sont une excellente source de calcium vegetal",
        ],
        "omega3": [
            "Le cerveau est compose a 60% de graisses dont beaucoup d'omega-3",
            "2 portions de poisson gras par semaine couvrent les besoins en omega-3",
            "Les graines de lin sont la source vegetale la plus riche en omega-3",
            "Les omega-3 reduisent l'inflammation dans tout le corps",
            "Le rapport omega-6/omega-3 ideal est de 4:1",
            "Les omega-3 contribuent a la sante cardiovasculaire",
        ],
        "magnesium": [
            "Le stress augmente les besoins en magnesium de 20%",
            "Le chocolat noir 70% est une bonne source de magnesium",
            "Le magnesium participe a plus de 300 reactions enzymatiques",
            "Les crampes musculaires sont souvent un signe de deficit en magnesium",
            "Les bananes contiennent du magnesium et du potassium",
            "Le magnesium favorise un sommeil de meilleure qualite",
        ],
    ]

    // MARK: - Action Toasts (Motivational, French)
    static let actionToasts: [String] = [
        "Continue comme ca !",
        "Ton corps te remercie",
        "Chaque scan compte, bravo !",
        "Tu prends soin de toi, c'est l'essentiel",
        "Un petit geste, un grand impact sante",
        "Ta sante, c'est ton meilleur investissement",
        "Bien joue, tu es sur la bonne voie !",
        "La regularite, c'est la cle du succes",
    ]

    // MARK: - Show Nutrient Toast (deterministic by day-of-year)
    func showRandomNutrientToast(nutrientId: String) {
        guard !GamificationService.shared.isZenMode else { return }

        guard let facts = Self.nutrientFacts[nutrientId], !facts.isEmpty else { return }

        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let index = dayOfYear % facts.count
        show(facts[index])
    }

    // MARK: - Show Motivational Toast
    func showActionToast() {
        guard !GamificationService.shared.isZenMode else { return }

        let index = Int.random(in: 0..<Self.actionToasts.count)
        show(Self.actionToasts[index])
    }

    // MARK: - Display & Auto-Dismiss
    private func show(_ message: String) {
        currentToast = message
        isShowing = true

        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        isShowing = false
        currentToast = nil
    }
}
