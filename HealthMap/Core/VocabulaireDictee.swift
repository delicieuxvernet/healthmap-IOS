import Foundation

// MARK: - Vocabulaire de la dictée (audit vocal du 19 oct. 2026)
//
// Retour d'Arthur : « je dis que j'ai mangé du skyr au soja et ça ne reconnaît
// rien ». La reconnaissance vocale de l'iPhone ne connaît pas les mots rares de
// l'assiette : elle écrit « ski » pour skyr, « quéfir » pour kéfir, et déforme
// les marques. `contextualStrings` lui donne ces mots d'avance (Apple conseille
// une centaine de termes au plus : au-delà, ils pèsent moins).
//
// Le serveur rattrape ensuite ce qui passe encore (consigne « la dictée est
// transcrite par une machine », parse-meal-voice). Ici, on évite l'erreur.
//
// Choix des termes : des noms d'aliments ou de marques qu'on DIT en racontant
// un repas, et que la dictée française rate (mots étrangers, mots récents,
// homophones). Pas les mots courants (pain, pomme) : elle les connaît déjà.

enum VocabulaireDictee {

    /// Termes donnés à la reconnaissance vocale, dans l'ordre d'importance.
    static let termes: [String] = [
        // Produits laitiers et végétal
        "skyr", "skyr au soja", "skyr végétal", "kéfir", "faisselle", "petit-suisse",
        "tofu", "tofu fumé", "tempeh", "seitan", "houmous", "falafel", "edamame",
        "lait d'avoine", "lait d'amande", "yaourt au soja", "steak végétal",
        // Féculents et céréales
        "quinoa", "boulgour", "granola", "muesli", "porridge", "gnocchi", "tagliatelles",
        "vermicelles", "ramen", "udon", "pad thaï", "bo bun", "polenta", "épeautre",
        // Plats
        "poke bowl", "wrap", "burrito", "tacos", "fajitas", "kebab", "panini",
        "croque-monsieur", "tartiflette", "raclette", "risotto", "taboulé", "couscous",
        "paella", "chili con carne", "nems", "sushi", "maki", "sashimi", "carbonara",
        // Viandes, poissons
        "chipolata", "merguez", "chorizo", "knacks", "rillettes", "magret",
        "gambas", "cabillaud", "maquereau", "surimi", "saint-jacques",
        // Fruits, légumes, graines
        "avocat", "litchi", "mangue", "kiwi", "patate douce", "butternut", "chou kale",
        "graines de chia", "noix de cajou", "pistaches", "açaï", "matcha", "kombucha",
        "smoothie", "chocolatine",
        // Marques qu'on cite en mangeant
        "Alpro", "Danone", "Activia", "Yoplait", "Siggi's", "Bjorg", "Gerblé", "Sojasun",
        "Nutella", "Kinder", "Bonne Maman", "Président", "Babybel", "Kiri", "Philadelphia",
        "Herta", "Fleury Michon", "Oreo", "Kellogg's",
        "Chocapic", "Trésor", "Coca-Cola", "Coca zéro",
    ]
}
