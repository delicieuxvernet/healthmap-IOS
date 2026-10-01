import SwiftUI

// MARK: - La bulle d'écoute (maquette « bulle kiwi », 2 octobre 2026)
//
// La bulle des messages vocaux de Snapchat et d'Instagram, avec le signe Kiwio
// à la place du rond blanc. Elle remplace la grande scène du 1er octobre
// (voile flou, page qui recule, cercle de 132 pt) : la page reste là, nette.
//
// Dès que la dictée démarre, une tranche de kiwi de 84 pt surgit juste
// au-dessus du bouton « Dicter » (0,62 → 1, ressort vif). Ses douze graines
// s'allongent avec la voix : chaque mesure du micro entre par la graine de
// droite et fait le tour dans le sens des aiguilles d'une montre. Un arc naît
// en haut à droite, s'allonge jusqu'à un quart de tour et tourne en 1,7 s.
// Tant que le doigt tient le bouton, la bulle le suit à l'horizontale et
// s'estompe à l'approche de l'annulation. À la fin elle rétrécit et s'efface
// en 0,15 s, et la feuille d'analyse monte.
//
// Le bouton, lui, garde sa place et dit où on en est : le minuteur, et le
// geste qui termine. La scène vit à la RACINE : elle passe par-dessus la barre
// d'onglets, et le Journal porte déjà trop de présentations. Le Journal garde
// toute la logique de la dictée et ne fait que déposer ici de quoi la montrer.
//
// Le bouton d'origine n'est jamais retiré de la page (seulement masqué) : un
// appui maintenu garde donc son geste vivant sous la scène.
//
// « Réduire les animations » : un fondu de 0,2 s, pas d'arc, pas de trajet.
// Les graines bougent encore : elles disent qu'on écoute.

// MARK: Géométrie

enum EcouteGeometrie {
    /// Diamètre de la bulle : la tranche de kiwi.
    static let diametre: CGFloat = 84
    /// Rayon du bouton « Dicter » au-dessus duquel elle se pose.
    static let rayonBouton: CGFloat = 22
    /// Entre le haut du bouton et le bas de la bulle.
    static let ecartAuBouton: CGFloat = 12
    /// Ce qu'on garde avec les bords de l'écran.
    static let margeEcran: CGFloat = 12
    /// Jamais plus haut : la bulle resterait sous l'encoche.
    static let hautMinimum: CGFloat = 60
    /// Sans cadre de bouton connu : distance du centre au bas de l'écran.
    static let hauteurParDefaut: CGFloat = 176

    // L'entrée et la sortie.

    /// D'où la bulle surgit.
    static let echelleDepart: CGFloat = 0.62
    /// Vers quoi elle rétrécit en partant.
    static let echelleSortie: CGFloat = 0.6
    /// Elle descend d'autant en s'effaçant.
    static let deriveSortie: CGFloat = 10
    static let dureeSortie: Double = 0.15

    // Le doigt.

    /// Vers la droite, la bulle suit le doigt jusque-là, pas plus loin.
    static let glisseDroiteMax: CGFloat = 60
    /// Distance sur laquelle la bulle s'estompe en partant vers l'annulation.
    static let courseEstompe: CGFloat = 140
    static let opaciteMinimum: Double = 0.25

    // L'arc.

    /// Entre le bord de la bulle et l'arc.
    static let arcEcart: CGFloat = 5.5
    static let arcEpaisseur: CGFloat = 2
    /// Sa longueur une fois déployé : 85° sur 360.
    static let arcPart: CGFloat = 85.0 / 360
    /// Où il naît : en haut à droite (0° = à droite, sens des aiguilles).
    static let arcDepart: Double = -60
    /// Durée d'un tour.
    static let arcTour: Double = 1.7
    /// Il attend que la bulle soit posée, puis se déploie.
    static let arcDelai: Duration = .milliseconds(250)
    static let arcDeploiement: Double = 0.6

    // La tranche. Mêmes rayons que `KiwiMarque.Geometrie.standard`, dans une
    // boîte de 96 : la peau (rayon 48) touche le bord de la bulle.

    static let boite: CGFloat = 96
    static let rayonPeau: CGFloat = 48
    static let rayonChair: CGFloat = 43
    static let rayonHaloRepos: CGFloat = 21
    static let rayonCoeurRepos: CGFloat = 12
    static let orbiteRepos: CGFloat = 26
    /// Ce qu'une graine gagne en longueur au plus fort de la voix.
    static let allongeGraine: CGFloat = 11
    /// Le halo et le cœur gonflent à peine : 10 % et 14 %.
    static let souffleHalo: CGFloat = 0.10
    static let souffleCoeur: CGFloat = 0.14

    /// Où le centre de la bulle se pose, dans une surcouche de cette taille :
    /// à l'aplomb du bouton, juste au-dessus de lui, toujours à l'écran.
    static func centreBulle(bouton: CGRect?, dans taille: CGSize) -> CGPoint {
        let rayon = diametre / 2
        guard let bouton else {
            return CGPoint(x: taille.width / 2, y: taille.height - hauteurParDefaut)
        }
        let gauche = rayon + margeEcran
        let droite = max(gauche, taille.width - rayon - margeEcran)
        let x = min(droite, max(gauche, bouton.midX))
        let y = max(hautMinimum + rayon, bouton.minY - ecartAuBouton - rayon)
        return CGPoint(x: x, y: y)
    }

    /// Le déplacement de la bulle pour un doigt qui a glissé d'autant : elle le
    /// suit, bornée à gauche par le seuil d'annulation.
    static func glisse(_ largeur: CGFloat) -> CGFloat {
        max(DicteeGeste.seuilAnnulation, min(glisseDroiteMax, largeur))
    }

    /// La bulle s'estompe à l'approche du seuil : on sent l'annulation venir.
    static func opacite(glisse: CGFloat) -> Double {
        max(opaciteMinimum, 1 + Double(min(0, glisse) / courseEstompe))
    }

    /// Le niveau du micro ramené entre 0 et 1. Une voix normale doit déjà
    /// faire vivre les graines, d'où le rehaussement.
    static func amplitude(niveau: Float) -> CGFloat {
        CGFloat(min(1, max(0, niveau * 1.6)))
    }

    /// Une graine pour une amplitude 0…1 : elle s'allonge vers le bord, son
    /// bout intérieur ne bouge pas.
    static func graine(amplitude: CGFloat) -> (longueur: CGFloat, orbite: CGFloat) {
        let borne = min(1, max(0, amplitude))
        let gain = allongeGraine * borne
        return (KiwiMarque.graineHauteur + gain, orbiteRepos + gain / 2)
    }

    static func rayonHalo(amplitude: CGFloat) -> CGFloat {
        rayonHaloRepos * (1 + souffleHalo * min(1, max(0, amplitude)))
    }

    static func rayonCoeur(amplitude: CGFloat) -> CGFloat {
        rayonCoeurRepos * (1 + souffleCoeur * min(1, max(0, amplitude)))
    }

    /// La trace de la voix après une nouvelle mesure : elle entre par la
    /// première graine et pousse les autres d'un cran.
    static func avancer(_ historique: [CGFloat], avec amplitude: CGFloat) -> [CGFloat] {
        guard !historique.isEmpty else { return historique }
        return [min(1, max(0, amplitude))] + historique.dropLast()
    }
}

// MARK: - Le relais vers la racine

/// Ce que le Journal dépose pour que la racine montre la scène d'écoute.
@MainActor
final class EcouteCentre: ObservableObject {
    static let partage = EcouteCentre()

    enum Phase: Equatable {
        /// Rien à l'écran.
        case repos
        /// La bulle est là, on écoute.
        case ecoute
        /// Fin d'écoute : la bulle s'efface, la feuille d'analyse monte.
        case calcul
        /// Dictée jetée ou trop courte : la bulle s'efface, le bouton revient.
        case retour
    }

    @Published private(set) var phase: Phase = .repos
    /// Mains libres : on touche la bulle pour terminer. Sinon le doigt tient le
    /// bouton, et le lever lance l'analyse.
    @Published private(set) var mainsLibres = true
    /// Le bouton de la page s'efface tant que la scène porte sa face.
    @Published private(set) var boutonCache = false

    private(set) var speech: SpeechCaptureService?
    private(set) var geste: GesteDictee?
    private var terminer: () -> Void = {}
    private var annuler: () -> Void = {}
    private var rangement: Task<Void, Never>?

    /// Le temps laissé à la scène pour s'effacer avant de quitter l'écran.
    static let sortie: Duration = .milliseconds(320)

    init() {}

    func ouvrir(speech: SpeechCaptureService,
                geste: GesteDictee,
                mainsLibres: Bool,
                onTerminer: @escaping () -> Void,
                onAnnuler: @escaping () -> Void) {
        rangement?.cancel()
        self.speech = speech
        self.geste = geste
        self.mainsLibres = mainsLibres
        terminer = onTerminer
        annuler = onAnnuler
        boutonCache = true
        phase = .ecoute
    }

    /// Le doigt a glissé vers le haut : la dictée continue sans lui.
    func verrouiller() {
        guard phase == .ecoute else { return }
        mainsLibres = true
    }

    /// Fin d'écoute réussie : la bulle s'efface, la feuille prend le relais.
    func contracter() {
        guard phase == .ecoute else { return }
        phase = .calcul
        boutonCache = false
        ranger()
    }

    /// Dictée jetée ou trop courte : la bulle s'efface, le bouton reprend sa face.
    func rendreLeBouton() {
        guard phase == .ecoute else { return }
        phase = .retour
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

    private func ranger() {
        rangement?.cancel()
        rangement = Task { [weak self] in
            try? await Task.sleep(for: EcouteCentre.sortie)
            guard !Task.isCancelled, let self else { return }
            self.boutonCache = false
            self.phase = .repos
            self.speech = nil
            self.geste = nil
            self.terminer = {}
            self.annuler = {}
        }
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
            }
        }
        .frame(width: taille.width, height: taille.height)
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
    /// La bulle a surgi.
    @State private var ouverte = false

    /// La scène est installée et on écoute encore.
    private var enScene: Bool { ouverte && centre.phase == .ecoute }

    private var entree: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .kiwiVif
    }

    var body: some View {
        let position = EcouteGeometrie.centreBulle(bouton: bouton, dans: taille)

        ZStack(alignment: .topLeading) {
            // Plus rien n'est touchable derrière la scène, jusqu'à sa sortie :
            // on ne change pas d'onglet avec un micro ouvert.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            if let bouton {
                FaceEcoute(centre: centre, speech: speech, enScene: enScene)
                    .frame(width: bouton.width, height: bouton.height)
                    .position(x: bouton.midX, y: bouton.midY)
            }

            BulleKiwi(
                speech: speech,
                geste: geste,
                enScene: enScene,
                partie: centre.phase != .ecoute,
                mainsLibres: centre.mainsLibres,
                reduceMotion: reduceMotion,
                onToucher: { centre.toucherLaBulle() }
            )
            .position(x: position.x, y: position.y)
        }
        .frame(width: taille.width, height: taille.height)
        .onAppear {
            withAnimation(entree) { ouverte = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - La face du bouton pendant l'écoute

/// Posée exactement sur le bouton « Dicter » : même fond, et à la place de
/// « Dicter · le plus rapide », le minuteur et le geste qui termine. À la
/// sortie elle reprend la face du bouton, puis la scène s'en va : le passage
/// de l'une à l'autre ne se voit pas.
private struct FaceEcoute: View {
    @ObservedObject var centre: EcouteCentre
    let speech: SpeechCaptureService
    let enScene: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var forme: RoundedRectangle {
        RoundedRectangle(cornerRadius: EcouteGeometrie.rayonBouton, style: .continuous)
    }

    var body: some View {
        ZStack {
            FondBoutonDicter(rayon: EcouteGeometrie.rayonBouton)

            FaceBoutonDicter()
                .opacity(enScene ? 0 : 1)
                .accessibilityHidden(true)

            consignes
                .opacity(enScene ? 1 : 0)
        }
        .clipShape(forme)
        .contentShape(forme)
        // Mains libres : toucher le bouton termine aussi, comme toucher la bulle.
        .onTapGesture { centre.toucherLaBulle() }
        .animation(reduceMotion ? nil : .kiwiVif, value: enScene)
        .animation(reduceMotion ? nil : .kiwiVif, value: centre.mainsLibres)
    }

    private var consignes: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
                .accessibilityHidden(true)

                Spacer(minLength: 0)

                if centre.mainsLibres {
                    Button {
                        HapticService.shared.tap()
                        centre.toucherAnnuler()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.22)))
                            .frame(width: DS.cibleTactile, height: DS.cibleTactile)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPress)
                    .accessibilityLabel("Jeter la dictée")
                }
            }

            // La place de l'onde du bouton : la même hauteur, pour que les
            // deux faces se superposent ligne à ligne.
            Color.clear
                .frame(height: 14)
                .padding(.top, 10)
                .overlay(alignment: .bottomLeading) {
                    if !centre.mainsLibres {
                        Text("‹‹ Glisse pour annuler")
                            .font(.dsLegende)
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

            MinuteurEcoute(speech: speech)
                .padding(.top, 8)

            Text(centre.mainsLibres ? "Touche pour terminer" : "Relâche pour envoyer")
                .font(.dsLegende)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Le minuteur (seul, avec la bulle, à suivre le micro)

private struct MinuteurEcoute: View {
    @ObservedObject var speech: SpeechCaptureService

    var body: some View {
        HStack(spacing: 7) {
            PointEnregistrement()
                .padding(3)
                .background(Circle().fill(Color.white))
            Text(String(format: "%d:%02d", Int(speech.duree) / 60, Int(speech.duree) % 60))
                .font(Font.dsHeadline.monospacedDigit())
                .tracking(DSTracking.corps)
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Enregistrement en cours")
    }
}

// MARK: - La bulle

/// Vue SÉPARÉE, et c'est le point : avec le minuteur, elle est la seule à
/// observer `speech` (niveau sonore, 20 Hz) et `geste` (glissement du doigt,
/// 120 Hz). Ni la scène ni la racine ne sont réinvalidées à ce rythme.
private struct BulleKiwi: View {
    @ObservedObject var speech: SpeechCaptureService
    @ObservedObject var geste: GesteDictee
    /// La bulle est à l'écran et on écoute.
    let enScene: Bool
    /// L'écoute est finie : la bulle s'en va.
    let partie: Bool
    let mainsLibres: Bool
    let reduceMotion: Bool
    let onToucher: () -> Void

    /// La trace de la voix : une amplitude par graine, la plus récente d'abord.
    @State private var historique: [CGFloat] = Array(repeating: 0, count: KiwiMarque.nombreDeGraines)
    @State private var arcDeploye = false
    @State private var arcTourne = false
    /// Où le doigt l'avait menée : elle s'efface là, sans revenir au centre.
    @State private var dernierGlisse: CGFloat = 0

    private var ecoute: Bool { speech.state == .listening }

    private var amplitude: CGFloat {
        ecoute ? EcouteGeometrie.amplitude(niveau: speech.level) : 0
    }

    /// Appui maintenu : la bulle suit le doigt à l'horizontale.
    private var glisse: CGFloat {
        if mainsLibres { return 0 }
        return partie ? dernierGlisse : EcouteGeometrie.glisse(geste.glissement.width)
    }

    private var echelle: CGFloat {
        if reduceMotion || enScene { return 1 }
        return partie ? EcouteGeometrie.echelleSortie : EcouteGeometrie.echelleDepart
    }

    /// Elle surgit sur un ressort, elle part sur une durée courte.
    private var courbe: Animation {
        if reduceMotion { return .easeOut(duration: 0.2) }
        return enScene ? .kiwiVif : .easeOut(duration: EcouteGeometrie.dureeSortie)
    }

    /// Le côté du carré qui contient la bulle et son arc.
    private var cote: CGFloat {
        EcouteGeometrie.diametre + 2 * (EcouteGeometrie.arcEcart + EcouteGeometrie.arcEpaisseur)
    }

    var body: some View {
        Button(action: onToucher) {
            ZStack {
                KiwiVivant(historique: historique, amplitude: amplitude, reduceMotion: reduceMotion)
                    .frame(width: EcouteGeometrie.diametre, height: EcouteGeometrie.diametre)
                    .compositingGroup()
                    .shadow(color: Color.black.opacity(0.16), radius: 7, x: 0, y: 4)

                if !reduceMotion { arc }
            }
            .frame(width: cote, height: cote)
            .contentShape(Circle())
        }
        .buttonStyle(.dsPress)
        .disabled(!mainsLibres || !enScene)
        .scaleEffect(echelle)
        .opacity(enScene ? EcouteGeometrie.opacite(glisse: glisse) : 0)
        .offset(x: glisse, y: partie && !reduceMotion ? EcouteGeometrie.deriveSortie : 0)
        .animation(courbe, value: enScene)
        // Verrouillée d'un glissé vers le haut, elle revient à l'aplomb du bouton.
        .animation(reduceMotion ? nil : .kiwiVif, value: mainsLibres)
        // `duree` avance à chaque mesure du micro : c'est l'horloge de la trace.
        .onChange(of: speech.duree) { _, _ in
            guard ecoute else { return }
            historique = EcouteGeometrie.avancer(historique, avec: amplitude)
        }
        // La page remet le glissement à zéro en fermant la dictée : on garde
        // le dernier, pour que la bulle parte de là où elle était.
        .onChange(of: geste.glissement) { _, nouveau in
            if !partie { dernierGlisse = EcouteGeometrie.glisse(nouveau.width) }
        }
        .onChange(of: ecoute) { _, estActif in
            if !estActif { historique = Array(repeating: 0, count: KiwiMarque.nombreDeGraines) }
        }
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: EcouteGeometrie.arcDelai)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: EcouteGeometrie.arcDeploiement)) { arcDeploye = true }
            withAnimation(.linear(duration: EcouteGeometrie.arcTour).repeatForever(autoreverses: false)) {
                arcTourne = true
            }
        }
        .accessibilityLabel(mainsLibres ? "Terminer la dictée" : "Enregistrement en cours")
        .accessibilityHint(mainsLibres
                           ? "Lance l'analyse de ce que tu viens de dire"
                           : "Relâche pour lancer l'analyse")
    }

    /// L'arc : il naît en haut à droite, s'allonge, et tourne tant qu'on écoute.
    private var arc: some View {
        Circle()
            .trim(from: 0, to: arcDeploye ? EcouteGeometrie.arcPart : 0)
            .stroke(KiwiMarque.peau,
                    style: StrokeStyle(lineWidth: EcouteGeometrie.arcEpaisseur, lineCap: .round))
            .frame(width: EcouteGeometrie.diametre + 2 * EcouteGeometrie.arcEcart,
                   height: EcouteGeometrie.diametre + 2 * EcouteGeometrie.arcEcart)
            .rotationEffect(.degrees(EcouteGeometrie.arcDepart + (arcTourne ? 360 : 0)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - La tranche qui écoute

/// Le signe Kiwio, vivant : mêmes couleurs et mêmes rayons que `KiwiSigne`,
/// mais les graines s'allongent avec la voix et le cœur gonfle à peine. Au
/// silence, c'est exactement le logo.
private struct KiwiVivant: View {
    let historique: [CGFloat]
    let amplitude: CGFloat
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            DisqueVivant(rayon: EcouteGeometrie.rayonPeau).fill(KiwiMarque.peau)
            DisqueVivant(rayon: EcouteGeometrie.rayonChair).fill(KiwiMarque.chair)
            DisqueVivant(rayon: EcouteGeometrie.rayonHalo(amplitude: amplitude)).fill(KiwiMarque.halo)
            DisqueVivant(rayon: EcouteGeometrie.rayonCoeur(amplitude: amplitude)).fill(KiwiMarque.coeur)
            ForEach(0..<KiwiMarque.nombreDeGraines, id: \.self) { index in
                GraineVivante(index: index, amplitude: historique.indices.contains(index) ? historique[index] : 0)
                    .fill(KiwiMarque.peau)
            }
        }
        // 80 ms entre deux mesures du micro : les graines glissent de l'une à
        // l'autre au lieu de sauter.
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: historique)
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: amplitude)
        .accessibilityHidden(true)
    }
}

/// Un disque centré, de rayon donné dans la boîte de la tranche.
private struct DisqueVivant: Shape {
    var rayon: CGFloat

    var animatableData: CGFloat {
        get { rayon }
        set { rayon = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let unite = min(rect.width, rect.height) / EcouteGeometrie.boite
        return Path(ellipseIn: CGRect(x: rect.midX - rayon * unite, y: rect.midY - rayon * unite,
                                      width: 2 * rayon * unite, height: 2 * rayon * unite))
    }
}

/// Une graine posée sur son orbite, grand axe tourné vers le centre, qui
/// s'allonge vers le bord avec l'amplitude.
private struct GraineVivante: Shape {
    let index: Int
    var amplitude: CGFloat

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let unite = min(rect.width, rect.height) / EcouteGeometrie.boite
        let forme = EcouteGeometrie.graine(amplitude: amplitude)
        let angle = Double(index) * 2 * Double.pi / Double(KiwiMarque.nombreDeGraines)
        let largeur = KiwiMarque.graineLargeur * unite
        let longueur = forme.longueur * unite
        let ellipse = Path(ellipseIn: CGRect(x: -largeur / 2, y: -longueur / 2,
                                             width: largeur, height: longueur))
        let x = rect.midX + CGFloat(cos(angle)) * forme.orbite * unite
        let y = rect.midY + CGFloat(sin(angle)) * forme.orbite * unite
        return ellipse.applying(
            CGAffineTransform(translationX: x, y: y).rotated(by: CGFloat(angle + Double.pi / 2))
        )
    }
}
