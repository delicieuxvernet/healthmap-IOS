import SwiftUI
import UIKit
import WidgetKit
import AppIntents

// MARK: - Le verre des widgets (maquette « Kiwio - Widgets », 3 oct. 2026)
//
// Compilé dans l'app ET dans l'extension : l'extension pose ces briques dans
// ses widgets, l'app s'en sert pour les aperçus des Réglages et pour rendre les
// widgets en image dans les tests (la seule preuve visuelle sans appareil).
// Aucune brique ne lit de données : on leur passe ce qu'elles dessinent.
//
// Le verre de la maquette est posé sur un fond d'écran coloré : texte blanc,
// plaques blanches translucides, boutons verts. Un widget ne voit pas le fond
// d'écran (pas de flou possible) : en couleurs pleines, `FondVerreW` peint la
// base verte de la maquette puis le verre par-dessus. Dans les présentations
// Teinté et Transparent (iOS 18, iOS 26), iOS retire ce fond et pose son
// propre verre ; les briques passent alors en blanc translucide
// (`widgetRenderingMode`), et les illustrations gardent leurs couleurs.
//
// Les couleurs des apports et des repas sont celles de la maquette : des
// teintes claires, faites pour se lire sur le verre. Elles ne remplacent pas
// la palette de l'app (`KiwiVerre.swift`), qui est faite pour un fond clair.
//
// Les encres s'écrivent toujours avec une couleur explicite (`Color.white`) :
// dans un `Link` ou un `Button`, `.primary` prendrait le bleu des liens.

// MARK: - Couleurs

enum TeinteW {
    /// Vert Kiwio (`teinteKiwi`).
    static let vert = Color(hex: "5DA838")
    /// Haut du dégradé des boutons verts de la maquette.
    static let vertClair = Color(hex: "96E26C")
    /// Calories restantes, anneau du jour, Dynamic Island.
    static let kcal = Color(hex: "FFB547")
    /// Au-dessus du budget du jour.
    static let depasse = Color(hex: "FF8F80")

    /// Teinte d'un apport sur le verre. Vitamine D, magnésium et fer viennent
    /// de la maquette ; les sept autres en sont dérivées (même clarté), pour
    /// qu'aucune ne se confonde avec une voisine.
    static func apport(_ id: String) -> Color {
        switch id {
        case "vitD": return Color(hex: "FFB547")
        case "magnesium": return Color(hex: "AFAEFF")
        case "iron": return Color(hex: "F0B27A")
        case "vitB12": return Color(hex: "FF8F8F")
        case "omega3": return Color(hex: "8CC8FF")
        case "vitC": return Color(hex: "FFD66B")
        case "calcium": return Color(hex: "E6E6EB")
        case "zinc": return Color(hex: "FF9FD0")
        case "iodine": return Color(hex: "7FDCCB")
        case "fiber": return Color(hex: "A6E07A")
        default: return Color.white
        }
    }

    /// Teinte d'un repas dans la barre de la journée (maquette W7).
    static func creneau(_ creneau: CreneauWidget) -> Color {
        switch creneau {
        case .breakfast: return Color(hex: "FFB547")
        case .lunch: return Color(hex: "8FDB62")
        case .dinner: return Color(hex: "AFAEFF")
        case .snack: return Color(hex: "FF8FB1")
        }
    }

    /// L'eau qui remplit le verre : du haut vers le bas.
    static let eauHaut = Color(red: 150 / 255, green: 226 / 255, blue: 255 / 255).opacity(0.95)
    static let eauBas = Color(red: 60 / 255, green: 170 / 255, blue: 240 / 255).opacity(0.9)
    static let eauSurface = Color(red: 200 / 255, green: 240 / 255, blue: 255 / 255).opacity(0.95)

    /// Piste des anneaux.
    static let piste = Color.white.opacity(0.22)
    /// Piste des barres (grand format).
    static let pisteBarre = Color.white.opacity(0.2)
    /// Piste de la barre de la journée.
    static let pisteJournee = Color.white.opacity(0.18)
    /// Filet entre deux blocs.
    static let separateur = Color.white.opacity(0.25)

    /// Le texte blanc, à l'opacité de la maquette : 0,9 en-têtes, 0,88 sous
    /// les anneaux, 0,85 phrases secondaires, 0,82 sous-titres, 0,8 légendes,
    /// 0,75 précisions, 0,7 « Prochain : … ».
    static func encre(_ opacite: Double = 1) -> Color { Color.white.opacity(opacite) }
}

extension Font {
    /// Les chiffres de la maquette : SF Pro Rounded gras, à chasse tabulaire
    /// (comme les chiffres héros du Journal).
    static func chiffreW(_ taille: CGFloat) -> Font {
        .system(size: taille, weight: .bold, design: .rounded).monospacedDigit()
    }

    /// Le texte de la maquette : SF Pro.
    static func texteW(_ taille: CGFloat, _ graisse: Font.Weight = .regular) -> Font {
        .system(size: taille, weight: graisse)
    }
}

// MARK: - Fonds

/// Le fond d'un widget d'accueil (`containerBackground`). La base reprend la
/// teinte du fond d'écran de la maquette sous le verre (vert clair en haut à
/// gauche, vert sarcelle en bas à droite) ; le verre se dessine par-dessus.
struct FondVerreW: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "79BE5D"), Color(hex: "3F9C63"), Color(hex: "2C8270")],
                startPoint: UnitPoint(x: 0.1, y: 0),
                endPoint: UnitPoint(x: 0.9, y: 1)
            )
            RadialGradient(colors: [Color(hex: "A9DB78").opacity(0.5), Color.clear],
                           center: .topLeading, startRadius: 0, endRadius: 240)
            // Le verre : blanc 26 % → 8 % → 14 %, à 155°.
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.26), location: 0),
                    .init(color: Color.white.opacity(0.08), location: 0.6),
                    .init(color: Color.white.opacity(0.14), location: 1),
                ],
                startPoint: UnitPoint(x: 0.29, y: 0.05),
                endPoint: UnitPoint(x: 0.71, y: 0.95)
            )
            // Reflet haut, liseré, reflet bas.
            ContainerRelativeShape()
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.3), Color.white.opacity(0.14)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8
                )
        }
    }
}

/// Le fond de la carte de l'activité en direct : verre sombre (maquette W7).
enum FondActiviteW {
    static let teinte = Color(red: 26 / 255, green: 36 / 255, blue: 28 / 255).opacity(0.62)
}

// MARK: - Matières : bouton vert, pastille pâle

/// Le bouton vert (« G ») et la pastille de verre pâle (« P ») de la maquette,
/// dans la forme qu'on leur donne. Hors des couleurs pleines (Teinté,
/// Transparent), un voile blanc : iOS recolore tout, un dégradé n'y aurait
/// plus de sens.
private struct MatiereW<Forme: InsettableShape>: ViewModifier {
    @Environment(\.widgetRenderingMode) private var rendu
    let forme: Forme
    let verte: Bool
    let ombre: Bool

    func body(content: Content) -> some View {
        content.background {
            if rendu == .fullColor {
                if verte {
                    forme
                        .fill(LinearGradient(colors: [Color(red: 150 / 255, green: 226 / 255, blue: 108 / 255).opacity(0.95),
                                                      Color(red: 93 / 255, green: 168 / 255, blue: 56 / 255).opacity(0.92)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(
                            forme.strokeBorder(
                                LinearGradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.3)],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 0.8)
                        )
                        .shadow(color: Color(red: 30 / 255, green: 80 / 255, blue: 10 / 255).opacity(ombre ? 0.45 : 0),
                                radius: 4, x: 0, y: 5)
                } else {
                    forme
                        .fill(LinearGradient(colors: [Color.white.opacity(0.30), Color.white.opacity(0.12)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(
                            forme.strokeBorder(
                                LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.3)],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 0.6)
                        )
                }
            } else {
                forme.fill(Color.white.opacity(verte ? 0.3 : 0.16))
            }
        }
    }
}

extension View {
    /// Fond du bouton vert de la maquette (Voir le calcul, + 25 cl, C'est
    /// fait, Dicter…). `ombre: false` pour les petits boutons ronds.
    func boutonVertW<Forme: InsettableShape>(_ forme: Forme, ombre: Bool = true) -> some View {
        modifier(MatiereW(forme: forme, verte: true, ombre: ombre))
    }

    /// Fond de la pastille de verre pâle (tuiles, aliments, état « fait »).
    func pastillePaleW<Forme: InsettableShape>(_ forme: Forme) -> some View {
        modifier(MatiereW(forme: forme, verte: false, ombre: false))
    }

    /// Le bouton vert, ou la pastille pâle une fois le geste fait (rituel,
    /// conseil) : la maquette passe de l'un à l'autre.
    func boutonW<Forme: InsettableShape>(_ forme: Forme, fait: Bool, ombre: Bool = true) -> some View {
        modifier(MatiereW(forme: forme, verte: !fait, ombre: ombre))
    }
}

// MARK: - Anneaux et barres

/// Un anneau de la maquette : départ en haut, sens horaire, extrémités nettes,
/// piste blanche à 22 %. `diametre` est le diamètre extérieur.
struct AnneauW<Centre: View>: View {
    let fraction: Double
    let couleur: Color
    let diametre: CGFloat
    let trait: CGFloat
    var piste: Color = TeinteW.piste
    @ViewBuilder var centre: () -> Centre

    var body: some View {
        ZStack {
            Circle().stroke(piste, lineWidth: trait)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, fraction))))
                .stroke(couleur, style: StrokeStyle(lineWidth: trait, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            centre()
        }
        .padding(trait / 2)
        .frame(width: diametre, height: diametre)
        .accessibilityHidden(true)
    }
}

extension AnneauW where Centre == EmptyView {
    init(fraction: Double, couleur: Color, diametre: CGFloat, trait: CGFloat, piste: Color = TeinteW.piste) {
        self.init(fraction: fraction, couleur: couleur, diametre: diametre, trait: trait, piste: piste) { EmptyView() }
    }
}

/// Une barre horizontale (rayon = hauteur / 2), sans animation.
struct BarreW: View {
    let fraction: Double
    let couleur: Color
    var hauteur: CGFloat = 6
    var piste: Color = TeinteW.pisteBarre

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(piste)
                Capsule()
                    .fill(couleur)
                    .frame(width: max(fraction > 0 ? hauteur : 0, geo.size.width * CGFloat(min(1, max(0, fraction)))))
                    .widgetAccentable()
            }
        }
        .frame(height: hauteur)
        .accessibilityHidden(true)
    }
}

// MARK: - Illustrations et en-têtes

/// Une illustration 3D (`fluent_…`). Le nom doit exister dans les deux
/// catalogues (`HealthMap/Resources/Assets.xcassets` et
/// `KiwioWidgets/Illustrations.xcassets`) ; un nom inconnu retombe sur
/// l'étincelle plutôt que sur un vide. Elle garde ses couleurs en Teinté.
struct IllustrationW: View {
    let nom: String
    let taille: CGFloat

    /// « fish » (liste fermée du bilan) ou « fluent_fish » → l'imageset.
    static func resoudre(_ nom: String) -> String {
        let complet = nom.hasPrefix("fluent_") ? nom : "fluent_" + nom
        return UIImage(named: complet) != nil ? complet : "fluent_sparkles"
    }

    var body: some View {
        image
            .frame(width: taille, height: taille)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var image: some View {
        let base = Image(Self.resoudre(nom)).resizable()
        if #available(iOS 18.0, *) {
            base.widgetAccentedRenderingMode(.fullColor).scaledToFit()
        } else {
            base.scaledToFit()
        }
    }
}

/// Le signe Kiwio en tête de widget : en couleurs, ou d'une seule encre hors
/// des couleurs pleines.
struct SigneW: View {
    @Environment(\.widgetRenderingMode) private var rendu
    var taille: CGFloat = 16

    var body: some View {
        Group {
            if rendu == .fullColor {
                KiwiSigne(taille: taille)
            } else {
                KiwiSigne(taille: taille, variante: .mono, encre: Color.white)
                    .widgetAccentable()
            }
        }
        .accessibilityHidden(true)
    }
}

/// La ligne d'en-tête des widgets d'accueil : icône 16, libellé 13/600 à
/// 0,9, et un élément optionnel à droite. Hauteur 18.
struct EnTeteW<Droite: View>: View {
    enum Icone {
        case signe
        case illustration(String)
        case symbole(String)
    }

    let icone: Icone
    let titre: String
    @ViewBuilder var droite: () -> Droite

    var body: some View {
        HStack(spacing: 6) {
            switch icone {
            case .signe:
                SigneW(taille: 16)
            case .illustration(let nom):
                IllustrationW(nom: nom, taille: 16)
            case .symbole(let nom):
                Image(systemName: nom)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TeinteW.encre(0.9))
                    .accessibilityHidden(true)
            }
            Text(titre)
                .font(.texteW(13, .semibold))
                .foregroundStyle(TeinteW.encre(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            droite()
        }
        .frame(height: 18)
    }
}

extension EnTeteW where Droite == EmptyView {
    init(icone: Icone, titre: String) {
        self.init(icone: icone, titre: titre) { EmptyView() }
    }
}

/// La série de jours : flamme 3D + chiffre ; rien quand elle vaut zéro.
struct SerieW: View {
    let serie: Int
    var taille: CGFloat = 13

    var body: some View {
        if serie > 0 {
            HStack(spacing: 2) {
                IllustrationW(nom: "fluent_fire", taille: taille + 1)
                Text("\(serie)")
                    .font(.chiffreW(taille))
                    .foregroundStyle(TeinteW.encre())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Série : \(serie) \(serie > 1 ? "jours" : "jour")")
        }
    }
}

/// Personne de connecté, l'app n'a encore rien écrit, ou pas encore de bilan.
struct InvitationW: View {
    var message = "Ouvre Kiwio pour commencer ta journée."

    var body: some View {
        VStack(spacing: 8) {
            SigneW(taille: 30)
            Text(message)
                .font(.texteW(13, .medium))
                .foregroundStyle(TeinteW.encre(0.88))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Un état est exploitable quand quelqu'un est connecté.
func exploitableW(_ etat: InstantaneJour?) -> InstantaneJour? {
    guard let etat, etat.connecte else { return nil }
    return etat
}

// MARK: - Mise en forme

enum FormatW {
    /// `1 021` : milliers séparés d'une espace fine insécable (comme `DS.entier`).
    static func entier(_ valeur: Int) -> String {
        let chiffres = Array(String(abs(valeur)))
        var groupes: [String] = []
        var fin = chiffres.count
        while fin > 0 {
            let debut = max(0, fin - 3)
            groupes.insert(String(chiffres[debut..<fin]), at: 0)
            fin = debut
        }
        return (valeur < 0 ? "-" : "") + groupes.joined(separator: "\u{202F}")
    }

    /// « 860 kcal restantes », « 120 kcal au-dessus », « 1 240 kcal » sans objectif.
    static func ligneCalories(_ etat: InstantaneJour) -> (nombre: String, legende: String) {
        guard let restantes = etat.kcalRestantes else {
            return (entier(etat.kcalConsommees), "kcal aujourd'hui")
        }
        return (entier(abs(restantes)), restantes < 0 ? "kcal au-dessus" : "kcal restantes")
    }

    /// Part du budget consommée, bornée à 0...1 ; 0 sans objectif.
    static func fractionCalories(_ etat: InstantaneJour) -> Double {
        guard let objectif = etat.kcalObjectif, objectif > 0 else { return 0 }
        return min(1, max(0, Double(etat.kcalConsommees) / Double(objectif)))
    }

    /// « 82% » de l'anneau du jour : tronqué, comme la maquette (2027 / 2455 →
    /// 82 %). `nil` sans objectif.
    static func pourcentCalories(_ etat: InstantaneJour) -> Int? {
        guard let objectif = etat.kcalObjectif, objectif > 0 else { return nil }
        return min(999, max(0, etat.kcalConsommees * 100 / objectif))
    }

    /// `0,75` · `2` · `1,5` : des litres, à partir de centilitres (virgule
    /// décimale, sans zéro inutile). Même écriture que la carte Eau du Journal.
    static func litres(centilitres: Int) -> String {
        let entiers = centilitres / 100
        let reste = centilitres % 100
        if reste == 0 { return "\(entiers)" }
        if reste % 10 == 0 { return "\(entiers),\(reste / 10)" }
        return "\(entiers)," + String(format: "%02d", reste)
    }

    /// Litres bus aujourd'hui et objectif du jour.
    static func litresBus(_ eau: InstantaneJour.Eau) -> String {
        litres(centilitres: eau.verres * eau.centilitres)
    }

    static func litresObjectif(_ eau: InstantaneJour.Eau) -> String {
        litres(centilitres: eau.objectif * eau.centilitres)
    }

    /// Noms des compléments d'un moment, sans dose : « Fer + Vitamine D ».
    static func noms(_ prises: [InstantaneJour.Prise]) -> String {
        prises.map(\.nom).joined(separator: " + ")
    }

    /// « +5 Vit. D » : le badge du petit conseil ; `nil` sans point à annoncer.
    static func badgePoints(_ conseil: ConseilW) -> String? {
        conseil.points > 0 ? "+\(conseil.points) \(conseil.apportCourt)" : nil
    }
}
