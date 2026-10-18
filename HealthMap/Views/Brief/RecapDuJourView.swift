import SwiftUI
import UIKit
import CoreMotion

// MARK: - Récap du jour (maquette v5.1 validée le 7 oct. 2026)
//
// « Hier, il te manquait » → deux sphères de verre où le liquide monte au
// pourcentage d'hier → « Ajoute aujourd'hui » → deux aliments en 3D qui
// flottent, pendant qu'un second liquide, translucide, monte jusqu'au niveau
// atteint avec une portion → « C'est parti ». Rien à toucher : l'écran arrive
// d'un coup, dans l'ordre de la maquette.
//
// Une seule horloge (`TimelineView`) pilote tout : liquides, compteurs, reflet,
// flottement et parallaxe. Deux horloges (une animation SwiftUI pour le chiffre,
// un `Canvas` pour le liquide) se désynchroniseraient. Sous « Réduire les
// animations », tout est posé à sa valeur finale, sans mouvement.
//
// Écarts voulus avec la maquette (accessibilité validée le 9 oct. 2026) : le
// bouton est le vert profond du design system, le gris secondaire est à 80 %,
// les graisses s'arrêtent à 700.

struct RecapDuJourView: View {
    let recap: RecapDuJour
    /// L'invitation aux notifications suit « C'est parti » quand elle est due.
    let proposerInvitation: Bool
    let cibleInvitation: CibleNutritionnelle?
    /// « Ajouter mes repas d'hier » : le journal s'ouvre sur la veille.
    let onAjouterHier: () -> Void
    let onTerminer: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var debut = Date()
    @State private var choregraphieFinie = false
    @State private var enInvitation = false
    @State private var demandeEnCours = false
    /// Les capteurs comptent leurs lecteurs : on ne s'inscrit qu'une fois.
    @State private var litLInclinaison = false

    /// Sous « Réduire les animations », tout est posé à sa valeur finale.
    private var fige: Bool { reduceMotion }
    /// En arrière-plan, l'horloge s'arrête. Pas pendant la phase « inactive »
    /// du lancement : le récap s'ouvre souvent à ce moment-là, et montrer
    /// l'état final avant de rejouer l'animation ferait clignoter l'écran.
    private var enPause: Bool { fige || scenePhase == .background }

    var body: some View {
        ZStack {
            VerreFond(teinte: .aube)

            if enInvitation {
                ScrollView {
                    InvitationNotificationsContenu(
                        cible: cibleInvitation,
                        demandeEnCours: demandeEnCours,
                        onAccepter: accepterNotifications,
                        onPlusTard: {
                            BriefDuJourStore.repousserInvitation()
                            terminer(raison: "notifs_plus_tard")
                        }
                    )
                    .padding(.horizontal, DS.marge)
                    .padding(.vertical, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
                .transition(.opacity)
            } else {
                // Après la chorégraphie, il ne reste que le flottement, la
                // vague et la parallaxe : 30 images par seconde suffisent.
                TimelineView(.animation(minimumInterval: choregraphieFinie ? 1.0 / 30 : 1.0 / 60, paused: enPause)) { horloge in
                    let t = fige ? RecapChoregraphie.final : horloge.date.timeIntervalSince(debut)
                    let inclinaison = fige ? CGPoint.zero : InclinaisonTelephone.partage.lire()
                    ecran(t: t, inclinaison: inclinaison)
                }
            }
        }
        .overlay(alignment: .topLeading) { croix }
        .simultaneousGesture(
            DragGesture(minimumDistance: 60).onEnded { valeur in
                guard valeur.translation.height > 80, abs(valeur.translation.width) < 60 else { return }
                terminer(raison: "glisser")
            }
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: enInvitation)
        .accessibilityAction(.escape) { terminer(raison: "echap") }
        .dynamicTypeSize(.large ... .accessibility3)
        .onAppear {
            debut = Date()
            suivreInclinaison(!reduceMotion)
            AnalyticsService.shared.track(.screenViewed, properties: [
                "screen": "brief_du_jour",
                "slides": 1,
                "cas": nomDuCas,
                "colonnes": nombreDeColonnes,
            ])
        }
        .onDisappear { suivreInclinaison(false) }
        // En arrière-plan, les capteurs s'arrêtent ; au retour, le zéro se
        // recale sur la tenue du téléphone à ce moment-là.
        .onChange(of: scenePhase) { _, phase in
            suivreInclinaison(!reduceMotion && phase != .background)
        }
        .task {
            try? await Task.sleep(for: .seconds(RecapChoregraphie.final))
            choregraphieFinie = true
        }
    }

    private func suivreInclinaison(_ lire: Bool) {
        guard lire != litLInclinaison else { return }
        litLInclinaison = lire
        if lire {
            InclinaisonTelephone.partage.demarrer()
        } else {
            InclinaisonTelephone.partage.arreter()
        }
    }

    // MARK: - L'écran

    private func ecran(t: Double, inclinaison: CGPoint) -> some View {
        VStack(spacing: 12) {
            ScrollView {
                Group {
                    switch recap.cas {
                    case .manques(let colonnes):
                        manques(colonnes, t: t, inclinaison: inclinaison)
                    case .rienHier(let repas):
                        centre(t: t, inclinaison: inclinaison,
                               titre: repas == 0 ? String(localized: "Rien de noté hier") : String(localized: "Un seul repas noté hier"),
                               texte: String(localized: "Ajoute tes repas d'hier pour voir ce qui t'a manqué."),
                               sphereVerte: false)
                    case .rienNaManque:
                        centre(t: t, inclinaison: inclinaison,
                               titre: String(localized: "Rien n'a manqué hier"),
                               texte: String(localized: "Tes apports ont tous passé 70 %. Refais pareil aujourd'hui."),
                               sphereVerte: true)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 58)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            bouton
                .padding(.horizontal, 22)
                .apparition(t, delai: estCentre ? 0.9 : RecapChoregraphie.bouton)
                .padding(.bottom, 8)
        }
    }

    private func manques(_ colonnes: [RecapDuJour.Colonne], t: Double, inclinaison: CGPoint) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            surtitre.apparition(t, delai: 0.05)
            titre(String(localized: "Hier, il te manquait"))
                .padding(.top, 4)
                .padding(.bottom, 22)
                .apparition(t, delai: 0.15)

            DSLigneOuColonne(alignementLigne: .top, alignementColonne: .center, espacement: 12) {
                ForEach(Array(colonnes.enumerated()), id: \.element.id) { rang, colonne in
                    colonneVue(colonne, rang: rang, t: t, inclinaison: inclinaison)
                        .frame(maxWidth: .infinity)
                }
            }

            if colonnes.contains(where: { $0.aliment != nil }) {
                titre(String(localized: "Ajoute aujourd'hui"))
                    .padding(.top, 26)
                    .padding(.bottom, 16)
                    .apparition(t, delai: RecapChoregraphie.aliments - 0.25)

                DSLigneOuColonne(alignementLigne: .top, alignementColonne: .center, espacement: 12) {
                    ForEach(Array(colonnes.enumerated()), id: \.element.id) { rang, colonne in
                        Group {
                            if let aliment = colonne.aliment {
                                alimentVue(aliment, colonne: colonne, rang: rang, t: t)
                            } else {
                                Color.clear.frame(height: 1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// Une colonne : le nom de l'apport, sa sphère, le chiffre d'hier qui
    /// compte avec le liquide.
    private func colonneVue(_ colonne: RecapDuJour.Colonne, rang: Int, t: Double, inclinaison: CGPoint) -> some View {
        let depart = RecapChoregraphie.colonnes + RecapChoregraphie.decalage * Double(rang)
        let niveau = Double(colonne.pourcentHier) * RecapChoregraphie.liquide(t, rang: rang)
        let ajout = colonne.projection.map { Double($0) * RecapChoregraphie.ajout(t, rang: rang) }
        return VStack(spacing: 0) {
            Text(colonne.nom)
                .dsPolice(15, .bold)
                .tracking(-0.2)
                .foregroundStyle(Color.teinteApportTexte(for: colonne.id))
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
                .apparition(t, delai: depart)

            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(Color(red: 40 / 255, green: 30 / 255, blue: 20 / 255).opacity(0.16))
                    .frame(width: 76, height: 10)
                    .blur(radius: 5)
                    .offset(y: 6)
                SphereRecapVue(
                    teinte: Color.nutrientColor(for: colonne.id),
                    niveau: niveau,
                    niveauAjout: ajout,
                    balayage: RecapChoregraphie.balayage(t, rang: rang),
                    temps: t,
                    rang: rang,
                    inclinaison: inclinaison
                )
                .frame(width: 136, height: 136)
            }
            .apparition(t, delai: depart + 0.05)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(DS.entier(Int(niveau.rounded())))
                    .dsPolice(40, .bold, design: .rounded, chiffres: true)
                    .tracking(-1.6)
                    .foregroundStyle(Color.dsTexte)
                Text("%")
                    .dsPolice(20, .semibold)
                    .foregroundStyle(Color.dsSecondaire)
            }
            .dynamicTypeSize(.large ... .accessibility2)
            .padding(.top, 16)
            .apparition(t, delai: depart + 0.15)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(colonne.nom) : \(colonne.pourcentHier) % de ton besoin couvert hier.")
    }

    /// L'aliment à ajouter : son illustration flotte, son nom, et le gain
    /// d'une portion quand il est chiffré.
    private func alimentVue(_ aliment: RecapDuJour.Aliment, colonne: RecapDuJour.Colonne, rang: Int, t: Double) -> some View {
        let flotte = reduceMotion ? 0 : RecapChoregraphie.flottement(t, rang: rang)
        return VStack(spacing: 0) {
            illustration(aliment.illustration, taille: 92)
                .offset(y: -6 * flotte)
            Ellipse()
                .fill(Color(red: 40 / 255, green: 30 / 255, blue: 20 / 255).opacity(0.18 * (1 - 0.45 * flotte)))
                .frame(width: 60 * (1 - 0.2 * flotte), height: 9)
                .blur(radius: 4)
                .padding(.top, 4)
            Text(aliment.nom)
                .dsPolice(22, .bold)
                .tracking(-0.6)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            if let gain = aliment.gain {
                Text(gain >= 100 ? String(localized: "Tout ton besoin du jour") : String(localized: "+\(DS.pourcent(gain)) de ton besoin"))
                    .dsPolice(14, .bold)
                    .foregroundStyle(Color.teinteApportTexte(for: colonne.id))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            if let portion = aliment.portion {
                Text("pour \(portion)")
                    .dsPolice(13)
                    .foregroundStyle(Color.dsSecondaire)
                    .padding(.top, 1)
            }
        }
        .apparition(t, delai: RecapChoregraphie.aliments + RecapChoregraphie.decalage * Double(rang))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleAliment(aliment, colonne: colonne))
    }

    /// Rien de noté hier, ou rien n'a manqué : un seul visuel centré.
    private func centre(t: Double, inclinaison: CGPoint, titre texteTitre: String, texte: String, sphereVerte: Bool) -> some View {
        VStack(spacing: 0) {
            surtitre
                .frame(maxWidth: .infinity, alignment: .leading)
                .apparition(t, delai: 0.05)
            Spacer(minLength: 60)
            Group {
                if sphereVerte {
                    SphereRecapVue(
                        teinte: Color.teinteKiwi,
                        niveau: 100 * RecapChoregraphie.quart(RecapChoregraphie.progression(t, depart: 0.6, duree: 1.6)),
                        niveauAjout: nil,
                        balayage: RecapChoregraphie.progression(t, depart: 1.6, duree: 1.6),
                        temps: t,
                        rang: 0,
                        inclinaison: inclinaison
                    )
                    .frame(width: 136, height: 136)
                } else {
                    illustration(Fluent3D.plate, taille: 100)
                }
            }
            .padding(.bottom, 26)
            .apparition(t, delai: 0.3)
            titre(texteTitre)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
                .apparition(t, delai: 0.5)
            Text(texte)
                .dsPolice(17, .semibold)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .apparition(t, delai: 0.65)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Briques

    private var surtitre: some View {
        Text("RÉCAP DU JOUR")
            .dsPolice(13, .bold)
            .tracking(0.6)
            .foregroundStyle(Color.dsSecondaire)
    }

    private func titre(_ texte: String) -> some View {
        Text(texte)
            .font(.dsGrandTitre)
            .tracking(DSTracking.grandTitre)
            .foregroundStyle(Color.dsTexte)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func illustration(_ nom: String?, taille: CGFloat) -> some View {
        let asset = nom.flatMap { UIImage(named: $0) == nil ? nil : $0 } ?? Fluent3D.plate
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(width: taille, height: taille)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var bouton: some View {
        switch recap.cas {
        case .rienHier:
            DSCapsuleButton(titre: String(localized: "Ajouter mes repas d'hier"), hauteur: Verre.hauteurAction) {
                AnalyticsService.shared.track(.screenViewed, properties: ["screen": "brief_ajouter_hier"])
                onAjouterHier()
            }
        case .manques, .rienNaManque:
            DSCapsuleButton(titre: String(localized: "C'est parti"), hauteur: Verre.hauteurAction, action: cestParti)
        }
    }

    private var croix: some View {
        Button {
            terminer(raison: "croix")
        } label: {
            // Rond de verre clair de 36 pt, cible de 44 pt.
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Verre.iconeNeutre)
                .frame(width: 36, height: 36)
                .verreClair(Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("Fermer le récap du jour")
        .padding(.leading, 12)
        .padding(.top, 6)
    }

    private var estCentre: Bool {
        if case .manques = recap.cas { return false }
        return true
    }

    private var nomDuCas: String {
        switch recap.cas {
        case .manques: return "manques"
        case .rienHier: return "rien_hier"
        case .rienNaManque: return "rien_n_a_manque"
        }
    }

    private var nombreDeColonnes: Int {
        if case .manques(let colonnes) = recap.cas { return colonnes.count }
        return 0
    }

    private func libelleAliment(_ aliment: RecapDuJour.Aliment, colonne: RecapDuJour.Colonne) -> String {
        let possessif = NomNutriment.possessif(id: colonne.id, nom: colonne.nom)
        if let portion = aliment.portion, let projection = colonne.projection {
            return String(localized: "À ajouter aujourd'hui pour \(possessif) : \(aliment.nom), \(portion). Tu passerais à \(projection) % de ton besoin.")
        }
        return String(localized: "À ajouter aujourd'hui pour \(possessif) : \(aliment.nom).")
    }

    // MARK: - Actions

    private func cestParti() {
        guard proposerInvitation else {
            terminer(raison: "fin")
            return
        }
        enInvitation = true
    }

    private func accepterNotifications() {
        Task {
            demandeEnCours = true
            let accorde = await PushNotificationService.shared.requestAuthorizationIfNeeded()
            if accorde { await RappelsPersonnalises.replanifier() }
            demandeEnCours = false
            terminer(raison: accorde ? "notifs_acceptees" : "notifs_refusees_ios")
        }
    }

    private func terminer(raison: String) {
        AnalyticsService.shared.track(.screenViewed, properties: [
            "screen": "brief_du_jour_ferme",
            "raison": raison,
            "cas": nomDuCas,
        ])
        onTerminer()
    }
}

// MARK: - Chorégraphie (horaires de la maquette v5.1)

enum RecapChoregraphie {
    /// Les sphères apparaissent à 0,5 s, les aliments à 2,1 s, le bouton à 3,3 s.
    static let colonnes = 0.5
    static let aliments = 2.1
    static let bouton = 3.3
    /// Décalage entre la première et la seconde colonne.
    static let decalage = 0.22
    /// Tout est posé : l'état final, celui qu'on montre sans animation.
    static let final = 4.6

    /// 0 avant le départ, 1 à la fin, linéaire entre les deux.
    static func progression(_ t: Double, depart: Double, duree: Double) -> Double {
        guard duree > 0 else { return t >= depart ? 1 : 0 }
        return min(1, max(0, (t - depart) / duree))
    }

    /// La courbe des liquides de la maquette : `1 − (1 − k)⁴`, sans dépassement.
    static func quart(_ k: Double) -> Double { 1 - pow(1 - min(1, max(0, k)), 4) }

    /// Le liquide d'hier : 1,5 s, juste après l'apparition de la sphère.
    static func liquide(_ t: Double, rang: Int) -> Double {
        quart(progression(t, depart: colonnes + 0.35 + decalage * Double(rang), duree: 1.5))
    }

    /// Le second liquide (avec l'aliment) : 1,4 s, pendant l'arrivée des aliments.
    static func ajout(_ t: Double, rang: Int) -> Double {
        quart(progression(t, depart: aliments + 0.6 + decalage * Double(rang), duree: 1.4))
    }

    /// Le reflet traverse une fois, après la montée du liquide.
    static func balayage(_ t: Double, rang: Int) -> Double {
        progression(t, depart: colonnes + 1.4 + 0.2 * Double(rang), duree: 1.6)
    }

    /// 0 → 1 → 0 en 4,5 s : l'aliment monte de 6 pt et redescend ; la seconde
    /// colonne est déphasée.
    static func flottement(_ t: Double, rang: Int) -> Double {
        0.5 - 0.5 * cos(2 * Double.pi * (t + 1.5 * Double(rang)) / 4.5)
    }

    /// L'entrée d'un élément (`cubic-bezier(.2, .8, .2, 1)` de la maquette).
    static let entree = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.8),
                                         endControlPoint: UnitPoint(x: 0.2, y: 1))
    /// Le balayage du reflet (`cubic-bezier(.4, 0, .2, 1)`).
    static let reflet = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.4, y: 0),
                                         endControlPoint: UnitPoint(x: 0.2, y: 1))
}

/// Entrée de la maquette : fondu en 0,7 s, remontée de 16 pt et échelle
/// 0,97 → 1 en 0,9 s, à partir de `delai`.
private struct ApparitionRecap: ViewModifier {
    let t: Double
    let delai: Double

    func body(content: Content) -> some View {
        let fondu = RecapChoregraphie.entree.value(at: RecapChoregraphie.progression(t, depart: delai, duree: 0.7))
        let geste = RecapChoregraphie.entree.value(at: RecapChoregraphie.progression(t, depart: delai, duree: 0.9))
        return content
            .opacity(fondu)
            .offset(y: 16 * (1 - geste))
            .scaleEffect(0.97 + 0.03 * geste)
    }
}

private extension View {
    func apparition(_ t: Double, delai: Double) -> some View {
        modifier(ApparitionRecap(t: t, delai: delai))
    }
}

// MARK: - La sphère de verre

/// Une sphère dessinée dans un `Canvas` : verre laiteux, liquide d'hier,
/// liquide de l'aliment, ombre intérieure, reflet qui balaie, éclats qui
/// suivent l'inclinaison. Toutes les valeurs viennent de l'horloge de l'écran.
struct SphereRecapVue: View {
    let teinte: Color
    /// Niveau du liquide d'hier, 0 à 100.
    let niveau: Double
    /// Niveau du liquide avec l'aliment, 0 à 100 ; nil = pas d'aliment chiffré.
    let niveauAjout: Double?
    /// Avancée du reflet, 0 à 1.
    let balayage: Double
    let temps: Double
    let rang: Int
    /// Inclinaison du téléphone, de −1 à 1 par axe.
    let inclinaison: CGPoint

    var body: some View {
        let claire = teinte.melangeePourRecap(avec: .white, part: 0.35)
        let foncee = teinte.melangeePourRecap(avec: .black, part: 0.25)
        Canvas { contexte, taille in
            SphereRecapPeintre.peindre(&contexte, taille: taille, teinte: teinte, claire: claire, foncee: foncee,
                                       niveau: niveau, niveauAjout: niveauAjout, balayage: balayage,
                                       temps: temps, rang: rang, inclinaison: inclinaison)
        }
        .rotation3DEffect(.degrees(Double(inclinaison.x) * 7), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .rotation3DEffect(.degrees(Double(-inclinaison.y) * 7), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .accessibilityHidden(true)
    }
}

/// La géométrie de la maquette (repère 120 × 120, rayon 55, centre 60).
enum SphereRecapPeintre {

    /// Ordonnée de la surface : 0 % au fond (115/120), 100 % en haut (5/120).
    static func surface(niveau: Double, unite u: CGFloat) -> CGFloat {
        (115 - CGFloat(min(100, max(0, niveau))) * 1.1) * u
    }

    /// Demi-largeur de la sphère à cette hauteur (jamais négative, jamais NaN).
    static func demiCorde(y: CGFloat, unite u: CGFloat) -> CGFloat {
        let rayon = 55 * u
        let ecart = y - 60 * u
        return sqrt(max(0, rayon * rayon - ecart * ecart))
    }

    /// La surface du liquide vue en perspective, qui ondule à peine.
    static func surfaceDuLiquide(y: CGFloat, unite u: CGFloat, temps: Double, rang: Int) -> Path {
        let rx = demiCorde(y: y, unite: u)
        let ry = max(0, rx * 0.16 + CGFloat(sin(temps * 2 + Double(rang))) * 0.6 * u)
        return Path(ellipseIn: CGRect(x: 60 * u - rx, y: y - ry, width: 2 * rx, height: 2 * ry))
    }

    static func peindre(
        _ c: inout GraphicsContext,
        taille: CGSize,
        teinte: Color,
        claire: Color,
        foncee: Color,
        niveau: Double,
        niveauAjout: Double?,
        balayage: Double,
        temps: Double,
        rang: Int,
        inclinaison: CGPoint
    ) {
        let d = min(taille.width, taille.height)
        guard d > 0 else { return }
        let u = d / 120
        c.translateBy(x: (taille.width - d) / 2, y: (taille.height - d) / 2)

        // Le verre : blanc laiteux en haut à gauche, teinté sur le bord.
        let verre = Path(ellipseIn: CGRect(x: 5 * u, y: 5 * u, width: 110 * u, height: 110 * u))
        c.fill(verre, with: .radialGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0.75), location: 0),
                .init(color: .white.opacity(0.25), location: 0.55),
                .init(color: teinte.opacity(0.22), location: 1),
            ]),
            center: CGPoint(x: 0.38 * d, y: 0.30 * d),
            startRadius: 0,
            endRadius: 0.8 * d))

        // Liquides, ombre intérieure et reflet, découpés par la sphère.
        c.drawLayer { couche in
            couche.clip(to: verre)
            if let niveauAjout, niveauAjout > 0.5 {
                let y = surface(niveau: niveauAjout, unite: u)
                couche.fill(Path(CGRect(x: 0, y: y, width: d, height: d - y)), with: .color(teinte.opacity(0.42)))
                couche.fill(surfaceDuLiquide(y: y, unite: u, temps: temps, rang: rang), with: .color(claire.opacity(0.6)))
            }
            if niveau > 0.5 {
                let y = surface(niveau: niveau, unite: u)
                couche.fill(Path(CGRect(x: 0, y: y, width: d, height: d - y)),
                            with: .linearGradient(Gradient(colors: [claire, foncee]),
                                                  startPoint: CGPoint(x: 0, y: y),
                                                  endPoint: CGPoint(x: 0, y: d)))
                couche.fill(surfaceDuLiquide(y: y, unite: u, temps: temps, rang: rang), with: .color(claire))
            }
            couche.fill(Path(CGRect(x: 0, y: 0, width: d, height: d)), with: .radialGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0), location: 0.6),
                    .init(color: .black.opacity(0.14), location: 1),
                ]),
                center: CGPoint(x: 0.5 * d, y: d),
                startRadius: 0,
                endRadius: 0.7 * d))
            if balayage > 0, balayage < 1 {
                let k = CGFloat(RecapChoregraphie.reflet.value(at: balayage))
                var bande = couche
                bande.translateBy(x: (-140 + 300 * k) * u + 33 * u, y: 60 * u)
                bande.rotate(by: .degrees(20))
                bande.fill(Path(CGRect(x: -13 * u, y: -80 * u, width: 26 * u, height: 160 * u)), with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.55), location: 0.5),
                        .init(color: .white.opacity(0), location: 1),
                    ]),
                    startPoint: CGPoint(x: -13 * u, y: 0),
                    endPoint: CGPoint(x: 13 * u, y: 0)))
            }
        }

        // Éclats : ils glissent un peu avec l'inclinaison, comme un vrai reflet.
        let dx = inclinaison.x * 6 * u
        let dy = inclinaison.y * 6 * u
        var eclat = c
        eclat.translateBy(x: 42 * u + dx, y: 30 * u + dy)
        eclat.rotate(by: .degrees(-28))
        eclat.fill(Path(ellipseIn: CGRect(x: -20 * u, y: -11 * u, width: 40 * u, height: 22 * u)), with: .color(.white.opacity(0.6)))
        c.fill(Path(ellipseIn: CGRect(x: 28.4 * u + dx, y: 41.4 * u + dy, width: 5.2 * u, height: 5.2 * u)), with: .color(.white.opacity(0.9)))

        c.stroke(verre, with: .color(.white.opacity(0.9)), lineWidth: 1.2 * u)
        c.stroke(Path(ellipseIn: CGRect(x: 4.2 * u, y: 4.2 * u, width: 111.6 * u, height: 111.6 * u)),
                 with: .color(teinte.opacity(0.25)), lineWidth: 0.6 * u)
    }
}

// MARK: - Inclinaison du téléphone

/// L'inclinaison du téléphone, lue à chaque image par l'horloge du récap : une
/// classe jamais publiée, pour ne pas réévaluer l'écran 60 fois par seconde
/// pour rien. Un seul `CMMotionManager` pour toute l'app (recommandation
/// d'Apple). Les capteurs de mouvement bruts ne demandent aucune autorisation
/// et rien ne quitte le téléphone. Zéro = la tenue du téléphone à l'ouverture.
@MainActor
final class InclinaisonTelephone {
    static let partage = InclinaisonTelephone()

    private let capteurs = CMMotionManager()
    private var reference: CMAttitude?
    private var lissee = CGPoint.zero
    private var lecteurs = 0

    func demarrer() {
        lecteurs += 1
        guard lecteurs == 1, capteurs.isDeviceMotionAvailable else { return }
        reference = nil
        lissee = .zero
        capteurs.deviceMotionUpdateInterval = 1.0 / 60
        capteurs.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }

    func arreter() {
        lecteurs = max(0, lecteurs - 1)
        guard lecteurs == 0 else { return }
        if capteurs.isDeviceMotionActive { capteurs.stopDeviceMotionUpdates() }
        reference = nil
        lissee = .zero
    }

    /// De −1 à 1 par axe (±0,35 rad), lissé.
    func lire() -> CGPoint {
        // Copie avant `multiply` : sans nouvelle mesure entre deux images, on
        // multiplierait deux fois le même objet.
        guard let mesure = capteurs.deviceMotion?.attitude.copy() as? CMAttitude else { return lissee }
        if reference == nil { reference = mesure.copy() as? CMAttitude }
        if let reference { mesure.multiply(byInverseOf: reference) }
        let cible = CGPoint(x: max(-1, min(1, mesure.roll / 0.35)), y: max(-1, min(1, mesure.pitch / 0.35)))
        lissee.x += (cible.x - lissee.x) * 0.12
        lissee.y += (cible.y - lissee.y) * 0.12
        return lissee
    }
}

// MARK: - Mélange de couleurs

extension Color {
    /// Couleur mélangée à une autre, comme le `mix()` de la maquette :
    /// `part` = 0 rend la couleur, 1 rend l'autre.
    func melangeePourRecap(avec autre: Color, part: CGFloat) -> Color {
        var r1: CGFloat = 0, v1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, v2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &v1, blue: &b1, alpha: &a1)
        UIColor(autre).getRed(&r2, green: &v2, blue: &b2, alpha: &a2)
        let k = min(1, max(0, part))
        return Color(red: Double(r1 + (r2 - r1) * k), green: Double(v1 + (v2 - v1) * k), blue: Double(b1 + (b2 - b1) * k))
    }
}
