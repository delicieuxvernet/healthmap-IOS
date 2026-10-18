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
            case "remplacer": return "REMPLACE"
            case "garder": return "GARDE"
            case "deplacer": return "DÉPLACE"
            default: return "AJOUTE"
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

    private static let moisCourts = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]

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
