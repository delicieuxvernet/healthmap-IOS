import Foundation

// MARK: - L'âge minimum (audit de conformité du 9 octobre 2026)
//
// Kiwio est réservé aux personnes de 16 ans et plus. C'est l'âge du
// consentement numérique le plus élevé de l'Union européenne (RGPD, art. 8),
// et l'app est vendue dans 175 pays : un seul seuil, le plus protecteur. Les
// conditions d'utilisation et la politique de confidentialité disent la même
// chose.
//
// En dessous, aucune collecte : l'âge n'est pas enregistré, le brouillon du
// questionnaire est effacé du téléphone et le bilan ne peut pas partir.

enum AgeMinimum {
    static let ans = 16

    /// La molette d'âge descend sous le minimum : on doit pouvoir dire son
    /// vrai âge, et l'écran l'explique au lieu de le cacher.
    static let plageMolette: ClosedRange<Int> = 12...100

    static func estAtteint(_ age: Int) -> Bool { age >= ans }

    /// Un âge déjà écrit (brouillon d'avant la mise à jour, profil) qui est
    /// sous le minimum. Un âge vide ou illisible n'est pas jugé ici.
    static func estSousLeMinimum(_ age: String) -> Bool {
        Int(age).map { !estAtteint($0) } ?? false
    }

    /// Ce que l'écran dit à quelqu'un de plus jeune.
    static let message = "Kiwio est réservé aux personnes de 16 ans et plus. Rien de ce que tu as répondu n'est gardé."
}
