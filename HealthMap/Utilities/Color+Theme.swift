import SwiftUI
import UIKit

// MARK: - Kiwio Color Palette (palette variée unifiée web ↔ iOS, façon FoodVisor)
//
// Décision produit (3 mai 2026) : abandon de la règle "tout bleu" pour les
// nutriments et les scores. Chaque nutriment a SA couleur distincte (mémorisation),
// alignée hex-pour-hex sur la constante NUTRIENTS du web (src/lib/health.js).
// Les neutres (background, card, ink, muted, blueLight) restent dynamic
// pour le dark mode.
extension Color {
    // Primary brand (constant across modes)
    static let healthMapBlue = Color(hex: "007AFF")
    static let healthMapBlueDark = Color(hex: "0056CC")
    static let healthMapBlueLight = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x1B/255, green: 0x32/255, blue: 0x52/255, alpha: 1.0)
            : UIColor(red: 0xE8/255, green: 0xF4/255, blue: 0xFD/255, alpha: 1.0)
    })
    /// Remplissage des cartes d'option SÉLECTIONNÉES du questionnaire. Plus
    /// saturé que `healthMapBlueLight` (#E8F4FD trop pâle pour signaler l'état
    /// sélectionné sur le fond chaud) — l'état choisi se lit au premier coup
    /// d'œil. Dynamique light/dark.
    static let healthMapSelectFill = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x21/255, green: 0x40/255, blue: 0x6B/255, alpha: 1.0)
            : UIColor(red: 0xDC/255, green: 0xEB/255, blue: 0xFB/255, alpha: 1.0)
    })

    // Backgrounds (dynamic)
    // Alignés sur l'ambiance lumineuse du site web (radial-gradients bleu/violet
    // sur fond clair, cf. src/pages/Home.jsx) : les neutres prennent une teinte
    // bleutée subtile au lieu du gris/noir pur — l'app paraît moins sombre.
    // Refonte « qualité Apple » (23 août 2026) : le fond devient NEUTRE, le
    // gris groupé des Réglages iOS (`systemGroupedBackground`, #F2F2F7). Le
    // beige code « wellness », le gris système code « instrument fiable ».
    static let healthMapBackground = Color(uiColor: .systemGroupedBackground)
    static let healthMapCard = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x1A/255, green: 0x1E/255, blue: 0x2A/255, alpha: 1.0)
            : UIColor.white
    })
    static let healthMapCardHover = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x23/255, green: 0x2A/255, blue: 0x3B/255, alpha: 1.0)
            : UIColor(red: 0xEE/255, green: 0xF2/255, blue: 0xFA/255, alpha: 1.0)
    })

    // Text (dynamic)
    static let healthMapText = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xF2/255, green: 0xF2/255, blue: 0xF7/255, alpha: 1.0)
            : UIColor(red: 0x1A/255, green: 0x1A/255, blue: 0x1A/255, alpha: 1.0)
    })
    static let healthMapSecondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xAE/255, green: 0xAE/255, blue: 0xB2/255, alpha: 1.0)
            : UIColor(red: 0x6B/255, green: 0x72/255, blue: 0x80/255, alpha: 1.0)
    })
    // Le gris d'habillage. En clair, #9CA3AF ne tient que 2,54:1 sur carte
    // blanche et 2,36:1 sur crème — or c'est la couleur de 17 des 22 usages de
    // `Theme.chromeFont`, un corps de 10,5 pt VOLONTAIREMENT fixe (il ne suit
    // pas Dynamic Type). Un texte qui ne grossit jamais ET qui passe sous
    // 2,6:1 n'est rattrapé par rien. Il prend donc la valeur de
    // `healthMapSecondary` : 4,83:1 sur blanc, 4,50:1 sur crème. Aucune teinte
    // inventée — il n'existe pas de gris plus clair qui tienne le seuil.
    // La variante sombre n'est pas concernée (l'app force `.light`).
    static let healthMapMuted = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x7A/255, green: 0x7A/255, blue: 0x80/255, alpha: 1.0)
            : UIColor(red: 0x6B/255, green: 0x72/255, blue: 0x80/255, alpha: 1.0)
    })

    // Score colors — tokens consommés par l'échelle unique HealthScale
    // (DESIGN-PAGES loi 3 : < 45 rouge, 45-69 orange, >= 70 vert).
    // scoreGood (bleu) reste utilisé comme accent sémantique dans les vues.
    static let scoreExcellent = Color(hex: "34C759")   // vert
    static let scoreGood = Color(hex: "007AFF")        // bleu (accent)
    static let scoreLow = Color(hex: "FF9500")         // orange
    static let scoreDeficient = Color(hex: "FF3B30")   // rouge

    // Nutrient-specific colors — palette variée alignée sur le web (NUTRIENTS dans health.js).
    // Chaque nutriment a SA couleur distincte pour aider la mémorisation utilisateur (façon FoodVisor).
    static let nutrientVitD = Color(hex: "FF9500")        // orange
    static let nutrientVitB12 = Color(hex: "FF3B30")      // rouge
    static let nutrientIron = Color(hex: "AF52DE")        // purple
    static let nutrientMagnesium = Color(hex: "5AC8FA")   // sky
    static let nutrientOmega3 = Color(hex: "007AFF")      // blue
    static let nutrientVitC = Color(hex: "34C759")        // green
    static let nutrientCalcium = Color(hex: "8E8E93")     // gray
    static let nutrientZinc = Color(hex: "FF2D55")        // magenta
    static let nutrientIodine = Color(hex: "5856D6")      // indigo
    static let nutrientFiber = Color(hex: "A2845E")       // brown

    // MARK: - Kiwio accent (vert kiwi) + macros FoodVisor
    // Décision produit 26 juin 2026 : la zone alimentation (écran scan repas)
    // passe en vert kiwi. Tokens additifs, consommés par MealScanView. Le reste
    // de l'app reste sur l'accent bleu pour l'instant (migration progressive).
    static let kiwiGreen = Color(hex: "5DA838")           // accent marque / "couvre un besoin"
    static let kiwiTint = Color(hex: "EAF3DE")            // fond teinté kiwi
    static let kiwiInk = Color(hex: "3B6D11")            // texte sur tint kiwi
    // Macros (façon FoodVisor) — couleurs distinctes, hors sémantique de statut
    // (vert/ambre/rouge portent déjà un sens : couvre / à renforcer / à combler).
    static let macroProtein = Color(hex: "2F6FE0")        // bleu
    static let macroCarb = Color(hex: "F2B705")           // jaune
    static let macroFat = Color(hex: "FB8500")            // orange
    // fibres = kiwiGreen (vert)

    // Urgency — red kept ONLY for genuine medical alerts (Apple HIG alert semantic).
    // "Soon" and "routine" are folded into the blue family.
    static let urgencyImmediate = Color(hex: "FF3B30")    // critical red (medical alert only)
    static let urgencySoon = Color(hex: "5856D6")         // indigo
    static let urgencyRoutine = Color(hex: "007AFF")      // primary blue

    // Generic semantic accents — all blue family ("tout bleu").
    // Use these in place of `.orange`, `.purple`, `.green`, `.yellow` in views.
    static let accentSky = Color(hex: "5AC8FA")           // replaces `.orange`
    static let accentIndigo = Color(hex: "5856D6")        // replaces `.purple`
    static let accentPowder = Color(hex: "A8C5E8")        // soft highlight
    static let accentSteel = Color(hex: "4A90E2")         // secondary blue

    // Brand gradient (miroir du web : BRAND.gradient = linear-gradient(135deg, #007AFF, #5856D6)).
    // Consommer via `LinearGradient.healthMapBrand` pour les CTA / wordmark / badges.
    // Refonte 23 août 2026 : le « dégradé de marque » est le vert Kiwio, uni.
    static let healthMapGradientStart = Color(hex: "5DA838")
    static let healthMapGradientEnd = Color(hex: "5DA838")

    // Teintes chaudes — fond unifié premium (WarmBackground), remplace le ruban
    // animé retiré. Dynamiques light/dark comme les autres neutres.
    // Refonte 23 août 2026 : le crème a disparu. Les deux tokens restent pour
    // les appelants historiques mais valent désormais le fond neutre et le
    // voile de marque (`#E9F2E2`) qui le coiffe sur 240 pt (cf. `KiwiDS`).
    static let healthMapWarm = Color(uiColor: .systemGroupedBackground)
    static let healthMapWarmGlow = Color(hex: "E9F2E2")

    // Mascotte kiwi (MascotView) — couleurs d'illustration, constantes entre modes
    // (comme un asset : la mascotte garde son identité en light et dark).
    static let mascotSkin = Color(hex: "9C7B52")          // peau brune du kiwi
    static let mascotFlesh = Color(hex: "85C440")         // chair verte
    static let mascotFleshLight = Color(hex: "C9E794")    // halo interne de la chair
    static let mascotCore = Color(hex: "F7FBEA")          // cœur pâle (zone du visage)
    static let mascotInk = Color(hex: "2F3B1D")           // pépins + traits du visage
    static let mascotCheek = Color(hex: "FF9BB5")         // joues (à utiliser en faible opacité)

    // Hex initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Brand Gradient
// Équivalent SwiftUI du `linear-gradient(135deg, #007AFF, #5856D6)` du site web.
extension LinearGradient {
    static let healthMapBrand = LinearGradient(
        colors: [.healthMapGradientStart, .healthMapGradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Score Color Helpers
// Échelle unique score → couleur : DÉLÉGUÉE à HealthScale (DESIGN-PAGES loi 3,
// < 45 rouge · 45-69 orange · ≥ 70 vert). Ne pas redéfinir de paliers ici.
extension Color {
    static func scoreColor(for score: Int) -> Color {
        HealthScale.color(for: score)
    }

    static func globalScoreColor(for score: Int) -> Color {
        HealthScale.color(for: score)
    }

    static func nutrientColor(for id: String) -> Color {
        switch id {
        case "vitD": return .nutrientVitD
        case "vitB12": return .nutrientVitB12
        case "iron": return .nutrientIron
        case "magnesium": return .nutrientMagnesium
        case "omega3": return .nutrientOmega3
        case "vitC": return .nutrientVitC
        case "calcium": return .nutrientCalcium
        case "zinc": return .nutrientZinc
        case "iodine": return .nutrientIodine
        case "fiber": return .nutrientFiber
        default: return .healthMapBlue
        }
    }
}

// MARK: - Card Style Modifier
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.healthMapCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - Kiwio « v4 » (refonte 3D — direction validée juin 2026)
//
// Accent vert kiwi promu accent PRINCIPAL des écrans refondus (le bleu
// historique reste pour les écrans pas encore migrés). Fond crème chaud
// (= `healthMapWarm`), cartes blanches arrondies, anneaux pleins, petites
// illustrations 3D (cf. `Fluent3D`). On designe en light.
extension Color {
    // `kiwiGreen` (#5DA838) / `kiwiTint` (#EAF3DE) / `kiwiInk` (#3B6D11, vert
    // « texte sur tint ») vivent déjà dans la palette ci-dessus (écran Scan kiwi) :
    // on ne les redéclare pas, on complète juste le langage v4.

    /// Fond teinté vert doux — cartes/pastilles « couvre un besoin ».
    static let kiwiGreenSoft = Color(hex: "EAF3DE")
    /// Texte vert sur fond teinté (paliers récolte, etc.).
    static let kiwiGreenInk = Color(hex: "3B6D11")
    /// Ex-crème du langage v4 : depuis la refonte du 23 août 2026, c'est le
    /// fond neutre (`systemGroupedBackground`). Le nom reste pour les
    /// appelants ; la valeur, elle, n'est plus crème.
    static let kiwiCream = Color(uiColor: .systemGroupedBackground)
    /// Encre charbon des titres/aplats v4 (distincte de `kiwiInk`, qui est le
    /// vert « texte sur tint »).
    static let kiwiCharcoal = Color(hex: "211F1A")
}

// MARK: - Écrin « analyse personnelle » (teasing premium, variante B — 18 août 2026)
//
// Un contenu réservé au premium ne se présente plus comme un mur gris : il
// prend l'aspect d'un écrin précieux (dégradé très doux violet vers rose pâle,
// filet violet fin). Les violets vifs de la palette restent la source de la
// famille (`accentIndigo` #5856D6, `nutrientIron` #AF52DE) ; on ajoute
// seulement les deux fonds pâles du dégradé et l'encre foncée qui leur répond.
// Teintes additives : aucune couleur existante n'est modifiée.
extension Color {
    /// Haut du dégradé de l'écrin premium (violet très pâle).
    static let premiumTeaseStart = Color(hex: "EEEDFE")
    /// Bas du dégradé de l'écrin premium (rose très pâle).
    static let premiumTeaseEnd = Color(hex: "FBEAF0")
    /// Encre violette foncée de l'écrin : le titre-problème et ses libellés.
    /// Contraste ~9:1 sur le dégradé, donc AA large ET AA texte courant.
    static let premiumTeaseInk = Color(hex: "3A2E8F")
}

extension LinearGradient {
    /// Fond de l'écrin premium (violet pâle vers rose pâle, en diagonale).
    static let premiumTease = LinearGradient(
        colors: [.premiumTeaseStart, .premiumTeaseEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Capsule « PREMIUM » : indigo vers violet, les deux teintes vives déjà
    /// présentes dans la palette.
    static let premiumBadge = LinearGradient(
        colors: [.accentIndigo, .nutrientIron],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Kiwi Card Style
/// Carte blanche posée sur le gris : rayon 14 (Santé / Fitness), AUCUNE ombre,
/// AUCUNE bordure. L'ombre douce sous chaque carte était le marqueur « template
/// web » le plus reconnaissable ; sa suppression est le changement le plus
/// visible de la refonte du 23 août 2026. Le paramètre `radius` reste accepté
/// pour les appelants historiques mais tout le monde est ramené à 14 : un seul
/// rayon de carte dans toute l'app.
struct KiwiCardStyle: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(Color.healthMapCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    /// Carte blanche sans ombre, rayon 14.
    func kiwiCard(radius: CGFloat = 14) -> some View {
        modifier(KiwiCardStyle(radius: radius))
    }
}

// MARK: - Teintes de fond par section du questionnaire (6 juil. 2026)
//
// Chaque section du questionnaire porte un lavis de fond TRÈS doux (haut de
// l'écran, fondu vers le crème) pour rendre le parcours plus vivant sans
// surcharger. Désaturées ; dynamiques light/dark (en dark : un simple soupçon
// de teinte sur le fond sombre). L'accent vert kiwi reste la SEULE couleur
// « active » (barre de progression + CTA) — la teinte n'est qu'une ambiance.
extension Color {
    private static func sectionTint(
        light: (UInt8, UInt8, UInt8),
        dark: (UInt8, UInt8, UInt8)
    ) -> Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat(c.0) / 255,
                green: CGFloat(c.1) / 255,
                blue: CGFloat(c.2) / 255,
                alpha: 1
            )
        })
    }

    // Teintes recalees + saturees (6 juil. 2026) pour etre nettement visibles
    // sur le creme : or / bleu / rose / vert / orange / teal.
    static let sectionTintGold  = sectionTint(light: (0xF7, 0xDF, 0xA8), dark: (0x2E, 0x26, 0x12)) // Profil (or ambre)
    static let sectionTintBlue  = sectionTint(light: (0xC6, 0xDD, 0xF4), dark: (0x17, 0x26, 0x3A)) // Mode de vie (bleu)
    static let sectionTintRose  = sectionTint(light: (0xF7, 0xCB, 0xD2), dark: (0x30, 0x1B, 0x20)) // Sante (rose)
    static let sectionTintGreen = sectionTint(light: (0xD3, 0xEA, 0xB2), dark: (0x1F, 0x2A, 0x14)) // Nutrition (vert)
    static let sectionTintCoral = sectionTint(light: (0xFB, 0xCD, 0xB4), dark: (0x33, 0x1E, 0x13)) // Symptomes (orange)
    static let sectionTintTeal  = sectionTint(light: (0xBF, 0xE6, 0xD9), dark: (0x14, 0x27, 0x1F)) // Medical (teal)
}
