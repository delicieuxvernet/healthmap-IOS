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
        // Mots exacts du règlement (UE) 432/2012 : une allégation de santé ne
        // se reformule pas (audit de conformité du 9 octobre 2026).
        "iron": "Le fer contribue à réduire la fatigue.",
        "magnesium": "Le magnésium part vite quand la semaine est chargée.",
        "omega3": "Les oméga-3 viennent surtout des poissons gras.",
        "vitC": "La vitamine C ne se stocke pas, elle se refait chaque jour.",
        "calcium": "Le calcium se joue sur la régularité, pas sur un à-coup.",
        "zinc": "Le zinc se trouve côté viandes, graines et légumineuses.",
        "iodine": "L'iode vient de la mer, et du sel iodé.",
        // Le règlement n'autorise aucune allégation pour « les fibres » en
        // général (seulement pour certaines, nommées) : on dit d'où elles viennent.
        "fiber": "Les fibres se trouvent surtout dans les végétaux.",
    ]

    static func pour(_ id: String) -> String? { parNutriment[id] }
}

// MARK: - Formulations des rappels
//
// Refonte du 1er oct. 2026 (demande d'Arthur, captures de Yazio à l'appui) :
// « très factuel et très aguicheur ». Yazio envoie huit rappels par jour, tous
// interchangeables (« Bien s'hydrater peut faire des merveilles pour la
// peau »). Kiwio sait ce que la personne a mangé, ce qu'elle a répondu, ce qui
// freine ses apports : chaque rappel OUVRE donc sur un fait à elle — un
// pourcentage tiré de ses repas notés, un compte de repas, des points du
// registre — et n'invente jamais un chiffre. Sans fait à dire, il se rabat sur
// l'ancienne formulation, sans chiffre.
//
// Le titre porte le fait (c'est lui qu'on lit sur l'écran verrouillé), le
// corps porte le geste.

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

    // MARK: Briques

    /// Au-delà, iOS coupe le corps sur l'écran verrouillé (`FormulationsTests`).
    static let corpsMax = 145

    /// « Ton fer », « Tes oméga-3 » — pour ouvrir une phrase ou un titre.
    static func sujet(_ cible: CibleNutritionnelle) -> String {
        NomNutriment.majusculeInitiale(cible.avecPossessif)
    }

    /// Le titre suivi de l'emoji canonique de l'apport.
    static func avecEmoji(_ titre: String, _ cible: CibleNutritionnelle) -> String {
        let emoji = cible.emoji
        return emoji.isEmpty ? titre : "\(titre) \(emoji)"
    }

    /// « ton fer est à », « tes fibres sont à ».
    static func estA(_ cible: CibleNutritionnelle) -> String {
        let verbe = NomNutriment.accord(id: cible.id, singulier: "est", pluriel: "sont")
        return "\(cible.avecPossessif) \(verbe) à"
    }

    /// « 1 repas noté », « 3 repas notés ».
    static func repasNotes(_ nombre: Int) -> String {
        nombre <= 1 ? "\(nombre) repas noté" : "\(nombre) repas notés"
    }

    /// « 1 besoin sur 10 couvert », « 6 besoins sur 10 couverts ».
    static func besoinsCouverts(_ nombre: Int) -> String {
        nombre <= 1 ? "\(nombre) besoin sur 10 couvert" : "\(nombre) besoins sur 10 couverts"
    }

    // MARK: Brief du matin

    /// Série à partir de laquelle on la dit : deux jours de suite ne font pas
    /// encore une habitude.
    static let serieMin = 3

    /// Le brief quand on NE SAIT PAS ce qui a été noté la veille (journal
    /// illisible au moment de planifier) : aucune affirmation, aucun chiffre.
    static func briefDuMatin(jour: Int) -> (titre: String, corps: String) {
        let variantes = [
            "Ce qui t'a manqué hier, et ce sur quoi miser aujourd'hui.",
            "Ta veille en un coup d'œil, et ta priorité du jour.",
            "Deux chiffres sur hier, une idée pour aujourd'hui.",
        ]
        return ("Ton brief du jour est prêt", variantes[indexVariante(jour: jour, parmi: variantes.count)])
    }

    /// Le brief chiffré.
    /// - Parameters:
    ///   - repasHier: repas notés la veille.
    ///   - couvertsHier: besoins (sur 10) couverts la veille ; `nil` = trop
    ///     peu noté pour qu'un chiffre veuille dire quelque chose.
    ///   - plusBas: l'apport à travailler le plus bas la veille, et sa part
    ///     couverte.
    ///   - serie: la série affichée dans l'app, veille comprise ; 0 quand on
    ///     ne la connaît pas.
    static func brief(
        repasHier: Int,
        couvertsHier: Int?,
        plusBas: (cible: CibleNutritionnelle, pourcent: Int)?,
        serie: Int,
        jour: Int
    ) -> (titre: String, corps: String) {
        guard let couvertsHier else {
            if repasHier == 1 {
                return ("Ton brief du jour est prêt",
                        "1 seul repas noté hier : trop peu pour un vrai chiffre. Note ton petit-déjeuner, et demain il parle.")
            }
            let variantes = [
                "Rien de noté hier, donc pas de chiffre ce matin. Note ton petit-déjeuner : demain, ton brief aura quelque chose à dire.",
                "Pas de repas noté hier. Une photo de ton petit-déjeuner, et ton brief repart demain.",
                "Ton brief n'a rien à te dire ce matin : hier est resté vide. Note ton petit-déjeuner pour le relancer.",
            ]
            return ("Ton brief attend tes repas", variantes[indexVariante(jour: jour, parmi: variantes.count)])
        }

        let chiffre = "Hier : \(besoinsCouverts(couvertsHier))"
        let suite: String
        if let plusBas {
            suite = "Le plus bas : \(plusBas.cible.avecPossessif), à \(plusBas.pourcent) %. Ton brief te dit sur quoi miser aujourd'hui."
        } else {
            suite = "Ton brief te montre ta veille, apport par apport."
        }
        // « 0 besoin sur 10 » ne donne envie de rien ouvrir : on le tait.
        let corpsChiffre = couvertsHier >= 1 ? "\(chiffre). \(suite)" : suite

        // Une série se fête : elle prend le titre, le chiffre passe dessous.
        if serie >= serieMin {
            return ("\(serie) jours d'affilée 🔥", corpsChiffre)
        }
        guard couvertsHier >= 1 else { return ("Ton brief du jour est prêt", suite) }
        return ("\(chiffre) 📊", suite)
    }

    // MARK: Déclic (ce qui freine un apport, d'après le questionnaire)

    /// `nil` quand le libellé du registre ferait déborder la notification : on
    /// préfère se taire que se faire couper par iOS au milieu d'une phrase.
    static func declic(cible: CibleNutritionnelle, frein: FreinCible, jour: Int) -> (titre: String, corps: String)? {
        let libelle = frein.libelle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !libelle.isEmpty, frein.points > 1 else { return nil }
        let enMinuscule = NomNutriment.minusculeInitiale(libelle)
        let variantes = [
            "D'après tes réponses : « \(enMinuscule) », c'est \(frein.points) points en moins. Ton plan te montre comment les reprendre.",
            "« \(libelle) » : \(frein.points) points en moins dans ton bilan. Touche pour voir par où les reprendre.",
            "\(frein.points) points partent avec « \(enMinuscule) ». Ton plan te dit par quoi commencer.",
        ]
        let corps = variantes[indexVariante(jour: jour, parmi: variantes.count)]
        guard corps.count <= corpsMax else { return nil }
        return (avecEmoji("Ce qui freine \(cible.avecPossessif)", cible), corps)
    }

    // MARK: Midi

    /// - Parameter hier: part du besoin COUVERTE la veille (0-100) pour cet
    ///   apport ; `nil` quand la veille est trop peu notée pour être chiffrée.
    static func midi(cible: CibleNutritionnelle, jour: Int, hier: Int?) -> (titre: String, corps: String) {
        let aliments = aliments(de: cible)
        // Nutriment hors catalogue (ne devrait pas arriver : les cibles sont
        // filtrées sur `NutrientData`) — on reste utile plutôt que bancal.
        guard !aliments.isEmpty else { return midiSansBilan(jour: jour) }
        let enMinuscule = NomNutriment.minusculeInitiale(aliments)

        guard let hier else {
            let variantes = [
                "\(aliments) ce midi ? Scanne ton assiette, tu sauras ce qu'elle t'apporte.",
                "\(aliments) au déjeuner, et ça remonte. Scanne ton assiette.",
                "Au menu du midi : \(enMinuscule). Une photo, et tu vois ce que ça change.",
            ]
            return (avecEmoji("Ce midi, mise sur \(cible.avecPossessif)", cible),
                    variantes[indexVariante(jour: jour, parmi: variantes.count)])
        }

        let titre = avecEmoji("\(sujet(cible)) : \(hier) % hier", cible)
        // Besoin couvert la veille : rien à rattraper, on garde le cap.
        if hier >= BriefDuJourBuilder.seuilCouvert {
            let variantes = [
                "Besoin couvert hier. \(aliments) ce midi pour tenir le cap ? Scanne ton assiette.",
                "Hier, le compte y était. \(aliments) au déjeuner, et tu gardes le rythme.",
                "Besoin couvert hier : on garde le cap. Au menu du midi : \(enMinuscule).",
            ]
            return (titre, variantes[indexVariante(jour: jour, parmi: variantes.count)])
        }
        let variantes = [
            "Il t'en a manqué \(100 - hier) %. \(aliments) ce midi ? Scanne ton assiette.",
            "\(aliments) au déjeuner, et le chiffre remonte. Scanne ton assiette pour le voir.",
            "Pour faire mieux qu'hier : \(enMinuscule) ce midi. Une photo, et tu vois où tu en es.",
        ]
        return (titre, variantes[indexVariante(jour: jour, parmi: variantes.count)])
    }

    // MARK: Encas

    /// - Parameter aujourdhui: où en est cet apport d'après les repas notés
    ///   AUJOURD'HUI, et sur combien de repas ; `nil` = rien de noté ce jour.
    static func encas(
        cible: CibleNutritionnelle,
        jour: Int,
        aujourdhui: (pourcent: Int, repas: Int)?
    ) -> (titre: String, corps: String) {
        guard let aujourdhui else {
            let ouEn = NomNutriment.accord(id: cible.id, singulier: "où en est", pluriel: "où en sont")
            let variantes = [
                "Commence par ton encas : une photo ou quelques mots à voix haute. Demain, ton brief aura de vrais chiffres.",
                "Un encas noté, et tu sais \(ouEn) \(cible.avecPossessif) aujourd'hui. Une photo ou quelques mots suffisent.",
                "Sans repas noté, pas de chiffre : ton encas peut être le premier. Dis-le à voix haute ou prends-le en photo.",
            ]
            return ("Rien de noté pour l'instant 🍎", variantes[indexVariante(jour: jour, parmi: variantes.count)])
        }
        let reste = max(0, 100 - aujourdhui.pourcent)
        let variantes = [
            "Compté sur \(repasNotes(aujourdhui.repas)) aujourd'hui. Ce que tu grignotes compte aussi : note-le.",
            "C'est ton chiffre du jour, pour l'instant. Note ton encas et regarde-le bouger.",
            "Il reste \(reste) % à aller chercher d'ici ce soir. Ton encas en fait partie : note-le.",
        ]
        let fait = NomNutriment.majusculeInitiale(estA(cible))
        return (avecEmoji("Un encas ? \(fait) \(aujourdhui.pourcent) %", cible),
                variantes[indexVariante(jour: jour, parmi: variantes.count)])
    }

    // MARK: Soir

    /// Le conseil du bilan passe devant quand il existe : il est personnalisé.
    /// Sinon les aliments, sinon la raison — jamais une phrase vide de sens.
    /// Longueur en dessous de laquelle le conseil du bilan ne se suffit pas :
    /// « Avec un filet de citron. » seul ne dit pas quoi manger. On l'accroche
    /// alors aux aliments au lieu de le servir nu.
    static let conseilAutoportantMin = 35

    /// - Parameter aujourdhui: part du besoin couverte AUJOURD'HUI pour cet
    ///   apport, d'après les repas déjà notés ; `nil` = rien de noté ce jour.
    static func soir(cible: CibleNutritionnelle, jour: Int, aujourdhui: Int? = nil) -> (titre: String, corps: String) {
        let aliments = aliments(de: cible)
        guard !aliments.isEmpty else { return soirSansBilan(jour: jour) }

        // Déjà à 100 % avant le dîner : on le dit, et on ne pousse rien.
        if let aujourdhui, aujourdhui >= 100 {
            return ("\(sujet(cible)) : besoin du jour couvert ✅",
                    "100 % d'après tes repas notés. Ajoute ton dîner pour boucler la journée.")
        }

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
        if aujourdhui == nil {
            variantes.append("\(aliments) au dîner ? Ta journée se complète.")
        } else {
            variantes.append("\(aliments) au dîner, et tu finis la journée plus haut. Scanne ton assiette.")
        }
        if let raison = RaisonNutriment.pour(cible.id) {
            // Deux phrases : l'énumération reprend donc la majuscule.
            variantes.append("\(raison) \(aliments) ce soir ?")
        } else {
            variantes.append("Un dîner avec \(NomNutriment.minusculeInitiale(aliments)), et la journée est complète.")
        }

        let titre: String
        if let aujourdhui {
            titre = avecEmoji("Ce soir : \(estA(cible)) \(aujourdhui) %", cible)
        } else {
            titre = avecEmoji("Ce soir, pense à \(cible.avecPossessif)", cible)
        }
        return (titre, variantes[indexVariante(jour: jour, parmi: variantes.count)])
    }

    // MARK: Dernier appel (le dîner manque à une journée déjà commencée)

    /// - Parameters:
    ///   - repas: repas notés aujourd'hui (au moins un).
    ///   - couverts: besoins couverts aujourd'hui ; `nil` = pas assez noté
    ///     pour un chiffre.
    static func dernierAppel(repas: Int, couverts: Int?) -> (titre: String, corps: String) {
        let titre = "Il manque ton dîner 🌙"
        if let couverts, couverts >= 1 {
            return (titre, "\(repasNotes(repas)) et \(besoinsCouverts(couverts)) aujourd'hui. Ajoute ton dîner : ton brief de demain sera complet.")
        }
        return (titre, "\(repasNotes(repas)) aujourd'hui. Ajoute ton dîner, à la voix ou en photo : ton brief de demain aura de vrais chiffres.")
    }

    // MARK: Dimanche (la semaine en chiffres)

    /// - Parameters:
    ///   - repas: repas notés depuis lundi.
    ///   - jours: jours de la semaine avec au moins un repas noté.
    ///   - effort: l'apport qui a le plus progressé sur la semaine précédente.
    static func semaine(repas: Int, jours: Int, effort: BriefDuJour.Effort?) -> (titre: String, corps: String) {
        let titre = "Ta semaine en chiffres 📈"
        let surJours = jours <= 1 ? "\(jours) jour" : "\(jours) jours"
        guard let effort else {
            return (titre, "\(repasNotes(repas)) sur \(surJours) cette semaine. Ton point de la semaine t'attend dans Progrès.")
        }
        let nomSujet = NomNutriment.majusculeInitiale(NomNutriment.possessif(id: effort.id, nom: effort.nom))
        let verbe = NomNutriment.accord(id: effort.id, singulier: "a gagné", pluriel: "ont gagné")
        return (titre, "\(repasNotes(repas)) sur \(surJours). \(nomSujet) \(verbe) \(effort.points) points par rapport à la semaine dernière. Le détail t'attend dans Progrès.")
    }

    // MARK: Retour après une semaine sans ouvrir

    static func retour(cible: CibleNutritionnelle?) -> (titre: String, corps: String) {
        guard let cible else {
            return ("Ton suivi t'attend",
                    "Une semaine sans nouvelles : un repas noté suffit à le relancer.")
        }
        let verbe = NomNutriment.accord(id: cible.id, singulier: "t'attend", pluriel: "t'attendent")
        return (
            avecEmoji("\(sujet(cible)) \(verbe)", cible),
            "Une semaine sans nouvelles : un repas noté suffit à relancer ton suivi."
        )
    }

    // MARK: La prise de sang a 6 mois

    /// Sonne le jour où la prise de sang passe à demi-effet
    /// (`PriseDeSangApports.moisPleinEffet`). Aucune valeur sur l'écran
    /// verrouillé : seulement son âge, et ce que ça change au calcul.
    static func priseDeSangSixMois() -> (titre: String, corps: String) {
        (
            "Ta prise de sang a 6 mois 🩸",
            "Elle compte désormais moitié moins dans tes apports. Une analyse plus récente ? Importe-la pour garder des chiffres justes."
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
