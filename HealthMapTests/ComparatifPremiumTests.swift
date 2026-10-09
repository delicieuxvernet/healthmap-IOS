import XCTest
@testable import HealthMap

/// Le comparatif « Standard ou Premium ? » (maquette validée le 9 octobre
/// 2026) : ce qu'il promet. Chaque ligne doit dire ce que l'app fait vraiment,
/// Apple le vérifie.
final class ComparatifPremiumTests: XCTestCase {

    private func ligne(_ id: String) -> LigneComparatif? {
        ComparatifPremium.lignes.first { $0.id == id }
    }

    /// Dix lignes, l'essentiel seulement : la carte tient sans défiler.
    func testDixLignesEtDesIdentifiantsUniques() {
        let ids = ComparatifPremium.lignes.map(\.id)
        XCTAssertEqual(ids.count, 10)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// Le Standard garde les dictées et les photos (plafonnées), la
    /// recherche, les calories et macros, et les widgets.
    func testCeQueLeStandardGarde() {
        let gardes = ComparatifPremium.lignes
            .filter { $0.standard != .absent }
            .map(\.id)
        XCTAssertEqual(gardes, ["dictee", "photo", "recherche", "macros", "widgets"])
    }

    func testPremiumATout() {
        for ligne in ComparatifPremium.lignes {
            XCTAssertNotEqual(ligne.premium, .absent, ligne.id)
        }
    }

    /// Le Standard nomme déjà une interaction et montre le plan avec ses
    /// liens : les lignes ne promettent que ce qui est vraiment réservé.
    func testLesIntitulesNePromettentQueLeReserve() {
        XCTAssertEqual(ligne("interactions")?.libelle, "Solutions à tes interactions")
        XCTAssertEqual(ligne("plan")?.libelle, "Plan guidé pas à pas")
        XCTAssertEqual(ligne("plan")?.standard, .absent)
    }

    /// Les dictées viennent du compteur de l'app : elles ne peuvent pas
    /// dériver l'une de l'autre.
    func testLesDicteesSuiventLeQuotaDeLApp() {
        let standard = VoiceMealService.QuotaStore.dictéesGratuitesParJour
        XCTAssertEqual(standard, 2)
        XCTAssertEqual(ligne("dictee")?.standard, .parJour(standard))
        // Jamais « illimitées » : le serveur arrête un abonné à 60 par jour.
        XCTAssertEqual(ligne("dictee")?.premium, .parJour(60))
    }

    func testLesPhotosSuiventLesQuotasDuServeur() {
        XCTAssertEqual(ligne("photo")?.standard, .parJour(3))
        XCTAssertEqual(ligne("photo")?.premium, .parJour(30))
    }

    func testVoiceOverLitUnePhraseParLigne() throws {
        let dictee = try XCTUnwrap(ligne("dictee"))
        XCTAssertEqual(ComparatifPremium.descriptionVocale(dictee),
                       "Repas dictés à l'IA. Standard : 2 par jour. Premium : 60 par jour.")
        let sang = try XCTUnwrap(ligne("prise_de_sang"))
        XCTAssertEqual(ComparatifPremium.descriptionVocale(sang),
                       "Prise de sang (bêta). Standard : non inclus. Premium : inclus.")
    }

    /// Le kiwi raplapla est une vraie image du catalogue.
    func testLeKiwiRaplaplaExiste() {
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dossier = racine.appendingPathComponent("HealthMap/Resources/Assets.xcassets/fluent_kiwi_ecrase.imageset")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dossier.appendingPathComponent("fluent_kiwi_ecrase.png").path))
    }
}
