import Foundation
import Supabase

// MARK: - Ce que les repas notés apportent, micro par micro (1er octobre 2026)
//
// Un repas enregistré garde, pour chaque aliment, son identifiant (`ciqual:…`
// ou `off:…`) et ses grammes. La composition de l'aliment pour 100 g vient de
// la base (`micros_detail_100g`) : on la multiplie par la portion, à la
// LECTURE. Trois conséquences voulues :
//   · les repas déjà photographiés comptent tout de suite, sans rien réécrire ;
//   · changer une quantité se résume à changer des grammes ;
//   · un apport NON RENSEIGNÉ dans Ciqual reste absent : on ne confond jamais
//     « on ne sait pas » et « il n'y en a pas ».
//
// Les repas anciens, sans identifiant d'aliment, gardent ce qu'ils avaient
// enregistré à l'époque : les dix apports du bilan, en part du besoin générique.

/// Composition d'un aliment pour 100 g, telle que la base la renvoie.
struct CompositionAliment: Codable, Equatable {
    /// Produit à code-barres rattaché à un aliment Ciqual équivalent.
    let estime: Bool
    /// Identifiant du micro → quantité pour 100 g, dans l'unité du catalogue.
    let apports: [String: Double]
}

typealias Compositions = [String: CompositionAliment]

extension MealJournalService.FoodEntry {

    /// « ciqual:26038 » ou « off:3017620422003 » : l'aliment tel que la base le
    /// connaît. Les repas photographiés portent `ciqual_code`, les aliments
    /// ajoutés depuis la recherche ou la dictée portent `food_id`. nil pour une
    /// saisie libre et pour les lignes d'avant octobre 2026.
    var foodId: String? {
        guard let raw else { return nil }
        if let valeur = raw["food_id"], case .string(let texte) = valeur, !texte.isEmpty {
            return texte
        }
        guard let code = raw["ciqual_code"] else { return nil }
        switch code {
        case .integer(let entier):
            return entier > 0 ? "ciqual:\(entier)" : nil
        case .double(let decimal):
            return decimal > 0 ? "ciqual:\(Int(decimal))" : nil
        default:
            return nil
        }
    }
}

/// Une part de repas dont on sait ce qu'elle apporte : un aliment quand le
/// repas a son détail, le repas entier sinon.
struct Bouchee: Equatable {
    /// Nom de l'aliment ; nil quand la part est un repas entier sans détail.
    let nom: String?
    let kcal: Double
    /// Quantités apportées. Un micro absent = cette part ne le renseigne pas.
    let quantites: [String: Double]
}

/// Tout ce qui a été noté sur une journée.
struct JourneeMesuree: Equatable {
    let jour: Date
    let kcal: Double
    /// Somme brute de ce qui a été noté, sans rien supposer du reste.
    let quantites: [String: Double]
    /// Calories des parts qui renseignent chaque micro.
    let kcalRenseignees: [String: Double]
    let bouchees: [Bouchee]
}

enum MesuresRepas {

    /// Part de la dépense qu'il faut avoir notée pour qu'un jour compte : la
    /// même règle que `JournalApports`.
    static let partMinimaleDesCalories = JournalApports.partMinimaleDesCalories
    /// Part des calories du jour que les aliments renseignant un micro doivent porter.
    static let partMinimaleRenseignee = JournalApports.partMinimaleRenseignee
    /// Une couverture au-delà ne dit plus rien d'utile.
    static let plafondCouverture = 200.0

    // MARK: Un repas

    /// Les aliments du repas dont la composition est connue.
    private static func composition(
        de item: MealJournalService.FoodEntry,
        dans compositions: Compositions
    ) -> (grammes: Double, composition: CompositionAliment)? {
        guard let identifiant = item.foodId,
              let grammes = item.portionG, grammes > 0,
              let composition = compositions[identifiant],
              !composition.apports.isEmpty else { return nil }
        return (grammes, composition)
    }

    /// Ce qu'un repas ancien avait enregistré : les apports du bilan, hors
    /// fibres (elles ont leur ligne dans les macros).
    private static func quantitesHeritees(_ micros: [MealJournalService.MicroPct]) -> [String: Double] {
        var sortie: [String: Double] = [:]
        for micro in micros {
            guard Micronutriments.parId[micro.id] != nil,
                  let reference = MealJournalService.canonRDA[micro.id] else { continue }
            let quantite = micro.amount ?? (Double(micro.pctRDA) / 100 * reference)
            sortie[micro.id, default: 0] += max(0, quantite)
        }
        return sortie
    }

    static func bouchees(
        repas: MealJournalService.MealRecord,
        compositions: Compositions
    ) -> [Bouchee] {
        guard repas.hasItemDetail else {
            return [Bouchee(nom: nil,
                            kcal: Double(max(0, repas.macros.calories)),
                            quantites: quantitesHeritees(repas.micros))]
        }
        return repas.items.map { item -> Bouchee in
            let kcal = Double(max(0, item.macros?.calories ?? 0))
            if let connu = composition(de: item, dans: compositions) {
                let facteur = connu.grammes / 100
                var quantites: [String: Double] = [:]
                for (id, pour100g) in connu.composition.apports where Micronutriments.parId[id] != nil {
                    quantites[id] = max(0, pour100g) * facteur
                }
                return Bouchee(nom: item.name, kcal: kcal, quantites: quantites)
            }
            return Bouchee(nom: item.name, kcal: kcal, quantites: quantitesHeritees(item.micros ?? []))
        }
    }

    // MARK: Une journée

    static func journees(
        repas: [MealJournalService.MealRecord],
        compositions: Compositions,
        calendar: Calendar = .current
    ) -> [Date: JourneeMesuree] {
        let parJour = Dictionary(grouping: repas) { calendar.startOfDay(for: $0.consumedAt) }
        var sortie: [Date: JourneeMesuree] = [:]
        for (jour, duJour) in parJour {
            var parts: [Bouchee] = []
            for unRepas in duJour {
                parts.append(contentsOf: bouchees(repas: unRepas, compositions: compositions))
            }
            var kcal = 0.0
            var quantites: [String: Double] = [:]
            var renseignees: [String: Double] = [:]
            for part in parts {
                kcal += part.kcal
                for (id, quantite) in part.quantites {
                    quantites[id, default: 0] += quantite
                    renseignees[id, default: 0] += part.kcal
                }
            }
            sortie[jour] = JourneeMesuree(jour: jour, kcal: kcal, quantites: quantites,
                                          kcalRenseignees: renseignees, bouchees: parts)
        }
        return sortie
    }

    /// Part du besoin couverte ce jour-là, en pourcentage. nil quand la journée
    /// n'est pas assez notée pour le dire, ou quand trop peu d'aliments
    /// renseignent ce micro. Les aliments qui ne le renseignent pas sont
    /// supposés à l'image des autres.
    static func couverture(
        _ id: String,
        journee: JourneeMesuree,
        besoin: Double,
        depense: Double
    ) -> Double? {
        guard besoin > 0, journee.kcal > 0,
              journee.kcal >= depense * partMinimaleDesCalories else { return nil }
        let renseignees = journee.kcalRenseignees[id] ?? 0
        guard renseignees > 0, renseignees >= journee.kcal * partMinimaleRenseignee else { return nil }
        let quantite = (journee.quantites[id] ?? 0) * (journee.kcal / renseignees)
        return min(plafondCouverture, quantite / besoin * 100)
    }

    // MARK: Les repas, relus avec la composition exacte

    /// Les mêmes repas, dont les dix apports du bilan sont recalculés depuis la
    /// composition exacte quand TOUS les aliments du repas sont connus de la
    /// base. C'est ce que `JournalApports` lit pour corriger les scores : le
    /// chiffre du bilan et le détail du Journal partent ainsi des mêmes mesures.
    /// Un repas dont un aliment manque reste tel qu'il a été enregistré.
    static func repasPrecises(
        _ repas: [MealJournalService.MealRecord],
        compositions: Compositions
    ) -> [MealJournalService.MealRecord] {
        guard !compositions.isEmpty else { return repas }
        return repas.map { unRepas -> MealJournalService.MealRecord in
            guard unRepas.hasItemDetail else { return unRepas }
            var connus: [(kcal: Double, grammes: Double, composition: CompositionAliment)] = []
            for item in unRepas.items {
                guard let connu = composition(de: item, dans: compositions) else { return unRepas }
                connus.append((Double(max(0, item.macros?.calories ?? 0)), connu.grammes, connu.composition))
            }
            let kcalRepas = connus.reduce(0.0) { $0 + $1.kcal }
            var micros: [MealJournalService.MicroPct] = []
            for apport in NutrientID.allCases {
                let id = apport.rawValue
                guard let reference = MealJournalService.canonRDA[id], reference > 0 else { continue }
                var quantite = 0.0
                var kcalRenseignees = 0.0
                var renseignes = 0
                for connu in connus {
                    guard let pour100g = connu.composition.apports[id] else { continue }
                    quantite += max(0, pour100g) * connu.grammes / 100
                    kcalRenseignees += connu.kcal
                    renseignes += 1
                }
                guard renseignes > 0 else { continue }
                if kcalRepas > 0 {
                    guard kcalRenseignees >= kcalRepas * partMinimaleRenseignee, kcalRenseignees > 0 else { continue }
                    quantite *= kcalRepas / kcalRenseignees
                } else if renseignes < connus.count {
                    continue
                }
                let pourcent = Int((quantite / reference * 100).rounded())
                micros.append(MealJournalService.MicroPct(
                    id: id,
                    pctRDA: max(0, min(400, pourcent)),
                    amount: (quantite * 100).rounded() / 100,
                    unit: ""
                ))
            }
            return MealJournalService.MealRecord(
                id: unRepas.id, consumedAt: unRepas.consumedAt, slot: unRepas.slot,
                items: unRepas.items, macros: unRepas.macros, micros: micros
            )
        }
    }

    // MARK: Les aliments à demander à la base

    /// Identifiants d'aliments portés par ces repas, sans doublon.
    static func identifiants(_ repas: [MealJournalService.MealRecord]) -> Set<String> {
        var sortie: Set<String> = []
        for unRepas in repas {
            for item in unRepas.items {
                if let identifiant = item.foodId { sortie.insert(identifiant) }
            }
        }
        return sortie
    }
}
