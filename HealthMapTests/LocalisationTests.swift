import XCTest
@testable import HealthMap

// MARK: - Kiwio en anglais : les garde-fous du catalogue (14 oct. 2026)
//
// Le catalogue `Partage/Localizable.xcstrings` est compilé en une table
// `Localizable.strings` par langue. Ces tests lisent la table anglaise
// directement (la suite tourne en français, cf. le scheme `HealthMap`).
final class LocalisationTests: XCTestCase {

    private func table(_ langue: String) -> [String: String]? {
        guard let chemin = Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                            inDirectory: nil, forLocalization: langue) else { return nil }
        return NSDictionary(contentsOfFile: chemin) as? [String: String]
    }

    /// iOS ne choisit qu'une langue dont le dossier `.lproj` existe : sans
    /// `fr.lproj`, un iPhone en français afficherait l'anglais.
    func testLAppDeclareLeFrancaisEtLAnglais() {
        let langues = Bundle.main.localizations
        XCTAssertTrue(langues.contains("fr"), "Langues du bundle : \(langues)")
        XCTAssertTrue(langues.contains("en"), "Langues du bundle : \(langues)")
    }

    /// La suite de tests vérifie des textes français : l'app doit s'y voir en français.
    func testLesTestsTournentEnFrancais() {
        XCTAssertTrue(Langue.estFrancais, "Langue choisie : \(Bundle.main.preferredLocalizations)")
        XCTAssertEqual(Langue.texte("Ton déjeuner"), "Ton déjeuner")
        XCTAssertEqual(Langue.locale.identifier, "fr_FR")
    }

    func testLaTableAnglaiseEstEmbarquee() throws {
        let en = try XCTUnwrap(table("en"), "en.lproj/Localizable.strings absent du bundle")
        XCTAssertGreaterThan(en.count, 500)
    }

    /// En français, rien ne change : si une table française existe, chaque
    /// valeur est sa propre clé.
    func testLeFrancaisResteIdentique() {
        guard let fr = table("fr") else { return }
        let modifies = fr.filter { $0.key != $0.value }
        XCTAssertTrue(modifies.isEmpty, "Textes français modifiés : \(Array(modifies.prefix(5)))")
    }

    /// La même règle de vocabulaire qu'en français (`VoiceComplianceTests`).
    func testAucunMotProscritEnAnglais() throws {
        let en = try XCTUnwrap(table("en"))
        let proscrit = try NSRegularExpression(
            pattern: #"\b(deficien\w*|diagnos\w*|diseases?|patients?|cures?|prescri\w*)\b"#,
            options: [.caseInsensitive])
        let fautifs = en.values.filter {
            proscrit.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil
        }
        XCTAssertTrue(fautifs.isEmpty, "Mots proscrits : \(Array(fautifs.prefix(5)))")
    }

    /// Une traduction garde autant d'emplacements (`%lld`, `%@`…) que sa clé :
    /// sinon l'app planterait ou afficherait n'importe quoi.
    func testLesEmplacementsCorrespondent() throws {
        let en = try XCTUnwrap(table("en"))
        let emplacement = try NSRegularExpression(
            pattern: #"%(\d+\$)?[-+0#]*\d*(\.\d+)?(hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA]"#)
        func compte(_ s: String) -> Int {
            let t = s.replacingOccurrences(of: "%%", with: "")
            return emplacement.numberOfMatches(in: t, range: NSRange(t.startIndex..., in: t))
        }
        let fautifs = en.filter { compte($0.key) != compte($0.value) }
        XCTAssertTrue(fautifs.isEmpty, "Emplacements différents : \(Array(fautifs.prefix(5)))")
    }
}
