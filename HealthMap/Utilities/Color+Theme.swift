import SwiftUI
import UIKit

// MARK: - HealthMap Color Palette (tout bleu, jamais de melange vert/bleu)
//
// The brand palette stays identical in light mode. Neutrals (background,
// card, ink, muted, blueLight) are declared as dynamic colors so the app
// feels native in dark mode without requiring an Asset Catalog edit.
extension Color {
    // Primary brand (constant across modes)
    static let healthMapBlue = Color(hex: "007AFF")
    static let healthMapBlueDark = Color(hex: "0056CC")
    static let healthMapBlueLight = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x16/255, green: 0x2A/255, blue: 0x40/255, alpha: 1.0)
            : UIColor(red: 0xE8/255, green: 0xF4/255, blue: 0xFD/255, alpha: 1.0)
    })

    // Backgrounds (dynamic)
    static let healthMapBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x0B/255, green: 0x0B/255, blue: 0x0E/255, alpha: 1.0)
            : UIColor(red: 0xFA/255, green: 0xFA/255, blue: 0xFA/255, alpha: 1.0)
    })
    static let healthMapCard = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x16/255, green: 0x18/255, blue: 0x1C/255, alpha: 1.0)
            : UIColor.white
    })
    static let healthMapCardHover = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x1E/255, green: 0x20/255, blue: 0x24/255, alpha: 1.0)
            : UIColor(red: 0xF5/255, green: 0xF5/255, blue: 0xF5/255, alpha: 1.0)
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

    // Score colors — "tout bleu" palette (4-tier, blue nuances only)
    // Écart de luminosité élargi pour distinguer les 4 tiers en un coup d'œil,
    // tout en restant 100% en palette bleue (respect branding).
    static let scoreExcellent = Color(hex: "00A3FF")   // bleu clair vibrant (très visible)
    static let scoreGood = Color(hex: "0066CC")        // bleu moyen
    static let scoreLow = Color(hex: "003D99")         // bleu foncé
    static let scoreDeficient = Color(hex: "001F66")   // bleu très foncé / marine

    // Nutrient-specific colors — all blue nuances ("tout bleu").
    // Prior version mixed orange/red/purple/green/brown, violating brand.
    static let nutrientVitD = Color(hex: "007AFF")        // primary
    static let nutrientVitB12 = Color(hex: "0056CC")      // dark blue
    static let nutrientIron = Color(hex: "5856D6")        // indigo (blue family)
    static let nutrientMagnesium = Color(hex: "5AC8FA")   // sky blue
    static let nutrientOmega3 = Color(hex: "007AFF")      // primary
    static let nutrientVitC = Color(hex: "64D2FF")        // light sky
    static let nutrientCalcium = Color(hex: "A8C5E8")     // powder blue
    static let nutrientZinc = Color(hex: "4A90E2")        // steel blue
    static let nutrientIodine = Color(hex: "5856D6")      // indigo
    static let nutrientFiber = Color(hex: "6B8EAF")       // dusty blue

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

// MARK: - Score Color Helpers
extension Color {
    static func scoreColor(for score: Int) -> Color {
        if score >= 75 { return .scoreExcellent }
        if score >= 50 { return .scoreGood }
        if score >= 40 { return .scoreLow }
        return .scoreDeficient
    }

    static func globalScoreColor(for score: Int) -> Color {
        // Brand rule: scores >= 60 use the primary brand blue; below that,
        // progressively muted blue/gray nuances signal risk without alarm.
        if score >= 60 { return .healthMapBlue }
        if score >= 40 { return .scoreLow }
        return .scoreDeficient
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
