import SwiftUI

// MARK: - Le signe Kiwio (maquette finale, « Identité · un seul logo, partout »)
//
// La tranche de kiwi de face, version 2 validée : peau #2F5A16 · chair #5DA838 ·
// halo #9FD46F · cœur #EAF3DE · 12 graines. Aplats nets, aucun dégradé.
// Ce SEUL signe remplace tous les dessins d'avant : l'icône, l'écran de
// chargement et ses loaders, la barre de la page de garde, la confirmation
// Premium, les états vides (le Plan). `KiwiContourMark`, la mascotte et le kiwi
// qui marche ont disparu avec lui.
//
// La géométrie est celle du SVG source, dans une boîte de 100 : des disques
// concentriques, et des graines en ellipses 3,8 × 7,2 posées sur un cercle,
// grand axe tourné vers le centre. `KiwiSigneTests` la tient point par point.
//
// Trois variantes :
//   · standard : sur un fond clair ou sombre, la peau cerne la tranche ;
//   · surVert  : sur un fond vert kiwi (l'icône), la peau disparaît ;
//   · mono     : le pied de page, un disque d'une seule encre, cœur et graines évidés.
//
// Règle de taille de la maquette : sous 32 pt le signe seul ; le nom « Kiwio »
// l'accompagne dans les en-têtes (`KiwiEnTete`, `KiwiLockupBarre`).

enum KiwiMarque {

    // MARK: Palette (hexadécimal : la maquette et les tests parlent la même langue)

    static let hexPeau = "2F5A16"
    static let hexChair = "5DA838"
    static let hexHalo = "9FD46F"
    static let hexCoeur = "EAF3DE"

    static let peau = Color(hex: hexPeau)
    static let chair = Color(hex: hexChair)
    static let halo = Color(hex: hexHalo)
    static let coeur = Color(hex: hexCoeur)

    // MARK: Géométrie (boîte de 100)

    static let nombreDeGraines = 12
    /// Petit axe et grand axe d'une graine (le SVG : rx 1,9 · ry 3,6).
    static let graineLargeur: CGFloat = 3.8
    static let graineHauteur: CGFloat = 7.2

    enum Teinte { case peau, chair, halo, coeur }

    struct Disque: Equatable {
        let rayon: CGFloat
        let teinte: Teinte
    }

    struct Geometrie: Equatable {
        /// Du plus grand au plus petit : l'ordre de dessin.
        let disques: [Disque]
        /// Rayon du cercle où sont posées les graines.
        let orbiteDesGraines: CGFloat

        static let standard = Geometrie(
            disques: [Disque(rayon: 48, teinte: .peau), Disque(rayon: 43, teinte: .chair),
                      Disque(rayon: 21, teinte: .halo), Disque(rayon: 12, teinte: .coeur)],
            orbiteDesGraines: 26)

        /// Sur fond vert kiwi : la chair se confond avec le fond, le halo et le
        /// cœur grandissent un peu, les graines s'écartent (fichier « sur-vert »).
        static let surVert = Geometrie(
            disques: [Disque(rayon: 46, teinte: .chair), Disque(rayon: 22.5, teinte: .halo),
                      Disque(rayon: 12.8, teinte: .coeur)],
            orbiteDesGraines: 28)
    }

    static func couleur(_ teinte: Teinte) -> Color {
        switch teinte {
        case .peau: return peau
        case .chair: return chair
        case .halo: return halo
        case .coeur: return coeur
        }
    }

    /// Centre (boîte de 100) et rotation de la graine `index` : la première à
    /// droite, puis tous les 30°, dans le sens des aiguilles d'une montre.
    /// La rotation (angle + 90°) couche le grand axe dans la direction du centre.
    static func graine(_ index: Int, orbite: CGFloat) -> (centre: CGPoint, rotation: Double) {
        let angle = Double(index) * 2 * .pi / Double(nombreDeGraines)
        let centre = CGPoint(x: 50 + orbite * CGFloat(cos(angle)), y: 50 + orbite * CGFloat(sin(angle)))
        return (centre, angle + .pi / 2)
    }
}

// MARK: - Les formes (boîte de 100, mise à l'échelle du cadre)

/// Un disque centré, de rayon donné sur 100.
private struct KiwiDisqueForme: Shape {
    let rayon: CGFloat

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        return Path(ellipseIn: CGRect(x: rect.midX - rayon * s, y: rect.midY - rayon * s,
                                      width: 2 * rayon * s, height: 2 * rayon * s))
    }
}

/// Une graine : l'ellipse du SVG, posée sur son orbite et tournée vers le centre.
private struct KiwiGraineForme: Shape {
    let index: Int
    let orbite: CGFloat

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let graine = KiwiMarque.graine(index, orbite: orbite)
        let ellipse = Path(ellipseIn: CGRect(x: -KiwiMarque.graineLargeur / 2 * s,
                                             y: -KiwiMarque.graineHauteur / 2 * s,
                                             width: KiwiMarque.graineLargeur * s,
                                             height: KiwiMarque.graineHauteur * s))
        let x = rect.midX + (graine.centre.x - 50) * s
        let y = rect.midY + (graine.centre.y - 50) * s
        return ellipse.applying(CGAffineTransform(translationX: x, y: y).rotated(by: CGFloat(graine.rotation)))
    }
}

/// Le signe mono : un disque plein, cœur et graines évidés (remplissage pair-impair).
private struct KiwiMonoForme: Shape {
    func path(in rect: CGRect) -> Path {
        var chemin = KiwiDisqueForme(rayon: 48).path(in: rect)
        chemin.addPath(KiwiDisqueForme(rayon: 12).path(in: rect))
        for index in 0..<KiwiMarque.nombreDeGraines {
            chemin.addPath(KiwiGraineForme(index: index, orbite: 26).path(in: rect))
        }
        return chemin
    }
}

// MARK: - Le signe

struct KiwiSigne: View {
    enum Variante { case standard, surVert, mono }

    var taille: CGFloat = 44
    var variante: Variante = .standard
    /// Mono : l'encre du disque (le cœur et les graines laissent voir le fond).
    var encre: Color = .dsTexte
    /// Opacité de chaque graine, 0 à 1 : c'est ce que fait tourner le loader.
    /// nil = toutes pleines.
    var graines: [Double]? = nil

    private var geometrie: KiwiMarque.Geometrie {
        variante == .surVert ? .surVert : .standard
    }

    var body: some View {
        Group {
            if variante == .mono {
                KiwiMonoForme().fill(encre, style: FillStyle(eoFill: true))
            } else {
                ZStack {
                    ForEach(Array(geometrie.disques.enumerated()), id: \.offset) { _, disque in
                        KiwiDisqueForme(rayon: disque.rayon).fill(KiwiMarque.couleur(disque.teinte))
                    }
                    ForEach(0..<KiwiMarque.nombreDeGraines, id: \.self) { index in
                        KiwiGraineForme(index: index, orbite: geometrie.orbiteDesGraines)
                            .fill(KiwiMarque.peau)
                            .opacity(opacite(index))
                    }
                }
            }
        }
        .frame(width: taille, height: taille)
        .accessibilityHidden(true)
    }

    private func opacite(_ index: Int) -> Double {
        guard let graines, graines.indices.contains(index) else { return 1 }
        return min(1, max(0, graines[index]))
    }
}

// MARK: - Le nom

/// « Kiwio » en SF Pro Rounded gras, serré comme sur la maquette (-1 pt à 22 pt).
struct KiwiWordmark: View {
    var taille: CGFloat = 22

    var body: some View {
        Text("Kiwio")
            .font(.system(size: taille, weight: .bold, design: .rounded))
            .tracking(-0.045 * taille)
            .foregroundStyle(Color.dsTexte)
    }
}

// MARK: - Les compositions de la maquette

/// Signe au-dessus du nom : l'écran de chargement (72 pt + 22 pt), et les
/// en-têtes qui le prolongent (connexion, page de garde de l'onboarding).
struct KiwiEnTete: View {
    var signe: CGFloat = 72
    var nom: CGFloat = 22

    var body: some View {
        VStack(spacing: signe / 6) {
            KiwiSigne(taille: signe)
            KiwiWordmark(taille: nom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kiwio")
    }
}

/// La barre de l'app : signe 26 pt et nom 19 pt, côte à côte.
struct KiwiLockupBarre: View {
    var body: some View {
        HStack(spacing: 8) {
            KiwiSigne(taille: 26)
            KiwiWordmark(taille: 19)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kiwio")
    }
}

/// La confirmation : le signe 44 pt dans un rond de 72 pt couleur cœur.
struct KiwiConfirmation: View {
    var body: some View {
        KiwiSigne(taille: 44)
            .frame(width: 72, height: 72)
            .background(Circle().fill(KiwiMarque.coeur))
            .accessibilityHidden(true)
    }
}

/// Le pied de page : signe mono 20 pt, le nom, puis ce qu'on lui passe
/// (la version, en petit).
struct KiwiPiedDePage: View {
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            KiwiSigne(taille: 20, variante: .mono, encre: .dsTexte)
            KiwiWordmark(taille: 16)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsTertiaire)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 28) {
            HStack(alignment: .bottom, spacing: 12) {
                KiwiSigne(taille: 120, variante: .surVert)
                    .background(KiwiMarque.chair)
                    .clipShape(RoundedRectangle(cornerRadius: 26.8, style: .continuous))
                KiwiSigne(taille: 60, variante: .surVert)
                    .background(KiwiMarque.chair)
                    .clipShape(RoundedRectangle(cornerRadius: 13.4, style: .continuous))
            }
            KiwiEnTete()
            KiwiLockupBarre()
            KiwiConfirmation()
            KiwiPiedDePage(detail: "1.0.4 (640)")
        }
        .padding(30)
    }
    .background(Color.dsFond)
}
