import SwiftUI
import UserNotifications

// MARK: - Brief du jour (plein écran, première ouverture de la journée)
//
// Même grammaire que le récap de fin de questionnaire (fond chaud, barre
// segmentée, compteur animé, jauges), mais piloté au DOIGT seulement : un
// brief se survole, il ne défile pas tout seul. Tap à droite = suivant, à
// gauche = précédent, glisser vers le bas ou la croix = fermer.
//
// Il ne bloque jamais rien : fermable à tout moment, et l'appelant ne le
// présente que s'il a au moins deux écrans à montrer.

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
            RecapProgressBar(total: slides.count, index: index, avancee: 1)
                .padding(.horizontal, Theme.spacingMD)

            HStack {
                Button {
                    terminer(raison: "croix")
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.dsTexte.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
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
        case .intro(let prenom):
            ecranIntro(prenom: prenom)
        case .hier(let couverts, let avantHier):
            ecranHier(couverts: couverts, avantHier: avantHier)
        case .rienHier(let repas):
            ecranRienHier(repas: repas)
        case .manques(let manques):
            ecranManques(manques)
        case .effort(let effort):
            ecranEffort(effort)
        case .cible(let cible):
            ecranCible(cible)
        case .invitation(let cible):
            ecranInvitation(cible: cible)
        }
    }

    private func ecranIntro(prenom: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            legende(prenom.map { "Bonjour \($0)" } ?? "Bonjour")
            Text("Voici où tu en étais hier, et ce qui compte aujourd'hui.")
                .font(.dsSection)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.spacingXL)
            HStack {
                Spacer()
                KiwiContourMark(size: 72, color: .dsAccent)
                    .accessibilityHidden(true)
                Spacer()
            }
            Spacer(minLength: Theme.spacingXL)
            indiceTap
        }
    }

    private func ecranHier(couverts: Int, avantHier: Int?) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            legende("Hier")
            Spacer(minLength: Theme.spacingXL)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Spacer()
                RecapCompteur(valeur: couverts, taille: 88, couleur: .dsAccent)
                Text("/ 10")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaire)
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(couverts) besoins sur 10 couverts hier")
            Text("besoins couverts")
                .font(.dsHeadline)
                .foregroundStyle(Color.dsTexte)
                .frame(maxWidth: .infinity)
            if let comparaison = Self.comparaison(couverts: couverts, avantHier: avantHier) {
                Text(comparaison)
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            Spacer(minLength: Theme.spacingXL)
            if estDernier { boutonFin }
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

    private func ecranManques(_ manques: [BriefDuJour.Manque]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            legende("Ce qui a manqué hier")
            ForEach(manques, id: \.id) { manque in
                VStack(alignment: .leading, spacing: 6) {
                    Text(manque.nom)
                        .font(.dsHeadline)
                        .foregroundStyle(Color.dsTexte)
                    RecapJaugeApport(
                        pourcent: manque.pourcent,
                        couleur: NutrientData.definition(for: manque.id)?.color ?? .dsAccent
                    )
                }
                .padding(.bottom, Theme.spacingSM)
            }
            if let plusBas = manques.first, plusBas.pourcent < 100 {
                Text("Il t'a manqué \(100 - plusBas.pourcent) % \(NomNutriment.complement(id: plusBas.id, nom: plusBas.nom)) : c'est ta priorité du jour.")
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if estDernier { boutonFin }
        }
    }

    private func ecranEffort(_ effort: BriefDuJour.Effort) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            legende("Ton effort qui paie")
            Spacer(minLength: Theme.spacingXL)
            Text("+\(effort.points)")
                .font(.system(size: 72, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.dsAccent)
                .frame(maxWidth: .infinity)
            Text("points \(NomNutriment.complement(id: effort.id, nom: effort.nom)) cette semaine")
                .font(.dsHeadline)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text("Par rapport à la semaine dernière. Continue comme ça.")
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Spacer(minLength: Theme.spacingXL)
            if estDernier { boutonFin }
        }
    }

    private func ecranCible(_ cible: CibleNutritionnelle) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            legende("Aujourd'hui, mise sur")
            Text(cible.avecPossessif)
                .font(.dsGrandTitre)
                .foregroundStyle(Color.dsTexte)

            if !cible.aliments.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(cible.aliments.enumerated()), id: \.offset) { position, aliment in
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

    /// « Un de plus qu'avant-hier. » — jamais culpabilisant quand ça baisse.
    static func comparaison(couverts: Int, avantHier: Int?) -> String? {
        guard let avantHier else { return nil }
        let ecart = couverts - avantHier
        switch ecart {
        case 0: return "Autant qu'avant-hier."
        case 1: return "Un de plus qu'avant-hier."
        case 2...: return "\(ecart) de plus qu'avant-hier."
        case -1: return "Un de moins qu'avant-hier : aujourd'hui, on remonte."
        default: return "\(-ecart) de moins qu'avant-hier : aujourd'hui, on remonte."
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

    static func explication(cible: CibleNutritionnelle?) -> String {
        guard let cible else {
            return "Un rappel à midi et un le soir, juste avant de passer à table. Rien d'autre."
        }
        return "\(NomNutriment.majusculeInitiale(cible.avecPossessif)) est ton apport le plus bas. On te prévient à midi et le soir, juste avant de passer à table."
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
        .background(Color.dsFond.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
