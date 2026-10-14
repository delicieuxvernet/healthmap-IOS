import SwiftUI

// MARK: - Gestes du quotidien
//
// Ce que la refonte « Verre liquide » (`KiwiVerre.swift`) n'avait pas encore :
// le compteur d'ajouts de la recherche et la butée d'une quantité. Le reste
// des gestes s'appuie sur les briques du verre : la coche d'un ajout rapide
// rebondit avec `verrePop` et part en `verreGerbe`, comme la prise d'un
// complément.
//
// Le maintien d'un « − » ou d'un « + » n'a pas de composant ici : c'est le
// comportement système (`.buttonRepeatBehavior(.enabled)`), le même que le
// poids du Journal. Tout se tait sous « Réduire les animations ».

// MARK: Compteur d'ajouts

/// Le nombre d'aliments ajoutés depuis l'ouverture de la recherche. Il prend
/// l'impulsion des cartes dont la valeur vient de changer (1,035) : on voit
/// que ça compte sans quitter la liste des yeux.
struct CompteurAjouts: View {
    let nombre: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(nombre)")
            .font(.system(size: 13, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Color.dsTexte)
            .contentTransition(.numericText())
            .padding(.horizontal, 6)
            .frame(minWidth: 26, minHeight: 26)
            .overlay(Capsule().stroke(Color.dsAccent, lineWidth: 1.5))
            .animation(reduceMotion ? nil : .kiwiVif, value: nombre)
            .kiwiImpulsion(nombre)
            .accessibilityLabel(nombre > 1 ? "\(nombre) aliments ajoutés" : "\(nombre) aliment ajouté")
    }
}

// MARK: Butée

/// Compte les butées à faire sentir. Un « − » ou un « + » maintenu rappelle
/// son action en boucle (`.buttonRepeatBehavior`) : tant que les appels se
/// suivent de près, c'est le même appui, donc une seule secousse.
struct Butee: Equatable {
    /// Nombre de secousses à jouer depuis l'ouverture (`kiwiSecousse`).
    private(set) var secousses = 0
    private var dernierAppel = Date.distantPast

    /// Deux appels plus rapprochés que ça appartiennent au même appui.
    static let memeAppui: TimeInterval = 0.6

    /// Le bouton vient d'être touché alors qu'il ne peut plus bouger.
    mutating func toucher(a maintenant: Date = Date()) {
        defer { dernierAppel = maintenant }
        guard maintenant.timeIntervalSince(dernierAppel) > Self.memeAppui else { return }
        secousses += 1
    }
}

/// La valeur fait non de la tête : deux allers-retours de quelques points.
/// `animatableData` compte les secousses demandées ; à chaque entier, le
/// décalage est nul, donc la vue se repose exactement où elle était.
struct KiwiSecousse: GeometryEffect {
    var amplitude: CGFloat = 6
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let decalage = amplitude * sin(animatableData * CGFloat.pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: decalage, y: 0))
    }
}

extension View {
    /// Secoue la vue une fois chaque fois que `secousses` augmente d'un cran.
    /// Rien sous « Réduire les animations ».
    func kiwiSecousse(_ secousses: Int) -> some View {
        modifier(KiwiSecousseModifier(secousses: secousses))
    }
}

private struct KiwiSecousseModifier: ViewModifier {
    let secousses: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(KiwiSecousse(animatableData: reduceMotion ? 0 : CGFloat(secousses)))
            // Une oscillation jouée une fois : sa durée fait partie du geste.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: secousses)
    }
}
