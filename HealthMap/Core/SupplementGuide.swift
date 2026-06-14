import Foundation

// MARK: - Supplement Guide (contenu curé, factuel — JAMAIS l'IA)
//
// Complète les données du moteur (`SupplementEngine` → score, whyText, produit,
// prix, contre-indications) avec des informations GÉNÉRALES et stables par
// nutriment : bénéfice, comment le prendre (forme + timing d'absorption), durée
// de cure, sources alimentaires. Même esprit que `NutrientData` (source canonique,
// pas de génération IA — règle CLAUDE.md 2.1).
//
// Clé = `NutrientID.rawValue` (« vitD », « iron », « magnesium », …), pour ne pas
// dépendre des noms de cas de l'enum.
struct SupplementGuideInfo {
    /// À quoi ça sert, en une ligne (vulgarisé).
    let benefit: String
    /// Forme conseillée + comment le prendre (absorption).
    let howToTake: String
    /// Durée de cure typique.
    let cureDuration: String
    /// Sources alimentaires pour en avoir aussi par l'assiette.
    let foodSources: String
}

enum SupplementGuide {
    /// Renvoie le guide d'un nutriment, ou `nil` s'il n'est pas catalogué
    /// (les fiches s'adaptent : un champ absent n'est tout simplement pas affiché).
    static func info(for nutrientRawValue: String) -> SupplementGuideInfo? {
        guides[nutrientRawValue]
    }

    static let guides: [String: SupplementGuideInfo] = [
        "vitD": SupplementGuideInfo(
            benefit: "Immunité, humeur et santé des os",
            howToTake: "Vitamine D3 (forme huileuse), avec un repas contenant un peu de gras : c'est bien mieux absorbé.",
            cureDuration: "Cure de 3 mois, puis on revérifie par une prise de sang.",
            foodSources: "Saumon, sardines, jaune d'œuf, foie de morue."
        ),
        "iron": SupplementGuideInfo(
            benefit: "Énergie et moins de fatigue",
            howToTake: "Fer bisglycinate (doux pour l'estomac), le matin. Avec de la vitamine C ; à distance du café, du thé et du calcium.",
            cureDuration: "Cure de 3 mois, puis contrôle de la ferritine.",
            foodSources: "Lentilles, boudin, viande rouge, épinards avec un filet de citron."
        ),
        "magnesium": SupplementGuideInfo(
            benefit: "Détente, sommeil et résistance au stress",
            howToTake: "Magnésium bisglycinate ou citrate (mieux tolérés que l'oxyde), plutôt le soir.",
            cureDuration: "Cure de 1 à 3 mois.",
            foodSources: "Amandes, chocolat noir, légumes verts, légumineuses."
        ),
        "vitB12": SupplementGuideInfo(
            benefit: "Énergie, système nerveux et globules rouges",
            howToTake: "Méthylcobalamine, à laisser fondre sous la langue, le matin.",
            cureDuration: "Cure de 2 à 3 mois, surtout avec peu de produits animaux.",
            foodSources: "Œufs, produits laitiers, poisson, viande (ou aliments enrichis si régime végétal)."
        ),
        "omega3": SupplementGuideInfo(
            benefit: "Cœur, cerveau et action anti-inflammatoire",
            howToTake: "EPA/DHA (huile de poisson ou d'algue), pendant un repas.",
            cureDuration: "En continu, ou par cures de 3 mois.",
            foodSources: "Poissons gras (sardine, maquereau, saumon), noix, graines de lin."
        ),
        "vitC": SupplementGuideInfo(
            benefit: "Immunité, absorption du fer et effet antioxydant",
            howToTake: "Le matin ou répartie dans la journée, avec un repas.",
            cureDuration: "Cure ponctuelle (hiver, coup de fatigue).",
            foodSources: "Kiwi, agrumes, poivron, persil, fruits rouges."
        ),
        "calcium": SupplementGuideInfo(
            benefit: "Solidité des os et des dents",
            howToTake: "En 2 prises si la dose est élevée, à distance du fer.",
            cureDuration: "Selon tes apports laitiers et ton bilan.",
            foodSources: "Produits laitiers, amandes, eaux riches en calcium, légumes verts."
        ),
        "zinc": SupplementGuideInfo(
            benefit: "Immunité, peau et cicatrisation",
            howToTake: "Zinc bisglycinate, à distance du fer et du calcium.",
            cureDuration: "Cure courte (1 à 2 mois).",
            foodSources: "Huîtres, viande, graines de courge, légumineuses."
        ),
        "iodine": SupplementGuideInfo(
            benefit: "Bon fonctionnement de la thyroïde",
            howToTake: "Le matin. Prudence en cas de trouble thyroïdien : demande un avis médical.",
            cureDuration: "Selon ton bilan thyroïdien.",
            foodSources: "Poisson, algues, sel iodé, produits laitiers."
        ),
        "fiber": SupplementGuideInfo(
            benefit: "Digestion, satiété et microbiote",
            howToTake: "Psyllium, avec un grand verre d'eau.",
            cureDuration: "En continu, en augmentant progressivement les doses.",
            foodSources: "Légumes, fruits, légumineuses, céréales complètes."
        ),
    ]
}
