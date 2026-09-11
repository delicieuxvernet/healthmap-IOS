import Foundation

// MARK: - Brief du jour (première ouverture de la journée)
//
// Ce que l'app dit en premier chaque jour : où l'on en était hier, ce qui a
// manqué, l'effort qui paie, et sur quoi miser aujourd'hui (demande d'Arthur
// du 11 sept. 2026, maquette validée).
//
// 100 % déterministe, calculé sur le téléphone. Aucun appel à l'IA et AUCUN
// chiffre inventé : chaque pourcentage affiché vient des repas réellement
// notés (Σ pctRDA du jour, plafonnée à 100 — même règle que `WeekScoreEngine`).
// Les idées de repas et le conseil viennent du bilan de l'utilisateur, déjà
// rédigé et affiché ailleurs dans l'app. Les libellés de nutriments viennent
// TOUJOURS de `NutrientData` (règle projet : jamais de l'IA).

/// Un apport du bilan réduit à ce dont le brief et les rappels ont besoin.
/// `Codable` : les rappels le mémorisent pour se replanifier sans le bilan.
struct CibleNutritionnelle: Codable, Equatable {
    /// Id canonique du nutriment (ex. « iron »).
    let id: String
    /// Libellé canonique (`NutrientData`), ex. « Fer ».
    let nom: String
    /// Jusqu'à 3 idées d'aliments, tirées du bilan.
    let aliments: [String]
    /// Conseil court du bilan (`tipBold`), s'il existe.
    let conseil: String?

    /// « ton fer », « ta vitamine C », « tes oméga-3 ».
    var avecPossessif: String { NomNutriment.possessif(id: id, nom: nom) }
}

// MARK: - Grammaire des noms de nutriments

enum NomNutriment {
    /// Le nom avec le bon possessif. Les notifications et le brief parlent à
    /// la personne (« renforcer ton fer ») : « renforcer le Fer » sonne comme
    /// une notice.
    static func possessif(id: String, nom: String) -> String {
        let bas = minusculeInitiale(nom)
        switch id {
        case "vitD", "vitB12", "vitC": return "ta \(bas)"
        case "omega3", "fiber": return "tes \(bas)"
        case "iron", "magnesium", "calcium", "zinc", "iodine": return "ton \(bas)"
        default: return "ton apport en \(bas)"
        }
    }

    /// « de ton fer », « de ta vitamine D », « de tes fibres ».
    static func complement(id: String, nom: String) -> String {
        "de \(possessif(id: id, nom: nom))"
    }

    /// Première lettre en minuscule, le reste intact : « Vitamine D » →
    /// « vitamine D » (pas « vitamine d »).
    static func minusculeInitiale(_ texte: String) -> String {
        guard let premiere = texte.first else { return texte }
        return premiere.lowercased() + texte.dropFirst()
    }

    /// Première lettre en majuscule : « ton fer » → « Ton fer ».
    static func majusculeInitiale(_ texte: String) -> String {
        guard let premiere = texte.first else { return texte }
        return premiere.uppercased() + texte.dropFirst()
    }

    /// « Lentilles, boudin ou épinards » — la liste telle qu'on la dit.
    static func enumeration(_ elements: [String]) -> String {
        let propres = elements
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        switch propres.count {
        case 0: return ""
        case 1: return majusculeInitiale(propres[0])
        default:
            let tete = propres.dropLast().enumerated().map { index, element in
                index == 0 ? majusculeInitiale(element) : minusculeInitiale(element)
            }
            return tete.joined(separator: ", ") + " ou " + minusculeInitiale(propres.last!)
        }
    }
}

// MARK: - Le brief

struct BriefDuJour: Equatable {
    /// Un apport tel qu'il s'est passé hier.
    struct Manque: Equatable {
        let id: String
        let nom: String
        /// Part du besoin COUVERTE hier (0-100). Ce qui a manqué = 100 − pourcent.
        let pourcent: Int
    }

    /// L'apport qui a le plus progressé cette semaine.
    struct Effort: Equatable {
        let id: String
        let nom: String
        /// Points de couverture moyenne gagnés vs la semaine précédente.
        let points: Int
    }

    let prenom: String?
    /// Repas notés hier.
    let repasHier: Int
    /// Besoins (sur 10) couverts hier à au moins 70 %. `nil` = trop peu noté
    /// hier pour que le chiffre veuille dire quelque chose.
    let besoinsCouvertsHier: Int?
    let besoinsCouvertsAvantHier: Int?
    /// Apports du bilan, du plus bas au plus haut hier (3 au plus). Vide si
    /// hier est trop peu noté.
    let manquesHier: [Manque]
    let effort: Effort?
    /// L'apport sur lequel miser aujourd'hui.
    let cible: CibleNutritionnelle?

    var hierAssezNote: Bool { besoinsCouvertsHier != nil }
}

enum BriefDuJourBuilder {

    /// Un besoin compte comme couvert au-delà de 70 % : c'est le repère
    /// « visé » affiché partout ailleurs dans l'app.
    static let seuilCouvert = 70
    /// En dessous de 2 repas notés, « 2 besoins sur 10 » décrirait la saisie,
    /// pas l'alimentation : on propose alors de compléter la journée.
    static let repasMinimum = 2
    /// Un progrès de moins de 5 points est du bruit.
    static let effortMinimum = 5

    // MARK: Cibles

    /// Les apports à travailler, dans l'ordre du bilan (« à combler » avant
    /// « à renforcer »). Libellés toujours canoniques ; un id inconnu est écarté.
    static func cibles(depuis apports: [ApportV2]) -> [CibleNutritionnelle] {
        let aTravailler = apports.filter { $0.statut == .aCombler || $0.statut == .aRenforcer }
        let ordonnes = aTravailler.enumerated().sorted { a, b in
            let rangA = a.element.statut == .aCombler ? 0 : 1
            let rangB = b.element.statut == .aCombler ? 0 : 1
            if rangA != rangB { return rangA < rangB }
            let pctA = a.element.pctBesoin ?? 100
            let pctB = b.element.pctBesoin ?? 100
            if pctA != pctB { return pctA < pctB }
            return a.offset < b.offset
        }
        var vus = Set<String>()
        return ordonnes.compactMap { _, apport in
            guard let id = apport.id,
                  let definition = NutrientData.definition(for: id),
                  !vus.contains(id) else { return nil }
            vus.insert(id)
            let aliments = (apport.aliments ?? [])
                .compactMap { $0.nom?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let conseil = apport.tipBold?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CibleNutritionnelle(
                id: id,
                nom: definition.label,
                aliments: Array(aliments.prefix(3)),
                conseil: (conseil?.isEmpty ?? true) ? nil : conseil
            )
        }
    }

    // MARK: Couverture d'un jour

    /// Part du besoin couverte ce jour-là, par nutriment : Σ pctRDA des repas
    /// du jour, plafonnée à 100 (même formule que le score de la semaine).
    static func couverture(
        jour: Date,
        repas: [MealJournalService.MealRecord],
        calendar: Calendar = .current
    ) -> [String: Int] {
        var somme: [String: Int] = [:]
        for record in repas where calendar.isDate(record.consumedAt, inSameDayAs: jour) {
            for micro in record.micros {
                somme[micro.id, default: 0] += micro.pctRDA
            }
        }
        return somme.mapValues { min(100, max(0, $0)) }
    }

    static func besoinsCouverts(_ couverture: [String: Int]) -> Int {
        NutrientData.all.filter { (couverture[$0.id.rawValue] ?? 0) >= seuilCouvert }.count
    }

    // MARK: Construction

    static func construire(
        prenom: String?,
        apports: [ApportV2],
        repas: [MealJournalService.MealRecord],
        maintenant: Date = Date(),
        calendar: Calendar = .current
    ) -> BriefDuJour {
        let aujourdhui = calendar.startOfDay(for: maintenant)
        let hier = calendar.date(byAdding: .day, value: -1, to: aujourdhui) ?? aujourdhui
        let avantHier = calendar.date(byAdding: .day, value: -2, to: aujourdhui) ?? aujourdhui

        let repasHier = repas.filter { calendar.isDate($0.consumedAt, inSameDayAs: hier) }.count
        let repasAvantHier = repas.filter { calendar.isDate($0.consumedAt, inSameDayAs: avantHier) }.count
        let couvertureHier = couverture(jour: hier, repas: repas, calendar: calendar)
        let couvertureAvantHier = couverture(jour: avantHier, repas: repas, calendar: calendar)

        let hierAssezNote = repasHier >= repasMinimum
        let toutesLesCibles = cibles(depuis: apports)

        let manques: [BriefDuJour.Manque] = hierAssezNote
            ? toutesLesCibles
                .map { BriefDuJour.Manque(id: $0.id, nom: $0.nom, pourcent: couvertureHier[$0.id] ?? 0) }
                .sorted { $0.pourcent < $1.pourcent }
                .prefix(3)
                .map { $0 }
            : []

        // La cible du jour : l'apport du bilan le plus bas HIER ; sans données
        // exploitables d'hier, la priorité du bilan.
        let cible: CibleNutritionnelle? = {
            if let plusBas = manques.first,
               let trouvee = toutesLesCibles.first(where: { $0.id == plusBas.id }) {
                return trouvee
            }
            return toutesLesCibles.first
        }()

        // L'effort qui paie : l'apport à travailler qui a le plus progressé
        // d'une semaine sur l'autre — seulement s'il a VRAIMENT progressé.
        let semaine = WeekScoreEngine.compute(
            meals: repas,
            weakNutrients: toutesLesCibles.map(\.id),
            now: maintenant
        )
        let effort: BriefDuJour.Effort? = {
            guard let mover = semaine.topMover,
                  mover.delta >= effortMinimum,
                  let definition = NutrientData.definition(for: mover.id) else { return nil }
            return BriefDuJour.Effort(id: mover.id, nom: definition.label, points: mover.delta)
        }()

        let prenomPropre = prenom?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BriefDuJour(
            prenom: (prenomPropre?.isEmpty ?? true) ? nil : prenomPropre,
            repasHier: repasHier,
            besoinsCouvertsHier: hierAssezNote ? besoinsCouverts(couvertureHier) : nil,
            besoinsCouvertsAvantHier: repasAvantHier >= repasMinimum ? besoinsCouverts(couvertureAvantHier) : nil,
            manquesHier: manques,
            effort: effort,
            cible: cible
        )
    }

    // MARK: Séquence

    /// Les écrans du brief, dans l'ordre. Moins de deux écrans = rien à dire :
    /// l'appelant ne présente alors pas le brief.
    static func slides(brief: BriefDuJour, proposerInvitation: Bool) -> [BriefSlide] {
        var slides: [BriefSlide] = [.intro(prenom: brief.prenom)]
        if let couverts = brief.besoinsCouvertsHier {
            slides.append(.hier(couverts: couverts, avantHier: brief.besoinsCouvertsAvantHier))
            if !brief.manquesHier.isEmpty {
                slides.append(.manques(brief.manquesHier))
            }
        } else {
            slides.append(.rienHier(repas: brief.repasHier))
        }
        if let effort = brief.effort {
            slides.append(.effort(effort))
        }
        if let cible = brief.cible {
            slides.append(.cible(cible))
        }
        if proposerInvitation {
            slides.append(.invitation(cible: brief.cible))
        }
        return slides
    }
}

// MARK: - Écrans du brief

enum BriefSlide: Equatable, Identifiable {
    case intro(prenom: String?)
    case hier(couverts: Int, avantHier: Int?)
    /// Hier trop peu noté : on propose d'ajouter les repas de la veille.
    case rienHier(repas: Int)
    case manques([BriefDuJour.Manque])
    case effort(BriefDuJour.Effort)
    case cible(CibleNutritionnelle)
    /// Invitation aux notifications, avant l'alerte d'iOS.
    case invitation(cible: CibleNutritionnelle?)

    var id: String {
        switch self {
        case .intro: return "intro"
        case .hier: return "hier"
        case .rienHier: return "rien-hier"
        case .manques: return "manques"
        case .effort: return "effort"
        case .cible: return "cible"
        case .invitation: return "invitation"
        }
    }

    /// Nom stable pour l'analytics.
    var typeName: String { id }
}

// MARK: - Mémoire du brief

/// Clés préfixées `healthmap_` : `AuthViewModel.clearLocalCaches()` les efface
/// au changement de compte — le brief et l'invitation repartent de zéro pour
/// l'utilisateur suivant.
enum BriefDuJourStore {
    static let cleDernierJour = "healthmap_brief_dernier_jour"
    static let cleInvitationRepoussee = "healthmap_invitation_notifs_repoussee"
    /// Après « Plus tard », on ne repropose pas avant 3 jours.
    static let delaiInvitation: TimeInterval = 3 * 24 * 60 * 60

    static func dejaVuAujourdhui(
        maintenant: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let dernier = defaults.object(forKey: cleDernierJour) as? Date else { return false }
        return calendar.isDate(dernier, inSameDayAs: maintenant)
    }

    static func marquerVu(maintenant: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(maintenant, forKey: cleDernierJour)
    }

    static func invitationAProposer(maintenant: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard let repoussee = defaults.object(forKey: cleInvitationRepoussee) as? Date else { return true }
        return maintenant.timeIntervalSince(repoussee) >= delaiInvitation
    }

    static func repousserInvitation(maintenant: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(maintenant, forKey: cleInvitationRepoussee)
    }
}
