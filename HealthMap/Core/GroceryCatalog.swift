import Foundation

// MARK: - Grocery Catalog — "Faites vos courses"
//
// Catalogue des aliments les plus achetés en supermarché français, rangés par
// rayon, chacun relié aux nutriments qu'il apporte RÉELLEMENT (seuil ~15% des
// VNR pour une portion courante ; tags vérifiés sur la table Ciqual de l'ANSES).
//
// Rôle : SOURCE de vérité de la partie nutrition du questionnaire. L'utilisateur
// coche les aliments de son caddie puis indique une quantité par semaine, stockée
// dans `UserProfile.groceries[id] = portions/semaine`. Le moteur de score
// (NutrientEngine, à venir) et le prompt IA consomment ces quantités + ces tags.
//
// Les 10 nutriments suivis utilisent les MÊMES identifiants que HealthCalculator :
// vitD, vitB12, iron, magnesium, omega3, vitC, calcium, zinc, iodine, fiber.

/// Identifiants canoniques des 10 nutriments suivis (alignés sur HealthCalculator).
enum GroceryNutrient: String, CaseIterable, Equatable {
    case vitD, vitB12, iron, magnesium, omega3, vitC, calcium, zinc, iodine, fiber
}

/// Un aliment concret du catalogue.
struct GroceryItem: Identifiable, Equatable {
    let id: String                       // slug stable, ex "steak_hache"
    let name: String                     // libellé affiché, ex "Steak haché"
    let emoji: String
    let nutrients: [GroceryNutrient]     // nutriments dont l'aliment est une source notable
}

/// Un rayon du supermarché (un écran "Faites vos courses").
struct GroceryAisle: Identifiable, Equatable {
    let id: String
    let label: String
    let emoji: String
    let items: [GroceryItem]
}

/// Fabrique compacte pour la déclaration du catalogue.
private func gi(_ id: String, _ name: String, _ emoji: String, _ nutrients: [GroceryNutrient] = []) -> GroceryItem {
    GroceryItem(id: id, name: name, emoji: emoji, nutrients: nutrients)
}

enum GroceryCatalog {

    // MARK: Rayons

    static let aisles: [GroceryAisle] = [

        GroceryAisle(id: "fruits", label: "Fruits", emoji: "🍎", items: [
            gi("bananes", "Bananes", "🍌", [.magnesium, .fiber]),
            gi("pommes", "Pommes", "🍎", [.fiber]),
            gi("clementines", "Clémentines", "🍊", [.vitC, .fiber]),
            gi("oranges", "Oranges", "🍊", [.vitC, .fiber]),
            gi("fraises", "Fraises", "🍓", [.vitC, .fiber]),
            gi("kiwis", "Kiwis", "🥝", [.vitC, .fiber]),
            gi("raisin", "Raisin", "🍇", [.fiber]),
            gi("poires", "Poires", "🍐", [.fiber]),
            gi("peches", "Pêches", "🍑", [.vitC, .fiber]),
            gi("ananas", "Ananas", "🍍", [.vitC, .fiber]),
            gi("melon", "Melon", "🍈", [.vitC, .fiber]),
            gi("citrons", "Citrons", "🍋", [.vitC]),
            gi("pruneaux", "Pruneaux", "🟣", [.fiber]),
            gi("jus_orange", "Jus d'orange", "🧃", [.vitC]),
        ]),

        GroceryAisle(id: "legumes", label: "Légumes frais", emoji: "🥕", items: [
            gi("tomates", "Tomates", "🍅", [.vitC]),
            gi("carottes", "Carottes", "🥕", [.fiber]),
            gi("pommes_de_terre", "Pommes de terre", "🥔", [.vitC, .fiber]),
            gi("salade_verte", "Salade verte", "🥬", []),
            gi("courgettes", "Courgettes", "🥒", []),
            gi("oignons", "Oignons", "🧅", []),
            gi("poivrons", "Poivrons", "🫑", [.vitC]),
            gi("champignons", "Champignons de Paris", "🍄", []),
            gi("brocoli", "Brocoli", "🥦", [.vitC, .fiber]),
            gi("haricots_verts", "Haricots verts", "🫛", [.fiber]),
            gi("epinards", "Épinards", "🥬", [.iron, .magnesium, .calcium]),
            gi("petits_pois", "Petits pois", "🟢", [.fiber]),
            gi("chou_fleur", "Chou-fleur", "🥦", [.vitC, .fiber]),
            gi("poireaux", "Poireaux", "🥬", [.fiber]),
        ]),

        GroceryAisle(id: "viandes", label: "Viandes & charcuterie", emoji: "🥩", items: [
            gi("escalopes_poulet", "Escalopes de poulet", "🍗", [.vitB12, .zinc]),
            gi("steak_hache", "Steak haché", "🍔", [.iron, .zinc, .vitB12]),
            gi("boeuf", "Bœuf", "🥩", [.iron, .zinc, .vitB12]),
            gi("cotes_porc", "Côtes de porc", "🐖", [.vitB12, .zinc]),
            gi("escalopes_dinde", "Escalopes de dinde", "🦃", [.vitB12, .zinc]),
            gi("jambon_blanc", "Jambon blanc", "🍖", [.vitB12, .zinc]),
            gi("lardons", "Lardons", "🥓", [.vitB12, .zinc]),
            gi("saucisses", "Saucisses", "🌭", [.vitB12, .zinc]),
            gi("merguez", "Merguez", "🌭", [.iron, .zinc, .vitB12]),
            gi("cuisses_poulet", "Cuisses de poulet", "🍗", [.vitB12, .zinc]),
            gi("foie_volaille", "Foie de volaille", "🫀", [.iron, .vitB12, .zinc]),
            gi("saucisson_sec", "Saucisson sec", "🍖", [.iron, .zinc, .vitB12]),
            gi("pate_campagne", "Pâté de campagne", "🥫", [.iron, .vitB12, .zinc]),
            gi("cordons_bleus", "Cordons bleus", "🍗", [.vitB12, .zinc]),
        ]),

        GroceryAisle(id: "poissons", label: "Poissons & fruits de mer", emoji: "🐟", items: [
            gi("saumon", "Saumon", "🍣", [.omega3, .vitD, .vitB12]),
            gi("thon_boite", "Thon en boîte", "🥫", [.vitB12, .iodine]),
            gi("cabillaud", "Cabillaud", "🐟", [.vitB12, .iodine]),
            gi("sardines", "Sardines en boîte", "🥫", [.omega3, .vitD, .vitB12, .calcium, .iron]),
            gi("maquereau", "Maquereau", "🐟", [.omega3, .vitD, .vitB12]),
            gi("crevettes", "Crevettes", "🦐", [.vitB12, .iodine, .zinc]),
            gi("moules", "Moules", "🦪", [.iron, .vitB12, .iodine, .zinc]),
            gi("surimi", "Surimi", "🍢", [.vitB12, .iodine]),
            gi("poisson_pane", "Poisson pané", "🐠", [.vitB12, .iodine]),
            gi("truite", "Truite", "🐟", [.omega3, .vitD, .vitB12]),
            gi("huitres", "Huîtres", "🦪", [.zinc, .iron, .vitB12, .iodine, .magnesium]),
        ]),

        GroceryAisle(id: "laitiers", label: "Œufs & produits laitiers", emoji: "🥚", items: [
            gi("oeufs", "Œufs", "🥚", [.vitD, .vitB12, .iodine]),
            gi("lait", "Lait demi-écrémé", "🥛", [.calcium, .vitB12, .iodine]),
            gi("yaourt_nature", "Yaourt nature", "🍶", [.calcium, .vitB12, .iodine]),
            gi("yaourt_grec", "Yaourt grec", "🥣", [.calcium, .vitB12]),
            gi("fromage_blanc", "Fromage blanc", "🍶", [.calcium, .vitB12]),
            gi("petits_suisses", "Petits-suisses", "🧀", [.calcium, .vitB12]),
            gi("emmental", "Emmental râpé", "🧀", [.calcium, .vitB12, .zinc]),
            gi("camembert", "Camembert", "🧀", [.calcium, .vitB12]),
            gi("comte", "Comté", "🧀", [.calcium, .vitB12, .zinc]),
            gi("mozzarella", "Mozzarella", "🧀", [.calcium, .vitB12]),
            gi("buche_chevre", "Bûche de chèvre", "🐐", [.calcium, .vitB12]),
            gi("beurre", "Beurre", "🧈", []),
            gi("creme_fraiche", "Crème fraîche", "🥛", []),
            gi("boisson_soja", "Boisson au soja", "🌱", [.calcium]),
        ]),

        GroceryAisle(id: "feculents", label: "Féculents & légumes secs", emoji: "🍚", items: [
            gi("pates", "Pâtes", "🍝", []),
            gi("riz_blanc", "Riz blanc", "🍚", []),
            gi("baguette", "Baguette", "🥖", []),
            gi("pain_complet", "Pain complet", "🍞", [.fiber, .magnesium]),
            gi("lentilles", "Lentilles", "🫘", [.iron, .magnesium, .fiber]),
            gi("pois_chiches", "Pois chiches", "🫛", [.iron, .magnesium, .fiber]),
            gi("haricots_rouges", "Haricots rouges", "🫘", [.iron, .magnesium, .fiber]),
            gi("haricots_blancs", "Haricots blancs", "🫘", [.iron, .magnesium, .fiber, .calcium]),
            gi("flocons_avoine", "Flocons d'avoine", "🥣", [.iron, .magnesium, .fiber, .zinc]),
            gi("semoule", "Semoule", "🌾", []),
            gi("quinoa", "Quinoa", "🌱", [.iron, .magnesium, .fiber, .zinc]),
            gi("riz_complet", "Riz complet", "🍚", [.magnesium, .fiber]),
            gi("patate_douce", "Patate douce", "🍠", [.fiber, .vitC]),
            gi("cereales_petit_dej", "Céréales du petit-déjeuner", "🥣", [.iron, .fiber]),
            gi("tofu", "Tofu", "🍲", [.calcium, .iron, .magnesium]),
        ]),

        GroceryAisle(id: "secs", label: "Fruits secs, graines & grignotage", emoji: "🥜", items: [
            gi("cacahuetes", "Cacahuètes", "🥜", [.magnesium, .fiber, .zinc]),
            gi("beurre_cacahuete", "Beurre de cacahuète", "🥜", [.magnesium, .fiber]),
            gi("amandes", "Amandes", "🌰", [.magnesium, .calcium, .fiber]),
            gi("noix", "Noix", "🌰", [.omega3, .magnesium, .fiber]),
            gi("noisettes", "Noisettes", "🌰", [.magnesium, .fiber]),
            gi("noix_cajou", "Noix de cajou", "🥜", [.magnesium, .iron, .zinc]),
            gi("pistaches", "Pistaches", "🥜", [.iron, .fiber, .magnesium]),
            gi("graines_courge", "Graines de courge", "🎃", [.magnesium, .iron, .zinc]),
            gi("graines_tournesol", "Graines de tournesol", "🌻", [.magnesium, .iron, .fiber]),
            gi("chocolat_noir", "Chocolat noir", "🍫", [.iron, .magnesium, .fiber]),
            gi("raisins_secs", "Raisins secs", "🍇", [.fiber, .iron]),
            gi("abricots_secs", "Abricots secs", "🟠", [.iron, .fiber]),
            gi("figues_sechees", "Figues séchées", "🟤", [.calcium, .magnesium, .iron, .fiber]),
            gi("dattes", "Dattes", "🌴", [.fiber, .magnesium]),
            gi("graines_chia", "Graines de chia", "⚫", [.omega3, .fiber]),
        ]),

        GroceryAisle(id: "gras", label: "Matières grasses & placard", emoji: "🫒", items: [
            gi("huile_olive", "Huile d'olive", "🫒", []),
            gi("huile_tournesol", "Huile de tournesol", "🌻", []),
            gi("huile_colza", "Huile de colza", "🌼", [.omega3]),
            gi("margarine", "Margarine", "🧈", []),
            gi("avocat", "Avocat", "🥑", [.fiber]),
            gi("mayonnaise", "Mayonnaise", "🥚", []),
            gi("olives", "Olives", "🫒", [.fiber]),
            gi("puree_amandes", "Purée d'amandes", "🌰", [.calcium, .magnesium, .iron, .fiber]),
            gi("pate_tartiner", "Pâte à tartiner choco-noisette", "🍫", []),
            gi("miel", "Miel", "🍯", []),
            gi("confiture", "Confiture de fraise", "🍓", []),
            gi("vinaigrette", "Vinaigrette", "🥗", []),
        ]),
    ]

    // MARK: Accès

    /// Tous les aliments, tous rayons confondus.
    static let allItems: [GroceryItem] = aisles.flatMap(\.items)

    /// Index id -> item pour résolution O(1).
    static let itemsById: [String: GroceryItem] = Dictionary(
        uniqueKeysWithValues: allItems.map { ($0.id, $0) }
    )

    /// Résout un aliment par son id (nil si inconnu).
    static func item(id: String) -> GroceryItem? { itemsById[id] }

    /// Aliments qui sont une source notable du nutriment donné.
    static func items(providing nutrient: GroceryNutrient) -> [GroceryItem] {
        allItems.filter { $0.nutrients.contains(nutrient) }
    }
}
