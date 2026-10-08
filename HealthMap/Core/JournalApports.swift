import Foundation

// MARK: - Le journal corrige les apports (audit de personnalisation, étape 3, 22 sept. 2026)
//
// Le calcul des apports ne lisait que le questionnaire : quelqu'un qui note ses
// repas depuis deux semaines voyait le même score que le jour de son
// inscription. Ici, les repas notés des 14 derniers jours tirent chaque score
// vers ce qu'ils montrent.
//
// 1er octobre 2026, demande d'Arthur : « fais que le chiffre réagisse plus vite
// aux repas ». La première version attendait trois journées finies, ne comptait
// jamais la journée en cours, et ne déplaçait le score que de 30 % de l'écart,
// 15 points au plus : on notait un repas et rien ne bougeait. Désormais :
//   · une seule journée assez notée suffit, et la journée EN COURS compte dès
//     qu'elle l'est ;
//   · le poids du journal GRANDIT avec le nombre de journées notées : le
//     questionnaire pèse comme quatre journées, donc une journée tire le score
//     de 20 % de l'écart, trois de 43 %, sept de 64 %, quatorze de 78 % ;
//   · la correction reste bornée, à ±30 points.
// Le chiffre part donc du questionnaire et rejoint peu à peu ce que la personne
// mange vraiment.
//
// Garde-fous, inchangés :
//   · seuls les jours REPRÉSENTATIFS comptent : au moins 60 % de la dépense
//     d'une journée de la personne notés (un jour à moitié noté dirait
//     « manque » à tort) ;
//   · un apport n'est lu, un jour donné, que si les repas qui le renseignent
//     pèsent la moitié des calories au moins ; les repas qui ne le renseignent
//     pas sont supposés à l'image des autres ;
//   · la couverture d'un jour se lit sur le besoin de la PERSONNE
//     (`BesoinsDeReference`), pas sur la référence générique des repas ;
//   · la correction s'affiche comme une ligne nommée de la cascade (« noté
//     dans ton journal »).

/// Ce que le journal a montré, apport par apport.
struct ObservationsJournal: Equatable {
    /// Jours représentatifs retenus dans la fenêtre.
    let joursRetenus: Int
    /// Par apport : part moyenne du besoin de la personne couverte (en %), sur
    /// les jours où l'apport est renseigné. Absent quand il n'y en a pas assez.
    let couverture: [String: Int]
    /// Par apport : nombre de journées qui le renseignent. C'est lui qui donne
    /// son poids au journal. Absent : on retient `joursRetenus`.
    let jours: [String: Int]

    init(joursRetenus: Int, couverture: [String: Int], jours: [String: Int] = [:]) {
        self.joursRetenus = joursRetenus
        self.couverture = couverture
        self.jours = jours
    }

    /// Journées qui renseignent cet apport.
    func joursPour(_ id: String) -> Int {
        jours[id] ?? joursRetenus
    }
}

enum JournalApports {

    static let fenetreJours = 14
    /// Une journée assez notée suffit à faire bouger un chiffre.
    static let joursMinimum = 1
    /// Part de la dépense d'une journée qu'il faut avoir notée pour qu'un jour compte.
    static let partMinimaleDesCalories = 0.6
    /// Part des calories d'un jour que les repas renseignant un apport doivent porter.
    static let partMinimaleRenseignee = 0.5
    /// Le questionnaire pèse comme ce nombre de journées notées.
    static let joursDuQuestionnaire = 4.0
    /// Le journal ne déplace jamais un score de plus de ces points.
    static let plafond = 30
    /// En dessous, la ligne ne dirait rien d'utile : elle n'est pas écrite.
    static let effetMinimum = 2
    /// Le bilan rédigé se refait quand le journal déplace un score d'un palier.
    static let palierDuBilan = 10
    static let libelle = "Tes repas notés ces 14 derniers jours"

    /// La part de l'écart que le journal rattrape : elle grandit avec le nombre
    /// de journées notées, sans jamais atteindre 1.
    static func traction(jours: Int) -> Double {
        let notes = Double(max(0, jours))
        return notes / (notes + joursDuQuestionnaire)
    }

    /// Les observations du journal, ou nil quand il n'en dit pas assez.
    /// La fenêtre : les 14 derniers jours, aujourd'hui compris.
    static func observations(
        repas: [MealJournalService.MealRecord],
        profil: UserProfile,
        maintenant: Date = Date(),
        calendar: Calendar = .current
    ) -> ObservationsJournal? {
        let aujourdhui = calendar.startOfDay(for: maintenant)
        guard let debut = calendar.date(byAdding: .day, value: -(fenetreJours - 1), to: aujourdhui),
              let demain = calendar.date(byAdding: .day, value: 1, to: aujourdhui) else { return nil }
        let journee = Double(PhysicalMetrics(profile: profil).tdee ?? 2000)
        let seuil = journee * partMinimaleDesCalories

        let fenetre = repas.filter { $0.consumedAt >= debut && $0.consumedAt < demain }
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
        var jours: [String: Int] = [:]
        for (id, mesures) in parApport where mesures.count >= joursMinimum {
            couverture[id] = Int((mesures.reduce(0, +) / Double(mesures.count)).rounded())
            jours[id] = mesures.count
        }
        guard retenus >= joursMinimum, !couverture.isEmpty else { return nil }
        return ObservationsJournal(joursRetenus: retenus, couverture: couverture, jours: jours)
    }

    /// La correction d'un apport, en points : la part de l'écart entre ce que
    /// montre le journal (plafonné au besoin couvert) et le score que ce nombre
    /// de journées permet de rattraper, bornée.
    static func correction(score: Int, couverture: Int, jours: Int) -> Int {
        let ecart = Double(min(100, max(0, couverture)) - score)
        let points = Int((ecart * traction(jours: jours)).rounded())
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
            let delta = correction(score: detail.score, couverture: couverture, jours: observations.joursPour(id))
            guard abs(delta) >= effetMinimum else { continue }
            sortie[id] = detail.ajoutant(ContributionApport(libelle: libelle, delta: delta, section: .journal))
        }
        return sortie
    }

    /// Ce que le journal change, pour le hash du bilan : les écarts de score
    /// arrondis au palier. Le bilan rédigé se régénère quand le journal change
    /// vraiment un chiffre, pas à chaque repas noté : le palier est large
    /// (10 points) parce que le chiffre, lui, bouge désormais chaque jour.
    /// Vide sans effet.
    static func signature(avant: [String: DetailApport], apres: [String: DetailApport]) -> String {
        apres.keys.sorted().compactMap { id -> String? in
            guard let a = avant[id]?.score, let b = apres[id]?.score else { return nil }
            let palier = Int((Double(b - a) / Double(palierDuBilan)).rounded()) * palierDuBilan
            return palier == 0 ? nil : "\(id)\(palier > 0 ? "+" : "")\(palier)"
        }.joined(separator: ",")
    }
}
