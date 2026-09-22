import SwiftUI

// MARK: - Kiwi Loader (chargement : les pépins qui chargent)
//
// Le signe Kiwio (`KiwiSigne`) devenu indicateur d'attente : les graines
// gardent leur place, c'est leur ÉCLAT qui tourne. Une graine s'allume quand
// la tête de la traînée passe, puis s'estompe jusqu'au tour suivant — la
// grammaire du spinner iOS, dessinée avec le fruit de la marque (variante
// « traînée » validée par Arthur le 27 juillet 2026, gardée avec le nouveau
// signe). Un tour en 1,8 s, comme le dit la maquette de l'identité.
//
// Entrée : on part de la couronne pleine (le signe tel que l'affiche l'écran de
// lancement statique) et la traînée s'installe en 0,35 s, sans saut.
//
// Périmètre : tous les écrans d'attente (lancement, analyse, chargement d'une
// page). Les spinners logés DANS un bouton restent des `ProgressView` : à
// 18 pt, douze graines deviennent illisibles.
//
// - Reduce Motion : le signe, plein et immobile.
struct KiwiLoader: View {
    var size: CGFloat = 44
    /// Durée d'un tour complet de la traînée.
    var period: Double = KiwiLoader.periode

    /// « tourne 1 tour / 1,8 s » (maquette finale, section Identité).
    static let periode: Double = 1.8
    /// De la couronne pleine à la traînée.
    static let entree: Double = 0.35
    /// Éclat de la dernière graine de la traînée.
    static let eclatMinimum: Double = 0.15
    /// La tête part de la graine du haut (midi), pas de celle de droite.
    private static let depart = 9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var debut: Date?

    var body: some View {
        Group {
            if reduceMotion {
                KiwiSigne(taille: size)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { contexte in
                    let ecoule = debut.map { contexte.date.timeIntervalSince($0) } ?? 0
                    KiwiSigne(taille: size, graines: Self.opacites(ecoule: ecoule, periode: period))
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            if debut == nil { debut = Date() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement en cours")
    }

    /// Éclat de chaque graine, `ecoule` secondes après l'apparition.
    static func opacites(ecoule: TimeInterval, periode: Double = KiwiLoader.periode) -> [Double] {
        let n = Double(KiwiMarque.nombreDeGraines)
        let temps = max(0, ecoule)
        let tete = (temps / max(periode, 0.1) * n + Double(depart)).truncatingRemainder(dividingBy: n)
        let installation = min(1, temps / entree)
        return (0..<KiwiMarque.nombreDeGraines).map { index in
            // Distance parcourue par la tête depuis qu'elle a quitté cette graine.
            var distance = (tete - Double(index)).truncatingRemainder(dividingBy: n)
            if distance < 0 { distance += n }
            let trainee = 1 - (1 - eclatMinimum) * distance / n
            return 1 - installation * (1 - trainee)
        }
    }
}

#Preview {
    ZStack {
        Color.dsFond.ignoresSafeArea()
        VStack(spacing: 36) {
            KiwiLoader(size: 72)
            KiwiLoader(size: 52)
            KiwiLoader(size: 44, period: 1.0)
        }
    }
}
