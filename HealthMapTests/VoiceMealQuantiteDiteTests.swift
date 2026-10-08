import XCTest
@testable import HealthMap

/// Ce qui est dit dans le vocal fait foi (retour d'Arthur, 30 sept. 2026).
/// « Deux cuillères d'huile d'olive » s'affichaient « 3 cuillères » : l'écran
/// divisait les 28 g du serveur par SA propre cuillère (10 g). Désormais le
/// serveur renvoie le compte dit et le poids d'une unité, et l'écran les affiche
/// tels quels.
@MainActor
final class VoiceMealQuantiteDiteTests: XCTestCase {

    private func item(_ json: String) throws -> VoiceMealService.Item {
        try JSONDecoder().decode(VoiceMealService.Item.self, from: Data(json.utf8))
    }

    func testDeuxCuilleresDHuileRestentDeux() throws {
        let huile = try item("""
        {"index":0,"foodId":"ciqual:17270","nom":"Huile d'olive vierge extra","g":28,
         "besoin_quantite":false,"confiance":0.95,"kcal":252,"portions":[{"label":"1 c. à s.","grammes":10}],
         "libelle":"huile d'olive","statut":"compris","alternatives":[],
         "quantite_dite":{"valeur":2,"unite":"cuillere_soupe","singulier":"c. à soupe","pluriel":"c. à soupe","poids_unite_g":13.8}}
        """)
        let unite = try XCTUnwrap(VoiceMealSheet.unite(pour: huile))
        XCTAssertEqual(unite.grammes, 13.8)
        XCTAssertTrue(unite.tailles.isEmpty)
        XCTAssertEqual(UnitPortionCatalog.nombre(grammes: 28, poidsUnite: unite.grammes), 2)
        XCTAssertEqual(unite.libelle(nombre: 2), "2 c. à soupe")
    }

    func testPieceGardeLeMotDuCatalogueEtLePoidsDuServeur() throws {
        let oeufs = try item("""
        {"index":1,"foodId":"ciqual:22010","nom":"Oeuf, dur","g":100,"besoin_quantite":false,
         "confiance":0.9,"kcal":134,"portions":[],"statut":"compris",
         "quantite_dite":{"valeur":2,"unite":"piece","singulier":"pièce","pluriel":"pièces","poids_unite_g":50}}
        """)
        let unite = try XCTUnwrap(VoiceMealSheet.unite(pour: oeufs))
        XCTAssertEqual(unite.singulier, "œuf")
        XCTAssertEqual(unite.grammes, 50)
        XCTAssertTrue(unite.tailles.isEmpty)
    }

    /// « Deux noix » : la pièce dite, avec le poids du serveur, et la poignée
    /// proposée à côté — plus « 2 poignées · 10 g » (7 oct. 2026).
    func testDeuxNoixSontDeuxPiecesEtLaPoigneeResteProposee() throws {
        let noix = try item("""
        {"index":0,"foodId":"ciqual:15005","nom":"Noix, séchée, cerneaux","g":10,"besoin_quantite":false,
         "confiance":0.9,"kcal":70,"portions":[{"label":"1 poignée","grammes":30}],"statut":"compris",
         "quantite_dite":{"valeur":2,"unite":"piece","singulier":"pièce","pluriel":"pièces","poids_unite_g":5}}
        """)
        let unite = try XCTUnwrap(VoiceMealSheet.unite(pour: noix))
        XCTAssertEqual(unite.libelle(nombre: 2), "2 pièces")
        XCTAssertEqual(unite.grammes, 5)
        XCTAssertEqual(VoiceMealSheet.unitesProposees(pour: noix).map(\.singulier), ["pièce", "poignée"])
    }

    func testAncienneReponseSansChampsDitsResteDecodable() throws {
        let ancien = try item("""
        {"index":0,"foodId":"ciqual:9104","nom":"Riz blanc, cuit","g":null,
         "besoin_quantite":true,"confiance":0.9,"kcal":null,"portions":[]}
        """)
        XCTAssertNil(ancien.statut)
        XCTAssertFalse(ancien.aVerifier)
        XCTAssertNil(ancien.quantiteDite)
    }

    func testStatutsEtAlternatives() throws {
        let poulet = try item("""
        {"index":0,"foodId":"ciqual:36018","nom":"Poulet, filet, sans peau, sauté/poêlé","g":null,
         "besoin_quantite":true,"confiance":0.85,"kcal":null,"portions":[],"libelle":"poulet",
         "statut":"defaut","alternatives":[{"foodId":"ciqual:36004","nom":"Poulet, cuisse","marque":null,"kcal_100g":213}]}
        """)
        XCTAssertTrue(poulet.parDefaut)
        XCTAssertFalse(poulet.aVerifier)
        XCTAssertEqual(poulet.alternatives?.first?.foodId, "ciqual:36004")
    }

    func testRepasNonDitNeSeDevinePas() {
        XCTAssertNil(VoiceMealService.slotDit("inconnu"))
        XCTAssertEqual(VoiceMealService.slotDit("dejeuner"), .lunch)
    }
}
