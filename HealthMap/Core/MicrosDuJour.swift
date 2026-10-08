import Foundation

// MARK: - Les micronutriments du Journal : un seul chiffre par apport (1er octobre 2026)
//
// Retour d'Arthur : Progrès affichait « 55 → 11 % » pour la vitamine D, et la
// fiche ouvrait sur « 58 ». Trois mesures différentes posées côte à côte.
//
// La règle, désormais : UN chiffre par apport, la part du besoin couverte.
//   · il PART du questionnaire (le score du registre, `NutrientLedger`) ;
//   · il BOUGE avec les repas notés (`JournalApports`), puis avec une prise de
//     sang ;
//   · c'est le même dans le Journal, dans Progrès et dans la fiche.
// Les micros sans question dans le questionnaire n'ont pas de point de départ :
// leur chiffre vient des seuls repas notés, et reste vide tant qu'aucune
// journée n'est assez remplie.
//
// Chaque ligne explique son chiffre par des FAITS de la personne : ce qu'elle a
// répondu, ce que ses repas ont apporté, ce qu'elle a signalé. Jamais une
// phrase générale servie à tout le monde.

/// Ce que le calcul lit de la personne. Comparable : sert de clé de cache.
struct ContexteMicros: Equatable {
    /// Besoin quotidien par micro (`BesoinsMicros`).
    let besoins: [String: Double]
    /// Dépense quotidienne, en kcal : dit si une journée est assez notée.
    let depense: Double
    /// Scores du registre par apport du bilan (questionnaire, repas, prise de sang).
    let scores: [String: Int]
    /// Ce que les repas notés ont montré aux apports du bilan, en part du besoin.
    let couvertureJournal: [String: Int]
    /// Nombre de journées notées qui renseignent chaque apport du bilan.
    let joursJournal: [String: Int]
    /// Symptômes déclarés au questionnaire.
    let symptomes: [String]
    /// Les apports estimés en vraies quantités (`EstimateurApports`, audit de
    /// fiabilité du 8 oct. 2026) : quand un micro y est, son chiffre est la
    /// part de la référence couverte et son statut celui de l'estimateur.
    var estimations: [String: EstimationApport] = [:]
    /// Le statut retenu par l'app (une prise de sang récente prime).
    var statuts: [String: StatutApport] = [:]
    /// Les réponses lues par l'estimateur, pour nommer les sources.
    var profil: ProfilEstimation? = nil
}

struct FaitMicro: Equatable, Identifiable {
    enum Genre: Equatable {
        case questionnaire, repas, priseDeSang, symptome, saison, jour
    }
    let genre: Genre
    let texte: String
    var id: String { texte }
}

/// Une journée de la semaine affichée. `couverture` nil = pas assez noté.
struct JourMicro: Equatable, Identifiable {
    let jour: Date
    let couverture: Int?
    var id: Date { jour }
}

enum StatutMicro: Equatable {
    case normal
    /// Sous le seuil sur la journée affichée, quand elle est assez notée.
    case basCeJour
    /// Sous le seuil au moins trois jours sur les sept derniers.
    case basProlonge(jours: Int)
    /// Au-dessus de la limite au moins trois jours sur les sept derniers.
    case auDessusDeLaLimite(jours: Int)

    var estUneAlerte: Bool {
        switch self {
        case .basProlonge, .auDessusDeLaLimite: return true
        case .normal, .basCeJour: return false
        }
    }
}

/// Un aliment des sept derniers jours et la part de l'apport qu'il a portée.
struct ContributeurMicro: Equatable, Identifiable {
    let nom: String
    let part: Int
    var id: String { nom }
}

struct LigneMicro: Equatable, Identifiable {
    let id: String
    let nom: String
    let unite: String
    let famille: FamilleMicro
    let sens: SensMicro
    /// Part du besoin couverte, de 0 à 100. nil = pas encore mesurable.
    let niveau: Int?
    /// Le chiffre part-il du questionnaire ? Sinon il ne vient que des repas.
    let partDuQuestionnaire: Bool
    let besoin: Double
    /// Quantité notée sur la journée affichée ; nil = aucun aliment ne la renseigne.
    /// Pour un rapport : le rapport de la journée affichée.
    let quantiteDuJour: Double?
    /// Pour un rapport seulement : sa valeur sur les repas notés (« 12 » pour
    /// 12 g d'oméga-6 par gramme d'oméga-3). nil = pas encore mesurable.
    let rapport: Double?
    let semaine: [JourMicro]
    let statut: StatutMicro
    let faits: [FaitMicro]
    let contributeurs: [ContributeurMicro]
    let role: String
    let sources: [String]
    /// Le statut de l'estimateur, quand il couvre ce micro : c'est lui, jamais
    /// un seuil sur le chiffre, qui décide des mots et des alertes.
    var statutApport: StatutApport? = nil
}

struct TableauMicros: Equatable {
    /// Les trois apports qui comptent le plus pour cette personne.
    let priorites: [LigneMicro]
    /// Tous les micros, dans l'ordre du catalogue.
    let toutes: [LigneMicro]

    /// Les apports en alerte prolongée, pour le bandeau du haut du Journal.
    var alertes: [LigneMicro] { toutes.filter { $0.statut.estUneAlerte && $0.sens == .besoin } }

    static let vide = TableauMicros(priorites: [], toutes: [])
}

enum MicrosDuJour {

    /// En dessous, la journée est basse pour cet apport (règle validée par Arthur).
    static let seuilBas = 60
    /// Nombre de jours bas, sur sept, qui déclenche l'alerte.
    static let joursPourAlerte = 3
    static let joursDeLaSemaine = 7
    static let nombreDePriorites = 3
    /// Journées assez notées qu'il faut pour donner un chiffre tiré des seuls repas.
    static let joursMinimum = JournalApports.joursMinimum
    static let fenetreJours = JournalApports.fenetreJours

    // MARK: Le tableau

    static func tableau(
        repas: [MealJournalService.MealRecord],
        jourAffiche: Date,
        compositions: Compositions,
        contexte: ContexteMicros,
        registre: [String: DetailApport],
        maintenant: Date = Date(),
        calendar: Calendar = .current
    ) -> TableauMicros {
        let journees = MesuresRepas.journees(repas: repas, compositions: compositions, calendar: calendar)
        let jour = calendar.startOfDay(for: jourAffiche)
        let aujourdhui = calendar.startOfDay(for: maintenant)

        // Les sept jours qui finissent au jour affiché.
        var semaine: [Date] = []
        for recul in stride(from: joursDeLaSemaine - 1, through: 0, by: -1) {
            if let date = calendar.date(byAdding: .day, value: -recul, to: jour) { semaine.append(date) }
        }
        // Les quatorze derniers jours, aujourd'hui compris : la journée en
        // cours compte dès qu'elle est assez notée (`MesuresRepas.couverture`).
        var quinzaine: [Date] = []
        for recul in 0..<fenetreJours {
            if let date = calendar.date(byAdding: .day, value: -recul, to: aujourdhui) { quinzaine.append(date) }
        }

        var lignes: [LigneMicro] = []
        for micro in Micronutriments.tous {
            if micro.sens == .rapport {
                lignes.append(ligneDuRapport(
                    micro, semaine: semaine, quinzaine: quinzaine, jour: jour,
                    jourEstAujourdhui: jour == aujourdhui, journees: journees, depense: contexte.depense
                ))
                continue
            }
            let besoin = contexte.besoins[micro.id] ?? 0

            func couverture(le date: Date) -> Double? {
                guard let journee = journees[date] else { return nil }
                return MesuresRepas.couverture(micro.id, journee: journee, besoin: besoin, depense: contexte.depense)
            }

            let jours = semaine.map { date in
                JourMicro(jour: date, couverture: couverture(le: date).map { Int($0.rounded()) })
            }
            let mesuresQuinzaine = quinzaine.compactMap { couverture(le: $0) }

            // Le chiffre : l'estimation quand elle couvre ce micro, sinon le
            // registre, sinon les repas seuls.
            var niveau: Int?
            var partDuQuestionnaire = false
            let estimation = micro.sens == .besoin ? contexte.estimations[micro.id] : nil
            let statutApport = estimation.map { contexte.statuts[micro.id] ?? $0.statut }
            if micro.sens == .besoin {
                if let estimation {
                    niveau = LectureEstimation.couverture(estimation)
                    partDuQuestionnaire = true
                } else if micro.apport != nil, let score = contexte.scores[micro.id] {
                    niveau = max(0, min(100, score))
                    partDuQuestionnaire = true
                } else if mesuresQuinzaine.count >= joursMinimum {
                    let moyenne = mesuresQuinzaine.reduce(0, +) / Double(mesuresQuinzaine.count)
                    niveau = max(0, min(100, Int(moyenne.rounded())))
                }
            }

            // Les repas seuls ne font plus d'alerte que l'estimateur ne
            // confirme pas : une journée ou trois sous 60 % ne suffisent pas à
            // affirmer un manque (vitamine D, B12…).
            var etat = Self.statut(sens: micro.sens, semaine: jours)
            if let statutApport, !(statutApport.estUneAlerte && etat.estUneAlerte) {
                etat = .normal
            }
            let quantiteDuJour = journees[jour]?.quantites[micro.id]

            let raisons = estimation.map {
                Self.faitsEstimes(micro: micro, estimation: $0, statut: statutApport ?? $0.statut,
                                  profil: contexte.profil, symptomes: contexte.symptomes,
                                  quantiteDuJour: quantiteDuJour, besoin: besoin,
                                  jourEstAujourdhui: jour == aujourdhui,
                                  mois: calendar.component(.month, from: maintenant))
            } ?? Self.faits(
                micro: micro,
                niveau: niveau,
                partDuQuestionnaire: partDuQuestionnaire,
                detail: registre[micro.id],
                couvertureJournal: contexte.couvertureJournal[micro.id],
                joursJournal: contexte.joursJournal[micro.id],
                joursMesures: mesuresQuinzaine.count,
                symptomes: contexte.symptomes,
                quantiteDuJour: quantiteDuJour,
                besoin: besoin,
                jourEstAujourdhui: jour == aujourdhui,
                mois: calendar.component(.month, from: maintenant)
            )

            lignes.append(LigneMicro(
                id: micro.id,
                nom: micro.nom,
                unite: micro.unite,
                famille: micro.famille,
                sens: micro.sens,
                niveau: niveau,
                partDuQuestionnaire: partDuQuestionnaire,
                besoin: besoin,
                quantiteDuJour: quantiteDuJour,
                rapport: nil,
                semaine: jours,
                statut: etat,
                faits: raisons,
                contributeurs: contributeurs(micro.id, jours: semaine, journees: journees),
                role: micro.role,
                sources: micro.sources,
                statutApport: statutApport
            ))
        }

        return TableauMicros(priorites: priorites(lignes, symptomes: contexte.symptomes), toutes: lignes)
    }

    // MARK: Le statut

    static func statut(sens: SensMicro, semaine: [JourMicro]) -> StatutMicro {
        let mesures = semaine.compactMap(\.couverture)
        switch sens {
        case .besoin:
            let bas = mesures.filter { $0 < seuilBas }.count
            if bas >= joursPourAlerte { return .basProlonge(jours: bas) }
            if let dernier = semaine.last?.couverture, dernier < seuilBas { return .basCeJour }
            return .normal
        case .limite:
            let hauts = mesures.filter { $0 > 100 }.count
            return hauts >= joursPourAlerte ? .auDessusDeLaLimite(jours: hauts) : .normal
        case .rapport:
            // Un repère à regarder, pas une alerte : la règle validée (trois
            // jours sur sept) porte sur les apports.
            return .normal
        }
    }

    // MARK: Le rapport oméga-6 / oméga-3

    /// Le repère de l'ANSES (2011) : acide linoléique / acide alpha-linolénique.
    static let rapportVise = 5.0
    /// Au-delà, un chiffre précis ne dit plus rien.
    static let rapportMaximal = 50.0
    /// Valeur retenue quand les repas apportent des oméga-6 et aucun oméga-3.
    static let rapportSansOmega3 = 999.0

    /// Oméga-6 (acide linoléique) et oméga-3 (acide alpha-linolénique) des
    /// aliments qui renseignent LES DEUX : comparer l'un mesuré sur tout le
    /// repas à l'autre mesuré sur la moitié fausserait le rapport. Avec
    /// `assezNotee`, la journée doit en plus être représentative, comme pour
    /// les autres chiffres.
    static func omegas(
        _ journee: JourneeMesuree,
        depense: Double,
        assezNotee: Bool
    ) -> (omega6: Double, omega3: Double)? {
        if assezNotee {
            guard journee.kcal > 0, journee.kcal >= depense * MesuresRepas.partMinimaleDesCalories else { return nil }
        }
        var omega6 = 0.0
        var omega3 = 0.0
        var kcal = 0.0
        var parts = 0
        for part in journee.bouchees {
            guard let linoleique = part.quantites["omega6"], let linolenique = part.quantites["ala"] else { continue }
            omega6 += linoleique
            omega3 += linolenique
            kcal += part.kcal
            parts += 1
        }
        guard parts > 0 else { return nil }
        if assezNotee {
            guard kcal > 0, kcal >= journee.kcal * MesuresRepas.partMinimaleRenseignee else { return nil }
        }
        return (omega6, omega3)
    }

    /// nil quand les repas n'apportent ni l'un ni l'autre.
    static func rapport(omega6: Double, omega3: Double) -> Double? {
        if omega3 > 0 { return min(rapportSansOmega3, omega6 / omega3) }
        return omega6 > 0 ? rapportSansOmega3 : nil
    }

    /// « 4,2 pour 1 », « 12 pour 1 », « plus de 50 pour 1 ».
    static func texteDuRapport(_ valeur: Double) -> String {
        valeur > rapportMaximal
            ? "plus de \(Int(rapportMaximal)) pour 1"
            : "\(quantite(valeur)) pour 1"
    }

    private static func ligneDuRapport(
        _ micro: MicroDefinition,
        semaine: [Date],
        quinzaine: [Date],
        jour: Date,
        jourEstAujourdhui: Bool,
        journees: [Date: JourneeMesuree],
        depense: Double
    ) -> LigneMicro {
        func mesure(le date: Date) -> (omega6: Double, omega3: Double)? {
            guard let journee = journees[date] else { return nil }
            return omegas(journee, depense: depense, assezNotee: true)
        }

        // Jour par jour, en part du repère : 100 = 5 pour 1.
        let jours = semaine.map { date -> JourMicro in
            let duJour = mesure(le: date).flatMap { rapport(omega6: $0.omega6, omega3: $0.omega3) }
            return JourMicro(jour: date, couverture: duJour.map { Int(($0 / rapportVise * 100).rounded()) })
        }

        // Sur la quinzaine : les grammes s'additionnent, puis on divise. Une
        // moyenne de rapports donnerait trop de poids à un petit repas.
        var omega6 = 0.0
        var omega3 = 0.0
        var mesures = 0
        for date in quinzaine {
            guard let duJour = mesure(le: date) else { continue }
            omega6 += duJour.omega6
            omega3 += duJour.omega3
            mesures += 1
        }
        let ensemble: Double? = mesures > 0 ? rapport(omega6: omega6, omega3: omega3) : nil

        // La journée affichée, telle qu'elle est notée à cet instant.
        var duJourAffiche: Double?
        if let journee = journees[jour], let note = omegas(journee, depense: depense, assezNotee: false) {
            duJourAffiche = rapport(omega6: note.omega6, omega3: note.omega3)
        }

        var raisons: [FaitMicro] = []
        if ensemble != nil {
            raisons.append(FaitMicro(genre: .repas, texte: "Calculé sur tes repas notés : \(Self.journees(mesures))."))
        } else {
            raisons.append(FaitMicro(genre: .repas, texte: "Pas encore de journée assez notée pour le calculer."))
        }
        let moment = jourEstAujourdhui ? "Aujourd'hui" : "Ce jour-là"
        if let duJourAffiche {
            raisons.append(FaitMicro(genre: .jour, texte: "\(moment) : \(texteDuRapport(duJourAffiche))."))
        } else {
            raisons.append(FaitMicro(genre: .jour, texte: "\(moment) : aucun aliment noté ne le renseigne."))
        }

        return LigneMicro(
            id: micro.id,
            nom: micro.nom,
            unite: micro.unite,
            famille: micro.famille,
            sens: micro.sens,
            niveau: nil,
            partDuQuestionnaire: false,
            besoin: rapportVise,
            quantiteDuJour: duJourAffiche,
            rapport: ensemble,
            semaine: jours,
            statut: .normal,
            faits: raisons,
            // Ce qui pèse dans le rapport : d'où viennent les oméga-6.
            contributeurs: contributeurs("omega6", jours: semaine, journees: journees),
            role: micro.role,
            sources: micro.sources
        )
    }

    // MARK: Les priorités

    /// Les apports qui comptent le plus pour cette personne : les plus bas
    /// d'abord, puis ceux en alerte prolongée, puis ceux qu'un symptôme déclaré
    /// éclaire. Le détail d'un autre apport (ALA, EPA et DHA) n'y entre pas, ni
    /// un apport sans chiffre.
    static func priorites(_ lignes: [LigneMicro], symptomes: [String]) -> [LigneMicro] {
        struct Candidat {
            let rang: Int
            let poids: Int
            let ligne: LigneMicro
        }
        var candidats: [Candidat] = []
        for (rang, ligne) in lignes.enumerated() {
            guard ligne.sens == .besoin, let niveau = ligne.niveau,
                  Micronutriments.parId[ligne.id]?.detailDe == nil else { continue }
            var poids = 100 - niveau
            // Le statut d'abord : une alerte sûre, puis « à surveiller », puis
            // « à affiner » ; un apport couvert ne passe jamais devant.
            switch ligne.statutApport {
            case .aRenforcer?, .auDessusDeLaLimite?: poids += 300
            case .aSurveiller?: poids += 200
            case .peuPrecise?: poids += 100
            case .couvert?, .couvertParComplement?, .sousLaLimite?: poids -= 100
            case nil: break
            }
            if case .basProlonge = ligne.statut { poids += 40 }
            poids += bonusSymptome(ligne.id, niveau: niveau, symptomes: symptomes)
            candidats.append(Candidat(rang: rang, poids: poids, ligne: ligne))
        }
        candidats.sort { gauche, droite in
            gauche.poids == droite.poids ? gauche.rang < droite.rang : gauche.poids > droite.poids
        }
        return candidats.prefix(nombreDePriorites).map(\.ligne)
    }

    /// Les liens solides de la table validée (`SymptomesApports`) : un lien
    /// faible ne pèse jamais seul. Le symptôme n'éclaire qu'un apport déjà bas.
    private static func liensSolides(_ id: String, symptomes: [String]) -> [LienSymptome] {
        guard let apport = NutrientID(rawValue: id) else { return [] }
        let declares = Set(symptomes)
        return SymptomesApports.liens.filter {
            $0.nutriment == apport && declares.contains($0.symptome) && $0.niveau != .faible
        }
    }

    private static func bonusSymptome(_ id: String, niveau: Int, symptomes: [String]) -> Int {
        guard niveau < seuilBas else { return 0 }
        let liens = liensSolides(id, symptomes: symptomes)
        if liens.contains(where: { $0.niveau == .fort }) { return 30 }
        return liens.isEmpty ? 0 : 20
    }

    // MARK: Les faits

    /// Les faits d'un micro estimé : d'où vient le chiffre (ses sources),
    /// ce qu'il faut pour l'affirmer, et la journée affichée. Plus de
    /// « points » : des quantités.
    static func faitsEstimes(
        micro: MicroDefinition,
        estimation e: EstimationApport,
        statut: StatutApport,
        profil: ProfilEstimation?,
        symptomes: [String],
        quantiteDuJour: Double?,
        besoin: Double,
        jourEstAujourdhui: Bool,
        mois: Int
    ) -> [FaitMicro] {
        var faits: [FaitMicro] = [FaitMicro(genre: .questionnaire, texte: LectureEstimation.provenance(e))]
        let unite = LectureEstimation.uniteAffichage(micro.id, estimation: e)
        if let premiere = LectureEstimation.sources(micro.id, e, profil: profil ?? ProfilEstimation()).first {
            let valeur = DS.decimal(LectureEstimation.arrondiLisible(premiere.valeur))
            faits.append(FaitMicro(
                genre: premiere.section == .journal ? .repas : .questionnaire,
                texte: "Ta plus grosse source : \(LectureEstimation.enMinuscule(premiere.libelle)), \(valeur)\(DS.fine)\(unite) par jour."
            ))
        }
        if let restant = LectureEstimation.journeesAvantFiabilite(e) {
            let n = restant.conseillees - restant.notees
            faits.append(FaitMicro(genre: .repas, texte: n > 1
                ? "Encore \(n) journées notées pour pouvoir l'affirmer."
                : "Encore 1 journée notée pour pouvoir l'affirmer."))
        }
        if statut.estSousLaReference, let lien = liensSolides(micro.id, symptomes: symptomes).first {
            faits.append(FaitMicro(genre: .symptome, texte: "Tu as signalé \(lien.formulation)."))
        } else if micro.id == "vitD", [10, 11, 12, 1, 2, 3].contains(mois) {
            faits.append(FaitMicro(
                genre: .saison,
                texte: "D'octobre à mars, le soleil ne suffit pas à en fabriquer sous nos latitudes."
            ))
        }
        let moment = jourEstAujourdhui ? "Aujourd'hui" : "Ce jour-là"
        if let quantiteDuJour, besoin > 0 {
            faits.append(FaitMicro(
                genre: .jour,
                texte: "\(moment) : \(quantite(quantiteDuJour)) noté\(DS.fine)\(micro.unite)."
            ))
        } else {
            faits.append(FaitMicro(genre: .jour, texte: "\(moment) : aucun aliment noté ne le renseigne."))
        }
        return faits
    }

    private static func points(_ delta: Int) -> String {
        let signe = delta >= 0 ? "+" : "\u{2212}"
        let valeur = abs(delta)
        return "\(signe)\(valeur) \(valeur > 1 ? "points" : "point")"
    }

    /// « 1 journée », « 6 journées ».
    private static func journees(_ nombre: Int) -> String {
        nombre > 1 ? "\(nombre) journées" : "\(nombre) journée"
    }

    static func faits(
        micro: MicroDefinition,
        niveau: Int?,
        partDuQuestionnaire: Bool,
        detail: DetailApport?,
        couvertureJournal: Int?,
        joursJournal: Int? = nil,
        joursMesures: Int,
        symptomes: [String],
        quantiteDuJour: Double?,
        besoin: Double,
        jourEstAujourdhui: Bool,
        mois: Int
    ) -> [FaitMicro] {
        var faits: [FaitMicro] = []

        if micro.sens == .limite {
            faits.append(FaitMicro(genre: .repas, texte: "Suivi sur tes repas notés, sans chiffre de départ."))
        } else if partDuQuestionnaire {
            // 1. Ce que la personne a répondu : le facteur le plus lourd.
            let declares = (detail?.contributions ?? []).filter { $0.section != .journal && $0.section != .priseDeSang }
            let frein = declares.filter { $0.delta < 0 }.min { $0.delta < $1.delta }
            let appui = declares.filter { $0.delta > 0 }.max { $0.delta < $1.delta }
            if let retenu = frein ?? appui {
                faits.append(FaitMicro(
                    genre: .questionnaire,
                    texte: "Ton questionnaire : « \(retenu.libelle) » (\(points(retenu.delta)))."
                ))
            } else {
                faits.append(FaitMicro(genre: .questionnaire, texte: "Ton questionnaire ne signale rien qui pèse sur cet apport."))
            }

            // 2. Ce que les repas notés ont changé au chiffre.
            let correction = detail?.contributions.first { $0.section == .journal }
            let notes = joursJournal.map { " (\(journees($0)))" } ?? ""
            if let couvertureJournal, let correction {
                faits.append(FaitMicro(
                    genre: .repas,
                    texte: "Tes repas notés\(notes) couvrent \(DS.pourcent(couvertureJournal)) de ton besoin : \(points(correction.delta))."
                ))
            } else if let couvertureJournal {
                faits.append(FaitMicro(
                    genre: .repas,
                    texte: "Tes repas notés\(notes) couvrent \(DS.pourcent(couvertureJournal)) de ton besoin : ils confirment ce chiffre."
                ))
            } else {
                faits.append(FaitMicro(
                    genre: .repas,
                    texte: "Pas encore de journée assez notée pour l'ajuster."
                ))
            }

            // 3. Un fait de plus, le plus solide disponible.
            if let sang = detail?.contributions.first(where: { $0.section == .priseDeSang }) {
                faits.append(FaitMicro(genre: .priseDeSang, texte: "Ta prise de sang : \(points(sang.delta))."))
            } else if let niveau, niveau < seuilBas,
                      let lien = liensSolides(micro.id, symptomes: symptomes).first {
                faits.append(FaitMicro(genre: .symptome, texte: "Tu as signalé \(lien.formulation)."))
            } else if micro.id == "vitD", [10, 11, 12, 1, 2, 3].contains(mois) {
                faits.append(FaitMicro(
                    genre: .saison,
                    texte: "D'octobre à mars, le soleil ne suffit pas à en fabriquer sous nos latitudes."
                ))
            }
        } else if niveau != nil {
            faits.append(FaitMicro(
                genre: .repas,
                texte: "Calculé sur tes repas notés : \(journees(joursMesures))."
            ))
        } else {
            faits.append(FaitMicro(
                genre: .repas,
                texte: "Pas encore de journée assez notée pour le calculer."
            ))
        }

        // Toujours : ce que la journée affichée a apporté.
        let moment = jourEstAujourdhui ? "Aujourd'hui" : "Ce jour-là"
        if let quantiteDuJour, besoin > 0 {
            let suffixe = micro.sens == .limite ? " au plus" : ""
            faits.append(FaitMicro(
                genre: .jour,
                texte: "\(moment) : \(quantite(quantiteDuJour)) sur \(quantite(besoin))\(DS.fine)\(micro.unite)\(suffixe)."
            ))
        } else {
            faits.append(FaitMicro(genre: .jour, texte: "\(moment) : aucun aliment noté ne le renseigne."))
        }
        return faits
    }

    /// « 0,25 », « 4,2 », « 120 » : la précision suit l'ordre de grandeur.
    static func quantite(_ valeur: Double) -> String {
        let absolue = abs(valeur)
        if absolue >= 10 { return DS.entier(Int(valeur.rounded())) }
        if absolue >= 1 { return DS.decimal(valeur, decimales: 1) }
        return DS.decimal(valeur, decimales: 2)
    }

    // MARK: D'où ça vient dans les repas

    /// Les trois aliments qui ont le plus porté cet apport sur la semaine
    /// affichée, avec leur part. Vide quand rien n'est renseigné.
    static func contributeurs(
        _ id: String,
        jours: [Date],
        journees: [Date: JourneeMesuree]
    ) -> [ContributeurMicro] {
        var parAliment: [String: Double] = [:]
        for jour in jours {
            guard let journee = journees[jour] else { continue }
            for part in journee.bouchees {
                guard let nom = part.nom, !nom.isEmpty, let quantite = part.quantites[id], quantite > 0 else { continue }
                parAliment[nom, default: 0] += quantite
            }
        }
        let total = parAliment.values.reduce(0, +)
        guard total > 0 else { return [] }
        let tries = parAliment.sorted { gauche, droite in
            gauche.value == droite.value ? gauche.key < droite.key : gauche.value > droite.value
        }
        var sortie: [ContributeurMicro] = []
        for (nom, quantite) in tries.prefix(3) {
            let part = Int((quantite / total * 100).rounded())
            guard part > 0 else { continue }
            sortie.append(ContributeurMicro(nom: nom, part: part))
        }
        return sortie
    }
}
