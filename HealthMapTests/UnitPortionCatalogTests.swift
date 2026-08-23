import XCTest
@testable import HealthMap

/// Quantités en unités : personne ne pèse un œuf, on en mange un (petit,
/// moyen ou gros), une banane, une pomme, deux tranches de pain. Ces tests
/// verrouillent la traduction nom d'aliment → unité, les poids retenus et
/// l'arithmétique nombre ↔ grammes ; la valeur enregistrée reste le grammage.
final class UnitPortionCatalogTests: XCTestCase {

    private func unite(_ nom: String) -> UnitPortionCatalog.Unite? {
        UnitPortionCatalog.unite(pourNom: nom)
    }

    // MARK: - Les exemples d'Arthur (23 août 2026)

    func testOeufPetitMoyenGros() {
        let oeuf = unite("Oeuf, cru")
        XCTAssertEqual(oeuf?.singulier, "œuf")
        XCTAssertEqual(oeuf?.pluriel, "œufs")
        XCTAssertEqual(oeuf?.grammes, 50)
        XCTAssertEqual(oeuf?.tailles.map(\.libelle), ["Petit", "Moyen", "Gros"])
        XCTAssertEqual(oeuf?.tailles.map(\.grammes), [42, 50, 60])
        XCTAssertEqual(oeuf?.tailleParDefaut, 1, "la taille proposée d'office est celle du milieu")
        XCTAssertEqual(oeuf?.question, "Combien d'œufs ?")
    }

    func testOeufAvecLigatureEtSansAccent() {
        XCTAssertEqual(unite("Œuf dur")?.singulier, "œuf")
        XCTAssertEqual(unite("œufs brouillés")?.singulier, "œuf")
        XCTAssertEqual(unite("Oeufs au plat")?.singulier, "œuf")
    }

    func testBananeEtPommeSontDesPiecesFeminines() {
        let banane = unite("Banane, pulpe, crue")
        XCTAssertEqual(banane?.singulier, "banane")
        XCTAssertEqual(banane?.grammes, 120)
        XCTAssertEqual(banane?.tailles.map(\.libelle), ["Petite", "Moyenne", "Grosse"])

        let pomme = unite("Pomme, pulpe et peau, crue")
        XCTAssertEqual(pomme?.singulier, "pomme")
        XCTAssertEqual(pomme?.grammes, 150)
        XCTAssertEqual(pomme?.question, "Combien de pommes ?")
    }

    func testPouletEtPatesDuDejeunerDArthur() {
        // « du poulet avec un œuf et des pâtes »
        XCTAssertEqual(unite("Poulet, blanc, sans peau, cuit")?.singulier, "filet")
        XCTAssertEqual(unite("Pâtes alimentaires, cuites")?.singulier, "assiette")
        XCTAssertEqual(unite("Pâtes alimentaires, cuites")?.tailles.map(\.libelle), ["Petite", "Moyenne", "Grande"])
    }

    // MARK: - Priorités et exceptions

    func testPommeDeTerreAvantPomme() {
        XCTAssertEqual(unite("Pomme de terre, cuite à l'eau")?.singulier, "pomme de terre")
        XCTAssertEqual(unite("Pomme de terre, cuite à l'eau")?.pluriel, "pommes de terre")
        XCTAssertEqual(unite("Tomate cerise, crue")?.singulier, "tomate cerise")
        XCTAssertEqual(unite("Tomate, crue")?.singulier, "tomate")
    }

    func testCompoteEtJusNeSontPasDesFruitsALaPiece() {
        XCTAssertEqual(unite("Compote de pomme")?.singulier, "pot")
        XCTAssertEqual(unite("Jus d'orange")?.singulier, "verre")
        XCTAssertEqual(unite("Tarte aux pommes")?.singulier, "part")
    }

    func testPatesCruesRestentEnGrammes() {
        XCTAssertNil(unite("Pâtes alimentaires, crues"))
        XCTAssertNil(unite("Riz blanc, cru"))
        XCTAssertNil(unite("Pâte feuilletée"), "une pâte à tarte n'est pas une assiette de pâtes")
    }

    func testChocolatChaudAvantCarreDeChocolat() {
        XCTAssertEqual(unite("Chocolat chaud")?.singulier, "tasse")
        XCTAssertEqual(unite("Chocolat noir 70 %")?.singulier, "carré")
        XCTAssertEqual(unite("Mousse au chocolat")?.singulier, "pot")
        XCTAssertEqual(unite("Glace au chocolat")?.singulier, "boule")
    }

    func testAlimentsPesesN_ontPasD_unite() {
        XCTAssertNil(unite("Lardons"))
        XCTAssertNil(unite("Champignon de Paris"))
        XCTAssertNil(unite("Farine de blé"))
        XCTAssertNil(unite("Gaufrette"), "« gaufrette » n'est pas une gaufre")
        XCTAssertNil(unite(""))
    }

    /// Pièges de sous-chaînes : un motif sans frontière de mot attrape des
    /// aliments qui n'ont rien à voir (« macaroni » ≠ « macaron »).
    func testSousChainesPiegees() {
        XCTAssertEqual(unite("Macaroni, cuits")?.singulier, "assiette")
        XCTAssertEqual(unite("Edamame, cuit")?.singulier, "portion")
        XCTAssertEqual(unite("Sucre glace")?.singulier, "cuillère")
        XCTAssertEqual(unite("Gâteau sec")?.singulier, "biscuit")
        XCTAssertEqual(unite("Pâte à tartiner aux noisettes")?.singulier, "cuillère")
        XCTAssertEqual(unite("Tartine de pain beurrée")?.singulier, "tartine")
    }

    // MARK: - Repli sur la portion « 1 … » du serveur

    func testPortionServeurUneUnite() {
        // Le serveur vocal a estimé le poids d'une pièce : chips Petite / « 1 unité » / Grande.
        let u = UnitPortionCatalog.unite(pourNom: "Cœur de canard",
                                         portions: [(label: "Petite", grammes: 42),
                                                    (label: "1 unité", grammes: 60),
                                                    (label: "Grande", grammes: 90)])
        XCTAssertEqual(u?.singulier, "unité")
        XCTAssertEqual(u?.pluriel, "unités")
        XCTAssertEqual(u?.grammes, 60)
        XCTAssertTrue(u?.tailles.isEmpty ?? false)
        XCTAssertEqual(u?.libelle(nombre: 3), "3 unités")
    }

    func testPortionServeurIgnoreLes100gEtLesParentheses() {
        let u = UnitPortionCatalog.unite(pourNom: "Produit inconnu",
                                         portions: [(label: "100 g", grammes: 100),
                                                    (label: "1 tranche (30 g)", grammes: 30)])
        XCTAssertEqual(u?.singulier, "tranche")
        XCTAssertEqual(u?.grammes, 30)
        XCTAssertNil(UnitPortionCatalog.unite(pourNom: "Produit inconnu",
                                              portions: [(label: "100 g", grammes: 100)]))
    }

    func testLeCatalogueGagneSurLaPortionServeur() {
        let u = UnitPortionCatalog.unite(pourNom: "Oeuf, cru",
                                         portions: [(label: "1 unité", grammes: 55)])
        XCTAssertEqual(u?.singulier, "œuf")
        XCTAssertEqual(u?.grammes, 50)
    }

    // MARK: - Libellés

    func testLibelleSingulierPlurielEtDemi() {
        let oeuf = unite("Oeuf")!
        XCTAssertEqual(oeuf.libelle(nombre: 1), "1 œuf")
        XCTAssertEqual(oeuf.libelle(nombre: 2), "2 œufs")
        XCTAssertEqual(oeuf.libelle(nombre: 1.5), "1,5 œuf", "en français, le pluriel commence à 2")
        XCTAssertEqual(oeuf.libelle(nombre: 0), "0 œuf")
        XCTAssertEqual(oeuf.lienCompter, "Compter en œufs")
    }

    func testPlurielDuPremierMotSeulement() {
        XCTAssertEqual(UnitPortionCatalog.pluriel(de: "tranche de pain"), "tranches de pain")
        XCTAssertEqual(UnitPortionCatalog.pluriel(de: "morceau"), "morceaux")
        XCTAssertEqual(UnitPortionCatalog.pluriel(de: "unité"), "unités")
        XCTAssertEqual(UnitPortionCatalog.pluriel(de: "radis"), "radis")
        XCTAssertEqual(UnitPortionCatalog.pluriel(de: "noix"), "noix")
    }

    func testQuestionAvecHAspire() {
        XCTAssertEqual(unite("Hot-dog")?.question, "Combien de hot-dogs ?")
        XCTAssertEqual(unite("Huîtres")?.question, "Combien d'huîtres ?")
    }

    // MARK: - Arithmétique nombre ↔ grammes

    func testNombreArrondiAuDemi() {
        XCTAssertEqual(UnitPortionCatalog.nombre(grammes: 50, poidsUnite: 50), 1)
        XCTAssertEqual(UnitPortionCatalog.nombre(grammes: 100, poidsUnite: 50), 2)
        XCTAssertEqual(UnitPortionCatalog.nombre(grammes: 75, poidsUnite: 50), 1.5)
        XCTAssertEqual(UnitPortionCatalog.nombre(grammes: 60, poidsUnite: 50), 1, "60 g d'œuf de 50 g : 1,2 → 1")
        XCTAssertEqual(UnitPortionCatalog.nombre(grammes: 0, poidsUnite: 50), 0)
        XCTAssertEqual(UnitPortionCatalog.nombre(grammes: 50, poidsUnite: 0), 0)
    }

    func testNombreSuivantAuPasDe1JamaisSous1() {
        XCTAssertEqual(UnitPortionCatalog.nombreSuivant(0, delta: 1), 1, "depuis « quantité ? », le premier + pose 1")
        XCTAssertEqual(UnitPortionCatalog.nombreSuivant(1, delta: 1), 2)
        XCTAssertEqual(UnitPortionCatalog.nombreSuivant(1.5, delta: 1), 2)
        XCTAssertEqual(UnitPortionCatalog.nombreSuivant(1.5, delta: -1), 1)
        XCTAssertEqual(UnitPortionCatalog.nombreSuivant(2, delta: -1), 1)
        XCTAssertEqual(UnitPortionCatalog.nombreSuivant(1, delta: -1), 1)
    }

    func testPoidsParTaille() {
        let oeuf = unite("Oeuf")!
        XCTAssertEqual(oeuf.poids(taille: 0), 42)
        XCTAssertEqual(oeuf.poids(taille: 2), 60)
        XCTAssertEqual(oeuf.poids(taille: nil), 50)
        XCTAssertEqual(oeuf.poids(taille: 9), 50, "index hors tailles → poids moyen")
        let tranche = unite("Pain de mie")!
        XCTAssertEqual(tranche.poids(taille: nil), 30)
    }

    /// Les poids « 1 pièce » doivent rester alignés sur la table
    /// PORTION_PIECE_DEFAUT de l'edge function parse-meal-voice, sinon le
    /// « 1 œuf » dicté (serveur) et le « 1 œuf » tapé (app) pèseraient différemment.
    func testPoidsAlignesSurLeServeurVocal() {
        XCTAssertEqual(unite("Oeuf")?.grammes, 50)
        XCTAssertEqual(unite("Banane")?.grammes, 120)
        XCTAssertEqual(unite("Pomme")?.grammes, 150)
        XCTAssertEqual(unite("Clémentine")?.grammes, 70)
        XCTAssertEqual(unite("Kiwi")?.grammes, 70)
        XCTAssertEqual(unite("Yaourt nature")?.grammes, 125)
        XCTAssertEqual(unite("Croissant")?.grammes, 60)
        XCTAssertEqual(unite("Expresso")?.grammes, 60)
        XCTAssertEqual(unite("Café")?.grammes, 200)
        XCTAssertEqual(unite("Coca-Cola canette")?.grammes, 330)
        XCTAssertEqual(unite("Vin rouge")?.grammes, 120)
        XCTAssertEqual(unite("Confiture de fraises")?.grammes, 20)
        XCTAssertEqual(unite("Pâte à tartiner aux noisettes")?.grammes, 15)
    }

    /// Tous les motifs du catalogue doivent compiler : un motif invalide est
    /// ignoré silencieusement en Release, ce test le rend visible.
    func testTousLesMotifsSontValides() {
        // Si un motif ne compile pas, l'entrée manque et l'un de ces aliments
        // très courants n'a plus d'unité.
        let attendus: [String: String] = [
            "Oeuf": "œuf", "Banane": "banane", "Pomme": "pomme", "Pain de mie": "tranche",
            "Yaourt nature": "pot", "Camembert": "part", "Jambon blanc": "tranche",
            "Saumon, cuit": "pavé", "Steak haché": "steak", "Riz blanc, cuit": "assiette",
            "Lentilles, cuites": "portion", "Amandes": "poignée", "Café": "tasse",
            "Bière": "verre", "Pizza": "part", "Sandwich jambon": "sandwich",
            "Biscuit petit beurre": "biscuit", "Barre de céréales": "barre", "Carotte": "carotte",
        ]
        for (nom, singulier) in attendus {
            XCTAssertEqual(unite(nom)?.singulier, singulier, nom)
        }
    }
}
