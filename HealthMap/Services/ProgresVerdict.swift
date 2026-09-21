import Foundation

// MARK: - Progrès : le verdict de la semaine (maquette « Progrès v3 », 20 sept. 2026)
//
// La page donne d'abord la réponse, en trois phrases au plus — un symptôme, un
// apport, les calories — puis le graphe pour qui veut voir. Tout est calculé
// ici, à partir de ce que l'app sait déjà : aucune I/O, aucun réseau, donc
// testable ligne par ligne.
//
// Frontière Premium (inchangée) : l'ÉVOLUTION d'un symptôme et la TENDANCE des
// apports sont ce que vendent les portes `suivi_symptomes` et `suivi_micros`.
// En gratuit, la ligne nomme le sujet suivi, jamais son verdict.

enum ProgresVerdict {

    enum Genre: Equatable {
        case symptome
        case apport(id: String)
        case calories
    }

    struct Ligne: Identifiable, Equatable {
        let genre: Genre
        /// Le début de phrase, en gras : la réponse.
        let gras: String
        /// La fin de phrase, en encre normale : la précision.
        let suite: String

        var id: String {
            switch genre {
            case .symptome: return "symptome"
            case .apport(let id): return "apport.\(id)"
            case .calories: return "calories"
            }
        }
    }

    // MARK: Symptôme

    /// Le symptôme dont on parle : le premier qui s'améliore, sinon le premier
    /// qui a une tendance, sinon le premier tout court.
    static func symptomeRetenu(_ evolutions: [SuiviEngineV4.SymptomEvolution]) -> SuiviEngineV4.SymptomEvolution? {
        let mesures = evolutions.filter { aUneTendance($0) }
        return mesures.first { $0.improving && $0.verdict != "Stable" } ?? mesures.first ?? evolutions.first
    }

    /// Une tendance se lit à partir de deux points : le départ et une réponse.
    static func aUneTendance(_ evolution: SuiviEngineV4.SymptomEvolution) -> Bool {
        !evolution.isExample && evolution.reel.count >= 2
    }

    static func ligneSymptome(_ evolutions: [SuiviEngineV4.SymptomEvolution], verrouille: Bool) -> Ligne? {
        guard let evolution = symptomeRetenu(evolutions) else { return nil }
        let trend = SymptomTrend.make(from: evolution.nom)
        let sujet = majuscule(trend.noun)

        guard aUneTendance(evolution) else {
            return Ligne(genre: .symptome, gras: sujet, suite: " : ton suivi démarre, tes réponses vont le dessiner.")
        }
        if verrouille {
            return Ligne(genre: .symptome, gras: sujet, suite: " : ta tendance se dessine, réponse après réponse.")
        }
        switch evolution.verdict {
        case "En amélioration":
            return Ligne(genre: .symptome, gras: "\(sujet) \(vaMieux(trend))", suite: " depuis tes premières réponses.")
        case "À surveiller":
            return Ligne(genre: .symptome, gras: "\(sujet) : à surveiller", suite: " ces jours-ci.")
        default:
            return Ligne(genre: .symptome, gras: "\(sujet) : stable", suite: " depuis tes premières réponses.")
        }
    }

    /// « vont mieux », « va mieux », ou « recule » quand le sujet EST le
    /// problème (on ne dit pas d'une fatigue qu'elle va mieux).
    static func vaMieux(_ trend: SymptomTrend) -> String {
        switch trend.noun {
        case "ta fatigue", "ton stress": return "recule"
        default: return trend.noun.hasPrefix("tes ") ? "vont mieux" : "va mieux"
        }
    }

    /// Les crans gagnés : une réponse « mieux » en vaut un, « moins bien » en
    /// retire un, « pareil » ne compte pas. Positif = dans le bon sens.
    static func niveauxGagnes(ressentis: [Int]) -> Int {
        ressentis.reduce(0) { total, ressenti in
            switch ressenti {
            case 0: return total + 1
            case 2: return total - 1
            default: return total
            }
        }
    }

    /// « +2 niveaux », « −1 niveau », « stable ». Le signe moins est le vrai
    /// (U+2212), comme partout dans l'app.
    static func libelleNiveaux(_ niveaux: Int) -> String {
        guard niveaux != 0 else { return "stable" }
        let signe = niveaux > 0 ? "+" : "\u{2212}"
        let valeur = abs(niveaux)
        return "\(signe)\(valeur) niveau\(valeur > 1 ? "x" : "")"
    }

    // MARK: Apport

    /// Sous ce nombre de jours suivis sur sept, comparer la semaine au départ
    /// reviendrait à juger un apport sur deux repas : on ne dit rien.
    static let joursMinimumPourComparer = 3

    /// Un écart plus petit que ça n'est pas une tendance, c'est du bruit.
    static let ecartMinimum = 3

    /// L'apport qui a le plus bougé depuis le départ : la plus forte hausse,
    /// sinon la plus forte baisse.
    static func apportRetenu(_ couverture: [SuiviEngineV4.NutrientCoverage7d]) -> SuiviEngineV4.NutrientCoverage7d? {
        let ecarts = couverture.filter { abs($0.pct - $0.baselinePct) >= ecartMinimum }
        let hausse = ecarts.filter { $0.pct > $0.baselinePct }.max { ($0.pct - $0.baselinePct) < ($1.pct - $1.baselinePct) }
        return hausse ?? ecarts.min { ($0.pct - $0.baselinePct) < ($1.pct - $1.baselinePct) }
    }

    static func ligneApport(couverture: [SuiviEngineV4.NutrientCoverage7d],
                            joursSuivis: Int,
                            verrouille: Bool) -> Ligne? {
        guard joursSuivis >= joursMinimumPourComparer else { return nil }
        if verrouille {
            guard let premier = couverture.first else { return nil }
            return Ligne(genre: .apport(id: premier.id), gras: premier.nom,
                         suite: " : ta tendance se mesure, repas après repas.")
        }
        guard let apport = apportRetenu(couverture) else { return nil }
        let sens = apport.pct > apport.baselinePct ? "en hausse" : "en baisse"
        return Ligne(genre: .apport(id: apport.id), gras: "\(apport.nom) \(sens)",
                     suite: " : \(apport.baselinePct) → \(apport.pct) %.")
    }

    // MARK: Calories

    static func ligneCalories(joursSuivis: Int, joursDansLaCible: Int, besoinConnu: Bool) -> Ligne? {
        guard besoinConnu, joursSuivis > 0 else { return nil }
        let pluriel = joursDansLaCible > 1 ? "s" : ""
        return Ligne(genre: .calories,
                     gras: "Calories : \(joursDansLaCible) jour\(pluriel) sur \(joursSuivis)",
                     suite: " dans ta cible.")
    }

    // MARK: Outils

    static func majuscule(_ texte: String) -> String {
        guard let premiere = texte.first else { return texte }
        return premiere.uppercased() + texte.dropFirst()
    }
}
