import Foundation

// MARK: - Quantités en unités (œuf, banane, tranche, pot…)
//
// Personne ne pèse un œuf : on en mange un, petit, moyen ou gros. Ce catalogue
// traduit le NOM d'un aliment en unité humaine (singulier, pluriel, poids d'une
// unité, variantes de taille) pour que la question de quantité se pose en
// unités et non en grammes, partout où elle se pose : dictée vocale, recherche,
// code-barres, édition d'une ligne du journal.
//
// La valeur ENREGISTRÉE reste le grammage : rien ne change côté serveur ni dans
// le journal, seule la saisie est traduite (nombre × poids d'une unité).
//
// Deux sources, dans cet ordre :
//   1. le catalogue ci-dessous — poids moyens usuels, alignés sur la table
//      `PORTION_PIECE_DEFAUT` de l'edge function parse-meal-voice ;
//   2. à défaut, la portion « 1 … » renvoyée par la base (`get_food`) ou par le
//      serveur vocal (« 1 unité » quand le modèle a estimé le poids d'une pièce).
//      Elle gagne aussi sur les entrées GÉNÉRIQUES du catalogue (« portion de
//      viande ») : « 1 unité » de cœur de canard vaut mieux qu'une portion.
// Sans l'une ni l'autre, la saisie reste en grammes, comme avant.

enum UnitPortionCatalog {

    struct Taille: Equatable, Hashable {
        /// Libellé déjà accordé : « Petit », « Moyenne », « Grosse », « Grand »…
        let libelle: String
        let grammes: Double
    }

    struct Unite: Equatable {
        let singulier: String
        let pluriel: String
        /// Poids d'une unité « normale » (la taille du milieu quand il y en a).
        let grammes: Double
        /// Variantes de taille proposées en chips ; vide = on compte seulement.
        let tailles: [Taille]

        /// Index de la taille proposée d'office (celle du milieu).
        var tailleParDefaut: Int? { tailles.isEmpty ? nil : tailles.count / 2 }

        func poids(taille index: Int?) -> Double {
            guard let index, tailles.indices.contains(index) else { return grammes }
            return tailles[index].grammes
        }

        /// « 1 œuf », « 2 œufs », « 1,5 banane » — le pluriel commence à 2.
        func libelle(nombre: Double) -> String {
            "\(UnitPortionCatalog.formater(nombre)) \(nombre >= 2 ? pluriel : singulier)"
        }

        /// « Combien d'œufs ? », « Combien de tranches ? »
        var question: String {
            // Élision devant voyelle ou h muet (« d'œufs », « d'huîtres ») ;
            // « hot-dogs » garde son h aspiré.
            let initiale = pluriel.first.map { String($0).lowercased() } ?? ""
            let elision = !initiale.isEmpty && "aeiouyhœ".contains(initiale) && !pluriel.hasPrefix("hot")
            return elision ? "Combien d'\(pluriel) ?" : "Combien de \(pluriel) ?"
        }

        /// « Compter en œufs » — lien pour revenir aux unités depuis les grammes.
        var lienCompter: String { "Compter en \(pluriel)" }
    }

    // MARK: - Résolution

    /// Unité pour un aliment, d'après son nom puis, à défaut, les portions
    /// renvoyées par le serveur (`label` « 1 … », `grammes`).
    static func unite(pourNom nom: String,
                      portions: [(label: String, grammes: Double)] = []) -> Unite? {
        let norme = normaliser(nom)
        if !norme.isEmpty {
            for entree in entrees where norme.contains(entree.motif) {
                if let sauf = entree.sauf, norme.contains(sauf) { continue }
                if entree.generique, let serveur = uniteServeur(portions) { return serveur }
                return entree.unite
            }
        }
        return uniteServeur(portions)
    }

    /// Nombre d'unités pour un grammage, arrondi au demi (« 1,5 banane »).
    static func nombre(grammes: Double, poidsUnite: Double) -> Double {
        guard poidsUnite > 0, grammes > 0 else { return 0 }
        return (grammes / poidsUnite * 2).rounded() / 2
    }

    /// Nombre suivant au pas de 1 : 1,5 → 2 en montant, → 1 en descendant ;
    /// jamais sous 1 (pour retirer l'aliment, il y a « Retirer »).
    static func nombreSuivant(_ actuel: Double, delta: Int) -> Double {
        if delta > 0 { return max(1, actuel.rounded(.down) + 1) }
        return max(1, actuel.rounded(.up) - 1)
    }

    /// « 1 », « 2 », « 1,5 » (virgule française, une décimale au plus).
    static func formater(_ nombre: Double) -> String {
        formateur.string(from: NSNumber(value: nombre)) ?? "\(nombre)"
    }

    private static let formateur: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        f.usesGroupingSeparator = false
        return f
    }()

    // MARK: - Repli serveur : la portion « 1 … »

    private static func uniteServeur(_ portions: [(label: String, grammes: Double)]) -> Unite? {
        for p in portions where p.grammes > 0 {
            let label = p.label.trimmingCharacters(in: .whitespaces)
            guard label.hasPrefix("1 ") else { continue }
            var nomUnite = String(label.dropFirst(2))
            if let parenthese = nomUnite.firstIndex(of: "(") {
                nomUnite = String(nomUnite[..<parenthese])
            }
            nomUnite = nomUnite.trimmingCharacters(in: .whitespaces).lowercased()
            // « 1 g », « 1 ml » : ce n'est pas une unité humaine.
            guard nomUnite.count > 2, !["g", "ml", "cl", "kg"].contains(nomUnite) else { continue }
            return Unite(singulier: nomUnite,
                         pluriel: pluriel(de: nomUnite),
                         grammes: p.grammes,
                         tailles: [])
        }
        return nil
    }

    /// Pluriel du premier mot seulement : « tranche de pain » → « tranches de
    /// pain », « morceau » → « morceaux », « radis » → « radis ».
    static func pluriel(de singulier: String) -> String {
        var mots = singulier.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let premier = mots.first, !premier.isEmpty else { return singulier }
        if let dernier = premier.last, "sxz".contains(dernier) {
            return singulier
        }
        if premier.hasSuffix("eau") || premier.hasSuffix("au") || premier.hasSuffix("eu") {
            mots[0] = premier + "x"
        } else if premier.hasSuffix("al") {
            mots[0] = String(premier.dropLast(2)) + "aux"
        } else {
            mots[0] = premier + "s"
        }
        return mots.joined(separator: " ")
    }

    // MARK: - Normalisation du nom

    /// Minuscules, sans accents, « œ » → « oe » : les motifs sont écrits dans
    /// cet alphabet, les noms CIQUAL (« Œuf, dur ») comme OFF y tombent.
    static func normaliser(_ nom: String) -> String {
        nom.replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "Œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
    }

    // MARK: - Catalogue

    private struct Entree {
        let motif: Regex<AnyRegexOutput>
        let sauf: Regex<AnyRegexOutput>?
        let generique: Bool
        let unite: Unite
    }

    private static func tailles(_ libelles: (String, String, String),
                                _ petite: Double, _ moyenne: Double, _ grande: Double) -> [Taille] {
        [Taille(libelle: libelles.0, grammes: petite),
         Taille(libelle: libelles.1, grammes: moyenne),
         Taille(libelle: libelles.2, grammes: grande)]
    }

    // Accords : une pièce est petite/moyenne/grosse, un contenant petit/moyen/grand.
    private static let pieceM = ("Petit", "Moyen", "Gros")
    private static let pieceF = ("Petite", "Moyenne", "Grosse")
    private static let contenantM = ("Petit", "Moyen", "Grand")
    private static let contenantF = ("Petite", "Moyenne", "Grande")

    private static let entrees: [Entree] = definitions.compactMap { d in
        guard let motif = try? Regex(d.motif) else {
            assertionFailure("UnitPortionCatalog : motif invalide « \(d.motif) »")
            return nil
        }
        let sauf = d.sauf.flatMap { try? Regex($0) }
        return Entree(motif: motif, sauf: sauf, generique: d.generique,
                      unite: Unite(singulier: d.singulier, pluriel: d.pluriel,
                                   grammes: d.grammes, tailles: d.tailles))
    }

    private struct Definition {
        let motif: String
        var sauf: String? = nil
        let singulier: String
        let pluriel: String
        let grammes: Double
        var tailles: [Taille] = []
        /// Entrée « filet de sécurité » (portion de viande, de poisson) : la
        /// portion « 1 … » du serveur, plus précise, passe devant.
        var generique = false
    }

    /// Motifs écrits dans l'alphabet normalisé (minuscules, sans accents).
    /// ORDRE = PRIORITÉ : le premier motif qui correspond gagne. D'où les
    /// sections : les plats composés avant leurs ingrédients (« sandwich au
    /// fromage » avant « fromage », « pâtes à la sauce tomate » avant « sauce »
    /// avant « tomate »), les cas particuliers avant les génériques (« pomme de
    /// terre » avant « pomme », « chocolat chaud » avant « chocolat »).
    private static let definitions: [Definition] = [
        // ── 1. Œufs ──────────────────────────────────────────────────────
        .init(motif: #"oeufs? de (lump|saumon|truite|poisson|cabillaud)"#, singulier: "cuillère", pluriel: "cuillères", grammes: 15),
        .init(motif: #"oeufs? de caille"#, singulier: "œuf de caille", pluriel: "œufs de caille", grammes: 10),
        .init(motif: #"jaune d'oeuf|oeuf.*\bjaune\b"#, singulier: "jaune d'œuf", pluriel: "jaunes d'œuf", grammes: 18),
        .init(motif: #"blanc d'oeuf|oeuf.*\bblanc\b"#, singulier: "blanc d'œuf", pluriel: "blancs d'œuf", grammes: 33),
        .init(motif: #"omelette"#, singulier: "omelette", pluriel: "omelettes", grammes: 120, tailles: tailles(pieceF, 60, 120, 180)),
        .init(motif: #"\boeufs?\b"#, singulier: "œuf", pluriel: "œufs", grammes: 50, tailles: tailles(pieceM, 42, 50, 60)),

        // ── 2. Boissons ──────────────────────────────────────────────────
        .init(motif: #"expresso|espresso|ristretto"#, singulier: "expresso", pluriel: "expressos", grammes: 60),
        .init(motif: #"\bcafes?\b|cappuccino|\blatte\b|macchiato"#, singulier: "tasse", pluriel: "tasses", grammes: 200, tailles: tailles(contenantF, 120, 200, 300)),
        .init(motif: #"\bthes?\b|infusions?|tisanes?|rooibos|\bmate\b"#, singulier: "tasse", pluriel: "tasses", grammes: 200, tailles: tailles(contenantF, 150, 200, 300)),
        .init(motif: #"chocolat chaud|chocolat a boire"#, singulier: "tasse", pluriel: "tasses", grammes: 200, tailles: tailles(contenantF, 150, 200, 300)),
        .init(motif: #"chocolat en poudre|cacao|nesquik|poudre chocolatee|ovomaltine"#, singulier: "cuillère", pluriel: "cuillères", grammes: 10),
        .init(motif: #"canettes?|\bsodas?\b|\bcola\b|\bcoca\b|limonade|energy|red bull|monster|ice tea|the glace|orangina|fanta|sprite|schweppes|tonic"#, singulier: "canette", pluriel: "canettes", grammes: 330),
        .init(motif: #"\bbieres?\b"#, singulier: "verre", pluriel: "verres", grammes: 250, tailles: tailles(("Demi", "Bouteille", "Pinte"), 250, 330, 500)),
        .init(motif: #"\bvins?\b|champagne|prosecco|cremant|\bcidre\b"#, singulier: "verre", pluriel: "verres", grammes: 120, tailles: tailles(contenantM, 100, 120, 150)),
        .init(motif: #"\bjus\b|\bnectar\b|smoothie"#, singulier: "verre", pluriel: "verres", grammes: 200, tailles: tailles(contenantM, 150, 200, 300)),
        .init(motif: #"^lait\b|\blait (entier|demi|ecreme|cru|de (chevre|brebis|vache|soja|coco|riz|amande|avoine)|d'amande|d'avoine)|boisson vegetale|boisson (au|a la) soja"#, singulier: "verre", pluriel: "verres", grammes: 200, tailles: tailles(contenantM, 150, 200, 300)),
        .init(motif: #"^eaux?\b|eau (gazeuse|minerale|plate|de source|petillante)"#, singulier: "verre", pluriel: "verres", grammes: 200, tailles: tailles(contenantM, 150, 200, 500)),
        .init(motif: #"\bsoupes?\b|veloute|potage|gaspacho|bouillon"#, singulier: "bol", pluriel: "bols", grammes: 250, tailles: tailles(contenantM, 200, 250, 350)),

        // ── 3. Desserts, parts sucrées, laitages ─────────────────────────
        .init(motif: #"quiches?|tarte (salee|aux legumes|au thon|lorraine|aux poireaux|a l'oignon)|flammekueche|tarte flambee|\btourtes?\b"#, singulier: "part", pluriel: "parts", grammes: 120, tailles: tailles(contenantF, 90, 120, 180)),
        .init(motif: #"tiramisu|cheesecake|fraisier|foret noire|\bbuche\b"#, singulier: "part", pluriel: "parts", grammes: 120, tailles: tailles(contenantF, 80, 120, 180)),
        .init(motif: #"\btartes?\b|gateaux?|\bcakes?\b|brownie|fondant|moelleux|clafoutis|far breton|quatre-quarts|\bmarbre\b|paris-brest|eclairs?|mille-?feuille|religieuse"#, sauf: #"gateaux? secs?|aperitif"#, singulier: "part", pluriel: "parts", grammes: 100, tailles: tailles(contenantF, 70, 100, 150)),
        .init(motif: #"creme dessert|danette|creme brulee|creme caramel|\bflan\b|liegeois|panna cotta|riz au lait|semoule au lait|ile flottante|\bmousse\b"#, singulier: "pot", pluriel: "pots", grammes: 110),
        .init(motif: #"creme glacee|\bglaces?\b|sorbet"#, sauf: #"sucre glace"#, singulier: "boule", pluriel: "boules", grammes: 60),
        .init(motif: #"magnum|cornetto|esquimau|batonnet glace|mister freeze"#, singulier: "pièce", pluriel: "pièces", grammes: 90),
        .init(motif: #"petits?-suisses?|petit suisse"#, singulier: "petit-suisse", pluriel: "petits-suisses", grammes: 60),
        .init(motif: #"yaourts?|yogourt|\bskyr\b|fromage blanc|faisselle|activia"#, singulier: "pot", pluriel: "pots", grammes: 125, tailles: tailles(contenantM, 100, 125, 150)),
        .init(motif: #"compotes?|gourde"#, singulier: "pot", pluriel: "pots", grammes: 100),

        // ── 4. Pain, viennoiseries, biscuits, céréales ───────────────────
        .init(motif: #"baguette|ficelle"#, singulier: "morceau", pluriel: "morceaux", grammes: 60, tailles: tailles(contenantM, 40, 60, 125)),
        .init(motif: #"biscottes?|cracottes?|\bwasa\b|krisprolls|pain grille"#, singulier: "biscotte", pluriel: "biscottes", grammes: 10),
        .init(motif: #"croissants?"#, singulier: "croissant", pluriel: "croissants", grammes: 60),
        .init(motif: #"pain au chocolat|chocolatine|pain aux raisins|chausson|viennoiserie"#, singulier: "pièce", pluriel: "pièces", grammes: 65),
        .init(motif: #"brioche"#, singulier: "tranche", pluriel: "tranches", grammes: 35),
        .init(motif: #"\btoasts?\b|\btartines?\b"#, singulier: "tartine", pluriel: "tartines", grammes: 40),
        .init(motif: #"pain (de mie|complet|de campagne|aux cereales|de seigle|au levain|d'epices|perdu|pita|naan)|\bpita\b|\bnaan\b|tranches? de pain|\bpains?\b"#, sauf: #"pains? (au|aux|de poisson|de viande)"#, singulier: "tranche", pluriel: "tranches", grammes: 30, tailles: tailles(contenantF, 20, 30, 45)),
        .init(motif: #"\bcrepes?\b|galette bretonne|galette de sarrasin"#, singulier: "crêpe", pluriel: "crêpes", grammes: 60),
        .init(motif: #"pancakes?"#, singulier: "pancake", pluriel: "pancakes", grammes: 40),
        .init(motif: #"\bblinis?\b"#, singulier: "blini", pluriel: "blinis", grammes: 15),
        .init(motif: #"\bgaufres?\b"#, singulier: "gaufre", pluriel: "gaufres", grammes: 60),
        .init(motif: #"madeleines?"#, singulier: "madeleine", pluriel: "madeleines", grammes: 20),
        .init(motif: #"financiers?|canneles?"#, singulier: "pièce", pluriel: "pièces", grammes: 30),
        .init(motif: #"\bmacarons?\b"#, singulier: "macaron", pluriel: "macarons", grammes: 15),
        .init(motif: #"muffins?"#, singulier: "muffin", pluriel: "muffins", grammes: 70),
        .init(motif: #"donuts?|beignets?"#, singulier: "beignet", pluriel: "beignets", grammes: 60),
        .init(motif: #"cookies?"#, singulier: "cookie", pluriel: "cookies", grammes: 20),
        .init(motif: #"biscuits?|petit beurre|petit-beurre|\bsables?\b|speculoos|\bbn\b|\bprince\b|\boreo\b|gateau sec|palmiers?|boudoirs?|langues de chat|petits? ecoliers?"#, singulier: "biscuit", pluriel: "biscuits", grammes: 12),
        .init(motif: #"barres? (de |aux )?cereales|barre chocolatee|barre proteinee|barres? prot|kinder bueno|\btwix\b|\bmars\b|snickers|kitkat|kit kat|bounty|\blion\b"#, singulier: "barre", pluriel: "barres", grammes: 35),
        .init(motif: #"porridge"#, singulier: "bol", pluriel: "bols", grammes: 250, tailles: tailles(contenantM, 180, 250, 350)),
        .init(motif: #"cereales|muesli|corn ?flakes|chocapic|miel pops|frosties|special k|flocons d'avoine|\bgranola\b"#, singulier: "bol", pluriel: "bols", grammes: 40, tailles: tailles(contenantM, 30, 40, 60)),
        .init(motif: #"carres? de chocolat|\bchocolat\b"#, singulier: "carré", pluriel: "carrés", grammes: 5),
        .init(motif: #"bonbons?|haribo|dragibus|tagada|carambar|sucettes?"#, singulier: "bonbon", pluriel: "bonbons", grammes: 5),

        // ── 5. Plats composés (avant leurs ingrédients) ──────────────────
        .init(motif: #"pizzas?"#, singulier: "part", pluriel: "parts", grammes: 100, tailles: tailles(contenantF, 80, 100, 150)),
        .init(motif: #"lasagnes?|moussaka|gratin|hachis parmentier|parmentier"#, singulier: "part", pluriel: "parts", grammes: 250, tailles: tailles(contenantF, 180, 250, 350)),
        .init(motif: #"burgers?|hamburger|cheeseburger|big mac|whopper"#, singulier: "burger", pluriel: "burgers", grammes: 200),
        .init(motif: #"sandwichs?|sandwiches|paninis?|croque-?monsieur|croque-?madame|\bcroque\b|jambon-beurre"#, singulier: "sandwich", pluriel: "sandwichs", grammes: 200),
        .init(motif: #"kebab|doner|durum"#, singulier: "kebab", pluriel: "kebabs", grammes: 300),
        .init(motif: #"\btacos\b"#, singulier: "tacos", pluriel: "tacos", grammes: 350),
        .init(motif: #"\bwraps?\b|burritos?|fajitas?|quesadilla"#, singulier: "pièce", pluriel: "pièces", grammes: 200),
        .init(motif: #"hot-?dogs?"#, singulier: "hot-dog", pluriel: "hot-dogs", grammes: 150),
        .init(motif: #"sushis?|makis?|california|sashimi|nigiri"#, singulier: "pièce", pluriel: "pièces", grammes: 25),
        .init(motif: #"\bnems?\b|rouleaux? de printemps|samoussas?|samosas?"#, singulier: "pièce", pluriel: "pièces", grammes: 40),
        .init(motif: #"falafels?|boulettes?|keftas?|accras?"#, singulier: "pièce", pluriel: "pièces", grammes: 30),
        .init(motif: #"nuggets?"#, singulier: "nugget", pluriel: "nuggets", grammes: 20),
        .init(motif: #"cordon bleu"#, singulier: "pièce", pluriel: "pièces", grammes: 100),
        .init(motif: #"batonnets? de poisson|poisson pane|croquettes?"#, singulier: "bâtonnet", pluriel: "bâtonnets", grammes: 30),

        // ── 6. Fromages, charcuterie, viandes, poissons ──────────────────
        .init(motif: #"babybel|\bkiri\b|vache qui rit|apericube|fromage fondu|portion de fromage"#, singulier: "portion", pluriel: "portions", grammes: 20),
        .init(motif: #"camembert|\bbrie\b|coulommiers|\bbleu\b|roquefort|fourme|gorgonzola|chevre|comte|emmental|gruyere|beaufort|gouda|\bedam\b|cheddar|mimolette|cantal|reblochon|tomme|raclette|morbier|saint-nectaire|munster|parmesan|mozzarella|\bfeta\b|ricotta|mascarpone|boursin|saint-moret|\bfromages?\b"#, singulier: "part", pluriel: "parts", grammes: 30, tailles: tailles(contenantF, 20, 30, 45)),
        .init(motif: #"saucisses?|merguez|chipolatas?|knacks?|francfort|strasbourg|\bboudin\b"#, singulier: "saucisse", pluriel: "saucisses", grammes: 50),
        .init(motif: #"saucisson|chorizo|rosette|salami|\bcoppa\b|mortadelle"#, singulier: "tranche", pluriel: "tranches", grammes: 8),
        .init(motif: #"jambon (cru|sec|serrano|de bayonne|de parme|iberique)|prosciutto|\bspeck\b|bresaola|viande des grisons"#, singulier: "tranche", pluriel: "tranches", grammes: 15),
        .init(motif: #"\bjambon\b|roti de (porc|dinde|poulet)"#, singulier: "tranche", pluriel: "tranches", grammes: 40),
        .init(motif: #"\bbacon\b|poitrine fumee"#, singulier: "tranche", pluriel: "tranches", grammes: 15),
        .init(motif: #"steaks? haches?|\bsteak\b|entrecote|bavette|rumsteck|faux-filet|pave de (boeuf|rumsteck)|viande hachee|boeuf hache"#, singulier: "steak", pluriel: "steaks", grammes: 120, tailles: tailles(pieceM, 100, 120, 150)),
        .init(motif: #"escalopes?"#, singulier: "escalope", pluriel: "escalopes", grammes: 130, tailles: tailles(pieceF, 100, 130, 170)),
        .init(motif: #"blanc de (poulet|dinde)|filet de (poulet|dinde)|poulet.*\bblanc\b|poulet.*\bfilet\b|dinde.*\bfilet\b"#, singulier: "filet", pluriel: "filets", grammes: 150, tailles: tailles(pieceM, 100, 150, 200)),
        .init(motif: #"cuisses? de poulet|haut de cuisse|\bcuisses?\b"#, singulier: "cuisse", pluriel: "cuisses", grammes: 150),
        .init(motif: #"pilons?"#, singulier: "pilon", pluriel: "pilons", grammes: 80),
        .init(motif: #"ailes? de poulet|\bwings\b"#, singulier: "aile", pluriel: "ailes", grammes: 40),
        .init(motif: #"cotes? (de porc|d'agneau|de veau)|cotelettes?"#, singulier: "côte", pluriel: "côtes", grammes: 120, tailles: tailles(pieceF, 90, 120, 160)),
        .init(motif: #"thon (en boite|au naturel|a l'huile)|sardines? (en boite|a l'huile)|maquereau en boite|boite de thon"#, singulier: "boîte", pluriel: "boîtes", grammes: 100),
        .init(motif: #"sardines?"#, singulier: "sardine", pluriel: "sardines", grammes: 25),
        .init(motif: #"crevettes?|gambas|langoustines?"#, singulier: "crevette", pluriel: "crevettes", grammes: 10),
        .init(motif: #"huitres?"#, singulier: "huître", pluriel: "huîtres", grammes: 15),
        .init(motif: #"pave de saumon|filet de (saumon|cabillaud|colin|lieu|merlu|truite|dorade|bar|sole|poisson)|\bdarne\b|\bsaumon\b|cabillaud|\bcolin\b|\blieu\b|\bmerlu\b|truite|dorade|daurade|\bsole\b|eglefin|haddock|\bthon\b"#, singulier: "pavé", pluriel: "pavés", grammes: 130, tailles: tailles(pieceM, 100, 130, 170)),

        // ── 7. Féculents, légumes cuisinés, apéritif ─────────────────────
        .init(motif: #"\bpates?\b|spaghetti|tagliatelle|\bpenne\b|fusilli|farfalle|macaroni|coquillettes?|linguine|raviolis?|gnocchis?|nouilles|\bramen\b|vermicelles"#, sauf: #"\bcru|feuilletee|brisee|sablee|a pizza|a tartiner|d'amande|de fruits|a sel|a crepes"#, singulier: "assiette", pluriel: "assiettes", grammes: 200, tailles: tailles(contenantF, 150, 200, 300)),
        .init(motif: #"\briz\b|risotto|paella|quinoa|boulgour|bulgur|semoule|couscous|polenta|\bebly\b"#, sauf: #"\bcru|\bsec\b|galette|gateau"#, singulier: "assiette", pluriel: "assiettes", grammes: 180, tailles: tailles(contenantF, 120, 180, 250)),
        .init(motif: #"\bfrites?\b"#, singulier: "portion", pluriel: "portions", grammes: 150, tailles: tailles(contenantF, 100, 150, 220)),
        .init(motif: #"\bpuree\b"#, singulier: "portion", pluriel: "portions", grammes: 200, tailles: tailles(contenantF, 150, 200, 300)),
        .init(motif: #"lentilles|pois chiches|haricots|flageolets|petits pois|\bfeves\b|edamame|ratatouille|poelee|epinards|brocolis?|choux?-?fleurs?|\blegumes?\b"#, sauf: #"\bcru|\bsec\b"#, singulier: "portion", pluriel: "portions", grammes: 150, tailles: tailles(contenantF, 100, 150, 220)),
        .init(motif: #"\bsalades?\b"#, singulier: "bol", pluriel: "bols", grammes: 150, tailles: tailles(contenantM, 100, 150, 250)),
        .init(motif: #"chips|doritos|pringles|popcorn|pop-corn|crackers?|\btuc\b|bretzels?|gressins|biscuits? aperitifs?|curly|monster munch"#, singulier: "poignée", pluriel: "poignées", grammes: 30),

        // ── 8. Tartinables, condiments (après les plats qui les contiennent) ─
        .init(motif: #"pate a tartiner|nutella"#, singulier: "cuillère", pluriel: "cuillères", grammes: 15),
        .init(motif: #"beurre de (cacahuete|cacahouete|cajou|amande|noix)|puree d'(amande|arachide|cacahuete|noisette)"#, singulier: "cuillère", pluriel: "cuillères", grammes: 15),
        .init(motif: #"confiture|\bmiel\b|sirop d'erable|marmelade|gelee de"#, singulier: "cuillère", pluriel: "cuillères", grammes: 20),
        .init(motif: #"\bbeurre\b|margarine"#, singulier: "noisette", pluriel: "noisettes", grammes: 10),
        .init(motif: #"\bhuiles?\b"#, singulier: "cuillère", pluriel: "cuillères", grammes: 10),
        .init(motif: #"sucre (en poudre|semoule|glace|roux|de canne)|cassonade|vergeoise"#, singulier: "cuillère", pluriel: "cuillères", grammes: 5),
        .init(motif: #"\bsucre\b"#, singulier: "morceau", pluriel: "morceaux", grammes: 5),
        .init(motif: #"\bsauces?\b|ketchup|mayonnaise|moutarde|vinaigrette|aioli|pesto|tzatziki|houmous|hummus|guacamole|tapenade|tarama"#, singulier: "cuillère", pluriel: "cuillères", grammes: 15),
        .init(motif: #"creme (fraiche|liquide|epaisse|fleurette|legere)"#, singulier: "cuillère", pluriel: "cuillères", grammes: 15),

        // ── 9. Oléagineux, fruits secs (poignée) ─────────────────────────
        .init(motif: #"amandes?|noisettes?|noix de cajou|\bcajou\b|pistaches?|cacahuetes?|cacahouetes?|arachides?|noix (du bresil|de pecan|de macadamia)|\bpecan\b|\bnoix\b|melange de (fruits secs|noix|graines)|graines de|raisins secs|fruits secs"#, singulier: "poignée", pluriel: "poignées", grammes: 30),

        // ── 10. Fruits, légumes à la pièce ───────────────────────────────
        .init(motif: #"patates? douces?"#, singulier: "patate douce", pluriel: "patates douces", grammes: 150, tailles: tailles(pieceF, 100, 150, 220)),
        .init(motif: #"pommes? de terre|patates?\b"#, singulier: "pomme de terre", pluriel: "pommes de terre", grammes: 120, tailles: tailles(pieceF, 80, 120, 180)),
        .init(motif: #"tomates? cerises?"#, singulier: "tomate cerise", pluriel: "tomates cerises", grammes: 15),
        .init(motif: #"\bpommes?\b"#, singulier: "pomme", pluriel: "pommes", grammes: 150, tailles: tailles(pieceF, 120, 150, 190)),
        .init(motif: #"\bbananes?\b"#, singulier: "banane", pluriel: "bananes", grammes: 120, tailles: tailles(pieceF, 90, 120, 150)),
        .init(motif: #"\bpoires?\b"#, singulier: "poire", pluriel: "poires", grammes: 150, tailles: tailles(pieceF, 120, 150, 190)),
        .init(motif: #"\boranges?\b"#, singulier: "orange", pluriel: "oranges", grammes: 150, tailles: tailles(pieceF, 120, 150, 190)),
        .init(motif: #"clementines?|mandarines?"#, singulier: "clémentine", pluriel: "clémentines", grammes: 70, tailles: tailles(pieceF, 50, 70, 90)),
        .init(motif: #"\bkiwis?\b"#, singulier: "kiwi", pluriel: "kiwis", grammes: 70, tailles: tailles(pieceM, 55, 70, 90)),
        .init(motif: #"\bpeches?\b"#, singulier: "pêche", pluriel: "pêches", grammes: 130, tailles: tailles(pieceF, 100, 130, 170)),
        .init(motif: #"nectarines?|brugnons?"#, singulier: "nectarine", pluriel: "nectarines", grammes: 130, tailles: tailles(pieceF, 100, 130, 170)),
        .init(motif: #"abricots?"#, singulier: "abricot", pluriel: "abricots", grammes: 45, tailles: tailles(pieceM, 35, 45, 60)),
        .init(motif: #"\bprunes?\b|mirabelles?|quetsches?|reine-claude"#, singulier: "prune", pluriel: "prunes", grammes: 35),
        .init(motif: #"pruneaux?"#, singulier: "pruneau", pluriel: "pruneaux", grammes: 10),
        .init(motif: #"\bdattes?\b"#, singulier: "datte", pluriel: "dattes", grammes: 8),
        .init(motif: #"\bfigues?\b"#, singulier: "figue", pluriel: "figues", grammes: 50),
        .init(motif: #"avocats?"#, singulier: "avocat", pluriel: "avocats", grammes: 130, tailles: tailles(pieceM, 100, 130, 170)),
        .init(motif: #"\btomates?\b"#, singulier: "tomate", pluriel: "tomates", grammes: 120, tailles: tailles(pieceF, 80, 120, 180)),
        .init(motif: #"carottes?"#, singulier: "carotte", pluriel: "carottes", grammes: 100, tailles: tailles(pieceF, 70, 100, 140)),
        .init(motif: #"courgettes?"#, singulier: "courgette", pluriel: "courgettes", grammes: 200, tailles: tailles(pieceF, 150, 200, 300)),
        .init(motif: #"\boignons?\b"#, singulier: "oignon", pluriel: "oignons", grammes: 100, tailles: tailles(pieceM, 60, 100, 150)),
        .init(motif: #"\bcitrons?\b"#, singulier: "citron", pluriel: "citrons", grammes: 80),
        .init(motif: #"\bmangues?\b"#, singulier: "mangue", pluriel: "mangues", grammes: 300),
        .init(motif: #"pamplemousses?|pomelos?"#, singulier: "pamplemousse", pluriel: "pamplemousses", grammes: 250),
        .init(motif: #"\bfraises?\b"#, singulier: "fraise", pluriel: "fraises", grammes: 15),
        .init(motif: #"\bradis\b"#, singulier: "radis", pluriel: "radis", grammes: 10),
        .init(motif: #"\bolives?\b"#, singulier: "olive", pluriel: "olives", grammes: 4),
        .init(motif: #"cornichons?"#, singulier: "cornichon", pluriel: "cornichons", grammes: 8),

        // ── 11. Génériques (filet de sécurité, en dernier) ───────────────
        .init(motif: #"\bpoulet\b|\bdinde\b|\bviande\b|\bboeuf\b|\bporc\b|\bagneau\b|\bveau\b|\bcanard\b|\blapin\b"#, singulier: "portion", pluriel: "portions", grammes: 120, tailles: tailles(contenantF, 90, 120, 180), generique: true),
        .init(motif: #"\bpoissons?\b"#, singulier: "portion", pluriel: "portions", grammes: 130, tailles: tailles(contenantF, 100, 130, 180), generique: true),
    ]
}
