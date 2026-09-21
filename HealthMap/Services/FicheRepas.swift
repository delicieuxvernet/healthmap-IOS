import Foundation

// MARK: - La fiche d'un repas (Journal, maquette du 20 septembre 2026)
//
// Toucher « Midi » n'ouvre pas la journée une seconde fois : ça ouvre CE repas.
// Ce que la personne a saisi, puis ce qu'il lui a apporté — macro par macro
// (avec sa part de la cible du jour), puis apport par apport.
//
// Pur, sans I/O : tout vient des repas déjà chargés par le Journal.

struct FicheRepas: Equatable {

    struct Macro: Identifiable, Equatable {
        let id: String
        let nom: String
        let grammes: Double
        /// Part de la cible du JOUR couverte par ce repas (0-100) ; `nil` quand
        /// la cible n'est pas connue — on ne montre alors que les grammes.
        let partDeLaCible: Int?
    }

    struct Apport: Identifiable, Equatable {
        let id: String
        let nom: String
        /// Part du besoin du jour apportée par ce repas, plafonnée à 100.
        let part: Int
    }

    let calories: Int
    /// « Poulet rôti, pâtes, yaourt » — les trois premiers, puis « et 2 autres ».
    let resume: String
    let macros: [Macro]
    let apports: [Apport]
    /// Ce que ce repas laisse de côté parmi les apports à renforcer. Nomme un
    /// constat, jamais un geste : ce texte est lisible en gratuit.
    let note: String?

    /// Nombre d'apports listés : au-delà, la fiche devient un tableau.
    static let apportsAffiches = 6
    /// Sous cette part, un apport à renforcer est « presque pas couvert ».
    static let seuilPresqueRien = 10

    static func calculer(repas: [MealJournalService.MealRecord],
                         cibleProteines: Int?, cibleGlucides: Int?, cibleLipides: Int?,
                         apportsARenforcer: [String]) -> FicheRepas {
        let calories = repas.reduce(0) { $0 + $1.macros.calories }
        let proteines = repas.reduce(0.0) { $0 + $1.macros.proteins }
        let glucides = repas.reduce(0.0) { $0 + $1.macros.carbs }
        let lipides = repas.reduce(0.0) { $0 + $1.macros.fats }
        let fibres = repas.reduce(0.0) { $0 + $1.macros.fiber }
        let cibleFibres = NutrientData.definition(for: "fiber").map { Int($0.rda) }

        let macros = [
            Macro(id: "proteines", nom: "Protéines", grammes: proteines, partDeLaCible: part(proteines, cibleProteines)),
            Macro(id: "glucides", nom: "Glucides", grammes: glucides, partDeLaCible: part(glucides, cibleGlucides)),
            Macro(id: "lipides", nom: "Lipides", grammes: lipides, partDeLaCible: part(lipides, cibleLipides)),
            Macro(id: "fibres", nom: "Fibres", grammes: fibres, partDeLaCible: part(fibres, cibleFibres)),
        ]

        // Apport par apport : la somme de ce que chaque saisie du repas apporte.
        var parApport: [String: Int] = [:]
        for micro in repas.flatMap(\.micros) {
            parApport[micro.id, default: 0] += micro.pctRDA
        }
        var apports: [Apport] = []
        for (id, somme) in parApport where somme > 0 {
            guard let definition = NutrientData.definition(for: id) else { continue }
            apports.append(Apport(id: id, nom: definition.label, part: min(100, somme)))
        }
        apports.sort { a, b in
            if a.part != b.part { return a.part > b.part }
            return a.id < b.id
        }

        return FicheRepas(
            calories: calories,
            resume: resume(repas.flatMap(\.foods)),
            macros: macros,
            apports: Array(apports.prefix(apportsAffiches)),
            note: note(parApport: parApport, apportsARenforcer: apportsARenforcer, aDesApports: !apports.isEmpty)
        )
    }

    static func part(_ grammes: Double, _ cible: Int?) -> Int? {
        guard let cible, cible > 0 else { return nil }
        return min(100, Int((grammes / Double(cible) * 100).rounded()))
    }

    static func resume(_ aliments: [String]) -> String {
        let noms = aliments.filter { !$0.isEmpty }
        guard !noms.isEmpty else { return "" }
        let premiers = noms.prefix(3).joined(separator: ", ")
        let reste = noms.count - 3
        guard reste > 0 else { return premiers }
        return "\(premiers) et \(reste) autre\(reste > 1 ? "s" : "")"
    }

    /// Le premier apport à renforcer que ce repas ne couvre presque pas. Rien à
    /// dire si le repas n'a pas de détail d'apports (on ne conclut pas du vide).
    static func note(parApport: [String: Int], apportsARenforcer: [String], aDesApports: Bool) -> String? {
        guard aDesApports else { return nil }
        for id in apportsARenforcer where (parApport[id] ?? 0) < seuilPresqueRien {
            guard let definition = NutrientData.definition(for: id) else { continue }
            // Deux-points plutôt que « de » : pas d'élision à gérer (« d'iode »).
            let nom = definition.label.prefix(1).lowercased() + definition.label.dropFirst()
            return "Ce repas couvre très peu un de tes apports à renforcer : \(nom)."
        }
        return nil
    }
}
