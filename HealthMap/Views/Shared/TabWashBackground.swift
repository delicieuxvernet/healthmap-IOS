import SwiftUI

// MARK: - Lavis de teinte par onglet (décision fondateur, août 2026)
/// Un très léger lavis vertical posé SOUS le contenu de chaque onglet racine,
/// dans l'esprit des fonds thématiques du questionnaire (cf. `sectionBackground`
/// de `QuestionnaireContainerView`) : « visible mais à peine ». La teinte part
/// du haut de l'écran et s'éteint vers les deux tiers — le bas de la page reste
/// sur le crème/fond de base, la barre flottante n'est jamais teintée.
///
/// Teintes par onglet — UNIQUEMENT des couleurs déjà présentes dans la palette
/// (`Color+Theme.swift`), une famille de teinte distincte par onglet :
///   - Bilan       → `healthMapBlue`  (bleu — l'accent historique de l'analyse,
///                                     départ du dégradé de marque)
///   - Suivi       → `macroCarb`      (or — le rythme des jours : matin / midi /
///                                     soir, l'énergie quotidienne)
///   - Scanner     → `macroFat`       (orange — la chaleur de l'assiette, déjà
///                                     la couleur des lipides du scan)
///   - Plan        → `accentIndigo`   (indigo — la projection long terme, fin
///                                     du dégradé de marque)
///   - Compléments → `kiwiGreen`      (décision fondateur)
///
/// Placement : juste APRÈS le fond de base (`WarmBackground()` ou
/// `Color.kiwiCream`) dans le `ZStack` racine de l'onglet, AVANT le contenu.
///
/// `ignoresSafeArea` : le lavis monte sous la barre d'état (fix #208 — un fond
/// qui s'arrête à la status bar laisse une bande « hors de l'app » en haut).
///
/// - Décoratif : `allowsHitTesting(false)` + `accessibilityHidden(true)`.
struct TabWashBackground: View {
    let tint: Color

    /// Opacité de la teinte tout en haut de l'écran — assez pour se sentir,
    /// jamais assez pour concurrencer le contenu (« visible mais à peine »).
    private static let opaciteHaut: Double = 0.09
    /// Fraction de la hauteur d'écran où le lavis est complètement éteint.
    private static let extinction: CGFloat = 0.66

    /// Refonte 23 août 2026 : un seul voile pour tous les onglets, celui de la
    /// marque (`#E9F2E2` vers le transparent sur 240 pt). La teinte par onglet
    /// n'est plus rendue ; le paramètre reste pour les appelants.
    var body: some View {
        DSBrandWash()
    }
}

#Preview {
    ZStack {
        WarmBackground()
        TabWashBackground(tint: .kiwiGreen)
    }
}
