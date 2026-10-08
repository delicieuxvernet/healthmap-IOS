import Foundation

// MARK: - Aliments de référence du brief (8 octobre 2026)
//
// Le brief dit « Sardines · 1 boîte · +30 % de ton besoin ». Ce chiffre n'est
// PAS écrit ici : la table ne donne que l'aliment Ciqual et sa portion. La
// composition vient de la base (`micros_detail_100g`, la même que le Journal)
// et le pourcentage se calcule comme celui d'un repas noté : quantité de la
// portion ÷ référence de `MealJournalService.canonRDA`. Noter cette portion
// dans le journal ferait donc monter le chiffre d'hier d'autant.
//
// Les aliments proposés viennent du bilan (texte libre de l'IA) ou du repli
// `SourcesAlimentaires`. Un nom que la table ne reconnaît pas reste affiché,
// sans chiffre : on ne devine pas.
//
// Codes vérifiés dans `ciqual_composition` le 8 oct. 2026 : pour chaque
// aliment, la variante la mieux renseignée sur les dix apports du bilan (le
// « saumon cuit, aliment moyen » n'a pas de vitamine D dans Ciqual, le saumon
// vapeur si). Portions : celles de `ciqual_portions` quand elles sont
// parlantes, sinon la portion usuelle d'un adulte.

struct AlimentDeReference: Equatable {
    /// Nom affiché, accordé à la portion : « Sardines », « Œufs ».
    let nom: String
    /// L'aliment tel que le journal l'enregistre (`ciqual:26034`).
    let foodId: String
    /// La portion telle qu'on la dit : « 1 boîte », « 2 œufs ».
    let portion: String
    let grammes: Double
    /// Illustration 3D du bundle (`fluent_*`), quand l'aliment en a une.
    let illustration: String?
    /// Les autres façons de l'écrire.
    var autresNoms: [String] = []
}

enum AlimentsDeReference {

    /// En dessous de 5 points, « +2 % de ton besoin » décourage plus qu'il
    /// n'aide : l'aliment est alors proposé sans chiffre. Même seuil que
    /// l'effort de la semaine.
    static let apportMinimum = 5

    static let tous: [AlimentDeReference] = [
        // Poissons et produits de la mer
        AlimentDeReference(nom: "Sardines", foodId: "ciqual:26034", portion: "1 boîte", grammes: 100,
                           illustration: "fluent_fish", autresNoms: ["sardines à l'huile"]),
        AlimentDeReference(nom: "Saumon", foodId: "ciqual:26038", portion: "1 pavé", grammes: 130,
                           illustration: "fluent_fish", autresNoms: ["pavé de saumon"]),
        AlimentDeReference(nom: "Maquereau", foodId: "ciqual:26019", portion: "1 filet", grammes: 120,
                           illustration: "fluent_fish", autresNoms: ["filet de maquereau"]),
        AlimentDeReference(nom: "Truite", foodId: "ciqual:27014", portion: "1 filet", grammes: 120,
                           illustration: "fluent_fish", autresNoms: ["filet de truite"]),
        AlimentDeReference(nom: "Cabillaud", foodId: "ciqual:25997", portion: "1 pavé", grammes: 120,
                           illustration: "fluent_fish", autresNoms: ["dos de cabillaud"]),
        AlimentDeReference(nom: "Lieu", foodId: "ciqual:26192", portion: "1 pavé", grammes: 120,
                           illustration: "fluent_fish", autresNoms: ["colin", "lieu colin", "lieu jaune"]),
        AlimentDeReference(nom: "Thon", foodId: "ciqual:26039", portion: "½ boîte", grammes: 70,
                           illustration: "fluent_fish",
                           autresNoms: ["thon en boîte", "thon au naturel", "miettes de thon"]),
        AlimentDeReference(nom: "Thon frais", foodId: "ciqual:26041", portion: "1 pavé", grammes: 120,
                           illustration: "fluent_fish", autresNoms: ["steak de thon", "pavé de thon"]),
        AlimentDeReference(nom: "Moules", foodId: "ciqual:10013", portion: "1 assiette", grammes: 120,
                           illustration: "fluent_oyster"),
        AlimentDeReference(nom: "Crevettes", foodId: "ciqual:10007", portion: "1 portion", grammes: 100,
                           illustration: "fluent_oyster"),

        // Œufs, abats, viandes
        AlimentDeReference(nom: "Œufs", foodId: "ciqual:22010", portion: "2 œufs", grammes: 100,
                           illustration: "fluent_egg", autresNoms: ["œuf", "œuf entier", "œufs durs"]),
        AlimentDeReference(nom: "Jaune d'œuf", foodId: "ciqual:22009", portion: "2 jaunes", grammes: 36,
                           illustration: "fluent_egg"),
        AlimentDeReference(nom: "Foie de volaille", foodId: "ciqual:40109", portion: "1 portion", grammes: 100,
                           illustration: "fluent_poultry", autresNoms: ["foie"]),
        AlimentDeReference(nom: "Boudin noir", foodId: "ciqual:8704", portion: "1 portion", grammes: 120,
                           illustration: "fluent_meat"),
        AlimentDeReference(nom: "Steak haché", foodId: "ciqual:6251", portion: "1 steak", grammes: 100,
                           illustration: "fluent_meat", autresNoms: ["steak"]),
        AlimentDeReference(nom: "Viande rouge", foodId: "ciqual:6200", portion: "1 steak", grammes: 120,
                           illustration: "fluent_meat", autresNoms: ["bœuf", "steak de bœuf", "bifteck"]),

        // Produits laitiers
        AlimentDeReference(nom: "Lait", foodId: "ciqual:19041", portion: "1 verre", grammes: 200,
                           illustration: "fluent_milk", autresNoms: ["lait demi-écrémé", "lait de vache"]),
        AlimentDeReference(nom: "Yaourt", foodId: "ciqual:19593", portion: "1 pot", grammes: 125,
                           illustration: "fluent_milk", autresNoms: ["yaourt nature", "yogourt"]),
        AlimentDeReference(nom: "Yaourt grec", foodId: "ciqual:19860", portion: "1 pot", grammes: 125,
                           illustration: "fluent_milk", autresNoms: ["yaourt à la grecque"]),
        AlimentDeReference(nom: "Fromage blanc", foodId: "ciqual:19646", portion: "1 pot", grammes: 100,
                           illustration: "fluent_milk"),
        AlimentDeReference(nom: "Emmental", foodId: "ciqual:12115", portion: "1 portion", grammes: 30,
                           illustration: "fluent_cheese", autresNoms: ["emmenthal", "emmental râpé"]),
        AlimentDeReference(nom: "Comté", foodId: "ciqual:12110", portion: "1 portion", grammes: 30,
                           illustration: "fluent_cheese"),

        // Légumineuses, légumes, céréales
        AlimentDeReference(nom: "Lentilles", foodId: "ciqual:20505", portion: "1 portion", grammes: 150,
                           illustration: nil,
                           autresNoms: ["lentilles vertes", "lentilles corail", "lentilles blondes"]),
        AlimentDeReference(nom: "Pois chiches", foodId: "ciqual:20507", portion: "1 portion", grammes: 150,
                           illustration: nil),
        AlimentDeReference(nom: "Haricots rouges", foodId: "ciqual:20503", portion: "1 portion", grammes: 150,
                           illustration: nil),
        AlimentDeReference(nom: "Haricots blancs", foodId: "ciqual:20502", portion: "1 portion", grammes: 150,
                           illustration: nil),
        AlimentDeReference(nom: "Épinards", foodId: "ciqual:20027", portion: "1 portion", grammes: 130,
                           illustration: "fluent_leafygreen"),
        AlimentDeReference(nom: "Brocoli", foodId: "ciqual:20006", portion: "1 portion", grammes: 130,
                           illustration: "fluent_broccoli"),
        AlimentDeReference(nom: "Petits pois", foodId: "ciqual:20037", portion: "1 portion", grammes: 130,
                           illustration: nil),
        AlimentDeReference(nom: "Poivron", foodId: "ciqual:20087", portion: "1 portion", grammes: 130,
                           illustration: nil, autresNoms: ["poivron rouge"]),
        AlimentDeReference(nom: "Pain complet", foodId: "ciqual:7110", portion: "2 tranches", grammes: 60,
                           illustration: nil),
        AlimentDeReference(nom: "Flocons d'avoine", foodId: "ciqual:9311", portion: "1 bol", grammes: 40,
                           illustration: nil, autresNoms: ["avoine"]),
        AlimentDeReference(nom: "Riz complet", foodId: "ciqual:9103", portion: "1 portion", grammes: 150,
                           illustration: nil),

        // Fruits
        AlimentDeReference(nom: "Kiwi", foodId: "ciqual:13021", portion: "1 kiwi", grammes: 90,
                           illustration: "fluent_kiwi"),
        AlimentDeReference(nom: "Orange", foodId: "ciqual:13034", portion: "1 orange", grammes: 130,
                           illustration: "fluent_tangerine"),
        AlimentDeReference(nom: "Clémentines", foodId: "ciqual:13024", portion: "2 clémentines", grammes: 120,
                           illustration: "fluent_tangerine", autresNoms: ["clémentine", "mandarines"]),
        AlimentDeReference(nom: "Fraises", foodId: "ciqual:13014", portion: "1 portion", grammes: 130,
                           illustration: "fluent_strawberry"),
        AlimentDeReference(nom: "Banane", foodId: "ciqual:13005", portion: "1 banane", grammes: 120,
                           illustration: "fluent_banana"),

        // Oléagineux, graines, huiles, chocolat
        AlimentDeReference(nom: "Amandes", foodId: "ciqual:15000", portion: "1 poignée", grammes: 30,
                           illustration: "fluent_peanuts"),
        AlimentDeReference(nom: "Noix", foodId: "ciqual:15005", portion: "1 poignée", grammes: 30,
                           illustration: "fluent_peanuts", autresNoms: ["cerneaux de noix"]),
        AlimentDeReference(nom: "Noisettes", foodId: "ciqual:15004", portion: "1 poignée", grammes: 30,
                           illustration: "fluent_peanuts"),
        AlimentDeReference(nom: "Graines de lin", foodId: "ciqual:15034", portion: "1 c. à soupe", grammes: 10,
                           illustration: nil),
        AlimentDeReference(nom: "Huile de colza", foodId: "ciqual:17130", portion: "1 c. à soupe", grammes: 10,
                           illustration: nil),
        AlimentDeReference(nom: "Chocolat noir", foodId: "ciqual:31074", portion: "2 carrés", grammes: 20,
                           illustration: nil),
    ]

    /// Les aliments à garder sur le téléphone pour que le brief chiffre sans réseau.
    static var identifiants: Set<String> { Set(tous.map(\.foodId)) }

    // MARK: Reconnaître un nom

    /// L'aliment de la table que ce nom désigne, ou nil. « Sardines en boîte »,
    /// « saumon vapeur » ou « Œufs » sont reconnus ; « noix de coco » n'est pas
    /// des noix, ni « lait enrichi » du lait : un nom qui dit autre chose reste
    /// sans chiffre.
    static func trouver(_ nom: String) -> AlimentDeReference? {
        var cle = Self.cle(nom)
        while !cle.isEmpty {
            if let aliment = parCle[cle] { return aliment }
            guard let raccourcie = sansPrecision(cle) else { return nil }
            cle = raccourcie
        }
        return nil
    }

    /// Le nom ramené à sa forme comparable : minuscules, sans accents ni
    /// ligatures, sans parenthèses, chiffres ni ponctuation, au singulier
    /// (« Épinards sautés » → « epinard saute »).
    static func cle(_ nom: String) -> String {
        var texte = nom.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "’", with: "'")
        texte = texte.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        texte = texte.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        return texte
            .split { !($0.isLetter || $0 == "'") }
            .map { brut -> String in
                let mot = String(brut)
                return mot.count > 3 && mot.hasSuffix("s") ? String(mot.dropLast()) : mot
            }
            .joined(separator: " ")
    }

    /// Façons de préparer qu'on peut retirer en fin de nom pour retrouver
    /// l'aliment. Les plus longues d'abord : « cuit à la vapeur » avant « vapeur ».
    private static let precisions: [String] = {
        let brutes = [
            "cuit à la vapeur", "cuite à la vapeur", "à la vapeur", "vapeur",
            "en boîte", "en conserve", "à l'huile", "à l'huile d'olive", "au naturel",
            "cru", "crue", "cuit", "cuite", "sauté", "sautée", "grillé", "grillée",
            "poêlé", "poêlée", "rôti", "rôtie", "frais", "fraîche",
            "entier", "entière", "moulu", "moulue", "nature", "bio", "maison",
        ]
        return Array(Set(brutes.map(cle))).sorted { $0.count > $1.count }
    }()

    private static func sansPrecision(_ cle: String) -> String? {
        for precision in precisions where cle.hasSuffix(" " + precision) {
            return String(cle.dropLast(precision.count + 1))
        }
        return nil
    }

    private static let parCle: [String: AlimentDeReference] = {
        var index: [String: AlimentDeReference] = [:]
        for aliment in tous {
            for nom in [aliment.nom] + aliment.autresNoms where index[cle(nom)] == nil {
                index[cle(nom)] = aliment
            }
        }
        return index
    }()

    // MARK: Ce que la portion apporte

    /// Ce que la portion apporte de ce nutriment, en points de « % du besoin »,
    /// avec la référence des repas notés. nil quand la base ne le renseigne pas
    /// pour cet aliment, ou que sa composition n'est pas encore sur le téléphone.
    static func apport(
        _ aliment: AlimentDeReference,
        nutriment id: String,
        compositions: Compositions
    ) -> Int? {
        guard let pour100g = compositions[aliment.foodId]?.apports[id],
              let reference = MealJournalService.canonRDA[id], reference > 0 else { return nil }
        return Int((max(0, pour100g) * aliment.grammes / 100 / reference * 100).rounded())
    }
}
