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
//
// 7 oct. 2026 : le brief devient le « Récap du jour », un seul écran sans
// tap (aliments notés hier · deux apports manquants avec chacun un aliment à
// ajouter · une accroche). Voir `priorites` et `accroche` plus bas, et la
// section 9 de DESIGN-PAGES.md.

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
    /// Les habitudes alimentaires DÉCLARÉES qui pèsent sur cet apport, de la
    /// plus lourde à la plus légère (`BriefDuJourBuilder.enrichir`). `nil` =
    /// cibles mémorisées avant le 1er oct. 2026, ou registre pas encore lu.
    var freins: [FreinCible]? = nil

    /// « ton fer », « ta vitamine C », « tes oméga-3 ».
    var avecPossessif: String { NomNutriment.possessif(id: id, nom: nom) }

    /// L'emoji canonique de l'apport (`NutrientData`, jamais l'IA). Vide pour
    /// un id hors catalogue.
    var emoji: String { NutrientData.definition(for: id)?.emoji ?? "" }

    /// Les aliments à dire : ceux du bilan (personnalisés) ou, à défaut, le
    /// repli écrit à la main. Un apport connu n'est JAMAIS sans idée de repas —
    /// c'est le plancher de qualité (19 sept. 2026).
    var alimentsAffichables: [String] {
        SourcesAlimentaires.pour(id: id, duBilan: aliments)
    }
}

/// Une ligne du registre des apports (`NutrientLedger`) réduite à ce qu'une
/// notification peut en dire : l'habitude, et ce qu'elle coûte.
struct FreinCible: Codable, Equatable {
    /// Libellé du registre, tel que la fiche de l'apport l'affiche
    /// (« Café ou thé pendant les repas »).
    let libelle: String
    /// Points d'apport perdus — toujours positif.
    let points: Int
}

// MARK: - Grammaire des noms de nutriments

enum NomNutriment {
    /// « tes oméga-3 », « tes fibres » : le verbe qui suit s'accorde.
    static func estPluriel(id: String) -> Bool {
        id == "omega3" || id == "fiber"
    }

    /// Le verbe accordé avec l'apport : « ton fer est », « tes fibres sont ».
    static func accord(id: String, singulier: String, pluriel: String) -> String {
        estPluriel(id: id) ? pluriel : singulier
    }

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

    // MARK: Récap du jour (refonte du 7 oct. 2026)

    /// Ce qui a été noté hier, aliment par aliment, dans l'ordre des repas et
    /// sans doublon. Vide si rien n'a été noté (ou cache d'avant la refonte).
    var alimentsHier: [String] = []
    /// Les deux apports à remonter aujourd'hui, chacun avec L'aliment à
    /// ajouter. Vide = rien n'a manqué (tout au-dessus de 70 %).
    var priorites: [Priorite] = []
    /// La phrase qui donne envie de revenir demain.
    var accroche: Accroche? = nil

    var hierAssezNote: Bool { besoinsCouvertsHier != nil }

    /// Un apport qui a manqué, et l'aliment qui le remonte.
    struct Priorite: Equatable {
        /// D'où vient le constat : il se dit différemment selon la période.
        enum Periode: String, Equatable {
            /// Hier assez noté (2 repas ou plus).
            case hier
            /// Hier trop peu noté : moyenne des derniers jours bien notés.
            case joursPrecedents
            /// Aucun jour exploitable : la priorité du bilan, sans chiffre.
            case bilan
        }

        let id: String
        /// Libellé canonique (`NutrientData`), ex. « Vitamine D ».
        let nom: String
        /// Part du besoin couverte sur la période (0-100). `nil` en mode
        /// `.bilan` : aucun repas ne permet de chiffrer, on n'invente rien.
        let pourcent: Int?
        let periode: Periode
        /// L'aliment à ajouter aujourd'hui (« Lentilles »).
        let aliment: String

        var emoji: String { NutrientData.definition(for: id)?.emoji ?? "" }
    }

    /// Le bas du récap : un chiffre héros (facultatif) et une phrase. Chaque
    /// chiffre est tiré des repas notés ou d'une étude publique citée, jamais
    /// inventé.
    struct Accroche: Equatable {
        enum Genre: String, Equatable {
            /// Moins de 3 jours notés sur 7 : le compte à rebours avant que
            /// Progrès ne compare les apports (`ProgresVerdict`).
            case apportsBientot
            /// Un apport à travailler a gagné des points cette semaine.
            case effort
            /// Plusieurs jours notés d'affilée.
            case serie
            /// Une stat France sourcée (`TeaserStatsCatalog`).
            case stat
            /// Rien de chiffré à dire : une phrase écrite à la main.
            case phrase
        }

        let genre: Genre
        /// Le chiffre héros, déjà écrit (« 2 », « +12 », « 9 sur 10 »).
        let chiffre: String?
        /// Collée au chiffre (« jours », « points »).
        let unite: String?
        /// La suite de la phrase, sous le chiffre.
        let texte: String
        /// Au-dessus du chiffre (« Plus que »).
        var prefixe: String? = nil
        /// Source publique, affichée en petit.
        var source: String? = nil

        /// La phrase entière, telle que VoiceOver la lit.
        var phrase: String {
            [prefixe, chiffre, unite, texte]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }
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

    // MARK: Freins déclarés (pour les rappels)

    /// Sous ce poids, un frein ne mérite pas une notification — même seuil
    /// que l'effort de la semaine : moins de 5 points, c'est du bruit.
    static let freinMinimum = 5
    /// Deux freins par apport suffisent : les rappels alternent entre eux.
    static let freinsParCible = 2

    /// Accroche à chaque cible ce que le registre sait de ce qui la freine.
    ///
    /// SEULES les habitudes ALIMENTAIRES passent (section « Nutrition » du
    /// questionnaire : « Pas de poisson gras », « Café ou thé pendant les
    /// repas »…). Un traitement, l'âge, le tabac ou un IMC n'ont rien à faire
    /// sur un écran verrouillé, que n'importe qui peut lire par-dessus
    /// l'épaule.
    static func enrichir(
        _ cibles: [CibleNutritionnelle],
        registre: [String: DetailApport]
    ) -> [CibleNutritionnelle] {
        cibles.map { cible in
            var enrichie = cible
            enrichie.freins = (registre[cible.id]?.freins ?? [])
                .filter { $0.section == .nutrition && abs($0.delta) >= freinMinimum }
                .prefix(freinsParCible)
                .map { FreinCible(libelle: $0.libelle, points: abs($0.delta)) }
            return enrichie
        }
    }

    // MARK: Effort de la semaine

    /// L'apport à travailler qui a le plus progressé d'une semaine sur
    /// l'autre — seulement s'il a VRAIMENT progressé. Le brief et le rappel du
    /// dimanche lisent ce même calcul : ils ne peuvent pas se contredire.
    static func effort(
        cibles: [CibleNutritionnelle],
        repas: [MealJournalService.MealRecord],
        maintenant: Date = Date()
    ) -> BriefDuJour.Effort? {
        let semaine = WeekScoreEngine.compute(
            meals: repas,
            weakNutrients: cibles.map(\.id),
            now: maintenant
        )
        guard let mover = semaine.topMover,
              mover.delta >= effortMinimum,
              let definition = NutrientData.definition(for: mover.id) else { return nil }
        return BriefDuJour.Effort(id: mover.id, nom: definition.label, points: mover.delta)
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

    /// Depuis le bilan fraîchement chargé.
    static func construire(
        prenom: String?,
        apports: [ApportV2],
        repas: [MealJournalService.MealRecord],
        maintenant: Date = Date(),
        calendar: Calendar = .current
    ) -> BriefDuJour {
        construire(prenom: prenom, cibles: cibles(depuis: apports), repas: repas,
                   maintenant: maintenant, calendar: calendar)
    }

    /// Le brief SANS réseau, depuis ce que le téléphone a gardé de la dernière
    /// session (repas de la quinzaine, cibles du bilan, prénom). `nil` = pas
    /// assez de matière — première ouverture après la mise à jour — et
    /// l'appelant repasse alors par le réseau.
    static func depuisLeCache(
        maintenant: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> BriefDuJour? {
        let cibles = RappelsPersonnalises.ciblesMemorisees(defaults: defaults)
        guard !cibles.isEmpty else { return nil }
        let repas = BriefDuJourStore.repasMemorises(maintenant: maintenant, defaults: defaults)
        guard !repas.isEmpty else { return nil }
        return construire(
            prenom: BriefDuJourStore.prenomMemorise(defaults: defaults),
            cibles: cibles,
            repas: repas,
            maintenant: maintenant,
            calendar: calendar
        )
    }

    static func construire(
        prenom: String?,
        cibles toutesLesCibles: [CibleNutritionnelle],
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
        let effortDeLaSemaine = Self.effort(cibles: toutesLesCibles, repas: repas, maintenant: maintenant)

        let mangesHier = alimentsNotes(jour: hier, repas: repas, calendar: calendar)
        let lesPriorites = priorites(
            cibles: toutesLesCibles,
            repas: repas,
            aujourdhui: aujourdhui,
            mangesHier: mangesHier,
            calendar: calendar
        )

        let prenomPropre = prenom?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BriefDuJour(
            prenom: (prenomPropre?.isEmpty ?? true) ? nil : prenomPropre,
            repasHier: repasHier,
            besoinsCouvertsHier: hierAssezNote ? besoinsCouverts(couvertureHier) : nil,
            besoinsCouvertsAvantHier: repasAvantHier >= repasMinimum ? besoinsCouverts(couvertureAvantHier) : nil,
            manquesHier: manques,
            effort: effortDeLaSemaine,
            cible: cible,
            alimentsHier: mangesHier,
            priorites: lesPriorites,
            accroche: accroche(
                repas: repas,
                aujourdhui: aujourdhui,
                effort: effortDeLaSemaine,
                priorites: lesPriorites,
                calendar: calendar
            )
        )
    }

    // MARK: - Récap du jour (refonte du 7 oct. 2026)
    //
    // Demande d'Arthur : « on rentre dans le vif du sujet ». Le récap dit, en
    // un seul écran, ce qui a été noté hier, les DEUX apports qui ont le plus
    // manqué et, pour chacun, UN aliment à ajouter aujourd'hui, puis une
    // raison de revenir demain. Même doctrine que le reste du brief : chaque
    // chiffre vient des repas notés, aucun n'est inventé.

    /// Deux apports, pas plus : au-delà, on relit une liste au lieu d'agir.
    static let prioritesMax = 2
    /// Fenêtre des « jours précédents » quand hier est trop peu noté.
    static let joursPrecedentsMax = 7
    /// Jours notés sur sept à partir desquels Progrès compare les apports
    /// (`ProgresVerdict.joursMinimumPourComparer`, qu'on recopie ici pour
    /// garder ce moteur pur et testable sans les services).
    static let joursPourComparer = 3
    /// Une série commence à se dire à partir de deux jours.
    static let serieMinimum = 2

    /// Les aliments notés ce jour-là, dans l'ordre des repas, sans doublon
    /// (« Pâtes » et « pâtes » sont le même aliment).
    static func alimentsNotes(
        jour: Date,
        repas: [MealJournalService.MealRecord],
        calendar: Calendar = .current
    ) -> [String] {
        var vus = Set<String>()
        var aliments: [String] = []
        let duJour = repas
            .filter { calendar.isDate($0.consumedAt, inSameDayAs: jour) }
            .sorted { $0.consumedAt < $1.consumedAt }
        for record in duJour {
            for nom in record.foods {
                let propre = nom.trimmingCharacters(in: .whitespacesAndNewlines)
                let clef = Self.cle(propre)
                guard !propre.isEmpty, !vus.contains(clef) else { continue }
                vus.insert(clef)
                aliments.append(NomNutriment.majusculeInitiale(propre))
            }
        }
        return aliments
    }

    /// Les deux apports à remonter aujourd'hui, du plus bas au moins bas.
    ///
    /// · Hier assez noté → la couverture d'hier.
    /// · Sinon, les derniers jours bien notés (2 repas ou plus, 7 jours au
    ///   plus) → la couverture moyenne de ces jours.
    /// · Sinon → les priorités du bilan, sans chiffre.
    ///
    /// Les apports du bilan passent d'abord : ce sont ceux que le profil
    /// expose. Un apport mesuré à 70 % ou plus n'a pas « manqué » et n'est
    /// jamais cité ; si les cibles ne suffisent pas à remplir deux places,
    /// l'apport le plus bas parmi les dix complète.
    static func priorites(
        cibles: [CibleNutritionnelle],
        repas: [MealJournalService.MealRecord],
        aujourdhui: Date,
        mangesHier: [String] = [],
        calendar: Calendar = .current
    ) -> [BriefDuJour.Priorite] {
        let debut = calendar.startOfDay(for: aujourdhui)
        let hier = calendar.date(byAdding: .day, value: -1, to: debut) ?? debut

        // 1) La période mesurée, s'il y en a une.
        var mesure: [String: Int]?
        var periode: BriefDuJour.Priorite.Periode = .bilan
        let repasHier = repas.filter { calendar.isDate($0.consumedAt, inSameDayAs: hier) }.count
        if repasHier >= Self.repasMinimum {
            mesure = Self.couverture(jour: hier, repas: repas, calendar: calendar)
            periode = .hier
        } else {
            var jours: [Date] = []
            for ecart in 1...Self.joursPrecedentsMax {
                guard let jour = calendar.date(byAdding: .day, value: -ecart, to: debut) else { continue }
                let n = repas.filter { calendar.isDate($0.consumedAt, inSameDayAs: jour) }.count
                if n >= Self.repasMinimum { jours.append(jour) }
            }
            if !jours.isEmpty {
                var somme: [String: Int] = [:]
                for jour in jours {
                    for (id, pct) in Self.couverture(jour: jour, repas: repas, calendar: calendar) {
                        somme[id, default: 0] += pct
                    }
                }
                let nombre = Double(jours.count)
                mesure = somme.mapValues { Int((Double($0) / nombre).rounded()) }
                periode = .joursPrecedents
            }
        }

        // 2) Les candidats, du plus bas au moins bas.
        var candidats: [CandidatPriorite] = []
        if let mesure {
            var duBilan: [CandidatPriorite] = []
            for (rang, cible) in cibles.enumerated() {
                let pct = mesure[cible.id] ?? 0
                guard pct < Self.seuilCouvert else { continue }
                duBilan.append(CandidatPriorite(id: cible.id, nom: cible.nom, pourcent: pct,
                                                rang: rang, aliments: cible.alimentsAffichables))
            }
            candidats = duBilan.sorted(by: CandidatPriorite.avant)
            if candidats.count < Self.prioritesMax {
                let dejaLa = Set(candidats.map(\.id))
                var autres: [CandidatPriorite] = []
                for (rang, definition) in NutrientData.all.enumerated() {
                    let id = definition.id.rawValue
                    let pct = mesure[id] ?? 0
                    guard !dejaLa.contains(id), pct < Self.seuilCouvert else { continue }
                    autres.append(CandidatPriorite(id: id, nom: definition.label, pourcent: pct,
                                                   rang: rang, aliments: SourcesAlimentaires.pour(id: id, duBilan: [])))
                }
                candidats += autres.sorted(by: CandidatPriorite.avant)
            }
        } else {
            for (rang, cible) in cibles.enumerated() {
                candidats.append(CandidatPriorite(id: cible.id, nom: cible.nom, pourcent: nil,
                                                  rang: rang, aliments: cible.alimentsAffichables))
            }
        }

        // 3) Un aliment par apport : le premier de la liste (le bilan les
        //    classe, le repli aussi), sauf s'il a déjà été mangé hier ou
        //    proposé pour l'autre apport. Deux fois « Amandes », ce serait une
        //    seule idée.
        var proposes: [String] = []
        var resultat: [BriefDuJour.Priorite] = []
        for candidat in candidats where resultat.count < prioritesMax {
            let pistes = candidat.aliments + SourcesAlimentaires.pour(id: candidat.id, duBilan: [])
            guard let aliment = Self.choisirAliment(parmi: pistes, mangesHier: mangesHier, dejaProposes: proposes) else { continue }
            proposes.append(aliment)
            resultat.append(BriefDuJour.Priorite(
                id: candidat.id,
                nom: candidat.nom,
                pourcent: candidat.pourcent,
                periode: periode,
                aliment: aliment
            ))
        }
        return resultat
    }

    /// Un apport candidat au récap, avant le choix de son aliment.
    struct CandidatPriorite {
        let id: String
        let nom: String
        let pourcent: Int?
        /// Rang d'origine (ordre du bilan) : départage deux apports au même
        /// pourcentage.
        let rang: Int
        let aliments: [String]

        static func avant(_ a: CandidatPriorite, _ b: CandidatPriorite) -> Bool {
            let pa = a.pourcent ?? 100
            let pb = b.pourcent ?? 100
            return pa != pb ? pa < pb : a.rang < b.rang
        }
    }

    /// Le premier aliment ni mangé hier ni déjà proposé ; à défaut, le premier
    /// pas encore proposé ; `nil` seulement si la liste est vide.
    static func choisirAliment(
        parmi pistes: [String],
        mangesHier: [String],
        dejaProposes: [String]
    ) -> String? {
        let propres = pistes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let manges = mangesHier.map { Self.cle($0) }
        let proposes = Set(dejaProposes.map { Self.cle($0) })
        let pasProposes = propres.filter { !proposes.contains(Self.cle($0)) }
        let neufs = pasProposes.filter { piste in
            let c = Self.cle(piste)
            // « Lentilles » est mangé si « Salade de lentilles » l'a été.
            return !manges.contains { $0.contains(c) || c.contains($0) }
        }
        return (neufs.first ?? pasProposes.first ?? propres.first).map(NomNutriment.majusculeInitiale)
    }

    /// Clé de comparaison d'un nom d'aliment : sans casse ni accents.
    static func cle(_ texte: String) -> String {
        texte
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    /// Jours des sept derniers (aujourd'hui compris) où au moins un repas a
    /// été noté : le même compte que l'onglet Progrès.
    static func joursNotes(
        repas: [MealJournalService.MealRecord],
        aujourdhui: Date,
        calendar: Calendar = .current
    ) -> Int {
        let debut = calendar.startOfDay(for: aujourdhui)
        return (0..<7).filter { ecart in
            guard let jour = calendar.date(byAdding: .day, value: -ecart, to: debut) else { return false }
            return repas.contains { calendar.isDate($0.consumedAt, inSameDayAs: jour) }
        }.count
    }

    /// Jours notés d'affilée jusqu'à hier (aujourd'hui ne compte pas encore :
    /// le récap s'ouvre le matin, avant le premier repas).
    static func serie(
        repas: [MealJournalService.MealRecord],
        aujourdhui: Date,
        calendar: Calendar = .current
    ) -> Int {
        let debut = calendar.startOfDay(for: aujourdhui)
        var jours = 0
        while let jour = calendar.date(byAdding: .day, value: -(jours + 1), to: debut),
              repas.contains(where: { calendar.isDate($0.consumedAt, inSameDayAs: jour) }) {
            jours += 1
        }
        return jours
    }

    /// Phrases sans chiffre, quand il n'y a rien de mesuré à dire. Elles
    /// tournent avec le jour : une semaine de récaps n'est pas sept fois la
    /// même phrase.
    static let phrasesDeMotivation: [String] = [
        "Pas besoin d'une journée parfaite : un bon choix par repas suffit.",
        "Tes apports se construisent repas après repas. Le prochain compte.",
        "Chaque repas noté rend ton suivi plus juste. On s'y remet ?",
    ]

    /// Ce qu'on dit en bas du récap, dans l'ordre de ce qui pousse le plus :
    /// un compte à rebours réel, un progrès réel, une série réelle, une stat
    /// publique sourcée, et seulement ensuite une phrase.
    static func accroche(
        repas: [MealJournalService.MealRecord],
        aujourdhui: Date,
        effort: BriefDuJour.Effort?,
        priorites: [BriefDuJour.Priorite],
        calendar: Calendar = .current
    ) -> BriefDuJour.Accroche {
        let notes = joursNotes(repas: repas, aujourdhui: aujourdhui, calendar: calendar)
        if notes < joursPourComparer {
            let reste = joursPourComparer - notes
            return BriefDuJour.Accroche(
                genre: .apportsBientot,
                chiffre: "\(reste)",
                unite: reste > 1 ? "jours" : "jour",
                texte: "de repas notés avant de voir tes apports évoluer dans Progrès.",
                prefixe: "Plus que"
            )
        }
        if let effort {
            return BriefDuJour.Accroche(
                genre: .effort,
                chiffre: "+\(effort.points)",
                unite: "points",
                texte: "pour \(NomNutriment.possessif(id: effort.id, nom: effort.nom)) cette semaine, par rapport à la précédente. Garde le rythme."
            )
        }
        let enSerie = serie(repas: repas, aujourdhui: aujourdhui, calendar: calendar)
        if enSerie >= serieMinimum {
            return BriefDuJour.Accroche(
                genre: .serie,
                chiffre: "\(enSerie)",
                unite: "jours d'affilée",
                texte: "à noter tes repas. Ne casse pas la série aujourd'hui."
            )
        }
        if let premiere = priorites.first {
            let stat = TeaserStatsCatalog.stat(for: premiere.id)
            if let fraction = stat.fraction {
                return BriefDuJour.Accroche(
                    genre: .stat,
                    chiffre: fraction,
                    unite: nil,
                    texte: "\(stat.texte) en \(NomNutriment.minusculeInitiale(premiere.nom)), en France. Toi, tu t'en occupes déjà.",
                    source: stat.source
                )
            }
        }
        let jour = calendar.ordinality(of: .day, in: .era, for: aujourdhui) ?? 0
        let phrase = phrasesDeMotivation[FormulationsRappel.indexVariante(jour: jour, parmi: phrasesDeMotivation.count)]
        return BriefDuJour.Accroche(genre: .phrase, chiffre: nil, unite: nil, texte: phrase)
    }

    // MARK: Présentation

    /// Le récap a-t-il de quoi parler ? Un aliment noté hier, un apport à
    /// remonter, ou des repas à rattraper : sinon, on ne l'ouvre pas.
    static func aDeQuoiParler(_ brief: BriefDuJour) -> Bool {
        !brief.priorites.isEmpty || !brief.alimentsHier.isEmpty || brief.repasHier < repasMinimum
    }
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

    // MARK: - Ingrédients gardés sur le téléphone (brief instantané)
    //
    // Retour d'Arthur du 19 sept. : le brief arrivait « au bout d'une minute ».
    // Il attendait trois allers-retours réseau en série (profil, bilan, repas).
    // On garde donc les DEUX ingrédients dont il a besoin — les repas de la
    // quinzaine et le prénom — à chaque fois que le journal les charge de
    // toute façon. Au lancement suivant, le brief se calcule sans réseau.
    //
    // Ce sont les repas qu'on garde, pas le brief tout fait : le passage à un
    // nouveau jour change « hier » sans rien changer aux repas, et un brief
    // mémorisé serait périmé le lendemain matin sans qu'on puisse le savoir.

    static let cleRepas = "healthmap_brief_repas"
    static let clePrenom = "healthmap_brief_prenom"
    static let cleStatutNotifs = "healthmap_brief_statut_notifs"
    /// Au-delà, les repas gardés ne décrivent plus « hier » : on repasse par
    /// le réseau plutôt que d'afficher des chiffres d'avant-hier.
    static let fraicheurRepas: TimeInterval = 3 * 24 * 60 * 60

    /// Un repas réduit à ce que le brief lit : le jour, les apports et,
    /// depuis le récap du 7 oct. 2026, le nom des aliments (« hier, tu as
    /// noté… »). `nil` pour un cache écrit avant : le récap s'en passe.
    struct RepasMemorise: Codable, Equatable {
        let jour: Date
        let micros: [String: Int]
        var aliments: [String]? = nil
    }

    static func memoriserRepas(
        _ repas: [MealJournalService.MealRecord],
        maintenant: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        let compact = repas.map { record in
            RepasMemorise(
                jour: record.consumedAt,
                micros: Dictionary(record.micros.map { ($0.id, $0.pctRDA) }, uniquingKeysWith: +),
                aliments: record.foods
            )
        }
        guard let data = try? JSONEncoder().encode(compact) else { return }
        defaults.set(data, forKey: cleRepas)
        defaults.set(maintenant, forKey: cleRepas + "_date")
    }

    /// Les repas gardés, reconstruits pour le moteur du brief. Vide si rien
    /// n'a été gardé, ou si c'est trop vieux pour parler d'hier.
    static func repasMemorises(
        maintenant: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> [MealJournalService.MealRecord] {
        guard let ecritLe = defaults.object(forKey: cleRepas + "_date") as? Date,
              maintenant.timeIntervalSince(ecritLe) < fraicheurRepas,
              let data = defaults.data(forKey: cleRepas),
              let compact = try? JSONDecoder().decode([RepasMemorise].self, from: data) else { return [] }
        return compact.map { memo in
            MealJournalService.MealRecord(
                id: UUID().uuidString,
                consumedAt: memo.jour,
                slot: MealJournalService.MealSlot.from(date: memo.jour),
                foods: memo.aliments ?? [],
                macros: MealJournalService.MealMacros(),
                micros: memo.micros.map { MealJournalService.MicroPct(id: $0.key, pctRDA: $0.value) }
            )
        }
    }

    static func memoriserPrenom(_ prenom: String?, defaults: UserDefaults = .standard) {
        let propre = prenom?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let propre, !propre.isEmpty else { return }
        defaults.set(propre, forKey: clePrenom)
    }

    static func prenomMemorise(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: clePrenom)
    }

    /// Dernier état connu de l'autorisation de notifications, écrit par le
    /// planificateur de rappels (qui le lit déjà à chaque passage au premier
    /// plan). Le brief doit décider d'afficher ou non l'invitation SANS
    /// attendre une réponse asynchrone d'iOS.
    static func memoriserStatutNotifications(_ brut: Int, defaults: UserDefaults = .standard) {
        defaults.set(brut, forKey: cleStatutNotifs)
    }

    /// `nil` = jamais observé (on n'invite pas : dans le doute, on se tait).
    static func statutNotificationsMemorise(defaults: UserDefaults = .standard) -> Int? {
        defaults.object(forKey: cleStatutNotifs) as? Int
    }
}
