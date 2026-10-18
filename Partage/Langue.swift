import Foundation

// MARK: - La langue de l'app (14 oct. 2026)
//
// Kiwio s'affiche dans la langue de l'iPhone : en anglais sur un iPhone en
// anglais, en français sinon. iOS choisit lui-même parmi les langues du
// catalogue `Localizable.xcstrings` ; on n'affiche aucun choix au démarrage
// (Réglages iOS > Kiwio > Langue permet d'en changer).
//
// Règle d'or : sur un iPhone en français, chaque texte reste identique au
// caractère près. Les clés du catalogue SONT les textes français, et tout ce
// qui sert de donnée (identifiants, mots de recherche, envois au serveur,
// hash du bilan) reste en français.
//
// Compilé dans l'app ET dans l'extension de widgets (`Partage/`).

enum Langue {

    /// Vrai quand l'app s'affiche en français.
    static var estFrancais: Bool {
        (Bundle.main.preferredLocalizations.first ?? "fr").hasPrefix("fr")
    }

    /// Traduit un texte connu seulement à l'exécution (le libellé d'un
    /// catalogue, passé par une fonction). Pour un texte écrit en dur, préférer
    /// `String(localized:)`, que le compilateur sait repérer.
    /// En français, rend le texte tel quel.
    static func texte(_ francais: String) -> String {
        Bundle.main.localizedString(forKey: francais, value: francais, table: nil)
    }

    /// La locale des dates et des nombres affichés : `fr_FR` en français,
    /// comme avant, celle de l'iPhone sinon.
    static var locale: Locale {
        estFrancais ? Locale(identifier: "fr_FR") : .current
    }
}
