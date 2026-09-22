import Foundation

// MARK: - Une cause, dépliée (retour d'Arthur du 21 septembre 2026)
//
// Le registre nomme chaque facteur et dit ce qu'il pèse. Ici, ce qu'on répond à
// qui touche une cause : ce qu'on regagnerait sans elle, pourquoi elle pèse, et
// — quand c'est une habitude ou l'assiette — par où commencer.
//
// Trois règles :
//   • ce qu'on « regagnerait » est une SIMULATION du même calcul (le registre
//     rejoué sans ce facteur), jamais une promesse ;
//   • le « pourquoi » est un mécanisme établi, écrit une fois, par famille de
//     facteurs — rien n'est rédigé à la volée ;
//   • un geste n'existe que pour ce qui se change (habitudes, assiette). Le
//     profil situe un point de départ ; la santé et les traitements renvoient
//     vers un professionnel, et jamais vers un arrêt de traitement.

/// Le nom d'un apport dans une phrase.
enum NomApport {
    /// « le fer », « la vitamine D », « l'iode ».
    static func avecArticle(id: String, repli: String) -> String {
        switch id {
        case "vitD": return "la vitamine D"
        case "vitB12": return "la vitamine B12"
        case "iron": return "le fer"
        case "magnesium": return "le magnésium"
        case "omega3": return "les oméga-3"
        case "vitC": return "la vitamine C"
        case "calcium": return "le calcium"
        case "zinc": return "le zinc"
        case "iodine": return "l'iode"
        case "fiber": return "les fibres"
        default: return repli.lowercased()
        }
    }

    /// « ton fer », « ta vitamine D », « tes oméga-3 », « ton iode ».
    static func possessif(_ avecArticle: String) -> String {
        if avecArticle.hasPrefix("les ") { return "tes " + avecArticle.dropFirst(4) }
        if avecArticle.hasPrefix("la ") { return "ta " + avecArticle.dropFirst(3) }
        if avecArticle.hasPrefix("le ") { return "ton " + avecArticle.dropFirst(3) }
        if avecArticle.hasPrefix("l'") { return "ton " + avecArticle.dropFirst(2) }
        return avecArticle
    }
}

extension DetailApport {
    /// Le score si ce facteur n'existait pas : le même calcul, rejoué sans lui,
    /// ramené dans l'échelle. Pour un frein, c'est ce qu'il y a à regagner ;
    /// pour un appui, ce qu'il tient.
    func scoreSans(_ contribution: ContributionApport) -> Int {
        max(0, min(100, brut - contribution.delta))
    }

    /// Ce que pèsent, ensemble, les facteurs sur lesquels la personne peut agir
    /// (habitudes et assiette). Négatif ou nul.
    var pointsModifiables: Int {
        freins.filter { CauseApport.seChange($0.section) }.reduce(0) { $0 + $1.delta }
    }
}

enum CauseApport {

    struct Explication: Equatable {
        /// Pourquoi ce facteur pèse (ou aide) : le mécanisme.
        let pourquoi: String
        /// Par où commencer — seulement pour ce qui se change. Réservé Premium.
        let geste: String?
        /// Le renvoi vers un professionnel (santé, traitements).
        let avis: String?
    }

    /// Une habitude ou l'assiette : ce sur quoi on peut agir soi-même.
    static func seChange(_ section: SectionQuestionnaire) -> Bool {
        section == .modeDeVie || section == .nutrition || section == .journal
    }

    /// Le journal des repas (étape 3 de l'audit, 22 sept. 2026) : ce que la
    /// personne a vraiment mangé corrige ce que le questionnaire laissait penser.
    static let journalPese = Explication(
        pourquoi: "Les repas que tu as notés ces deux dernières semaines en apportent moins que ce que ton questionnaire laissait penser. Ils corrigent ton score, sans le remplacer.",
        geste: "Continue de noter tes repas : plus ton journal est complet, plus ce chiffre te ressemble.",
        avis: nil)
    static let journalAide = Explication(
        pourquoi: "Les repas que tu as notés ces deux dernières semaines en apportent plus que ce que ton questionnaire laissait penser : ils remontent ton score.",
        geste: nil,
        avis: nil)

    private static func cle(_ texte: String) -> String {
        texte.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR")).lowercased()
    }

    /// Les familles de facteurs, dans l'ordre où on les reconnaît.
    private static let familles: [(mots: [String], pourquoi: String, geste: String)] = [
        (["courses"],
         "Tes courses habituelles contiennent peu d'aliments qui apportent cet apport. C'est la première source, avant tout le reste : c'est souvent là qu'il y a le plus de points à regagner.",
         "Ajoute à tes courses deux ou trois aliments qui en sont riches, et garde-les d'une semaine sur l'autre."),
        (["cafe", "the pendant"],
         "Les tanins du café et du thé se lient au fer pendant la digestion : une partie du fer du repas n'est pas absorbée. Le magnésium est touché aussi, dans une moindre mesure.",
         "Garde ton café ou ton thé, mais à distance des repas : une heure après suffit."),
        (["vegetarien", "produits animaux", "ni viande"],
         "Le fer des végétaux est moins bien absorbé que celui des produits animaux, et la vitamine B12 ne se trouve pratiquement que chez eux. Le zinc et les oméga-3 suivent la même pente.",
         "Associe tes légumineuses à une source de vitamine C (agrume, poivron, kiwi) : elle aide l'absorption du fer végétal."),
        (["cuisson"],
         "La vitamine C est fragile : elle passe dans l'eau de cuisson, et la chaleur la dégrade.",
         "Vapeur douce, cuisson courte, ou cru quand c'est possible."),
        (["poisson"],
         "Les oméga-3 à longue chaîne viennent surtout des poissons gras, qui apportent aussi de la vitamine D et de l'iode.",
         "Sardines, maquereau ou hareng, deux fois par semaine : en boîte, c'est très bien."),
        (["laitier"],
         "Les produits laitiers sont la source de calcium la plus concentrée de l'alimentation courante ; ils apportent aussi de l'iode.",
         "Si tu en consommes peu : eaux riches en calcium, sardines avec leurs arêtes, amandes, choux."),
        (["sel"],
         "En France, le sel iodé est l'une des principales sources d'iode du quotidien.",
         "Vérifie la mention « iodé » sur ton sel de table."),
        (["pain blanc", "cereales", "gluten"],
         "Les céréales raffinées ont perdu l'essentiel de leurs fibres, de leur magnésium et de leur zinc.",
         "Passe au complet ou au levain pour le pain du quotidien."),
        (["dehors", "transforme", "maison"],
         "Les repas pris dehors et les produits transformés sont, en moyenne, plus pauvres en fibres et en minéraux.",
         "Un repas fait maison de plus par semaine change déjà la moyenne."),
        (["fermente"],
         "Les aliments fermentés nourrissent le microbiote, qui participe à l'assimilation de plusieurs apports.",
         "Un yaourt, un peu de choucroute crue ou de kéfir, quelques fois par semaine."),
        (["stress", "nuits", "ecrans", "sommeil"],
         "Le stress prolongé et le manque de sommeil augmentent les pertes de magnésium ; un magnésium bas rend à son tour plus sensible au stress.",
         "Un coucher régulier et des écrans coupés avant de dormir : c'est le levier le plus direct."),
        (["interieur", "soleil", "exposition"],
         "La vitamine D se fabrique surtout dans la peau, au soleil. Sans exposition, l'alimentation seule couvre rarement le besoin.",
         "Un quart d'heure dehors, bras découverts, en milieu de journée quand c'est possible."),
        (["alcool"],
         "L'alcool diminue l'absorption de plusieurs vitamines et minéraux, et augmente leurs pertes.",
         "Des jours sans, chaque semaine."),
        (["tabac", "fume"],
         "Le tabac consomme de la vitamine C : le besoin d'un fumeur est plus élevé.",
         "Chaque cigarette en moins compte ; en attendant, un fruit riche en vitamine C par jour."),
        (["sport", "activite"],
         "L'effort régulier augmente certains besoins, par la sueur et la récupération musculaire.",
         "Pense aux oléagineux et aux légumineuses les jours d'entraînement."),
    ]

    /// Le geste rendu quand aucune famille ne reconnaît le facteur : il renvoie
    /// au questionnaire. La fiche d'un apport ne le liste pas parmi ses gestes.
    static let gesteDeRepli = "Reprends cette réponse dans ton questionnaire si elle a changé : le calcul se refait aussitôt."

    static func explication(pour contribution: ContributionApport) -> Explication {
        if contribution.section == .journal {
            return contribution.delta < 0 ? journalPese : journalAide
        }
        // Ce qui joue en ta faveur.
        guard contribution.delta < 0 else {
            let pourquoi = contribution.libelle.hasPrefix("Tu prends déjà")
                ? "Tu nous as dit en prendre : on en tient compte, et ça compte en ta faveur."
                : "C'est une de tes habitudes qui joue en ta faveur : elle ajoute des points à cet apport. À garder."
            return Explication(pourquoi: pourquoi, geste: nil, avis: nil)
        }

        switch contribution.section {
        case .profil:
            return Explication(
                pourquoi: "Ton âge et ton profil modifient ton besoin, ou la façon dont ton corps absorbe cet apport. Ce n'est pas un facteur sur lequel agir : il situe simplement ton point de départ.",
                geste: nil, avis: nil)
        case .sante, .symptomes:
            return Explication(
                pourquoi: "Cette période ou cet état augmente ton besoin, ou tes pertes, pour cet apport. C'est attendu, et ça se compense.",
                geste: nil,
                avis: "Si ça te fatigue ou que ça dure, parles-en à ton médecin ou à ta sage-femme.")
        case .medical:
            return Explication(
                pourquoi: "Certains traitements et antécédents diminuent l'absorption de cet apport, ou augmentent ses pertes. C'est connu, et ça se surveille.",
                geste: nil,
                avis: "Ne modifie jamais un traitement de toi-même : parles-en à ton médecin ou à ton pharmacien.")
        case .journal:
            return journalPese
        case .modeDeVie, .nutrition:
            let libelle = cle(contribution.libelle)
            if let famille = familles.first(where: { $0.mots.contains { libelle.contains($0) } }) {
                return Explication(pourquoi: famille.pourquoi, geste: famille.geste, avis: nil)
            }
            return Explication(
                pourquoi: "Ce facteur vient de tes réponses au questionnaire : il retire des points à cet apport dans notre calcul.",
                geste: gesteDeRepli,
                avis: nil)
        }
    }
}
