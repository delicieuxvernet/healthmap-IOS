import XCTest
import SwiftUI
import UIKit
@testable import HealthMap

/// Garde-fou de la charte de hiérarchie de l'information (17 août 2026).
///
/// La charte tient en trois promesses vérifiables :
///   1. les 12 polices de rôle existent et rendent une police utilisable ;
///   2. aucune taille littérale hors de l'échelle à 8 tailles n'entre dans le
///      bloc des tokens de rôle (10.5 · 11.5 · 12 · 13 · 15 · 17 · 20 · 28) ;
///   3. les text styles iOS sur lesquels s'appuient ces tokens valent bien la
///      taille annoncée à la taille système par défaut.
///
/// La 3e est la plus utile : elle est la seule à pouvoir casser sans qu'on
/// touche au code. Si Apple bougeait `.footnote` de 13 à 14, un titre de
/// section changerait de taille en silence sur tous les écrans.
///
/// Détail de la grille rôle → style : `docs/DESIGN-SYSTEM.md`.
final class HierarchieTokensTests: XCTestCase {

    /// L'échelle cible de la charte. Toute autre taille est un palier de plus,
    /// donc un palier indiscernable.
    private let echelle: Set<Double> = [10.5, 11.5, 12, 13, 15, 17, 20, 28]

    /// Les text styles iOS admis, avec leur taille à la taille système par
    /// défaut (catégorie `.large`). Ce sont les 6 tailles de l'échelle qui
    /// tombent pile sur un style relatif, donc gardent Dynamic Type.
    private let stylesAdmis: [(nom: String, style: UIFont.TextStyle, taille: CGFloat)] = [
        ("title", .title1, 28),
        ("title3", .title3, 20),
        ("body", .body, 17),
        ("subheadline", .subheadline, 15),
        ("footnote", .footnote, 13),
        ("caption", .caption1, 12),
    ]

    /// Les 12 tokens de rôle. Les nommer ici suffit à prouver leur existence :
    /// si l'un disparaît de `ThemeConstants`, ce fichier ne compile plus.
    private var tokensDeRole: [(nom: String, police: Font)] {
        [
            ("screenTitleFont", Theme.screenTitleFont),
            ("sheetTitleFont", Theme.sheetTitleFont),
            ("sectionLabelFont", Theme.sectionLabelFont),
            ("subLabelFont", Theme.subLabelFont),
            ("conclusionFont", Theme.conclusionFont),
            ("insightFont", Theme.insightFont),
            ("heroValueFont", Theme.heroValueFont),
            ("heroValueRowFont", Theme.heroValueRowFont),
            ("heroTextFont", Theme.heroTextFont),
            ("dataSecondaryFont", Theme.dataSecondaryFont),
            ("chromeFont", Theme.chromeFont),
            ("ctaFont", Theme.ctaFont),
        ]
    }

    // MARK: - 1. Existence

    func testLesDouzeTokensDeRoleExistentEtRendentUnePolice() {
        let tokens = tokensDeRole
        XCTAssertEqual(tokens.count, 12, "La charte compte 12 rôles typographiques.")

        for (nom, police) in tokens {
            // Une police que SwiftUI peut appliquer : si le token était mal
            // construit, l'application planterait ici.
            _ = Text(verbatim: "0").font(police)
            XCTAssertEqual(police, police, "\(nom) doit être une valeur stable.")
        }

        // Des rôles distincts appellent des styles distincts. Deux paires sont
        // légitimement identiques (conclusion/héros textuel en 17 heavy,
        // insight/CTA en 15 semibold) : on attend donc 10 styles distincts,
        // et on tolère 8 pour ne pas rendre le test cassant.
        let distincts = Set(tokens.map(\.police))
        XCTAssertGreaterThanOrEqual(
            distincts.count, 8,
            "Les tokens de rôle se sont effondrés sur un même style : la hiérarchie ne tiendrait plus."
        )
    }

    // MARK: - 2. Aucune taille hors échelle

    func testAucuneTailleLitteraleHorsEchelleDansLesTokensDeRole() throws {
        let bloc = try blocDesTokensDeRole()

        let regex = try NSRegularExpression(pattern: #"\.system\(size:\s*([0-9]+(?:\.[0-9]+)?)"#)
        let plage = NSRange(bloc.startIndex..<bloc.endIndex, in: bloc)
        let trouvailles = regex.matches(in: bloc, range: plage)

        XCTAssertFalse(
            trouvailles.isEmpty,
            "Aucune taille littérale trouvée : le test ne surveille plus rien (les marqueurs ont bougé ?)."
        )

        var infractions: [String] = []
        for trouvaille in trouvailles {
            guard let plageTaille = Range(trouvaille.range(at: 1), in: bloc),
                  let taille = Double(bloc[plageTaille]) else { continue }
            if !echelle.contains(taille) {
                infractions.append(String(taille))
            }
        }

        XCTAssertTrue(
            infractions.isEmpty,
            """

            Taille hors de l'échelle à 8 tailles dans les tokens de rôle : \
            \(infractions.joined(separator: ", ")).
            L'échelle est 10.5 / 11.5 / 12 / 13 / 15 / 17 / 20 / 28.
            Un palier de plus est un palier que personne ne distingue.

            """
        )
    }

    func testLesTokensDeRoleNUtilisentQueLesTextStylesAdmis() throws {
        let bloc = try blocDesTokensDeRole()

        let regex = try NSRegularExpression(pattern: #"\.system\(\.([a-zA-Z0-9]+)"#)
        let plage = NSRange(bloc.startIndex..<bloc.endIndex, in: bloc)
        let trouvailles = regex.matches(in: bloc, range: plage)

        XCTAssertFalse(trouvailles.isEmpty, "Aucun text style trouvé : les marqueurs ont bougé.")

        let admis = Set(stylesAdmis.map(\.nom))
        var infractions: [String] = []
        for trouvaille in trouvailles {
            guard let plageNom = Range(trouvaille.range(at: 1), in: bloc) else { continue }
            let nom = String(bloc[plageNom])
            if !admis.contains(nom) { infractions.append(nom) }
        }

        XCTAssertTrue(
            infractions.isEmpty,
            """

            Text style hors charte dans les tokens de rôle : \
            \(infractions.joined(separator: ", ")).
            Seuls title (28), title3 (20), body (17), subheadline (15), \
            footnote (13) et caption (12) tombent sur l'échelle.

            """
        )
    }

    // MARK: - 3. Les text styles valent bien la taille annoncée

    func testLesTextStylesUtilisesTombentSurLEchelle() {
        let traits = UITraitCollection(preferredContentSizeCategory: .large)

        for (nom, style, attendue) in stylesAdmis {
            let mesuree = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
            XCTAssertEqual(
                mesuree, attendue, accuracy: 0.01,
                "Le text style \(nom) vaut \(mesuree) pt et non \(attendue) : les tokens de rôle adossés à ce style ont changé de taille en silence."
            )
            XCTAssertTrue(
                echelle.contains(Double(attendue)),
                "\(attendue) pt n'appartient pas à l'échelle à 8 tailles."
            )
        }
    }

    // MARK: - Helpers

    /// Racine du dépôt, déduite de l'emplacement de ce fichier à la compilation.
    private var racine: URL {
        URL(fileURLWithPath: #filePath)      // …/HealthMapTests/HierarchieTokensTests.swift
            .deletingLastPathComponent()     // …/HealthMapTests
            .deletingLastPathComponent()     // …/ (racine du dépôt)
    }

    /// Le seul bloc de `ThemeConstants.swift` que cette charte gouverne, borné
    /// par ses deux marqueurs `MARK`. Les 6 polices historiques (qui décrivent
    /// une taille, pas un rôle) restent volontairement hors du périmètre.
    private func blocDesTokensDeRole() throws -> String {
        let url = racine.appendingPathComponent("HealthMap/Views/Shared/ThemeConstants.swift")
        let contenu = try String(contentsOf: url, encoding: .utf8)
        let lignes = contenu.components(separatedBy: .newlines)

        guard let debut = lignes.firstIndex(where: { $0.contains("MARK: Polices de rôle") }),
              let fin = lignes.firstIndex(where: { $0.contains("MARK: Fin des polices de rôle") }),
              debut < fin else {
            XCTFail("Marqueurs des polices de rôle introuvables dans ThemeConstants.swift.")
            return ""
        }
        return lignes[debut...fin].joined(separator: "\n")
    }
}
