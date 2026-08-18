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
            "La vitamine D aide à fixer le calcium sur les os",
            "Près de 80 % des Français manquent de vitamine D",
            "Les poissons gras sont la meilleure source alimentaire de vitamine D",
            "La vitamine D joue un rôle clé dans le système immunitaire",
        ],
        "vitC": [
            "La vitamine C est détruite par la chaleur au-delà de 60 degrés",
            "Le corps humain ne peut pas stocker la vitamine C",
            "Un kiwi contient plus de vitamine C qu'une orange",
            "La vitamine C améliore l'absorption du fer végétal",
            "Le poivron rouge est le légume le plus riche en vitamine C",
            "La vitamine C contribue à la production de collagène",
        ],
        "iron": [
            "Le fer héminique (viande) est 5 fois mieux absorbé que le fer végétal",
            "Le thé et le café réduisent l'absorption du fer de 60 %",
            "Les lentilles sont la meilleure source de fer végétal",
            "Le manque de fer est le plus répandu dans le monde",
            "Le fer transporte l'oxygène dans le sang via l'hémoglobine",
            "Associer fer végétal et vitamine C double son absorption",
        ],
        "calcium": [
            "Le calcium représente 2 % du poids corporel total",
            "Les eaux minérales riches en calcium sont une source souvent oubliée",
            "Le brocoli contient du calcium mieux absorbé que celui du lait",
            "99 % du calcium se trouve dans les os et les dents",
            "La vitamine D est indispensable pour absorber le calcium",
            "Les amandes sont une excellente source de calcium végétal",
        ],
        "omega3": [
            "Le cerveau est composé à 60 % de graisses, dont beaucoup d'oméga-3",
            "2 portions de poisson gras par semaine couvrent les besoins en oméga-3",
            "Les graines de lin sont la source végétale la plus riche en oméga-3",
            "Les oméga-3 réduisent l'inflammation dans tout le corps",
            "Le rapport oméga-6 / oméga-3 idéal est de 4:1",
            "Les oméga-3 contribuent à la santé cardiovasculaire",
        ],
        "magnesium": [
            "Le stress augmente les besoins en magnésium de 20 %",
            "Le chocolat noir 70 % est une bonne source de magnésium",
            "Le magnésium participe à plus de 300 réactions enzymatiques",
            "Les crampes musculaires sont souvent un signe de manque de magnésium",
            "Les bananes contiennent du magnésium et du potassium",
            "Le magnésium favorise un sommeil de meilleure qualité",
        ],
    ]

    // MARK: - Action Toasts (Motivational, French)
    static let actionToasts: [String] = [
        "Continue comme ça !",
        "Ton corps te remercie",
        "Chaque scan compte, bravo !",
        "Tu prends soin de toi, c'est l'essentiel",
        "Un petit geste, un grand impact santé",
        "Ta santé, c'est ton meilleur investissement",
        "Bien joué, tu es sur la bonne voie !",
        "La régularité, c'est la clé du succès",
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
