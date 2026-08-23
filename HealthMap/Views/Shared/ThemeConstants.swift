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
    // Refonte 23 août 2026 : un seul rayon de carte (14), les petits
    // contrôles à 10.
    static let cornerRadius: CGFloat = 14
    static let cornerRadiusSM: CGFloat = 10
    static let cornerRadiusLG: CGFloat = 14
    static let cornerRadiusPill: CGFloat = 100

    // Card
    static let cardPadding: CGFloat = 16
    // Refonte 23 août 2026 : les cartes n'ont plus d'ombre. Les deux tokens
    // restent pour les appelants, à zéro.
    static let cardShadowRadius: CGFloat = 0
    static let cardShadowOpacity: Double = 0

    // Font Styles — utilisent les semantic text styles pour respecter Dynamic Type
    // (l'utilisateur peut augmenter la taille système via Réglages → Accessibilité).
    // Design `.rounded` préservé pour cohérence visuelle brand.
    // Refonte 23 août 2026 : SF Pro standard partout (plus de `.rounded`).
    static let titleFont: Font = .system(.title, design: .default).weight(.bold)
    static let headlineFont: Font = .system(.headline, design: .default).weight(.semibold)
    static let subheadlineFont: Font = .system(.subheadline, design: .default).weight(.medium)
    static let bodyFont: Font = .system(.body)
    static let captionFont: Font = .system(.caption)
    static let captionBoldFont: Font = .system(.caption).weight(.semibold)

    // MARK: Polices de rôle (charte de hiérarchie de l'information, 17 août 2026)
    //
    // Les 6 polices ci-dessus décrivent une TAILLE ; celles-ci décrivent un
    // RÔLE. Tout texte de l'app est l'un de ces rôles : titre, donnée-héros,
    // conclusion, donnée secondaire / habillage, action. Le rôle choisit le
    // token, le token choisit le style : c'est ce qui rend la hiérarchie
    // vérifiable (`grep '.system(size:'` doit rester marginal dans les vues).
    //
    // Échelle cible, 8 tailles : 10.5 · 11.5 · 12 · 13 · 15 · 17 · 20 · 28.
    // Six d'entre elles tombent exactement sur un text style iOS à la taille
    // système par défaut (title 28, title3 20, body 17, subheadline 15,
    // footnote 13, caption 12) : on les exprime donc en style relatif, ce qui
    // conserve Dynamic Type comme les tokens historiques. Les deux plus
    // petites (11.5 et 10.5) passent sous caption2 (11) : aucun text style ne
    // les porte, elles sont donc déclarées en taille fixe.
    //
    // Le token ne porte QUE la police. La couleur (encre du domaine, encre du
    // statut) et le tracking restent à la charge de l'appelant : voir les
    // constantes de tracking plus bas et la grille rôle → style de
    // `docs/DESIGN-SYSTEM.md`.

    /// Titre d'écran : le nom de l'onglet, une fois par page.
    /// 28 / bold · encre neutre · `screenTitleTracking`.
    /// Refonte 23 août 2026 : gras plafonné à 700 (aucun écran système ne
    /// dépasse le bold) et SF Pro standard (le `.rounded` a sauté).
    static let screenTitleFont: Font = .system(.title, design: .default).weight(.bold)

    /// Titre de sheet : l'en-tête d'une feuille ouverte par un tap.
    /// 20 / bold · `kiwiCharcoal`.
    static let sheetTitleFont: Font = .system(.title3).weight(.bold)

    /// Titre de section : il annonce, il ne rivalise jamais avec le contenu.
    /// 13 / bold · COULEUR DU DOMAINE, jamais l'encre neutre (règle 1).
    static let sectionLabelFont: Font = .system(.footnote).weight(.bold)

    /// Sous-label discret : la précision qui accompagne un titre de section.
    /// 11.5 / bold · encre pâle (`healthMapSecondary` ou `healthMapMuted`).
    static let subLabelFont: Font = .system(size: 11.5, weight: .bold)

    /// Conclusion : ce que les données veulent dire, le pic de sa carte.
    /// 17 / semibold · encre la plus foncée · `conclusionTracking` · JAMAIS de
    /// `lineLimit` (règle 2 : aucun texte de la carte ne doit la dépasser).
    /// Refonte 23 août 2026 : c'est le `headline` iOS (17 / 600).
    static let conclusionFont: Font = .system(.body).weight(.semibold)

    /// Conclusion secondaire : le verdict d'une ligne, d'une courbe, d'un item.
    /// 15 / semibold · encre foncée.
    static let insightFont: Font = .system(.subheadline).weight(.semibold)

    /// Donnée-héros chiffrée d'une carte : LE chiffre que la carte existe pour
    /// montrer. 28 / bold / rounded / chiffres à chasse fixe · encre du statut.
    static let heroValueFont: Font = .system(.title, design: .default)
        .weight(.bold)
        .monospacedDigit()

    /// Donnée-héros chiffrée d'une ligne de liste. 15 / heavy / rounded /
    /// chiffres à chasse fixe. Plancher absolu : une donnée-héros ne descend
    /// jamais sous 15 pt (règle 3).
    static let heroValueRowFont: Font = .system(.subheadline, design: .default)
        .weight(.bold)
        .monospacedDigit()

    /// Donnée-héros textuelle : l'aliment, le produit, le geste recommandé.
    /// 17 / semibold · `kiwiCharcoal`. Elle porte la plus grande taille ET
    /// l'encre la plus foncée de son bloc.
    static let heroTextFont: Font = .system(.body).weight(.semibold)

    /// Donnée secondaire : libellé, dose, quantité qui complète le héros sans
    /// lui disputer la place. 12 / medium · `healthMapSecondary`.
    static let dataSecondaryFont: Font = .system(.caption).weight(.medium)

    /// Habillage : unité, date, mention, note de bas de carte.
    /// 10.5 / medium · `healthMapMuted`. Jamais de fond coloré si la
    /// donnée-héros du même bloc n'en porte pas.
    static let chromeFont: Font = .system(size: 10.5, weight: .medium)

    /// CTA primaire : un seul par carte, 15 / semibold, blanc sur `kiwiGreen`,
    /// hauteur 48, sans ombre. Un CTA n'est jamais plus lourd que ce qu'il sert.
    static let ctaFont: Font = .system(.subheadline).weight(.semibold)

    // MARK: Fin des polices de rôle

    // Pill style
    static let pillPaddingH: CGFloat = 12
    static let pillPaddingV: CGFloat = 6
    static let pillCornerRadius: CGFloat = 20

    // Typography kerning (matches web `letter-spacing: -0.02em`)
    static let titleTracking: CGFloat = -0.5
    static let headlineTracking: CGFloat = -0.3
    static let bodyTracking: CGFloat = 0
    // Tracking des polices de rôle (charte de hiérarchie) : le titre d'écran se
    // resserre franchement, la conclusion juste assez pour tenir sur sa carte.
    static let screenTitleTracking: CGFloat = -0.7
    static let conclusionTracking: CGFloat = -0.35

    // Standardized opacities
    static let opacitySubtle: Double = 0.04
    static let opacityLight: Double = 0.08
    static let opacityMedium: Double = 0.12
    static let opacityStrong: Double = 0.15
    static let opacityOverlay: Double = 0.25

    // Standardized shadows
    // Refonte 23 août 2026 : aucune ombre sur les cartes. Les tokens restent
    // pour les appelants, à zéro.
    static let shadowCard = (opacity: 0.0, radius: CGFloat(0), y: CGFloat(0))
    static let shadowElevated = (opacity: 0.0, radius: CGFloat(0), y: CGFloat(0))
    static let shadowFloating = (opacity: 0.0, radius: CGFloat(0), y: CGFloat(0))
    // Ombre teintée bleue des CTA brand (miroir du web BRAND.shadow :
    // `0 4px 24px rgba(0,122,255,0.35)`). À utiliser avec Color.healthMapBlue.
    static let shadowBrandGlow = (opacity: 0.0, radius: CGFloat(0), y: CGFloat(0))
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
