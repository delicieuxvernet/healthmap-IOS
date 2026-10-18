import Foundation

// MARK: - Les micronutriments du Journal (1er octobre 2026)
//
// Le Journal montrait les macros du jour, puis trois apports à renforcer. Il
// montre désormais TOUS les micronutriments que la table Ciqual sait mesurer :
// vitamines, minéraux, acides gras.
//
// Deux familles d'identifiants cohabitent, et c'est voulu :
//   · les apports du BILAN (`NutrientID`, dix cas) ont un score calculé depuis
//     le questionnaire, corrigé par les repas notés (`NutrientLedger`,
//     `JournalApports`). Leur chiffre part du questionnaire ;
//   · les autres n'ont pas de question dans le questionnaire : leur chiffre ne
//     vient que des repas notés, et reste vide tant qu'il n'y en a pas assez.
//
// On n'ajoute donc PAS de cas à `NutrientID` : il est balayé de façon
// exhaustive par le moteur de score, le registre et les tests de parité avec
// le web. Ce catalogue vit à côté.
//
// Sources, à garder en tête à chaque retouche :
//   · composition des aliments : Table Ciqual 2020 (ANSES) ;
//   · besoins : références nutritionnelles de l'ANSES (2021) pour les vitamines
//     et minéraux, avis de l'ANSES de 2011 pour les acides gras ;
//   · rôle : allégations de santé autorisées (règlement UE n° 432/2012). Aucune
//     phrase n'annonce un symptôme : on dit à quoi l'apport contribue.

enum FamilleMicro: String, CaseIterable, Identifiable {
    case vitamines = "Vitamines"
    case mineraux = "Minéraux"
    case acidesGras = "Acides gras"

    var id: String { rawValue }
}

/// Un besoin se remplit ; une limite ne se dépasse pas (sodium).
enum SensMicro: Equatable {
    case besoin
    case limite
    /// Pas une quantité : un rapport entre deux apports (oméga-6 / oméga-3).
    case rapport
}

struct MicroDefinition: Identifiable, Equatable {
    /// Code du nutriment dans `ciqual_composition` (et dans `NutrientID` pour
    /// les apports du bilan).
    let id: String
    let nom: String
    /// Unité des quantités, celle de la base (UI pour la vitamine D).
    let unite: String
    let famille: FamilleMicro
    let sens: SensMicro
    /// À quoi il contribue : une allégation autorisée, en phrase complète.
    let role: String
    /// Trois aliments courants qui en apportent (vérifiés dans Ciqual).
    let sources: [String]
    /// Détail d'un autre micro (ALA, EPA et DHA sont le détail des oméga-3) :
    /// il s'affiche dans la liste, jamais dans les priorités.
    let detailDe: String?

    init(_ id: String, _ nom: String, _ unite: String, _ famille: FamilleMicro,
         role: String, sources: [String], sens: SensMicro = .besoin, detailDe: String? = nil) {
        self.id = id
        self.nom = nom
        self.unite = unite
        self.famille = famille
        self.sens = sens
        self.role = role
        self.sources = sources
        self.detailDe = detailDe
    }

    /// L'apport du bilan qui porte ce micro, quand il en existe un.
    var apport: NutrientID? { NutrientID(rawValue: id) }
}

enum Micronutriments {

    /// Dans l'ordre d'affichage. Les fibres n'y sont pas : elles ont déjà leur
    /// ligne dans les macros du jour.
    static let tous: [MicroDefinition] = [
        // — Vitamines
        MicroDefinition("vitD", String(localized: "Vitamine D"), String(localized: "UI"), .vitamines,
                        role: String(localized: "La vitamine D contribue au fonctionnement normal du système immunitaire et au maintien d'une ossature normale."),
                        sources: [String(localized: "Sardines"), String(localized: "Saumon"), String(localized: "Jaune d'œuf")]),
        MicroDefinition("vitB12", String(localized: "Vitamine B12"), "µg", .vitamines,
                        role: String(localized: "La vitamine B12 contribue à réduire la fatigue et au fonctionnement normal du système nerveux."),
                        sources: [String(localized: "Sardines"), String(localized: "Œufs"), String(localized: "Foie")]),
        MicroDefinition("vitC", String(localized: "Vitamine C"), "mg", .vitamines,
                        role: String(localized: "La vitamine C contribue au fonctionnement normal du système immunitaire et accroît l'absorption du fer."),
                        sources: [String(localized: "Poivron"), String(localized: "Kiwi"), String(localized: "Agrumes")]),
        MicroDefinition("vitB9", String(localized: "Vitamine B9"), "µg", .vitamines,
                        role: String(localized: "Les folates contribuent à réduire la fatigue et à la formation normale du sang."),
                        sources: [String(localized: "Épinards"), String(localized: "Lentilles"), String(localized: "Foie de volaille")]),
        MicroDefinition("vitA", String(localized: "Vitamine A"), "µg", .vitamines,
                        role: String(localized: "La vitamine A contribue au maintien d'une vision normale et d'une peau normale."),
                        sources: [String(localized: "Carotte"), String(localized: "Patate douce"), String(localized: "Foie")]),
        MicroDefinition("vitE", String(localized: "Vitamine E"), "mg", .vitamines,
                        role: String(localized: "La vitamine E contribue à protéger les cellules contre le stress oxydatif."),
                        sources: [String(localized: "Huile de tournesol"), String(localized: "Amandes"), String(localized: "Noisettes")]),
        MicroDefinition("vitK", String(localized: "Vitamine K"), "µg", .vitamines,
                        role: String(localized: "La vitamine K contribue à une coagulation sanguine normale et au maintien d'une ossature normale."),
                        sources: [String(localized: "Épinards"), String(localized: "Chou frisé"), String(localized: "Blettes")]),
        MicroDefinition("vitB1", String(localized: "Vitamine B1"), "mg", .vitamines,
                        role: String(localized: "La thiamine contribue à un métabolisme énergétique normal et au fonctionnement normal du système nerveux."),
                        sources: [String(localized: "Graines de tournesol"), String(localized: "Jambon"), String(localized: "Céréales complètes")]),
        MicroDefinition("vitB2", String(localized: "Vitamine B2"), "mg", .vitamines,
                        role: String(localized: "La riboflavine contribue à réduire la fatigue et à un métabolisme énergétique normal."),
                        sources: [String(localized: "Fromages"), String(localized: "Œufs"), String(localized: "Foie")]),
        MicroDefinition("vitB5", String(localized: "Vitamine B5"), "mg", .vitamines,
                        role: String(localized: "L'acide pantothénique contribue à réduire la fatigue et à des performances intellectuelles normales."),
                        sources: [String(localized: "Champignons"), String(localized: "Graines de tournesol"), String(localized: "Foie")]),
        MicroDefinition("vitB6", String(localized: "Vitamine B6"), "mg", .vitamines,
                        role: String(localized: "La vitamine B6 contribue à réduire la fatigue et au fonctionnement normal du système immunitaire."),
                        sources: [String(localized: "Saumon"), String(localized: "Poulet"), String(localized: "Banane")]),

        // — Minéraux
        MicroDefinition("iron", String(localized: "Fer"), "mg", .mineraux,
                        role: String(localized: "Le fer contribue à réduire la fatigue et au transport normal de l'oxygène dans l'organisme."),
                        sources: [String(localized: "Lentilles"), String(localized: "Bœuf"), String(localized: "Boudin noir")]),
        MicroDefinition("magnesium", String(localized: "Magnésium"), "mg", .mineraux,
                        role: String(localized: "Le magnésium contribue à réduire la fatigue et à une fonction musculaire normale."),
                        sources: [String(localized: "Amandes"), String(localized: "Chocolat noir"), String(localized: "Pois chiches")]),
        MicroDefinition("calcium", String(localized: "Calcium"), "mg", .mineraux,
                        role: String(localized: "Le calcium est nécessaire au maintien d'une ossature normale et contribue à une fonction musculaire normale."),
                        sources: [String(localized: "Fromages à pâte dure"), String(localized: "Yaourt"), String(localized: "Sardines avec arêtes")]),
        MicroDefinition("zinc", String(localized: "Zinc"), "mg", .mineraux,
                        role: String(localized: "Le zinc contribue au fonctionnement normal du système immunitaire et au maintien d'une peau, de cheveux et d'ongles normaux."),
                        sources: [String(localized: "Huîtres"), String(localized: "Bœuf"), String(localized: "Graines de courge")]),
        MicroDefinition("iodine", String(localized: "Iode"), "µg", .mineraux,
                        role: String(localized: "L'iode contribue à une fonction thyroïdienne normale et à une fonction cognitive normale."),
                        sources: [String(localized: "Poissons de mer"), String(localized: "Œufs"), String(localized: "Sel iodé")]),
        MicroDefinition("potassium", String(localized: "Potassium"), "mg", .mineraux,
                        role: String(localized: "Le potassium contribue à une fonction musculaire normale et au maintien d'une pression sanguine normale."),
                        sources: [String(localized: "Haricots blancs"), String(localized: "Banane"), String(localized: "Abricots secs")]),
        MicroDefinition("selenium", String(localized: "Sélénium"), "µg", .mineraux,
                        role: String(localized: "Le sélénium contribue au fonctionnement normal du système immunitaire et à protéger les cellules contre le stress oxydatif."),
                        sources: [String(localized: "Thon"), String(localized: "Cabillaud"), String(localized: "Noix du Brésil")]),
        MicroDefinition("phosphorus", String(localized: "Phosphore"), "mg", .mineraux,
                        role: String(localized: "Le phosphore contribue au maintien d'une ossature normale et à un métabolisme énergétique normal."),
                        sources: [String(localized: "Fromages à pâte dure"), String(localized: "Graines de courge"), String(localized: "Graines de sésame")]),
        MicroDefinition("copper", String(localized: "Cuivre"), "mg", .mineraux,
                        role: String(localized: "Le cuivre contribue au transport normal du fer et au fonctionnement normal du système immunitaire."),
                        sources: [String(localized: "Noix de cajou"), String(localized: "Chocolat noir"), String(localized: "Foie")]),
        MicroDefinition("sodium", String(localized: "Sodium"), "mg", .mineraux,
                        role: String(localized: "Le sodium vient surtout du sel. L'ANSES fixe une limite de sécurité à 2 300 mg par jour, soit environ 6 g de sel."),
                        sources: [String(localized: "Charcuterie"), String(localized: "Fromages"), String(localized: "Pain")],
                        sens: .limite),

        // — Acides gras
        MicroDefinition("omega3", String(localized: "Oméga-3"), "g", .acidesGras,
                        role: String(localized: "Les oméga-3 EPA et DHA contribuent à une fonction cardiaque normale, à partir de 250 mg par jour."),
                        sources: [String(localized: "Maquereau"), String(localized: "Noix"), String(localized: "Huile de colza")]),
        MicroDefinition("epaDha", String(localized: "Oméga-3 EPA et DHA"), "g", .acidesGras,
                        role: String(localized: "L'EPA et le DHA contribuent à une fonction cardiaque normale, à partir de 250 mg par jour."),
                        sources: [String(localized: "Maquereau"), String(localized: "Sardines"), String(localized: "Saumon")],
                        detailDe: "omega3"),
        MicroDefinition("ala", String(localized: "Oméga-3 ALA"), "g", .acidesGras,
                        role: String(localized: "L'acide alpha-linolénique contribue au maintien d'une cholestérolémie normale, à partir de 2 g par jour."),
                        sources: [String(localized: "Huile de colza"), String(localized: "Noix"), String(localized: "Graines de lin")],
                        detailDe: "omega3"),
        MicroDefinition("omega6", String(localized: "Oméga-6"), "g", .acidesGras,
                        role: String(localized: "L'acide linoléique contribue au maintien d'une cholestérolémie normale, à partir de 10 g par jour."),
                        sources: [String(localized: "Huile de tournesol"), String(localized: "Noix"), String(localized: "Graines de tournesol")]),
        MicroDefinition("omega9", String(localized: "Oméga-9"), "g", .acidesGras,
                        role: String(localized: "L'acide oléique est une graisse insaturée. Remplacer des graisses saturées par des graisses insaturées contribue au maintien d'une cholestérolémie normale."),
                        sources: [String(localized: "Huile d'olive"), String(localized: "Noisettes"), String(localized: "Avocat")]),
        // Le rapport entre l'acide linoléique (oméga-6) et l'acide
        // alpha-linolénique (oméga-3) : l'ANSES (2011) le veut inférieur à 5.
        // Ses « sources » sont les aliments qui le font baisser.
        MicroDefinition("rapportOmega", String(localized: "Rapport oméga-6 / oméga-3"), "", .acidesGras,
                        role: String(localized: "Les oméga-6 et les oméga-3 empruntent les mêmes voies dans l'organisme. Le repère conseillé : au plus 5 fois plus d'oméga-6 que d'oméga-3."),
                        sources: [String(localized: "Huile de colza"), String(localized: "Noix"), String(localized: "Graines de lin")],
                        sens: .rapport),
    ]

    static let parId: [String: MicroDefinition] = Dictionary(uniqueKeysWithValues: tous.map { ($0.id, $0) })

    static func definition(_ id: String) -> MicroDefinition? { parId[id] }

    /// D'où viennent les chiffres : la ligne de bas de fiche.
    static let mentionSources = String(localized: "Composition des aliments : table Ciqual 2020 de l'ANSES. Besoins : références nutritionnelles de l'ANSES.")
}

// MARK: - Les besoins de la personne, pour tous les micros

enum BesoinsMicros {

    /// Dépense quotidienne retenue quand le profil ne permet pas de la calculer.
    static let depenseParDefaut = 2000.0

    /// Le besoin quotidien de cette personne pour chaque micro du catalogue,
    /// dans l'unité du catalogue. Pour le sodium, c'est la limite.
    static func tous(profil p: UserProfile, depense: Double? = nil) -> [String: Double] {
        let kcal = depense ?? Double(PhysicalMetrics(profile: p).tdee ?? Int(depenseParDefaut))
        var sortie: [String: Double] = [:]
        for micro in Micronutriments.tous {
            sortie[micro.id] = besoin(micro.id, profil: p, depense: kcal)
        }
        return sortie
    }

    /// Références de l'ANSES (2021) : référence nutritionnelle pour la
    /// population ou apport satisfaisant, par sexe, grossesse et allaitement.
    /// Les acides gras suivent l'avis de 2011, exprimé en part de l'énergie :
    /// on le ramène en grammes avec la dépense de la personne (9 kcal par gramme).
    static func besoin(_ id: String, profil p: UserProfile, depense kcal: Double) -> Double {
        if let apport = NutrientID(rawValue: id) {
            return BesoinsDeReference.besoin(apport, profil: p)
        }
        let femme = p.gender == .femme
        let enceinte = femme && p.pregnancyStatus == "pregnant"
        let allaite = femme && p.pregnancyStatus == "breastfeeding"
        let energie = max(1200, kcal)

        switch id {
        case "vitA":
            if allaite { return 1300 }
            if enceinte { return 700 }
            return femme ? 650 : 750
        case "vitE":
            return femme ? 9 : 10
        case "vitK":
            return 79
        case "vitB1":
            // 0,1 mg par mégajoule d'énergie consommée (1 kcal = 0,004184 MJ).
            return 0.1 * energie * 0.004184
        case "vitB2":
            if allaite { return 2.0 }
            if enceinte { return 1.9 }
            return 1.6
        case "vitB5":
            if allaite { return 7 }
            return femme ? 5 : 6
        case "vitB6":
            if allaite { return 1.7 }
            if enceinte { return 1.8 }
            return femme ? 1.6 : 1.7
        case "vitB9":
            // Projet de grossesse : 600 µg, comme le référentiel (ANSES 2021).
            if enceinte || (femme && p.pregnancyStatus == "trying_to_conceive") { return 600 }
            if allaite { return 500 }
            return 330
        case "potassium":
            return allaite ? 4000 : 3500
        case "selenium":
            return allaite ? 85 : 70
        case "phosphorus":
            return 550
        case "copper":
            if enceinte || allaite { return 1.7 }
            return femme ? 1.5 : 1.9
        case "sodium":
            return 2300
        case "rapportOmega":
            return MicrosDuJour.rapportVise
        case "epaDha":
            return 0.5
        case "ala":
            return 0.01 * energie / 9
        case "omega6":
            return 0.04 * energie / 9
        case "omega9":
            return 0.15 * energie / 9
        default:
            return 0
        }
    }
}
