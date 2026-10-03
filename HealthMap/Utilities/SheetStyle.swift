import SwiftUI

// MARK: - Sheet Style Modifier
/// Applique les styles iOS natifs aux sheets : detents, drag indicator,
/// corner radius. Standardise tous les sheets de l'app sur un look cohérent.
///
/// Usage :
/// ```swift
/// .sheet(isPresented: $showSheet) {
///     MySheetContent()
///         .healthMapSheet(.medium) // medium + large
/// }
/// ```
extension View {
    /// Pour les sheets contenant du contenu riche (NutrientDetail, Paywall).
    /// Supporte medium ET large, drag indicator visible, coins de 38 (verre).
    /// Le FOND de verre se pose à part, avec `.verreFeuille()`, une fois que
    /// le contenu de la feuille ne peint plus d'aplat opaque.
    func healthMapSheet(_ initialDetent: PresentationDetent = .large) -> some View {
        self
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Verre.rayonFeuille)
    }

    /// Pour les sheets d'action courte (ForgotPassword, confirmations).
    /// Medium uniquement, pour laisser le contexte visible derrière.
    func healthMapActionSheet() -> some View {
        self
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Verre.rayonFeuille)
    }

    /// Pour les sheets plein écran (Questionnaire édition, détails critiques).
    /// Large uniquement, drag indicator, corner radius standard.
    func healthMapFullSheet() -> some View {
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Verre.rayonFeuille)
    }

    /// Pour le questionnaire : plein écran, et le glissement vers le bas NE
    /// ferme PAS la feuille. On la quittait par accident, en faisant défiler
    /// une liste ou une molette ; la sortie passe désormais par la croix, qui
    /// confirme. Pas de poignée non plus : elle promettrait un geste qui ne
    /// fait plus rien.
    func healthMapQuestionnaireSheet() -> some View {
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(Verre.rayonFeuille)
            .interactiveDismissDisabled()
    }
}
