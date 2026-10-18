import XCTest
@testable import HealthMap

/// Récap du jour (maquette v5.1) : quels apports, quel aliment, quel gain.
/// Aucun chiffre écrit à la main : le pourcentage d'hier vient du brief, le
/// gain de la composition de la portion.
final class RecapDuJourTests: XCTestCase {

    private func brief(repas: Int = 3, manques: [(String, String, Int)], cible: CibleNutritionnelle? = nil) -> BriefDuJour {
        BriefDuJour(
            prenom: nil,
            repasHier: repas,
            besoinsCouvertsHier: repas >= BriefDuJourBuilder.repasMinimum ? 5 : nil,
            besoinsCouvertsAvantHier: nil,
            manquesHier: manques.map { BriefDuJour.Manque(id: $0.0, nom: $0.1, pourcent: $0.2) },
            effort: nil,
            cible: cible
        )
    }

    /// Compositions de quelques aliments de la table, pour 100 g, dans
    /// l'unité de `MealJournalService.canonRDA`.
    private let compositions: Compositions = [
        "ciqual:26034": CompositionAliment(estime: false, apports: ["vitD": 300, "omega3": 1.6, "iron": 2.9]),   // sardines
        "ciqual:26038": CompositionAliment(estime: false, apports: ["vitD": 500, "omega3": 2.0]),                // saumon
        "ciqual:22010": CompositionAliment(estime: false, apports: ["vitD": 80, "iron": 1.8, "vitB12": 1.0]),    // œufs
        "ciqual:20505": CompositionAliment(estime: false, apports: ["iron": 3.3, "fiber": 8]),                  // lentilles
        "ciqual:8704": CompositionAliment(estime: false, apports: ["iron": 6.0]),                               // boudin noir
        "ciqual:13021": CompositionAliment(estime: false, apports: ["vitC": 90]),                               // kiwi
        "ciqual:13034": CompositionAliment(estime: false, apports: ["vitC": 50]),                               // orange
    ]

    func testRienDeNoteHier() {
        let recap = RecapDuJourBuilder.construire(brief: brief(repas: 1, manques: []), compositions: compositions)
        XCTAssertEqual(recap?.cas, .rienHier(repas: 1))
    }

    func testRienNAManqueQuandToutPasse70() {
        let recap = RecapDuJourBuilder.construire(brief: brief(manques: [("vitD", "Vitamine D", 72), ("iron", "Fer", 90)]),
                                                  compositions: compositions)
        XCTAssertEqual(recap?.cas, .rienNaManque)
    }

    func testRienAMontrerSansApportRenseigne() {
        XCTAssertNil(RecapDuJourBuilder.construire(brief: brief(manques: []), compositions: compositions))
    }

    func testDeuxColonnesDuPlusBasAuMoinsBas() throws {
        let recap = try XCTUnwrap(RecapDuJourBuilder.construire(
            brief: brief(manques: [("vitD", "Vitamine D", 22), ("iron", "Fer", 38), ("zinc", "Zinc", 50)]),
            compositions: compositions))
        guard case .manques(let colonnes) = recap.cas else { return XCTFail("deux colonnes attendues") }
        XCTAssertEqual(colonnes.map(\.id), ["vitD", "iron"])
        XCTAssertEqual(colonnes.map(\.pourcentHier), [22, 38])
        // Saumon : 500 × 130 g / 100 / 1000 × 100 = 65 points de « % du besoin ».
        XCTAssertEqual(colonnes[0].aliment?.nom, "Saumon")
        XCTAssertEqual(colonnes[0].aliment?.gain, 65)
        XCTAssertEqual(colonnes[0].aliment?.portion, "1 pavé")
        XCTAssertEqual(colonnes[0].projection, 87)
    }

    func testUneSeuleColonneQuandLeSecondEstCouvert() throws {
        let recap = try XCTUnwrap(RecapDuJourBuilder.construire(
            brief: brief(manques: [("vitD", "Vitamine D", 22), ("iron", "Fer", 80)]), compositions: compositions))
        guard case .manques(let colonnes) = recap.cas else { return XCTFail() }
        XCTAssertEqual(colonnes.map(\.id), ["vitD"])
    }

    func testLaProjectionEstPlafonneeA100() {
        let colonne = RecapDuJour.Colonne(id: "vitC", nom: "Vitamine C", pourcentHier: 60,
                                          aliment: .init(nom: "Orange", portion: "1 orange", gain: 70, illustration: nil))
        XCTAssertEqual(colonne.projection, 100)
    }

    func testJamaisDeuxFoisLeMemeAliment() throws {
        // Les sardines sont la meilleure source des deux apports ici : la
        // seconde colonne en propose une autre.
        let recap = try XCTUnwrap(RecapDuJourBuilder.construire(
            brief: brief(manques: [("omega3", "Oméga-3", 20), ("vitD", "Vitamine D", 30)]), compositions: compositions))
        guard case .manques(let colonnes) = recap.cas else { return XCTFail() }
        let noms = colonnes.compactMap(\.aliment?.nom)
        XCTAssertEqual(noms.count, Set(noms).count, noms.joined(separator: ", "))
    }

    func testAllergiePoissonPasDeSardinesNiDeSaumon() {
        let profil = ProfilAlimentaire(regime: "omnivore", allergies: ["fish_shellfish"])
        let aliment = RecapDuJourBuilder.aliment(pour: "vitD", idees: ["Saumon", "Sardines"], compositions: compositions, profil: profil)
        XCTAssertEqual(aliment?.nom, "Œufs")
    }

    func testVeganNiOeufNiPoissonNiLaitage() {
        let profil = ProfilAlimentaire(regime: "vegan")
        for nom in ["Œufs", "Sardines", "Yaourt", "Comté", "Boudin noir", "Jaune d'œuf"] {
            XCTAssertFalse(GardeFousAliments.compatible(nom, profil: profil), nom)
        }
        XCTAssertTrue(GardeFousAliments.compatible("Lentilles", profil: profil))
    }

    func testVegetarienEtHalalPasDeBoudinNoir() {
        XCTAssertFalse(GardeFousAliments.compatible("Boudin noir", profil: ProfilAlimentaire(regime: "vegetarien")))
        XCTAssertFalse(GardeFousAliments.compatible("Boudin noir", profil: ProfilAlimentaire(regime: "halal")))
        XCTAssertTrue(GardeFousAliments.compatible("Œufs", profil: ProfilAlimentaire(regime: "vegetarien")))
        let fer = RecapDuJourBuilder.aliment(pour: "iron", idees: ["Boudin noir", "Lentilles"], compositions: compositions,
                                            profil: ProfilAlimentaire(regime: "halal"))
        XCTAssertEqual(fer?.nom, "Lentilles")
    }

    func testGrossessePasDeFoie() {
        XCTAssertFalse(GardeFousAliments.compatible("Foie de volaille", profil: ProfilAlimentaire(enceinte: true)))
        XCTAssertTrue(GardeFousAliments.compatible("Foie de volaille", profil: .inconnu))
    }

    func testJamaisLeKiwi() {
        // Le kiwi apporte plus de vitamine C, mais son illustration est
        // l'ancien logo de Kiwio.
        let aliment = RecapDuJourBuilder.aliment(pour: "vitC", idees: ["Kiwi", "Orange"], compositions: compositions, profil: .inconnu)
        XCTAssertEqual(aliment?.nom, "Orange")
    }

    func testSansCompositionAucunChiffre() {
        let aliment = RecapDuJourBuilder.aliment(pour: "vitD", idees: ["Sardines"], compositions: [:], profil: .inconnu)
        XCTAssertEqual(aliment?.nom, "Sardines")
        XCTAssertNil(aliment?.gain)
        XCTAssertNil(aliment?.portion)
    }

    func testLeProfilSeGardeEtSeRelit() {
        let defaults = UserDefaults(suiteName: "RecapDuJourTests")!
        defaults.removePersistentDomain(forName: "RecapDuJourTests")
        XCTAssertEqual(BriefDuJourStore.profilAlimentaireMemorise(defaults: defaults), .inconnu)
        let profil = ProfilAlimentaire(regime: "vegan", allergies: ["nuts"], enceinte: true)
        BriefDuJourStore.memoriserProfilAlimentaire(profil, defaults: defaults)
        XCTAssertEqual(BriefDuJourStore.profilAlimentaireMemorise(defaults: defaults), profil)
    }

    func testLaChoregraphieFinitPileSurLesValeurs() {
        XCTAssertEqual(RecapChoregraphie.liquide(0, rang: 0), 0)
        XCTAssertEqual(RecapChoregraphie.liquide(RecapChoregraphie.final, rang: 1), 1)
        XCTAssertEqual(RecapChoregraphie.ajout(RecapChoregraphie.final, rang: 1), 1)
        var precedent = 0.0
        for pas in 0...100 {
            let v = RecapChoregraphie.liquide(Double(pas) * 0.05, rang: 0)
            XCTAssertGreaterThanOrEqual(v, precedent)
            precedent = v
        }
        XCTAssertEqual(SphereRecapPeintre.demiCorde(y: 0, unite: 1), 0)
        XCTAssertEqual(SphereRecapPeintre.demiCorde(y: 60, unite: 1), 55)
        XCTAssertEqual(SphereRecapPeintre.surface(niveau: 0, unite: 1), 115)
        XCTAssertEqual(SphereRecapPeintre.surface(niveau: 100, unite: 1), 5, accuracy: 0.0001)
        XCTAssertEqual(SphereRecapPeintre.surface(niveau: 250, unite: 1), 5, accuracy: 0.0001)
    }
}
