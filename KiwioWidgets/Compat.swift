import SwiftUI
import UIKit

// MARK: - Ce dont `KiwiSigne.swift` a besoin, hors de l'app
//
// Le signe Kiwio est dessiné par le MÊME fichier que dans l'app
// (`HealthMap/Views/Shared/KiwiSigne.swift`, ajouté aux sources de l'extension) :
// un seul logo, partout. Il s'appuie sur trois choses que l'app définit dans
// ses propres fichiers de thème ; l'extension n'embarque pas ce thème, elle en
// fournit ici le strict nécessaire.

extension Color {
    /// Même lecture que `Color(hex:)` de l'app (`Color+Theme.swift`).
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

    static let dsTexte = Color.primary
    static let dsTertiaire = Color.secondary.opacity(0.6)
    static let dsFond = Color(uiColor: .systemGroupedBackground)
}
