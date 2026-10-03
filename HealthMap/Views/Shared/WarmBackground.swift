import SwiftUI

// MARK: - Warm Background
/// Le fond de page historique. Il a été un ruban animé, puis un dégradé chaud
/// statique, puis le gris neutre de la refonte du 23 août 2026 ; depuis le
/// verre liquide (2 octobre 2026) c'est le FOND DE VERRE de l'app : quatre
/// halos flous qui dérivent sur une base pâle, à la teinte de l'onglet
/// (`DSPageBackground`, c'est-à-dire `VerreFond`). Le nom reste pour les
/// appelants ; plus rien ici n'est « chaud ».
///
/// - Décoratif : `allowsHitTesting(false)` + `accessibilityHidden(true)`,
///   portés par `VerreFond`, qui ignore aussi les zones sûres.
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
    /// avec le fond de nos pages.
    ///
    /// ⚠️ Première tentative (build #388) : PEINDRE ce bandeau en `healthMapWarm`
    /// pour le fondre dans la page. Raté, et spectaculairement — retour d'Arthur :
    /// « ça se voit dix fois plus, il y en a deux maintenant ». Deux raisons :
    ///
    /// 1. nos pages ne sont pas d'une couleur unie (et le fond de verre, dont
    ///    les halos dérivent, l'est encore moins). `WarmBackground` était un dégradé
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

/// Verre liquide (2 octobre 2026) : `WarmBackground` rend `DSPageBackground`,
/// qui est maintenant le fond de verre (`VerreFond`) à la teinte ambiante
/// (celle de l'onglet courant ; kiwi hors onglets). Plus de gris groupé, plus
/// de voile de marque. Le nom reste pour les appelants.
struct WarmBackground: View {
    var body: some View {
        DSPageBackground()
    }
}

#Preview {
    WarmBackground()
}
