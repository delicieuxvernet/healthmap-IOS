import XCTest
@testable import HealthMap

// MARK: - Un repère visuel par résultat de recherche (21 sept. 2026)
//
// Quel repère pour quelle ligne, quel sous-titre, quelles sections : tout se
// décide dans `RechercheVisuelle`, sans écran. Ces tests tiennent aussi le
// contrat de décodage : la nouvelle RPC (`search_foods_visuel`) ET l'ancienne
// (`search_foods`, qui sert de repli) doivent se lire avec le même `FoodHit`.

final class RechercheVisuelleTests: XCTestCase {

    private func generique(_ nom: String, _ sousGroupe: String?, groupe: String? = nil) -> RepereAliment {
        RechercheVisuelle.repere(source: "ciqual", image: nil, nom: nom, groupe: groupe, sousGroupe: sousGroupe)
    }

    // MARK: Le repère

    func testUnProduitDeMarqueMontreSaPhoto() {
        let adresse = "https://images.openfoodfacts.org/images/products/301/762/042/5035/front_en.583.200.jpg"
        XCTAssertEqual(RechercheVisuelle.repere(source: "off", image: adresse, nom: "Nutella", groupe: nil, sousGroupe: nil),
                       .photo(URL(string: adresse)!))
    }

    /// Sans photo, ou avec une adresse qui n'est pas en https : le symbole.
    func testSansPhotoSureLeProduitGardeUnSymbole() {
        XCTAssertEqual(RechercheVisuelle.repere(source: "off", image: nil, nom: "Coquillettes", groupe: nil, sousGroupe: nil),
                       .symbole("barcode"))
        XCTAssertEqual(RechercheVisuelle.repere(source: "off", image: "http://exemple.fr/a.jpg", nom: "Coquillettes", groupe: nil, sousGroupe: nil),
                       .symbole("barcode"))
        XCTAssertEqual(RechercheVisuelle.repere(source: "off", image: "", nom: "Coquillettes", groupe: nil, sousGroupe: nil),
                       .symbole("barcode"))
    }

    func testLaFamilleDonneLeRepereDUnGenerique() {
        XCTAssertEqual(generique("Pâtes sèches standard, cuites, non salées", "pâtes, riz et céréales"), .illustration("fluent_spaghetti"))
        XCTAssertEqual(generique("Riz blanc, cuit, non salé", "pâtes, riz et céréales"), .emoji("🍚"))
        XCTAssertEqual(generique("Boeuf, steak haché 15% MG, cru", "viandes crues"), .illustration("fluent_meat"))
        XCTAssertEqual(generique("Saumon, cuit à la vapeur", "poissons cuits"), .illustration("fluent_fish"))
        XCTAssertEqual(generique("Oeuf, dur", "œufs"), .illustration("fluent_egg"))
        XCTAssertEqual(generique("Comté", "fromages et assimilés"), .illustration("fluent_cheese"))
        XCTAssertEqual(generique("Pain, baguette, courante", "pains et assimilés"), .emoji("🥖"))
        XCTAssertEqual(generique("Lentille verte, bouillie/cuite à l'eau", "légumineuses"), .emoji("🫘"))
        XCTAssertEqual(generique("Eau minérale, plate", "eaux"), .illustration("fluent_droplet"))
    }

    /// Dans une famille large, le nom affine : une volaille n'est pas un steak.
    func testLeNomAffineLaFamille() {
        XCTAssertEqual(generique("Poulet, blanc, sans peau, cru", "viandes crues"), .illustration("fluent_poultry"))
        XCTAssertEqual(generique("Épinards, cuits", "légumes"), .illustration("fluent_leafygreen"))
        XCTAssertEqual(generique("Brocoli, cuit", "légumes"), .illustration("fluent_broccoli"))
        XCTAssertEqual(generique("Banane, pulpe, crue", "fruits"), .illustration("fluent_banana"))
        XCTAssertEqual(generique("Pomme, pulpe et peau, crue", "fruits"), .emoji("🍎"))
        XCTAssertEqual(generique("Mangue, pulpe, crue", "fruits"), .illustration("fluent_kiwi"))
        XCTAssertEqual(generique("Thé infusé, non sucré", "boissons sans alcool"), .emoji("🍵"))
    }

    /// Un mot-clé se cherche en DÉBUT de mot : « foie » n'est pas une « oie »,
    /// « menthe » n'est pas du « thé ».
    func testUnMotCleNeSeTrouvePasAuMilieuDUnMot() {
        XCTAssertEqual(generique("Foie, veau, cuit", "viandes cuites"), .illustration("fluent_meat"))
        XCTAssertEqual(generique("Sirop à la menthe, dilué", "boissons sans alcool"), .emoji("🥤"))
    }

    /// Sous-famille inconnue : la famille ; rien du tout : l'assiette.
    func testLesReplis() {
        XCTAssertEqual(generique("Skyr", "une sous-famille inconnue", groupe: "produits laitiers et assimilés"),
                       .illustration("fluent_milk"))
        XCTAssertEqual(generique("Crème glacée", nil, groupe: "glaces et sorbets"), .emoji("🍨"))
        XCTAssertEqual(generique("Aliment sans famille", nil), .illustration("fluent_plate"))
    }

    /// Toute illustration nommée existe bien dans le catalogue d'images.
    func testChaqueIllustrationExisteDansLeCatalogue() {
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let catalogue = racine.appendingPathComponent("HealthMap/Resources/Assets.xcassets")
        let essais: [(String, String?, String?)] = [
            ("Avocat", "légumes", nil), ("Laitue", "légumes", nil), ("Brocoli", "légumes", nil),
            ("Banane", "fruits", nil), ("Fraise", "fruits", nil), ("Citron", "fruits", nil), ("Orange", "fruits", nil),
            ("Myrtille", "fruits", nil), ("Mangue", "fruits", nil), ("Amande", "fruits à coque et graines oléagineuses", nil),
            ("Poulet", "viandes cuites", nil), ("Boeuf", "viandes cuites", nil), ("Jambon", "charcuteries et assimilés", nil),
            ("Cabillaud", "poissons crus", nil), ("Huître", "mollusques et crustacés crus", nil), ("Oeuf", "œufs", nil),
            ("Comté", "fromages et assimilés", nil), ("Pâtes", "pâtes, riz et céréales", nil), ("Eau", "eaux", nil),
            ("Lasagnes", "plats composés", nil), ("Yaourt", nil, "produits laitiers et assimilés"), ("Rien", nil, nil),
        ]
        for (nom, sousGroupe, groupe) in essais {
            guard case .illustration(let image) = generique(nom, sousGroupe, groupe: groupe) else {
                XCTFail("\(nom) devait rendre une illustration"); continue
            }
            let dossier = catalogue.appendingPathComponent("\(image).imageset")
            XCTAssertTrue(FileManager.default.fileExists(atPath: dossier.path), "\(image) absent du catalogue (\(nom))")
        }
    }

    // MARK: Le sous-titre

    func testLaMarqueSeReduitASonPremierNom() {
        XCTAssertEqual(RechercheVisuelle.marqueCourte("Barilla, Barilla Teigwaren,  Barilla G. e R. Fratelli"), "Barilla")
        XCTAssertEqual(RechercheVisuelle.marqueCourte("  Panzani "), "Panzani")
        XCTAssertNil(RechercheVisuelle.marqueCourte(""))
        XCTAssertNil(RechercheVisuelle.marqueCourte(" , "))
        XCTAssertNil(RechercheVisuelle.marqueCourte(nil))
    }

    func testLeSousTitre() {
        XCTAssertEqual(RechercheVisuelle.sousTitre(source: "off", marque: "Barilla, Barilla Nr. 3", groupe: nil,
                                                   sousGroupe: nil, kcal100g: 358.6),
                       "Barilla · 359 kcal / 100 g")
        XCTAssertEqual(RechercheVisuelle.sousTitre(source: "off", marque: nil, groupe: nil, sousGroupe: nil, kcal100g: nil),
                       "Produit de marque")
        XCTAssertEqual(RechercheVisuelle.sousTitre(source: "ciqual", marque: nil, groupe: "viandes, œufs, poissons et assimilés",
                                                   sousGroupe: "viandes crues", kcal100g: 131),
                       "Viandes crues · 131 kcal / 100 g")
        XCTAssertEqual(RechercheVisuelle.sousTitre(source: "ciqual", marque: nil, groupe: "glaces et sorbets",
                                                   sousGroupe: "-", kcal100g: 200),
                       "Glaces et sorbets · 200 kcal / 100 g")
        // L'ancienne RPC ne donne pas la famille : la ligne reste celle d'avant.
        XCTAssertEqual(RechercheVisuelle.sousTitre(source: "ciqual", marque: nil, groupe: nil, sousGroupe: nil, kcal100g: 52),
                       "Générique · 52 kcal / 100 g")
    }

    // MARK: Les sections

    private struct Ligne: Equatable {
        let nom: String
        let source: String
        let score: Double?
    }

    private func sections(_ lignes: [Ligne]) -> [RechercheVisuelle.Section<Ligne>] {
        RechercheVisuelle.sections(lignes, source: \.source, score: \.score)
    }

    /// « pâtes » : les génériques d'abord, chaque section dans l'ordre du serveur.
    func testLesGeneriquesPassentDevantQuandIlsSontLesMeilleurs() {
        let resultat = sections([
            Ligne(nom: "Pâtes fraîches", source: "ciqual", score: 3.85),
            Ligne(nom: "Spaghetti n°5", source: "off", score: 2.60),
            Ligne(nom: "Pâtes sèches", source: "ciqual", score: 2.40),
            Ligne(nom: "Coquillettes", source: "off", score: 2.59),
        ])
        XCTAssertEqual(resultat.map(\.titre), ["Aliments", "Produits de marque"])
        XCTAssertEqual(resultat[0].lignes.map(\.nom), ["Pâtes fraîches", "Pâtes sèches"])
        XCTAssertEqual(resultat[1].lignes.map(\.nom), ["Spaghetti n°5", "Coquillettes"])
    }

    /// « nutella » : le pot avant les génériques qui lui ressemblent de loin.
    func testLaMarqueChercheePasseDevant() {
        let resultat = sections([
            Ligne(nom: "Nutella", source: "off", score: 2.80),
            Ligne(nom: "Pâte à tartiner chocolat et noisette", source: "ciqual", score: 1.90),
        ])
        XCTAssertEqual(resultat.map(\.titre), ["Produits de marque", "Aliments"])
    }

    func testUneSeuleSourceUneSeuleSectionEtRienPourRien() {
        XCTAssertEqual(sections([Ligne(nom: "Kiwi", source: "ciqual", score: 3)]).map(\.titre), ["Aliments"])
        XCTAssertEqual(sections([Ligne(nom: "Coca", source: "off", score: 3)]).map(\.titre), ["Produits de marque"])
        XCTAssertTrue(sections([]).isEmpty)
        // Repli sur l'ancienne RPC (pas de score) : l'ordre par défaut tient.
        XCTAssertEqual(sections([Ligne(nom: "Coca", source: "off", score: nil),
                                 Ligne(nom: "Kiwi", source: "ciqual", score: nil)]).map(\.titre),
                       ["Aliments", "Produits de marque"])
    }

    // MARK: Le contrat de décodage

    func testLaNouvelleRechercheSeDecode() throws {
        let json = """
        [{"id":"off:3017620425035","source":"off","nom":"Nutella","marque":"Ferrero, Nutella",
          "image":"https://images.openfoodfacts.org/images/products/301/762/042/5035/front_en.583.200.jpg",
          "kcal_100g":539,"nutriscore":"E","groupe":null,"sous_groupe":null,"score":2.8},
         {"id":"ciqual:9811","source":"ciqual","nom":"Pâtes sèches standard, cuites, non salées","marque":null,
          "image":null,"kcal_100g":126,"nutriscore":null,"groupe":"produits céréaliers",
          "sous_groupe":"pâtes, riz et céréales","score":2.4}]
        """
        let hits = try JSONDecoder().decode([MealJournalService.FoodHit].self, from: Data(json.utf8))
        XCTAssertEqual(hits.count, 2)
        guard case .photo = hits[0].repere else { return XCTFail("le produit devait montrer sa photo") }
        XCTAssertEqual(hits[0].nutriscore, "E")
        XCTAssertEqual(hits[0].sousTitre, "Ferrero · 539 kcal / 100 g")
        XCTAssertEqual(hits[1].repere, .illustration("fluent_spaghetti"))
        XCTAssertEqual(hits[1].sousTitre, "Pâtes, riz et céréales · 126 kcal / 100 g")
    }

    /// Le repli : la réponse de `search_foods`, sans famille ni Nutri-Score.
    func testLAncienneRechercheSeDecodeEncore() throws {
        let json = """
        [{"id":"ciqual:13039","source":"ciqual","nom":"Pomme, pulpe et peau, crue","marque":null,"image":null,
          "code_barres":null,"kcal_100g":53.2,"proteines":0.3,"glucides":11.6,"lipides":0.2,"fibres":2.1,
          "nova":1,"score":3.1}]
        """
        let hits = try JSONDecoder().decode([MealJournalService.FoodHit].self, from: Data(json.utf8))
        XCTAssertEqual(hits.first?.name, "Pomme, pulpe et peau, crue")
        XCTAssertNil(hits.first?.nutriscore)
        XCTAssertEqual(hits.first?.sousTitre, "Générique · 53 kcal / 100 g")
        XCTAssertEqual(hits.first?.repere, .illustration("fluent_plate"))
    }
}
