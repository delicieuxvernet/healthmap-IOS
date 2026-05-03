import SwiftUI

// MARK: - Haptic Feedback
extension View {
    func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        self.onTapGesture {
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }
}

// MARK: - Conditional Modifier
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - iOS Spring Animation (matches Framer Motion spring)
extension Animation {
    static let healthMapSpring = Animation.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0)
    static let healthMapQuick = Animation.spring(response: 0.3, dampingFraction: 0.85, blendDuration: 0)

    /// Returns `.healthMapSpring` when motion is allowed, `nil` otherwise.
    /// Pass `nil` to `withAnimation` to apply the state change immediately.
    static func healthMapSpringOrNone(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .healthMapSpring
    }

    /// Returns `.healthMapQuick` when motion is allowed, `.none` otherwise.
    static func healthMapQuickOrNone(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .healthMapQuick
    }
}

// MARK: - Safe Area Bottom Padding
extension View {
    func safeAreaBottomPadding(_ extra: CGFloat = 0) -> some View {
        self.padding(.bottom, extra)
    }
}
