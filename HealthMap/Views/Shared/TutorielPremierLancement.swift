import SwiftUI

// MARK: - Tutoriel du premier lancement (maquette « Kiwio - Tutoriel », 23 août 2026)
//
// Cinq gestes appris en trente secondes : le tutoriel ne raconte pas
// l'application, il FAIT FAIRE. À chaque étape, l'écran s'assombrit sauf la
// cible (voile 64 % découpé par `.blendMode(.destinationOut)`), une bulle dit
// quoi en attendre, et la personne touche la VRAIE commande — jamais un
// bouton « Suivant » factice. Elle apprend en produisant sa première donnée,
// ce qui règle du même coup l'écran vide.
//
// Règles de la maquette :
//   • « Passer » visible à chaque étape ;
//   • un seul geste attendu par étape ;
//   • le voile ne bloque que ce qui n'est pas la cible ;
//   • l'étape franchie se marque dans UserDefaults (reprise si l'app est tuée) ;
//   • relançable depuis Réglages.
//
// Les étapes 1, 2, 5 et 6 vivent en surcouche de MainTabView ; l'étape 3 dans
// la feuille d'ajout, l'étape 4 dans la feuille de dictée (chaque feuille est
// son propre arbre de vues, une surcouche racine ne la couvrirait pas).

// MARK: - Étapes et service

enum TutorielEtape: Int {
    case bienvenue = 1   // carte centrée, sans découpe
    case bouton          // découpe circulaire sur le « + » flottant
    case dicter          // dans la feuille d'ajout, découpe sur « Dicter mon repas »
    case verifier        // dans la feuille de dictée, bulle sans découpe
    case valeur          // découpe sur la carte « Apports à renforcer »
    case suite           // découpe sur la barre d'onglets + « J'ai compris »

    /// Position dans les points de progression (l'étape 1 n'en a pas :
    /// la carte de bienvenue porte ses propres boutons).
    var point: Int? {
        switch self {
        case .bienvenue: return nil
        case .bouton: return 0
        case .dicter: return 1
        case .verifier: return 2
        case .valeur: return 3
        case .suite: return 4
        }
    }
}

/// État du tutoriel, partagé entre MainTabView et les feuilles.
/// Persistance : 0 = jamais lancé · 1-6 = étape en cours · 7 = terminé.
@MainActor
final class TutorielService: ObservableObject {
    static let partage = TutorielService()

    @Published private(set) var etape: TutorielEtape?

    private let cle = "tutoriel.premier.etape"
    private var defauts: UserDefaults { .standard }

    private init() {}

    // MARK: Cycle de vie

    /// Armé depuis MainTabView quand le Journal est réellement à l'écran
    /// (bilan chargé, récap passé). `ancienTourVu` : les comptes qui ont déjà
    /// vu l'ancien tour d'onglets ne reçoivent pas le tutoriel d'office —
    /// il reste relançable depuis Réglages.
    func armer(ancienTourVu: Bool) {
        guard etape == nil else { return }
        let stocke = defauts.integer(forKey: cle)
        guard stocke < 7 else { return }
        if stocke == 0 {
            if ancienTourVu {
                defauts.set(7, forKey: cle)
                return
            }
            aller(.bienvenue)
        } else if let reprise = TutorielEtape(rawValue: stocke) {
            // Les étapes 3 et 4 vivent dans des feuilles fermées au
            // relancement : la reprise repart du bouton d'ajout.
            switch reprise {
            case .dicter, .verifier: aller(.bouton)
            default: aller(reprise)
            }
        }
    }

    /// « Passer », à n'importe quelle étape — ou « Plus tard » de la carte.
    func passer() { terminer() }

    func terminer() {
        etape = nil
        defauts.set(7, forKey: cle)
    }

    /// Réglages → « Revoir le tutoriel ».
    func relancer() { aller(.bienvenue) }

    #if DEBUG
    /// Captures d'écran (`-captureTutoriel`) : rejoue le tutoriel une seule
    /// fois par lancement, même marqué terminé. Absent du binaire App Store.
    private var relancePourCapturesFaite = false
    func relancerPourCaptures() {
        guard !relancePourCapturesFaite, etape == nil else { return }
        relancePourCapturesFaite = true
        aller(.bienvenue)
    }
    #endif

    // MARK: Événements du parcours (chacun ne réagit qu'à SON étape)

    func commencer() { if etape == .bienvenue { aller(.bouton) } }
    func plusTape() { if etape == .bouton { aller(.dicter) } }
    /// Feuille d'ajout refermée sans choisir : la découpe revient sur le « + ».
    func feuilleAjoutFermeeSansChoix() { if etape == .dicter { aller(.bouton) } }
    func dicterChoisi() { if etape == .dicter { aller(.verifier) } }
    func repasEnregistre() { if etape == .verifier { aller(.valeur) } }
    /// Dictée abandonnée (feuille fermée sans enregistrer) : on saute la
    /// valeur — elle n'existe pas sans repas — et on montre la suite.
    func dicteeAbandonnee() { if etape == .verifier { aller(.suite) } }
    func apportOuvert() { if etape == .valeur { aller(.suite) } }
    /// Changer d'onglet pendant « la suite », c'est déjà explorer : le
    /// tutoriel a fini son travail.
    func ongletChange() { if etape == .suite { terminer() } }

    private func aller(_ nouvelle: TutorielEtape) {
        withAnimation(.easeOut(duration: 0.22)) { etape = nouvelle }
        defauts.set(nouvelle.rawValue, forKey: cle)
    }
}

// MARK: - Ancres des cibles

enum TutorielCible: Hashable {
    case boutonAjout
    case carteApports
    case barreOnglets
    case tuileDicter
}

struct TutorielCibleKey: PreferenceKey {
    static var defaultValue: [TutorielCible: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TutorielCible: Anchor<CGRect>],
                       nextValue: () -> [TutorielCible: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, plusProche in plusProche }
    }
}

extension View {
    /// Déclare la vue comme cible possible du tutoriel.
    func cibleTutoriel(_ cible: TutorielCible) -> some View {
        anchorPreference(key: TutorielCibleKey.self, value: .bounds) { [cible: $0] }
    }

    /// Variante conditionnelle (une seule vue d'une liste est la cible).
    @ViewBuilder
    func cibleTutoriel(_ cible: TutorielCible, si condition: Bool) -> some View {
        if condition {
            cibleTutoriel(cible)
        } else {
            self
        }
    }
}

// MARK: - Voile découpé

/// Forme de la découpe posée sur la cible.
enum TutorielDecoupe {
    case cercle
    case arrondi(CGFloat)

    fileprivate func chemin(dans rect: CGRect) -> Path {
        switch self {
        case .cercle:
            let cote = max(rect.width, rect.height)
            let carre = CGRect(x: rect.midX - cote / 2, y: rect.midY - cote / 2,
                               width: cote, height: cote)
            return Path(ellipseIn: carre)
        case .arrondi(let rayon):
            return Path(roundedRect: rect, cornerRadius: rayon)
        }
    }
}

/// Le voile de la maquette : encre à 64 %, la cible restant nette et
/// touchable. Pas de calque troué au hit-testing : le visuel ignore les
/// touches, et quatre bloqueurs transparents entourent la découpe — le voile
/// ne bloque que ce qui n'est pas la cible.
struct TutorielVoile: View {
    /// Cadre de la cible dans le repère de la surcouche ; nil = voile plein.
    var trou: CGRect?
    var forme: TutorielDecoupe = .cercle
    /// Marge autour de la cible, pour que la découpe respire.
    var marge: CGFloat = 6

    private var trouElargi: CGRect? {
        trou?.insetBy(dx: -marge, dy: -marge)
    }

    var body: some View {
        GeometryReader { geo in
            let plein = CGRect(origin: .zero, size: geo.size)
            ZStack {
                // Visuel : voile + découpe (destinationOut dans un
                // compositingGroup, comme spécifié par la maquette).
                Rectangle()
                    .fill(Color(hex: "1C1C1E").opacity(0.64))
                    .overlay {
                        if let trouElargi {
                            forme.chemin(dans: trouElargi)
                                .fill(Color.black)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                    .allowsHitTesting(false)

                // Bloqueurs : tout sauf la découpe absorbe les touches.
                ForEach(Array(bloqueurs(autour: trouElargi, dans: plein).enumerated()),
                        id: \.offset) { _, zone in
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: zone.width, height: zone.height)
                        .position(x: zone.midX, y: zone.midY)
                        .onTapGesture {}
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Quatre rectangles autour du trou (ou un seul plein écran sans trou).
    private func bloqueurs(autour trou: CGRect?, dans plein: CGRect) -> [CGRect] {
        guard let trou = trou?.intersection(plein), !trou.isNull, !trou.isEmpty else { return [plein] }
        return [
            CGRect(x: 0, y: 0, width: plein.width, height: max(0, trou.minY)),
            CGRect(x: 0, y: trou.maxY, width: plein.width, height: max(0, plein.height - trou.maxY)),
            CGRect(x: 0, y: trou.minY, width: max(0, trou.minX), height: trou.height),
            CGRect(x: trou.maxX, y: trou.minY, width: max(0, plein.width - trou.maxX), height: trou.height),
        ].filter { $0.width > 0 && $0.height > 0 }
    }
}

// MARK: - Bulle

/// La bulle blanche de la maquette : points de progression + « Passer »,
/// titre 19/700, texte 15 secondaire, CTA capsule optionnel (dernière étape).
struct TutorielBulle: View {
    let etape: TutorielEtape
    let titre: String
    let texte: Text
    /// CTA plein (« J'ai compris ») ; nil = le geste attendu est sur l'écran.
    var actionTitre: String? = nil
    var action: (() -> Void)? = nil
    var onPasser: (() -> Void)? = nil

    private static let nombreDePoints = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if etape.point != nil || onPasser != nil {
                HStack(alignment: .center) {
                    if let actif = etape.point {
                        HStack(spacing: 5) {
                            ForEach(0..<Self.nombreDePoints, id: \.self) { index in
                                Capsule()
                                    .fill(index == actif ? Color.dsAccent : Color.dsTexte.opacity(0.22))
                                    .frame(width: index == actif ? 18 : 6, height: 6)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    Spacer(minLength: 8)
                    if let onPasser {
                        Button("Passer", action: onPasser)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.dsSecondaire)
                            .buttonStyle(.plain)
                    }
                }
            }

            Text(titre)
                .font(.system(size: 19, weight: .bold))
                .tracking(-0.45)
                .lineSpacing(2)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)

            texte
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)

            if let actionTitre, let action {
                Button(action: action) {
                    Text(actionTitre)
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Capsule().fill(Color.dsAccent))
                }
                .buttonStyle(.dsPress)
                .padding(.top, 14)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsCarte, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilitySortPriority(1)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Carte de bienvenue (étape 1)

struct TutorielCarteBienvenue: View {
    let onCommencer: () -> Void
    let onPlusTard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.dsAccentPale)
                    .frame(width: 56, height: 56)
                Image(systemName: "hand.tap")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.dsAccent)
                    .accessibilityHidden(true)
            }

            Text("Ton premier repas, maintenant")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.7)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Text("Cinq étapes pour dicter un plat et voir ce qu'il couvre de tes besoins. Tu peux arrêter quand tu veux.")
                .font(.system(size: 16))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Button(action: onCommencer) {
                Text("Commencer")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(Color.dsAccent))
            }
            .buttonStyle(.dsPress)
            .padding(.top, 20)

            Button(action: onPlusTard) {
                Text("Plus tard")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.dsSecondaire)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .background(Color.dsCarte, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilitySortPriority(1)
    }
}

// MARK: - Surcouche principale (étapes 1, 2, 5 et 6 — MainTabView)

/// Posée après la barre d'onglets pour la couvrir aussi. Les cibles arrivent
/// par `TutorielCibleKey` ; une cible absente de l'écran fait patienter la
/// surcouche (voile plein, sans bulle trompeuse).
struct TutorielOverlayPrincipal: View {
    @ObservedObject var service: TutorielService
    let ancres: [TutorielCible: Anchor<CGRect>]
    let proxy: GeometryProxy
    /// Les étapes qui montrent le Journal (bouton +, carte apports) ne se
    /// posent que lui à l'écran — les onglets restent tous montés, leurs
    /// ancres existent donc même hors écran.
    var journalVisible: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func cadre(_ cible: TutorielCible) -> CGRect? {
        ancres[cible].map { proxy[$0] }
    }

    var body: some View {
        if let etape = service.etape,
           journalVisible || etape == .bienvenue || etape == .suite {
            contenu(etape)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99)))
        }
    }

    @ViewBuilder
    private func contenu(_ etape: TutorielEtape) -> some View {
        switch etape {
        case .bienvenue:
            ZStack {
                TutorielVoile(trou: nil)
                TutorielCarteBienvenue(
                    onCommencer: { service.commencer() },
                    onPlusTard: { service.passer() }
                )
                .padding(.horizontal, 24)
            }

        case .bouton:
            let trou = cadre(.boutonAjout)
            ZStack(alignment: .bottom) {
                TutorielVoile(trou: trou, forme: .cercle, marge: 8)
                TutorielBulle(
                    etape: etape,
                    titre: "Tout part de ce bouton",
                    texte: Text("Dicter, scanner, chercher un produit : une seule porte d'entrée. Appuie dessus."),
                    onPasser: { service.passer() }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, distanceSousLaCible(trou, defaut: 190))
            }

        case .valeur:
            let trou = cadre(.carteApports)
            ZStack(alignment: .top) {
                TutorielVoile(trou: trou, forme: .arrondi(DS.rayonCarte), marge: 4)
                TutorielBulle(
                    etape: etape,
                    titre: "Voilà pourquoi tu es là",
                    texte: Text("Pas seulement des calories : ce que ton repas couvre de tes besoins. Touche une ligne pour savoir pourquoi elle est basse et comment la remonter."),
                    onPasser: { service.passer() }
                )
                .padding(.horizontal, 20)
                .padding(.top, max(12, (trou?.maxY ?? 120) + 12))
            }

        case .suite:
            let trou = cadre(.barreOnglets)
            ZStack(alignment: .bottom) {
                TutorielVoile(trou: trou, forme: .arrondi(32), marge: 4)
                TutorielBulle(
                    etape: etape,
                    titre: "Reviens demain",
                    texte: Text("Deux repas suivis et ")
                        + Text("Progrès").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.dsTexte)
                        + Text(" trace tes courbes. ")
                        + Text("Plan").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.dsTexte)
                        + Text(" te dira quoi changer, symptôme par symptôme."),
                    actionTitre: "J'ai compris",
                    action: { service.terminer() }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, distanceSousLaCible(trou, defaut: 120))
            }

        case .dicter, .verifier:
            // Ces étapes vivent dans leurs feuilles ; ici, rien à couvrir.
            EmptyView()
        }
    }

    /// Espace entre le bas de l'écran et la bulle pour qu'elle se pose
    /// au-dessus de la cible, jamais dessus.
    private func distanceSousLaCible(_ trou: CGRect?, defaut: CGFloat) -> CGFloat {
        guard let trou else { return defaut }
        // 36 pt : la découpe circulaire déborde du cadre de la cible
        // (côté = max(l, h) + 2 × marge), la bulle ne doit pas la chevaucher.
        return max(20, proxy.size.height - trou.minY + 36)
    }
}

// MARK: - Surcouche de la feuille d'ajout (étape 3)

struct TutorielOverlayAjout: View {
    @ObservedObject var service: TutorielService
    let ancres: [TutorielCible: Anchor<CGRect>]
    let proxy: GeometryProxy

    var body: some View {
        if service.etape == .dicter {
            let trou = ancres[.tuileDicter].map { proxy[$0] }
            ZStack(alignment: .bottom) {
                TutorielVoile(trou: trou, forme: .arrondi(22), marge: 6)
                TutorielBulle(
                    etape: .dicter,
                    titre: "Parle-lui comme à un ami",
                    texte: Text("Dis simplement : « ce midi, 150 g de poulet rôti, une assiette de pâtes et un yaourt ». Donne les quantités si tu les connais, sinon on te les demandera."),
                    onPasser: { service.passer() }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Bulle de la feuille de dictée (étape 4, sans voile)

/// La liste reste entièrement manipulable : la seule question posée (la
/// quantité manquante) est déjà mise en avant par la feuille elle-même.
struct TutorielBulleVerifier: View {
    @ObservedObject var service: TutorielService

    var body: some View {
        if service.etape == .verifier {
            TutorielBulle(
                etape: .verifier,
                titre: "On ne te demande que ce qui manque",
                texte: Text("Ce qui est identifié porte une coche verte. S'il reste une quantité à préciser, un appui suffit."),
                onPasser: { service.passer() }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .shadow(color: Color.black.opacity(0.10), radius: 18, y: 6)
            .transition(.opacity)
        }
    }
}
