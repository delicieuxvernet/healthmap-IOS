import Foundation
import SwiftUI

// MARK: - Toast Service (confirmations courtes)
@MainActor
final class ToastService: ObservableObject {
    static let shared = ToastService()

    @Published var currentToast: String?
    @Published var isShowing: Bool = false

    private var dismissTask: Task<Void, Never>?

    private init() {}

    // Les « faits nutriments » et les toasts de motivation (code mort, jamais
    // appelés) sont partis le 9 octobre 2026 : ils portaient des allégations
    // de santé non autorisées (« les oméga-3 réduisent l'inflammation »…).

    /// La séquence animée n'a pas pu être construite (bilan incomplet). On le dit
    /// plutôt que de laisser un bouton sans effet : « rien ne se passe » est le
    /// pire retour qu'une interface puisse donner.
    func showÉchecRecap() {
        show("Ton bilan animé n'est pas disponible pour l'instant.")
    }

    /// Confirmation d'un geste que la personne vient de faire (« Objectifs mis
    /// à jour ») : elle passe même en mode Zen, ce n'est pas une sollicitation.
    func confirmer(_ message: String) {
        show(message)
    }

    // MARK: - Display & Auto-Dismiss
    private func show(_ message: String) {
        currentToast = message
        isShowing = true

        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        isShowing = false
        currentToast = nil
    }
}
