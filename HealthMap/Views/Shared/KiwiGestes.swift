import SwiftUI

// MARK: - Gestes du quotidien
//
// Les retours des gestes faits dix fois par jour : ajouter un aliment, changer
// une quantité. Chacun répond AU DOIGT, tout de suite, et dit ce qui vient de
// se passer sans texte : le « + » devient une coche, le chiffre défile, la
// butée fait non de la tête.
//
// Rien ici ne grossit au-delà de 1,08 : au-dessus, le geste devient un jeu.
// Tout se tait sous « Réduire les animations » : l'état final reste lisible
// (une coche est une coche), seul le trajet disparaît.

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
/// rétracte, revient en coche avec un léger rebond, et huit éclats partent
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
        withAnimation(.easeOut(duration: 0.09)) { echelle = 0.86 }
        withAnimation(.easeOut(duration: 0.5)) { progresEclats = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { echelle = 1 }
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

/// Le nombre d'aliments ajoutés depuis l'ouverture de la recherche. Il gonfle
/// à peine (1,08) à chaque ajout : on voit que ça compte sans quitter la liste
/// des yeux.
struct CompteurAjouts: View {
    let nombre: Int

    @State private var gonfle = false
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
            .scaleEffect(gonfle ? 1.08 : 1)
            .onChange(of: nombre) { _, _ in
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.12)) { gonfle = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { gonfle = false }
                }
            }
            .accessibilityLabel(nombre > 1 ? "\(nombre) aliments ajoutés" : "\(nombre) aliment ajouté")
    }
}

// MARK: Bouton à répétition

/// Un « − » ou un « + » de quantité. Un toucher fait un pas ; un maintien
/// répète, de plus en plus vite (400 ms, puis un quart de moins à chaque pas,
/// jamais sous 80 ms). Le pas part à la pose du doigt, comme le compteur
/// système : c'est ce qui permet d'enchaîner sans relever le doigt.
///
/// `pas` renvoie `false` quand la valeur n'a pas bougé (butée) : la répétition
/// s'arrête là, et c'est à l'appelant de le faire sentir.
struct BoutonARepetition<Etiquette: View>: View {
    private let enButee: Bool
    private let pas: () -> Bool
    private let etiquette: () -> Etiquette

    /// Retombe tout seul à `false` quand le geste finit OU est annulé (une
    /// feuille qui se ferme, un geste système) : jamais de répétition orpheline.
    @GestureState private var doigtPose = false
    @State private var repetition: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter enButee: le bouton s'estompe mais reste touchable, pour que
    ///   la valeur puisse répondre « non » au doigt.
    init(enButee: Bool = false,
         pas: @escaping () -> Bool,
         @ViewBuilder etiquette: @escaping () -> Etiquette) {
        self.enButee = enButee
        self.pas = pas
        self.etiquette = etiquette
    }

    var body: some View {
        etiquette()
            .opacity(enButee ? 0.4 : 1)
            .scaleEffect(doigtPose && !reduceMotion ? 0.97 : 1)
            .brightness(doigtPose ? -0.04 : 0)
            .animation(DS.ressortAppui, value: doigtPose)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($doigtPose) { _, pose, _ in pose = true }
            )
            .onChange(of: doigtPose) { _, pose in
                if pose { commencer() } else { arreter() }
            }
            .onDisappear { arreter() }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { _ = pas() }
    }

    private func commencer() {
        arreter()
        guard pas() else { return }
        repetition = Task { @MainActor in
            var attente = CadenceRepetition.depart
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(attente))
                if Task.isCancelled { break }
                guard pas() else { break }
                attente = CadenceRepetition.suivante(attente)
            }
        }
    }

    private func arreter() {
        repetition?.cancel()
        repetition = nil
    }
}

/// Le rythme d'un maintien : il part lentement (on a le temps de relâcher
/// après un seul pas), accélère, puis plafonne à une vitesse qu'on suit encore
/// des yeux.
enum CadenceRepetition {
    /// Attente avant le deuxième pas, en secondes.
    static let depart: Double = 0.4
    /// Attente la plus courte entre deux pas.
    static let plancher: Double = 0.08

    /// Attente suivante : un quart de moins, jamais sous le plancher.
    static func suivante(_ attente: Double) -> Double {
        max(plancher, attente * 0.75)
    }
}

// MARK: Butée

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
            .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: secousses)
    }
}
