import SwiftUI

// MARK: - Pressed Button Style
/// Remplace `.buttonStyle(.plain)` partout où on veut un feedback visuel
/// standard iOS-like sur le tap. Scale 0.97 + opacity 0.85 = cohérent
/// avec Apple Music, Fitness, Health.
///
/// Respecte `AccessibilityReduceMotion` : pas de scale si l'utilisateur
/// a activé Reduce Motion (mais opacity reste pour feedback visuel).
///
/// Usage :
/// ```swift
/// Button { action() } label: { ... }
///     .buttonStyle(.healthMapPressed)
/// ```
struct PressedButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scaleFor(isPressed: configuration.isPressed))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private func scaleFor(isPressed: Bool) -> CGFloat {
        if reduceMotion { return 1.0 }
        return isPressed ? 0.97 : 1.0
    }
}

extension ButtonStyle where Self == PressedButtonStyle {
    /// Style standard HealthMap pour tous les CTAs et cards interactives.
    static var healthMapPressed: PressedButtonStyle { PressedButtonStyle() }
}

// MARK: - Card Pressed Style
/// Variante pour les cards entières tap-ables (HighlightCard, navCard).
/// Scale plus subtil (0.98) car la zone est plus grande.
struct CardPressedButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scaleFor(isPressed: configuration.isPressed))
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }

    private func scaleFor(isPressed: Bool) -> CGFloat {
        if reduceMotion { return 1.0 }
        return isPressed ? 0.98 : 1.0
    }
}

extension ButtonStyle where Self == CardPressedButtonStyle {
    /// Pour les cards entières tap-ables — feedback plus subtil que PressedButtonStyle.
    static var healthMapCardPressed: CardPressedButtonStyle { CardPressedButtonStyle() }
}
