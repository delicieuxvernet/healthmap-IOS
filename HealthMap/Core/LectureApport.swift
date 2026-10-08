import Foundation

// MARK: - Lire la fiche d'un apport dans le bon ordre (maquette validée le 21 sept. 2026)
//
// Retour d'Arthur : « on ne sait pas où regarder en premier, ni quelle
// information est la plus importante, ni où trouver de quoi agir ». La fiche
// répond donc dans l'ordre des questions : le VERDICT en une phrase, CE QUI
// PÈSE le plus, CE QUE TU PEUX FAIRE dès aujourd'hui, OÙ LE TROUVER — et le
// reste replié.
//
// Ici, ce qui se calcule : tout vient du registre (`DetailApport`) et de
// `CauseApport`. Pur, testable phrase par phrase.

enum LectureApport {

    // MARK: Le verdict

    private enum Accord { case masculin, feminin, masculinPluriel, femininPluriel }

    private static func accord(_ id: String) -> Accord {
        switch id {
        case "vitD", "vitB12", "vitC": return .feminin
        case "omega3": return .masculinPluriel
        case "fiber": return .femininPluriel
        default: return .masculin
        }
    }

    /// « bas », « basse », « un peu justes », « couverte »… : le mot du statut,
    /// accordé à l'apport.
    private static func mot(_ score: Int, _ accord: Accord) -> String {
        switch (score, accord) {
        case (..<40, .masculin): return "bas"
        case (..<40, .feminin): return "basse"
        case (..<40, .masculinPluriel): return "bas"
        case (..<40, .femininPluriel): return "basses"
        case (..<70, .masculin), (..<70, .feminin): return "un peu juste"
        case (..<70, _): return "un peu justes"
        case (_, .masculin): return "couvert"
        case (_, .feminin): return "couverte"
        case (_, .masculinPluriel): return "couverts"
        case (_, .femininPluriel): return "couvertes"
        }
    }

    /// « est bas », « est basse », « sont bas », « sont basses »…
    private static func etat(_ score: Int, _ accord: Accord) -> String {
        let pluriel = accord == .masculinPluriel || accord == .femininPluriel
        return "\(pluriel ? "sont" : "est") \(mot(score, accord))"
    }

    /// Le mot du statut d'un apport (« un peu juste »), pour les widgets.
    static func motStatut(id: String, score: Int) -> String {
        mot(score, accord(id))
    }

    /// Le mot d'un STATUT d'apport estimé (audit de fiabilité, 8 oct. 2026),
    /// accordé : il ne se déduit plus d'un seuil sur le chiffre.
    static func mot(_ statut: StatutApport, id: String) -> String {
        let a = accord(id)
        switch statut {
        case .couvert, .couvertParComplement:
            switch a {
            case .masculin: return "couvert"
            case .feminin: return "couverte"
            case .masculinPluriel: return "couverts"
            case .femininPluriel: return "couvertes"
            }
        case .aSurveiller:
            return (a == .masculin || a == .feminin) ? "un peu juste" : "un peu justes"
        case .aRenforcer:
            switch a {
            case .masculin, .masculinPluriel: return "bas"
            case .feminin: return "basse"
            case .femininPluriel: return "basses"
            }
        case .peuPrecise: return "à affiner"
        case .auDessusDeLaLimite: return "au-dessus de la limite"
        case .sousLaLimite: return "sous la limite"
        }
    }

    /// Le mot du statut d'un apport, d'après son détail : le statut estimé
    /// quand il existe, l'échelle du score sinon.
    static func motStatut(id: String, detail: DetailApport) -> String {
        if let statut = detail.estimation?.statut { return mot(statut, id: id) }
        return motStatut(id: id, score: detail.score)
    }

    /// Le constat d'après le détail : « Ton apport en magnésium semble proche
    /// de la référence. » pour un apport estimé.
    static func constat(id: String, nom: String, detail: DetailApport) -> String {
        if let estimation = detail.estimation {
            return LectureEstimation.verdict(nom: nom, estimation: estimation)
        }
        return constat(id: id, nom: nom, score: detail.score)
    }

    /// « Ta vitamine D est un peu juste. » : le constat seul, sans sa cause.
    static func constat(id: String, nom: String, score: Int) -> String {
        let sujet = NomNutriment.majusculeInitiale(NomApport.possessif(NomApport.avecArticle(id: id, repli: nom)))
        return "\(sujet) \(etat(score, accord(id)))."
    }

    /// « Ton fer est bas. Première cause : règles abondantes. » — la phrase à
    /// lire en premier. Sans cause nommée, elle s'arrête au constat.
    static func verdict(id: String, nom: String, detail: DetailApport) -> String {
        // Apport estimé : la phrase de l'estimation, sans « première cause » —
        // ses contributions sont des sources, pas des freins.
        if let estimation = detail.estimation {
            return LectureEstimation.verdict(nom: nom, estimation: estimation)
        }
        let phrase = constat(id: id, nom: nom, score: detail.score)
        guard detail.score < 70 else { return phrase }
        // Une prise de sang n'est pas une cause : elle confirme le constat, et
        // la première cause reste à chercher parmi les autres freins.
        let mesure = detail.freins.first { $0.section == .priseDeSang }
        let confirmation = mesure.map { " \($0.libelle) va dans ce sens." } ?? ""
        guard let premiere = detail.freins.first(where: { $0.section != .priseDeSang }) else {
            return phrase + confirmation
        }
        return "\(phrase)\(confirmation) Première cause : \(enCoursDePhrase(premiere.libelle))."
    }

    /// Un libellé du registre, au milieu d'une phrase : la majuscule initiale
    /// tombe, sauf quand c'est celle d'un sigle (« IMC inférieur à 18,5 »).
    static func enCoursDePhrase(_ libelle: String) -> String {
        let debut = libelle.prefix(2)
        guard debut.count == 2, debut.last?.isUppercase == false else { return libelle }
        return libelle.prefix(1).lowercased() + libelle.dropFirst()
    }

    // MARK: Ce qui pèse le plus

    static let causesAffichees = 3

    struct CausePesee: Identifiable, Equatable {
        let cause: ContributionApport
        /// Sa part du frein le plus lourd (1 pour le premier) : la longueur de
        /// sa barre.
        let poids: Double
        var id: String { cause.id }
    }

    /// Les freins les plus lourds, dans l'ordre du registre.
    static func causesPrincipales(_ detail: DetailApport) -> [CausePesee] {
        let freins = Array(detail.freins.prefix(causesAffichees))
        guard let premier = freins.first, premier.delta != 0 else { return [] }
        let plusLourd = Double(abs(premier.delta))
        return freins.map { CausePesee(cause: $0, poids: Double(abs($0.delta)) / plusLourd) }
    }

    // MARK: Ce que tu peux faire

    struct Geste: Identifiable, Equatable {
        let id: String
        let texte: String
        /// Points que le calcul rendrait sans ce facteur — 0 quand l'échelle est
        /// déjà saturée par d'autres : on n'annonce alors aucun chiffre.
        let regain: Int
        /// Le facteur auquel répond ce geste.
        let cause: String
    }

    static let gestesAffiches = 3

    /// Un geste par facteur qui SE CHANGE (habitudes, assiette), le plus lourd
    /// d'abord. Deux facteurs qui appellent le même geste (« beaucoup de café »
    /// et « café pendant les repas ») n'en font qu'un : le premier.
    static func gestes(_ detail: DetailApport) -> [Geste] {
        var sortie: [Geste] = []
        for frein in detail.freins where CauseApport.seChange(frein.section) {
            // Le geste de repli (« reprends cette réponse… ») n'en est pas un.
            guard let texte = CauseApport.explication(pour: frein).geste,
                  texte != CauseApport.gesteDeRepli,
                  !sortie.contains(where: { $0.texte == texte }) else { continue }
            sortie.append(Geste(id: frein.id, texte: texte,
                                regain: max(0, detail.scoreSans(frein) - detail.score),
                                cause: frein.libelle))
            if sortie.count == gestesAffiches { break }
        }
        return sortie
    }

    /// « jusqu'à +12 points » ; rien quand il n'y a pas de point à annoncer.
    static func libelleRegain(_ regain: Int) -> String? {
        regain > 0 ? "jusqu'à +\(regain) point\(regain > 1 ? "s" : "")" : nil
    }
}
