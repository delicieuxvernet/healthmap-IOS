import SwiftUI
import UIKit

// MARK: - La bulle de dictée (maquette « Motion v3 - Verre liquide », 2 octobre 2026)
//
// Le bouton « Dicter » DEVIENT la bulle. Elle part de son cadre, grandit en un
// disque de 150 pt posé au centre de l'écran (ressort `kiwiFluide`), pendant
// qu'un voile flou tombe sur la page. Elle remplace la bulle kiwi façon
// Snapchat de la veille (tranche de 84 pt, graines vivantes, arc).
//
// La bulle : trois couches liquides, des formes fermées à sept points lissées
// qui tournent et ondulent. Leur amplitude suit le niveau du micro, lissé ;
// l'ensemble gonfle avec la voix, une aura verte respire derrière, et une onde
// part à chaque pic.
//
// Au-dessus, la carte de transcription en verre. L'app ne transcrit pas en
// direct (la capture enregistre, puis transcrit : voir `SpeechCaptureService`)
// : la carte dit « Je t'écoute… » tant qu'on parle, puis les mots arrivent un
// par un, du flou au net, dès que la transcription existe.
//
// Sous la bulle : la consigne, puis « Annuler » et « Terminer ». Quand le doigt
// tient encore le bouton (appui maintenu), ces deux boutons deviennent les
// deux gestes qui font la même chose : glisser pour annuler, relâcher pour
// terminer.
//
// « Terminer » : la bulle se contracte à 66 pt, trois points tournent autour
// d'elle, les couches accélèrent. La transcription se fait là, sous elle (sur
// l'appareil). Quand le texte est prêt elle s'efface, la feuille monte sur sa
// relecture — l'analyse, payante, n'est lancée que depuis la feuille — et le
// voile reste jusqu'à ce que la feuille redescende.
//
// La scène vit à la RACINE : elle passe par-dessus la barre d'onglets, et le
// Journal porte déjà trop de présentations. Le Journal garde toute la logique
// de la dictée et ne fait que déposer ici de quoi la montrer.
//
// Le bouton d'origine n'est jamais retiré de la page (seulement masqué) : un
// appui maintenu garde donc son geste vivant sous la scène.
//
// « Réduire les animations » : la bulle est posée d'emblée à sa place, fixe,
// sans onde ni trajet. Tout arrive et repart en fondu.

// MARK: Géométrie

enum EcouteGeometrie {

    // MARK: Les trois temps de la bulle

    /// Où en est la bulle : encore dans le cadre du bouton, en train
    /// d'écouter, ou contractée pendant le calcul.
    enum Temps: Equatable {
        case bouton
        case ecoute
        case calcul
    }

    /// Diamètre de la bulle qui écoute.
    static let diametre: CGFloat = 150
    /// Diamètre de la bulle contractée, pendant le calcul.
    static let diametreCalcul: CGFloat = 66
    /// Rayon du bouton « Dicter » dont elle part : sa capsule de 60 pt (la
    /// même valeur que `JournalSaisieBloc.rayonDicter`).
    static let rayonBouton: CGFloat = Verre.hauteurSaisie / 2
    /// Vers quoi elle rétrécit quand les résultats montent.
    static let echelleSortie: CGFloat = 0.5

    // MARK: Où tout se pose
    //
    // La maquette est un téléphone de 393 × 852. La scène, elle, se dessine
    // dans la zone sûre : on retire 59 pt en haut et 34 en bas.

    /// Hauteur du centre de la bulle, en part de la hauteur utile : 527 sur
    /// 852 dans la maquette, soit 468 sur 759.
    static let hauteurRelative: CGFloat = 468.0 / 759.0
    /// Haut de la carte de transcription (118 − 59).
    static let hautCarte: CGFloat = 59
    /// Marge latérale de la carte de transcription.
    static let margeCarte: CGFloat = 20
    /// Hauteur minimale de la carte de transcription.
    static let hauteurCarteMin: CGFloat = 128
    /// Entre le bas de la carte et le haut de la bulle, au plus serré.
    static let margeSousCarte: CGFloat = 16
    /// Entre le bas de la bulle et la consigne.
    static let ecartControles: CGFloat = 28
    /// Place gardée sous la bulle pour la consigne et ses deux boutons.
    static let hauteurControles: CGFloat = 96
    /// Entre le bas de la bulle contractée et « Kiwio relit ta dictée… ».
    static let ecartCalcul: CGFloat = 23
    /// Les trois points tournent à cette distance du bord de la bulle.
    static let ecartPoints: CGFloat = 16
    /// Durée d'un tour des trois points.
    static let tourPoints: Double = 1.2

    /// Le centre de la bulle qui écoute, dans une surcouche de cette taille :
    /// au milieu, un peu sous la mi-hauteur. Jamais sous la carte de
    /// transcription, et toujours de quoi poser les boutons dessous.
    static func centreEcoute(dans taille: CGSize) -> CGPoint {
        let rayon = diametre / 2
        let plancher = hautCarte + hauteurCarteMin + margeSousCarte + rayon
        let plafond = taille.height - rayon - ecartControles - hauteurControles
        let voulu = taille.height * hauteurRelative
        let y = min(max(voulu, plancher), max(plancher, plafond))
        return CGPoint(x: taille.width / 2, y: y)
    }

    /// Le cadre de la bulle à chacun de ses temps. Sans cadre de bouton connu,
    /// elle naît contractée, là où elle écoutera.
    static func cadreBulle(_ temps: Temps, bouton: CGRect?, dans taille: CGSize) -> CGRect {
        let centre = centreEcoute(dans: taille)
        let cote: CGFloat
        switch temps {
        case .bouton:
            if let bouton { return bouton }
            cote = diametreCalcul
        case .ecoute:
            cote = diametre
        case .calcul:
            cote = diametreCalcul
        }
        return CGRect(x: centre.x - cote / 2, y: centre.y - cote / 2, width: cote, height: cote)
    }

    /// Le rayon des coins de la bulle à chacun de ses temps.
    static func rayonBulle(_ temps: Temps, bouton: CGRect?) -> CGFloat {
        switch temps {
        case .bouton:
            return bouton == nil ? diametreCalcul / 2 : rayonBouton
        case .ecoute:
            return diametre / 2
        case .calcul:
            return diametreCalcul / 2
        }
    }

    // MARK: Le doigt (appui maintenu)

    /// Vers la droite, la bulle suit le doigt jusque-là, pas plus loin.
    static let glisseDroiteMax: CGFloat = 60
    /// Distance sur laquelle la bulle s'estompe en partant vers l'annulation.
    static let courseEstompe: CGFloat = 140
    static let opaciteMinimum: Double = 0.25

    /// Le déplacement de la bulle pour un doigt qui a glissé d'autant : elle le
    /// suit, bornée à gauche par le seuil d'annulation.
    static func glisse(_ largeur: CGFloat) -> CGFloat {
        max(DicteeGeste.seuilAnnulation, min(glisseDroiteMax, largeur))
    }

    /// La bulle s'estompe à l'approche du seuil : on sent l'annulation venir.
    static func opacite(glisse: CGFloat) -> Double {
        max(opaciteMinimum, 1 + Double(min(0, glisse) / courseEstompe))
    }

    // MARK: La voix

    /// Le niveau du micro ramené entre 0 et 1. Une voix normale doit déjà
    /// faire vivre le liquide, d'où le rehaussement.
    static func amplitude(niveau: Float) -> CGFloat {
        CGFloat(min(1, max(0, niveau * 1.6)))
    }

    /// Amplitude du liquide quand personne ne parle.
    static let amplitudePlancher: Double = 0.16
    /// Ce que la voix y ajoute, au plus fort.
    static let amplitudeCourse: Double = 0.75
    /// Amplitude pendant le calcul : le liquide tourne, il ne suit plus rien.
    static let amplitudeCalcul: Double = 0.12
    /// Lissage : à chaque image (60 par seconde), l'amplitude parcourt cette
    /// part du chemin qui la sépare de sa cible.
    static let lissage: Double = 0.2
    /// L'ensemble gonfle d'autant au plus fort de la voix.
    static let gonflement: CGFloat = 0.08
    /// L'aura : 0,9 au repos, jusqu'à 1,35 au plus fort de la voix.
    static let auraRepos: CGFloat = 0.9
    static let auraCourse: CGFloat = 0.45
    /// L'aura déborde la bulle de 34 % de chaque côté.
    static let auraEtendue: CGFloat = 1.68
    /// Pendant le calcul, les couches tournent trois fois plus vite.
    static let vitesseCalcul: Double = 3

    /// Vers quoi tend l'amplitude du liquide.
    static func cible(niveau: Float, ecoute: Bool) -> Double {
        guard ecoute else { return amplitudeCalcul }
        return amplitudePlancher + amplitudeCourse * Double(amplitude(niveau: niveau))
    }

    /// L'amplitude après `dt` secondes : le lissage de la maquette (0,2 par
    /// image à 60 Hz), ramené au temps réellement écoulé.
    static func lisser(_ amplitude: Double, vers cible: Double, dt: Double) -> Double {
        let images = max(0, min(dt, 0.25)) * 60
        let part = 1 - pow(1 - lissage, images)
        return amplitude + (cible - amplitude) * part
    }

    // Une onde part à chaque pic de voix.

    /// En dessous, ce n'est pas une voix : un bruit de fond.
    static let seuilPic: CGFloat = 0.3
    /// Le saut d'une mesure à la suivante qui fait un pic.
    static let sautPic: CGFloat = 0.1
    /// Jamais deux ondes à moins de cet écart.
    static let ecartOndes: Double = 0.29
    /// L'onde : de 1 à 1,9 en 1,1 s.
    static let echelleOnde: CGFloat = 1.9
    static let dureeOnde: Double = 1.1

    /// La voix vient-elle de monter d'un coup ?
    static func estUnPic(avant: CGFloat, maintenant: CGFloat) -> Bool {
        maintenant >= seuilPic && maintenant - avant >= sautPic
    }

    // MARK: Le liquide
    //
    // Les trois couches se dessinent dans un repère de 200, celui du dessin de
    // la maquette : rayons 72, 54 et 32 autour du centre (100, 100).

    static let repere: CGFloat = 200
    static let nombreDePoints = 7
    static let rayonCoucheFond: Double = 72
    static let rayonCoucheMilieu: Double = 54
    static let rayonCoucheCoeur: Double = 32

    /// Les sept points d'une couche à l'instant `temps` (en millisecondes).
    /// Chaque point tourne lentement autour du centre, et son rayon ondule :
    /// une onde portée par la voix, plus un frisson qui ne s'arrête jamais.
    static func pointsDeCouche(rayon: Double, temps: Double, amplitude: Double,
                               graine: Double, dx: Double, dy: Double) -> [CGPoint] {
        var points: [CGPoint] = []
        points.reserveCapacity(nombreDePoints)
        for index in 0..<nombreDePoints {
            let rang = Double(index)
            let angle = rang / Double(nombreDePoints) * 2 * Double.pi + temps * 0.0003 * (graine + 1)
            let phaseVoix = temps * 0.0026 * (1 + graine * 0.35) + rang * 1.9 + graine * 3
            let phaseFrisson = temps * 0.0012 + rang * 2.7 + graine
            let facteur = 1 + amplitude * 0.2 * sin(phaseVoix) + 0.04 * sin(phaseFrisson)
            let x = 100 + dx + rayon * facteur * cos(angle)
            let y = 100 + dy + rayon * facteur * sin(angle)
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }

    /// La forme fermée qui passe par ces points, lissée : chaque tronçon est
    /// une courbe dont les poignées suivent les deux points voisins.
    static func contourLisse(_ points: [CGPoint]) -> Path {
        var contour = Path()
        let nombre = points.count
        guard nombre >= 3 else { return contour }
        contour.move(to: points[0])
        for index in 0..<nombre {
            let p0 = points[(index - 1 + nombre) % nombre]
            let p1 = points[index]
            let p2 = points[(index + 1) % nombre]
            let p3 = points[(index + 2) % nombre]
            let poignee1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let poignee2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            contour.addCurve(to: p2, control1: poignee1, control2: poignee2)
        }
        contour.closeSubpath()
        return contour
    }

    /// Peint les trois couches et le reflet, centrés dans `taille`.
    static func peindreLiquide(_ contexte: inout GraphicsContext, taille: CGSize,
                               temps: Double, amplitude: Double) {
        let cote = min(taille.width, taille.height)
        guard cote > 0 else { return }
        let unite = cote / repere
        let origineX = (taille.width - cote) / 2
        let origineY = (taille.height - cote) / 2
        let versEcran = CGAffineTransform(translationX: origineX, y: origineY).scaledBy(x: unite, y: unite)

        // Le fond : la couche la plus large, du vert clair au vert profond.
        let pointsFond = pointsDeCouche(rayon: rayonCoucheFond, temps: temps, amplitude: amplitude,
                                        graine: 0, dx: 0, dy: 0)
        let centreFond = CGPoint(x: origineX + CGFloat(100 - 0.3 * rayonCoucheFond) * unite,
                                 y: origineY + CGFloat(100 - 0.4 * rayonCoucheFond) * unite)
        contexte.fill(
            contourLisse(pointsFond).applying(versEcran),
            with: .radialGradient(
                Gradient(colors: [Color(hex: "8FD460"), Color(hex: "3E8A1E")]),
                center: centreFond,
                startRadius: 0,
                endRadius: CGFloat(1.6 * rayonCoucheFond) * unite
            )
        )

        // Le milieu : une couche claire qui dérive, et se fond dans le fond.
        let dxMilieu = 8 * sin(temps / 900)
        let dyMilieu = 6 * cos(temps / 1100)
        let pointsMilieu = pointsDeCouche(rayon: rayonCoucheMilieu, temps: temps, amplitude: amplitude * 1.2,
                                          graine: 1, dx: dxMilieu, dy: dyMilieu)
        let centreMilieu = CGPoint(x: origineX + CGFloat(100 + dxMilieu - 0.2 * rayonCoucheMilieu) * unite,
                                   y: origineY + CGFloat(100 + dyMilieu - 0.3 * rayonCoucheMilieu) * unite)
        var coucheMilieu = contexte
        coucheMilieu.opacity = 0.9
        coucheMilieu.fill(
            contourLisse(pointsMilieu).applying(versEcran),
            with: .radialGradient(
                Gradient(colors: [Color(hex: "DDF5C4"), Color(hex: "7CCC54").opacity(0)]),
                center: centreMilieu,
                startRadius: 0,
                endRadius: CGFloat(1.4 * rayonCoucheMilieu) * unite
            )
        )

        // Le cœur : une lueur presque blanche, floue, en haut à gauche.
        let dxCoeur = -12 + 6 * cos(temps / 700)
        let dyCoeur = -14 + 5 * sin(temps / 800)
        let pointsCoeur = pointsDeCouche(rayon: rayonCoucheCoeur, temps: temps, amplitude: amplitude * 1.4,
                                         graine: 2, dx: dxCoeur, dy: dyCoeur)
        var coucheCoeur = contexte
        coucheCoeur.opacity = 0.55
        coucheCoeur.addFilter(.blur(radius: 6 * unite))
        coucheCoeur.fill(contourLisse(pointsCoeur).applying(versEcran), with: .color(Color(hex: "F2FBEA")))

        // Le reflet : une ellipse blanche, penchée de 30°.
        let ellipse = Path(ellipseIn: CGRect(x: -24, y: -12, width: 48, height: 24))
            .applying(CGAffineTransform(translationX: 74, y: 60).rotated(by: -CGFloat.pi / 6))
            .applying(versEcran)
        var coucheReflet = contexte
        coucheReflet.opacity = 0.35
        coucheReflet.addFilter(.blur(radius: 4 * unite))
        coucheReflet.fill(ellipse, with: .color(Color.white))
    }
}

// MARK: - Le relais vers la racine

/// Ce que le Journal dépose pour que la racine montre la scène de dictée.
@MainActor
final class EcouteCentre: ObservableObject {
    static let partage = EcouteCentre()

    enum Phase: Equatable {
        /// Rien à l'écran.
        case repos
        /// La bulle est là, on écoute.
        case ecoute
        /// Fin d'écoute : la bulle se contracte et tourne, le temps de
        /// transcrire. Rien ne part encore au serveur.
        case calcul
        /// Le texte est prêt : la bulle s'efface, la feuille monte pour le
        /// relire. Le voile reste jusqu'à ce qu'elle redescende.
        case resultat
        /// Dictée jetée ou trop courte : la bulle retourne dans son bouton.
        case retour
    }

    @Published private(set) var phase: Phase = .repos
    /// Mains libres : on touche « Terminer » (ou la bulle). Sinon le doigt
    /// tient le bouton, et le lever lance l'analyse.
    @Published private(set) var mainsLibres = true
    /// Le bouton de la page s'efface tant que la bulle porte sa forme.
    @Published private(set) var boutonCache = false
    /// Ce qui vient d'être dit, dès que la transcription existe.
    @Published private(set) var transcription = ""

    private(set) var speech: SpeechCaptureService?
    private(set) var geste: GesteDictee?
    private var terminer: () -> Void = {}
    private var annuler: () -> Void = {}
    private var abandonner: () -> Void = {}
    private var rangement: Task<Void, Never>?

    /// Le temps laissé à la bulle pour retourner dans son bouton.
    static let sortie: Duration = .milliseconds(560)

    init() {}

    func ouvrir(speech: SpeechCaptureService,
                geste: GesteDictee,
                mainsLibres: Bool,
                onTerminer: @escaping () -> Void,
                onAnnuler: @escaping () -> Void,
                onAbandonner: @escaping () -> Void = {}) {
        rangement?.cancel()
        self.speech = speech
        self.geste = geste
        self.mainsLibres = mainsLibres
        terminer = onTerminer
        annuler = onAnnuler
        abandonner = onAbandonner
        transcription = ""
        boutonCache = true
        phase = .ecoute
    }

    /// Le doigt a glissé vers le haut : la dictée continue sans lui.
    func verrouiller() {
        guard phase == .ecoute else { return }
        mainsLibres = true
    }

    /// Fin d'écoute réussie : la bulle se contracte et tourne, le temps de
    /// transcrire. Le bouton reste caché, sous le voile puis
    /// sous la feuille : il ne revient qu'au repos (`vider()`), comme dans la
    /// maquette.
    func contracter() {
        guard phase == .ecoute else { return }
        phase = .calcul
    }

    /// La transcription existe : la carte la relit mot à mot.
    func transcrire(_ texte: String) {
        guard phase == .calcul else { return }
        transcription = texte
    }

    /// Le texte est prêt : la bulle s'efface, la feuille prend le relais.
    func livrer() {
        guard phase == .calcul else { return }
        phase = .resultat
    }

    /// La feuille de résultats est redescendue : le voile s'éteint.
    func fermer() {
        guard phase == .resultat else { return }
        rangement?.cancel()
        vider()
    }

    /// Dictée jetée, trop courte, ou calcul abandonné : la bulle retourne dans
    /// son bouton, qui reste caché jusqu'à ce qu'elle s'y soit reposée.
    func rendreLeBouton() {
        guard phase == .ecoute || phase == .calcul else { return }
        phase = .retour
        boutonCache = true
        ranger()
    }

    func toucherLaBulle() {
        guard phase == .ecoute, mainsLibres else { return }
        terminer()
    }

    func toucherAnnuler() {
        guard phase == .ecoute else { return }
        annuler()
    }

    /// « Annuler » pendant le calcul : on ne garde rien de cette dictée.
    func toucherAbandonner() {
        guard phase == .calcul else { return }
        abandonner()
    }

    private func ranger() {
        rangement?.cancel()
        rangement = Task { [weak self] in
            try? await Task.sleep(for: EcouteCentre.sortie)
            guard !Task.isCancelled, let self else { return }
            self.vider()
        }
    }

    private func vider() {
        boutonCache = false
        phase = .repos
        transcription = ""
        speech = nil
        geste = nil
        terminer = {}
        annuler = {}
        abandonner = {}
    }
}

// MARK: - La surcouche (posée par la racine)

struct EcouteSurcouche: View {
    /// Cadre du bouton « Dicter » dans le repère de la surcouche.
    let cadreBouton: CGRect?
    let taille: CGSize

    @ObservedObject private var centre = EcouteCentre.partage
    /// Le cadre du bouton AVANT que la scène ne s'ouvre : il ne doit pas
    /// bouger sous elle si la page se remet en page pendant l'écoute.
    @State private var cadreAuRepos: CGRect?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .allowsHitTesting(false)
                .onChange(of: cadreBouton, initial: true) { _, nouveau in
                    if centre.phase == .repos { cadreAuRepos = nouveau }
                }

            if centre.phase != .repos, let speech = centre.speech, let geste = centre.geste {
                EcouteScene(centre: centre, speech: speech, geste: geste,
                            bouton: cadreAuRepos, taille: taille)
                    // Elle est là d'un coup (c'est le bouton qui change de
                    // forme), et s'en va en fondu.
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .frame(width: taille.width, height: taille.height)
        .animation(.easeInOut(duration: 0.4), value: centre.phase == .repos)
    }
}

// MARK: - La scène

private struct EcouteScene: View {
    @ObservedObject var centre: EcouteCentre
    let speech: SpeechCaptureService
    let geste: GesteDictee
    let bouton: CGRect?
    let taille: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// La scène est installée : le voile est tombé, la bulle a quitté le bouton.
    @State private var ouverte = false
    /// Le calcul dure : on laisse une sortie.
    @State private var abandonPossible = false

    /// Après ce délai de calcul, « Annuler » revient sous la bulle.
    private static let delaiAbandon: Duration = .seconds(4)

    private var entree: Animation {
        reduceMotion ? Animation.easeOut(duration: 0.2) : Animation.kiwiFluide
    }

    /// Où en est la bulle.
    private var temps: EcouteGeometrie.Temps {
        switch centre.phase {
        case .ecoute:
            return (ouverte || reduceMotion) ? .ecoute : .bouton
        case .calcul, .resultat:
            return .calcul
        case .retour, .repos:
            return reduceMotion ? .ecoute : .bouton
        }
    }

    private var voile: Bool {
        guard ouverte else { return false }
        return centre.phase == .ecoute || centre.phase == .calcul || centre.phase == .resultat
    }

    private var carteVisible: Bool {
        ouverte && (centre.phase == .ecoute || centre.phase == .calcul)
    }

    private var controlesVisibles: Bool {
        ouverte && centre.phase == .ecoute
    }

    private var bulleVisible: Bool {
        switch centre.phase {
        case .ecoute:
            return reduceMotion ? ouverte : true
        case .calcul:
            return true
        case .retour:
            return !reduceMotion
        case .resultat, .repos:
            return false
        }
    }

    var body: some View {
        let repere = EcouteGeometrie.centreEcoute(dans: taille)
        let hautControles = repere.y + EcouteGeometrie.diametre / 2 + EcouteGeometrie.ecartControles
        let hautCalcul = repere.y + EcouteGeometrie.diametreCalcul / 2 + EcouteGeometrie.ecartCalcul

        ZStack(alignment: .topLeading) {
            // Plus rien n'est touchable derrière la scène, jusqu'à sa sortie :
            // on ne change pas d'onglet avec un micro ouvert.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                // Filet de sécurité : la feuille de résultats couvre ce fond.
                // Si on arrive à le toucher, c'est qu'elle n'est pas montée :
                // le voile ne doit pas garder l'écran.
                .onTapGesture {
                    if centre.phase == .resultat { centre.fermer() }
                }
                .accessibilityHidden(true)

            VerreVoile()
                .opacity(voile ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: voile)
                .allowsHitTesting(false)

            CarteTranscription(centre: centre, speech: speech,
                               visible: carteVisible, reduceMotion: reduceMotion)
                .padding(.horizontal, EcouteGeometrie.margeCarte)
                .padding(.top, EcouteGeometrie.hautCarte)
                .frame(width: taille.width)
                .allowsHitTesting(false)

            BulleLiquide(
                speech: speech,
                geste: geste,
                temps: temps,
                cadre: EcouteGeometrie.cadreBulle(temps, bouton: bouton, dans: taille),
                rayon: EcouteGeometrie.rayonBulle(temps, bouton: bouton),
                partie: centre.phase == .resultat,
                visible: bulleVisible,
                mainsLibres: centre.mainsLibres,
                reduceMotion: reduceMotion,
                onToucher: { centre.toucherLaBulle() }
            )

            consigneCalcul
                .frame(width: taille.width)
                .offset(y: hautCalcul)

            controles
                .frame(width: taille.width)
                .offset(y: hautControles)
        }
        .frame(width: taille.width, height: taille.height, alignment: .topLeading)
        // La carte et les boutons gardent leur place : au-delà, le texte
        // passerait sous la bulle.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .onAppear {
            withAnimation(entree) { ouverte = true }
        }
        .task(id: centre.phase) {
            abandonPossible = false
            guard centre.phase == .calcul else { return }
            UIAccessibility.post(notification: .announcement, argument: "Kiwio relit ta dictée")
            try? await Task.sleep(for: Self.delaiAbandon)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { abandonPossible = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Sous la bulle, pendant l'écoute

    private var controles: some View {
        VStack(spacing: 14) {
            Text("Dis ce que tu as mangé, avec les quantités")
                .font(.dsSousTitreMoyen)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 1)
                .padding(.horizontal, DS.marge)

            if centre.mainsLibres {
                HStack(spacing: 12) {
                    boutonAnnuler
                    boutonTerminer
                }
            } else {
                // Le doigt tient le bouton : les deux boutons deviennent les
                // deux gestes qui font la même chose.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        gesteAnnuler
                        gesteTerminer
                    }
                    VStack(spacing: 10) {
                        gesteTerminer
                        gesteAnnuler
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .opacity(controlesVisibles ? 1 : 0)
        .offset(y: (controlesVisibles || reduceMotion) ? 0 : 12)
        .animation(reduceMotion ? Animation.easeOut(duration: 0.2) : Animation.kiwiFluide, value: controlesVisibles)
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: centre.mainsLibres)
        .allowsHitTesting(controlesVisibles)
    }

    /// La vibration vient de `annulerDictee()` (un avertissement) : en jouer
    /// une ici en ferait deux pour un seul geste.
    private var boutonAnnuler: some View {
        Button {
            centre.toucherAnnuler()
        } label: {
            Text("Annuler")
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 22)
                .frame(minHeight: 50)
                .verre(VerreMatiere.surVoile, forme: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.dsPress)
        .accessibilityHint("Jette la dictée")
    }

    private var boutonTerminer: some View {
        Button {
            centre.toucherLaBulle()
        } label: {
            HStack(spacing: 8) {
                carreRouge
                Text("Terminer")
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
            }
            .padding(.horizontal, 22)
            .frame(minHeight: 50)
            .verre(VerreMatiere.carteFlottante, forme: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("Terminer la dictée")
        .accessibilityHint("Lance l'analyse de ce que tu viens de dire")
    }

    private var gesteAnnuler: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left.2")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text("Glisse pour annuler")
                .font(.dsSousTitreFort)
                .tracking(DSTracking.sousTitre)
        }
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(minHeight: 50)
        .verre(VerreMatiere.surVoile, forme: Capsule(style: .continuous))
    }

    private var gesteTerminer: some View {
        HStack(spacing: 8) {
            carreRouge
            Text("Relâche pour terminer")
                .font(.dsSousTitreFort)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
        }
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(minHeight: 50)
        .verre(VerreMatiere.carteFlottante, forme: Capsule(style: .continuous))
    }

    /// Le carré rouge d'un enregistreur : « arrêter ».
    private var carreRouge: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.dsACombler)
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }

    // MARK: Sous la bulle, pendant le calcul

    private var consigneCalcul: some View {
        let actif = centre.phase == .calcul
        return VStack(spacing: 18) {
            Text("Kiwio relit ta dictée…")
                .font(.dsSousTitreFort)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 1)

            // La transcription peut durer (longue dictée, modèle absent de
            // l'appareil) : on ne garde personne devant un écran sans sortie.
            if abandonPossible && actif {
                // Vibration : celle de `abandonnerCalcul()`, une seule.
                Button {
                    centre.toucherAbandonner()
                } label: {
                    Text("Annuler")
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 20)
                        .frame(minHeight: DS.cibleTactile)
                        .verre(VerreMatiere.surVoile, forme: Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.dsPress)
                .accessibilityHint("Jette la dictée")
                .transition(.opacity)
            }
        }
        .opacity(actif ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: actif)
        .allowsHitTesting(actif)
    }
}

// MARK: - La carte de transcription

/// En verre flottant, au-dessus de la bulle : le point rouge de
/// l'enregistrement, où on en est, le minuteur, puis ce qui a été dit.
private struct CarteTranscription: View {
    @ObservedObject var centre: EcouteCentre
    let speech: SpeechCaptureService
    let visible: Bool
    let reduceMotion: Bool

    private var ecoute: Bool { centre.phase == .ecoute }
    private var transcrite: Bool { !centre.transcription.isEmpty }

    private var libelle: String {
        if ecoute { return "Je t'écoute" }
        return transcrite ? "Transcription terminée" : "Transcription en cours"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.dsACombler)
                    .frame(width: 8, height: 8)
                    .opacity(ecoute ? 1 : 0)
                    .accessibilityHidden(true)
                Text(libelle)
                    .font(.system(.footnote, design: .default).weight(.semibold))
                    .foregroundStyle(Color.dsSecondaire)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MinuteurEcoute(speech: speech)
            }

            if transcrite {
                MotsQuiArrivent(texte: centre.transcription, grand: true)
            } else {
                Text(ecoute ? "Je t'écoute…" : "Je relis ce que tu as dit…")
                    .font(MotsQuiArrivent.policeGrande)
                    .tracking(-0.5)
                    .foregroundStyle(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: EcouteGeometrie.hauteurCarteMin, alignment: .topLeading)
        .verreCarteFlottante()
        .offset(y: (visible || reduceMotion) ? 0 : -16)
        .scaleEffect((visible || reduceMotion) ? 1 : 0.96)
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: visible)
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.35), value: visible)
        .animation(.easeOut(duration: 0.2), value: centre.phase)
        // La transcription arrive : la carte grandit pour la recevoir.
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: transcrite)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Le minuteur (seul, avec la bulle, à suivre le micro)

private struct MinuteurEcoute: View {
    @ObservedObject var speech: SpeechCaptureService

    var body: some View {
        Text(String(format: "%d:%02d", Int(speech.duree) / 60, Int(speech.duree) % 60))
            .font(.system(.footnote, design: .default).weight(.semibold).monospacedDigit())
            .foregroundStyle(Color.dsSecondaire)
            .accessibilityHidden(true)
    }
}

// MARK: - La bulle

/// L'horloge du liquide : son temps propre (il accélère pendant le calcul) et
/// son amplitude lissée. Une classe, pas un `@State` : elle avance à chaque
/// image sans jamais réinvalider la vue.
private final class MoteurLiquide {
    /// Temps propre des couches, en millisecondes.
    private var temps: Double = 0
    private var amplitude: Double = EcouteGeometrie.amplitudePlancher
    private var derniereImage: Date?
    /// La mesure du micro d'avant, pour repérer un pic.
    var niveauPrecedent: CGFloat = 0
    var derniereOnde: Date = .distantPast

    /// Là où le liquide en est, sans le faire avancer (bulle figée).
    var etat: (temps: Double, amplitude: Double) { (temps, amplitude) }

    func avancer(a date: Date, cible: Double, vitesse: Double) -> (temps: Double, amplitude: Double) {
        let ecoule = derniereImage.map { max(0, min(date.timeIntervalSince($0), 0.1)) } ?? 0
        derniereImage = date
        temps += ecoule * 1000 * vitesse
        amplitude = EcouteGeometrie.lisser(amplitude, vers: cible, dt: ecoule)
        return (temps, amplitude)
    }
}

/// Vue SÉPARÉE, et c'est le point : avec le minuteur, elle est la seule à
/// observer `speech` (niveau sonore, 20 Hz) et `geste` (glissement du doigt,
/// 120 Hz). Ni la scène ni la racine ne sont réinvalidées à ce rythme.
private struct BulleLiquide: View {
    @ObservedObject var speech: SpeechCaptureService
    @ObservedObject var geste: GesteDictee
    let temps: EcouteGeometrie.Temps
    /// Où elle se tient, et sa taille : le cadre du bouton, puis le disque.
    let cadre: CGRect
    let rayon: CGFloat
    /// Le résultat est prêt : elle rétrécit et s'efface.
    let partie: Bool
    let visible: Bool
    let mainsLibres: Bool
    let reduceMotion: Bool
    let onToucher: () -> Void

    @State private var moteur = MoteurLiquide()
    /// Les ondes en cours : une par pic de voix.
    @State private var ondes: [UUID] = []

    private var ecoute: Bool { temps == .ecoute && speech.state == .listening }

    /// Le côté du disque dans lequel le liquide se dessine.
    private var cote: CGFloat { min(cadre.width, cadre.height) }

    /// Appui maintenu : la bulle suit le doigt à l'horizontale.
    private var glisse: CGFloat {
        guard !mainsLibres, temps == .ecoute else { return 0 }
        return EcouteGeometrie.glisse(geste.glissement.width)
    }

    private var courbe: Animation {
        reduceMotion ? Animation.easeOut(duration: 0.2) : Animation.kiwiFluide
    }

    var body: some View {
        Button(action: onToucher) {
            corps
                .frame(width: cadre.width, height: cadre.height)
                .contentShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .disabled(!mainsLibres || temps != .ecoute)
        .scaleEffect(partie && !reduceMotion ? EcouteGeometrie.echelleSortie : 1)
        .position(x: cadre.midX + glisse, y: cadre.midY)
        .animation(courbe, value: temps)
        .animation(courbe, value: partie)
        // Verrouillée d'un glissé vers le haut, elle revient au centre.
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: mainsLibres)
        .opacity(visible ? EcouteGeometrie.opacite(glisse: glisse) : 0)
        .animation(.easeOut(duration: 0.3), value: visible)
        // `duree` avance à chaque mesure du micro : c'est l'horloge des pics.
        .onChange(of: speech.duree) { _, _ in
            guetterUnPic()
        }
        // « Terminer » porte déjà ce geste pour VoiceOver.
        .accessibilityHidden(true)
    }

    private var corps: some View {
        ZStack {
            // La face du bouton, le temps que la bulle le quitte ou y revienne.
            RoundedRectangle(cornerRadius: rayon, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: Color(hex: "7CCC54"), location: 0),
                            Gradient.Stop(color: Color(hex: "5DA838"), location: 0.5),
                            Gradient.Stop(color: Color(hex: "428426"), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(temps == .bouton ? 1 : 0)

            ForEach(ondes, id: \.self) { _ in
                OndeDeVoix()
            }

            liquide

            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.white)
                .opacity(temps == .bouton ? 1 : 0)

            // Seulement tant qu'elle calcule : sous la feuille de résultats,
            // plus rien ne tourne.
            if temps == .calcul && !partie {
                PointsDeCalcul(reduceMotion: reduceMotion)
                    .frame(width: cote + 2 * EcouteGeometrie.ecartPoints,
                           height: cote + 2 * EcouteGeometrie.ecartPoints)
                    .transition(.opacity)
            }
        }
    }

    /// Les trois couches, leur aura, et ce qui les fait bouger. L'amplitude
    /// est lue et lissée à chaque image : rien ici ne passe par un état.
    private var liquide: some View {
        let cible = EcouteGeometrie.cible(niveau: speech.level, ecoute: temps != .calcul)
        let vitesse: Double = temps == .calcul ? EcouteGeometrie.vitesseCalcul : 1
        let montre = temps != .bouton
        let opaciteAura: Double = temps == .ecoute ? 1 : (temps == .calcul ? 0.6 : 0)
        let coteAura = cote * EcouteGeometrie.auraEtendue
        // À l'arrêt dès que la bulle n'est plus à l'écran : la feuille de
        // résultats peut rester ouverte longtemps au-dessus de la scène.
        let fige = reduceMotion || !visible
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: fige)) { chrono in
            // Figée, elle ne bouge pas non plus quand la vue se redessine au
            // rythme du micro.
            let image = fige ? moteur.etat : moteur.avancer(a: chrono.date, cible: cible, vitesse: vitesse)
            Canvas { contexte, taille in
                EcouteGeometrie.peindreLiquide(&contexte, taille: taille,
                                               temps: image.temps, amplitude: image.amplitude)
            }
            .scaleEffect(1 + CGFloat(image.amplitude) * EcouteGeometrie.gonflement)
            .opacity(montre ? 1 : 0)
            .background {
                AuraDeVoix(cote: coteAura)
                    .scaleEffect(EcouteGeometrie.auraRepos + CGFloat(image.amplitude) * EcouteGeometrie.auraCourse)
                    .opacity(opaciteAura)
            }
        }
        .allowsHitTesting(false)
    }

    /// Une onde part quand la voix monte d'un coup, jamais deux de suite.
    private func guetterUnPic() {
        let niveau = EcouteGeometrie.amplitude(niveau: speech.level)
        let avant = moteur.niveauPrecedent
        moteur.niveauPrecedent = niveau
        guard ecoute, !reduceMotion,
              EcouteGeometrie.estUnPic(avant: avant, maintenant: niveau) else { return }
        let maintenant = Date()
        guard maintenant.timeIntervalSince(moteur.derniereOnde) >= EcouteGeometrie.ecartOndes else { return }
        moteur.derniereOnde = maintenant

        let onde = UUID()
        ondes.append(onde)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(EcouteGeometrie.dureeOnde + 0.1))
            ondes.removeAll { $0 == onde }
        }
    }
}

/// L'aura verte, floue, derrière la bulle.
private struct AuraDeVoix: View {
    let cote: CGFloat

    private static let vert = Color(red: 143 / 255, green: 212 / 255, blue: 96 / 255)

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Self.vert.opacity(0.7), Self.vert.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(1, cote / 2 * 0.93)
                )
            )
            .frame(width: cote, height: cote)
            .blur(radius: 10)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Une onde : un anneau qui s'élargit de 1 à 1,9 et s'efface en 1,1 s.
private struct OndeDeVoix: View {
    @State private var partie = false

    var body: some View {
        Circle()
            .strokeBorder(Color.teinteKiwiClair.opacity(0.85), lineWidth: 1.5)
            .scaleEffect(partie ? EcouteGeometrie.echelleOnde : 1)
            .opacity(partie ? 0 : 0.8)
            .onAppear {
                withAnimation(.timingCurve(0.2, 0.7, 0.3, 1, duration: EcouteGeometrie.dureeOnde)) {
                    partie = true
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Les trois points qui tournent autour de la bulle pendant le calcul. Sous
/// « Réduire les animations », ils sont posés et ne tournent pas.
private struct PointsDeCalcul: View {
    let reduceMotion: Bool
    @State private var tourne = false

    private static let teintes: [Color] = [Color.teinteKiwiClair, Color.teinteKiwiPale, Color.teinteKiwi]

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Self.teintes[index])
                    .frame(width: 7, height: 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .rotationEffect(.degrees(Double(index) * 120))
            }
        }
        .rotationEffect(.degrees(tourne ? 360 : 0))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: EcouteGeometrie.tourPoints).repeatForever(autoreverses: false)) {
                tourne = true
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
