import Foundation
import CoreGraphics

// MARK: - Le Plan en graphe (maquette « Plan · graphe de liens », 20 sept. 2026)
//
// Trois anneaux : au centre L'OBJECTIF, autour LES SYMPTÔMES qu'on suit, en
// périphérie LES LEVIERS — apports et habitudes — reliés à ce qu'ils font
// bouger. C'est la valeur ajoutée de Kiwio rendue visible : « le café touche le
// fer, qui touche les ongles et l'énergie ».
//
// Ici, le modèle et le placement : purs, sans SwiftUI, testés. Les positions
// sont CALCULÉES, pas simulées — angles répartis sur chaque anneau, leviers
// tirés vers ceux qu'ils touchent, puis écartés en une passe.
//
// Rien n'est inventé : les symptômes et l'objectif viennent du questionnaire,
// les liens symptôme → apport du bilan, et les habitudes du REGISTRE des
// apports (`HealthCalculator.registreApports`) — la même pénalité, avec le même
// libellé, que celle qui a fait le score.

struct PlanGraph: Equatable {

    enum Genre: Equatable {
        case objectif
        case symptome
        case apport
        case habitude
    }

    struct Noeud: Identifiable, Equatable {
        let id: String
        let genre: Genre
        let nom: String
        /// 0 = centre, 1 = symptômes (et objectifs secondaires), 2 = leviers.
        let anneau: Int
        /// En degrés, 0 = à droite, sens horaire à l'écran (y vers le bas).
        var angle: Double
        /// Score 0-100 d'un apport ; `nil` pour les autres genres.
        var score: Int? = nil
        /// Points que cette habitude retire, tous apports confondus (négatif).
        var points: Int? = nil
    }

    struct Lien: Identifiable, Equatable {
        let de: String
        let vers: String
        /// 1 = lien faible, 2 = moyen, 3 = fort — donne l'épaisseur du trait.
        let force: Int
        var id: String { "\(de)→\(vers)" }
    }

    var noeuds: [Noeud]
    var liens: [Lien]

    static let idCentre = "centre"

    func noeud(_ id: String) -> Noeud? { noeuds.first { $0.id == id } }

    /// Le nœud et ceux qu'il touche : ce qui reste allumé quand on le choisit.
    func voisinage(de id: String) -> Set<String> {
        var ids: Set<String> = [id]
        for lien in liens {
            if lien.de == id { ids.insert(lien.vers) }
            if lien.vers == id { ids.insert(lien.de) }
        }
        return ids
    }

    func voisins(de id: String) -> [Noeud] {
        let ids = voisinage(de: id).subtracting([id])
        return noeuds.filter { ids.contains($0.id) }
    }

    func force(entre a: String, et b: String) -> Int? {
        liens.first { ($0.de == a && $0.vers == b) || ($0.de == b && $0.vers == a) }?.force
    }

    // MARK: Ce qu'on en dit (bandeau de sélection)

    /// « À 42 % · touche 2 symptômes ». Nomme un état, jamais un geste : ce
    /// texte est lisible en gratuit.
    func resume(de id: String) -> String {
        guard let noeud = noeud(id) else { return "" }
        let proches = voisins(de: id)
        let symptomes = proches.filter { $0.genre == .symptome }.count
        let apports = proches.filter { $0.genre == .apport }
        switch noeud.genre {
        case .apport:
            let etat = noeud.score.map { "À \($0) %" }
            let touche = symptomes > 0 ? "touche \(Self.compte(symptomes, "symptôme"))" : nil
            return [etat, touche].compactMap { $0 }.joined(separator: " · ")
        case .symptome:
            return apports.isEmpty ? "Relié à ton objectif" : "\(Self.compte(apports.count, "apport")) en cause"
        case .objectif:
            let suivis = noeud.anneau == 0 ? noeuds.filter { $0.genre == .symptome }.count : symptomes
            return suivis > 0 ? "\(Self.compte(suivis, "symptôme")) sur le chemin" : "Le centre de ton plan"
        case .habitude:
            guard let premier = apports.first else { return "Pèse sur tes apports" }
            return apports.count > 1
                ? "Freine \(Self.compte(apports.count, "apport"))"
                : "Freine ton apport en \(premier.nom.lowercased())"
        }
    }

    private static func compte(_ n: Int, _ mot: String) -> String {
        "\(n) \(mot)\(n > 1 ? "s" : "")"
    }
}

// MARK: - Construction

extension PlanGraph {

    struct Sujet: Equatable {
        let id: String
        let nom: String
        /// Ids des apports (NutrientID) que le bilan rattache à ce sujet.
        var apports: [String] = []
    }

    struct Apport: Equatable {
        let id: String
        let nom: String
        let score: Int
    }

    /// Une habitude déclarée et ce qu'elle retire, apport par apport.
    private struct Habitude {
        struct Effet {
            let apport: String
            let points: Int
        }
        let libelle: String
        var effets: [Effet]
        var total: Int { effets.reduce(0) { $0 + $1.points } }
    }

    static let symptomesAffiches = 4
    static let apportsAffiches = 4
    static let habitudesAffichees = 2

    /// Un score bas = un lien fort : c'est cet apport-là qui pèse en ce moment.
    static func force(pourScore score: Int) -> Int {
        score < 40 ? 3 : (score < 70 ? 2 : 1)
    }

    /// Une pénalité lourde = un lien fort.
    static func force(pourPoints points: Int) -> Int {
        abs(points) >= 15 ? 3 : (abs(points) >= 8 ? 2 : 1)
    }

    /// - Parameters:
    ///   - objectifs: le premier va au centre, les suivants rejoignent l'anneau 1.
    ///   - symptomes: les symptômes suivis, dans l'ordre de priorité du bilan.
    ///   - apports: les apports connus (score du bilan), pour nommer et peser.
    ///   - registre: le registre des apports, d'où viennent les habitudes.
    static func construire(objectifs: [Sujet],
                           symptomes: [Sujet],
                           apports: [Apport],
                           registre: [String: DetailApport]) -> PlanGraph {
        let centre = objectifs.first
        let secondaires = Array(objectifs.dropFirst().prefix(max(0, symptomesAffiches + 1 - min(symptomes.count, symptomesAffiches))))
        let suivis = Array(symptomes.prefix(symptomesAffiches))

        var noeuds: [Noeud] = [
            Noeud(id: idCentre, genre: .objectif, nom: centre?.nom ?? "Ton équilibre", anneau: 0, angle: 0)
        ]
        var liens: [Lien] = []

        var anneau1: [(sujet: Sujet, genre: Genre)] = suivis.map { (sujet: $0, genre: Genre.symptome) }
        anneau1 += secondaires.map { (sujet: $0, genre: Genre.objectif) }
        for element in anneau1 {
            noeuds.append(Noeud(id: element.sujet.id, genre: element.genre, nom: element.sujet.nom, anneau: 1, angle: 0))
            liens.append(Lien(de: idCentre, vers: element.sujet.id, force: 2))
        }

        // Les apports cités par ce qui est affiché, les plus bas d'abord.
        let parId = Dictionary(apports.map { ($0.id, $0) }, uniquingKeysWith: { premier, _ in premier })
        var cites: [String] = []
        let candidats = (centre?.apports ?? []) + anneau1.flatMap { $0.sujet.apports }
        for id in candidats where parId[id] != nil && !cites.contains(id) {
            cites.append(id)
        }
        var classes: [Apport] = cites.compactMap { parId[$0] }
        classes.sort { a, b in
            if a.score != b.score { return a.score < b.score }
            return a.id < b.id
        }
        let retenus: [Apport] = Array(classes.prefix(apportsAffiches))

        for apport in retenus {
            noeuds.append(Noeud(id: apport.id, genre: .apport, nom: apport.nom, anneau: 2, angle: 0, score: apport.score))
            let poids = force(pourScore: apport.score)
            for element in anneau1 where element.sujet.apports.contains(apport.id) {
                liens.append(Lien(de: element.sujet.id, vers: apport.id, force: poids))
            }
            if centre?.apports.contains(apport.id) == true {
                liens.append(Lien(de: idCentre, vers: apport.id, force: poids))
            }
        }

        // Les habitudes : ce que la personne a déclaré et qui pèse sur ces
        // apports-là. Même libellé, mêmes points que dans la fiche de l'apport.
        var habitudes: [Habitude] = []
        for apport in retenus {
            let freins: [ContributionApport] = registre[apport.id]?.freins ?? []
            for frein in freins where frein.section == .modeDeVie || frein.section == .nutrition {
                let effet = Habitude.Effet(apport: apport.id, points: frein.delta)
                if let rang = habitudes.firstIndex(where: { $0.libelle == frein.libelle }) {
                    habitudes[rang].effets.append(effet)
                } else {
                    habitudes.append(Habitude(libelle: frein.libelle, effets: [effet]))
                }
            }
        }
        // Les plus lourdes d'abord (le total est négatif).
        habitudes.sort { a, b in
            if a.total != b.total { return a.total < b.total }
            return a.libelle < b.libelle
        }
        for habitude in habitudes.prefix(habitudesAffichees) {
            let id = "habitude.\(habitude.libelle)"
            noeuds.append(Noeud(id: id, genre: .habitude, nom: habitude.libelle, anneau: 2, angle: 0, points: habitude.total))
            for effet in habitude.effets {
                liens.append(Lien(de: id, vers: effet.apport, force: force(pourPoints: effet.points)))
            }
        }

        var graphe = PlanGraph(noeuds: noeuds, liens: liens)
        graphe.placer()
        return graphe
    }
}

// MARK: - Placement (calculé, en une passe)

extension PlanGraph {

    /// Premier symptôme en haut à gauche, comme sur la maquette.
    static let angleDeDepart = -105.0
    /// Écart minimal entre deux leviers : en dessous, les libellés se touchent.
    static let ecartMinimal = 44.0

    mutating func placer() {
        // Anneau 1 : répartition régulière.
        let premier = noeuds.indices.filter { noeuds[$0].anneau == 1 }
        for (rang, index) in premier.enumerated() {
            noeuds[index].angle = Self.normaliser(Self.angleDeDepart + 360.0 * Double(rang) / Double(max(1, premier.count)))
        }

        // Anneau 2, les apports : vers le barycentre de ceux qu'ils touchent.
        let leviers = noeuds.indices.filter { noeuds[$0].anneau == 2 }
        for index in leviers where noeuds[index].genre == .apport {
            let proches = voisins(de: noeuds[index].id).filter { $0.anneau == 1 }.map(\.angle)
            noeuds[index].angle = Self.moyenneCirculaire(proches) ?? Self.angleDeDepart + 180
        }
        // Puis les habitudes : à côté de l'apport qu'elles freinent.
        for index in leviers where noeuds[index].genre == .habitude {
            let proches = voisins(de: noeuds[index].id).filter { $0.genre == .apport }.map(\.angle)
            noeuds[index].angle = (Self.moyenneCirculaire(proches) ?? 0) - Self.ecartMinimal
        }

        // Une passe d'écartement : dans l'ordre des angles, chacun pousse le suivant.
        guard leviers.count > 1 else { return }
        let ecart = min(Self.ecartMinimal, 360.0 / Double(leviers.count))
        let ordre = leviers.sorted { Self.normaliser(noeuds[$0].angle) < Self.normaliser(noeuds[$1].angle) }
        var precedent = Self.normaliser(noeuds[ordre[0]].angle)
        noeuds[ordre[0]].angle = precedent
        for index in ordre.dropFirst() {
            let voulu = max(Self.normaliser(noeuds[index].angle), precedent + ecart)
            noeuds[index].angle = voulu
            precedent = voulu
        }
        // Le dernier ne doit pas revenir sur le premier. Si la chaîne déborde,
        // on répartit régulièrement : l'écart reste garanti (360 ≥ n × écart).
        let premierAngle = noeuds[ordre[0]].angle
        let maximum = 360.0 - ecart
        if precedent - premierAngle > maximum {
            let pas = maximum / Double(ordre.count - 1)
            for (rang, index) in ordre.enumerated() {
                noeuds[index].angle = premierAngle + pas * Double(rang)
            }
        }
        for index in ordre { noeuds[index].angle = Self.normaliser(noeuds[index].angle) }
    }

    static func normaliser(_ angle: Double) -> Double {
        let reste = angle.truncatingRemainder(dividingBy: 360)
        // Un « −0,0000001° » sorti d'un atan2 vaut 0°, pas 359,9999999°.
        guard abs(reste) > 1e-9 else { return 0 }
        return reste < 0 ? reste + 360 : reste
    }

    /// Moyenne d'angles qui ne se trompe pas autour de 0° / 360°.
    static func moyenneCirculaire(_ angles: [Double]) -> Double? {
        guard !angles.isEmpty else { return nil }
        let x = angles.reduce(0) { $0 + cos($1 * .pi / 180) }
        let y = angles.reduce(0) { $0 + sin($1 * .pi / 180) }
        guard abs(x) > 1e-9 || abs(y) > 1e-9 else { return angles[0] }
        return normaliser(atan2(y, x) * 180 / .pi)
    }

    // MARK: Géométrie à l'écran

    /// Maquette : 353 × 470, anneaux à 100 et 150 pt.
    static let tailleDeReference = CGSize(width: 353, height: 470)
    static let rayons: [CGFloat] = [0, 100, 150]

    static func echelle(pour taille: CGSize) -> CGFloat {
        min(1.15, min(taille.width / tailleDeReference.width, taille.height / tailleDeReference.height))
    }

    func position(de noeud: Noeud, dans taille: CGSize) -> CGPoint {
        let echelle: CGFloat = Self.echelle(pour: taille)
        let rayon: CGFloat = Self.rayons[min(max(noeud.anneau, 0), 2)] * echelle
        let angle: Double = noeud.angle * Double.pi / 180
        // Le centre est remonté : les libellés vivent SOUS les nœuds.
        let centreX: CGFloat = taille.width / 2
        let centreY: CGFloat = taille.height / 2 - 8 * echelle
        let dx: CGFloat = CGFloat(cos(angle)) * rayon
        let dy: CGFloat = CGFloat(sin(angle)) * rayon
        return CGPoint(x: centreX + dx, y: centreY + dy)
    }
}
