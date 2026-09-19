import Foundation

// MARK: - Formulations du brief et des rappels (19 sept. 2026)
//
// TOUTES les phrases dites à l'utilisateur par le brief du jour et les rappels
// vivent ici. Une seule raison : la qualité ne doit pas dépendre de ce que le
// bilan a bien voulu remplir.
//
// Avant, quand le bilan ne fournissait ni aliments ni conseil pour un apport,
// les rappels retombaient sur « Note ton dîner : ta journée se complète. » —
// à côté d'un « Lentilles, boudin noir ou épinards ce midi ? » sur un autre
// apport. Même app, deux niveaux de soin. Retour d'Arthur du 19 sept. :
// « on peut avoir des résultats différents, mais toujours de la même qualité ».
//
// Trois garde-fous, tenus par `FormulationsTests` :
//   · chaque nutriment a TOUJOURS des aliments et une raison (repli écrit ici) ;
//   · trois formulations par intention, choisies par le jour : on varie sans
//     jamais tomber plus bas ;
//   · longueurs bornées — un titre qui déborde se fait couper par iOS.

// MARK: - Sources alimentaires (repli quand le bilan n'en donne pas)

enum SourcesAlimentaires {
    /// Trois aliments par nutriment, écrits pour être DITS dans une phrase
    /// (« Lentilles, boudin noir ou épinards ce midi ? »). Alignés sur les
    /// sources du guide des compléments, mais découpés en éléments courts :
    /// « viande (ou aliments enrichis si régime végétal) » ne se dit pas.
    static let parNutriment: [String: [String]] = [
        "vitD": ["Saumon", "Sardines", "Jaune d'œuf"],
        "vitB12": ["Œufs", "Poisson", "Produits laitiers"],
        "iron": ["Lentilles", "Boudin noir", "Épinards"],
        "magnesium": ["Amandes", "Chocolat noir", "Légumes verts"],
        "omega3": ["Sardines", "Noix", "Graines de lin"],
        "vitC": ["Kiwi", "Poivron", "Agrumes"],
        "calcium": ["Yaourt", "Amandes", "Légumes verts"],
        "zinc": ["Graines de courge", "Viande", "Légumineuses"],
        "iodine": ["Poisson", "Algues", "Sel iodé"],
        "fiber": ["Légumineuses", "Céréales complètes", "Fruits"],
    ]

    /// Les aliments du BILAN s'ils existent (ils sont personnalisés), sinon le
    /// repli ci-dessus. Ne rend jamais une liste vide pour un nutriment connu.
    static func pour(id: String, duBilan: [String]) -> [String] {
        let propres = duBilan
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !propres.isEmpty { return Array(propres.prefix(3)) }
        return parNutriment[id] ?? []
    }

    /// Longueur totale au-delà de laquelle l'énumération fait déborder une
    /// notification. Le bilan écrit parfois « Foie de morue en conserve » trois
    /// fois : on garde alors moins d'aliments plutôt qu'un message coupé par
    /// iOS au milieu d'un mot.
    static let longueurMaxEnumeration = 58

    /// La liste ramenée à ce qui tient dans une notification — au moins un
    /// aliment tant qu'il y en a un.
    static func ajustes(_ aliments: [String]) -> [String] {
        var gardes: [String] = []
        var longueur = 0
        for aliment in aliments {
            let cout = aliment.count + (gardes.isEmpty ? 0 : 4) // « , » ou « ou »
            if !gardes.isEmpty && longueur + cout > longueurMaxEnumeration { break }
            gardes.append(aliment)
            longueur += cout
        }
        return gardes
    }
}

// MARK: - Raison courte (pourquoi cet apport compte)

enum RaisonNutriment {
    /// Une phrase par nutriment, écrite à la main : courte, concrète, sans
    /// promesse de santé. Sert de dernier recours quand le bilan n'a pas de
    /// conseil à donner — pour ne jamais tomber sur une phrase creuse.
    /// ⚠️ 60 caractères maximum : ces phrases sont suivies d'une énumération
    /// d'aliments dans la même notification (cf. `FormulationsTests`).
    static let longueurMax = 60

    static let parNutriment: [String: String] = [
        "vitD": "La vitamine D se fabrique au soleil, rare en hiver.",
        "vitB12": "La B12 ne vient que des produits animaux ou enrichis.",
        "iron": "Le fer, c'est ton énergie de la journée.",
        "magnesium": "Le magnésium part vite quand la semaine est chargée.",
        "omega3": "Les oméga-3 viennent surtout des poissons gras.",
        "vitC": "La vitamine C ne se stocke pas, elle se refait chaque jour.",
        "calcium": "Le calcium se joue sur la régularité, pas sur un à-coup.",
        "zinc": "Le zinc se trouve côté viandes, graines et légumineuses.",
        "iodine": "L'iode vient de la mer, et du sel iodé.",
        "fiber": "Les fibres nourrissent ton microbiote, et elles calent.",
    ]

    static func pour(_ id: String) -> String? { parNutriment[id] }
}

// MARK: - Formulations des rappels

/// Un rappel écrit : titre + corps. Les variantes tournent avec le jour, pour
/// qu'une semaine de rappels ne soit pas sept fois la même phrase.
enum FormulationsRappel {

    static func indexVariante(jour: Int, parmi total: Int) -> Int {
        guard total > 0 else { return 0 }
        return ((jour % total) + total) % total
    }

    /// Les aliments d'une cible, prêts à être dits et taillés pour tenir dans
    /// une notification. Vide seulement pour un nutriment hors catalogue.
    static func aliments(de cible: CibleNutritionnelle) -> String {
        NomNutriment.enumeration(SourcesAlimentaires.ajustes(cible.alimentsAffichables))
    }

    /// Une phrase se termine. Le conseil vient du bilan, rédigé par le
    /// serveur : il lui arrive de ne pas porter de point final.
    static func termine(_ phrase: String) -> String {
        let propre = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let derniere = propre.last else { return propre }
        return ".?!".contains(derniere) ? propre : propre + "."
    }

    // MARK: Midi

    /// - Parameter manqueHier: part du besoin NON couverte hier (0-100), quand
    ///   on la connaît — seulement pour aujourd'hui, « hier » n'est pas encore
    ///   écrit pour les jours suivants.
    static func midi(cible: CibleNutritionnelle, jour: Int, manqueHier: Int?) -> (titre: String, corps: String) {
        let aliments = aliments(de: cible)
        // Nutriment hors catalogue (ne devrait pas arriver : les cibles sont
        // filtrées sur `NutrientData`) — on reste utile plutôt que bancal.
        guard !aliments.isEmpty else { return midiSansBilan(jour: jour) }

        let variantes = [
            "\(aliments) ce midi ? Scanne ton assiette.",
            "\(aliments) au déjeuner, et ça remonte. Scanne ton assiette.",
            "Au menu du midi : \(NomNutriment.minusculeInitiale(aliments)). Scanne ton assiette.",
        ]
        var corps = ""
        if let manqueHier, manqueHier > 0 {
            corps = "Hier, il t'en a manqué \(manqueHier) %. "
        }
        corps += variantes[indexVariante(jour: jour, parmi: variantes.count)]
        return ("C'est le moment de renforcer \(cible.avecPossessif)", corps)
    }

    // MARK: Soir

    /// Le conseil du bilan passe devant quand il existe : il est personnalisé.
    /// Sinon les aliments, sinon la raison — jamais une phrase vide de sens.
    /// Longueur en dessous de laquelle le conseil du bilan ne se suffit pas :
    /// « Avec un filet de citron. » seul ne dit pas quoi manger. On l'accroche
    /// alors aux aliments au lieu de le servir nu.
    static let conseilAutoportantMin = 35

    static func soir(cible: CibleNutritionnelle, jour: Int) -> (titre: String, corps: String) {
        let aliments = aliments(de: cible)
        guard !aliments.isEmpty else { return soirSansBilan(jour: jour) }

        // Le conseil vient du serveur (contrat : 55 caractères). Au-delà de
        // 120 il ferait déborder la notification : on s'en passe plutôt que
        // de le faire couper au milieu.
        let conseil = cible.conseil.map(termine).flatMap { $0.count <= 120 ? $0 : nil }
        var variantes: [String] = []
        // Le conseil du bilan d'abord : c'est le seul texte personnalisé.
        if let conseil {
            variantes.append(
                conseil.count >= conseilAutoportantMin
                    ? conseil
                    : "\(aliments) au dîner ? \(conseil)"
            )
        }
        variantes.append("\(aliments) au dîner ? Ta journée se complète.")
        if let raison = RaisonNutriment.pour(cible.id) {
            // Deux phrases : l'énumération reprend donc la majuscule.
            variantes.append("\(raison) \(aliments) ce soir ?")
        } else {
            variantes.append("Un dîner avec \(NomNutriment.minusculeInitiale(aliments)), et la journée est complète.")
        }
        return (
            "Ce soir, pense à \(cible.avecPossessif)",
            variantes[indexVariante(jour: jour, parmi: variantes.count)]
        )
    }

    // MARK: Brief du matin

    static func briefDuMatin(jour: Int) -> (titre: String, corps: String) {
        let variantes = [
            "Ce qui t'a manqué hier, et ce sur quoi miser aujourd'hui.",
            "Ta veille en un coup d'œil, et ta priorité du jour.",
            "Deux chiffres sur hier, une idée pour aujourd'hui.",
        ]
        return ("Ton brief du jour est prêt", variantes[indexVariante(jour: jour, parmi: variantes.count)])
    }

    // MARK: Retour après une semaine sans ouvrir

    static func retour(cible: CibleNutritionnelle?) -> (titre: String, corps: String) {
        guard let cible else {
            return ("Ton suivi t'attend",
                    "Une semaine sans nouvelles : un repas noté suffit à le relancer.")
        }
        return (
            "\(NomNutriment.majusculeInitiale(cible.avecPossessif)) t'attend",
            "Une semaine sans nouvelles : un repas noté suffit à relancer ton suivi."
        )
    }

    // MARK: Sans bilan (l'utilisateur n'a pas encore fait son questionnaire)

    static func midiSansBilan(jour: Int) -> (titre: String, corps: String) {
        let variantes = [
            "Scanne ton assiette, Kiwio s'occupe de l'analyse.",
            "Une photo de ton déjeuner, et tu sais ce qu'il t'apporte.",
            "Ton déjeuner en une photo : Kiwio fait le reste.",
        ]
        return ("Photographie ton repas", variantes[indexVariante(jour: jour, parmi: variantes.count)])
    }

    static func soirSansBilan(jour: Int) -> (titre: String, corps: String) {
        let variantes = [
            "Note ton dîner : ta journée se complète.",
            "Un dîner noté, et ta journée est complète.",
            "Ton dîner en une photo, et la journée est bouclée.",
        ]
        return ("Et ce soir, qu'y a-t-il au menu ?", variantes[indexVariante(jour: jour, parmi: variantes.count)])
    }
}
