import SwiftUI

// MARK: - Gestes du quotidien
//
// Les retours des gestes faits dix fois par jour : ajouter un aliment, changer
// une quantité. Chacun répond AU DOIGT, tout de suite, et dit ce qui vient de
// se passer sans texte : le « + » devient une coche, le chiffre défile, la
// butée fait non de la tête.
//
// La physique vient de `KiwiMotion.swift` (ressorts `kiwiVif` / `kiwiRebond`,
// échelles `KiwiEchelle`) : rien ici ne grossit au-delà de 1,08. Tout se tait
// sous « Réduire les animations » : l'état final reste lisible (une coche est
// une coche), seul le trajet disparaît.
//
// Le maintien d'un « − » ou d'un « + » n'a pas de composant ici : c'est le
// comportement système (`.buttonRepeatBehavior(.enabled)`), le même que le
// poids du Journal.

// MARK: Éclats

/// Des traits courts qui partent d'un rond, s'allongent, puis se résorbent en
/// s'éloignant. Une `Shape` animable : `progres` va de 0 à 1 et tout le reste
/// s'en déduit, donc l'animation peut être interrompue sans laisser de trace.
struct EclatsShape: Shape {
    /// 0 = rien à l'écran, 1 = fini (rien non plus).
    var progres: CGFloat
    /// Rayon du rond d'où partent les éclats.
    var rayonDepart: CGFloat
    var nombre: Int = 8

    var animatableData: CGFloat {
        get { progres }
        set { progres = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var chemin = Path()
        guard progres > 0.001, progres < 0.999, nombre > 0 else { return chemin }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let longueur: CGFloat = 6 * sin(CGFloat.pi * progres)
        let depart: CGFloat = rayonDepart + 3 + 9 * progres
        for rang in 0..<nombre {
            let angle = CGFloat(rang) / CGFloat(nombre) * 2 * CGFloat.pi - CGFloat.pi / 2
            let dx = cos(angle)
            let dy = sin(angle)
            chemin.move(to: CGPoint(x: centre.x + dx * depart, y: centre.y + dy * depart))
            chemin.addLine(to: CGPoint(x: centre.x + dx * (depart + longueur),
                                       y: centre.y + dy * (depart + longueur)))
        }
        return chemin
    }
}

// MARK: Pastille d'ajout rapide

/// Le rond « + » d'une ligne de recherche. Quand l'ajout a réussi, il se
/// rétracte, revient en coche sur le ressort « rebond », et huit éclats partent
/// autour. C'est le libellé d'un bouton : le toucher reste porté par l'appelant.
struct PastilleAjoutRapide: View {
    enum Etat: Equatable {
        /// « + » : prêt à ajouter.
        case repos
        /// L'écriture est en route.
        case enCours
        /// C'est dans le journal.
        case ajoute
    }

    let etat: Etat
    var diametre: CGFloat = 32

    /// Le creux d'où la coche repart : assez marqué pour se voir sur un rond
    /// de 32 points, sans jamais dépasser sa taille au retour.
    private static let creux: CGFloat = 0.86

    @State private var progresEclats: CGFloat = 0
    @State private var echelle: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            EclatsShape(progres: progresEclats, rayonDepart: diametre / 2)
                .stroke(Color.dsAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: diametre + 40, height: diametre + 40)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            ZStack {
                Circle().fill(Color.dsAccent)
                if etat == .enCours {
                    ProgressView().tint(.white).scaleEffect(0.7)
                } else {
                    Image(systemName: etat == .ajoute ? "checkmark" : "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: diametre, height: diametre)
            .scaleEffect(echelle)
        }
        // Les éclats débordent du rond sans pousser la ligne.
        .frame(width: diametre, height: diametre)
        .onChange(of: etat) { _, nouvelEtat in
            if nouvelEtat == .ajoute {
                celebrer()
            } else {
                rangerLesEclats()
            }
        }
    }

    private func celebrer() {
        guard !reduceMotion else { return }
        withAnimation(.kiwiVif) { echelle = Self.creux }
        // Décoration qui s'éteint toute seule : une durée, pas un ressort (un
        // ressort dépasserait 1 et redessinerait les traits).
        withAnimation(.easeOut(duration: 0.5)) { progresEclats = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.kiwiRebond) { echelle = 1 }
        }
    }

    /// Remise à zéro SANS animation : rejouée à l'envers, la progression
    /// redessinerait les éclats au moment où la coche redevient « + ».
    private func rangerLesEclats() {
        var sansAnimation = Transaction()
        sansAnimation.disablesAnimations = true
        withTransaction(sansAnimation) { progresEclats = 0 }
    }
}

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
