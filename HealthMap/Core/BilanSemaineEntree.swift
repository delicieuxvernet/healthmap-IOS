import Foundation

// MARK: - Ce que l'app envoie à `weekly-review` (contrat v1)
//
// Des FAITS calculés sur le téléphone, rien d'autre :
// - les repas des 7 derniers jours (aliments, quantités, moment) et leurs
//   totaux par jour ;
// - les apports tels que l'app les affiche (UN chiffre par apport : celui du
//   registre, avec son statut), les journées basses de la semaine, les
//   aliments qui les ont portés ;
// - les macros contre l'objectif du Journal, sur les seules journées assez
//   notées (60 % de la dépense, la règle de `JournalApports`) ;
// - pour les apports « à suivre », des aliments candidats chiffrés depuis
//   Ciqual et filtrés par le régime et les allergies (`GardeFousAliments`).
// Le serveur relit lui-même le profil (régime, allergies, objectifs). Ni
// prénom, ni e-mail, ni eau, ni ressentis.

struct BilanSemaineEntree: Encodable, Equatable {
    struct Periode: Encodable, Equatable { let debut: String; let fin: String }

    struct Objectifs: Encodable, Equatable {
        let kcal: Int?
        let proteines_g: Int?
        let glucides_g: Int?
        let lipides_g: Int?
        let fibres_g: Int?
    }

    struct Aliment: Encodable, Equatable {
        let nom: String
        let moment: String
        let quantite: String
    }

    struct Jour: Encodable, Equatable {
        let date: String
        let repas: Int
        let kcal: Int?
        let proteines_g: Int?
        let glucides_g: Int?
        let lipides_g: Int?
        let fibres_g: Int?
        let aliments: [Aliment]
    }

    struct Source: Encodable, Equatable { let nom: String; let part: Int }

    struct Apport: Encodable, Equatable {
        let id: String
        let nom: String
        /// LE chiffre de l'apport dans l'app (registre), 0-100.
        let moyennePct: Int
        let joursBas: Int
        let joursMesures: Int
        /// `a_renforcer`, `a_surveiller`, `a_affiner`, `couvert` ou vide.
        let statut: String
        let sources: [Source]
    }

    struct Macro: Encodable, Equatable {
        let id: String
        let nom: String
        let moyennePct: Int
        let joursAtteints: Int
        let joursMesures: Int
    }

    struct Frequence: Encodable, Equatable { let nom: String; let fois: Int }
    struct Candidat: Encodable, Equatable { let nom: String; let portion: String; let gainPct: Int }
    struct Suggestion: Encodable, Equatable { let apport: String; let aliments: [Candidat] }
    struct Poids: Encodable, Equatable { let debut: Double?; let fin: Double?; let objectif: Double? }

    var version = 1
    let periode: Periode
    let repasNotes: Int
    let joursNotes: Int
    let objectifs: Objectifs
    let jours: [Jour]
    let apports: [Apport]
    let macros: [Macro]
    let frequences: [Frequence]
    let suggestions: [Suggestion]
    let poids: Poids?
}

enum BilanSemaineBuilder {

    /// Une macro « atteinte » un jour où elle passe 85 % de son objectif.
    static let seuilMacroAtteinte = 0.85
    /// Candidats par apport « à suivre », et apports pour lesquels on en cherche.
    static let candidatsParApport = 3
    static let apportsAvecCandidats = 3

    // MARK: Les repas de la fenêtre

    /// Les repas des 7 derniers jours, aujourd'hui compris, jamais un repas
    /// daté dans le futur (préparé d'avance).
    static func repasDeLaSemaine(_ repas: [MealJournalService.MealRecord],
                                 maintenant: Date = Date(),
                                 calendrier: Calendar = .current) -> [MealJournalService.MealRecord] {
        let aujourdhui = calendrier.startOfDay(for: maintenant)
        guard let debut = calendrier.date(byAdding: .day, value: -(BilanSemaineRegle.joursRelus - 1), to: aujourdhui) else { return [] }
        return repas.filter { $0.consumedAt >= debut && $0.consumedAt <= maintenant }
    }

    /// Un repas = un créneau d'un jour (la recherche écrit une ligne par
    /// aliment : quatre aliments au déjeuner font UN repas).
    static func repasDistincts(_ repas: [MealJournalService.MealRecord], calendrier: Calendar = .current) -> Int {
        Set(repas.map { "\(calendrier.startOfDay(for: $0.consumedAt).timeIntervalSince1970)-\($0.slot.rawValue)" }).count
    }

    static func joursNotes(_ repas: [MealJournalService.MealRecord], calendrier: Calendar = .current) -> Int {
        Set(repas.map { calendrier.startOfDay(for: $0.consumedAt) }).count
    }

    // MARK: L'entrée

    static func construire(
        repas tousLesRepas: [MealJournalService.MealRecord],
        tableau: TableauMicros,
        metrics: PhysicalMetrics,
        profil: UserProfile,
        compositions: Compositions,
        profilAlimentaire: ProfilAlimentaire,
        maintenant: Date = Date(),
        calendrier: Calendar = .current
    ) -> BilanSemaineEntree? {
        let repas = repasDeLaSemaine(tousLesRepas, maintenant: maintenant, calendrier: calendrier)
        let nombre = repasDistincts(repas, calendrier: calendrier)
        let jours = joursNotes(repas, calendrier: calendrier)
        guard nombre >= BilanSemaineRegle.repasMinimum, jours >= BilanSemaineRegle.joursMinimum else { return nil }

        let aujourdhui = calendrier.startOfDay(for: maintenant)
        let fenetre = (0..<BilanSemaineRegle.joursRelus).reversed().compactMap {
            calendrier.date(byAdding: .day, value: -$0, to: aujourdhui)
        }
        guard let premier = fenetre.first else { return nil }

        let objectifs = BilanSemaineEntree.Objectifs(
            kcal: metrics.macros?.calories,
            proteines_g: metrics.macros?.protein,
            glucides_g: metrics.macros?.carbs,
            lipides_g: metrics.macros?.fat,
            fibres_g: Int(NutrientData.definition(for: "fiber")?.rda ?? 30)
        )

        let joursEntree = fenetre.map { jour -> BilanSemaineEntree.Jour in
            let duJour = repas.filter { calendrier.isDate($0.consumedAt, inSameDayAs: jour) }
            let totaux = totaux(duJour)
            return BilanSemaineEntree.Jour(
                date: BilanSemaineRegle.texte(jour),
                repas: repasDistincts(duJour, calendrier: calendrier),
                kcal: duJour.isEmpty ? nil : totaux.calories,
                proteines_g: duJour.isEmpty ? nil : Int(totaux.proteins.rounded()),
                glucides_g: duJour.isEmpty ? nil : Int(totaux.carbs.rounded()),
                lipides_g: duJour.isEmpty ? nil : Int(totaux.fats.rounded()),
                fibres_g: duJour.isEmpty ? nil : Int(totaux.fiber.rounded()),
                aliments: Array(duJour.flatMap(aliments).prefix(40))
            )
        }

        let lignes = tableau.toutes.filter { $0.sens == .besoin && $0.niveau != nil }
        let apports = lignes.map { ligne in
            BilanSemaineEntree.Apport(
                id: ligne.id,
                nom: ligne.nom,
                moyennePct: ligne.niveau ?? 0,
                joursBas: ligne.semaine.filter { ($0.couverture ?? 100) < MicrosDuJour.seuilBas }.count,
                joursMesures: ligne.semaine.filter { $0.couverture != nil }.count,
                statut: ligne.statutApport?.codeServeur ?? "",
                sources: ligne.contributeurs.prefix(3).map { .init(nom: $0.nom, part: $0.part) }
            )
        }

        return BilanSemaineEntree(
            periode: .init(debut: BilanSemaineRegle.texte(premier), fin: BilanSemaineRegle.texte(aujourdhui)),
            repasNotes: nombre,
            joursNotes: jours,
            objectifs: objectifs,
            jours: joursEntree,
            apports: apports,
            macros: macros(jours: joursEntree, objectifs: objectifs, depense: metrics.tdee),
            frequences: frequences(repas),
            suggestions: suggestions(apports: apports, compositions: compositions, profil: profilAlimentaire),
            poids: poids(profil)
        )
    }

    // MARK: Les morceaux

    static func totaux(_ repas: [MealJournalService.MealRecord]) -> MealJournalService.MealMacros {
        repas.reduce(into: MealJournalService.MealMacros()) { somme, r in
            somme.calories += r.macros.calories
            somme.proteins += r.macros.proteins
            somme.carbs += r.macros.carbs
            somme.fats += r.macros.fats
            somme.fiber += r.macros.fiber
        }
    }

    private static func moment(_ slot: MealJournalService.MealSlot) -> String {
        switch slot {
        case .breakfast: return "petit-déjeuner"
        case .lunch: return "déjeuner"
        case .dinner: return "dîner"
        case .snack: return "collation"
        }
    }

    private static func aliments(_ repas: MealJournalService.MealRecord) -> [BilanSemaineEntree.Aliment] {
        repas.items.compactMap { item in
            let nom = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nom.isEmpty else { return nil }
            let quantite = item.portionG.map { "\(Int($0.rounded())) g" } ?? ""
            return .init(nom: nom, moment: moment(repas.slot), quantite: quantite)
        }
    }

    /// Protéines, glucides et lipides contre l'objectif du Journal, sur les
    /// journées assez notées seulement : un jour à moitié noté n'est pas un
    /// jour « sous l'objectif ». Les fibres se lisent comme un apport (une
    /// seule lecture).
    static func macros(jours: [BilanSemaineEntree.Jour],
                       objectifs: BilanSemaineEntree.Objectifs,
                       depense: Int?) -> [BilanSemaineEntree.Macro] {
        let plancher = Double(depense ?? objectifs.kcal ?? 0) * JournalApports.partMinimaleDesCalories
        let comptes = jours.filter { j in
            guard let kcal = j.kcal else { return false }
            return plancher > 0 && Double(kcal) >= plancher
        }
        guard !comptes.isEmpty else { return [] }
        let lectures: [(id: String, nom: String, objectif: Int?, valeur: (BilanSemaineEntree.Jour) -> Int?)] = [
            ("proteines", "Protéines", objectifs.proteines_g, { $0.proteines_g }),
            ("glucides", "Glucides", objectifs.glucides_g, { $0.glucides_g }),
            ("lipides", "Lipides", objectifs.lipides_g, { $0.lipides_g }),
        ]
        return lectures.compactMap { lecture in
            guard let objectif = lecture.objectif, objectif > 0 else { return nil }
            let parts = comptes.compactMap(lecture.valeur).map { Double($0) / Double(objectif) }
            guard !parts.isEmpty else { return nil }
            let moyenne = parts.reduce(0, +) / Double(parts.count)
            return .init(id: lecture.id, nom: lecture.nom,
                         moyennePct: Int((moyenne * 100).rounded()),
                         joursAtteints: parts.filter { $0 >= seuilMacroAtteinte }.count,
                         joursMesures: parts.count)
        }
    }

    /// Les aliments qui reviennent le plus (une fois par repas), douze au plus.
    static func frequences(_ repas: [MealJournalService.MealRecord]) -> [BilanSemaineEntree.Frequence] {
        var comptes: [String: (nom: String, fois: Int)] = [:]
        var ordre: [String] = []
        for r in repas {
            var dejaCompte: Set<String> = []
            for item in r.items {
                let nom = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let cle = AlimentsDeReference.cle(nom)
                guard !cle.isEmpty, dejaCompte.insert(cle).inserted else { continue }
                if comptes[cle] == nil { ordre.append(cle) }
                comptes[cle, default: (nom: nom, fois: 0)].fois += 1
            }
        }
        return ordre.compactMap { comptes[$0] }
            .filter { $0.fois >= 2 }
            .sorted { $0.fois > $1.fois }
            .prefix(12)
            .map { .init(nom: $0.nom, fois: $0.fois) }
    }

    /// Pour les apports « à suivre » (statut de l'app), les aliments de la
    /// table qui en apportent le plus par portion, filtrés par le régime et
    /// les allergies, jamais le kiwi (illustration = ancien logo).
    static func suggestions(apports: [BilanSemaineEntree.Apport],
                            compositions: Compositions,
                            profil: ProfilAlimentaire) -> [BilanSemaineEntree.Suggestion] {
        let aSuivre = apports
            .filter { ["a_renforcer", "a_surveiller"].contains($0.statut) && $0.moyennePct < 100 }
            .sorted { $0.moyennePct < $1.moyennePct }
            .prefix(apportsAvecCandidats)
        return aSuivre.compactMap { apport in
            let candidats = AlimentsDeReference.tous
                .filter { AlimentsDeReference.cle($0.nom) != "kiwi" && GardeFousAliments.compatible($0.nom, profil: profil) }
                .compactMap { aliment -> BilanSemaineEntree.Candidat? in
                    guard let gain = AlimentsDeReference.apport(aliment, nutriment: apport.id, compositions: compositions),
                          gain >= AlimentsDeReference.apportMinimum else { return nil }
                    return .init(nom: aliment.nom, portion: aliment.portion, gainPct: gain)
                }
                .sorted { $0.gainPct > $1.gainPct }
                .prefix(candidatsParApport)
            return candidats.isEmpty ? nil : .init(apport: apport.id, aliments: Array(candidats))
        }
    }

    /// Le poids actuel et le poids souhaité, tels que réglés dans le Journal
    /// (aucun historique : pas de « tu as perdu tant cette semaine »).
    private static func poids(_ profil: UserProfile) -> BilanSemaineEntree.Poids? {
        let actuel = Double(profil.weight.replacingOccurrences(of: ",", with: "."))
        let souhaite = profil.targetWeightDouble
        guard actuel != nil || souhaite != nil else { return nil }
        return .init(debut: nil, fin: actuel, objectif: souhaite)
    }
}
