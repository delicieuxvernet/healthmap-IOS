import SwiftUI

// MARK: - Accessibility View Modifiers
// Reusable modifiers for VoiceOver announcements and reduced-motion support.

/// Announces a sheet presentation to VoiceOver with a `.screenChanged` notification.
struct AnnounceSheetModifier: ViewModifier {
    let isPresented: Bool
    let announcement: String

    func body(content: Content) -> some View {
        content.onChange(of: isPresented) { _, newValue in
            if newValue {
                UIAccessibility.post(notification: .screenChanged, argument: announcement)
            }
        }
    }
}

/// Conditionally applies an animation based on `accessibilityReduceMotion`.
/// When reduce motion is enabled, the animation is replaced with `.none`
/// so layout changes still apply but skip the visual transition.
struct ReducedMotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .none : animation, value: value)
    }
}

// MARK: - View Convenience Extensions
extension View {
    /// Posts a VoiceOver `.screenChanged` announcement when a sheet appears.
    func announceSheet(isPresented: Bool, _ announcement: String) -> some View {
        modifier(AnnounceSheetModifier(isPresented: isPresented, announcement: announcement))
    }

    /// Applies `animation` only when reduce-motion is OFF. Otherwise uses `.none`.
    func reducedMotionAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReducedMotionModifier(animation: animation, value: value))
    }
}
