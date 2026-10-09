import SwiftUI
import UserNotifications

// MARK: - Brief du jour (plein écran, première ouverture de la journée)
//
// Même grammaire que le récap de fin de questionnaire (fond de verre, barre
// segmentée, compteur animé, jauges), mais piloté au DOIGT seulement : un
// brief se survole, il ne défile pas tout seul. Tap à droite = suivant, à
// gauche = précédent, glisser vers le bas ou la croix = fermer.
//
// Il ne bloque jamais rien : fermable à tout moment, et l'appelant ne le
// présente que s'il a un écran à montrer. Depuis le 9 oct. 2026, c'est
// presque toujours UN écran : ce qui a manqué hier (`BriefDuJourBuilder.slides`).
//
// Verre liquide (2 octobre 2026) : la chorégraphie ne bouge pas. Seules les
// surfaces changent : fond de verre (teinte kiwi), cartes de verre (`.dsCard()`),
// action principale en verre vert (`DSCapsuleButton`), croix en rond de verre
// clair, feuille d'invitation sur le verre de feuille.

struct BriefDuJourView: View {
    let slides: [BriefSlide]
    /// « Ajouter mes repas d'hier » : le journal s'ouvre sur la veille.
    let onAjouterHier: () -> Void
    let onTerminer: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var demandeEnCours = false

    /// Même partage que le récap : 40 % à gauche reviennent, le reste avance.
    private static let partRetour: CGFloat = 0.4

    private var slideCourant: BriefSlide? {
        slides.indices.contains(index) ? slides[index] : nil
    }

    private var estDernier: Bool { index >= slides.count - 1 }

    /// La priorité du jour garde son bouton HORS du défilement : sur un
    /// iPhone de 6,1", sphère, carte et ligne du fer poussaient « C'est
    /// parti » de 35 pt sous le bord. Le contenu peut glisser, pas le bouton.
    private var boutonEpingle: Bool {
        guard estDernier, case .priorite? = slideCourant else { return false }
        return true
    }

    /// Typée `AnyTransition` (comme dans le récap) : en ternaire, `.opacity`
    /// est ambigu depuis iOS 17 (`AnyTransition` ou `Transition`).
    private var transitionEcran: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                removal: .opacity
            )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                WarmBackground().ignoresSafeArea()

                VStack(spacing: Theme.spacingSM) {
                    entete

                    if let slide = slideCourant {
                        ScrollView {
                            contenu(slide)
                                .padding(.horizontal, Theme.spacingLG)
                                .padding(.vertical, Theme.spacingLG)
                                .frame(maxWidth: .infinity, minHeight: max(geo.size.height - 200, 200), alignment: .topLeading)
                                .contentShape(Rectangle())
                                .id(slide.id)
                                .transition(transitionEcran)
                                .onTapGesture(coordinateSpace: .local) { point in
                                    if point.x < geo.size.width * Self.partRetour {
                                        precedent()
                                    } else {
                                        suivant()
                                    }
                                }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 60).onEnded { valeur in
                                guard valeur.translation.height > 80,
                                      abs(valeur.translation.width) < 60 else { return }
                                terminer(raison: "glisser")
                            }
                        )
                    }

                    if boutonEpingle {
                        boutonFin
                            .padding(.horizontal, Theme.spacingLG)
                    }

                    Text("Calculé sur les repas que tu as notés.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsSecondaire)
                        .padding(.bottom, Theme.spacingSM)
                }
                .padding(.top, Theme.spacingSM)
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: index)
        .onAppear {
            AnalyticsService.shared.track(.screenViewed, properties: [
                "screen": "brief_du_jour",
                "slides": slides.count,
            ])
        }
        .dynamicTypeSize(.large ... .accessibility3)
    }

    // MARK: - Chrome

    private var entete: some View {
        VStack(spacing: Theme.spacingSM) {
            // Un seul écran (le cas courant depuis le 9 oct. 2026) : pas de
            // barre de progression à un segment.
            if slides.count > 1 {
                RecapProgressBar(total: slides.count, index: index, avancee: 1)
                    .padding(.horizontal, Theme.spacingMD)
            }

            HStack {
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
                .accessibilityLabel("Fermer le brief du jour")
                Spacer()
            }
            .padding(.horizontal, Theme.spacingSM)
        }
    }

    // MARK: - Navigation

    private func suivant() {
        guard !estDernier else {
            // Le dernier écran se ferme par son bouton : un tap distrait ne
            // doit pas faire rater l'invitation ou le conseil du jour.
            return
        }
        HapticService.shared.tap()
        index += 1
    }

    private func precedent() {
        guard index > 0 else { return }
        HapticService.shared.tap()
        index -= 1
    }

    private func terminer(raison: String) {
        AnalyticsService.shared.track(.screenViewed, properties: [
            "screen": "brief_du_jour_ferme",
            "raison": raison,
            "index": index,
            "slide": slideCourant?.typeName ?? "",
        ])
        onTerminer()
    }

    // MARK: - Écrans

    @ViewBuilder
    private func contenu(_ slide: BriefSlide) -> some View {
        switch slide {
        case .rienHier(let repas):
            ecranRienHier(repas: repas)
        case .priorite(let priorite):
            ecranPriorite(priorite)
        case .cible(let cible):
            ecranCible(cible)
        case .invitation(let cible):
            ecranInvitation(cible: cible)
        }
    }

    private func ecranRienHier(repas: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            legende("Hier")
            Text(repas == 0 ? "Rien de noté hier." : "Un seul repas noté hier.")
                .font(.dsSection)
                .foregroundStyle(Color.dsTexte)
            Text("Tes repas d'hier comptent encore : ajoute-les, et ton suivi se met à jour.")
                .font(.dsCorps)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.spacingLG)
            DSCapsuleButton(titre: "Ajouter mes repas d'hier") {
                AnalyticsService.shared.track(.screenViewed, properties: ["screen": "brief_ajouter_hier"])
                onAjouterHier()
            }
            if estDernier {
                boutonFin
            } else {
                indiceTap
            }
        }
    }

    /// Ce qui a manqué hier et l'aliment qui le remonte : une colonne, un
    /// chiffre héros (`BriefPrioriteContenu`). Son bouton est épinglé sous le
    /// défilement (`boutonEpingle`).
    private func ecranPriorite(_ priorite: PrioriteDuJour) -> some View {
        BriefPrioriteContenu(priorite: priorite)
    }

    private func ecranCible(_ cible: CibleNutritionnelle) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            legende("Aujourd'hui, mise sur")
            Text(cible.avecPossessif)
                .font(.dsGrandTitre)
                .foregroundStyle(Color.dsTexte)

            // Le repli écrit à la main quand l'apport n'est pas une cible du
            // bilan (`BriefDuJourBuilder.suivis`) : jamais d'écran sans idée.
            if !cible.alimentsAffichables.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(cible.alimentsAffichables.enumerated()), id: \.offset) { position, aliment in
                        if position > 0 { DSSeparator() }
                        HStack(spacing: 12) {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.dsAccent)
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            Text(NomNutriment.majusculeInitiale(aliment))
                                .font(.dsCorps)
                                .foregroundStyle(Color.dsTexte)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, DS.paddingCarte)
                .dsCard()
            }

            if let conseil = cible.conseil {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.dsAccent)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text(conseil)
                        .font(.dsSousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(DS.paddingCarte)
                .dsCard()
            }

            Spacer(minLength: Theme.spacingLG)
            if estDernier { boutonFin }
        }
    }

    private func ecranInvitation(cible: CibleNutritionnelle?) -> some View {
        InvitationNotificationsContenu(
            cible: cible,
            demandeEnCours: demandeEnCours,
            onAccepter: {
                Task {
                    demandeEnCours = true
                    let accorde = await PushNotificationService.shared.requestAuthorizationIfNeeded()
                    if accorde { await RappelsPersonnalises.replanifier() }
                    demandeEnCours = false
                    terminer(raison: accorde ? "notifs_acceptees" : "notifs_refusees_ios")
                }
            },
            onPlusTard: {
                BriefDuJourStore.repousserInvitation()
                terminer(raison: "notifs_plus_tard")
            }
        )
    }

    // MARK: - Briques

    private func legende(_ texte: String) -> some View {
        Text(texte)
            .font(.dsSousTitreMoyen)
            .foregroundStyle(Color.dsSecondaire)
    }

    private var indiceTap: some View {
        Text("Touche l'écran pour continuer")
            .font(.dsLegende)
            .foregroundStyle(Color.dsTertiaire)
            .frame(maxWidth: .infinity)
    }

    private var boutonFin: some View {
        DSCapsuleButton(titre: "C'est parti") {
            terminer(raison: "fin")
        }
    }
}

// MARK: - Invitation aux notifications (avant l'alerte d'iOS)

/// L'écran qui explique CE QUE Kiwio enverra, avant de déclencher l'alerte
/// système. Sans lui, l'alerte arrivait sans contexte et un refus est
/// définitif côté iOS (on ne peut plus la reposer, seulement renvoyer vers
/// les Réglages).
struct InvitationNotificationsContenu: View {
    let cible: CibleNutritionnelle?
    var demandeEnCours: Bool = false
    let onAccepter: () -> Void
    let onPlusTard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack {
                Spacer()
                Image(systemName: "bell.badge")
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.dsAccent)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.dsAccentPale))
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.top, Theme.spacingLG)

            Text("Kiwio te fait signe au bon moment")
                .font(.dsSection)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(Self.explication(cible: cible))
                .font(.dsCorps)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                Text("Exemple, à midi")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                Text(Self.exemple(cible: cible))
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.paddingCarte)
            .dsCard()

            Spacer(minLength: Theme.spacingLG)

            DSCapsuleButton(titre: "Oui, préviens-moi", chargement: demandeEnCours, action: onAccepter)

            Button(action: onPlusTard) {
                Text("Plus tard")
                    .font(.dsSousTitreMoyen)
                    .foregroundStyle(Color.dsSecondaire)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// La raison, puis la vraie fréquence (`RappelsPersonnalises.frequenceAnnoncee`) :
    /// on dit combien de rappels avant de demander l'accord.
    static func explication(cible: CibleNutritionnelle?) -> String {
        let frequence = RappelsPersonnalises.frequenceAnnoncee
        guard let cible else {
            return "Chaque rappel part d'un chiffre tiré de tes repas notés. \(frequence)"
        }
        let verbe = NomNutriment.accord(id: cible.id, singulier: "est", pluriel: "sont")
        return "\(NomNutriment.majusculeInitiale(cible.avecPossessif)) \(verbe) ton apport le plus bas. Kiwio te dit où tu en es, et quoi mettre dans l'assiette. \(frequence)"
    }

    static func exemple(cible: CibleNutritionnelle?) -> String {
        guard let cible else { return "Photographie ton repas : Kiwio s'occupe de l'analyse." }
        if cible.aliments.isEmpty {
            return "C'est le moment de renforcer \(cible.avecPossessif). Scanne ton assiette."
        }
        return "\(NomNutriment.enumeration(cible.aliments)) ce midi ? \(NomNutriment.majusculeInitiale(cible.avecPossessif)) te dira merci."
    }
}

/// L'invitation en feuille — présentée à la fin du récap de questionnaire.
struct InvitationNotificationsSheet: View {
    let cible: CibleNutritionnelle?
    @Environment(\.dismiss) private var dismiss
    @State private var demandeEnCours = false

    var body: some View {
        ScrollView {
            InvitationNotificationsContenu(
                cible: cible,
                demandeEnCours: demandeEnCours,
                onAccepter: {
                    Task {
                        demandeEnCours = true
                        let accorde = await PushNotificationService.shared.requestAuthorizationIfNeeded()
                        if accorde { await RappelsPersonnalises.replanifier() }
                        demandeEnCours = false
                        dismiss()
                    }
                },
                onPlusTard: {
                    BriefDuJourStore.repousserInvitation()
                    dismiss()
                }
            )
            .padding(.horizontal, Theme.spacingLG)
            .padding(.bottom, Theme.spacingLG)
        }
        // Plus d'aplat : la feuille porte son fond de verre et ses coins de 38.
        .verreFeuille()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
