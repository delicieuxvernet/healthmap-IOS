import SwiftUI

// MARK: - Health Scale (échelle unique couleur/label — DESIGN-PAGES lois 3 & 4)
//
// SOURCE UNIQUE DE VÉRITÉ de la correspondance score → couleur → mot d'état.
// Anneaux, jauges, pastilles et labels d'état passent tous par ici, soit
// directement, soit via les helpers délégués `Color.scoreColor(for:)` /
// `Color.globalScoreColor(for:)` de `Color+Theme.swift`.
//
// Échelle (loi 3) : score < 45 → rouge · 45-69 → orange · ≥ 70 → vert.
// La couleur n'est JAMAIS utilisée seule : toujours doublée d'un mot d'état
// fixe (loi 4) — `nutrientLabel(for:)` pour un nutriment, `globalLabel(for:)`
// pour le score global.
enum HealthScale {

    // MARK: - Couleur unique (loi 3)

    /// Couleur d'état pour un score 0-100.
    /// Tokens existants de `Color+Theme.swift` uniquement — aucune teinte inventée.
    static func color(for score: Int) -> Color {
        if score < 45 { return .scoreDeficient }   // rouge
        if score < 70 { return .scoreLow }         // orange
        return .scoreExcellent                     // vert
    }

    /// La même échelle pour un TEXTE (chiffre, mot d'état) : les encres
    /// foncées de la palette. Les teintes vives ci-dessus ne tiennent pas
    /// 4,5:1 en texte (orange 2,0:1, vert 2,2:1 ; audit du 9 oct. 2026) ;
    /// elles restent pour les anneaux, jauges et pastilles.
    static func couleurTexte(for score: Int) -> Color {
        if score < 45 { return .dsAComblerTexte }  // rouge foncé #C0322A
        if score < 70 { return .dsARenforcerTexte } // ambre foncé #995600
        return .dsAccent                           // vert forêt #3B6D11
    }

    // MARK: - Labels d'état fixes (loi 4)

    /// Mot d'état d'un NUTRIMENT :
    /// < 45 « À renforcer » · 45-69 « Limite » · ≥ 70 « Solide ».
    static func nutrientLabel(for score: Int) -> String {
        if score < 45 { return "À renforcer" }
        if score < 70 { return "Limite" }
        return "Solide"
    }

    /// Mot d'état du score GLOBAL :
    /// < 45 « Priorité » · 45-69 « À surveiller » · 70-84 « Solide » · ≥ 85 « Optimal ».
    static func globalLabel(for score: Int) -> String {
        if score < 45 { return "Priorité" }
        if score < 70 { return "À surveiller" }
        if score < 85 { return "Solide" }
        return "Optimal"
    }
}
