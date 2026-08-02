import Foundation

// MARK: - Nettoyage typographique des textes affichés
//
// Vit ici (Shared) et non dans un écran : tout texte venant de l'IA ou du
// catalogue passe par là avant affichage, quel que soit l'onglet.
// Déplacé depuis SupplementsChainV6.swift le 2 août 2026, où il ne servait
// qu'à l'écran Compléments.
enum KiwiProse {
    /// Le tiret cadratin en incise (« … — … ») ne se prononce pas, hache la
    /// lecture, et c'est la signature typographique des textes générés par
    /// machine. On le ramène à la ponctuation qu'on écrirait à la main.
    /// À appliquer à TOUT texte venant de l'IA ou du catalogue avant affichage.
    static func lisible(_ texte: String) -> String {
        var sortie = texte.trimmingCharacters(in: .whitespacesAndNewlines)

        // Incises : « … — … » → « …, … ». On couvre aussi les espaces
        // insécables, que le modèle produit régulièrement.
        for tiret in [" — ", " – ", " − ", " -- ", "\u{00A0}— ", " —\u{00A0}", "\u{00A0}—\u{00A0}"] {
            sortie = sortie.replacingOccurrences(of: tiret, with: ", ")
        }

        // Tiret en tête de ligne : c'est une puce déguisée, on la retire.
        for prefixe in ["— ", "– ", "-- "] where sortie.hasPrefix(prefixe) {
            sortie.removeFirst(prefixe.count)
        }

        // Tiret en fin de fragment (concaténation tronquée) : sans valeur.
        for suffixe in [" —", " –", " --"] where sortie.hasSuffix(suffixe) {
            sortie.removeLast(suffixe.count)
        }

        return sortie
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: ", ,", with: ",")
            .replacingOccurrences(of: ",,", with: ",")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
