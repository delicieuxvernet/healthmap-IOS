import SwiftUI
import UIKit

// MARK: - Réglages : widgets et écran verrouillé
//
// iOS ne laisse pas une app poser un widget à la place de la personne : cette
// page montre ce qui existe, dit comment l'ajouter, et porte le seul réglage
// qui dépend de nous, la journée en direct sur l'écran verrouillé.
//
// Les aperçus sont les VRAIES vues des widgets (`Partage/VuesWidgets.swift`),
// nourries par la journée en cours quand elle existe, par un exemple sinon.
//
// Verre liquide (2 octobre 2026) : page poussée sur `VerrePageFond()`, aperçus
// posés dans des cartes de verre, étapes numérotées avec la pastille de la
// maquette (rond vert pâle, chiffre vert foncé).

struct WidgetsReglagesView: View {
    @Environment(\.scenePhase) private var scenePhase
    /// Relus à l'apparition (`relire`) : la préférence et l'autorisation d'iOS.
    @State private var voulue = true
    @State private var autorisee = true
    @State private var etat: InstantaneJour = .exemple

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
                    DSSectionHeader(titre: "Sur l'écran verrouillé")
                        .padding(.top, -14)
                    DSGroupedList { ligneActivite }
                    apercu(hauteur: 170) { VueActiviteJournee(etat: etat) }
                        .padding(.top, DS.interCarte)

                    DSSectionHeader(titre: "Sur l'écran d'accueil")
                    apercu(hauteur: 158) { VueJourneeMoyenne(etat: etat) }
                    legende("Ma journée. Touche un repas pour y ajouter un aliment.")
                    apercu(hauteur: 120) { VueAjoutRapide(etat: etat) }
                        .padding(.top, DS.interCarte)
                    legende("Ajout rapide. Dicter et Photo ouvrent Kiwio au bon endroit ; l'eau et le rituel se cochent sans l'ouvrir.")

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
        if let courant = BoiteCommune.etatAffiche(), courant.connecte { etat = courant }
    }

    // MARK: Aperçus

    /// Un widget tel qu'il se dessine, posé dans sa carte de verre. Un aperçu
    /// ne se touche pas : ses boutons agiraient pour de vrai.
    private func apercu<Contenu: View>(hauteur: CGFloat, @ViewBuilder _ contenu: () -> Contenu) -> some View {
        contenu()
            .padding(16)
            .frame(maxWidth: .infinity)
            .frame(height: hauteur)
            .dsCard()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
