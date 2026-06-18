import SwiftUI

// MARK: - iOS Spring Animation (matches Framer Motion spring)
extension Animation {
    static let healthMapSpring = Animation.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0)
    static let healthMapQuick = Animation.spring(response: 0.3, dampingFraction: 0.85, blendDuration: 0)
}
