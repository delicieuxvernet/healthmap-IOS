import Foundation

// MARK: - Gratification après un ajout (maquette du 20 septembre 2026)
//
// Après une saisie, l'app montre CE QUE LE GESTE A CHANGÉ plutôt qu'un simple
// « c'est enregistré » : les apports que ce repas a fait bouger aujourd'hui,
// d'où vient le gain, et la série de jours suivis.
//
// Tout se calcule ici, à partir du journal déjà chargé — aucune I/O, aucun
// réseau. S'il n'y a rien d'honnête à célébrer (un café, un repas sans détail
// d'apports), il n'y a pas de gratification du tout : la feuille ne sort
// jamais pour dire « bien joué » à vide.

struct GratificationRepas: Identifiable, Equatable {

    struct Gain: Identifiable, Equatable {
        let id: String
        let nom: String
        /// Part du besoin du jour couverte AVANT ce repas, puis APRÈS (0-100).
        let avant: Int
        let apres: Int
        /// « le poulet rôti, surtout » : l'aliment qui porte le gain, quand un
        /// seul le porte vraiment. `nil` = repas d'un seul aliment, ou gain partagé.
        let source: String?
    }

    /// L'identifiant du repas ajouté.
    let id: String
    let creneau: MealJournalService.MealSlot
    let gains: [Gain]
    /// Jours d'affilée avec au moins un repas suivi ; `nil` sous deux jours.
    let serie: Int?

    /// « Ce déjeuner fait bouger deux de tes apports. »
    var phrase: String {
        let repas: String
        switch creneau {
        case .breakfast: repas = "Ce petit-déjeuner"
        case .lunch: repas = "Ce déjeuner"
        case .dinner: repas = "Ce dîner"
        case .snack: repas = "Cet encas"
        }
        return gains.count > 1
            ? "\(repas) fait bouger \(Self.enLettres(gains.count)) de tes apports."
            : "\(repas) fait bouger un de tes apports."
    }

    /// « 13 jours d'affilée » ; la fenêtre chargée s'arrête à deux semaines, on
    /// ne prétend pas en savoir plus.
    var libelleSerie: String? {
        guard let serie else { return nil }
        return serie >= Self.fenetreSerie ? "Deux semaines d'affilée" : "\(serie) jours d'affilée"
    }

    // MARK: Règles

    /// En dessous, un apport n'a pas « bougé » : c'est du bruit.
    static let gainMinimum = 5
    /// Deux lignes : une feuille de deux secondes, pas un tableau.
    static let gainsAffiches = 2
    /// L'aliment est nommé s'il porte au moins cette part du gain du repas.
    static let partPourNommer = 0.5
    /// Jours couverts par `MealJournalViewModel.fortnight`.
    static let fenetreSerie = 14

    // MARK: Calcul

    /// - Parameters:
    ///   - nouveau: le repas qui vient d'être ajouté.
    ///   - repasDuJour: tous les repas du même jour, `nouveau` compris ou non.
    ///   - apportsARenforcer: ids des apports bas du bilan — ils passent devant.
    ///   - quinzaine: les repas des 14 derniers jours (pour la série).
    static func calculer(nouveau: MealJournalService.MealRecord,
                         repasDuJour: [MealJournalService.MealRecord],
                         apportsARenforcer: [String],
                         quinzaine: [MealJournalService.MealRecord],
                         maintenant: Date = Date(),
                         calendrier: Calendar = .current) -> GratificationRepas? {
        let autres = repasDuJour.filter { $0.id != nouveau.id }

        var gains: [Gain] = []
        for micro in nouveau.micros where micro.pctRDA > 0 {
            guard let definition = NutrientData.definition(for: micro.id) else { continue }
            let dejaCouvert = autres.flatMap(\.micros).filter { $0.id == micro.id }.reduce(0) { $0 + $1.pctRDA }
            let avant = min(100, dejaCouvert)
            let apres = min(100, dejaCouvert + micro.pctRDA)
            guard apres - avant >= gainMinimum else { continue }
            gains.append(Gain(id: micro.id, nom: definition.label, avant: avant, apres: apres,
                              source: source(de: micro.id, dans: nouveau)))
        }
        guard !gains.isEmpty else { return nil }

        // Les apports à renforcer d'abord (c'est pour eux qu'on suit ses repas),
        // puis le plus gros gain.
        let prioritaires = Set(apportsARenforcer)
        gains.sort { a, b in
            let pa = prioritaires.contains(a.id), pb = prioritaires.contains(b.id)
            if pa != pb { return pa }
            let ga = a.apres - a.avant, gb = b.apres - b.avant
            return ga == gb ? a.id < b.id : ga > gb
        }

        return GratificationRepas(
            id: nouveau.id,
            creneau: nouveau.slot,
            gains: Array(gains.prefix(gainsAffiches)),
            serie: serie(quinzaine: quinzaine + [nouveau], maintenant: maintenant, calendrier: calendrier)
        )
    }

    /// L'aliment qui porte le gain — nommé seulement s'il y en a plusieurs et
    /// qu'un seul fait le gros du travail.
    static func source(de apportId: String, dans repas: MealJournalService.MealRecord) -> String? {
        let parts: [(nom: String, pct: Int)] = repas.items.compactMap { item in
            guard !item.name.isEmpty,
                  let pct = item.micros?.first(where: { $0.id == apportId })?.pctRDA, pct > 0 else { return nil }
            return (item.name, pct)
        }
        guard repas.items.count > 1, let premier = parts.max(by: { $0.pct < $1.pct }) else { return nil }
        let total = parts.reduce(0) { $0 + $1.pct }
        guard total > 0, Double(premier.pct) / Double(total) >= partPourNommer else { return nil }
        return "\(premier.nom.lowercased()), surtout"
    }

    /// Jours d'affilée, aujourd'hui compris, avec au moins un repas.
    static func serie(quinzaine: [MealJournalService.MealRecord],
                      maintenant: Date = Date(),
                      calendrier: Calendar = .current) -> Int? {
        let jours = Set(quinzaine.map { calendrier.startOfDay(for: $0.consumedAt) })
        var compte = 0
        var jour = calendrier.startOfDay(for: maintenant)
        while jours.contains(jour), compte < fenetreSerie {
            compte += 1
            guard let veille = calendrier.date(byAdding: .day, value: -1, to: jour) else { break }
            jour = veille
        }
        return compte >= 2 ? compte : nil
    }

    private static func enLettres(_ n: Int) -> String {
        let mots = ["zéro", "un", "deux", "trois"]
        return n >= 0 && n < mots.count ? mots[n] : "\(n)"
    }
}

// MARK: - Le relais vers la racine

/// La feuille est présentée par la RACINE, pas par le Journal : il porte déjà
/// quatorze feuilles, et SwiftUI n'ouvre plus celles qu'on empile au-delà (bug
/// du 21 août). Le Journal dépose ici ce qu'il y a à célébrer, la racine le lit.
@MainActor
final class GratificationCentre: ObservableObject {
    static let partage = GratificationCentre()
    @Published var courante: GratificationRepas?
    private init() {}
}
