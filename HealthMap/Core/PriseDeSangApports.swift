import Foundation

// MARK: - La prise de sang corrige les apports (30 sept. 2026)
//
// Le questionnaire dit ce que la personne DÉCLARE, le journal ce qu'elle
// MANGE ; une prise de sang dit ce qui est MESURÉ. Elle passe donc en dernier,
// et pèse plus lourd que les deux autres : une ligne nommée de la cascade
// (« Ta prise de sang du 12 sept. »), qui tire le score vers ce que la mesure
// montre. Le bilan, la fiche apport, le Plan et les Compléments lisent tous
// ce même registre : ils suivent sans rien savoir de la prise de sang.
//
// Qui décide quoi :
//   · le serveur (`analyze-blood-report`) fait RECOPIER au modèle la valeur et
//     l'intervalle imprimé, puis situe la valeur dans cet intervalle — le code
//     compare, le modèle ne juge jamais ;
//   · ici, une position devient une cible de score, et la cible une traction
//     bornée. Rien n'est inventé : sans intervalle imprimé, aucun effet.
//
// Garde-fous :
//   · une prise de sang de plus de 12 mois n'a plus d'effet ; au-delà de 6
//     mois, elle ne compte qu'à moitié ;
//   · le calcium et le magnésium du sang sont tenus serrés par le corps : une
//     valeur DANS l'intervalle ne dit rien des apports, seule une valeur hors
//     de l'intervalle compte ;
//   · la correction tire le score de 70 % de l'écart, bornée à ±35 points ;
//   · aucun verdict : l'écran parle de « repères du laboratoire » et renvoie
//     vers le médecin (compliance du 6 juil. 2026).

/// Où une valeur se situe dans l'intervalle imprimé par le laboratoire.
/// Calculé par le serveur ; l'app n'en fait que la lecture.
enum PositionRepere: String, Codable, Equatable {
    case sousRepere = "sous_repere"
    case basDuRepere = "bas_du_repere"
    case dansRepere = "dans_repere"
    case auDessus = "au_dessus"
    case sansRepere = "sans_repere"

    /// Tolérant : une position inconnue (version serveur plus récente) se lit
    /// « sans repère », qui n'a aucun effet.
    init(from decoder: Decoder) throws {
        let brut = try decoder.singleValueContainer().decode(String.self)
        self = PositionRepere(rawValue: brut) ?? .sansRepere
    }
}

/// Une valeur lue sur le compte rendu.
struct MarqueurSanguin: Codable, Equatable, Identifiable {
    let code: String
    /// L'apport de Kiwio auquel elle renvoie ; nil hors des dix (folates).
    let nutriment: String?
    let libelle: String
    let valeur: Double
    let unite: String
    let borneBasse: Double?
    let borneHaute: Double?
    let position: PositionRepere

    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code, nutriment, libelle, valeur, unite, position
        case borneBasse = "borne_basse"
        case borneHaute = "borne_haute"
    }
}

/// Une prise de sang importée (ligne de `blood_reports`, lecture seule).
struct PriseDeSang: Codable, Equatable, Identifiable {
    let id: String
    /// « 2026-09-12 » — la date du prélèvement, ou le jour de l'import.
    let takenAt: String
    /// Vrai quand la date a été lue sur le document.
    let dateLue: Bool
    let markers: [MarqueurSanguin]

    enum CodingKeys: String, CodingKey {
        case id, markers
        case takenAt = "taken_at"
        case dateLue = "date_lue"
    }

    init(id: String, takenAt: String, dateLue: Bool, markers: [MarqueurSanguin]) {
        self.id = id
        self.takenAt = takenAt
        self.dateLue = dateLue
        self.markers = markers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        takenAt = try c.decode(String.self, forKey: .takenAt)
        dateLue = (try? c.decode(Bool.self, forKey: .dateLue)) ?? false
        // Un marqueur illisible n'emporte pas les autres.
        markers = (try? c.decode(LossyMarqueurs.self, forKey: .markers).valeurs) ?? []
    }

    private struct LossyMarqueurs: Decodable {
        let valeurs: [MarqueurSanguin]
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            var sortie: [MarqueurSanguin] = []
            while !c.isAtEnd {
                if let m = try? c.decode(MarqueurSanguin.self) {
                    sortie.append(m)
                } else if (try? c.decode(Rebut.self)) == nil {
                    // Ni marqueur ni objet (une chaîne, un nombre) : le curseur
                    // n'avancerait plus, on s'arrête plutôt que de boucler.
                    break
                }
            }
            valeurs = sortie
        }
        private struct Rebut: Decodable, Equatable {}
    }

    private static let lecture: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var date: Date? { Self.lecture.date(from: takenAt) }

    /// « 12 sept. » (année ajoutée si ce n'est pas l'année en cours).
    func dateCourte(maintenant: Date = Date()) -> String {
        guard let date else { return takenAt }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.timeZone = TimeZone(identifier: "UTC")
        let memeAnnee = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: maintenant)
        f.dateFormat = memeAnnee ? "d MMM" : "d MMM yyyy"
        return f.string(from: date)
    }
}

enum PriseDeSangApports {

    /// Au-delà, la prise de sang ne compte plus qu'à moitié…
    static let moisPleinEffet = 6
    /// … et au-delà de celle-ci, plus du tout.
    static let moisMaximum = 12
    /// La mesure tire le score de cette part de l'écart (en %, entier : en
    /// flottant, 45 × 0,7 vaut 31,4999… et s'arrondirait à 31)…
    static let tractionPourcent = 70
    /// … sans jamais le déplacer de plus de ces points.
    static let plafond = 35
    static let effetMinimum = 2

    /// Marqueurs que le corps garde dans l'intervalle quels que soient les
    /// apports : seule une valeur hors de l'intervalle en dit quelque chose.
    static let marqueursRegules: Set<String> = ["calcium", "magnesium"]

    /// Le score vers lequel une position tire l'apport.
    static func cible(_ position: PositionRepere, code: String) -> Int? {
        let regule = marqueursRegules.contains(code)
        switch position {
        case .sousRepere: return 30
        case .basDuRepere: return regule ? nil : 55
        case .dansRepere: return regule ? nil : 85
        case .auDessus: return 95
        case .sansRepere: return nil
        }
    }

    /// 1 jusqu'à 6 mois, 0,5 jusqu'à 12, 0 au-delà (et pour une date illisible).
    static func fraicheur(_ prise: PriseDeSang, maintenant: Date = Date(), calendar: Calendar = .current) -> Double {
        guard let date = prise.date,
              let mois = calendar.dateComponents([.month], from: date, to: maintenant).month else { return 0 }
        if mois < 0 { return 1 }
        if mois < moisPleinEffet { return 1 }
        if mois < moisMaximum { return 0.5 }
        return 0
    }

    /// La correction d'un apport, en points.
    static func correction(score: Int, cible: Int, fraicheur: Double) -> Int {
        let points = Int((Double((cible - score) * tractionPourcent) / 100 * fraicheur).rounded())
        return max(-plafond, min(plafond, points))
    }

    static func libelle(_ prise: PriseDeSang, maintenant: Date = Date()) -> String {
        "Ta prise de sang du \(prise.dateCourte(maintenant: maintenant))"
    }

    /// Ce que la prise de sang apporte au hash du bilan : sa date, puis ce
    /// qu'elle change aux scores. La date seule suffit à régénérer le bilan —
    /// il la CITE (`generate-analysis` lit `blood_reports`, 1er oct. 2026),
    /// même quand elle ne déplace aucun score. Vide sans prise de sang : aucun
    /// autre bilan ne se régénère.
    static func signatureDuBilan(_ prise: PriseDeSang?, scores: String) -> String {
        guard let prise else { return "" }
        return "\(prise.takenAt)/\(scores)"
    }

    /// Le moment où la prise de sang cesse de compter pleinement : c'est là
    /// que le rappel sonne (`RappelsPersonnalises`).
    static func finDuPleinEffet(prelevement: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .month, value: moisPleinEffet, to: prelevement)
    }

    /// Ce que la prise de sang a changé à un apport.
    struct Effet: Equatable, Identifiable {
        let id: String
        let avant: Int
        let apres: Int
    }

    /// Le marqueur qui parle pour un apport (le premier relié, le serveur les
    /// ayant déjà triés : ferritine avant fer sérique).
    static func marqueur(pour nutriment: String, dans prise: PriseDeSang) -> MarqueurSanguin? {
        prise.markers.first { $0.nutriment == nutriment }
    }

    /// Le registre, avec la ligne de la prise de sang sur chaque apport mesuré.
    static func appliquer(
        _ registre: [String: DetailApport],
        priseDeSang: PriseDeSang?,
        maintenant: Date = Date()
    ) -> [String: DetailApport] {
        guard let priseDeSang else { return registre }
        let poids = fraicheur(priseDeSang, maintenant: maintenant)
        guard poids > 0 else { return registre }
        let texte = libelle(priseDeSang, maintenant: maintenant)

        var sortie = registre
        for (id, detail) in registre {
            guard let m = marqueur(pour: id, dans: priseDeSang),
                  let vers = cible(m.position, code: m.code) else { continue }
            let delta = correction(score: detail.score, cible: vers, fraicheur: poids)
            guard abs(delta) >= effetMinimum else { continue }
            sortie[id] = detail.ajoutant(ContributionApport(libelle: texte, delta: delta, section: .priseDeSang))
        }
        return sortie
    }

    // MARK: Lecture à l'écran

    /// Les trois états montrés à la personne — jamais un verdict.
    enum Etat: Equatable {
        case aOptimiser
        case dansLesReperes
        case auDessus
        case sansRepere

        var libelle: String {
            switch self {
            case .aOptimiser: return "à optimiser"
            case .dansLesReperes: return "dans les repères"
            case .auDessus: return "au-dessus du repère"
            case .sansRepere: return "sans repère imprimé"
            }
        }
    }

    static func etat(_ m: MarqueurSanguin) -> Etat {
        switch m.position {
        case .sousRepere, .basDuRepere: return .aOptimiser
        case .dansRepere: return .dansLesReperes
        case .auDessus: return .auDessus
        case .sansRepere: return .sansRepere
        }
    }

    /// Les aliments à mettre dans l'assiette pour une valeur à optimiser.
    static func aliments(pour m: MarqueurSanguin) -> [String] {
        if let n = m.nutriment, let liste = SourcesAlimentaires.parNutriment[n] { return liste }
        if m.code == "folates" { return ["Légumes verts", "Légumineuses", "Avocat"] }
        return []
    }

    /// « 18 ng/mL » — virgule décimale, sans zéro inutile.
    static func valeurLisible(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = v < 10 ? 2 : (v < 100 ? 1 : 0)
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// « repère 30–100 », « repère ≥ 30 », « repère ≤ 5 », ou nil.
    static func repereLisible(_ m: MarqueurSanguin) -> String? {
        switch (m.borneBasse, m.borneHaute) {
        case let (b?, h?): return "repère \(valeurLisible(b))–\(valeurLisible(h))"
        case let (b?, nil): return "repère ≥ \(valeurLisible(b))"
        case let (nil, h?): return "repère ≤ \(valeurLisible(h))"
        default: return nil
        }
    }
}
