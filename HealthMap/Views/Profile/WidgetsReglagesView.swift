import SwiftUI
import UIKit

// MARK: - Réglages : widgets et écran verrouillé
//
// iOS ne laisse pas une app poser un widget à la place de la personne : cette
// page montre ce qui existe, dit comment l'ajouter, et porte le seul réglage
// qui dépend de nous, la journée en direct sur l'écran verrouillé.
//
// Les aperçus sont les VRAIES vues des widgets (`Partage/`), nourries par la
// journée en cours quand elle existe, par un exemple sinon. On ne mélange
// jamais les deux : sans bilan, l'aperçu montre l'invitation que le widget
// montrerait, pas les chiffres de l'exemple.
//
// Widgets en verre (3 octobre 2026, maquette « Kiwio - Widgets ») : un widget
// d'accueil est posé comme iOS le pose, sur son verre (`FondVerreW`), avec
// 14 pt de marge et des coins de 22, à la taille d'un iPhone 16 (réduite en
// proportion sur un écran plus étroit). L'écran verrouillé est dessiné sur le
// fond d'écran de la maquette : ses accessoires et la carte de la journée sont
// blancs, ils ne se lisent que sur une image.

struct WidgetsReglagesView: View {
    @Environment(\.scenePhase) private var scenePhase
    /// Relus à l'apparition (`relire`) : la préférence et l'autorisation d'iOS.
    @State private var voulue = true
    @State private var autorisee = true
    @State private var etat: InstantaneJour = .exemple
    /// L'heure des aperçus : le repas proposé (« Ton midi ? ») la suit, comme
    /// sur l'écran d'accueil.
    @State private var maintenant = Date()

    private var allumee: Bool { voulue && autorisee }

    private var sousTitreActivite: String {
        if !autorisee { return "Désactivée pour Kiwio dans les réglages de l'iPhone" }
        return allumee
            ? "Tes repas, ton eau et ton rituel, sans déverrouiller"
            : "La carte de ta journée n'apparaît plus"
    }

    var body: some View {
        ZStack {
            VerrePageFond()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionVerrouille
                    sectionAccueil
                    sectionAjout
                }
                .padding(.horizontal, DS.marge)
                .padding(.bottom, DS.marge)
                .containerRelativeFrame(.horizontal)
            }
        }
        .kiwiTabBarBottomInset()
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .kiwiNavigationBarBackground()
        .onAppear { relire() }
        // Retour des réglages de l'iPhone : l'autorisation a pu changer.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { relire() }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var sectionVerrouille: some View {
        DSSectionHeader(titre: "Sur l'écran verrouillé")
            .padding(.top, -14)
        DSGroupedList { ligneActivite }
        apercu { ecranVerrouille }
            .padding(.top, DS.interCarte)
        legende("Ta journée en direct : les repas en une barre, les kcal restantes, la série ; un verre d'eau et la prise du moment se cochent sur place. Au-dessus, le conseil du jour, l'eau et ton apport à renforcer, posés en accessoires.")
    }

    @ViewBuilder
    private var sectionAccueil: some View {
        DSSectionHeader(titre: "Sur l'écran d'accueil")
        bloc("Tes apports. L'apport le plus juste en grand, les autres en anneaux : les mêmes chiffres que le Journal. « Voir le calcul » ouvre sa fiche.",
             sousLeTitre: true) {
            moyen { VueApportsMoyenne(etat: etat) }
        }
        bloc("Ajout rapide et Eau. Le micro ouvre Kiwio prêt à dicter le repas de l'heure ; le bouton de l'eau ajoute un verre sans ouvrir l'app.") {
            HStack(spacing: Self.entrePetits) {
                petit { VueAjoutPetite(etat: etat, maintenant: maintenant) }
                petit { VueEauPetite(etat: etat) }
            }
            .frame(maxWidth: Self.largeurMoyen)
            .frame(maxWidth: .infinity)
        }
        bloc("Conseil du jour. Un geste par jour pour ton apport à renforcer, pris dans sa fiche ; « C'est fait » se coche sans ouvrir l'app. Demain, un autre.") {
            moyen { VueConseilMoyenne(etat: etat) }
        }
        bloc("Rituel du jour. Matin, midi et soir, à cocher sur place. Aucune dose, comme dans l'app.") {
            moyen { VueRituelMoyenne(etat: etat) }
        }
        bloc("Ma journée. Les kcal du jour et tes quatre repas ; touche un repas pour y ajouter un aliment.") {
            moyen { VueJourneeMoyenne(etat: etat) }
        }
    }

    @ViewBuilder
    private var sectionAjout: some View {
        DSSectionHeader(titre: "Ajouter un widget")
        DSGroupedList {
            etape(1, "Appuie longuement sur ton écran d'accueil")
            DSSeparator(retrait: Self.retraitEtape)
            etape(2, "Touche Modifier, puis Ajouter un widget")
            DSSeparator(retrait: Self.retraitEtape)
            etape(3, "Cherche Kiwio et choisis ton widget")
        }
        legende("Sur l'écran verrouillé : appui long, Personnaliser, puis Ajouter des widgets. À partir d'iOS 18, « Dicter un repas » se pose aussi dans le Centre de contrôle et sur le bouton Action.")
    }

    // MARK: Journée en direct

    private var ligneActivite: some View {
        Toggle(isOn: Binding(
            get: { allumee },
            set: { basculer($0) }
        )) {
            HStack(spacing: 12) {
                ReglagePastille(symbole: "lock.iphone")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ma journée en direct")
                        .font(.dsCorps)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte)
                    Text(sousTitreActivite)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Color.dsAccent)
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 11)
        .frame(minHeight: ReglageMetrique.hauteurLigne)
    }

    // MARK: Étapes numérotées

    /// Début du texte d'une étape : 16 + 30 + 12.
    private static let retraitEtape: CGFloat = 58

    /// Une étape : la pastille numérotée de la maquette (rond vert pâle de
    /// 30 pt, chiffre 15 / 700 en vert foncé), puis la consigne.
    private func etape(_ numero: Int, _ texte: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(numero)")
                .font(.system(.subheadline, design: .default).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.teinteKiwiTexte)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.dsAccentPale))
            Text(texte)
                .font(.dsCorps)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: ReglageMetrique.hauteurLigne, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func basculer(_ allumer: Bool) {
        HapticService.shared.selection()
        // Coupée dans iOS : seule la personne peut rouvrir la porte.
        if allumer, !autorisee {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        ActiviteJournee.voulue = allumer
        voulue = allumer
        SynchroWidgets.rafraichir()
    }

    private func relire() {
        voulue = ActiviteJournee.voulue
        autorisee = ActiviteJournee.autorisee
        maintenant = Date()
        if let courant = BoiteCommune.etatAffiche(maintenant: maintenant), courant.connecte { etat = courant }
    }

    // MARK: Aperçus : mesures

    /// Un iPhone 16 (393 pt de large) : widget petit 158, moyen 338 × 158,
    /// 22 pt entre deux petits. Ce sont aussi les tailles de la planche CI.
    private static let largeurMoyen: CGFloat = 338
    private static let hauteurMoyen: CGFloat = 158
    private static let cotePetit: CGFloat = 158
    private static let entrePetits: CGFloat = 22
    /// Coins d'un widget d'accueil, comme iOS les arrondit.
    private static let rayonWidget: CGFloat = 22
    /// Entre une légende et l'aperçu suivant.
    private static let entreApercus: CGFloat = 20

    // MARK: Aperçus : écran d'accueil

    /// Un aperçu ne se touche pas (ses boutons agiraient pour de vrai) et ne
    /// se lit pas à VoiceOver : la légende qui le suit dit ce qu'il montre.
    private func apercu<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        contenu()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Un aperçu suivi de sa légende. `sousLeTitre` : le premier de sa
    /// section, collé à l'en-tête comme une carte.
    private func bloc<Apercu: View>(_ texte: String, sousLeTitre: Bool = false,
                                    @ViewBuilder _ contenu: () -> Apercu) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            apercu(contenu)
            legende(texte)
        }
        .padding(.top, sousLeTitre ? 0 : Self.entreApercus)
    }

    /// Le verre d'un widget d'accueil, tel que le bundle le pose : 14 pt de
    /// marge, `FondVerreW` en fond, coins de 22. `containerShape` donne au
    /// liseré du verre (`ContainerRelativeShape`) la forme du widget. Le verre
    /// est le même en mode clair et sombre : l'encre est toujours blanche.
    private func verre<Contenu: View>(_ contenu: Contenu) -> some View {
        let forme = RoundedRectangle(cornerRadius: Self.rayonWidget, style: .continuous)
        return contenu
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FondVerreW())
            .clipShape(forme)
            .containerShape(forme)
            .environment(\.colorScheme, .dark)
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
    }

    /// Un widget moyen : 338 × 158, centré ; plus étroit que la page, il garde
    /// ses proportions.
    private func moyen<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        verre(contenu())
            .aspectRatio(Self.largeurMoyen / Self.hauteurMoyen, contentMode: .fit)
            .frame(maxWidth: Self.largeurMoyen)
            .frame(maxWidth: .infinity)
    }

    /// Un petit widget : un carré de 158 au plus.
    private func petit<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        verre(contenu())
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: Self.cotePetit)
    }

    // MARK: Aperçus : écran verrouillé

    /// L'écran verrouillé en miniature (téléphone de la maquette, `phone-1`) :
    /// les accessoires sur une ligne, puis la carte de la journée. Les coins du
    /// fond suivent ceux de la carte (26 + 10 de marge).
    private var ecranVerrouille: some View {
        let forme = RoundedRectangle(cornerRadius: 36, style: .continuous)
        return VStack(spacing: 14) {
            accessoires
            VueActiviteJournee(etat: etat, maintenant: maintenant)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background { carteActivite }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background { FondEcranApercuReglagesW().clipShape(forme) }
        .environment(\.colorScheme, .dark)
    }

    /// Le conseil a besoin du bilan, l'eau d'être suivie, l'anneau d'un
    /// apport : un accessoire sans donnée n'est pas montré.
    private var montreConseil: Bool { etat.apports != nil }
    private var montreEau: Bool { etat.eau != nil }
    private var montreApport: Bool { etat.apports?.principal != nil }

    /// Les accessoires de la maquette : le conseil (rectangulaire), l'eau et
    /// l'apport à renforcer (ronds).
    @ViewBuilder
    private var accessoires: some View {
        if montreConseil || montreEau || montreApport {
            HStack(spacing: 10) {
                if montreConseil {
                    accessoireRectangulaire { VueConseilRectangulaire(etat: etat) }
                }
                if montreEau {
                    accessoireRond { VueEauRonde(etat: etat) }
                }
                if montreApport {
                    accessoireRond { VueApportsRonde(etat: etat) }
                }
            }
        }
    }

    /// Le fond d'un accessoire tel qu'iOS le dessine sur l'écran verrouillé
    /// (maquette : blanc 16 %, liseré blanc 25 %), dans la forme donnée.
    private func voileAccessoire<Forme: InsettableShape>(_ forme: Forme) -> some View {
        forme
            .fill(Color.white.opacity(0.16))
            .overlay(forme.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))
    }

    /// Un accessoire rond : 72 pt.
    private func accessoireRond<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        contenu()
            .frame(width: 72, height: 72)
            .background { voileAccessoire(Circle()) }
    }

    /// Un accessoire rectangulaire : 172 × 72 au plus, 9 pt et 12 pt de marge
    /// (maquette W6) ; il cède sa largeur aux ronds sur un écran étroit.
    private func accessoireRectangulaire<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        contenu()
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: 172, alignment: .leading)
            .frame(height: 72)
            .background { voileAccessoire(RoundedRectangle(cornerRadius: 18, style: .continuous)) }
    }

    /// La carte de l'activité en direct : verre sombre (`FondActiviteW`, la
    /// teinte que l'extension pose), coins de 26, liseré.
    private var carteActivite: some View {
        let forme = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return forme
            .fill(FondActiviteW.teinte)
            .overlay(forme.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6))
    }

    private func legende(_ texte: String) -> some View {
        Text(texte)
            .font(.dsLegende)
            .tracking(DSTracking.legende)
            .foregroundStyle(Color.dsSecondaire)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
            .padding(.horizontal, 4)
    }
}

// MARK: - Le fond d'écran de la maquette

/// Le fond d'écran sur lequel la maquette règle le verre (section « fond
/// d'écran ») : quatre taches de couleur sur un vert profond. Les taches sont
/// des ellipses proportionnées au cadre, comme les `radial-gradient` de la
/// maquette : position, rayons et point où la couleur s'éteint.
private struct FondEcranApercuReglagesW: View {
    var body: some View {
        GeometryReader { geo in
            let largeur = geo.size.width
            let hauteur = geo.size.height
            ZStack {
                LinearGradient(colors: [Color(hex: "4C8A4E"), Color(hex: "22574B")],
                               startPoint: .top, endPoint: .bottom)
                // Dans l'ordre inverse de la maquette : la première tache
                // listée est celle du dessus.
                tache(Color(hex: "7B6CC4"), x: 0.9 * largeur, y: 0.95 * hauteur,
                      rayonX: 0.8 * largeur, rayonY: 0.5 * hauteur, extinction: 0.6)
                tache(Color(hex: "F4A86E"), x: 0.2 * largeur, y: hauteur,
                      rayonX: 1.2 * largeur, rayonY: 0.7 * hauteur, extinction: 0.6)
                tache(Color(hex: "2E9C86"), x: largeur, y: 0.35 * hauteur,
                      rayonX: 0.9 * largeur, rayonY: 0.6 * hauteur, extinction: 0.62)
                tache(Color(hex: "A9DB78"), x: 0, y: 0,
                      rayonX: 1.2 * largeur, rayonY: 0.7 * hauteur, extinction: 0.55)
            }
        }
        .accessibilityHidden(true)
    }

    /// Une tache : pleine au centre, éteinte à `extinction` de ses rayons.
    /// Le dégradé elliptique remplit son cadre (fraction 0,5 = le bord) : on
    /// lui donne donc un cadre de deux rayons de côté.
    private func tache(_ couleur: Color, x: CGFloat, y: CGFloat,
                       rayonX: CGFloat, rayonY: CGFloat, extinction: CGFloat) -> some View {
        EllipticalGradient(colors: [couleur, couleur.opacity(0)],
                           center: .center,
                           startRadiusFraction: 0,
                           endRadiusFraction: 0.5 * extinction)
            .frame(width: 2 * rayonX, height: 2 * rayonY)
            .position(x: x, y: y)
    }
}
