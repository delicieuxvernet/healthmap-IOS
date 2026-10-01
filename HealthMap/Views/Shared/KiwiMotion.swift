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

// MARK: - Une seule physique (maquette « Motion », 1er octobre 2026)
//
// Ce qui répond au doigt ou fête un geste ne prend AUCUNE durée fixe : trois
// ressorts, pour que tout s'interrompe et reparte sans saut. Les quatre courbes
// du dessus restent celles du contenu qui s'installe tout seul (entrée d'une
// page, jauge qui se remplit à l'ouverture).
extension Animation {

    /// Vif : appuis, bascules, sélection.
    static let kiwiVif = Animation.spring(response: 0.28, dampingFraction: 0.86)

    /// Fluide : feuilles et grandes surfaces qui s'installent.
    static let kiwiFluide = Animation.spring(response: 0.5, dampingFraction: 0.9)

    /// Rebond : célébrations uniquement (coche, étiquettes, confirmation).
    static let kiwiRebond = Animation.spring(response: 0.55, dampingFraction: 0.72)

    /// Un chiffre qui compte jusqu'à sa nouvelle valeur. Amorti critique : un
    /// compteur qui dépasse sa cible puis revient afficherait un faux total.
    static let kiwiCompteur = Animation.spring(response: 0.6, dampingFraction: 1)
}

/// Ce qui grandit, et de combien. Rien ne dépasse 1,08 : au-delà, ça devient
/// un jeu.
enum KiwiEchelle {
    /// Appui sur tout élément touchable.
    static let appui: CGFloat = 0.96
    /// Une récompense qui apparaît : 0,5 → 1,08 → 1.
    static let recompenseDepart: CGFloat = 0.5
    static let recompenseCrete: CGFloat = 1.08
    /// Une carte dont la valeur vient de changer : impulsion, puis retour.
    static let impulsion: CGFloat = 1.035
    /// Le plafond de tout ce qui précède.
    static let plafond: CGFloat = 1.08
}

// MARK: - Un chiffre qui compte

/// Affiche un entier qui COMPTE jusqu'à sa nouvelle valeur quand celle-ci
/// change dans une transaction animée (`.animation(.kiwiCompteur, value:)`).
/// Sans animation, il prend directement sa valeur : c'est le comportement
/// attendu sous « Réduire les animations ».
struct ChiffreQuiCompte: View, Animatable {
    var valeur: Double
    /// Mise en forme de l'entier affiché (`DS.entier` par défaut : `1 021`).
    var format: (Int) -> String = { DS.entier($0) }

    var animatableData: Double {
        get { valeur }
        set { valeur = newValue }
    }

    var body: some View {
        Text(format(Int(valeur.rounded())))
    }
}

// MARK: - Impulsion d'une carte mise à jour

/// La carte gonfle à 1,035 puis revient, une fois, quand `declencheur` change.
/// Rien sous « Réduire les animations » : la nouvelle valeur suffit.
struct KiwiImpulsion<Declencheur: Equatable>: ViewModifier {
    let declencheur: Declencheur
    @State private var gonflee = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(gonflee ? KiwiEchelle.impulsion : 1)
            .onChange(of: declencheur) { _, _ in
                guard !reduceMotion else { return }
                withAnimation(.kiwiVif) { gonflee = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    withAnimation(.kiwiRebond) { gonflee = false }
                }
            }
    }
}

// MARK: - Apparition d'une récompense

/// 0,5 → 1,08 → 1 : la récompense surgit, dépasse à peine, se pose. Sous
/// « Réduire les animations », un simple fondu.
struct KiwiRecompense: ViewModifier {
    let visible: Bool
    @State private var echelle: CGFloat = KiwiEchelle.recompenseDepart
    @State private var opacite: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(echelle)
            .opacity(opacite)
            .onAppear { if visible { surgir() } }
            .onChange(of: visible) { _, maintenant in
                if maintenant { surgir() } else { ranger() }
            }
    }

    private func surgir() {
        guard !reduceMotion else {
            echelle = 1
            withAnimation(.easeOut(duration: 0.2)) { opacite = 1 }
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            echelle = KiwiEchelle.recompenseCrete
            opacite = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            withAnimation(.kiwiRebond) { echelle = 1 }
        }
    }

    private func ranger() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .kiwiVif) { opacite = 0 }
        echelle = reduceMotion ? 1 : KiwiEchelle.recompenseDepart
    }
}

extension View {
    /// Impulsion 1,035 puis retour quand `declencheur` change.
    func kiwiImpulsion<Declencheur: Equatable>(_ declencheur: Declencheur) -> some View {
        modifier(KiwiImpulsion(declencheur: declencheur))
    }

    /// La vue surgit comme une récompense quand `visible` devient vrai.
    func kiwiRecompense(_ visible: Bool) -> some View {
        modifier(KiwiRecompense(visible: visible))
    }
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

// MARK: - « Suis-je à l'écran ? »

/// Les cinq onglets restent montés : `onAppear` ne dit pas qu'on est visible.
/// La racine pose cette valeur sur chaque onglet ; une vue qui anime en continu
/// (le graphe du Plan) s'en sert pour se mettre en pause hors écran, et une
/// entrée chorégraphiée pour se rejouer à l'arrivée. Vrai par défaut : une
/// feuille ou un aperçu est toujours « à l'écran ».
private struct EstOngletActifKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var estOngletActif: Bool {
        get { self[EstOngletActifKey.self] }
        set { self[EstOngletActifKey.self] = newValue }
    }
}

extension View {
    /// Entrée en fondu décalée. `index` = position dans la liste.
    func kiwiEntrance(_ index: Int = 0) -> some View {
        modifier(KiwiEntrance(index: index))
    }
}
