import SwiftUI

// MARK: - Pont Plan v2 (contrat AIAnalysisV2.plan → cartes existantes)
//
// Le Plan historique se dérive de `aiAnalysis` (MergedAnalysis, flux v7). Or le
// Bilan tourne désormais sur `analysisV2`, et les deux appels sont indépendants
// (cf. DashboardViewModel.triggerAnalysis) : si le v7 échoue/renvoie nil, le
// Plan restait bloqué sur « Aucune analyse » alors que le bilan v2, lui, est là.
//
// Ce pont rend le Plan résilient : quand `aiAnalysis` manque mais que
// `analysisV2.plan` est présent, on construit les mêmes `PlanTopic` à partir du
// contrat v2 et on réutilise `PlanTopicCardV4` + `PlanSolutionsSheetV4`. Les
// repères génériques (« au repas principal », etc.) sont EXACTEMENT ceux que le
// builder v7 pose déjà — aucune donnée inventée de plus que l'existant.

/// Construit les topics du Plan à partir du contrat v2 (`plan.sections`).
func planTopicsFromV2(_ analysis: AIAnalysisV2) -> [PlanTopic] {
    guard let sections = analysis.plan?.sections, !sections.isEmpty else { return [] }

    // id → nom de complément (pour nommer les solutions « par les compléments »).
    let complementNames: [String: String] = Dictionary(
        (analysis.complements?.complements ?? []).compactMap { c -> (String, String)? in
            guard let id = c.id, let nom = c.nom else { return nil }
            return (id, nom)
        },
        uniquingKeysWith: { first, _ in first }
    )

    return sections.compactMap { section -> PlanTopic? in
        guard let titre = section.titre, !titre.isEmpty else { return nil }
        let kind: PlanTopic.Kind = section.type == "objectif" ? .objectif : .symptome

        // Intro = explication (tipBold + tipRest), sinon les causes listées.
        let bold = section.tipBold?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rest = section.tipRest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let joined = [bold, rest].filter { !$0.isEmpty }.joined(separator: " ")
        let intro: String
        if !joined.isEmpty {
            intro = joined
        } else {
            let causes = (section.causes ?? []).compactMap { $0.label }.filter { !$0.isEmpty }
            intro = causes.isEmpty ? "Ton plan personnalisé pour ce point." : causes.joined(separator: ", ")
        }

        // Rituel matin / midi / soir.
        let ritual: [PlanRitualStep] = (section.rituel ?? []).compactMap { r in
            guard let moment = r.moment else { return nil }
            let slot: PlanRitualStep.Slot
            let title: String
            switch moment {
            case "matin": slot = .matin;   title = "Matin"
            case "midi":  slot = .journee; title = "Midi"
            case "soir":  slot = .soir;    title = "Soir"
            default:      slot = .journee; title = String(moment.prefix(1)).uppercased() + moment.dropFirst()
            }
            let detail = (r.actions ?? []).joined(separator: "\n")
            return PlanRitualStep(slot: slot, title: title, detail: detail)
        }

        // Solutions « par la nutrition » — repères génériques alignés sur le v7.
        let nutrition: [PlanNutritionSolution] = (section.solutions?.nutrition ?? []).map { n in
            let asset = n.icone.map { $0.hasPrefix("fluent_") ? $0 : "fluent_\($0)" } ?? "fluent_leaf"
            return PlanNutritionSolution(
                asset: asset,
                label: n.aliment ?? "Aliment",
                note: n.niveau2 ?? "Riche en nutriments",
                qty: "1 portion par jour",
                moment: "Au repas principal",
                cuisson: "Cuisson douce pour préserver les apports",
                astuce: n.niveau3 ?? "À associer à une source de vitamine C"
            )
        }

        // Solutions « par les habitudes ».
        let habitudes: [PlanHabitSolution] = (section.solutions?.habitudes ?? []).compactMap { h in
            let text = h.tipBold?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return PlanHabitSolution(symbol: "checkmark.circle.fill", text: text, note: h.tipRest ?? "")
        }

        // Solutions « par les compléments ».
        let complements: [PlanSupplementSolution] = (section.solutions?.complements ?? []).map { c in
            let name = c.complementId.flatMap { complementNames[$0] } ?? "Complément"
            return PlanSupplementSolution(name: name, note: c.phrase ?? "", tag: "Si besoin", strong: false)
        }

        return PlanTopic(
            id: section.id ?? titre,
            kind: kind,
            name: titre,
            intro: intro,
            ritual: ritual,
            nutrition: nutrition,
            habitudes: habitudes,
            complements: complements
        )
    }
}

// MARK: - Contenu du Plan à partir du contrat v2 (repli quand aiAnalysis manque)
/// Même mise en page que `RecommendationsContentView` (titre éditorial, une
/// carte par topic, pop-up solutions, sources), mais alimentée par le contrat
/// v2. Réutilise `PlanTopicCardV4` et `PlanSolutionsSheetV4`.
struct RecommendationsV2ContentView: View {
    let topics: [PlanTopic]
    @State private var activeTopic: PlanTopic?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ton plan")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Text("La cause, quoi faire, et quand — pour chaque symptôme")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 4)

                ForEach(topics) { topic in
                    PlanTopicCardV4(topic: topic) {
                        HapticService.shared.tap()
                        activeTopic = topic
                    }
                    .padding(.horizontal, 24)
                }

                SourcesSection()
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $activeTopic) { topic in
            PlanSolutionsSheetV4(topic: topic) {
                activeTopic = nil
                NotificationCenter.default.post(
                    name: .healthmapNavigateToTab,
                    object: "complements"
                )
            }
        }
    }
}
