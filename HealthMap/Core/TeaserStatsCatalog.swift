import Foundation

// MARK: - Catalogue des stats France (mode découverte du Bilan — V12b)
//
// Avant le bilan, la grille des apports n'a aucune donnée personnelle à
// afficher : chaque ligne montre à la place un ORDRE DE GRANDEUR français
// issu d'études publiques, à l'emplacement du « % de tes besoins ».
//
// Règles du catalogue (principe validé fondateur, 12-13 août 2026) :
//   • uniquement des chiffres d'études publiques françaises, arrondis à la
//     fraction simple (« 7 sur 10 ») — jamais de décimale, jamais de % ;
//   • formulation « apport insuffisant » / « sous les repères » exclusivement
//     (vocabulaire conforme — VoiceComplianceTests s'applique ici aussi) ;
//   • chaque entrée porte sa source, en commentaire ici ET en petit texte
//     affiché (« · Esteban », « · INCA3 ») ;
//   • pas de chiffre solide → formulation générique prudente : on n'invente
//     JAMAIS un chiffre.

/// Une stat France affichable dans la grille des apports en mode découverte.
struct TeaserStat {
    /// Fraction courte à l'emplacement du « % de tes besoins » (« 7 sur 10 »).
    /// `nil` quand aucun chiffre national robuste n'existe : la ligne reste
    /// prudente, sans nombre.
    let fraction: String?
    /// Qualificatif court affiché sous la jauge (« Adultes sous les repères »).
    let texte: String
    /// Source publique, affichée en petit (« Esteban », « INCA3 »).
    let source: String

    /// Phrase complète pour VoiceOver (ponctuation prononçable uniquement,
    /// jamais de tiret cadratin — même doctrine que TypographieTests).
    var accessibilite: String {
        if let fraction {
            return "\(fraction) : \(texte), source \(source)"
        }
        return "\(texte), source \(source)"
    }
}

enum TeaserStatsCatalog {
    /// Formulation prudente quand aucun chiffre national robuste n'existe
    /// pour un nutriment isolé (décision : ne jamais inventer un chiffre).
    /// Source affichée : repères d'apport ANSES (actualisation 2016-2021).
    static let generique = TeaserStat(
        fraction: nil,
        texte: "Souvent sous les repères en France",
        source: "ANSES"
    )

    /// Stats par nutriment — ids canoniques de `NutrientData` (les 10).
    static let parNutriment: [String: TeaserStat] = [
        // Étude Esteban 2014-2016 (Santé publique France), volet statut
        // vitaminique : environ 7 adultes sur 10 sous le seuil d'adéquation
        // en vitamine D.
        "vitD": TeaserStat(
            fraction: "7 sur 10",
            texte: "Adultes sous les repères",
            source: "Esteban"
        ),
        // SU.VI.MAX (relayé par INCA3/ANSES) : environ 1 adulte sur 3 sous
        // le besoin nutritionnel moyen (BNM) en magnésium.
        "magnesium": TeaserStat(
            fraction: "1 sur 3",
            texte: "Adultes sous les besoins moyens",
            source: "SU.VI.MAX"
        ),
        // INCA3 (ANSES, 2017) : environ 1 femme sur 4 en âge de procréer
        // avec un apport en fer insuffisant.
        "iron": TeaserStat(
            fraction: "1 sur 4",
            texte: "Femmes avec un apport insuffisant",
            source: "INCA3"
        ),
        // INCA3 (ANSES, 2017) : environ 9 adultes sur 10 sous les repères
        // ANSES en oméga-3 (EPA + DHA).
        "omega3": TeaserStat(
            fraction: "9 sur 10",
            texte: "Adultes sous les repères ANSES",
            source: "INCA3"
        ),
        // INCA3 (ANSES, 2017) : environ 9 adultes sur 10 sous les 25 g de
        // fibres par jour recommandés.
        "fiber": TeaserStat(
            fraction: "9 sur 10",
            texte: "Adultes sous les 25 g par jour",
            source: "INCA3"
        ),
        // Pas de chiffre national robuste isolé pour ces cinq nutriments →
        // formulation générique prudente (repères ANSES), aucun chiffre.
        "vitB12": generique,
        "vitC": generique,
        "calcium": generique,
        "zinc": generique,
        "iodine": generique,
    ]

    /// Stat pour un id de nutriment — repli générique prudent si absent.
    static func stat(for id: String) -> TeaserStat {
        parNutriment[id] ?? generique
    }
}
