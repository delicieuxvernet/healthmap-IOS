import SwiftUI

// MARK: - Theme Constants
enum Theme {
    // Spacing
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32
    static let spacingXXL: CGFloat = 48

    // Corner Radius
    static let cornerRadius: CGFloat = 16
    static let cornerRadiusSM: CGFloat = 10
    static let cornerRadiusLG: CGFloat = 20
    static let cornerRadiusPill: CGFloat = 100

    // Card
    static let cardPadding: CGFloat = 16
    static let cardShadowRadius: CGFloat = 8
    static let cardShadowOpacity: Double = 0.04

    // Font Styles — utilisent les semantic text styles pour respecter Dynamic Type
    // (l'utilisateur peut augmenter la taille système via Réglages → Accessibilité).
    // Design `.rounded` préservé pour cohérence visuelle brand.
    static let titleFont: Font = .system(.title, design: .rounded).weight(.bold)
    static let headlineFont: Font = .system(.headline, design: .rounded).weight(.semibold)
    static let subheadlineFont: Font = .system(.subheadline, design: .rounded).weight(.medium)
    static let bodyFont: Font = .system(.body)
    static let captionFont: Font = .system(.caption)
    static let captionBoldFont: Font = .system(.caption).weight(.semibold)

    // Pill style
    static let pillPaddingH: CGFloat = 12
    static let pillPaddingV: CGFloat = 6
    static let pillCornerRadius: CGFloat = 20

    // Typography kerning (matches web `letter-spacing: -0.02em`)
    static let titleTracking: CGFloat = -0.5
    static let headlineTracking: CGFloat = -0.3
    static let bodyTracking: CGFloat = 0

    // Standardized opacities
    static let opacitySubtle: Double = 0.04
    static let opacityLight: Double = 0.08
    static let opacityMedium: Double = 0.12
    static let opacityStrong: Double = 0.15
    static let opacityOverlay: Double = 0.25

    // Standardized shadows
    static let shadowCard = (opacity: 0.04, radius: CGFloat(8), y: CGFloat(2))
    static let shadowElevated = (opacity: 0.08, radius: CGFloat(12), y: CGFloat(4))
    static let shadowFloating = (opacity: 0.15, radius: CGFloat(20), y: CGFloat(10))
}

// MARK: - Brand Title Modifier
// Applies the web's `-0.02em` letter-spacing on titles and headlines.
struct BrandTitle: ViewModifier {
    let tracking: CGFloat
    func body(content: Content) -> some View {
        content.tracking(tracking)
    }
}

extension View {
    /// Apply the brand title tracking (-0.5pt) for h1/page titles.
    func brandTitleKerning() -> some View {
        modifier(BrandTitle(tracking: Theme.titleTracking))
    }

    /// Apply the brand headline tracking (-0.3pt) for section headers.
    func brandHeadlineKerning() -> some View {
        modifier(BrandTitle(tracking: Theme.headlineTracking))
    }
}

// MARK: - Pill Modifier
struct PillStyle: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(Theme.captionBoldFont)
            .foregroundStyle(color)
            .padding(.horizontal, Theme.pillPaddingH)
            .padding(.vertical, Theme.pillPaddingV)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

extension View {
    func pillStyle(color: Color) -> some View {
        modifier(PillStyle(color: color))
    }
}
