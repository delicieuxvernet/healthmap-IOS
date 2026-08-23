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

        // Marqueurs markdown (« **fer héminique** », `code`) : le modèle en
        // produit parfois, SwiftUI les affiche tels quels — on les retire,
        // l'app pose sa propre hiérarchie typographique.
        for marqueur in ["**", "__", "`"] {
            sortie = sortie.replacingOccurrences(of: marqueur, with: "")
        }

        // Apartés savants entre parenthèses : « (cofacteur de la synthèse de
        // l'hème) » n'aide personne et hache la phrase. On retire les apartés
        // LONGS et sans chiffre ; les repères courts ou chiffrés restent
        // (« (2 par jour) », « (à jeun) »).
        sortie = sansApartesSavants(sortie)

        return sortie
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: ", ,", with: ",")
            .replacingOccurrences(of: ",,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Assemble des fragments en un paragraphe de PHRASES : chaque fragment
    /// est nettoyé, doté d'une majuscule et d'un point final. C'est le remède
    /// aux pavés recollés par un espace (« …énergie cellulaire Règles
    /// abondantes… », vu sur le Plan le 23 août).
    static func phrases(_ fragments: [String]) -> String {
        fragments
            .map { lisible($0) }
            .filter { !$0.isEmpty }
            .map { phrase($0) }
            .joined(separator: " ")
    }

    /// Une phrase propre : majuscule initiale, point final (sauf ponctuation
    /// déjà là), jamais de double point.
    static func phrase(_ texte: String) -> String {
        var sortie = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sortie.isEmpty else { return "" }
        sortie = sortie.prefix(1).uppercased() + sortie.dropFirst()
        if let dernier = sortie.last, !".!?…".contains(dernier) {
            sortie += "."
        }
        return sortie
    }

    /// Retire les groupes entre parenthèses longs (≥ 25 caractères) et sans
    /// chiffre — la signature des apartés « scientifiques » du modèle.
    private static func sansApartesSavants(_ texte: String) -> String {
        var sortie = ""
        var profondeur = 0
        var aparte = ""
        for caractere in texte {
            if caractere == "(" {
                if profondeur > 0 { aparte.append(caractere) }
                profondeur += 1
                continue
            }
            if caractere == ")" && profondeur > 0 {
                profondeur -= 1
                if profondeur == 0 {
                    let garde = aparte.count < 25 || aparte.contains(where: \.isNumber)
                    if garde { sortie += "(" + aparte + ")" }
                    aparte = ""
                } else {
                    aparte.append(caractere)
                }
                continue
            }
            if profondeur > 0 { aparte.append(caractere) } else { sortie.append(caractere) }
        }
        // Parenthèse jamais refermée : on garde tel quel plutôt que d'avaler.
        if profondeur > 0 { sortie += "(" + aparte }
        return sortie.replacingOccurrences(of: "  ", with: " ")
    }
}
