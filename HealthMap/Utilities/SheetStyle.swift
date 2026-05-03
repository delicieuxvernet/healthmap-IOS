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
    /// Supporte medium ET large, drag indicator visible, corner radius 28.
    func healthMapSheet(_ initialDetent: PresentationDetent = .large) -> some View {
        self
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
    }

    /// Pour les sheets d'action courte (ForgotPassword, confirmations).
    /// Medium uniquement, pour laisser le contexte visible derrière.
    func healthMapActionSheet() -> some View {
        self
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
    }

    /// Pour les sheets plein écran (Questionnaire édition, détails critiques).
    /// Large uniquement, drag indicator, corner radius standard.
    func healthMapFullSheet() -> some View {
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
    }
}
