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
// contrat v2 et on rend la MÊME carte radiale (`PlanRadialScreen`). Les repères
// génériques (« au repas principal », etc.) sont EXACTEMENT ceux que le builder
// v7 pose déjà — aucune donnée inventée de plus que l'existant.
//
// Une nuance assumée : le contrat v2 ne porte pas le score des apports ni le
// délai d'effet. `evidence` reste donc vide et la cause s'écrit sans chiffre —
// plutôt que d'en inventer un.

/// Construit les topics du Plan à partir du contrat v2 (`plan.sections`).
///
/// Le serveur émet UNE section par symptôme et par objectif déclarés, sans
/// plafond — or la couronne radiale est dessinée pour 3 à 6 nœuds. On retient
/// donc 3 symptômes puis 3 objectifs, exactement la sélection que le builder
/// v7 opère déjà : même nombre, même ordre, quel que soit le flux qui répond.
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

    let topics = sections.compactMap { section -> PlanTopic? in
        guard let titre = section.titre, !titre.isEmpty else { return nil }
        let kind: PlanTopic.Kind = section.type == "objectif" ? .objectif : .symptome

        // Intro = explication (tipBold + tipRest), sinon les causes listées.
        // tipBold/tipRest du contrat sont des GESTES (« Décale ton café… ») :
        // quand ils font l'intro, `introTeasing` porte la version gratuite
        // (les causes — le problème — ou un libellé neutre), jamais le geste.
        let bold = section.tipBold?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rest = section.tipRest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let joined = [bold, rest].filter { !$0.isEmpty }.joined(separator: " ")
        let causes = (section.causes ?? []).compactMap { $0.label }.filter { !$0.isEmpty }
        let causesIntro = causes.isEmpty ? "Ton plan personnalisé pour ce point." : causes.joined(separator: ", ")
        let intro: String
        let introTeasing: String?
        if !joined.isEmpty {
            intro = joined
            introTeasing = causesIntro
        } else {
            intro = causesIntro
            introTeasing = nil
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
            introTeasing: introTeasing,
            ritual: ritual,
            nutrition: nutrition,
            habitudes: habitudes,
            complements: complements
        )
    }

    // La sélection du v7 : les symptômes d'abord (le motif de venue), puis les
    // objectifs, 3 par famille.
    let symptomes = topics.filter { $0.kind == .symptome }.prefix(3)
    let objectifs = topics.filter { $0.kind == .objectif }.prefix(3)
    return Array(symptomes) + Array(objectifs)
}

// MARK: - Contenu du Plan à partir du contrat v2 (repli quand aiAnalysis manque)
/// Exactement la même carte radiale que le flux v7, alimentée par le contrat v2.
/// Pas de focus de la semaine ici : il se calcule sur les repas scannés, que ce
/// repli ne charge pas.
struct RecommendationsV2ContentView: View {
    let topics: [PlanTopic]

    /// Le VM du Dashboard porte les scores LOCAUX des nutriments — la vue
    /// « Apports » reste donc disponible même quand le flux v7 manque.
    @EnvironmentObject var dashboardVM: DashboardViewModel
    /// Même clé que le flux v7 (RecommendationsContentView) : un seul choix
    /// mémorisé, quel que soit le flux qui alimente l'écran.
    @AppStorage("planVueChoisie") private var planVueRaw: String = PlanVue.objectifs.rawValue

    private var planVue: Binding<PlanVue> {
        Binding(
            get: { PlanVue(rawValue: planVueRaw) ?? .objectifs },
            set: { planVueRaw = $0.rawValue }
        )
    }

    var body: some View {
        PlanRadialScreen(
            topics: planVue.wrappedValue == .apports ? planTopicsFromApports(dashboardVM.nutrients) : topics,
            focus: nil,
            vue: planVue
        )
    }
}
