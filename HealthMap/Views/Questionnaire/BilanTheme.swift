import SwiftUI
import UIKit

// MARK: - Les couleurs du questionnaire (refonte du 1er octobre 2026)
//
// Une couleur par étape : c'est ce qui dit, sans lire, qu'on a changé de
// chapitre (« plus de couleurs, plus de formes », demande d'Arthur).
//
// Écart ASSUMÉ à la règle du 23 août 2026 (« le vert ne colore que ce qui se
// tape ») : ici la couleur porte un sens, l'étape, comme la couleur d'une jauge
// porte un statut. Ce qui fait avancer reste vert : le bouton du bas ne change
// jamais de couleur.

/// Les trois nuances d'une couleur du questionnaire.
struct TeinteBilan {
    /// La couleur vive : liseré d'une réponse choisie, segment de la barre.
    let vive: Color
    /// Le fond d'une réponse choisie, le halo du haut d'écran.
    let pale: Color
    /// Le texte posé sur le fond pâle.
    let encre: Color

    /// Trois hexadécimaux pour le mode clair. En mode sombre le fond pâle
    /// devient la couleur vive en transparence et l'encre passe au blanc :
    /// un fond pastel clair y serait illisible.
    init(vive: String, pale: String, encre: String) {
        let viveUI = UIColor(Color(hex: vive))
        let paleUI = UIColor(Color(hex: pale))
        let encreUI = UIColor(Color(hex: encre))
        self.vive = Color(hex: vive)
        self.pale = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? viveUI.withAlphaComponent(0.26) : paleUI
        })
        self.encre = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor.white : encreUI
        })
    }

    /// Le vert de la marque : accueil, fin, écrans d'affinage, bons points.
    static let kiwi = TeinteBilan(vive: "5DA838", pale: "EAF3DE", encre: "2F5A0C")

    /// La carte « on vient de l'apprendre ».
    static let information = TeinteBilan(vive: "007AFF", pale: "E5F1FF", encre: "0A4E9E")

    /// La couleur d'un apport, alignée sur `Color.nutrientColor(for:)`.
    static func apport(_ id: NutrientID) -> TeinteBilan {
        switch id {
        case .vitD: return TeinteBilan(vive: "FF9500", pale: "FFF1DC", encre: "8A4B00")
        case .vitB12: return TeinteBilan(vive: "FF3B30", pale: "FFE9E7", encre: "9B1C14")
        case .iron: return TeinteBilan(vive: "AF52DE", pale: "F5E9FB", encre: "6A2496")
        case .magnesium: return TeinteBilan(vive: "5AC8FA", pale: "E3F4FC", encre: "0B5E86")
        case .omega3: return TeinteBilan(vive: "007AFF", pale: "E5F1FF", encre: "0A4E9E")
        case .vitC: return TeinteBilan(vive: "34C759", pale: "E4F7E9", encre: "1B6B30")
        case .calcium: return TeinteBilan(vive: "8E8E93", pale: "EFEFF4", encre: "4A4A4F")
        case .zinc: return TeinteBilan(vive: "FF2D55", pale: "FFE7EC", encre: "A01536")
        case .iodine: return TeinteBilan(vive: "5856D6", pale: "ECECFB", encre: "2F2E8F")
        case .fiber: return TeinteBilan(vive: "A2845E", pale: "F4EDE4", encre: "5E4526")
        }
    }
}

extension EtapeBilan {
    /// La couleur de l'étape.
    var teinte: TeinteBilan {
        switch self {
        case .toi: return TeinteBilan(vive: "007AFF", pale: "E5F1FF", encre: "0A4E9E")
        case .quotidien: return TeinteBilan(vive: "FF9500", pale: "FFF1DC", encre: "8A4B00")
        case .forme: return TeinteBilan(vive: "AF52DE", pale: "F5E9FB", encre: "6A2496")
        case .assiette: return .kiwi
        }
    }
}

extension EcranBilan {
    /// La couleur de l'écran : celle de son étape, le vert de la marque sinon.
    var teinte: TeinteBilan {
        etape?.teinte ?? .kiwi
    }
}

// MARK: - La couleur courante, dans l'environnement

private struct TeinteBilanKey: EnvironmentKey {
    static let defaultValue = TeinteBilan.kiwi
}

extension EnvironmentValues {
    /// La couleur de l'étape en cours. Les composants du questionnaire la
    /// lisent ici plutôt que de la recevoir un par un.
    var teinteBilan: TeinteBilan {
        get { self[TeinteBilanKey.self] }
        set { self[TeinteBilanKey.self] = newValue }
    }
}

// MARK: - La typographie du questionnaire

/// Des styles de texte système, donc Dynamic Type suit partout.
enum BilanTypo {
    /// Titre d'écran.
    static let titre: Font = .system(.title2, design: .default).weight(.bold)
    /// La raison de la question, sous le titre.
    static let pourquoi: Font = .system(.subheadline, design: .default)
    /// Libellé d'un groupe de réponses.
    static let etiquette: Font = .system(.footnote, design: .default).weight(.semibold)
    /// Texte d'une tuile.
    static let tuile: Font = .system(.footnote, design: .default).weight(.semibold)
    /// Texte d'une tuile d'échelle, plus serré.
    static let echelle: Font = .system(.caption, design: .default).weight(.semibold)
    /// L'emoji d'une tuile.
    static let emoji: Font = .system(.title2, design: .default)
    /// La valeur centrale d'une molette.
    static let molette: Font = .system(.title, design: .default).weight(.bold).monospacedDigit()
    /// Les valeurs voisines d'une molette.
    static let moletteVoisine: Font = .system(.subheadline, design: .default).weight(.semibold).monospacedDigit()

    /// Rayon des tuiles et des cartes du questionnaire.
    static let rayon: CGFloat = 16
}
