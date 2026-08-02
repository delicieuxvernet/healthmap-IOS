import SwiftUI

// MARK: - Vocabulaire de mouvement
//
// L'app comptait plus de vingt courbes différentes pour les mêmes gestes
// (0.2, 0.22, 0.25, 0.3, 0.4… au gré des écrans). Une durée qui change d'un
// écran à l'autre pour la même intention, c'est exactement ce qui fait qu'une
// app « ne se tient pas ». On nomme donc les quatre intentions réelles.
//
// Même logique que les tokens de couleur et de typographie : on consomme,
// on n'invente pas de valeur au cas par cas.
extension Animation {

    /// Du contenu qui arrive à l'écran (cartes, sections, listes).
    /// Sort vite, s'installe doucement : on suit le doigt, on ne le devance pas.
    static let kiwiEntrance = Animation.easeOut(duration: 0.55)

    /// Une jauge, un anneau, une barre qui se remplit. Volontairement long :
    /// c'est le moment où l'utilisateur lit son résultat.
    static let kiwiGauge = Animation.easeOut(duration: 1.0)

    /// Un changement d'état discret (bascule, apparition d'un encart,
    /// bandeau hors ligne). Doit se remarquer sans se faire attendre.
    static let kiwiSoft = Animation.easeInOut(duration: 0.25)

    /// Réponse immédiate à un appui. En dessous de 0.2 s, l'œil ne perçoit
    /// plus une animation mais une réaction — c'est le but.
    static let kiwiSnap = Animation.easeOut(duration: 0.18)
}

// MARK: - Entrée en cascade

/// Fait arriver un élément en fondu, très légèrement décalé vers le bas,
/// avec un retard proportionnel à sa position dans la liste.
///
/// Le décalage est plafonné : au-delà du 6ᵉ élément, tout arrive ensemble.
/// Sans ce plafond, le bas d'une longue liste se ferait attendre une seconde,
/// ce qui donne l'impression d'une app lente et non d'une app soignée.
///
/// Neutralisé par `accessibilityReduceMotion` : le contenu est alors
/// simplement présent, sans transition.
struct KiwiEntrance: ViewModifier {
    let index: Int
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var delay: Double { min(Double(max(index, 0)), 6) * 0.05 }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
            .onAppear {
                guard !visible else { return }
                if reduceMotion {
                    visible = true
                } else {
                    withAnimation(.kiwiEntrance.delay(delay)) { visible = true }
                }
            }
    }
}

extension View {
    /// Entrée en fondu décalée. `index` = position dans la liste.
    func kiwiEntrance(_ index: Int = 0) -> some View {
        modifier(KiwiEntrance(index: index))
    }
}
