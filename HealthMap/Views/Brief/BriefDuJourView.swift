import SwiftUI
import UserNotifications

// MARK: - Récap du jour (plein écran, première ouverture de la journée)
//
// Refonte du 7 octobre 2026, demande d'Arthur : « on rentre dans le vif du
// sujet, pas besoin d'appuyer pour avoir le récap ». Fini les cinq écrans à
// toucher (bonjour, hier, manques, effort, cible) : UN écran qui arrive d'un
// coup, en très gros, et dit dans l'ordre
//
//   1. ce qui a été noté hier (les aliments, en pastilles) ;
//   2. les DEUX apports qui ont le plus manqué, et pour chacun L'aliment à
//      ajouter aujourd'hui ;
//   3. une raison de revenir demain : un compte à rebours, un progrès, une
//      série, une stat publique sourcée, sinon une phrase.
//
// Tout le contenu vient de `BriefDuJourBuilder` : aucun chiffre inventé.
// L'invitation aux notifications, quand elle est due, prend le relais après
// « C'est parti » au lieu de fermer.
//
// Il ne bloque jamais rien : la croix et le glissé vers le bas ferment à tout
// moment.

struct BriefDuJourView: View {
    let brief: BriefDuJour
    /// L'invitation aux notifications suit le récap (autorisation jamais
    /// demandée, pas repoussée récemment).
    let proposerInvitation: Bool
    /// « Ajouter mes repas d'hier » : le journal s'ouvre sur la veille.
    let onAjouterHier: () -> Void
    let onTerminer: () -> Void
    var maintenant: Date = Date()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var apparu = false
    @State private var enInvitation = false
    @State private var demandeEnCours = false

    /// Au plus six pastilles : au-delà, « +3 » dit le reste.
    private static let pastillesMax = 6

    var body: some View {
        ZStack(alignment: .topLeading) {
            WarmBackground().ignoresSafeArea()

            Group {
                if enInvitation {
                    ScrollView {
                        invitation
                            .padding(.horizontal, DS.marge)
                            .padding(.top, 64)
                            .padding(.bottom, Theme.spacingLG)
                    }
                    .transition(transitionEcran)
                } else {
                    ScrollView {
                        recap
                            .padding(.horizontal, DS.marge)
                            .padding(.top, 56)
                            .padding(.bottom, Theme.spacingLG)
                    }
                    .transition(transitionEcran)
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

            boutonFermer
                .padding(.leading, Theme.spacingSM)
                .padding(.top, Theme.spacingSM)
        }
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: enInvitation)
        .onAppear {
            AnalyticsService.shared.track(.screenViewed, properties: [
                "screen": "brief_du_jour",
                "priorites": brief.priorites.count,
                "periode": brief.priorites.first?.periode.rawValue ?? "aucune",
                "accroche": brief.accroche?.genre.rawValue ?? "aucune",
            ])
            HapticService.shared.success()
            apparu = true
        }
        .dynamicTypeSize(.large ... .accessibility3)
    }

    /// Typée `AnyTransition` : en ternaire, `.opacity` est ambigu depuis
    /// iOS 17 (`AnyTransition` ou `Transition`).
    private var transitionEcran: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                removal: .opacity
            )
    }

    // MARK: - Le récap

    private var recap: some View {
        VStack(alignment: .leading, spacing: 0) {
            titre
                .padding(.bottom, Theme.spacingLG)

            blocHier
                .apparitionRecap(apparu, rang: 1)
                .padding(.bottom, Theme.spacingLG)

            if brief.priorites.isEmpty {
                carteRienNAManque
                    .apparitionRecap(apparu, rang: 2)
                    .padding(.bottom, DS.interCarte)
            } else {
                ForEach(Array(brief.priorites.enumerated()), id: \.element.id) { position, priorite in
                    cartePriorite(priorite, numero: position + 1)
                        .apparitionRecap(apparu, rang: 2 + position)
                        .padding(.bottom, DS.interCarte)
                }
            }

            if let accroche = brief.accroche {
                carteAccroche(accroche)
                    .apparitionRecap(apparu, rang: 4)
                    .padding(.top, DS.interCarte)
            }

            VStack(spacing: Theme.spacingSM) {
                DSCapsuleButton(titre: "C'est parti", brillance: true) {
                    if proposerInvitation {
                        HapticService.shared.tap()
                        AnalyticsService.shared.track(.screenViewed, properties: ["screen": "brief_invitation"])
                        enInvitation = true
                    } else {
                        terminer(raison: "fin")
                    }
                }
                Text("Calculé sur les repas que tu as notés.")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
            }
            .apparitionRecap(apparu, rang: 5)
            .padding(.top, Theme.spacingXL)
        }
    }

    // MARK: Titre

    /// « Récap du jour » en très gros : il arrive en rebond, avant tout le
    /// reste.
    private var titre: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.surTitre(prenom: brief.prenom, maintenant: maintenant))
                .font(.dsSousTitreMoyen)
                .foregroundStyle(Color.dsSecondaire)
                .apparitionRecap(apparu, rang: 0)

            Text("Récap\ndu jour")
                .font(.system(size: 56, weight: .bold))
                .tracking(-2.2)
                .lineSpacing(-6)
                .foregroundStyle(Color.dsTexte)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .scaleEffect(apparu || reduceMotion ? 1 : 0.6, anchor: .bottomLeading)
                .opacity(apparu ? 1 : 0)
                .animation(reduceMotion ? nil : Animation.kiwiRebond, value: apparu)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Hier

    @ViewBuilder
    private var blocHier: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !brief.alimentsHier.isEmpty {
                legende("Hier, tu as noté")
                DSFlow(espacement: 8) {
                    ForEach(Array(brief.alimentsHier.prefix(Self.pastillesMax).enumerated()), id: \.offset) { _, aliment in
                        pastille(aliment)
                    }
                    if brief.alimentsHier.count > Self.pastillesMax {
                        pastille("+\(brief.alimentsHier.count - Self.pastillesMax)")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hier, tu as noté : \(brief.alimentsHier.joined(separator: ", "))")
            }

            if let couverts = brief.besoinsCouvertsHier {
                Text(Self.ligneBesoins(couverts: couverts, avantHier: brief.besoinsCouvertsAvantHier))
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Hier trop peu noté : on le dit, et on propose de rattraper.
                VStack(alignment: .leading, spacing: 10) {
                    Text(brief.repasHier == 0 ? "Rien de noté hier." : "Un seul repas noté hier.")
                        .font(.dsHeadline)
                        .foregroundStyle(Color.dsTexte)
                    Button {
                        AnalyticsService.shared.track(.screenViewed, properties: ["screen": "brief_ajouter_hier"])
                        onAjouterHier()
                    } label: {
                        Label("Ajouter mes repas d'hier", systemImage: "plus")
                            .font(.dsSousTitreFort)
                            .foregroundStyle(Color.dsAccent)
                            .padding(.horizontal, 16)
                            .frame(minHeight: DS.cibleTactile)
                            .verreClair()
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.dsPress)
                }
            }
        }
    }

    private func pastille(_ texte: String) -> some View {
        Text(texte)
            .font(.dsSousTitreMoyen)
            .foregroundStyle(Color.dsTexte)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .verreClair()
    }

    // MARK: Les deux priorités

    /// « Il te manquait du fer » → « Ajoute des lentilles ». Le nom de l'apport
    /// et l'aliment sont les deux plus gros textes de la carte : c'est tout ce
    /// qu'il faut retenir.
    private func cartePriorite(_ priorite: BriefDuJour.Priorite, numero: Int) -> some View {
        let teinte = NutrientData.definition(for: priorite.id)?.color ?? .dsAccent
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                legende(Self.legende(periode: priorite.periode))
                Spacer(minLength: 8)
                Text("\(numero)/\(brief.priorites.count)")
                    .font(.dsLegendeMoyenne)
                    .monospacedDigit()
                    .foregroundStyle(Color.dsTertiaire)
                    .accessibilityHidden(true)
            }

            HStack(alignment: .center, spacing: 12) {
                Text(priorite.emoji)
                    .font(.system(size: 30))
                    .accessibilityHidden(true)
                Text(priorite.nom)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }

            if let pourcent = priorite.pourcent {
                RecapJaugeApport(pourcent: pourcent, couleur: teinte)
            }

            DSSeparator()

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(teinte)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(teinte.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ajoute aujourd'hui")
                        .font(.dsLegendeMoyenne)
                        .foregroundStyle(Color.dsSecondaire)
                    Text(priorite.aliment)
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.phraseAccessible(priorite))
    }

    /// Hier assez noté, et tout au-dessus de 70 % : on le fête au lieu
    /// d'inventer un manque.
    private var carteRienNAManque: some View {
        HStack(alignment: .center, spacing: 14) {
            KiwiSigne(taille: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Rien n'a vraiment manqué")
                    .font(.dsSection)
                    .foregroundStyle(Color.dsTexte)
                Text("Tes apports suivis ont tous passé 70 %. Refais pareil aujourd'hui.")
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: L'accroche

    private func carteAccroche(_ accroche: BriefDuJour.Accroche) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let prefixe = accroche.prefixe {
                Text(prefixe)
                    .font(.dsHeadline)
                    .foregroundStyle(Color.dsTexte)
            }
            if let chiffre = accroche.chiffre {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(chiffre)
                        .font(.dsHeros48)
                        .tracking(DSTracking.heros48)
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unite = accroche.unite {
                        Text(unite)
                            .font(.dsSection)
                            .foregroundStyle(Color.dsTexte)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            Text(accroche.texte)
                .font(accroche.chiffre == nil ? Font.dsSection : Font.dsCorps)
                .foregroundStyle(accroche.chiffre == nil ? Color.dsTexte : Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
            if let source = accroche.source {
                Text("Source : \(source)")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsTertiaire)
                    .padding(.top, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accroche.phrase + (accroche.source.map { ". Source : \($0)" } ?? ""))
    }

    // MARK: - Invitation (après « C'est parti »)

    private var invitation: some View {
        InvitationNotificationsContenu(
            cible: brief.cible,
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

    private var boutonFermer: some View {
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
    }

    private func legende(_ texte: String) -> some View {
        Text(texte)
            .font(.dsSousTitreMoyen)
            .foregroundStyle(Color.dsSecondaire)
    }

    private func terminer(raison: String) {
        AnalyticsService.shared.track(.screenViewed, properties: [
            "screen": "brief_du_jour_ferme",
            "raison": raison,
            "etape": enInvitation ? "invitation" : "recap",
        ])
        onTerminer()
    }

    // MARK: - Textes (purs, testés)

    /// « Bonjour Léa · mardi 7 octobre ».
    static func surTitre(prenom: String?, maintenant: Date) -> String {
        let formatteur = DateFormatter()
        formatteur.locale = Locale(identifier: "fr_FR")
        formatteur.dateFormat = "EEEE d MMMM"
        let date = formatteur.string(from: maintenant)
        let bonjour = prenom.map { "Bonjour \($0)" } ?? "Bonjour"
        return "\(bonjour) · \(date)"
    }

    static func legende(periode: BriefDuJour.Priorite.Periode) -> String {
        switch periode {
        case .hier: return "Hier, il te manquait"
        case .joursPrecedents: return "Ces derniers jours, il te manquait"
        case .bilan: return "D'après ton bilan, à renforcer"
        }
    }

    /// « 6 besoins sur 10 couverts hier. Un de plus qu'avant-hier. »
    static func ligneBesoins(couverts: Int, avantHier: Int?) -> String {
        let base = "\(couverts) \(couverts > 1 ? "besoins" : "besoin") sur 10 couverts hier."
        guard let comparaison = comparaison(couverts: couverts, avantHier: avantHier) else { return base }
        return "\(base) \(comparaison)"
    }

    static func phraseAccessible(_ priorite: BriefDuJour.Priorite) -> String {
        let constat: String
        switch priorite.periode {
        case .hier, .joursPrecedents:
            let quand = priorite.periode == .hier ? "Hier" : "Ces derniers jours"
            let chiffre = priorite.pourcent.map { ", couvert à \($0) %" } ?? ""
            constat = "\(quand), il te manquait : \(priorite.nom)\(chiffre)."
        case .bilan:
            constat = "D'après ton bilan, à renforcer : \(priorite.nom)."
        }
        return "\(constat) Ajoute aujourd'hui : \(priorite.aliment)."
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

// MARK: - Entrée du récap : chaque bloc monte à son tour

private struct ApparitionRecap: ViewModifier {
    let visible: Bool
    let rang: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 28)
            .animation(
                reduceMotion
                    ? Animation.easeOut(duration: 0.2)
                    : Animation.kiwiCascade.delay(0.12 + Double(rang) * 0.09),
                value: visible
            )
    }
}

private extension View {
    func apparitionRecap(_ visible: Bool, rang: Int) -> some View {
        modifier(ApparitionRecap(visible: visible, rang: rang))
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
            return "Quelques signes dans la journée, avant de passer à table, chacun avec un chiffre tiré de tes repas notés."
        }
        let verbe = NomNutriment.accord(id: cible.id, singulier: "est", pluriel: "sont")
        return "\(NomNutriment.majusculeInitiale(cible.avecPossessif)) \(verbe) ton apport le plus bas. Kiwio te fait signe dans la journée, avec tes chiffres : où tu en es, et quoi mettre dans l'assiette."
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
