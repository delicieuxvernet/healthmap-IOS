import UIKit

// MARK: - Haptic Service
// Centralized haptic feedback for CTAs, toggles, success states.
// All calls are cheap no-ops on devices without a Taptic Engine.

@MainActor
final class HapticService {
    static let shared = HapticService()

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()
    private let selectionGen = UISelectionFeedbackGenerator()

    private init() {
        // Prepare generators so the first tap has no latency.
        light.prepare()
        medium.prepare()
        heavy.prepare()
        rigid.prepare()
        soft.prepare()
        notification.prepare()
        selectionGen.prepare()
    }

    // MARK: - Public API

    /// Light tap — use for chip toggles, option selections, micro-interactions.
    func selection() {
        selectionGen.selectionChanged()
        selectionGen.prepare()
    }

    /// Soft impact — use for card taps, sheet presentations.
    func tap() {
        soft.impactOccurred()
        soft.prepare()
    }

    /// Medium impact — use for primary CTAs, "Suivant", "Valider", "Lancer l'analyse".
    func primary() {
        medium.impactOccurred()
        medium.prepare()
    }

    /// Heavy impact — use for major actions like "Voir mes résultats" at end of questionnaire.
    func strong() {
        heavy.impactOccurred()
        heavy.prepare()
    }

    /// Success notification — use when analysis finishes, purchase completes, account created.
    func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    /// Warning — use when a form field fails validation or a premium feature is blocked.
    func warning() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    /// Error — use for hard failures (network down, auth failed).
    func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }
}
