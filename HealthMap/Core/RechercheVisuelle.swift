import Foundation

// MARK: - Un repère visuel par résultat de recherche (maquette validée le 21 sept. 2026)
//
// Retour d'Arthur : « parmi les dix résultats, qui se ressemblent quasiment à
// la lettre près », rien n'aidait à reconnaître le bon. Chaque ligne porte
// donc un repère :
//   · un PRODUIT de marque (Open Food Facts) → la photo de son emballage ;
//   · un ALIMENT générique (CIQUAL, sans photo) → l'illustration de sa famille.
// Et la liste se range en deux sections, pour ne plus mêler les deux.
//
// Ici, ce qui se décide sans écran : quel repère, quel sous-titre, quelles
// sections. Pur, testable ligne par ligne.

/// Ce que la vignette d'une ligne affiche.
enum RepereAliment: Equatable {
    /// Photo de l'emballage (Open Food Facts, toujours en https).
    case photo(URL)
    /// Illustration 3D du bundle (`fluent_*`).
    case illustration(String)
    /// Famille sans illustration 3D : l'emoji du système.
    case emoji(String)
    /// Produit de marque sans photo.
    case symbole(String)
}

enum RechercheVisuelle {

    // MARK: Le repère

    private static func cle(_ texte: String?) -> String {
        (texte ?? "").folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR")).lowercased()
    }

    /// Un MOT du nom commence par l'un des mots-clés : « épinards » répond à
    /// « epinard », mais « foie » ne répond pas à « oie », ni « menthe » à « the ».
    private static func contient(_ texte: String, _ mots: [String]) -> Bool {
        let debuts = texte.split { !$0.isLetter }
        return mots.contains { mot in debuts.contains { $0.hasPrefix(mot) } }
    }

    static func repere(source: String, image: String?, nom: String,
                       groupe: String?, sousGroupe: String?) -> RepereAliment {
        if source == "off" {
            if let image, let url = URL(string: image), url.scheme == "https" { return .photo(url) }
            return .symbole("barcode")
        }
        return repereDeFamille(nom: cle(nom), groupe: cle(groupe), sousGroupe: cle(sousGroupe))
    }

    /// La famille CIQUAL donne le repère ; le nom l'affine quand la famille est
    /// large (une volaille n'est pas un steak, une banane n'est pas un agrume).
    private static func repereDeFamille(nom: String, groupe: String, sousGroupe: String) -> RepereAliment {
        switch sousGroupe {
        case "legumes":
            if contient(nom, ["avocat"]) { return .illustration("fluent_avocado") }
            if contient(nom, ["salade", "laitue", "epinard", "mache", "roquette", "chou", "blette", "cresson"]) {
                return .illustration("fluent_leafygreen")
            }
            if contient(nom, ["carotte"]) { return .emoji("🥕") }
            if contient(nom, ["tomate"]) { return .emoji("🍅") }
            return .illustration("fluent_broccoli")
        case "fruits":
            if contient(nom, ["banane"]) { return .illustration("fluent_banana") }
            if contient(nom, ["fraise", "framboise"]) { return .illustration("fluent_strawberry") }
            if contient(nom, ["citron"]) { return .illustration("fluent_lemon") }
            if contient(nom, ["orange", "clementine", "mandarine", "pamplemousse"]) { return .illustration("fluent_tangerine") }
            if contient(nom, ["myrtille", "cassis", "mure"]) { return .illustration("fluent_blueberries") }
            if contient(nom, ["avocat"]) { return .illustration("fluent_avocado") }
            if contient(nom, ["pomme"]) { return .emoji("🍎") }
            if contient(nom, ["poire"]) { return .emoji("🍐") }
            if contient(nom, ["raisin"]) { return .emoji("🍇") }
            return .illustration("fluent_kiwi")
        case "fruits a coque et graines oleagineuses":
            return .illustration("fluent_peanuts")
        case "legumineuses":
            return .emoji("🫘")
        case "pommes de terre et autres tubercules":
            return .emoji("🥔")
        case "viandes crues", "viandes cuites":
            if contient(nom, ["poulet", "dinde", "canard", "volaille", "pintade", "caille", "oie"]) {
                return .illustration("fluent_poultry")
            }
            return .illustration("fluent_meat")
        case "charcuteries et assimiles", "autres produits a base de viande":
            return .illustration("fluent_meat")
        case "poissons crus", "poissons cuits", "produits a base de poissons et produits de la mer":
            return .illustration("fluent_fish")
        case "mollusques et crustaces crus", "mollusques et crustaces cuits":
            return .illustration("fluent_oyster")
        case "oeufs", "œufs":
            return .illustration("fluent_egg")
        case "fromages et assimiles":
            return .illustration("fluent_cheese")
        case "pates, riz et cereales":
            if contient(nom, ["riz"]) { return .emoji("🍚") }
            return .illustration("fluent_spaghetti")
        case "pains et assimiles":
            return .emoji("🥖")
        case "biscuits aperitifs":
            return .emoji("🥨")
        case "gateaux et patisseries":
            return .emoji("🍰")
        case "biscuits sucres":
            return .emoji("🍪")
        case "viennoiseries":
            return .emoji("🥐")
        case "cereales de petit-dejeuner":
            return .emoji("🥣")
        case "chocolats et produits a base de chocolat":
            return .emoji("🍫")
        case "confiseries non chocolatees":
            return .emoji("🍬")
        case "sucres, miels et assimiles", "confitures et assimiles":
            return .emoji("🍯")
        case "eaux":
            return .illustration("fluent_droplet")
        case "boissons sans alcool":
            if contient(nom, ["cafe"]) { return .emoji("☕️") }
            if contient(nom, ["the", "infusion", "tisane"]) { return .emoji("🍵") }
            return .emoji("🥤")
        case "boisson alcoolisees", "boissons alcoolisees":
            return .emoji("🍷")
        case "plats composes":
            return .illustration("fluent_plate")
        case "pizzas, tartes et crepes salees":
            return .emoji("🍕")
        case "soupes":
            return .emoji("🍲")
        case "sandwichs":
            return .emoji("🥪")
        case "salades composees et crudites":
            return .emoji("🥗")
        case "huiles et graisses vegetales":
            return .emoji("🫒")
        case "beurres", "margarines":
            return .emoji("🧈")
        case "sauces", "condiments":
            return .emoji("🥫")
        case "herbes", "epices", "algues":
            return .emoji("🌿")
        default:
            break
        }

        switch groupe {
        case "fruits, legumes, legumineuses et oleagineux": return .illustration("fluent_broccoli")
        case "viandes, oeufs, poissons et assimiles", "viandes, œufs, poissons et assimiles": return .illustration("fluent_meat")
        case "produits laitiers et assimiles": return .illustration("fluent_milk")
        case "produits cerealiers": return .illustration("fluent_spaghetti")
        case "produits sucres": return .emoji("🍰")
        case "eaux et autres boissons": return .emoji("🥤")
        case "entrees et plats composes": return .illustration("fluent_plate")
        case "matieres grasses": return .emoji("🧈")
        case "glaces et sorbets": return .emoji("🍨")
        case "aliments infantiles": return .emoji("🍼")
        case "aides culinaires et ingredients divers": return .emoji("🧂")
        default: return .illustration("fluent_plate")
        }
    }

    // MARK: Le sous-titre

    /// Open Food Facts livre parfois toute la raison sociale (« Barilla, Barilla
    /// Teigwaren, Barilla G. e R. Fratelli… ») : on garde la première marque.
    static func marqueCourte(_ marque: String?) -> String? {
        guard let premiere = marque?.split(separator: ",").first else { return nil }
        let propre = premiere.trimmingCharacters(in: .whitespacesAndNewlines)
        return propre.isEmpty ? nil : propre
    }

    /// « Viandes crues », « Pâtes, riz et céréales » : la famille la plus
    /// précise connue, avec sa majuscule.
    static func famille(groupe: String?, sousGroupe: String?) -> String? {
        let brut = [sousGroupe, groupe].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "-" }
        guard let brut, let initiale = brut.first else { return nil }
        return initiale.uppercased() + brut.dropFirst()
    }

    /// « Barilla · 359 kcal / 100 g » ; « Viandes crues · 131 kcal / 100 g ».
    static func sousTitre(source: String, marque: String?, groupe: String?,
                          sousGroupe: String?, kcal100g: Double?) -> String {
        let tete: String
        if source == "off" {
            tete = marqueCourte(marque) ?? "Produit de marque"
        } else {
            tete = famille(groupe: groupe, sousGroupe: sousGroupe) ?? "Générique"
        }
        guard let kcal100g else { return tete }
        return "\(tete) · \(Int(kcal100g.rounded())) kcal / 100 g"
    }

    // MARK: Les sections

    struct Section<Ligne>: Identifiable {
        let id: String
        let titre: String
        let lignes: [Ligne]
    }

    static let titreAliments = "Aliments"
    static let titreProduits = "Produits de marque"

    /// Deux sections, chacune dans l'ordre du classement serveur. Celle qui
    /// porte le MEILLEUR résultat passe devant : chercher « nutella » ne doit
    /// pas faire défiler des génériques avant le pot.
    static func sections<Ligne>(_ lignes: [Ligne], source: (Ligne) -> String,
                                score: (Ligne) -> Double?) -> [Section<Ligne>] {
        let aliments = lignes.filter { source($0) != "off" }
        let produits = lignes.filter { source($0) == "off" }
        var sortie: [Section<Ligne>] = []
        if !aliments.isEmpty { sortie.append(Section(id: "aliments", titre: titreAliments, lignes: aliments)) }
        if !produits.isEmpty { sortie.append(Section(id: "produits", titre: titreProduits, lignes: produits)) }
        guard sortie.count == 2,
              let meilleurAliment = aliments.compactMap(score).max(),
              let meilleurProduit = produits.compactMap(score).max(),
              meilleurProduit > meilleurAliment else { return sortie }
        return sortie.reversed()
    }
}
