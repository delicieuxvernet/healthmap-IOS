import Foundation

// MARK: - Catalogue des mécanismes de points d'attention (déterministe)
//
// Patron `FunFactCatalog` : logique PURE et code-side, l'IA n'invente rien à
// l'affichage. Chaque point d'attention connu du produit (interactions de la
// liste fermée du contrat v2 + croisements mode de vie de health.js) est mappé
// vers le contenu du pop-up « Point d'attention » :
//   teasing (reste net) · schéma en 3 étapes (habitude → mécanisme → impact)
//   · phrase de solution · nutriment concerné (chip du header).
//
// Un point d'attention sans entrée → `nil` : le pop-up bascule sur le repli
// (texte existant du contrat, gaté), JAMAIS de coquille vide ni de texte
// inventé.
//
// Chiffres du schéma : uniquement des ordres de grandeur établis, les mêmes
// que le prompt serveur (IPP + B12 : Lam 2013 · metformine + B12 : de Jager
// 2010 · tanins et fer non héminique : jusqu'à −60 %). Pas de source → pas de
// chiffre (l'étape impact reste qualitative).

struct AttentionMechanism: Equatable {
    struct Step: Equatable {
        /// SF Symbol de la pastille.
        let icon: String
        /// Libellé sur 2 lignes courtes.
        let line1: String
        let line2: String
    }

    /// Phrase toujours en clair : le QUOI est nommé (le nutriment), jamais
    /// l'habitude (elle est réservée au contenu gaté).
    let teasing: String
    let habit: Step
    let mechanism: Step
    let impact: Step
    /// Phrase actionnable de la carte « Ta solution ».
    let solution: String
    /// Id du catalogue `NutrientData` (chip colorée du header).
    let nutrientId: String
}

enum AttentionMechanismCatalog {

    /// Entrée du catalogue pour une interaction du contrat v2, par
    /// reconnaissance déterministe de mots-clés dans son texte. `nil` si le
    /// point d'attention n'est pas répertorié → le pop-up passe en repli.
    static func entry(for interaction: InteractionV2) -> AttentionMechanism? {
        let text = normalized(searchText(of: interaction))
        return entries.first { matches($0.required, in: text) }?.mechanism
    }

    /// Nutriment cité dans le texte de l'interaction (repli : permet d'avoir
    /// la chip et un teasing nommant le nutriment même hors catalogue).
    /// `nil` si aucun nutriment du catalogue n'est reconnaissable.
    static func inferredNutrientId(from interaction: InteractionV2) -> String? {
        inferredNutrientIds(from: interaction).first
    }

    /// TOUS les nutriments reconnus dans le texte de l'interaction, dans
    /// l'ordre stable des sondes (déterministe). Sert au teasing générique
    /// « X et y : deux de tes apports se gênent ».
    static func inferredNutrientIds(from interaction: InteractionV2) -> [String] {
        let text = normalized(searchText(of: interaction))
        let probes: [(pattern: String, id: String)] = [
            ("b12", "vitB12"),
            ("\\bfer\\b", "iron"),
            ("\\bmagnes", "magnesium"),
            ("vitamine d\\b", "vitD"),
            ("vitamine c\\b", "vitC"),
            ("\\bomega", "omega3"),
            ("\\bcalcium", "calcium"),
            ("\\bzinc", "zinc"),
            ("\\biode", "iodine"),
            ("\\bfibre", "fiber"),
        ]
        return probes.filter { contains(text, $0.pattern) }.map(\.id)
    }

    // MARK: - Titre « gratuit » d'un point d'attention

    /// Libellé neutre par défaut quand rien n'est reconnaissable.
    static let neutralFreeTitle = "Un point d'attention détecté dans tes réponses"

    /// Titre affichable en GRATUIT : nomme le PROBLÈME (le nutriment, la
    /// gêne), jamais le geste correcteur — le titre IA (`tipBold`) est un
    /// conseil actionnable réservé au premium. Chaîne déterministe :
    ///   1. teasing du catalogue quand l'interaction y matche ;
    ///   2. sinon, 2 nutriments reconnus → « Fer et calcium : deux de tes
    ///      apports se gênent » ;
    ///   3. sinon, 1 nutriment reconnu → la même phrase générique que le
    ///      pop-up (« Une de tes habitudes… ton apport en fer ») ;
    ///   4. sinon → `neutral` (libellé neutre, surchargé par le pop-up).
    static func freeTitle(for interaction: InteractionV2,
                          neutral: String = neutralFreeTitle) -> String {
        if let mechanism = entry(for: interaction) { return mechanism.teasing }

        let labels = inferredNutrientIds(from: interaction)
            .compactMap { NutrientData.definition(for: $0)?.label }
        if labels.count >= 2 {
            return "\(labels[0]) et \(lowercasedFirst(labels[1])) : deux de tes apports se gênent"
        }
        if let label = labels.first {
            return "Une de tes habitudes du quotidien influence directement ton apport en \(lowercasedFirst(label))."
        }
        return neutral
    }

    /// « Vitamine B12 » → « vitamine B12 » (seule l'initiale passe en
    /// minuscule — un .lowercased() global écraserait « B12 » en « b12 »).
    private static func lowercasedFirst(_ label: String) -> String {
        guard let first = label.first else { return label }
        return first.lowercased() + label.dropFirst()
    }

    // MARK: - Reconnaissance (texte normalisé, mots-clés en ET de OU)

    private static func searchText(of interaction: InteractionV2) -> String {
        [interaction.tipBold, interaction.tipRest]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// Minuscules + accents repliés → les motifs sont en ASCII (\b fiable).
    private static func normalized(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
    }

    private static func contains(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Chaque groupe (OU) doit fournir au moins un motif présent (ET).
    private static func matches(_ groups: [[String]], in text: String) -> Bool {
        groups.allSatisfy { group in group.contains { contains(text, $0) } }
    }

    // MARK: - Entrées (ordre = priorité : du plus spécifique au plus large)

    private struct Entry {
        /// ET de OU : `[["metformine"], ["b12"]]` = metformine ET b12.
        let required: [[String]]
        let mechanism: AttentionMechanism
    }

    private static let entries: [Entry] = [
        // Metformine → B12 (de Jager 2010) — avant IPP et B12 générique.
        Entry(
            required: [["\\bmetformine"]],
            mechanism: AttentionMechanism(
                teasing: "Un traitement que tu prends freine l'assimilation de ta vitamine B12.",
                habit: .init(icon: "pills.fill", line1: "Metformine", line2: "au quotidien"),
                mechanism: .init(icon: "link", line1: "Son absorption", line2: "est freinée"),
                impact: .init(icon: "chart.line.downtrend.xyaxis", line1: "Jusqu'à −30 %", line2: "de B12 assimilée"),
                solution: "Soigne tes sources de B12 (œufs, poisson, laitages) et fais le point avec ton médecin au prochain rendez-vous.",
                nutrientId: "vitB12"
            )
        ),
        // Calcium + lévothyroxine (liste fermée du contrat : 4 h d'écart).
        Entry(
            required: [["\\blevothyrox", "\\bthyro"], ["\\bcalcium"]],
            mechanism: AttentionMechanism(
                teasing: "Ton calcium peut gêner l'effet d'un de tes traitements du matin.",
                habit: .init(icon: "pills.fill", line1: "Calcium proche", line2: "du traitement"),
                mechanism: .init(icon: "link", line1: "Ils se lient", line2: "dans l'estomac"),
                impact: .init(icon: "chart.line.downtrend.xyaxis", line1: "Effet du", line2: "traitement réduit"),
                solution: "Garde 4 h entre ton traitement du matin et tes laitages ou ton calcium : chacun garde son effet.",
                nutrientId: "calcium"
            )
        ),
        // IPP / antiacides → B12 (Lam 2013).
        Entry(
            required: [["\\bipp\\b", "\\bomeprazole", "\\bpantoprazole", "\\besomeprazole", "\\bantiacide", "anti-acide", "protecteur gastrique"]],
            mechanism: AttentionMechanism(
                teasing: "Un de tes traitements freine l'assimilation de ta vitamine B12.",
                habit: .init(icon: "pills.fill", line1: "Antiacide", line2: "au quotidien"),
                mechanism: .init(icon: "drop.fill", line1: "Moins d'acidité pour", line2: "libérer la B12"),
                impact: .init(icon: "chart.line.downtrend.xyaxis", line1: "Jusqu'à −65 %", line2: "d'absorption"),
                solution: "Mise sur des sources régulières de B12 (œufs, poisson, laitages) et parles-en à ton médecin au prochain rendez-vous.",
                nutrientId: "vitB12"
            )
        ),
        // Café / thé pendant le repas → fer (tanins, jusqu'à −60 %).
        Entry(
            required: [["\\bcafe", "\\bcafeine", "\\bthe\\b", "\\btanin", "\\btannin"], ["\\bfer\\b"]],
            mechanism: AttentionMechanism(
                teasing: "Une de tes habitudes quotidiennes bloque l'absorption de ton fer.",
                habit: .init(icon: "cup.and.saucer.fill", line1: "Café pendant", line2: "le repas"),
                mechanism: .init(icon: "magnet", line1: "Les tanins", line2: "captent le fer"),
                impact: .init(icon: "chart.line.downtrend.xyaxis", line1: "Jusqu'à −60 %", line2: "d'absorption"),
                solution: "Décale ton café à 1 h après le repas : ton fer passe, ton café reste.",
                nutrientId: "iron"
            )
        ),
        // Fer + calcium pris ensemble (liste fermée : 2 h d'écart).
        Entry(
            required: [["\\bfer\\b"], ["\\bcalcium"]],
            mechanism: AttentionMechanism(
                teasing: "Deux de tes apports se gênent quand ils arrivent en même temps.",
                habit: .init(icon: "pills.fill", line1: "Fer et calcium", line2: "en même temps"),
                mechanism: .init(icon: "door.left.hand.closed", line1: "Même porte", line2: "d'absorption"),
                impact: .init(icon: "chart.line.downtrend.xyaxis", line1: "Absorption réduite", line2: "pour les deux"),
                solution: "Espace-les de 2 h : le fer au déjeuner, le calcium au dîner par exemple.",
                nutrientId: "iron"
            )
        ),
        // Écrans / stress / sommeil court → magnésium (croisement health.js).
        Entry(
            required: [["\\bmagnes"], ["\\becran", "\\bstress", "\\bsommeil", "\\bsoir", "\\bcoucher", "\\bdormir", "\\bnuit"]],
            mechanism: AttentionMechanism(
                teasing: "Ton rythme du soir puise dans tes réserves de magnésium.",
                habit: .init(icon: "iphone", line1: "Écrans et stress", line2: "le soir"),
                mechanism: .init(icon: "bolt.fill", line1: "Ton corps brûle", line2: "son magnésium"),
                impact: .init(icon: "chart.line.downtrend.xyaxis", line1: "Réserves qui", line2: "s'épuisent"),
                solution: "Coupe les écrans 30 min avant de dormir : ton magnésium travaille pour ta nuit, pas contre ton stress.",
                nutrientId: "magnesium"
            )
        ),
        // Cuisson longue à l'eau → vitamine C (croisement health.js).
        Entry(
            required: [["vitamine c\\b"], ["\\bcuisson", "\\bbouill", "\\bcuire", "\\bcuit"]],
            mechanism: AttentionMechanism(
                teasing: "Une habitude en cuisine fait fondre ta vitamine C avant l'assiette.",
                habit: .init(icon: "flame.fill", line1: "Cuisson longue", line2: "à l'eau"),
                mechanism: .init(icon: "thermometer.high", line1: "La chaleur détruit", line2: "la vitamine C"),
                impact: .init(icon: "chart.line.downtrend.xyaxis", line1: "Jusqu'à −50 %", line2: "dans l'assiette"),
                solution: "Privilégie la vapeur douce ou les cuissons courtes : ta vitamine C reste dans l'assiette.",
                nutrientId: "vitC"
            )
        ),
        // Ultra-transformés → fibres (croisement health.js).
        Entry(
            required: [["\\bfibre"], ["ultra", "\\btransforme", "\\bindustriel", "\\braffine", "plats prepares"]],
            mechanism: AttentionMechanism(
                teasing: "Une partie de tes repas arrive déjà vidée de ses fibres.",
                habit: .init(icon: "shippingbox.fill", line1: "Plats", line2: "ultra-transformés"),
                mechanism: .init(icon: "scissors", line1: "Le raffinage", line2: "retire les fibres"),
                impact: .init(icon: "chart.line.downtrend.xyaxis", line1: "2 à 3 fois moins", line2: "de fibres"),
                solution: "Ajoute une portion de légumes ou de légumineuses par jour : tes fibres remontent vite.",
                nutrientId: "fiber"
            )
        ),
    ]
}
