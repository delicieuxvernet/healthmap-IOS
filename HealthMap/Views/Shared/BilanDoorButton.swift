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
    /// D'où cette porte est tapée — paramètre `zone` de l'événement
    /// `decouverte_cta_bilan` (funnel V12f), émis à CHAQUE tap.
    let zone: BilanDoorZone
    /// Lance (ou reprend) le bilan — `DashboardViewModel.demarrerBilan()`.
    let action: () -> Void

    var body: some View {
        Button {
            HapticService.shared.primary()
            DecouverteFunnel.ctaBilan(zone: zone)
            action()
        } label: {
            // Refonte 23 août 2026 : bouton capsule du DS (50 pt, 17 / 600,
            // aucune ombre, aucune icône décorative).
            Text(title)
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: DS.hauteurBouton)
                .background(Capsule().fill(Color.dsAccent))
                .contentShape(Capsule())
        }
        .buttonStyle(.dsPress)
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
        /// Journal avant questionnaire (refonte 23 août 2026) : la porte de
        /// la carte « On ne connaît pas encore tes besoins ».
        static let journal = "Répondre au questionnaire"
        /// Plan (couronne radiale en mode découverte).
        static let plan = "Construire MON plan · bilan 3 min"
        /// Suivi (sous les carrousels d'exemple).
        static let suivi = "Suivre MES vrais chiffres · bilan 3 min"
        /// Compléments (sous les exemples de chaînes).
        static let complements = "Voir MES compléments · bilan 3 min"
        /// Résultat de scan (V12e : sous les repères adulte moyen).
        static let scan = "Personnaliser MES repères · bilan 3 min"
    }
}

// MARK: - Zones des portes (paramètre `zone` de `decouverte_cta_bilan`)
/// Un cas par emplacement RÉEL d'une `BilanDoorButton` — le rawValue part tel
/// quel en analytics (snake_case, jamais de donnée personnelle ; invariant
/// DecouverteFunnelTests).
enum BilanDoorZone: String, CaseIterable {
    /// Onglet Bilan, carte apports en mode découverte (#217).
    case bilanApports = "bilan_apports"
    /// Onglet Plan, couronne radiale en mode découverte.
    case plan
    /// Onglet Suivi, sous les carrousels d'exemple.
    case suivi
    /// Onglet Compléments, sous les exemples de chaînes.
    case complements
    /// Écran de résultat d'un scan (V12e, seule porte de l'onglet Scan).
    case scanResultat = "scan_resultat"
}
