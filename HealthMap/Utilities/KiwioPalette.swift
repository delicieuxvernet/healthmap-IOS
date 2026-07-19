import SwiftUI

/// Palette Kiwio — source de vérité des couleurs de l'écran Scan et du vocal.
///
/// Reprise du design validé (`Scan - kcal autonome.html`, juillet 2026) et des
/// instructions associées : **un seul accent, le vert kiwi `#5DA838`**.
///
/// ⚠️ Le bleu `#2F6FE0` est réservé EXCLUSIVEMENT à la pastille macro
/// « Protéines ». Il ne doit apparaître nulle part ailleurs — surtout pas sur un
/// bouton ou une chip. C'est l'erreur qui a été commise au premier portage : le
/// bouton micro et les chips de portions étaient bleus (`healthMapBlue`, le
/// bleu iOS historique de l'app), ce qui diluait l'identité de marque.
///
/// `Color.healthMapBlue` et les autres tokens de `Color+Theme.swift` restent en
/// place pour le reste de l'app ; cette palette-ci ne concerne que le Scan.
enum Kiwio {

    // MARK: - Accent

    /// Vert kiwi — l'unique accent : micro, chips actives, CTA, chiffres en grammes.
    static let vert = Color(hex: "5DA838")
    /// Vert foncé — texte sur fond vert pâle (badges « identifié »).
    static let vertFonce = Color(hex: "3B6D11")
    /// Vert pâle — fond des badges.
    static let vertPale = Color(hex: "EAF3DE")

    // MARK: - Fonds

    /// Fond d'écran crème.
    static let fond = Color(hex: "F7F3EA")
    /// Fond des bottom-sheets (légèrement plus clair).
    static let fondSheet = Color(hex: "FBF6EF")
    /// Cartes blanches.
    static let carte = Color.white

    // MARK: - Texte

    static let encre = Color(hex: "211F1A")
    static let secondaire = Color(hex: "6B7280")
    static let discret = Color(hex: "9CA3AF")

    // MARK: - États

    /// Ambre — « quantité ? », une réponse est attendue.
    static let ambre = Color(hex: "B36B00")
    static let ambreBordure = Color(hex: "FF9500").opacity(0.5)
    static let ambreFond = Color(hex: "FF9500").opacity(0.14)
    /// Rouge — annulation, suppression, surplus de calories.
    static let rouge = Color(hex: "FF3B30")

    // MARK: - Surfaces neutres (style Apple natif)

    /// Fond des contrôles non actifs, search bar, pilule de waveform.
    static let neutre = Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.12)
    static let bordure = Color(hex: "211F1A").opacity(0.08)

    // MARK: - Pastilles macros — SEUL endroit où le bleu est autorisé

    static let proteines = Color(hex: "2F6FE0")
    static let proteinesFond = Color(hex: "2F6FE0").opacity(0.10)
    static let glucides = Color(hex: "B78A00")
    static let glucidesFond = Color(hex: "F2B705").opacity(0.14)
    static let lipides = Color(hex: "D96F00")
    static let lipidesFond = Color(hex: "FB8500").opacity(0.12)
}

extension Font {
    /// Chiffres clés (kcal, grammes, minuteur) en chasse fixe, comme le design.
    /// `monospacedDigit` garde l'alignement quand la valeur change sous les yeux —
    /// sans lui, un total qui passe de 99 à 100 fait sauter toute la ligne.
    static func kiwioMono(_ taille: CGFloat, _ poids: Font.Weight = .semibold) -> Font {
        .system(size: taille, weight: poids, design: .monospaced)
    }
}
