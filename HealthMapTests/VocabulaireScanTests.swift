import XCTest

/// Garde-fou de vocabulaire sur l'écran Scan et la dictée vocale.
///
/// Kiwio compte des calories, il ne fait pas de médecine. Les mots « carence »,
/// « diagnostic », « patient » et « maladie » installent un registre clinique
/// que ni le produit ni la réglementation ne permettent d'assumer sur cette
/// surface (EU 1924/2006 sur les allégations, position ANSES sur « carence »
/// réservé au constat biologique). Le remplacement retenu côté produit est
/// « apport insuffisant ».
///
/// ⚠️ PÉRIMÈTRE VOLONTAIREMENT LIMITÉ à `Views/MealScan/` et au service vocal.
/// Une interdiction sur tout le dépôt casserait des textes légitimes et, pour
/// certains, obligatoires :
///   - « Maladie cœliaque » — intitulé d'une question du questionnaire santé ;
///     c'est le nom de la pathologie, on ne peut pas le paraphraser ;
///   - le disclaimer de `RedFlag` — il DOIT contenir le mot « diagnostic »,
///     puisque sa fonction est précisément de dire que ce n'en est pas un ;
///   - « Patiente une minute » dans `HealthMapError` — verbe patienter, pas le
///     nom « patient » (d'où la recherche par frontière de mot).
/// Élargir ce test à d'autres dossiers demande d'abord d'arbitrer ces cas.
final class VocabulaireScanTests: XCTestCase {

    /// Racine du dépôt, déduite de l'emplacement de ce fichier à la compilation.
    /// `Bundle` ne convient pas ici : on inspecte du code source, pas une
    /// ressource embarquée dans le binaire de test.
    private var racine: URL {
        URL(fileURLWithPath: #filePath)      // …/HealthMapTests/VocabulaireScanTests.swift
            .deletingLastPathComponent()     // …/HealthMapTests
            .deletingLastPathComponent()     // …/ (racine du dépôt)
    }

    private static let interdits = ["carence", "diagnostic", "patient", "maladie"]

    func testAucunVocabulaireMedicalDansLesTextesDuScan() throws {
        let dossiers = [
            "HealthMap/Views/MealScan",
            "HealthMap/Services/VoiceMealService.swift",
            "HealthMap/Services/SpeechCaptureService.swift",
        ]

        var fichiers: [URL] = []
        for chemin in dossiers {
            let url = racine.appendingPathComponent(chemin)
            var estDossier: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &estDossier) else {
                XCTFail("Chemin surveillé introuvable : \(chemin) — le test ne surveille plus rien.")
                continue
            }
            if estDossier.boolValue {
                let contenu = try FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil
                )
                fichiers += contenu.filter { $0.pathExtension == "swift" }
            } else {
                fichiers.append(url)
            }
        }

        XCTAssertFalse(fichiers.isEmpty, "Aucun fichier scanné : le garde-fou serait vert à tort.")

        var fautes: [String] = []

        for fichier in fichiers {
            let source = try String(contentsOf: fichier, encoding: .utf8)
            for (numero, ligne) in source.components(separatedBy: .newlines).enumerated() {
                let nue = ligne.trimmingCharacters(in: .whitespaces)
                // Les commentaires expliquent le code et s'adressent aux
                // développeurs — ce test ne juge que ce que l'utilisateur lit.
                guard !nue.hasPrefix("//"), !nue.hasPrefix("///") else { continue }

                for texte in Self.chainesLitterales(de: ligne) {
                    for mot in Self.interdits where Self.contient(mot, dans: texte) {
                        fautes.append(
                            "\(fichier.lastPathComponent):\(numero + 1) — « \(mot) » dans « \(texte) »"
                        )
                    }
                }
            }
        }

        XCTAssertTrue(
            fautes.isEmpty,
            """
            Vocabulaire médical dans l'interface du Scan :
            \(fautes.joined(separator: "\n"))

            Kiwio compte des calories. Écrire « apport insuffisant » plutôt que
            « carence », et ne rien formuler qui ressemble à un avis médical.
            """
        )
    }

    /// Extrait les chaînes entre guillemets doubles d'une ligne de Swift.
    ///
    /// Volontairement simple : on ne cherche pas à analyser le langage, juste à
    /// isoler ce qui a une chance d'être affiché. Les échappements `\"` sont
    /// rares dans nos libellés ; au pire on coupe une chaîne en deux, ce qui
    /// peut faire manquer une faute mais n'en invente jamais.
    private static func chainesLitterales(de ligne: String) -> [String] {
        var resultat: [String] = []
        var courante = ""
        var dedans = false
        for caractere in ligne {
            if caractere == "\"" {
                if dedans { resultat.append(courante); courante = "" }
                dedans.toggle()
            } else if dedans {
                courante.append(caractere)
            }
        }
        return resultat
    }

    /// Recherche par frontière de mot, insensible à la casse et aux accents.
    ///
    /// Sans la frontière, « patiente » (verbe) et « diagnostique » (adjectif)
    /// déclencheraient à tort. Sans l'insensibilité aux accents, « carencé »
    /// passerait au travers.
    private static func contient(_ mot: String, dans texte: String) -> Bool {
        let motifs = "\\b\(mot)s?\\b"
        guard let regex = try? NSRegularExpression(
            pattern: motifs,
            options: [.caseInsensitive]
        ) else { return false }

        let neutre = texte.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        let plage = NSRange(neutre.startIndex..., in: neutre)
        return regex.firstMatch(in: neutre, range: plage) != nil
    }
}
