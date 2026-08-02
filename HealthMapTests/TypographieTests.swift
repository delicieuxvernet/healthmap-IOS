import XCTest
@testable import HealthMap

/// Garde-fou typographique sur les textes affichés.
///
/// Le tiret cadratin en incise (« … — … ») est proscrit dans l'UI : il ne se
/// prononce pas, hache la lecture, et c'est la signature visuelle d'un texte
/// écrit par une machine. Décision produit du 1er août 2026.
///
/// Deux lignes de défense, ce test couvre la seconde :
///   1. Les textes venant de l'IA sont nettoyés au décodage par
///      `KiwiProse.lisible` (AIAnalysis, AIAnalysisV2, ScanV2).
///   2. Les chaînes écrites en dur dans le code, elles, ne passent par aucun
///      filtre au runtime : c'est ce test qui les surveille.
///
/// ⚠️ PÉRIMÈTRE : `HealthMap/Views/` uniquement, plus les quelques fichiers
/// hors vues qui portent du texte affiché. Les couches basses (Services, Core,
/// Utilities) sont exclues volontairement : elles sont pleines de messages
/// `os.Logger` qui contiennent des tirets cadratins parfaitement légitimes et
/// que l'utilisateur ne voit jamais.
final class TypographieTests: XCTestCase {

    /// Racine du dépôt, déduite de l'emplacement de ce fichier à la compilation.
    private var racine: URL {
        URL(fileURLWithPath: #filePath)      // …/HealthMapTests/TypographieTests.swift
            .deletingLastPathComponent()     // …/HealthMapTests
            .deletingLastPathComponent()     // …/ (racine du dépôt)
    }

    /// Fichiers exemptés en entier, avec la raison. Garder cette liste la plus
    /// courte possible : chaque entrée est un angle mort.
    private let exceptions: [String: String] = [
        // C'est l'implémentation du nettoyage : ses tables de remplacement
        // contiennent forcément les tirets qu'elle élimine.
        "KiwiProse.swift": "table de remplacement de l'utilitaire lui-même",
    ]

    func testAucunTiretCadratinEnInciseDansLesTextesAffiches() throws {
        var fichiers = try fichiersSwift(sous: "HealthMap/Views")
        for horsVue in ["HealthMap/Core/RedFlagDetector.swift",
                        "HealthMap/Core/HealthMapError.swift",
                        "HealthMap/Models/SupplementModels.swift"] {
            let url = racine.appendingPathComponent(horsVue)
            guard FileManager.default.fileExists(atPath: url.path) else {
                XCTFail("Chemin surveillé introuvable : \(horsVue). Le test ne surveille plus rien.")
                continue
            }
            fichiers.append(url)
        }

        var infractions: [String] = []

        for url in fichiers {
            let nom = url.lastPathComponent
            if exceptions[nom] != nil { continue }
            guard let contenu = try? String(contentsOf: url, encoding: .utf8) else { continue }

            for (index, ligne) in contenu.components(separatedBy: .newlines).enumerated() {
                let nettoyee = ligne.trimmingCharacters(in: .whitespaces)
                // Journaux : invisibles pour l'utilisateur.
                if nettoyee.contains("logger.") || nettoyee.contains("os.Logger")
                    || nettoyee.contains("privacy:") || nettoyee.contains("print(") { continue }

                // On n'inspecte QUE les littéraux de chaîne : un tiret cadratin
                // dans un commentaire de fin de ligne ne regarde personne.
                for litteral in Self.litterauxDeChaine(dans: ligne) {
                    // L'incise, c'est « — » entouré d'espaces. Un « — » seul
                    // (placeholder de valeur vide) ne matche pas.
                    guard litteral.contains(" — ") else { continue }
                    // Cas admis : séparateur entre deux valeurs dans un libellé
                    // court, du type "\(nom) — \(sous-titre)". Ce n'est pas une
                    // incise dans une phrase.
                    if litteral.contains(") — \\(") { continue }
                    infractions.append("\(nom):\(index + 1) — \(nettoyee.prefix(120))")
                    break
                }
            }
        }

        XCTAssertTrue(
            infractions.isEmpty,
            """

            Tiret cadratin en incise détecté dans du texte affiché.
            Remplace-le par un point, une virgule ou deux-points.
            Si c'est un séparateur légitime, ajoute le fichier au dictionnaire
            `exceptions` de ce test AVEC sa justification.

            """ + infractions.joined(separator: "\n")
        )
    }

    /// `KiwiProse.lisible` est la première ligne de défense : si elle cesse de
    /// nettoyer, les textes de l'IA repassent en incise sans que rien n'alerte.
    func testKiwiProseRamenoneLInciseALaPonctuationManuscrite() {
        XCTAssertEqual(
            KiwiProse.lisible("Ton fer est bas — pense aux lentilles."),
            "Ton fer est bas, pense aux lentilles."
        )
        XCTAssertEqual(KiwiProse.lisible("— Une puce déguisée."), "Une puce déguisée.")
        XCTAssertEqual(KiwiProse.lisible("Fragment tronqué —"), "Fragment tronqué")
        XCTAssertEqual(KiwiProse.lisible("  Espaces  superflues  "), "Espaces superflues")
        // Un identifiant traverse le filtre sans dommage.
        XCTAssertEqual(KiwiProse.lisible("vitD"), "vitD")
        XCTAssertEqual(KiwiProse.lisible("7"), "7")
    }

    // MARK: - Helpers

    /// Extrait les littéraux de chaîne d'une ligne Swift, contenu seul.
    /// Volontairement simple : suffisant pour du texte d'interface, où les
    /// guillemets échappés sont rares.
    private static func litterauxDeChaine(dans ligne: String) -> [String] {
        var litteraux: [String] = []
        var courant: String?
        var precedent: Character?
        for caractere in ligne {
            if caractere == "\"" && precedent != "\\" {
                if let ouvert = courant {
                    litteraux.append(ouvert)
                    courant = nil
                } else {
                    courant = ""
                }
            } else if courant != nil {
                courant?.append(caractere)
            }
            precedent = caractere
        }
        return litteraux
    }

    private func fichiersSwift(sous chemin: String) throws -> [URL] {
        let url = racine.appendingPathComponent(chemin)
        guard let enumerateur = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else {
            XCTFail("Impossible de parcourir \(chemin)")
            return []
        }
        return enumerateur.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
