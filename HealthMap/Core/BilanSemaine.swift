import Foundation

// MARK: - Bilan de la semaine (demande d'Arthur du 14 oct. 2026)
//
// « Au bout de 10 repas renseignés, ou à la fin d'une semaine, un vrai bilan de
// ce que la personne a mangé : ce qui manque, les habitudes qui pèsent sur ses
// résultats, des recommandations très concrètes. »
//
// L'app calcule tous les chiffres (repas notés, Ciqual, besoins de la personne,
// objectifs du Journal) et les envoie à la fonction `weekly-review`, qui les
// fait lire par l'IA et vérifie chaque phrase côté serveur. Le bilan reçu est
// gardé sur le téléphone : rien n'est stocké côté serveur. Seuls partent les
// repas et les apports (déjà au serveur) : ni l'eau ni les ressentis, qui ne
// quittent jamais le téléphone.

/// Le bilan rendu par `weekly-review`. Les chiffres (pourcentages, jours,
/// gains) viennent de l'app ou des aliments candidats, jamais de l'IA.
struct BilanSemaine: Codable, Equatable, Identifiable {
    struct Periode: Codable, Equatable {
        let debut: String
        let fin: String
    }

    struct Manque: Codable, Equatable, Identifiable {
        let id: String
        let nom: String
        /// Le chiffre de l'apport dans l'app (ou la moyenne d'une macro en % de
        /// son objectif).
        let moyennePct: Int
        let joursBas: Int
        let joursMesures: Int
        let explication: String
        /// `apport` (vitamines, minéraux, fibres) ou `macro` (glucides…).
        let type: String
    }

    struct Habitude: Codable, Equatable, Identifiable {
        /// `frein` ou `atout`.
        let type: String
        let titre: String
        let constat: String
        let apports: [String]
        let illustration: String

        var id: String { titre }
        var estUnAtout: Bool { type == "atout" }
    }

    struct Recommandation: Codable, Equatable, Identifiable {
        /// `ajouter`, `remplacer`, `garder` ou `deplacer`.
        let action: String
        let titre: String
        let detail: String
        let apports: [String]
        /// Nom exact d'un aliment candidat, vide sinon.
        let aliment: String
        let portion: String
        /// Gain d'une portion en % du besoin, recopié du candidat ; nil sinon.
        let gainPct: Int?
        let illustration: String

        var id: String { titre }

        var verbe: String {
            switch action {
            case "remplacer": return String(localized: "REMPLACE")
            case "garder": return String(localized: "GARDE")
            case "deplacer": return String(localized: "DÉPLACE")
            default: return String(localized: "AJOUTE")
            }
        }
    }

    struct Objectif: Codable, Equatable {
        let titre: String
        let detail: String
    }

    struct Meta: Codable, Equatable {
        let modele: String?
        let genere_le: String?
    }

    let version: Int
    let periode: Periode
    let repasNotes: Int
    let joursNotes: Int
    let titre: String
    let resume: String
    let manques: [Manque]
    let habitudes: [Habitude]
    let recommandations: [Recommandation]
    let objectif: Objectif
    let meta: Meta?

    var id: String { periode.fin }

    /// « 7 – 13 oct. »
    var periodeLisible: String {
        BilanSemaineRegle.periodeLisible(debut: periode.debut, fin: periode.fin)
    }
}

// MARK: - Quand le bilan est proposé

enum BilanSemaineRegle {
    /// Repas notés sur les 7 derniers jours pour débloquer un bilan (Arthur :
    /// « au bout de 10 repas renseignés »).
    static let repasMinimum = 10
    /// Et sur au moins 3 jours : dix encas d'une seule journée ne disent rien
    /// d'une semaine.
    static let joursMinimum = 3
    /// Écart minimal entre deux bilans : un par semaine.
    static let joursEntreDeuxBilans = 7
    /// Fenêtre relue : les 7 derniers jours, aujourd'hui compris.
    static let joursRelus = 7

    enum Etat: Equatable {
        /// Pas encore assez de repas cette semaine : combien en sont notés.
        case enCours(repas: Int)
        /// Assez de repas, aucun bilan récent : on peut le préparer.
        case aPreparer(repas: Int)
        /// Le bilan de la semaine est là.
        case pret(BilanSemaine)
    }

    /// L'état de la carte, à partir des repas notés sur les 7 derniers jours et
    /// du dernier bilan gardé sur le téléphone.
    static func etat(repas: Int, jours: Int, dernier: BilanSemaine?,
                     maintenant: Date = Date(), calendrier: Calendar = .current) -> Etat {
        if let dernier, let fin = date(dernier.periode.fin) {
            let ecart = calendrier.dateComponents([.day], from: calendrier.startOfDay(for: fin),
                                                  to: calendrier.startOfDay(for: maintenant)).day ?? 0
            if ecart < joursEntreDeuxBilans { return .pret(dernier) }
        }
        if repas >= repasMinimum, jours >= joursMinimum { return .aPreparer(repas: repas) }
        return .enCours(repas: repas)
    }

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ texte: String) -> Date? { iso.date(from: texte) }
    static func texte(_ date: Date) -> String { iso.string(from: date) }

    private static let moisCourts = [
        String(localized: "janv."), String(localized: "févr."), String(localized: "mars"), String(localized: "avr."),
        String(localized: "mai"), String(localized: "juin"), String(localized: "juil."), String(localized: "août"),
        String(localized: "sept."), String(localized: "oct."), String(localized: "nov."), String(localized: "déc."),
    ]

    /// « 7 – 13 oct. », ou « 28 sept. – 4 oct. » à cheval sur deux mois.
    static func periodeLisible(debut: String, fin: String, calendrier: Calendar = .current) -> String {
        guard let d = date(debut), let f = date(fin) else { return "" }
        let jd = calendrier.component(.day, from: d), jf = calendrier.component(.day, from: f)
        let md = calendrier.component(.month, from: d), mf = calendrier.component(.month, from: f)
        let moisFin = moisCourts[(mf + 11) % 12]
        if md == mf { return "\(jd) – \(jf) \(moisFin)" }
        return "\(jd) \(moisCourts[(md + 11) % 12]) – \(jf) \(moisFin)"
    }
}

// MARK: - Le bilan gardé sur le téléphone

enum BilanSemaineStore {
    /// Préfixe `healthmap_` : effacé à la déconnexion (`AuthViewModel.clearLocalCaches`).
    private static let cle = "healthmap_bilan_semaine_v1"

    static func dernier(defaults: UserDefaults = .standard) -> BilanSemaine? {
        guard let data = defaults.data(forKey: cle) else { return nil }
        return try? JSONDecoder().decode(BilanSemaine.self, from: data)
    }

    static func enregistrer(_ bilan: BilanSemaine, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(bilan) else { return }
        defaults.set(data, forKey: cle)
    }
}

#if DEBUG
// MARK: - Captures d'écran

/// `-captureBilanSemaine YES` : la carte de Progrès porte un bilan d'exemple,
/// sans appel au serveur ni enregistrement. Les chiffres sont ceux d'un profil
/// fictif, comme le récap d'exemple (`RecapDuJourExemple`).
enum BilanSemaineExemple {
    static func depuisLesArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments,
                                   maintenant: Date = Date()) -> BilanSemaine? {
        guard arguments.contains("-captureBilanSemaine") else { return nil }
        return exemple(maintenant: maintenant)
    }

    static func exemple(maintenant: Date = Date(), calendrier: Calendar = .current) -> BilanSemaine {
        let fin = calendrier.startOfDay(for: maintenant)
        let debut = calendrier.date(byAdding: .day, value: -(BilanSemaineRegle.joursRelus - 1), to: fin) ?? fin
        return BilanSemaine(
            version: 1,
            periode: .init(debut: BilanSemaineRegle.texte(debut), fin: BilanSemaineRegle.texte(fin)),
            repasNotes: 14,
            joursNotes: 6,
            titre: String(localized: "Une semaine régulière, il manque le poisson"),
            resume: String(localized: "14 repas notés sur 6 jours. Tes protéines suivent, mais la vitamine D et les oméga-3 restent bas : aucun poisson gras cette semaine."),
            manques: [
                .init(id: "vitD", nom: String(localized: "Vitamine D"), moyennePct: 24, joursBas: 6, joursMesures: 6,
                      explication: String(localized: "Ni poisson gras ni œufs cette semaine : tes repas en apportent très peu, et le soleil d'octobre ne compense plus."),
                      type: "apport"),
                .init(id: "omega3", nom: String(localized: "Oméga-3"), moyennePct: 31, joursBas: 5, joursMesures: 6,
                      explication: String(localized: "Tes matières grasses viennent surtout du beurre et de l'huile de tournesol, pauvres en oméga-3."),
                      type: "apport"),
                .init(id: "fiber", nom: String(localized: "Fibres"), moyennePct: 58, joursBas: 4, joursMesures: 6,
                      explication: String(localized: "Pain blanc et pâtes le midi : les versions complètes apportent deux à trois fois plus de fibres."),
                      type: "apport"),
            ],
            habitudes: [
                .init(type: "frein", titre: String(localized: "Des pâtes blanches 5 midis sur 6"),
                      constat: String(localized: "Le même plat revient presque chaque midi : c'est là que tes fibres se perdent."),
                      apports: ["fiber", "magnesium"], illustration: "pates"),
                .init(type: "atout", titre: String(localized: "Un fruit chaque matin"),
                      constat: String(localized: "L'orange du petit-déjeuner couvre ta vitamine C presque tous les jours."),
                      apports: ["vitC"], illustration: "agrume"),
            ],
            recommandations: [
                .init(action: "ajouter", titre: String(localized: "Des sardines deux fois par semaine"),
                      detail: String(localized: "En boîte, sur du pain complet ou dans une salade : c'est ce qui remonte le plus ta vitamine D et tes oméga-3."),
                      apports: ["vitD", "omega3"], aliment: "Sardines", portion: String(localized: "1 boîte"), gainPct: 33,
                      illustration: "poisson"),
                .init(action: "remplacer", titre: String(localized: "Les pâtes blanches par des complètes"),
                      detail: String(localized: "Même plat, même cuisson : deux fois plus de fibres, et du magnésium en plus."),
                      apports: ["fiber", "magnesium"], aliment: "", portion: "", gainPct: nil,
                      illustration: "pates"),
                .init(action: "garder", titre: String(localized: "Ton fruit du matin"),
                      detail: String(localized: "Il couvre ta vitamine C chaque jour : garde-le."),
                      apports: ["vitC"], aliment: "", portion: "", gainPct: nil,
                      illustration: "agrume"),
            ],
            objectif: .init(titre: String(localized: "Deux repas de poisson gras"),
                            detail: String(localized: "Note-les : ton prochain bilan montrera ce qu'ils changent pour ta vitamine D.")),
            meta: .init(modele: "exemple", genere_le: nil)
        )
    }
}
#endif
