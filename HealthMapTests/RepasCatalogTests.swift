import XCTest
@testable import HealthMap

// MARK: - Les aliments, repas par repas
//
// Le regroupement par repas est une présentation : il ne doit ni inventer un
// aliment, ni en rendre un inatteignable, ni toucher au catalogue.
final class RepasCatalogTests: XCTestCase {

    private let regimes = ["omnivore", "flexitarian", "vegetarien", "vegan", "sans_gluten", "halal", "autre"]

    // MARK: Le catalogue reste la source

    func testChaqueVedetteExisteDansLeCatalogue() {
        for repas in RepasBilan.allCases {
            for id in RepasCatalog.vedettesDeBase[repas] ?? [] {
                XCTAssertNotNil(GroceryCatalog.item(id: id), "\(repas.rawValue) : vedette inconnue « \(id) »")
            }
            for id in RepasCatalog.remplacantes[repas] ?? [] {
                XCTAssertNotNil(GroceryCatalog.item(id: id), "\(repas.rawValue) : remplaçante inconnue « \(id) »")
            }
        }
    }

    func testLesQuatreRepasOntDesVedettes() {
        for repas in RepasBilan.allCases {
            XCTAssertGreaterThanOrEqual(RepasCatalog.vedettesDeBase[repas]?.count ?? 0, 9, repas.rawValue)
            XCTAssertNotNil(RepasCatalog.rayonsPropres[repas], repas.rawValue)
        }
    }

    func testLesNomsCourtsDesignentDesAlimentsDuCatalogue() {
        for id in RepasCatalog.nomsCourts.keys {
            XCTAssertNotNil(GroceryCatalog.item(id: id), "nom court pour un aliment inconnu : \(id)")
        }
        let poulet = GroceryCatalog.item(id: "escalopes_poulet")!
        XCTAssertEqual(RepasCatalog.nomCourt(poulet), "Poulet")
        let saumon = GroceryCatalog.item(id: "saumon")!
        XCTAssertEqual(RepasCatalog.nomCourt(saumon), saumon.name)
    }

    func testLeProduitsDePorcEtLesVegetauxDuRayonLaitierExistent() {
        for id in RepasCatalog.porc.union(RepasCatalog.vegetauxDuRayonLaitier) {
            XCTAssertNotNil(GroceryCatalog.item(id: id), id)
        }
    }

    // MARK: Tout aliment reste atteignable

    func testChaqueRepasOuvreSurLeCatalogueEntier() {
        let tous = Set(GroceryCatalog.allItems.map(\.id))
        for repas in RepasBilan.allCases {
            let rayons = RepasCatalog.rayons(repas)
            XCTAssertEqual(rayons.count, GroceryCatalog.aisles.count, repas.rawValue)
            XCTAssertEqual(Set(rayons.map(\.id)).count, rayons.count, "\(repas.rawValue) : un rayon en double")
            XCTAssertEqual(Set(rayons.flatMap { $0.items.map(\.id) }), tous, repas.rawValue)
        }
    }

    func testChaqueRepasCommenceParSesPropresRayons() {
        for repas in RepasBilan.allCases {
            let propres = RepasCatalog.rayonsPropres[repas] ?? []
            let ouverts = RepasCatalog.rayons(repas).map(\.id)
            XCTAssertEqual(Array(ouverts.prefix(propres.count)), propres, repas.rawValue)
        }
    }

    func testChaqueRayonAppartientAAuMoinsUnRepas() {
        let couverts = Set(RepasCatalog.rayonsPropres.values.flatMap { $0 })
        XCTAssertEqual(couverts, Set(GroceryCatalog.aisles.map(\.id)))
    }

    func testChaqueAlimentASonRayon() {
        for aliment in GroceryCatalog.allItems {
            XCTAssertNotNil(RepasCatalog.rayonParAliment[aliment.id], aliment.id)
        }
    }

    // MARK: Les vedettes suivent le régime

    func testLeNombreDeVedettesNeDependPasDuRegime() {
        for regime in regimes {
            for repas in RepasBilan.allCases {
                let ids = RepasCatalog.idsVedettes(repas, regime: regime)
                XCTAssertEqual(ids.count, RepasCatalog.vedettesDeBase[repas]?.count, "\(regime) / \(repas.rawValue)")
                XCTAssertEqual(Set(ids).count, ids.count, "\(regime) / \(repas.rawValue) : doublon")
                XCTAssertEqual(RepasCatalog.vedettes(repas, regime: regime).map(\.id), ids)
            }
        }
    }

    func testSansRegimeParticulierLesVedettesSontCellesDeLaMaquette() {
        for regime in ["omnivore", "flexitarian", "sans_gluten", "autre"] {
            for repas in RepasBilan.allCases {
                XCTAssertEqual(RepasCatalog.idsVedettes(repas, regime: regime), RepasCatalog.vedettesDeBase[repas])
            }
        }
    }

    func testUnVegetarienNeVoitNiViandeNiPoisson() {
        for repas in RepasBilan.allCases {
            for id in RepasCatalog.idsVedettes(repas, regime: "vegetarien") {
                let rayon = RepasCatalog.rayonParAliment[id]
                XCTAssertFalse(rayon == "viandes" || rayon == "poissons", "\(repas.rawValue) : \(id)")
            }
        }
        // Les œufs et les laitages restent.
        XCTAssertTrue(RepasCatalog.idsVedettes(.petitDej, regime: "vegetarien").contains("oeufs"))
    }

    func testUnVeganNeVoitQueDuVegetal() {
        for repas in RepasBilan.allCases {
            for id in RepasCatalog.idsVedettes(repas, regime: "vegan") {
                let rayon = RepasCatalog.rayonParAliment[id]
                XCTAssertFalse(rayon == "viandes" || rayon == "poissons", "\(repas.rawValue) : \(id)")
                if rayon == "laitiers" {
                    XCTAssertTrue(RepasCatalog.vegetauxDuRayonLaitier.contains(id), "\(repas.rawValue) : \(id)")
                }
            }
        }
    }

    func testHalalRemplaceLeJambon() {
        let midi = RepasCatalog.idsVedettes(.midi, regime: "halal")
        XCTAssertFalse(midi.contains("jambon_blanc"))
        XCTAssertTrue(midi.contains("escalopes_dinde"))
        XCTAssertTrue(midi.contains("steak_hache"))
    }

    /// La remplaçante prend la place de l'aliment écarté : les protéines
    /// restent en tête du midi.
    func testLaRemplacantePrendLaPlaceDeLAlimentEcarte() {
        let midi = RepasCatalog.idsVedettes(.midi, regime: "vegetarien")
        XCTAssertEqual(Array(midi.prefix(5)), ["oeufs", "tofu", "pois_chiches", "haricots_rouges", "quinoa"])
        XCTAssertEqual(Array(midi.suffix(7)), ["pates", "riz_blanc", "pommes_de_terre", "lentilles", "tomates", "carottes", "salade_verte"])
    }

    // MARK: Les ajouts hors vedettes

    func testUnAjoutApparaitAuxRepasDeSonRayon() {
        let caddie = ["agneau": 3]
        XCTAssertEqual(RepasCatalog.ajouts(.midi, caddie: caddie, regime: "omnivore").map(\.id), ["agneau"])
        XCTAssertEqual(RepasCatalog.ajouts(.soir, caddie: caddie, regime: "omnivore").map(\.id), ["agneau"])
        XCTAssertTrue(RepasCatalog.ajouts(.petitDej, caddie: caddie, regime: "omnivore").isEmpty)
        XCTAssertTrue(RepasCatalog.ajouts(.gouter, caddie: caddie, regime: "omnivore").isEmpty)
    }

    func testUneVedetteNEstJamaisUnAjout() {
        let caddie = ["saumon": 3, "oeufs": 10]
        for repas in RepasBilan.allCases {
            XCTAssertTrue(RepasCatalog.ajouts(repas, caddie: caddie, regime: "omnivore").isEmpty, repas.rawValue)
        }
    }

    func testUnAlimentDecocheNEstPasUnAjout() {
        XCTAssertTrue(RepasCatalog.ajouts(.midi, caddie: ["agneau": 0], regime: "omnivore").isEmpty)
    }

    /// Tout aliment coché se voit dans la grille d'au moins un repas : il
    /// reste réglable sans rouvrir le catalogue.
    func testToutAlimentCocheSeVoitDansAuMoinsUneGrille() {
        for regime in regimes {
            for aliment in GroceryCatalog.allItems {
                let caddie = [aliment.id: 3]
                let visible = RepasBilan.allCases.contains { repas in
                    RepasCatalog.grille(repas, caddie: caddie, regime: regime).contains { $0.id == aliment.id }
                }
                XCTAssertTrue(visible, "\(regime) : \(aliment.id) coché mais visible nulle part")
            }
        }
    }

    func testLaGrilleCommenceParLesVedettes() {
        let grille = RepasCatalog.grille(.midi, caddie: ["agneau": 3], regime: "omnivore").map(\.id)
        XCTAssertEqual(Array(grille.dropLast()), RepasCatalog.vedettesDeBase[.midi])
        XCTAssertEqual(grille.last, "agneau")
    }

    // MARK: La recherche

    func testLaRechercheIgnoreAccentsEtMajuscules() {
        XCTAssertTrue(RepasCatalog.recherche("epin").contains { $0.id == "epinards" })
        XCTAssertTrue(RepasCatalog.recherche("ÉPINARDS").contains { $0.id == "epinards" })
        XCTAssertTrue(RepasCatalog.recherche("  poulet ").contains { $0.id == "escalopes_poulet" })
    }

    func testLaRechercheDeplieLeE_Dans_LO() {
        XCTAssertTrue(RepasCatalog.recherche("oeuf").contains { $0.id == "oeufs" })
        XCTAssertTrue(RepasCatalog.recherche("œuf").contains { $0.id == "oeufs" })
        XCTAssertTrue(RepasCatalog.recherche("boeuf").contains { $0.id == "boeuf" })
    }

    func testCeQuiCommenceParLeTextePasseDevant() {
        let resultats = RepasCatalog.recherche("pain").map(\.id)
        XCTAssertFalse(resultats.isEmpty)
        XCTAssertTrue(resultats.first?.hasPrefix("pain") ?? false, "\(resultats)")
    }

    func testUneRechercheVideNeRendRien() {
        XCTAssertTrue(RepasCatalog.recherche("").isEmpty)
        XCTAssertTrue(RepasCatalog.recherche("   ").isEmpty)
        XCTAssertTrue(RepasCatalog.recherche("zzzz").isEmpty)
    }

    func testLaRechercheCouvreToutLeCatalogue() {
        for aliment in GroceryCatalog.allItems {
            XCTAssertTrue(RepasCatalog.recherche(aliment.name).contains { $0.id == aliment.id }, aliment.name)
        }
    }
}
