import SwiftUI

// MARK: - Porte bilan (CTA kiwi partagé)
//
// Le bouton « porte vers le bilan » introduit par le mode découverte du Bilan
// (#217, `BilanV7ApportsTeaserCard`) : patron du bouton primaire du
// questionnaire — aplat kiwi, coins continus, ombre verte douce, sparkles.
// Extrait ici (V12c) pour que Plan, Suivi et Compléments posent la MÊME porte
// sans recopier le style. Aucun style nouveau : chaque cote vient du CTA
// d'origine, validé fondateur (12-13 août).
struct BilanDoorButton: View {
    /// Libellé affiché — passer un `BilanDoorButton.Libelle` (séparateur
    /// médian « · », jamais de tiret cadratin : TypographieTests).
    let title: String
    /// Phrase VoiceOver (virgule, pas de séparateur médian — même décision
    /// typo que les CTA du Bilan).
    let accessibilityText: String
    /// Lance (ou reprend) le bilan — `DashboardViewModel.demarrerBilan()`.
    let action: () -> Void

    var body: some View {
        Button {
            HapticService.shared.primary()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.kiwiGreen)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.kiwiGreen.opacity(0.28), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel(accessibilityText)
    }
}

// MARK: - Libellés canoniques des portes (un par onglet, testables hors UI)
extension BilanDoorButton {
    /// LA source des libellés de porte : chaque onglet consomme le sien, les
    /// tests (invariant « CTA présent, sans tiret cadratin ») s'assert dessus.
    /// Même idiome que « · Esteban » sur le Bilan (décision typo 1er août).
    enum Libelle {
        /// Bilan, zone apports (libellé historique de #217, inchangé).
        static let bilanApports = "Voir MES apports · bilan 3 min"
        /// Plan (couronne radiale en mode découverte).
        static let plan = "Construire MON plan · bilan 3 min"
        /// Suivi (sous les carrousels d'exemple).
        static let suivi = "Suivre MES vrais chiffres · bilan 3 min"
        /// Compléments (sous les exemples de chaînes).
        static let complements = "Voir MES compléments · bilan 3 min"
    }
}
