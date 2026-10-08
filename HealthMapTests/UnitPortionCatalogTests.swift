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

    func testYaourtAuLaitEntierEstUnPot() {
        // Vu sur simulateur le 23 août : « Yaourt nature au lait entier »
        // tombait sur « verre » (lait) au lieu de « pot ».
        XCTAssertEqual(unite("Yaourt nature au lait entier nature")?.singulier, "pot")
        XCTAssertEqual(unite("Fromage blanc au lait entier")?.singulier, "pot")
        XCTAssertEqual(unite("Lait entier")?.singulier, "verre")
        XCTAssertEqual(unite("Lait demi-écrémé UHT")?.singulier, "verre")
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

    // MARK: - Plusieurs unités par aliment (retour d'Arthur, 7 oct. 2026)
    // « Deux noix » proposait deux poignées ; une tablette de chocolat se
    // comptait en cuillères. Chaque aliment a désormais sa liste d'unités, la
    // première proposée d'office ; « g » est ajouté par l'écran, en dernier.

    private func unites(_ nom: String) -> [UnitPortionCatalog.Unite] {
        UnitPortionCatalog.unites(pourNom: nom)
    }

    func testTabletteDeChocolatSeCompteEnCarres() {
        let tablette = unites("Chocolat noir à 70% cacao minimum, extra, dégustation, tablette")
        XCTAssertEqual(tablette.map(\.singulier), ["carré", "tablette"],
                       "« 70% cacao » ne doit plus tomber sur le chocolat en poudre")
        XCTAssertEqual(tablette.map(\.grammes), [10, 100], "10 g le carré, comme côté serveur")
        XCTAssertEqual(tablette.first?.code, "carre")
        XCTAssertEqual(unite("Chocolat au lait, tablette")?.singulier, "carré")
        XCTAssertEqual(unite("Chocolat blanc, tablette")?.singulier, "carré")
    }

    func testChocolatEnPoudreResteEnCuilleres() {
        XCTAssertEqual(unites("Chocolat en poudre").map(\.singulier), ["cuillère"])
        XCTAssertEqual(unite("Cacao, non sucré, poudre soluble")?.singulier, "cuillère")
        XCTAssertEqual(unite("Pâte à tartiner au chocolat")?.singulier, "cuillère",
                       "une pâte à tartiner ne se compte pas en carrés")
    }

    func testNoixSeComptentALaPieceOuALaPoignee() {
        let noix = unites("Noix, séchée, cerneaux")
        XCTAssertEqual(noix.map(\.singulier), ["poignée", "pièce"])
        XCTAssertEqual(noix.map(\.grammes), [30, 5])
        XCTAssertEqual(noix.map(\.code), ["poignee", "piece"])
        XCTAssertEqual(noix.last?.libelle(nombre: 2), "2 pièces")

        XCTAssertEqual(unites("Amande, grillée, salée").map(\.grammes), [30, 1.2])
        XCTAssertEqual(unites("Noisette").map(\.grammes), [30, 1.5])
        XCTAssertEqual(unites("Noix de cajou, grillée, salée").map(\.grammes), [30, 1.5])
    }

    func testOleagineuxQuiNeSeComptentPas() {
        XCTAssertEqual(unites("Noix de coco, amande mûre, fraîche").map(\.singulier), ["poignée"])
        XCTAssertEqual(unites("Amande, poudre").map(\.singulier), ["poignée"])
        XCTAssertEqual(unites("Pistache, grillée, salée").map(\.singulier), ["poignée"])
    }

    func testHuileEnCuillereASoupeOuACafe() {
        let huile = unites("Huile d'olive vierge extra")
        XCTAssertEqual(huile.map(\.singulier), ["c. à soupe", "c. à café"])
        XCTAssertEqual(huile.map(\.grammes), [14, 4.6])
        XCTAssertEqual(huile.map(\.code), ["cuillere_soupe", "cuillere_cafe"])
    }

    func testUneSeuleUniteEtAucune() {
        XCTAssertEqual(unites("Oeuf, cru").map(\.singulier), ["œuf"])
        XCTAssertEqual(unites("Oeuf, cru").first?.code, "piece")
        XCTAssertTrue(unites("Farine de blé").isEmpty)
        XCTAssertTrue(unites("").isEmpty)
    }

    // MARK: - Unité dite dans le vocal (code serveur)

    private func dites(_ code: String, _ singulier: String, _ pluriel: String,
                       _ poids: Double, _ nom: String) -> [UnitPortionCatalog.Unite] {
        UnitPortionCatalog.unites(dites: code, singulier: singulier, pluriel: pluriel,
                                  poidsUnite: poids, parmi: unites(nom))
    }

    func testDeuxNoixDitesSontDeuxPieces() {
        let liste = dites("piece", "pièce", "pièces", 5, "Noix, séchée, cerneaux")
        XCTAssertEqual(liste.map(\.singulier), ["pièce", "poignée"])
        XCTAssertEqual(liste.first?.grammes, 5)
        XCTAssertEqual(liste.first?.libelle(nombre: 2), "2 pièces", "plus jamais « 2 poignées · 10 g »")
    }

    func testUnePoigneeDiteRestePoignee() {
        let liste = dites("poignee", "poignée", "poignées", 30, "Noix, séchée, cerneaux")
        XCTAssertEqual(liste.map(\.singulier), ["poignée", "pièce"])
        XCTAssertEqual(liste.map(\.grammes), [30, 5])
    }

    func testCarresDeChocolatDits() {
        let tablette = "Chocolat noir à 70% cacao minimum, extra, dégustation, tablette"
        XCTAssertEqual(dites("carre", "carré", "carrés", 10, tablette).map(\.singulier), ["carré", "tablette"])
        // Un serveur qui dit encore « piece » pour des carrés : le carré se
        // compte, il est retenu.
        let piece = dites("piece", "pièce", "pièces", 10, tablette)
        XCTAssertEqual(piece.first?.singulier, "carré")
        XCTAssertEqual(piece.first?.grammes, 10)
    }

    func testUnePieceDiteNeTombeJamaisSurUneMesure() {
        // Les pistaches n'ont que la poignée : la pièce dite est créée avec le
        // libellé et le poids du serveur, la poignée reste proposée ensuite.
        let liste = dites("piece", "pièce", "pièces", 0.8, "Pistache, grillée, salée")
        XCTAssertEqual(liste.map(\.singulier), ["pièce", "poignée"])
        XCTAssertEqual(liste.map(\.grammes), [0.8, 30])
        XCTAssertEqual(liste.first?.code, "piece")
    }

    func testUniteDiteInconnueDuCatalogue() {
        let liste = dites("verre", "verre", "verres", 200, "Noix, séchée, cerneaux")
        XCTAssertEqual(liste.map(\.singulier), ["verre", "poignée", "pièce"])
        XCTAssertEqual(liste.first?.code, "verre")
        XCTAssertTrue(liste.first?.tailles.isEmpty ?? false)
    }

    func testUniteDiteSansPoidsGardeLeCatalogue() {
        let liste = dites("piece", "pièce", "pièces", 0, "Noix, séchée, cerneaux")
        XCTAssertEqual(liste.map(\.singulier), ["poignée", "pièce"])
        XCTAssertEqual(liste.first?.grammes, 30)
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
