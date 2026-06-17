import SwiftUI
import UIKit

// MARK: - HealthMap Color Palette (palette variée unifiée web ↔ iOS, façon FoodVisor)
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
    static let healthMapBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x11/255, green: 0x14/255, blue: 0x1D/255, alpha: 1.0)
            : UIColor(red: 0xF6/255, green: 0xF8/255, blue: 0xFD/255, alpha: 1.0)
    })
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
    static let healthMapMuted = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x7A/255, green: 0x7A/255, blue: 0x80/255, alpha: 1.0)
            : UIColor(red: 0x9C/255, green: 0xA3/255, blue: 0xAF/255, alpha: 1.0)
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
    static let healthMapGradientStart = Color(hex: "007AFF")
    static let healthMapGradientEnd = Color(hex: "5856D6")

    // Teintes chaudes — fond unifié premium (WarmBackground), remplace le ruban
    // animé retiré. Dynamiques light/dark comme les autres neutres.
    static let healthMapWarm = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x14/255, green: 0x13/255, blue: 0x0F/255, alpha: 1.0)
            : UIColor(red: 0xFB/255, green: 0xF6/255, blue: 0xEF/255, alpha: 1.0)
    })
    static let healthMapWarmGlow = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x3A/255, green: 0x2E/255, blue: 0x1C/255, alpha: 1.0)
            : UIColor(red: 0xFF/255, green: 0xE9/255, blue: 0xCF/255, alpha: 1.0)
    })

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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
