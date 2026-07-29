import SwiftUI

// MARK: - Warm Background
/// Fond chaud statique unifié de l'app — remplace l'ancien ruban animé
/// (`AnimatedBackground`, retiré pour la perf : 3 bandes floutées redessinées
/// en continu). Ici : un simple dégradé chaud + un halo radial doux, **sans
/// animation ni blur** → coût GPU négligeable.
///
/// Dynamique light/dark via les tokens `healthMapWarm` / `healthMapWarmGlow`
/// (cf. `Color+Theme.swift`).
///
/// - Décoratif : `allowsHitTesting(false)` + `accessibilityHidden(true)`.
///
/// Usage (drop-in, comme l'ancien fond) :
/// ```swift
/// ZStack {
///     WarmBackground()
///     contenu
/// }
/// ```
extension View {
    /// Efface le fond de la barre de navigation : la page passe dessous.
    ///
    /// Sans réglage, iOS pose le sien — un bandeau clair figé sous l'heure et la
    /// batterie, qui ne s'en va jamais (barre `.inline`, titre vide) et tranche
    /// avec le crème de nos pages.
    ///
    /// ⚠️ Première tentative (build #388) : PEINDRE ce bandeau en `healthMapWarm`
    /// pour le fondre dans la page. Raté, et spectaculairement — retour d'Arthur :
    /// « ça se voit dix fois plus, il y en a deux maintenant ». Deux raisons :
    ///
    /// 1. nos pages ne sont pas d'un crème uni. `WarmBackground` est un dégradé
    ///    avec un halo chaud centré à 16 % de la hauteur, donc juste sous la
    ///    barre : un aplat figé par-dessus ne peut pas coïncider, et le filet de
    ///    séparation de la barre se lit alors comme une seconde ligne ;
    /// 2. les cinq onglets restent MONTÉS en permanence (conteneur maison, cf.
    ///    `MainTabView`), chacun avec son `NavigationStack`. Forcer `.visible`
    ///    faisait peindre sa barre à chacun, empilées au même endroit.
    ///
    /// On n'imite donc plus le fond : on le supprime. Les boutons de barre
    /// restent lisibles, la page glisse dessous comme partout ailleurs sur iOS.
    ///
    /// À poser sur le contenu racine de CHAQUE onglet, dans son `NavigationStack`.
    func kiwiNavigationBarBackground() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct WarmBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.healthMapWarm, Color.healthMapBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.healthMapWarmGlow.opacity(0.55), Color.healthMapWarmGlow.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.16),
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    WarmBackground()
}
