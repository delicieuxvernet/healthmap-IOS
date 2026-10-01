import SwiftUI

// MARK: - La bulle d'écoute (maquette « Motion », 1er octobre 2026)
//
// « Dicter, être écouté, être félicité » : le bouton Dicter DEVIENT la bulle.
// Le rectangle de 22 pt de rayon s'étire en un cercle de 132 pt au bas de
// l'écran, pendant que toute l'interface recule à 0,94 derrière un voile flou.
// Tant qu'on parle, la bulle suit le niveau du micro (de 1 à 1,07), une aura
// liquide à trois harmoniques déborde derrière elle et cinq barres vivent sous
// le micro. La toucher termine : elle se contracte en indicateur de calcul et
// disparaît sous la feuille d'analyse qui monte.
//
// La scène vit à la RACINE (comme la gratification) : elle recouvre la barre
// d'onglets, et le Journal porte déjà trop de présentations. Le Journal garde
// toute la logique de la dictée et ne fait que déposer ici de quoi la montrer.
//
// Le bouton d'origine n'est jamais retiré de la page (seulement masqué) : un
// appui maintenu garde donc son geste vivant sous la bulle.
//
// « Réduire les animations » : pas de trajet ni d'aura, un fondu de 0,2 s, la
// bulle ne respire pas. Les barres bougent encore : elles disent qu'on écoute.

// MARK: Géométrie

enum EcouteGeometrie {
    /// Diamètre de la bulle d'écoute.
    static let diametre: CGFloat = 132
    /// Rayon du bouton « Dicter » d'où elle part.
    static let rayonBouton: CGFloat = 22
    /// Distance du centre de la bulle au bas de la zone sûre.
    static let hauteurDuCentre: CGFloat = 176
    /// Côté du carré dans lequel l'aura se dessine.
    static let coteAura: CGFloat = 260
    /// La bulle contractée en indicateur de calcul.
    static let contraction: CGFloat = 0.42

    /// Où la bulle se pose, dans une surcouche de cette taille.
    static func cadreBulle(dans taille: CGSize) -> CGRect {
        CGRect(x: taille.width / 2 - diametre / 2,
               y: taille.height - hauteurDuCentre - diametre / 2,
               width: diametre,
               height: diametre)
    }

    /// Échelle de la bulle pour un niveau de micro 0…1 : de 1 à 1,07. Une voix
    /// normale doit déjà la faire respirer, d'où le rehaussement.
    static func echelle(niveau: Float) -> CGFloat {
        let borne = CGFloat(min(1, max(0, niveau * 1.6)))
        return 1 + (KiwiEchelle.voix - 1) * borne
    }

    /// Rayon de l'aura dans une direction : un cercle déformé par trois
    /// harmoniques qui tournent à des vitesses différentes. `vigueur` = la part
    /// du rayon que la déformation peut prendre.
    static func rayonAura(base: CGFloat, angle: Double, temps: Double, vigueur: CGFloat) -> CGFloat {
        let premiere = sin(angle * 2 + temps * 1.3) * 0.5
        let deuxieme = sin(angle * 3 - temps * 1.9) * 0.3
        let troisieme = sin(angle * 5 + temps * 2.6) * 0.2
        let onde = CGFloat(premiere + deuxieme + troisieme)
        return base * (1 + vigueur * onde)
    }

    static func contourAura(centre: CGPoint, base: CGFloat, temps: Double, vigueur: CGFloat) -> Path {
        var chemin = Path()
        let pas = 72
        for index in 0...pas {
            let angle = Double(index) / Double(pas) * 2 * Double.pi
            let rayon = rayonAura(base: base, angle: angle, temps: temps, vigueur: vigueur)
            let point = CGPoint(x: centre.x + CGFloat(cos(angle)) * rayon,
                                y: centre.y + CGFloat(sin(angle)) * rayon)
            if index == 0 {
                chemin.move(to: point)
            } else {
                chemin.addLine(to: point)
            }
        }
        chemin.closeSubpath()
        return chemin
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
        /// La bulle a la main.
        case ecoute
        /// Fin d'écoute : la bulle se contracte, la feuille d'analyse monte.
        case calcul
        /// Dictée jetée ou trop courte : la bulle redevient le bouton.
        case retour
    }

    @Published private(set) var phase: Phase = .repos
    /// Mains libres : on touche la bulle pour terminer. Sinon le doigt tient le
    /// bouton, et le lever lance l'analyse.
    @Published private(set) var mainsLibres = true
    /// Le bouton de la page s'efface tant que la bulle porte sa forme.
    @Published private(set) var boutonCache = false

    private(set) var speech: SpeechCaptureService?
    private(set) var geste: GesteDictee?
    private var terminer: () -> Void = {}
    private var annuler: () -> Void = {}
    private var rangement: Task<Void, Never>?

    /// Le temps laissé à la bulle pour finir son trajet avant de quitter l'écran.
    static let sortie: Duration = .milliseconds(520)

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

    /// Fin d'écoute réussie : la bulle se contracte, la feuille prend le relais.
    func contracter() {
        guard phase == .ecoute else { return }
        phase = .calcul
        boutonCache = false
        ranger()
    }

    /// Dictée jetée ou trop courte : la bulle retourne dans son bouton.
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
            try? await Task.sleep(for: Self.sortie)
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

// MARK: - Le recul de la page

/// Toute l'interface recule à 0,94 quand la bulle prend la main, et revient
/// quand elle la rend. Seul ce modificateur suit le relais : la racine, elle,
/// n'est pas réévaluée.
struct ReculSousLaBulle: ViewModifier {
    @ObservedObject private var centre = EcouteCentre.partage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let recule = centre.phase == .ecoute
        content
            .scaleEffect(recule && !reduceMotion ? KiwiEchelle.recul : 1)
            .animation(reduceMotion ? nil : .kiwiFluide, value: recule)
            .background(Color.dsFond.ignoresSafeArea())
    }
}

// MARK: - La surcouche (posée par la racine)

struct EcouteSurcouche: View {
    /// Cadre du bouton « Dicter » dans le repère de la surcouche.
    let cadreBouton: CGRect?
    let taille: CGSize

    @ObservedObject private var centre = EcouteCentre.partage
    /// Le cadre du bouton AVANT que la page ne recule : c'est de là que la
    /// bulle part, et là qu'elle revient.
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
                            depart: cadreAuRepos, taille: taille)
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
    let depart: CGRect?
    let taille: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// La bulle a quitté la forme du bouton.
    @State private var ouverte = false
    /// Fin d'écoute : la bulle se contracte en indicateur de calcul.
    @State private var contractee = false
    /// Contractée, elle s'efface sous la feuille qui monte.
    @State private var effacee = false

    private var cible: CGRect { EcouteGeometrie.cadreBulle(dans: taille) }

    /// Le cadre de la bulle à cet instant. Sous « Réduire les animations »,
    /// aucun trajet : elle est déjà à sa place.
    private var cadre: CGRect {
        guard !reduceMotion, !ouverte, let depart else { return cible }
        return depart
    }

    /// La scène est installée et on écoute encore.
    private var enScene: Bool { ouverte && centre.phase == .ecoute }

    private var courbe: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .kiwiFluide
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Le voile : la page recule derrière lui.
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(enScene ? 1 : 0)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            // Plus rien n'est touchable derrière la scène, jusqu'à sa sortie.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            entete

            BulleVivante(
                speech: speech,
                geste: geste,
                ouverte: ouverte,
                contractee: contractee,
                mainsLibres: centre.mainsLibres,
                reduceMotion: reduceMotion,
                onToucher: { centre.toucherLaBulle() }
            )
            .frame(width: cadre.width, height: cadre.height)
            .opacity(effacee ? 0 : 1)
            .position(x: cadre.midX, y: cadre.midY)

            pied
        }
        .frame(width: taille.width, height: taille.height)
        .opacity(reduceMotion && !enScene ? 0 : 1)
        .animation(courbe, value: centre.phase)
        .animation(courbe, value: centre.mainsLibres)
        .onAppear {
            withAnimation(courbe) { ouverte = true }
        }
        .onChange(of: centre.phase) { _, phase in
            switch phase {
            case .retour:
                withAnimation(courbe) { ouverte = false }
            case .calcul:
                withAnimation(courbe) { contractee = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(240))
                    withAnimation(.easeOut(duration: 0.2)) { effacee = true }
                }
            case .repos, .ecoute:
                break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Ce qui se lit au-dessus de la bulle

    private var entete: some View {
        VStack(spacing: 8) {
            Text("Kiwio t'écoute")
                .font(.system(.title2, design: .default).weight(.bold))
                .tracking(-0.6)
                .foregroundStyle(Color.dsTexte)
                .accessibilityAddTraits(.isHeader)
            MinuteurEcoute(speech: speech)
            Text("Dis ce que tu as mangé, avec les quantités…")
                .font(.dsCorps)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.horizontal, 32)
        .frame(width: taille.width)
        .opacity(enScene ? 1 : 0)
        .offset(y: enScene || reduceMotion ? 0 : 12)
        .position(x: taille.width / 2, y: taille.height * 0.26)
    }

    // MARK: Ce qui se lit sous la bulle

    private var pied: some View {
        VStack(spacing: 2) {
            Text(centre.mainsLibres ? "Touche la bulle pour terminer" : "Relâche pour lancer l'analyse")
                .font(.dsSousTitreMoyen)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)

            if centre.mainsLibres {
                Button {
                    HapticService.shared.tap()
                    centre.toucherAnnuler()
                } label: {
                    Text("Annuler")
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .padding(.horizontal, 18)
                        .frame(minHeight: DS.cibleTactile)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel("Jeter la dictée")
            } else {
                Text("Glisse à gauche pour annuler, vers le haut pour lâcher le bouton.")
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: DS.cibleTactile)
            }
        }
        .padding(.horizontal, 32)
        .frame(width: taille.width)
        .opacity(enScene ? 1 : 0)
        .position(x: taille.width / 2, y: taille.height - 52)
    }
}

// MARK: - Le minuteur (seul, avec la bulle, à suivre le micro)

private struct MinuteurEcoute: View {
    @ObservedObject var speech: SpeechCaptureService

    var body: some View {
        HStack(spacing: 7) {
            PointEnregistrement()
            Text(String(format: "%d:%02d", Int(speech.duree) / 60, Int(speech.duree) % 60))
                .font(.system(.subheadline, design: .default).weight(.medium).monospacedDigit())
                .foregroundStyle(Color.dsSecondaire)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Enregistrement en cours")
    }
}

// MARK: - La bulle

/// Vue SÉPARÉE, et c'est le point : avec le minuteur, elle est la seule à
/// observer `speech` (niveau sonore, 20 Hz) et `geste` (glissement du doigt,
/// 120 Hz). Ni la scène ni la racine ne sont réinvalidées à ce rythme.
private struct BulleVivante: View {
    @ObservedObject var speech: SpeechCaptureService
    @ObservedObject var geste: GesteDictee
    let ouverte: Bool
    let contractee: Bool
    let mainsLibres: Bool
    let reduceMotion: Bool
    let onToucher: () -> Void

    /// L'arc de l'indicateur de calcul tourne.
    @State private var tourne = false

    private var ecoute: Bool { speech.state == .listening }

    /// La bulle respire avec la voix : de 1 à 1,07.
    private var echelleVoix: CGFloat {
        guard ouverte, !contractee, !reduceMotion, ecoute else { return 1 }
        return EcouteGeometrie.echelle(niveau: speech.level)
    }

    private var rayon: CGFloat {
        ouverte ? EcouteGeometrie.diametre / 2 : EcouteGeometrie.rayonBouton
    }

    /// Appui maintenu : la bulle suit le doigt vers la gauche et s'estompe à
    /// l'approche du seuil, on sent l'annulation venir.
    private var glisse: CGFloat {
        guard !mainsLibres else { return 0 }
        return max(DicteeGeste.seuilAnnulation, min(0, geste.glissement.width))
    }

    var body: some View {
        Button(action: onToucher) {
            ZStack {
                FondBoutonDicter(rayon: rayon)

                // La face du bouton, tant qu'il n'est pas devenu bulle.
                FaceBoutonDicter()
                    .opacity(ouverte ? 0 : 1)

                VStack(spacing: 9) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(.white)
                    BarresDeVoix(level: speech.level, active: ecoute)
                }
                .opacity(ouverte && !contractee ? 1 : 0)
                .rotationEffect(.degrees(contractee ? 90 : 0))

                // Contractée, elle devient l'indicateur de calcul.
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .padding(34)
                    .rotationEffect(.degrees(tourne ? 360 : 0))
                    .opacity(contractee ? 1 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .disabled(!mainsLibres || !ouverte || contractee)
        .scaleEffect(echelleVoix)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: echelleVoix)
        .scaleEffect(contractee ? EcouteGeometrie.contraction : 1)
        .background { aura }
        .offset(x: glisse)
        .opacity(Double(max(0.25, 1 + glisse / 140)))
        .onChange(of: contractee) { _, maintenant in
            guard maintenant, !reduceMotion else { return }
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { tourne = true }
        }
        .accessibilityLabel(mainsLibres ? "Terminer la dictée" : "Enregistrement en cours")
        .accessibilityHint(mainsLibres
                           ? "Lance l'analyse de ce que tu viens de dire"
                           : "Relâche pour lancer l'analyse")
    }

    @ViewBuilder
    private var aura: some View {
        if ouverte, !contractee, !reduceMotion {
            AuraLiquide(niveau: speech.level, active: ecoute)
                .transition(.opacity)
        }
    }
}

// MARK: - L'aura liquide

/// Deux nappes vertes qui ondulent derrière la bulle. Leur rayon et leur
/// agitation suivent le NIVEAU SONORE mesuré : quand on parle, ça déborde ;
/// quand on se tait, ça retombe. Aucune boucle décorative.
private struct AuraLiquide: View {
    let niveau: Float
    let active: Bool

    private var amplitude: CGFloat {
        guard active else { return 0 }
        return CGFloat(min(1, max(0, niveau * 1.6)))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { contexte in
            let temps = contexte.date.timeIntervalSinceReferenceDate
            let force = amplitude
            Canvas { dessin, taille in
                let centre = CGPoint(x: taille.width / 2, y: taille.height / 2)
                let proche = EcouteGeometrie.contourAura(
                    centre: centre,
                    base: EcouteGeometrie.diametre / 2 + 8 + force * 12,
                    temps: temps,
                    vigueur: 0.04 + force * 0.07
                )
                let lointaine = EcouteGeometrie.contourAura(
                    centre: centre,
                    base: EcouteGeometrie.diametre / 2 + 20 + force * 18,
                    temps: temps + 1.7,
                    vigueur: 0.05 + force * 0.08
                )
                dessin.fill(lointaine, with: .color(Color.dsAccent.opacity(0.14)))
                dessin.fill(proche, with: .color(Color.dsAccent.opacity(0.24)))
            }
        }
        .frame(width: EcouteGeometrie.coteAura, height: EcouteGeometrie.coteAura)
        .blur(radius: 5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Cinq barres sous le micro

/// Les cinq derniers niveaux du micro, de gauche à droite : la trace de la
/// voix, pas une animation en boucle.
private struct BarresDeVoix: View {
    let level: Float
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var historique: [CGFloat] = Array(repeating: 0, count: BarresDeVoix.nombre)

    private static let nombre = 5
    private static let poids: [CGFloat] = [0.6, 0.85, 1, 0.85, 0.6]
    private static let hauteurMin: CGFloat = 6
    private static let course: CGFloat = 20

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<Self.nombre, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 4, height: hauteur(index))
            }
        }
        .frame(height: Self.hauteurMin + Self.course)
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: historique)
        .onChange(of: level) { _, nouveau in
            guard active else { return }
            historique.removeFirst()
            historique.append(CGFloat(min(1, max(0, nouveau * 1.6))))
        }
        .onChange(of: active) { _, estActif in
            if !estActif { historique = Array(repeating: 0, count: Self.nombre) }
        }
        .accessibilityHidden(true)
    }

    private func hauteur(_ index: Int) -> CGFloat {
        Self.hauteurMin + historique[index] * Self.poids[index] * Self.course
    }
}
