import Foundation

// MARK: - Le journal corrige les apports (audit de personnalisation, étape 3, 22 sept. 2026)
//
// Le calcul des apports ne lisait que le questionnaire : quelqu'un qui note ses
// repas depuis deux semaines voyait le même score que le jour de son
// inscription. Ici, les repas notés des 14 derniers jours tirent chaque score
// vers ce qu'ils montrent, sans le remplacer : le journal ne voit que ce qui
// est noté, le questionnaire dit le reste.
//
// Garde-fous :
//   · seuls les jours REPRÉSENTATIFS comptent : au moins 60 % de la dépense
//     d'une journée de la personne notés (un jour à moitié noté dirait
//     « manque » à tort). Aujourd'hui n'en fait pas partie : la journée court ;
//   · un apport n'est corrigé qu'avec au moins 3 de ces jours où les repas
//     qui le renseignent pèsent la moitié des calories au moins ; les repas qui
//     ne le renseignent pas sont supposés à l'image des autres ;
//   · la couverture d'un jour se lit sur le besoin de la PERSONNE
//     (`BesoinsDeReference`), pas sur la référence générique des repas ;
//   · la correction tire le score de 30 % de l'écart, bornée à ±15 points, et
//     s'affiche comme une ligne nommée de la cascade (« noté dans ton journal »).

/// Ce que le journal a montré, apport par apport.
struct ObservationsJournal: Equatable {
    /// Jours représentatifs retenus dans la fenêtre.
    let joursRetenus: Int
    /// Par apport : part moyenne du besoin de la personne couverte (en %), sur
    /// les jours où l'apport est renseigné. Absent quand il n'y en a pas assez.
    let couverture: [String: Int]
}

enum JournalApports {

    static let fenetreJours = 14
    static let joursMinimum = 3
    /// Part de la dépense d'une journée qu'il faut avoir notée pour qu'un jour compte.
    static let partMinimaleDesCalories = 0.6
    /// Part des calories d'un jour que les repas renseignant un apport doivent porter.
    static let partMinimaleRenseignee = 0.5
    /// Le journal tire le score de cette part de l'écart…
    static let traction = 0.3
    /// … sans jamais le déplacer de plus de ces points.
    static let plafond = 15
    /// En dessous, la ligne ne dirait rien d'utile : elle n'est pas écrite.
    static let effetMinimum = 2
    static let libelle = "Tes repas notés ces 14 derniers jours"

    /// Les observations du journal, ou nil quand il n'en dit pas assez.
    static func observations(
        repas: [MealJournalService.MealRecord],
        profil: UserProfile,
        maintenant: Date = Date(),
        calendar: Calendar = .current
    ) -> ObservationsJournal? {
        let aujourdhui = calendar.startOfDay(for: maintenant)
        guard let debut = calendar.date(byAdding: .day, value: -fenetreJours, to: aujourdhui) else { return nil }
        let journee = Double(PhysicalMetrics(profile: profil).tdee ?? 2000)
        let seuil = journee * partMinimaleDesCalories

        let fenetre = repas.filter { $0.consumedAt >= debut && $0.consumedAt < aujourdhui }
        let parJour = Dictionary(grouping: fenetre) { calendar.startOfDay(for: $0.consumedAt) }

        var retenus = 0
        var parApport: [String: [Double]] = [:]
        for (_, duJour) in parJour {
            let kcal = Double(duJour.reduce(0) { $0 + max(0, $1.macros.calories) })
            guard kcal > 0, kcal >= seuil else { continue }
            retenus += 1
            for nutriment in NutrientID.allCases {
                let id = nutriment.rawValue
                let renseignes = duJour.filter { repas in repas.micros.contains { $0.id == id } }
                let kcalRenseignees = Double(renseignes.reduce(0) { $0 + max(0, $1.macros.calories) })
                guard kcalRenseignees > 0, kcalRenseignees >= kcal * partMinimaleRenseignee else { continue }
                let pourcent = Double(renseignes.flatMap(\.micros).filter { $0.id == id }.reduce(0) { $0 + max(0, $1.pctRDA) })
                let duJourEntier = pourcent * (kcal / kcalRenseignees)
                let pourLaPersonne = duJourEntier * BesoinsDeReference.facteur(nutriment, profil: profil)
                parApport[id, default: []].append(min(200, pourLaPersonne))
            }
        }

        var couverture: [String: Int] = [:]
        for (id, jours) in parApport where jours.count >= joursMinimum {
            couverture[id] = Int((jours.reduce(0, +) / Double(jours.count)).rounded())
        }
        guard retenus >= joursMinimum, !couverture.isEmpty else { return nil }
        return ObservationsJournal(joursRetenus: retenus, couverture: couverture)
    }

    /// La correction d'un apport, en points : une part de l'écart entre ce que
    /// montre le journal (plafonné au besoin couvert) et le score, bornée.
    static func correction(score: Int, couverture: Int) -> Int {
        let ecart = Double(min(100, max(0, couverture)) - score)
        let points = Int((ecart * traction).rounded())
        return max(-plafond, min(plafond, points))
    }

    /// Le registre, avec la ligne du journal sur chaque apport qu'il corrige.
    static func appliquer(
        _ registre: [String: DetailApport],
        observations: ObservationsJournal?
    ) -> [String: DetailApport] {
        guard let observations else { return registre }
        var sortie = registre
        for (id, detail) in registre {
            guard let couverture = observations.couverture[id] else { continue }
            let delta = correction(score: detail.score, couverture: couverture)
            guard abs(delta) >= effetMinimum else { continue }
            let contributions = detail.contributions + [ContributionApport(libelle: libelle, delta: delta, section: .journal)]
            let brut = DetailApport.pointDeDepart + contributions.reduce(0) { $0 + $1.delta }
            sortie[id] = DetailApport(contributions: contributions, score: max(0, min(100, brut)))
        }
        return sortie
    }

    /// Ce que le journal change, pour le hash du bilan : les écarts de score
    /// arrondis à 5 points. Le bilan se régénère quand le journal change
    /// vraiment un chiffre, pas à chaque repas noté. Vide sans effet.
    static func signature(avant: [String: DetailApport], apres: [String: DetailApport]) -> String {
        apres.keys.sorted().compactMap { id -> String? in
            guard let a = avant[id]?.score, let b = apres[id]?.score else { return nil }
            let palier = Int((Double(b - a) / 5).rounded()) * 5
            return palier == 0 ? nil : "\(id)\(palier > 0 ? "+" : "")\(palier)"
        }.joined(separator: ",")
    }
}
