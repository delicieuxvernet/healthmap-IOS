import SwiftUI

// MARK: - Pressed Button Style
/// Un seul état d'appui dans toute l'app : celui du design system
/// (`DSPressStyle`, `KiwiDS.swift` : léger rétrécissement + assombrissement,
/// rétrécissement coupé sous « Réduire les animations »).
///
/// `.healthMapPressed` est le nom historique. Il renvoie désormais au même
/// style que `.dsPress` : il existait deux réglages différents pour le même
/// geste (opacité 0,85 ici, assombrissement là), et un bouton ne répondait pas
/// pareil selon l'écran où il se trouvait.
///
/// Usage :
/// ```swift
/// Button { action() } label: { ... }
///     .buttonStyle(.healthMapPressed)
/// ```
typealias PressedButtonStyle = DSPressStyle

extension ButtonStyle where Self == DSPressStyle {
    /// Nom historique de `.dsPress` : même style, même réglage.
    static var healthMapPressed: DSPressStyle { DSPressStyle() }
}
