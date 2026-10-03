import SwiftUI

// MARK: - Lavis de teinte par onglet (décision fondateur, août 2026)
/// Historique : un très léger lavis vertical posé SOUS le contenu de chaque
/// onglet racine, une teinte par onglet ; puis (refonte du 23 août 2026) un
/// seul voile de marque `#E9F2E2` sur 240 pt, le même pour tous.
///
/// Verre liquide (2 octobre 2026) : ce lavis ne rend PLUS RIEN. La teinte par
/// onglet est revenue, mais c'est le fond lui-même qui la porte : `VerreFond`
/// fond ses halos vers la palette de l'onglet courant (kiwi, aube, ciel,
/// orchidée, neutre) en 0,9 s. Un voile de marque posé par-dessus verdirait
/// les cinq onglets et annulerait ce changement de teinte : `DSBrandWash`
/// n'est donc plus rendu ici.
///
/// Le type et son paramètre restent pour les appelants : le poser dans un
/// `ZStack` est sans effet, ni à l'œil ni sur la mise en page.
struct TabWashBackground: View {
    let tint: Color

    var body: some View {
        EmptyView()
    }
}

#Preview {
    ZStack {
        WarmBackground()
        TabWashBackground(tint: .dsAccent)
    }
}
