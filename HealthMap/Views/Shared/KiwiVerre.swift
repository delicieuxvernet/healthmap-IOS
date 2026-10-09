import SwiftUI
import UIKit

// MARK: - Verre liquide (maquette « Kiwio - Motion v3 - Verre liquide », 2 octobre 2026)
//
// Trois décisions portent toute la direction :
//
//   1. Le FOND n'est plus un gris uni : quatre halos flous dérivent lentement
//      sur une base pâle, et la teinte suit l'onglet (kiwi, aube, ciel,
//      orchidée, neutre) en fondu de 0,9 s. → `VerreFond`.
//   2. Les SURFACES sont du verre : cartes en verre dépoli (blanc 80 → 58 %,
//      liseré blanc intérieur, rayon 24), boutons en verre clair plus léger
//      (reflet haut et bas, capsule), action principale en verre teinté vert.
//      → `VerreMatiere` + `.verreCarte()`, `.verreClair()`, `.verrePrincipal()`.
//   3. Les COULEURS sont resserrées : une teinte par catégorie, une version
//      foncée pour le texte. Le vert kiwi reste réservé à ce qui se touche.
//      → `Color.teinte…`.
//
// Le flou d'arrière-plan vivant (`Material`) coûte cher : il est réservé à ce
// qui flotte au-dessus d'un contenu qui défile (barre d'onglets, bord haut,
// voile, feuilles, carte du Plan). Une carte posée sur le fond n'en a pas
// besoin : ce qu'elle recouvre est déjà un dégradé flou.
//
// Sous « Réduire la transparence », chaque matière devient un aplat opaque.
// Sous « Réduire les animations », le fond ne dérive plus et rien ne rebondit.

enum Verre {

    // MARK: Rayons

    /// Carte en verre dépoli.
    static let rayonCarte: CGFloat = 24
    /// Tuile à l'intérieur d'une carte (créneau du rituel, encart d'objectif).
    static let rayonTuile: CGFloat = 14
    /// Carte flottante du Plan, carte de transcription.
    static let rayonCarteFlottante: CGFloat = 28
    /// Coins hauts d'une feuille.
    static let rayonFeuille: CGFloat = 38
    /// Feuille détachée des bords (résultats de dictée).
    static let rayonFeuilleDetachee: CGFloat = 44

    // MARK: Hauteurs

    /// Puce d'en-tête (Eau, Poids, Série, Analyses).
    static let hauteurPuce: CGFloat = 52
    /// Action principale d'une feuille.
    static let hauteurAction: CGFloat = 54
    /// Rangée de saisie du Journal (Dicter, Photo, Autres).
    static let hauteurSaisie: CGFloat = 60
    /// Bascule à deux segments.
    static let hauteurBascule: CGFloat = 38

    // MARK: Encres neutres de la maquette

    /// Ombre portée du verre : un vert-noir, jamais un noir pur.
    static let encreOmbre = Color(red: 22 / 255, green: 44 / 255, blue: 12 / 255)
    /// Voile posé sous une feuille ou la dictée.
    static let encreVoile = Color(red: 16 / 255, green: 30 / 255, blue: 10 / 255)
    /// Piste d'une jauge, pastille d'icône neutre : `rgba(120,120,128,.12)`.
    static let remplissage = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.12)
    /// Piste d'un anneau : `rgba(120,120,128,.14)`.
    static let pisteAnneau = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.14)
    /// Tuile inactive : `rgba(120,120,128,.08)`.
    static let tuileInactive = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.08)
    /// Icône neutre dans une pastille : `rgba(60,60,67,.75)`.
    static let iconeNeutre = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.75)
}

// MARK: - Palette par catégorie

/// Une teinte par catégorie, une version foncée pour le texte posé sur fond
/// clair. Les cinq dernières (B12, magnésium, oméga-3, zinc, calcium) ne sont
/// pas dans la maquette : elles sont dérivées dans la même famille (même
/// clarté, même saturation) pour que les dix apports restent distincts.
extension Color {
    static let teinteKiwi = Color(hex: "5DA838")
    static let teinteKiwiTexte = Color(hex: "3B6D11")
    static let teinteKiwiPale = Color(hex: "EAF3DE")
    static let teinteKiwiClair = Color(hex: "9FD46F")
    static let teinteKiwiPeau = Color(hex: "2F5A16")

    static let teinteEnergie = Color(hex: "F07040")
    static let teinteEnergieTexte = Color(hex: "A94620")

    static let teinteVitamineD = Color(hex: "F1961D")
    static let teinteVitamineDTexte = Color(hex: "995600")
    /// Texte d'une étiquette ambrée (« Nouveau · bêta »).
    static let teinteAmbreEncre = Color(hex: "7F490C")

    static let teinteGlucides = Color(hex: "E6B731")
    static let teinteGlucidesTexte = Color(hex: "876200")
    /// Trait d'icône ou de courbe sur fond clair : le jaune, un cran plus dense.
    static let teinteGlucidesTrait = Color(hex: "D7A10C")

    static let teinteLipides = Color(hex: "F18336")
    static let teinteLipidesTexte = Color(hex: "923F00")

    static let teinteFibres = Color(hex: "4CAC91")
    static let teinteFibresTexte = Color(hex: "206C58")

    static let teinteVitamineC = Color(hex: "11A6AA")
    static let teinteVitamineCTexte = Color(hex: "006368")

    static let teinteEau = Color(hex: "46B1E3")
    static let teinteEauTexte = Color(hex: "147298")
    static let teinteEauClair = Color(hex: "74C6F0")

    static let teinteProteines = Color(hex: "4E82E5")
    static let teinteProteinesTexte = Color(hex: "224FA7")
    static let teinteProteinesPale = Color(hex: "BCD2F9")

    /// Iode, et le créneau du soir.
    static let teinteIode = Color(hex: "7368D4")
    static let teinteIodeTexte = Color(hex: "5348A1")

    static let teinteFer = Color(hex: "AF5FC7")
    static let teinteFerTexte = Color(hex: "7F3C93")

    static let teinteSymptomes = Color(hex: "EB5070")
    static let teinteSymptomesTexte = Color(hex: "B52F4E")

    // Dérivées (hors maquette).

    static let teinteB12 = Color(hex: "E8605B")
    static let teinteB12Texte = Color(hex: "90302E")
    static let teinteMagnesium = Color(hex: "2FA9CE")
    static let teinteMagnesiumTexte = Color(hex: "006582")
    static let teinteOmega3 = Color(hex: "3B9CF6")
    static let teinteOmega3Texte = Color(hex: "00579A")
    static let teinteZinc = Color(hex: "DB5FA1")
    static let teinteZincTexte = Color(hex: "87305F")
    static let teinteCalcium = Color(hex: "8E8E93")
    static let teinteCalciumTexte = Color(hex: "636366")

    /// Version foncée d'une teinte d'apport, pour un libellé posé sur fond
    /// clair (`id` = identifiant canonique : `vitD`, `iron`, `fiber`…).
    static func teinteApportTexte(for id: String) -> Color {
        switch id {
        case "vitD": return .teinteVitamineDTexte
        case "vitB12": return .teinteB12Texte
        case "iron": return .teinteFerTexte
        case "magnesium": return .teinteMagnesiumTexte
        case "omega3": return .teinteOmega3Texte
        case "vitC": return .teinteVitamineCTexte
        case "calcium": return .teinteCalciumTexte
        case "zinc": return .teinteZincTexte
        case "iodine": return .teinteIodeTexte
        case "fiber": return .teinteFibresTexte
        default: return .teinteKiwiTexte
        }
    }
}

// MARK: - Teinte du fond

/// Une couleur en composantes, pour pouvoir fondre deux palettes l'une dans
/// l'autre image par image (un `Color` ne se mélange pas).
struct VerreRVB: Equatable {
    let r: Double
    let v: Double
    let b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        v = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, v: Double, b: Double) {
        self.r = r
        self.v = v
        self.b = b
    }

    func vers(_ autre: VerreRVB, _ p: Double) -> VerreRVB {
        VerreRVB(r: r + (autre.r - r) * p, v: v + (autre.v - v) * p, b: b + (autre.b - b) * p)
    }

    var couleur: Color { Color(red: r, green: v, blue: b) }
}

/// Base pâle + trois couleurs de halo.
struct VerrePalette: Equatable {
    let base: VerreRVB
    let a: VerreRVB
    let b: VerreRVB
    let c: VerreRVB

    func vers(_ autre: VerrePalette, _ p: Double) -> VerrePalette {
        VerrePalette(base: base.vers(autre.base, p), a: a.vers(autre.a, p), b: b.vers(autre.b, p), c: c.vers(autre.c, p))
    }
}

/// La teinte du fond suit l'onglet.
enum VerreTeinte: Int, CaseIterable, Hashable {
    /// Journal.
    case kiwi
    /// Progrès.
    case aube
    /// Plan.
    case ciel
    /// Compléments.
    case orchidee
    /// Réglages.
    case neutre

    var palette: VerrePalette {
        switch self {
        case .kiwi:
            return VerrePalette(base: VerreRVB(0xEDF2E9), a: VerreRVB(0xC9E6B4), b: VerreRVB(0xCFEDE2), c: VerreRVB(0xF3E8D2))
        case .aube:
            return VerrePalette(base: VerreRVB(0xF4F0EA), a: VerreRVB(0xF8D6BF), b: VerreRVB(0xD3EAC2), c: VerreRVB(0xF6E4B0))
        case .ciel:
            return VerrePalette(base: VerreRVB(0xECF0F6), a: VerreRVB(0xC7D8F7), b: VerreRVB(0xCFEDE2), c: VerreRVB(0xDFD8F5))
        case .orchidee:
            return VerrePalette(base: VerreRVB(0xF3EFF3), a: VerreRVB(0xE8D2F0), b: VerreRVB(0xF8DDBF), c: VerreRVB(0xCFEDE2))
        case .neutre:
            return VerrePalette(base: VerreRVB(0xEFF1F4), a: VerreRVB(0xD9E0EB), b: VerreRVB(0xDFEAD6), c: VerreRVB(0xE9E2EC))
        }
    }
}

private struct VerreTeinteKey: EnvironmentKey {
    static let defaultValue: VerreTeinte = .kiwi
}

extension EnvironmentValues {
    /// Teinte ambiante du fond. La racine y pose celle de l'onglet courant ;
    /// tout `VerreFond` de la hiérarchie (onglets, pages poussées, feuilles) la
    /// suit, en fondu.
    var verreTeinte: VerreTeinte {
        get { self[VerreTeinteKey.self] }
        set { self[VerreTeinteKey.self] = newValue }
    }
}

// MARK: - Fond

/// Le fond de l'app : quatre halos flous qui dérivent sur une base pâle.
///
/// La position des halos ne dépend que de l'heure : deux `VerreFond` affichés
/// en même temps (l'onglet qui sort, celui qui entre, la page poussée) sont
/// donc superposables au pixel près, et la transition ne montre aucune couture.
///
/// Dessin : un `Canvas` à 30 images par seconde, quatre dégradés radiaux (le
/// profil d'un disque flouté), aucun filtre de flou. À l'arrêt hors écran, sous
/// « Réduire les animations » et en mode économie d'énergie.
struct VerreFond: View {
    /// Teinte imposée. `nil` : celle de l'environnement.
    var teinte: VerreTeinte? = nil

    @Environment(\.verreTeinte) private var teinteAmbiante
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.estOngletActif) private var estOngletActif
    @Environment(\.scenePhase) private var scenePhase

    @State private var origine: VerreTeinte? = nil
    @State private var debut: Date = .distantPast

    /// Durée du fondu d'une teinte vers l'autre.
    static let dureeFondu: Double = 0.9

    private var cible: VerreTeinte { teinte ?? teinteAmbiante }

    private var economie: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// Le fond ne se redessine plus en continu.
    private var fige: Bool {
        reduceMotion || economie || !estOngletActif || scenePhase != .active
    }

    /// Le fondu de teinte est sauté (aucune horloge ne le ferait avancer).
    private var sansFondu: Bool {
        reduceMotion || economie || scenePhase != .active
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: fige)) { chrono in
            Canvas(opaque: true) { contexte, taille in
                let instant = fige ? Date() : chrono.date
                let palette = paletteAffichee(a: instant)
                let temps = (reduceMotion || economie) ? 0 : instant.timeIntervalSinceReferenceDate
                VerreFond.peindre(&contexte, taille: taille, palette: palette, temps: temps)
            }
        }
        .ignoresSafeArea()
        .onChange(of: cible) { ancienne, _ in
            origine = ancienne
            debut = Date()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func paletteAffichee(a instant: Date) -> VerrePalette {
        guard let origine, !sansFondu else { return cible.palette }
        let brut = instant.timeIntervalSince(debut) / Self.dureeFondu
        let p = min(1, max(0, brut))
        // Entrée et sortie douces, comme le `ease` de la maquette.
        let adouci = p * p * (3 - 2 * p)
        return origine.palette.vers(cible.palette, adouci)
    }

    // MARK: Dessin

    /// Un halo de la maquette, dans son repère de 393 × 852.
    private struct Halo {
        let couleur: Int
        let x: Double
        let y: Double
        let diametre: Double
    }

    private static let halos: [Halo] = [
        Halo(couleur: 0, x: -90, y: -70, diametre: 360),
        Halo(couleur: 1, x: 190, y: -30, diametre: 300),
        Halo(couleur: 2, x: -40, y: 520, diametre: 380),
        Halo(couleur: 0, x: 230, y: 380, diametre: 260),
    ]

    /// Écart-type du flou de la maquette (`blur(48px)`).
    private static let flou: Double = 48

    private static func adoucir(_ p: Double) -> Double { p * p * (3 - 2 * p) }

    static func peindre(_ contexte: inout GraphicsContext, taille: CGSize, palette: VerrePalette, temps: Double) {
        contexte.fill(Path(CGRect(origin: .zero, size: taille)), with: .color(palette.base.couleur))
        guard taille.width > 0, taille.height > 0 else { return }

        let ex = Double(taille.width) / 393
        let ey = Double(taille.height) / 852
        let e = (ex + ey) / 2
        let couleurs = [palette.a, palette.b, palette.c]

        for (j, halo) in halos.enumerated() {
            // Dérive : (0, 0, ×1) → (26, −18, ×1,12) → (−18, 14, ×0,94), en
            // aller-retour, sur 17, 22, 27 et 32 s, décalés de 4 s.
            let periode = 17.0 + Double(j) * 5
            var u = ((temps + Double(j) * 4) / periode).truncatingRemainder(dividingBy: 2)
            if u < 0 { u += 2 }
            if u > 1 { u = 2 - u }
            let dx: Double
            let dy: Double
            let echelle: Double
            if u < 0.5 {
                let k = adoucir(u * 2)
                dx = 26 * k
                dy = -18 * k
                echelle = 1 + 0.12 * k
            } else {
                let k = adoucir((u - 0.5) * 2)
                dx = 26 + (-18 - 26) * k
                dy = -18 + (14 + 18) * k
                echelle = 1.12 + (0.94 - 1.12) * k
            }

            let rayon = halo.diametre / 2 * e * echelle
            let sigma = flou * e
            let cx = (halo.x + halo.diametre / 2) * ex + dx * e
            let cy = (halo.y + halo.diametre / 2) * ey + dy * e
            let portee = rayon + 2.4 * sigma
            let teinte = couleurs[halo.couleur].couleur

            // Profil d'un disque flouté : plein au centre, fondu en S au bord.
            var arrets: [Gradient.Stop] = [Gradient.Stop(color: teinte.opacity(0.95), location: 0)]
            let pas = 12
            let depart = max(0, rayon - 2.4 * sigma)
            for i in 0...pas {
                let d = depart + (portee - depart) * Double(i) / Double(pas)
                let alpha = 0.5 * (1 - erf((d - rayon) / (sigma * 1.41421356)))
                arrets.append(Gradient.Stop(color: teinte.opacity(0.95 * alpha), location: CGFloat(d / portee)))
            }

            let cadre = CGRect(x: cx - portee, y: cy - portee, width: portee * 2, height: portee * 2)
            contexte.fill(
                Path(ellipseIn: cadre),
                with: .radialGradient(
                    Gradient(stops: arrets),
                    center: CGPoint(x: cx, y: cy),
                    startRadius: 0,
                    endRadius: CGFloat(portee)
                )
            )
        }
    }
}

// MARK: - Matières

/// Ombre portée d'une plaque de verre.
struct VerreOmbre {
    var couleur: Color
    var rayon: CGFloat
    var y: CGFloat
}

/// Recette d'une surface en verre : dégradé, reflets, liseré, ombre.
struct VerreMatiere {
    /// Dégradé de la plaque, de `debut` vers `fin`.
    var arrets: [Gradient.Stop]
    var debut: UnitPoint = .top
    var fin: UnitPoint = .bottom
    /// Reflet blanc sur l'arête haute (opacité).
    var refletHaut: Double = 0
    /// Reflet sur l'arête basse (opacité) et sa couleur.
    var refletBas: Double = 0
    var refletBasCouleur: Color = .white
    /// Liseré blanc intérieur de 0,5 pt (opacité).
    var lisere: Double = 0
    /// Éclat blanc sur la moitié haute (opacité au sommet).
    var eclat: Double = 0
    var ombre: VerreOmbre? = nil
    /// Flou d'arrière-plan vivant : seulement pour ce qui flotte au-dessus
    /// d'un contenu qui défile.
    var flouVivant: Bool = false
    /// Aplat de remplacement sous « Réduire la transparence ».
    var opaque: Color = .white

    private static func blanc(_ haut: Double, _ bas: Double) -> [Gradient.Stop] {
        [
            Gradient.Stop(color: blancContraste(haut), location: 0),
            Gradient.Stop(color: blancContraste(bas), location: 1),
        ]
    }

    /// Un blanc translucide qui se densifie sous « Augmenter le contraste » :
    /// l'opacité gagne 70 % de ce qui lui manque (.58 → .87, .40 → .82). Le
    /// texte posé dessus garde alors son contraste quel que soit le fond.
    private static func blancContraste(_ opacite: Double) -> Color {
        Color(uiColor: UIColor { trait in
            let alpha = trait.accessibilityContrast == .high ? opacite + (1 - opacite) * 0.7 : opacite
            return UIColor(white: 1, alpha: alpha)
        })
    }

    /// Une couleur, et sa version plus foncée sous « Augmenter le contraste ».
    private static func vert(_ normal: String, eleve: String) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(Color(hex: trait.accessibilityContrast == .high ? eleve : normal))
        })
    }

    /// Carte en verre dépoli : blanc 80 → 58 %, liseré intérieur.
    static let carte = VerreMatiere(
        arrets: blanc(0.80, 0.58),
        refletHaut: 0.95,
        lisere: 0.7,
        ombre: VerreOmbre(couleur: Verre.encreOmbre.opacity(0.11), rayon: 14, y: 10),
        liquide: .clair
    )

    /// La même carte, quand elle flotte au-dessus d'un contenu (Plan,
    /// transcription) : flou vivant en plus.
    static let carteFlottante = VerreMatiere(
        arrets: blanc(0.80, 0.58),
        refletHaut: 0.95,
        lisere: 0.7,
        ombre: VerreOmbre(couleur: Verre.encreOmbre.opacity(0.11), rayon: 14, y: 10),
        flouVivant: true,
        liquide: .clair
    )

    /// Verre clair des boutons et des puces : blanc 74 → 40 %, reflet haut
    /// et bas.
    static let clair = VerreMatiere(
        arrets: blanc(0.74, 0.40),
        refletHaut: 1,
        refletBas: 0.45,
        lisere: 0.85,
        ombre: VerreOmbre(couleur: Verre.encreOmbre.opacity(0.14), rayon: 8, y: 5),
        liquide: .clair
    )

    /// Verre clair « activé » (le bouton Autres déplié) : vert pâle.
    static let clairActif = VerreMatiere(
        arrets: [
            Gradient.Stop(color: Color(red: 228 / 255, green: 242 / 255, blue: 216 / 255).opacity(0.92), location: 0),
            Gradient.Stop(color: Color(red: 206 / 255, green: 231 / 255, blue: 190 / 255).opacity(0.72), location: 1),
        ],
        refletHaut: 1,
        refletBas: 0.45,
        lisere: 0.85,
        ombre: VerreOmbre(couleur: Verre.encreOmbre.opacity(0.14), rayon: 8, y: 5),
        opaque: Color.teinteKiwiPale,
        liquide: .teinte(Color.teinteKiwi.opacity(0.22))
    )

    /// Barre d'onglets : blanc 62 → 40 %, flou vivant.
    static let barre = VerreMatiere(
        arrets: blanc(0.62, 0.40),
        refletHaut: 1,
        refletBas: 0.4,
        lisere: 0.8,
        ombre: VerreOmbre(couleur: Verre.encreOmbre.opacity(0.16), rayon: 17, y: 12),
        flouVivant: true,
        liquide: .clair
    )

    /// Pastille de l'onglet actif : blanc 95 → 60 %.
    static let pastille = VerreMatiere(
        arrets: blanc(0.95, 0.60),
        refletHaut: 1,
        lisere: 0.9,
        ombre: VerreOmbre(couleur: Verre.encreOmbre.opacity(0.12), rayon: 6, y: 3)
    )

    /// Curseur d'une bascule : blanc 100 → 78 %.
    static let curseur = VerreMatiere(
        arrets: blanc(1, 0.78),
        refletHaut: 1,
        lisere: 0.9,
        ombre: VerreOmbre(couleur: Verre.encreOmbre.opacity(0.14), rayon: 6, y: 4)
    )

    /// Piste d'une bascule : blanc 34 %. Pas de flou vivant : une bascule vit
    /// dans une page qui défile, posée sur le fond (déjà flou).
    static let piste = VerreMatiere(
        arrets: blanc(0.34, 0.34),
        lisere: 0.75,
        opaque: Color(uiColor: .systemGray5)
    )

    /// Verre posé sur le voile (bouton « Annuler » de la dictée) : blanc
    /// 74 → 50 %, libellé en encre. Blanc sur un verre à 34 → 14 %, il ne
    /// tenait que 1,5:1 (audit du 9 oct. 2026) ; l'encre tient 11:1.
    static let surVoile = VerreMatiere(
        arrets: blanc(0.74, 0.50),
        refletHaut: 0.7,
        lisere: 0.5,
        flouVivant: true,
        opaque: Color(uiColor: .systemGray)
    )

    /// Action principale : verre vert profond, même reflet, libellé blanc.
    ///
    /// Conformité WCAG AA (audit du 9 oct. 2026, maquette validée par Arthur) :
    /// le blanc sur `#8AD262 → #5DA838 → #4C982B` ne tenait que 2,4 à 3,1:1
    /// sous le libellé. `#4C9330 → #387A1C → #2C6416` tient 4,6 à 5,7:1 ;
    /// sous « Augmenter le contraste », `#3E8424 → #2F6A19 → #24550F`.
    static let principal = VerreMatiere(
        arrets: [
            Gradient.Stop(color: vert("4C9330", eleve: "3E8424"), location: 0),
            Gradient.Stop(color: vert("387A1C", eleve: "2F6A19"), location: 0.55),
            Gradient.Stop(color: vert("2C6416", eleve: "24550F"), location: 1),
        ],
        refletHaut: 0.75,
        refletBas: 0.28,
        refletBasCouleur: Color(red: 20 / 255, green: 60 / 255, blue: 0),
        lisere: 0.3,
        ombre: VerreOmbre(couleur: Color(red: 66 / 255, green: 132 / 255, blue: 38 / 255).opacity(0.42), rayon: 12, y: 9),
        opaque: vert("387A1C", eleve: "2F6A19")
    )

    /// Le bouton Dicter : le même verre vert profond, bombé (éclat sur la
    /// moitié haute, dégradé en biais).
    static let principalBombe = VerreMatiere(
        arrets: [
            Gradient.Stop(color: vert("4C9330", eleve: "3E8424"), location: 0),
            Gradient.Stop(color: vert("387A1C", eleve: "2F6A19"), location: 0.52),
            Gradient.Stop(color: vert("2C6416", eleve: "24550F"), location: 1),
        ],
        debut: UnitPoint(x: 0.3, y: 0),
        fin: UnitPoint(x: 0.7, y: 1),
        refletHaut: 0.8,
        refletBas: 0.3,
        refletBasCouleur: Color(red: 20 / 255, green: 60 / 255, blue: 0),
        lisere: 0.35,
        eclat: 0.38,
        ombre: VerreOmbre(couleur: Color(red: 66 / 255, green: 132 / 255, blue: 38 / 255).opacity(0.45), rayon: 13, y: 11),
        opaque: vert("387A1C", eleve: "2F6A19")
    )

    /// Carte en verre teintée d'une couleur de catégorie dans son coin haut
    /// gauche (les quatre repas du Journal) : `c` à 20 % → 0 à 62 %, posé sur
    /// le verre de carte.
    static func carteTeintee(_ couleur: Color) -> VerreMatiere {
        var matiere = VerreMatiere.carte
        matiere.teinteCoin = couleur
        matiere.liquide = .teinte(couleur.opacity(0.16))
        return matiere
    }

    /// Couleur fondue dans le coin haut gauche (voir `carteTeintee`).
    var teinteCoin: Color? = nil
    /// Sur iOS 26 et plus : le VRAI verre liquide d'iOS (`glassEffect`), qui
    /// floute, sature et réfracte ce qu'il recouvre. La recette dessinée
    /// au-dessus reste celle d'iOS 17 à 25. `nil` : la matière garde sa
    /// recette partout (actions vertes, pastilles, curseurs).
    var liquide: VerreLiquide? = nil
}

/// La variante de verre liquide natif d'une matière (iOS 26 et plus).
enum VerreLiquide {
    /// Verre liquide ordinaire.
    case clair
    /// Verre liquide légèrement teinté.
    case teinte(Color)
}

/// Une plaque de verre : la matière dessinée dans une forme.
struct VerrePlaque<Forme: InsettableShape>: View {
    let forme: Forme
    let matiere: VerreMatiere

    @Environment(\.accessibilityReduceTransparency) private var reduireTransparence
    @Environment(\.colorSchemeContrast) private var contraste

    var body: some View {
        if #available(iOS 26.0, *) {
            // Sous « Augmenter le contraste », la recette dessinée, dont le
            // blanc se densifie : le verre natif laisserait trop voir le fond.
            if let liquide = matiere.liquide, !reduireTransparence, contraste != .increased {
                VerreLiquideNatif(forme: forme, liquide: liquide)
            } else {
                recette
            }
        } else {
            recette
        }
    }

    /// La recette dessinée de la maquette (iOS 17 à 25, et les matières sans
    /// verre natif).
    private var recette: some View {
        ZStack {
            if reduireTransparence {
                forme.fill(matiere.opaque)
            } else {
                if matiere.flouVivant {
                    forme.fill(.ultraThinMaterial)
                }
                forme.fill(LinearGradient(stops: matiere.arrets, startPoint: matiere.debut, endPoint: matiere.fin))
            }
            if let coin = matiere.teinteCoin {
                forme.fill(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: coin.opacity(0.20), location: 0),
                            Gradient.Stop(color: coin.opacity(0), location: 0.62),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            if matiere.eclat > 0 {
                forme.fill(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: Color.white.opacity(matiere.eclat), location: 0),
                            Gradient.Stop(color: Color.white.opacity(0), location: 0.5),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            if matiere.refletBas > 0 {
                forme.strokeBorder(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: matiere.refletBasCouleur.opacity(0), location: 0.62),
                            Gradient.Stop(color: matiere.refletBasCouleur.opacity(matiere.refletBas), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            if matiere.refletHaut > 0 {
                forme.strokeBorder(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: Color.white.opacity(matiere.refletHaut), location: 0),
                            Gradient.Stop(color: Color.white.opacity(0), location: 0.38),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            if matiere.lisere > 0 {
                forme.strokeBorder(Color.white.opacity(matiere.lisere), lineWidth: 0.5)
            }
        }
        .background {
            if let ombre = matiere.ombre {
                VerreOmbrePortee(forme: forme, ombre: ombre)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Le verre liquide natif d'iOS 26 dans une forme : il floute, sature et
/// réfracte ce qu'il recouvre, comme les barres et boutons du système.
@available(iOS 26.0, *)
private struct VerreLiquideNatif<Forme: InsettableShape>: View {
    let forme: Forme
    let liquide: VerreLiquide

    private var verre: Glass {
        switch liquide {
        case .clair:
            return .regular
        case .teinte(let couleur):
            return .regular.tint(couleur)
        }
    }

    var body: some View {
        Color.clear
            .glassEffect(verre, in: forme)
            .allowsHitTesting(false)
    }
}

/// L'ombre d'une plaque, DÉCOUPÉE : rien sous la plaque. Le verre est
/// translucide ; une ombre ordinaire se verrait à travers et le salirait.
struct VerreOmbrePortee<Forme: InsettableShape>: View {
    let forme: Forme
    let ombre: VerreOmbre

    var body: some View {
        forme
            // Un point en retrait : le bord anticrénelé de la silhouette reste
            // sous la découpe, sans laisser de filet sombre.
            .inset(by: 1)
            .fill(Color.black)
            .shadow(color: ombre.couleur, radius: ombre.rayon, x: 0, y: ombre.y)
            .mask {
                // Tout sauf l'intérieur de la plaque. La forme reste à la
                // taille de la plaque ; seul le rectangle déborde.
                ZStack {
                    Rectangle().padding(-(ombre.rayon * 3 + abs(ombre.y)))
                    forme.blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

extension View {
    /// Pose une plaque de verre derrière la vue.
    func verre<Forme: InsettableShape>(_ matiere: VerreMatiere, forme: Forme) -> some View {
        background { VerrePlaque(forme: forme, matiere: matiere) }
    }

    /// Carte en verre dépoli (rayon 24). Le contenu est rogné à la carte.
    func verreCarte(rayon: CGFloat = Verre.rayonCarte) -> some View {
        let forme = RoundedRectangle(cornerRadius: rayon, style: .continuous)
        return clipShape(forme).verre(.carte, forme: forme)
    }

    /// Carte en verre dépoli teintée dans son coin (repas du Journal).
    func verreCarte(teinte: Color, rayon: CGFloat = Verre.rayonCarte) -> some View {
        let forme = RoundedRectangle(cornerRadius: rayon, style: .continuous)
        return clipShape(forme).verre(.carteTeintee(teinte), forme: forme)
    }

    /// Carte en verre qui flotte au-dessus d'un contenu (flou vivant).
    func verreCarteFlottante(rayon: CGFloat = Verre.rayonCarteFlottante) -> some View {
        let forme = RoundedRectangle(cornerRadius: rayon, style: .continuous)
        return clipShape(forme).verre(.carteFlottante, forme: forme)
    }

    /// Verre clair en capsule : puces, boutons secondaires.
    func verreClair() -> some View {
        verre(.clair, forme: Capsule(style: .continuous))
    }

    /// Verre clair dans une forme donnée (cercle d'un « − / + », tuile de
    /// rayon 22).
    func verreClair<Forme: InsettableShape>(_ forme: Forme) -> some View {
        verre(.clair, forme: forme)
    }

    /// Verre teinté vert en capsule : l'action principale.
    func verrePrincipal() -> some View {
        verre(.principal, forme: Capsule(style: .continuous))
    }

    /// Verre teinté vert dans une forme donnée.
    func verrePrincipal<Forme: InsettableShape>(_ forme: Forme) -> some View {
        verre(.principal, forme: forme)
    }
}

// MARK: - Feuilles

/// Fond d'une feuille : verre épais, presque blanc, flou vivant.
/// `rgba(250,252,248,.84) → rgba(243,247,241,.76)` sur un flou de 40.
struct VerreFeuilleFond: View {
    @Environment(\.accessibilityReduceTransparency) private var reduireTransparence

    private var bordure: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Verre.rayonFeuille,
            topTrailingRadius: Verre.rayonFeuille,
            style: .continuous
        )
    }

    var body: some View {
        ZStack {
            if reduireTransparence {
                Color(red: 247 / 255, green: 250 / 255, blue: 245 / 255)
            } else {
                Rectangle().fill(.regularMaterial)
                LinearGradient(
                    colors: [
                        Color(red: 250 / 255, green: 252 / 255, blue: 248 / 255).opacity(0.84),
                        Color(red: 243 / 255, green: 247 / 255, blue: 241 / 255).opacity(0.76),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                // Liseré blanc intérieur et reflet de l'arête haute : seulement
                // les coins hauts, le bas de la feuille est le bord de l'écran.
                bordure.strokeBorder(Color.white.opacity(0.8), lineWidth: 0.5)
                bordure
                    .strokeBorder(Color.white, lineWidth: 1)
                    .mask {
                        LinearGradient(
                            stops: [
                                Gradient.Stop(color: .black, location: 0),
                                Gradient.Stop(color: .black.opacity(0), location: 0.02),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fond d'une page poussée ou d'une couverture plein écran hors onglets :
/// le fond de l'app, sous un voile de verre presque opaque
/// (`rgba(247,250,245,.9) → rgba(240,245,238,.84)`).
struct VerrePageFond: View {
    var body: some View {
        ZStack {
            VerreFond()
            LinearGradient(
                colors: [
                    Color(red: 247 / 255, green: 250 / 255, blue: 245 / 255).opacity(0.9),
                    Color(red: 240 / 255, green: 245 / 255, blue: 238 / 255).opacity(0.84),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Donne à une feuille son fond de verre et ses coins de 38.
    /// À poser sur le CONTENU de la feuille, qui ne doit plus peindre de fond
    /// opaque lui-même.
    func verreFeuille() -> some View {
        presentationBackground { VerreFeuilleFond() }
            .presentationCornerRadius(Verre.rayonFeuille)
    }
}

// MARK: - Voile et bord haut

/// Le voile posé derrière la dictée ou une feuille maison : `rgba(16,30,10,.22)`
/// sur un flou de 22.
struct VerreVoile: View {
    @Environment(\.accessibilityReduceTransparency) private var reduireTransparence

    var body: some View {
        ZStack {
            if !reduireTransparence {
                Rectangle().fill(.ultraThinMaterial)
            }
            Verre.encreVoile.opacity(reduireTransparence ? 0.55 : 0.22)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Le bord haut flouté : sous la barre d'état, le contenu qui défile se fond
/// dans un flou blanc au lieu de passer net sous l'heure.
struct VerreBordHaut: View {
    @Environment(\.accessibilityReduceTransparency) private var reduireTransparence

    var body: some View {
        GeometryReader { geo in
            let hauteur = geo.safeAreaInsets.top + 6
            ZStack {
                if !reduireTransparence {
                    Rectangle().fill(.ultraThinMaterial)
                }
                LinearGradient(
                    colors: [Color.white.opacity(reduireTransparence ? 0.9 : 0.5), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .mask {
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: .black, location: 0),
                        Gradient.Stop(color: .black, location: 0.5),
                        Gradient.Stop(color: .black.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: hauteur)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Bascule à segments

/// Bascule en verre (« Compléments / Par l'assiette ») : piste translucide,
/// curseur de verre blanc qui glisse avec un ressort.
struct VerreBascule<Valeur: Hashable>: View {
    @Binding var selection: Valeur
    let options: [(valeur: Valeur, libelle: String)]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var tailleTexte

    private var index: Int {
        options.firstIndex { $0.valeur == selection } ?? 0
    }

    @ViewBuilder
    var body: some View {
        if tailleTexte.isAccessibilitySize {
            empilee
        } else {
            enLigne
        }
    }

    /// Aux tailles d'accessibilité, les options s'empilent sur toute la
    /// largeur : en deux moitiés de 38 pt, « Compléments » se coupait (AX3).
    /// L'option choisie porte le curseur de verre blanc.
    private var empilee: some View {
        VStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let actif = option.valeur == selection
                Button {
                    guard !actif else { return }
                    HapticService.shared.selection()
                    selection = option.valeur
                } label: {
                    Text(option.libelle)
                        .font(.system(.subheadline, design: .default).weight(actif ? .semibold : .medium))
                        .foregroundStyle(Color.dsTexte)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                        .background {
                            if actif {
                                Color.clear
                                    .verre(.curseur, forme: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(actif ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .verre(.piste, forme: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private var enLigne: some View {
        GeometryReader { geo in
            let largeur = max(0, (geo.size.width - 6) / CGFloat(max(1, options.count)))
            ZStack(alignment: .leading) {
                Color.clear
                    .frame(width: max(0, largeur), height: Verre.hauteurBascule - 6)
                    .verre(.curseur, forme: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .offset(x: 3 + CGFloat(index) * largeur)
                    .animation(reduceMotion ? nil : Animation.kiwiPastille, value: selection)
                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        let actif = option.valeur == selection
                        Button {
                            guard !actif else { return }
                            HapticService.shared.selection()
                            selection = option.valeur
                        } label: {
                            Text(option.libelle)
                                .font(.system(.subheadline, design: .default).weight(actif ? .semibold : .medium))
                                .foregroundStyle(Color.dsTexte)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(actif ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, 3)
            }
            .frame(width: geo.size.width, height: Verre.hauteurBascule)
        }
        .frame(height: Verre.hauteurBascule)
        .verre(.piste, forme: Capsule(style: .continuous))
        // La bascule fait 38 pt de haut : la cible tactile déborde de 3 pt en
        // haut et en bas pour atteindre 44.
        .contentShape(Rectangle().inset(by: -3))
    }
}

// MARK: - Puce d'en-tête

/// Puce de verre de l'en-tête d'un onglet (« Eau · 0,75 L ») : pastille de
/// 30 pt à gauche, libellé secondaire de 12, valeur de 15 / 600.
struct VerrePuce<Icone: View>: View {
    let libelle: String
    let valeur: String
    /// Écart entre la pastille et le texte : 9 au Journal, 10 en Progrès.
    var espacement: CGFloat = 9
    @ViewBuilder var icone: () -> Icone

    var body: some View {
        HStack(spacing: espacement) {
            icone()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(libelle)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(Color.dsSecondaire)
                    .lineLimit(1)
                Text(valeur)
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .frame(minHeight: Verre.hauteurPuce)
        .verreClair()
        // La plaque ignore les touches : dans un bouton, c'est cette forme
        // qui rend toute la puce touchable.
        .contentShape(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Pastille ronde teintée portant une icône (30 pt dans une puce, 36 ou 40
/// dans une ligne) : fond à 12 % de la teinte, icône de la teinte.
struct VerrePastilleIcone: View {
    let symbole: String
    var teinte: Color? = nil
    var taille: CGFloat = 30
    var tailleIcone: CGFloat = 16

    var body: some View {
        Image(systemName: symbole)
            .font(.system(size: tailleIcone, weight: .medium))
            .foregroundStyle(teinte ?? Verre.iconeNeutre)
            .frame(width: taille, height: taille)
            .background(Circle().fill(teinte.map { $0.opacity(0.12) } ?? Verre.remplissage))
            .accessibilityHidden(true)
    }
}

// MARK: - Brillance d'une action principale

/// Valeur animée par images clés (une seule grandeur).
struct VerreCurseurAnime {
    var valeur: CGFloat
}

/// Un reflet qui traverse l'action principale toutes les 3,2 s (bande de
/// 40 %, inclinée). Rien sous « Réduire les animations ».
struct VerreBrillance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.estOngletActif) private var estOngletActif
    /// La maquette attend une seconde avant le premier passage, une seule fois.
    @State private var demarre = false

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion && estOngletActif && demarre {
                GeometryReader { geo in
                    let bande = geo.size.width * 0.4
                    LinearGradient(
                        colors: [Color.white.opacity(0), Color.white.opacity(0.4), Color.white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bande, height: geo.size.height * 1.6)
                    .rotationEffect(.degrees(20))
                    .keyframeAnimator(initialValue: VerreCurseurAnime(valeur: -1.2), repeating: true) { vue, etat in
                        vue.offset(x: etat.valeur * bande, y: -geo.size.height * 0.3)
                    } keyframes: { _ in
                        KeyframeTrack(\.valeur) {
                            MoveKeyframe(-1.2)
                            CubicKeyframe(3.3, duration: 1.76)
                            LinearKeyframe(3.3, duration: 1.44)
                        }
                    }
                }
                .clipShape(Capsule(style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .task {
            guard !demarre else { return }
            try? await Task.sleep(for: .seconds(1))
            demarre = true
        }
    }
}

extension View {
    /// Reflet périodique sur une action principale en capsule.
    func verreBrillance() -> some View {
        modifier(VerreBrillance())
    }
}

// MARK: - Halo qui respire

/// Un anneau blanc qui s'élargit et s'efface autour d'une icône (le micro du
/// bouton Dicter) : 1 → 1,35 en 2,6 s, en boucle.
struct VerreHaloQuiRespire: View {
    var couleur: Color = Color.white.opacity(0.6)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.estOngletActif) private var estOngletActif

    var body: some View {
        if reduceMotion || !estOngletActif {
            EmptyView()
        } else {
            Circle()
                .strokeBorder(couleur, lineWidth: 1.5)
                .keyframeAnimator(initialValue: VerreCurseurAnime(valeur: 0), repeating: true) { vue, etat in
                    vue
                        .scaleEffect(1 + 0.35 * etat.valeur)
                        .opacity(Double(1 - etat.valeur))
                } keyframes: { _ in
                    KeyframeTrack(\.valeur) {
                        MoveKeyframe(0)
                        CubicKeyframe(1, duration: 2.6)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Cascade

/// Un élément qui arrive en cascade : fondu de 0,4 s, remontée de `decalage`
/// sur un ressort, après `delai`. Il disparaît sans animation (comme la
/// maquette : la sortie est sèche, c'est l'entrée qui se joue).
struct VerreCascade: ViewModifier {
    let visible: Bool
    let delai: Double
    let decalage: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: (visible || reduceMotion) ? 0 : decalage)
            .animation((visible && !reduceMotion) ? Animation.kiwiCascade.delay(delai) : nil, value: visible)
            .opacity(visible ? 1 : 0)
            .animation(visible ? Animation.easeOut(duration: 0.4).delay(reduceMotion ? 0 : delai) : nil, value: visible)
    }
}

/// Une pastille qui surgit : 0,6 → 1 sur un ressort vif, fondu de 0,3 s.
struct VerreSurgir: ViewModifier {
    let visible: Bool
    let delai: Double
    let depart: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect((visible || reduceMotion) ? 1 : depart)
            .animation((visible && !reduceMotion) ? Animation.kiwiRebond.delay(delai) : nil, value: visible)
            .opacity(visible ? 1 : 0)
            .animation(visible ? Animation.easeOut(duration: 0.3).delay(reduceMotion ? 0 : delai) : nil, value: visible)
    }
}

extension View {
    /// Entrée en cascade pilotée par un booléen (causes, lignes, conseils).
    func verreCascade(_ visible: Bool, delai: Double = 0, decalage: CGFloat = 12) -> some View {
        modifier(VerreCascade(visible: visible, delai: delai, decalage: decalage))
    }

    /// Une pastille qui surgit (aliments suggérés, étiquettes de gain).
    func verreSurgir(_ visible: Bool, delai: Double = 0, depart: CGFloat = 0.6) -> some View {
        modifier(VerreSurgir(visible: visible, delai: delai, depart: depart))
    }
}

// MARK: - Gerbe

/// Une particule d'une gerbe.
struct VerreParticule: Identifiable {
    let id: Int
    let couleur: Color
    let taille: CGFloat
    let dx: CGFloat
    let dy: CGFloat
    let duree: Double
}

/// Une salve : toutes les particules parties au même instant.
struct VerreSalve: Identifiable {
    let id = UUID()
    let particules: [VerreParticule]
}

/// Une gerbe de particules qui part du centre de la vue quand `declencheur`
/// change (coche d'une prise, objectif d'eau atteint). Les particules mesurent
/// 4, 6 ou 8 pt, partent à `distance` ± 30 %, rétrécissent à 0,3 et
/// s'effacent en 0,65 à 0,9 s. Rien sous « Réduire les animations ».
struct VerreGerbe<Declencheur: Equatable>: ViewModifier {
    let declencheur: Declencheur
    let couleurs: [Color]
    let nombre: Int
    let distance: CGFloat
    /// La gerbe ne part que si cette condition est vraie au moment du
    /// changement (cocher, pas décocher).
    let si: () -> Bool

    @State private var salves: [VerreSalve] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    ForEach(salves) { salve in
                        ForEach(salve.particules) { particule in
                            VerreParticuleVue(particule: particule)
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: declencheur) { _, _ in
                guard !reduceMotion, si(), !couleurs.isEmpty, nombre > 0 else { return }
                var particules: [VerreParticule] = []
                for i in 0..<nombre {
                    let angle = Double(i) / Double(nombre) * 2 * Double.pi + Double.random(in: 0..<0.5)
                    let portee = Double(distance) * Double.random(in: 0.7..<1.3)
                    particules.append(VerreParticule(
                        id: i,
                        couleur: couleurs[i % couleurs.count],
                        taille: CGFloat(4 + (i % 3) * 2),
                        dx: CGFloat(cos(angle) * portee),
                        dy: CGFloat(sin(angle) * portee),
                        duree: Double.random(in: 0.65..<0.9)
                    ))
                }
                let salve = VerreSalve(particules: particules)
                salves.append(salve)
                let identifiant = salve.id
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1000))
                    salves.removeAll { $0.id == identifiant }
                }
            }
    }
}

private struct VerreParticuleVue: View {
    let particule: VerreParticule
    @State private var partie = false

    var body: some View {
        Circle()
            .fill(particule.couleur)
            .frame(width: particule.taille, height: particule.taille)
            .scaleEffect(partie ? 0.3 : 1)
            .offset(x: partie ? particule.dx : 0, y: partie ? particule.dy : 0)
            .opacity(partie ? 0 : 1)
            .onAppear {
                withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: particule.duree)) {
                    partie = true
                }
            }
    }
}

extension View {
    /// Gerbe de particules au changement de `declencheur`.
    func verreGerbe<Declencheur: Equatable>(
        _ declencheur: Declencheur,
        couleurs: [Color],
        nombre: Int = 12,
        distance: CGFloat = 28,
        si: @escaping () -> Bool = { true }
    ) -> some View {
        modifier(VerreGerbe(declencheur: declencheur, couleurs: couleurs, nombre: nombre, distance: distance, si: si))
    }
}

// MARK: - Texte qui s'envole

/// État animé d'un texte qui s'envole.
struct VerreEnvolEtat {
    var y: CGFloat = 6
    var opacite: Double = 0
}

/// Un petit texte (« +25 cl ») qui monte et s'efface au-dessus de la vue quand
/// `declencheur` change : 13 / 600, 1 s. Rien sous « Réduire les animations ».
struct VerreEnvol<Declencheur: Equatable>: ViewModifier {
    let declencheur: Declencheur
    let texte: String
    let couleur: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if !reduceMotion {
                Text(texte)
                    .font(.system(.footnote, design: .default).weight(.semibold))
                    .foregroundStyle(couleur)
                    .fixedSize()
                    .keyframeAnimator(initialValue: VerreEnvolEtat(), trigger: declencheur) { vue, etat in
                        vue
                            .offset(y: etat.y)
                            .opacity(etat.opacite)
                    } keyframes: { _ in
                        KeyframeTrack(\.y) {
                            MoveKeyframe(6)
                            CubicKeyframe(-12, duration: 0.3)
                            CubicKeyframe(-36, duration: 0.7)
                        }
                        KeyframeTrack(\.opacite) {
                            MoveKeyframe(0)
                            LinearKeyframe(1, duration: 0.3)
                            LinearKeyframe(0, duration: 0.7)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Un texte qui s'envole au-dessus de la vue au changement de `declencheur`.
    func verreEnvol<Declencheur: Equatable>(_ declencheur: Declencheur, texte: String, couleur: Color) -> some View {
        modifier(VerreEnvol(declencheur: declencheur, texte: texte, couleur: couleur))
    }
}

// MARK: - Rebond ponctuel

/// La vue rebondit une fois quand `declencheur` change : 1 → `creux` →
/// `crete` → 1 sur `duree`. Coche : 0,75 puis 1,2. Nœud du Plan : 0,86 puis
/// 1,1. Rien sous « Réduire les animations ».
struct VerrePop<Declencheur: Equatable>: ViewModifier {
    let declencheur: Declencheur
    let creux: CGFloat
    let crete: CGFloat
    let duree: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: VerreCurseurAnime(valeur: 1), trigger: declencheur) { vue, etat in
                vue.scaleEffect(etat.valeur)
            } keyframes: { _ in
                KeyframeTrack(\.valeur) {
                    MoveKeyframe(1)
                    CubicKeyframe(creux, duration: duree / 3)
                    CubicKeyframe(crete, duration: duree / 3)
                    CubicKeyframe(1, duration: duree / 3)
                }
            }
        }
    }
}

extension View {
    /// Rebond ponctuel au changement de `declencheur`.
    func verrePop<Declencheur: Equatable>(
        _ declencheur: Declencheur,
        creux: CGFloat = 0.75,
        crete: CGFloat = 1.2,
        duree: Double = 0.45
    ) -> some View {
        modifier(VerrePop(declencheur: declencheur, creux: creux, crete: crete, duree: duree))
    }
}
