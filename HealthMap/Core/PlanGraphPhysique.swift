import Foundation
import CoreGraphics

// MARK: - Le Plan en graphe : la physique (validée par Arthur le 30 sept. 2026)
//
// Le même effet que la vue graphe d'Obsidian : les bulles se REPOUSSENT, les
// tiges qui les relient les RETIENNENT comme des ressorts, et une gravité douce
// ramène l'ensemble vers le centre. On peut attraper une bulle : ses voisines
// suivent, les autres s'écartent ; lâchée, tout revient en place.
//
// Réglages validés sur la maquette (curseurs) : répulsion 1150, raideur des
// tiges 15, amorti 70. Ils ont été choisis sur un canevas de 308 × 360 pt ; les
// longueurs suivent l'écran (facteur `taille`) pour que le dessin garde ses
// proportions — la répulsion en taille³, puisque son équilibre avec un ressort
// linéaire se fait en 1/d².
//
// Pur, sans SwiftUI : la vue lui donne l'heure, il rend des positions. Le point
// de départ est le placement calculé des trois anneaux (`PlanGraph.position`) —
// le graphe se pose donc tout près de la mise en page connue.

final class PlanGraphPhysique {

    // MARK: Réglages (maquette validée)

    static let repulsion: CGFloat = 1150
    static let raideur: CGFloat = 15
    static let amorti: CGFloat = 0.70
    /// L'échelle du graphe (`PlanGraph.echelle`) sur le canevas de la maquette.
    static let echelleDeLaMaquette: CGFloat = 0.766
    /// Un pas d'intégration : les réglages ont été trouvés à 60 images/s.
    static let pas: Double = 1.0 / 60.0
    /// Au-delà, une image manquée ne rattrape pas le temps perdu d'un coup.
    static let pasMaximumParImage = 4
    static let vitesseMaximale: CGFloat = 40

    struct Corps {
        var position: CGPoint
        var vitesse: CGVector = .zero
        let anneau: Int
        let rayon: CGFloat
    }

    private(set) var corps: [String: Corps] = [:]
    private var ordre: [String] = []
    private var liens: [PlanGraph.Lien] = []
    private var taille: CGSize = .zero
    private var signature = ""
    private var derniereHeure: Double?
    private var enRetard: Double = 0
    /// Reduce Motion : l'équilibre est atteint, rien n'avance plus.
    private(set) var estStable = false
    /// La bulle tenue sous le doigt : elle suit le doigt, pas les forces.
    private(set) var tenu: String?

    /// Rayon d'un disque — le même que celui que dessine la vue.
    static func rayon(anneau: Int, echelle: CGFloat) -> CGFloat {
        let base: CGFloat = anneau == 0 ? 30 : (anneau == 1 ? 22 : 19)
        return base * max(0.85, echelle)
    }

    // MARK: Mise en place

    /// (Re)pose les corps sur les anneaux si le graphe ou l'écran a changé.
    func preparer(_ graphe: PlanGraph, dans taille: CGSize) {
        let cle = graphe.noeuds.map(\.id).joined(separator: "|")
            + "#" + graphe.liens.map(\.id).joined(separator: "|")
            + "#\(Int(taille.width))x\(Int(taille.height))"
        guard cle != signature else { return }
        signature = cle
        self.taille = taille
        liens = graphe.liens
        ordre = graphe.noeuds.map(\.id)
        let echelle = PlanGraph.echelle(pour: taille)
        var nouveaux: [String: Corps] = [:]
        for noeud in graphe.noeuds {
            nouveaux[noeud.id] = Corps(position: graphe.position(de: noeud, dans: taille),
                                       anneau: noeud.anneau,
                                       rayon: Self.rayon(anneau: noeud.anneau, echelle: echelle))
        }
        corps = nouveaux
        tenu = nil
        estStable = false
        derniereHeure = nil
        enRetard = 0
    }

    /// Reduce Motion : le graphe est calculé une fois, puis ne bouge plus.
    func stabiliser(pas nombre: Int = 1500) {
        for _ in 0..<nombre { integrer() }
        estStable = true
    }

    // MARK: Le temps

    /// Avance jusqu'à `heure` (secondes), à pas fixes de 1/60 s.
    func avancer(jusqua heure: Double) {
        guard let avant = derniereHeure else { derniereHeure = heure; return }
        derniereHeure = heure
        enRetard += max(0, heure - avant)
        var pasFaits = 0
        while enRetard >= Self.pas && pasFaits < Self.pasMaximumParImage {
            integrer()
            enRetard -= Self.pas
            pasFaits += 1
        }
        if pasFaits == Self.pasMaximumParImage { enRetard = 0 }
    }

    // MARK: Le doigt

    func attraper(_ id: String) {
        guard corps[id] != nil else { return }
        tenu = id
    }

    /// La bulle tenue suit le doigt ; son élan est celui du doigt.
    func deplacer(vers point: CGPoint) {
        guard let id = tenu, var c = corps[id] else { return }
        let borne = borner(point, rayon: c.rayon)
        c.vitesse = CGVector(dx: borne.x - c.position.x, dy: borne.y - c.position.y)
        c.position = borne
        corps[id] = c
    }

    func lacher() { tenu = nil }

    // MARK: Les forces

    private var facteur: CGFloat { PlanGraph.echelle(pour: taille) / Self.echelleDeLaMaquette }

    private var centre: CGPoint {
        // Le même centre que les anneaux : remonté, les libellés vivent dessous.
        CGPoint(x: taille.width / 2, y: taille.height / 2 - 8 * PlanGraph.echelle(pour: taille))
    }

    private func integrer() {
        guard corps.count > 1 else { return }
        let f = facteur
        let repulsion = Self.repulsion * f * f * f
        var force: [String: CGVector] = [:]
        for id in ordre { force[id] = .zero }

        // 1. Toutes les bulles se repoussent (en 1/d²).
        for i in 0..<ordre.count {
            for j in (i + 1)..<ordre.count {
                guard let a = corps[ordre[i]], let b = corps[ordre[j]] else { continue }
                var dx = b.position.x - a.position.x
                var dy = b.position.y - a.position.y
                if abs(dx) < 0.01 && abs(dy) < 0.01 {
                    // Deux bulles au même point : on les sépare de façon stable.
                    dx = CGFloat(i - j) * 0.1
                    dy = 0.1
                }
                let d2 = dx * dx + dy * dy + 0.01
                let d = d2.squareRoot()
                let intensite = repulsion / d2
                let fx = dx / d * intensite
                let fy = dy / d * intensite
                force[ordre[i]]!.dx -= fx
                force[ordre[i]]!.dy -= fy
                force[ordre[j]]!.dx += fx
                force[ordre[j]]!.dy += fy
            }
        }

        // 2. Les tiges retiennent : un lien fort est plus court et plus raide.
        for lien in liens {
            guard let a = corps[lien.de], let b = corps[lien.vers] else { continue }
            let dx = b.position.x - a.position.x
            let dy = b.position.y - a.position.y
            let d = max(0.01, (dx * dx + dy * dy).squareRoot())
            let poids = CGFloat(min(max(lien.force, 1), 3))
            let repos = (70 + (3 - poids) * 14) * f
            let k = Self.raideur * 0.004 * (0.6 + poids * 0.25)
            let intensite = (d - repos) * k
            force[lien.de]!.dx += dx / d * intensite
            force[lien.de]!.dy += dy / d * intensite
            force[lien.vers]!.dx -= dx / d * intensite
            force[lien.vers]!.dy -= dy / d * intensite
        }

        // 3. Gravité douce vers le centre (plus forte pour l'objectif), puis
        //    amorti, et les bords de l'écran.
        let c = centre
        for id in ordre {
            guard var corpsCourant = corps[id], id != tenu else { continue }
            let gravite: CGFloat = corpsCourant.anneau == 0 ? 0.02 : 0.004
            var v = corpsCourant.vitesse
            v.dx = (v.dx + force[id]!.dx + (c.x - corpsCourant.position.x) * gravite) * Self.amorti
            v.dy = (v.dy + force[id]!.dy + (c.y - corpsCourant.position.y) * gravite) * Self.amorti
            let vitesse = (v.dx * v.dx + v.dy * v.dy).squareRoot()
            if vitesse > Self.vitesseMaximale {
                v.dx *= Self.vitesseMaximale / vitesse
                v.dy *= Self.vitesseMaximale / vitesse
            }
            let voulu = CGPoint(x: corpsCourant.position.x + v.dx, y: corpsCourant.position.y + v.dy)
            let borne = borner(voulu, rayon: corpsCourant.rayon)
            if borne.x != voulu.x { v.dx *= -0.4 }
            if borne.y != voulu.y { v.dy *= -0.4 }
            corpsCourant.position = borne
            corpsCourant.vitesse = v
            corps[id] = corpsCourant
        }
    }

    /// Dans le cadre, avec la place du libellé sous le disque.
    private func borner(_ point: CGPoint, rayon: CGFloat) -> CGPoint {
        let marge = rayon + 6
        let basDuNom: CGFloat = rayon + 30
        guard taille.width > 2 * marge, taille.height > marge + basDuNom else { return point }
        return CGPoint(x: min(max(point.x, marge), taille.width - marge),
                       y: min(max(point.y, marge), taille.height - basDuNom))
    }
}
