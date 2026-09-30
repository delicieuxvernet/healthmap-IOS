import XCTest
@testable import HealthMap

// MARK: - Le Plan en graphe : la physique (30 sept. 2026)
//
// Ce qui compte à l'écran : une fois posé, aucune bulle n'en chevauche une
// autre, tout tient dans le cadre, et une bulle qu'on tire entraîne ses voisines.

final class PlanGraphPhysiqueTests: XCTestCase {

    private typealias Sujet = PlanGraph.Sujet
    private typealias Apport = PlanGraph.Apport

    private let graphe = PlanGraph.construire(
        objectifs: [Sujet(id: "obj", nom: "Énergie")],
        symptomes: [Sujet(id: "fatigue", nom: "Fatigue", apports: ["iron", "zinc"]),
                    Sujet(id: "crampes", nom: "Crampes", apports: ["magnesium", "vitC"])],
        apports: [Apport(id: "iron", nom: "Fer", score: 42),
                  Apport(id: "magnesium", nom: "Magnésium", score: 58),
                  Apport(id: "vitC", nom: "Vitamine C", score: 85),
                  Apport(id: "zinc", nom: "Zinc", score: 35)],
        registre: [:]
    )

    private func pose(dans taille: CGSize) -> PlanGraphPhysique {
        let physique = PlanGraphPhysique()
        physique.preparer(graphe, dans: taille)
        physique.stabiliser()
        return physique
    }

    func testLesBullesSeRepoussentSansSeChevaucher() {
        let physique = pose(dans: CGSize(width: 353, height: 470))
        let corps = Array(physique.corps.values)
        for i in corps.indices {
            for j in corps.indices where j > i {
                let a = corps[i], b = corps[j]
                let d = hypot(a.position.x - b.position.x, a.position.y - b.position.y)
                XCTAssertGreaterThan(d, a.rayon + b.rayon, "deux bulles se chevauchent")
            }
        }
    }

    func testToutTientDansLeCadre() {
        for taille in [CGSize(width: 353, height: 470), CGSize(width: 320, height: 300)] {
            let physique = pose(dans: taille)
            for (id, c) in physique.corps {
                XCTAssertTrue(c.position.x.isFinite && c.position.y.isFinite, "\(id) n'est plus un nombre")
                XCTAssertTrue((0...taille.width).contains(c.position.x) && (0...taille.height).contains(c.position.y),
                              "\(id) sort du cadre \(taille)")
            }
        }
    }

    func testLaTigeRetientLaVoisine() {
        let physique = pose(dans: CGSize(width: 353, height: 470))
        let fer = physique.corps["iron"]!.position
        let avant = physique.corps["fatigue"]!.position
        // On tire Fatigue loin de Fer : Fer suit.
        let cible = CGPoint(x: avant.x + (avant.x - fer.x) * 0.8, y: avant.y + (avant.y - fer.y) * 0.8)
        physique.attraper("fatigue")
        physique.deplacer(vers: cible)
        for pas in 1...60 { physique.avancer(jusqua: Double(pas) / 60) }
        let tenue = physique.corps["fatigue"]!.position
        let ferApres = physique.corps["iron"]!.position
        XCTAssertLessThan(hypot(ferApres.x - tenue.x, ferApres.y - tenue.y),
                          hypot(fer.x - tenue.x, fer.y - tenue.y),
                          "la voisine ne suit pas la bulle tirée")
        physique.lacher()
        XCTAssertNil(physique.tenu)
    }
}
