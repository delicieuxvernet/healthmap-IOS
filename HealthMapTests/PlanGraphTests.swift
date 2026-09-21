import XCTest
@testable import HealthMap

// MARK: - Le Plan en graphe : modèle et placement (20 sept. 2026)
//
// Ce qui ne se voit pas à la relecture : qui est relié à qui, d'où viennent les
// habitudes (le registre des apports, jamais une liste recopiée), et un
// placement où deux leviers ne se marchent pas dessus, quel que soit l'écran.

final class PlanGraphTests: XCTestCase {

    private typealias Sujet = PlanGraph.Sujet
    private typealias Apport = PlanGraph.Apport

    private let apports = [
        Apport(id: "iron", nom: "Fer", score: 42),
        Apport(id: "magnesium", nom: "Magnésium", score: 58),
        Apport(id: "vitC", nom: "Vitamine C", score: 85),
        Apport(id: "zinc", nom: "Zinc", score: 35),
    ]

    private func registre(_ freins: [String: [(String, Int, SectionQuestionnaire)]]) -> [String: DetailApport] {
        freins.mapValues { lignes in
            let contributions = lignes.map { ContributionApport(libelle: $0.0, delta: $0.1, section: $0.2) }
            let brut = DetailApport.pointDeDepart + contributions.reduce(0) { $0 + $1.delta }
            return DetailApport(contributions: contributions, score: max(0, min(100, brut)))
        }
    }

    private func graphe(objectifs: [Sujet] = [Sujet(id: "obj", nom: "Perte de poids")],
                        symptomes: [Sujet],
                        registre: [String: DetailApport] = [:]) -> PlanGraph {
        PlanGraph.construire(objectifs: objectifs, symptomes: symptomes, apports: apports, registre: registre)
    }

    // MARK: Les trois anneaux

    func testLObjectifEstAuCentreLesSymptomesAutour() {
        let g = graphe(symptomes: [Sujet(id: "ongles", nom: "Ongles cassants", apports: ["iron"]),
                                   Sujet(id: "fatigue", nom: "Fatigue", apports: ["iron", "magnesium"])])
        XCTAssertEqual(g.noeud(PlanGraph.idCentre)?.nom, "Perte de poids")
        XCTAssertEqual(g.noeud(PlanGraph.idCentre)?.anneau, 0)
        XCTAssertEqual(g.noeuds.filter { $0.anneau == 1 }.map(\.id), ["ongles", "fatigue"])
        XCTAssertEqual(Set(g.noeuds.filter { $0.genre == .apport }.map(\.id)), ["iron", "magnesium"])
    }

    func testSansObjectifLeCentreResteNomme() {
        let g = graphe(objectifs: [], symptomes: [Sujet(id: "ongles", nom: "Ongles cassants", apports: ["iron"])])
        XCTAssertEqual(g.noeud(PlanGraph.idCentre)?.nom, "Ton équilibre")
    }

    /// Seuls les apports QUE LE BILAN RATTACHE à ce qui est affiché deviennent
    /// des leviers : un apport bas mais relié à rien n'a rien à faire ici.
    func testUnApportNonCiteNEstPasUnLevier() {
        let g = graphe(symptomes: [Sujet(id: "ongles", nom: "Ongles cassants", apports: ["iron"])])
        XCTAssertNil(g.noeud("zinc"))
        XCTAssertNil(g.noeud("vitC"))
    }

    func testQuatreSymptomesAuPlus() {
        let symptomes = (1...6).map { Sujet(id: "s\($0)", nom: "Symptôme \($0)") }
        XCTAssertEqual(graphe(symptomes: symptomes).noeuds.filter { $0.genre == .symptome }.count,
                       PlanGraph.symptomesAffiches)
    }

    // MARK: Les liens

    func testUnApportBasFaitUnLienFort() {
        let g = graphe(symptomes: [Sujet(id: "ongles", nom: "Ongles cassants", apports: ["zinc", "vitC"])])
        XCTAssertEqual(g.force(entre: "ongles", et: "zinc"), 3)   // 35 %
        XCTAssertEqual(g.force(entre: "ongles", et: "vitC"), 1)   // 85 %
        XCTAssertEqual(PlanGraph.force(pourScore: 58), 2)
    }

    func testLeVoisinageEstCeQuiResteAllume() {
        let g = graphe(symptomes: [Sujet(id: "ongles", nom: "Ongles cassants", apports: ["iron"]),
                                   Sujet(id: "sommeil", nom: "Sommeil", apports: ["magnesium"])])
        XCTAssertEqual(g.voisinage(de: "iron"), ["iron", "ongles"])
        XCTAssertTrue(g.voisinage(de: PlanGraph.idCentre).isSuperset(of: ["ongles", "sommeil"]))
    }

    // MARK: Les habitudes viennent du registre

    func testLeCafeToucheLeFerQuiToucheLesOngles() {
        let g = graphe(
            symptomes: [Sujet(id: "ongles", nom: "Ongles cassants", apports: ["iron", "magnesium"])],
            registre: registre(["iron": [("Café au moment des repas", -22, .modeDeVie)],
                                "magnesium": [("Café au moment des repas", -10, .modeDeVie)]])
        )
        let cafe = g.noeuds.first { $0.genre == .habitude }
        XCTAssertEqual(cafe?.nom, "Café au moment des repas")
        XCTAssertEqual(cafe?.points, -32)
        XCTAssertEqual(g.force(entre: cafe?.id ?? "", et: "iron"), 3)
        XCTAssertEqual(g.force(entre: cafe?.id ?? "", et: "magnesium"), 2)
        XCTAssertEqual(g.resume(de: cafe?.id ?? ""), "Freine 2 apports")
    }

    /// Un traitement ou un antécédent n'est pas une habitude qu'on change :
    /// il reste dans la fiche de l'apport, pas sur le graphe.
    func testLeMedicalNEstPasUneHabitude() {
        let g = graphe(
            symptomes: [Sujet(id: "ongles", nom: "Ongles cassants", apports: ["iron"])],
            registre: registre(["iron": [("Traitement anti-acide", -8, .medical), ("Âge", -5, .profil)]])
        )
        XCTAssertTrue(g.noeuds.filter { $0.genre == .habitude }.isEmpty)
    }

    func testDeuxHabitudesAuPlusLesPlusLourdesDAbord() {
        let g = graphe(
            symptomes: [Sujet(id: "ongles", nom: "Ongles cassants", apports: ["iron"])],
            registre: registre(["iron": [("Petite", -3, .nutrition), ("Lourde", -20, .modeDeVie), ("Moyenne", -9, .nutrition)]])
        )
        XCTAssertEqual(g.noeuds.filter { $0.genre == .habitude }.map(\.nom), ["Lourde", "Moyenne"])
    }

    // MARK: Le bandeau

    func testLeResumeDitUnEtatJamaisUnGeste() {
        let g = graphe(symptomes: [Sujet(id: "ongles", nom: "Ongles cassants", apports: ["iron"]),
                                   Sujet(id: "fatigue", nom: "Fatigue", apports: ["iron"])])
        XCTAssertEqual(g.resume(de: "iron"), "À 42 % · touche 2 symptômes")
        XCTAssertEqual(g.resume(de: "ongles"), "1 apport en cause")
        XCTAssertEqual(g.resume(de: PlanGraph.idCentre), "2 symptômes sur le chemin")
    }

    // MARK: Le placement

    func testLesLeviersNeSeMarchentPasDessus() {
        let symptomes = [Sujet(id: "a", nom: "A", apports: ["iron", "zinc", "magnesium", "vitC"]),
                         Sujet(id: "b", nom: "B", apports: ["iron", "zinc"])]
        let g = graphe(symptomes: symptomes,
                       registre: registre(["iron": [("Café", -22, .modeDeVie)], "zinc": [("Ultra-transformés", -5, .nutrition)]]))
        let angles = g.noeuds.filter { $0.anneau == 2 }.map(\.angle).sorted()
        XCTAssertEqual(angles.count, 6)
        let ecartAttendu = min(PlanGraph.ecartMinimal, 360.0 / Double(angles.count))
        for (a, b) in zip(angles, angles.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, ecartAttendu - 0.001)
        }
        XCTAssertGreaterThanOrEqual(angles[0] + 360 - angles[angles.count - 1], ecartAttendu - 0.001)
    }

    func testUnLevierEstTireVersCeQuIlTouche() {
        let g = graphe(objectifs: [], symptomes: [Sujet(id: "a", nom: "A", apports: ["iron"]),
                                                   Sujet(id: "b", nom: "B"),
                                                   Sujet(id: "c", nom: "C"),
                                                   Sujet(id: "d", nom: "D")])
        XCTAssertEqual(g.noeud("iron")?.angle ?? -1, g.noeud("a")?.angle ?? -2, accuracy: 0.001)
    }

    func testLaMoyenneCirculaireNeSeTrompePasAutourDeZero() {
        XCTAssertEqual(PlanGraph.moyenneCirculaire([350, 10]) ?? -1, 0, accuracy: 0.001)
        XCTAssertNil(PlanGraph.moyenneCirculaire([]))
    }

    func testToutTientDansLeCadreMemeSurUnPetitEcran() {
        let g = graphe(symptomes: [Sujet(id: "a", nom: "A", apports: ["iron", "zinc"]),
                                   Sujet(id: "b", nom: "B", apports: ["magnesium", "vitC"])])
        for taille in [CGSize(width: 353, height: 470), CGSize(width: 335, height: 330), CGSize(width: 320, height: 300)] {
            for noeud in g.noeuds {
                let p = g.position(de: noeud, dans: taille)
                XCTAssertTrue((0...taille.width).contains(p.x) && (0...taille.height).contains(p.y),
                              "\(noeud.id) sort du cadre \(taille)")
            }
        }
    }
}
