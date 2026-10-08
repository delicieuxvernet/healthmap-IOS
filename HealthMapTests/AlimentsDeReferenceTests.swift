import XCTest
@testable import HealthMap

// MARK: - Aliments de référence du brief (8 oct. 2026)
//
// La table ne porte que des codes Ciqual et des portions : le chiffre vient de
// la composition, calculé comme pour un repas noté. Ces tests tiennent les
// trois promesses : reconnaître les noms du bilan, ne rien deviner, et chiffrer
// exactement comme le Journal.

final class AlimentsDeReferenceTests: XCTestCase {

    private func nom(_ texte: String) -> String? {
        AlimentsDeReference.trouver(texte)?.nom
    }

    func testTrouver_reconnaitLesNomsEcritsParLeBilan() {
        XCTAssertEqual(nom("Sardines en boîte"), "Sardines")
        XCTAssertEqual(nom("Sardines (avec arêtes)"), "Sardines")
        XCTAssertEqual(nom("saumon vapeur"), "Saumon")
        XCTAssertEqual(nom("Œufs"), "Œufs")
        XCTAssertEqual(nom("oeuf entier"), "Œufs")
        XCTAssertEqual(nom("Jaune d'œuf"), "Jaune d'œuf")
        XCTAssertEqual(nom("Brocoli cuit à la vapeur"), "Brocoli")
        XCTAssertEqual(nom("Epinards sautés"), "Épinards")
        XCTAssertEqual(nom("Chocolat noir 70%"), "Chocolat noir")
        XCTAssertEqual(nom("Graines de lin moulues"), "Graines de lin")
        XCTAssertEqual(nom("Lieu, colin"), "Lieu")
        XCTAssertEqual(nom("Thon en boîte"), "Thon")
        XCTAssertEqual(nom("Thon frais"), "Thon frais")
        XCTAssertEqual(nom("Kiwis"), "Kiwi")
        XCTAssertEqual(nom("Poivron cru"), "Poivron")
        XCTAssertEqual(nom("Bœuf"), "Viande rouge")
        XCTAssertEqual(nom("Steak hache"), "Steak haché")
        XCTAssertEqual(nom("Lait demi-écrémé"), "Lait")
    }

    func testTrouver_neDevinePas() {
        // Un autre aliment, un produit enrichi, une famille : pas de chiffre.
        XCTAssertNil(nom("Noix de coco"))
        XCTAssertNil(nom("Lait enrichi"))
        XCTAssertNil(nom("Boisson d'avoine enrichie"))
        XCTAssertNil(nom("Champignons exposés au soleil"))
        XCTAssertNil(nom("Légumineuses"))
        XCTAssertNil(nom("Poisson"))
        XCTAssertNil(nom(""))
    }

    /// Chaque nom de la table retrouve SON aliment : deux entrées qui se
    /// disputeraient un même nom se verraient ici.
    func testChaqueNomDeLaTableRetrouveSonAliment() {
        for aliment in AlimentsDeReference.tous {
            for texte in [aliment.nom] + aliment.autresNoms {
                XCTAssertEqual(AlimentsDeReference.trouver(texte)?.foodId, aliment.foodId,
                               "« \(texte) » devrait désigner \(aliment.nom)")
            }
        }
    }

    func testIdentifiants_codesCiqualSansDoublon_portionsPositives() {
        let tous = AlimentsDeReference.tous
        XCTAssertEqual(AlimentsDeReference.identifiants.count, tous.count, "un code Ciqual en double")
        for aliment in tous {
            XCTAssertTrue(aliment.foodId.hasPrefix("ciqual:"), aliment.foodId)
            XCTAssertNotNil(Int(aliment.foodId.dropFirst("ciqual:".count)), aliment.foodId)
            XCTAssertGreaterThan(aliment.grammes, 0, aliment.nom)
            XCTAssertFalse(aliment.portion.isEmpty, aliment.nom)
            if let illustration = aliment.illustration {
                XCTAssertTrue(illustration.hasPrefix("fluent_"), illustration)
            }
        }
    }

    func testApport_memeCalculQuUnRepasNote() throws {
        let sardines = try XCTUnwrap(AlimentsDeReference.trouver("Sardines"))
        let lentilles = try XCTUnwrap(AlimentsDeReference.trouver("Lentilles"))
        let compositions: Compositions = [
            sardines.foodId: CompositionAliment(estime: false, apports: ["vitD": 302.4]),
            lentilles.foodId: CompositionAliment(estime: false, apports: ["iron": 1.44]),
        ]
        // 100 g × 302,4 UI / 100 g = 302 UI, pour une référence de 1 000 UI.
        XCTAssertEqual(AlimentsDeReference.apport(sardines, nutriment: "vitD", compositions: compositions), 30)
        // 150 g × 1,44 mg / 100 g = 2,16 mg, pour une référence de 18 mg.
        XCTAssertEqual(AlimentsDeReference.apport(lentilles, nutriment: "iron", compositions: compositions), 12)
        // La référence est celle des repas notés : le chiffre d'hier et celui
        // de la portion s'additionnent sans conversion.
        XCTAssertEqual(MealJournalService.canonRDA["vitD"], 1000)
    }

    func testApport_nonRenseigne_rendNil() throws {
        let sardines = try XCTUnwrap(AlimentsDeReference.trouver("Sardines"))
        let compositions: Compositions = [
            sardines.foodId: CompositionAliment(estime: false, apports: ["vitD": 302.4]),
        ]
        XCTAssertNil(AlimentsDeReference.apport(sardines, nutriment: "vitC", compositions: compositions),
                     "« non renseigné » n'est pas « zéro »")
        XCTAssertNil(AlimentsDeReference.apport(sardines, nutriment: "vitD", compositions: [:]),
                     "composition pas encore sur le téléphone")
    }
}
