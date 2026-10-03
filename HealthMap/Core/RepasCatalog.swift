import Foundation

// MARK: - Les aliments, repas par repas (1er octobre 2026)
//
// Le questionnaire ne présente plus les aliments rayon par rayon, mais comme on
// mange : « ton petit déj, ton midi, ton goûter, ton soir » (retour d'Arthur
// sur la maquette).
//
// ⚠️ PRÉSENTATION UNIQUEMENT, comme `QuantityFamily`. Rien ici ne remplace
// `GroceryCatalog.aisles`, qui reste la source des aliments, de leurs
// identifiants et de leurs apports. La réponse s'écrit toujours dans
// `profile.groceries[id] = portions par semaine` : le moteur de score et le
// prompt reçoivent exactement la même donnée qu'avant. Un repas n'est donc pas
// enregistré ; un aliment coché à un repas l'est pour tous.
//
// Chaque repas montre d'abord une douzaine d'aliments courants (ses
// « vedettes »), puis ouvre sur le catalogue entier, ses propres rayons en
// tête, avec une recherche : tout aliment du catalogue reste atteignable.

/// Les quatre repas du questionnaire.
enum RepasBilan: String, CaseIterable, Identifiable {
    case petitDej
    case midi
    case gouter
    case soir

    var id: String { rawValue }

    /// Libellé court de l'onglet.
    var onglet: String {
        switch self {
        case .petitDej: return "Petit déj"
        case .midi: return "Midi"
        case .gouter: return "Goûter"
        case .soir: return "Soir"
        }
    }

    /// Titre de l'écran.
    var titre: String {
        switch self {
        case .petitDej: return "Ton petit déj"
        case .midi: return "Ton midi"
        case .gouter: return "Ton goûter"
        case .soir: return "Ton soir"
        }
    }
}

enum RepasCatalog {

    // MARK: Vedettes

    /// Les aliments montrés d'emblée, dans l'ordre de la maquette validée.
    static let vedettesDeBase: [RepasBilan: [String]] = [
        .petitDej: [
            "baguette", "pain_complet", "flocons_avoine", "cereales_petit_dej",
            "lait", "yaourt_nature", "oeufs", "bananes",
            "jus_orange", "kiwis", "beurre", "confiture",
        ],
        .midi: [
            "escalopes_poulet", "steak_hache", "jambon_blanc", "saumon",
            "thon_boite", "pates", "riz_blanc", "pommes_de_terre",
            "lentilles", "tomates", "carottes", "salade_verte",
        ],
        .gouter: [
            "pommes", "bananes", "clementines", "amandes", "noix",
            "chocolat_noir", "barre_cereales", "yaourt_aux_fruits", "fromage_blanc",
        ],
        .soir: [
            "oeufs", "cabillaud", "sardines", "crevettes",
            "brocoli", "epinards", "courgettes", "champignons",
            "quinoa", "pois_chiches", "camembert", "yaourt_nature",
        ],
    ]

    /// Ce qui prend la place d'une vedette que le régime déclaré écarte : une
    /// personne végétarienne n'a rien à faire de cinq tuiles de viande et de
    /// poisson. Dans l'ordre où on les propose.
    static let remplacantes: [RepasBilan: [String]] = [
        .petitDej: ["boisson_soja", "yaourt_soja", "beurre_cacahuete", "amandes", "pommes", "puree_amandes"],
        .midi: [
            "escalopes_dinde", "oeufs", "tofu", "pois_chiches", "haricots_rouges",
            "quinoa", "houmous", "avocat", "haricots_verts",
        ],
        .gouter: ["yaourt_soja", "noisettes", "dattes"],
        .soir: [
            "lentilles", "tofu", "haricots_verts", "riz_complet",
            "haricots_blancs", "patate_douce", "yaourt_soja",
        ],
    ]

    /// Ce qui est végétal dans le rayon « Œufs & produits laitiers ».
    static let vegetauxDuRayonLaitier: Set<String> = [
        "boisson_soja", "yaourt_soja", "boisson_avoine", "boisson_amande",
    ]

    /// Les produits de porc du catalogue.
    static let porc: Set<String> = [
        "cotes_porc", "jambon_blanc", "lardons", "saucisses",
        "saucisson_sec", "pate_campagne", "chorizo", "boudin_noir",
    ]

    /// Faux quand le régime déclaré (`profile.dietType`) écarte cet aliment.
    /// Ne sert qu'à choisir les vedettes : le catalogue entier et la recherche
    /// ne filtrent rien, chacun reste libre de cocher ce qu'il mange vraiment.
    static func compatible(_ id: String, regime: String) -> Bool {
        let rayon = rayonParAliment[id]
        switch regime {
        case "vegan":
            if rayon == "viandes" || rayon == "poissons" { return false }
            if rayon == "laitiers" { return vegetauxDuRayonLaitier.contains(id) }
            return id != "miel" && id != "mayonnaise"
        case "vegetarien":
            return rayon != "viandes" && rayon != "poissons"
        case "halal":
            return !porc.contains(id)
        default:
            return true
        }
    }

    /// Identifiants des vedettes d'un repas pour ce régime : celles de base,
    /// chaque aliment écarté laissant sa place à la remplaçante suivante.
    static func idsVedettes(_ repas: RepasBilan, regime: String) -> [String] {
        let base = vedettesDeBase[repas] ?? []
        var reserve = (remplacantes[repas] ?? []).filter {
            compatible($0, regime: regime) && !base.contains($0)
        }
        var sortie: [String] = []
        for id in base {
            if compatible(id, regime: regime) {
                sortie.append(id)
            } else if !reserve.isEmpty {
                sortie.append(reserve.removeFirst())
            }
        }
        return sortie
    }

    /// Les vedettes d'un repas, résolues dans le catalogue.
    static func vedettes(_ repas: RepasBilan, regime: String) -> [GroceryItem] {
        idsVedettes(repas, regime: regime).compactMap { GroceryCatalog.item(id: $0) }
    }

    /// Tout ce qui est vedette d'au moins un repas, pour ce régime.
    static func toutesLesVedettes(regime: String) -> Set<String> {
        Set(RepasBilan.allCases.flatMap { idsVedettes($0, regime: regime) })
    }

    // MARK: Rayons

    /// Les rayons propres à chaque repas, dans l'ordre où on les ouvre.
    static let rayonsPropres: [RepasBilan: [String]] = [
        .petitDej: ["feculents", "laitiers", "fruits", "gras", "secs"],
        .midi: ["viandes", "poissons", "legumes", "feculents", "laitiers", "gras"],
        .gouter: ["fruits", "secs", "laitiers", "feculents"],
        .soir: ["poissons", "viandes", "legumes", "feculents", "laitiers", "gras"],
    ]

    /// Les rayons que le régime déclaré écarte en entier.
    static func rayonsEcartes(regime: String) -> Set<String> {
        switch regime {
        case "vegan", "vegetarien": return ["viandes", "poissons"]
        default: return []
        }
    }

    /// Le catalogue entier vu depuis un repas : ses rayons d'abord, les autres
    /// ensuite. Aucun rayon n'est jamais omis ; ceux que le régime écarte
    /// passent seulement à la fin, pour ne pas ouvrir sur la viande chez une
    /// personne végétarienne.
    static func rayons(_ repas: RepasBilan, regime: String = "") -> [GroceryAisle] {
        let propres = rayonsPropres[repas] ?? []
        let enTete = propres.compactMap { id in GroceryCatalog.aisles.first { $0.id == id } }
        let reste = GroceryCatalog.aisles.filter { !propres.contains($0.id) }
        let ecartes = rayonsEcartes(regime: regime)
        let tous = enTete + reste
        return tous.filter { !ecartes.contains($0.id) } + tous.filter { ecartes.contains($0.id) }
    }

    /// Rayon de chaque aliment (id d'aliment → id de rayon).
    static let rayonParAliment: [String: String] = {
        var index: [String: String] = [:]
        for rayon in GroceryCatalog.aisles {
            for aliment in rayon.items { index[aliment.id] = rayon.id }
        }
        return index
    }()

    // MARK: Ce que la personne a ajouté hors vedettes

    /// Les aliments cochés depuis le catalogue entier qui ont leur place à ce
    /// repas (leur rayon est l'un des siens) sans être la vedette d'aucun.
    /// Ils s'affichent à la suite des vedettes, pour rester réglables.
    static func ajouts(_ repas: RepasBilan, caddie: [String: Int], regime: String) -> [GroceryItem] {
        let vedettes = toutesLesVedettes(regime: regime)
        let propres = rayonsPropres[repas] ?? []
        return GroceryCatalog.allItems.filter { aliment in
            (caddie[aliment.id] ?? 0) > 0
                && !vedettes.contains(aliment.id)
                && propres.contains(rayonParAliment[aliment.id] ?? "")
        }
    }

    /// La grille d'un repas : ses vedettes, puis les ajouts de la personne.
    static func grille(_ repas: RepasBilan, caddie: [String: Int], regime: String) -> [GroceryItem] {
        vedettes(repas, regime: regime) + ajouts(repas, caddie: caddie, regime: regime)
    }

    // MARK: Libellés

    /// Nom raccourci de quelques vedettes, pour tenir sur une tuile : le
    /// catalogue dit « Escalopes de poulet », la tuile dit « Poulet ».
    static let nomsCourts: [String: String] = [
        "escalopes_poulet": "Poulet",
        "escalopes_dinde": "Dinde",
        "cereales_petit_dej": "Céréales",
        "lait": "Lait",
        "sardines": "Sardines",
        "champignons": "Champignons",
        "confiture": "Confiture",
    ]

    /// Le nom affiché sur une tuile.
    static func nomCourt(_ aliment: GroceryItem) -> String {
        nomsCourts[aliment.id] ?? aliment.name
    }

    // MARK: Recherche

    /// Clé de comparaison : sans accents, sans majuscules, « œ » déplié.
    static func cle(_ texte: String) -> String {
        texte
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "Œ", with: "oe")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Les aliments du catalogue dont le nom contient le texte cherché. Ceux
    /// qui commencent par lui passent devant. Texte vide : aucun résultat.
    static func recherche(_ texte: String) -> [GroceryItem] {
        let cherche = cle(texte)
        guard !cherche.isEmpty else { return [] }
        var debut: [GroceryItem] = []
        var milieu: [GroceryItem] = []
        for aliment in GroceryCatalog.allItems {
            let nom = cle(aliment.name)
            if nom.hasPrefix(cherche) {
                debut.append(aliment)
            } else if nom.contains(cherche) {
                milieu.append(aliment)
            }
        }
        return debut + milieu
    }
}
