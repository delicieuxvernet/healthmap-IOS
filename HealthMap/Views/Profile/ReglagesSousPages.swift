import SwiftUI
import StoreKit
import RevenueCat

// MARK: - Réglages : les sous-pages
//
// Ce qui s'ouvre depuis l'onglet Réglages (`ReglagesView.swift`) : mon compte,
// mes objectifs, mon abonnement, supprimer mon compte — et la restauration
// des achats, partagée entre la page principale et la page abonnement.

// MARK: - Restauration des achats (App Store Guideline 3.1.1)

/// Un seul chemin pour « Restaurer » : le lien de pied de page des Réglages et
/// la ligne de la page abonnement font exactement la même chose, et disent la
/// même chose ensuite.
@MainActor
final class RestaurationAchats: ObservableObject {
    @Published private(set) var enCours = false
    /// Le résultat à annoncer ; `nil` = rien à dire.
    @Published var message: String?

    func lancer(contexte: String) async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }

        let service = SubscriptionService.shared
        do {
            try await service.restorePurchases()
            if service.isPremium {
                message = "Achats restaurés. Bienvenue dans Premium !"
                AnalyticsService.shared.track(.subscriptionRestored, properties: ["outcome": "success"])
            } else {
                message = "Aucun achat à restaurer pour cet identifiant Apple. Si tu penses qu'il y a une erreur, écris au support."
                AnalyticsService.shared.track(.subscriptionRestored, properties: ["outcome": "no_purchase"])
            }
        } catch {
            message = "La restauration n'a pas abouti. Vérifie ta connexion puis réessaie, ou écris au support."
            AnalyticsService.shared.track(.subscriptionRestored, properties: ["outcome": "error"])
            AppLogger.subscription.report(error, context: "Restore purchases (\(contexte))")
        }
    }
}

extension View {
    /// L'alerte qui annonce le résultat d'une restauration.
    func alerteRestauration(_ restauration: RestaurationAchats) -> some View {
        alert(
            "Restaurer mes achats",
            isPresented: Binding(
                get: { restauration.message != nil },
                set: { if !$0 { restauration.message = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(restauration.message ?? "")
        }
    }
}

// MARK: - Mon abonnement

/// État de l'abonnement et les trois gestes obligatoires : gérer (Apple),
/// saisir un code, restaurer (App Store Review 3.1.1). La porte Premium
/// n'apparaît qu'une fois le bilan fait (V12a) ; le code promo, lui, reste
/// visible avant : ce n'est pas une porte, aucune formule, aucun prix.
struct AbonnementReglagesView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showPaywall = false
    @State private var showManageSubscriptions = false

    @StateObject private var restauration = RestaurationAchats()

    @State private var isRedeemingPromo = false
    @State private var promoResultMessage: String?
    @State private var showPromoResult = false

    var body: some View {
        ZStack {
            Color.dsFond.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    etat
                        .padding(.top, DS.marge)

                    DSSectionHeader(titre: "Gérer")
                    DSGroupedList {
                        if subscriptionService.isPremium {
                            Button {
                                showManageSubscriptions = true
                            } label: {
                                DSRow(icone: "gearshape", titre: "Gérer mon abonnement",
                                      sousTitre: "Modifier ou annuler dans les réglages Apple")
                            }
                            .buttonStyle(.dsPress)
                            .accessibilityHint("Ouvre la gestion de ton abonnement (modifier ou annuler) dans les réglages Apple.")
                            DSSeparator(retrait: DS.retraitSeparateurIcone)
                        } else if dashboardVM.bilanComplete {
                            Button {
                                HapticService.shared.tap()
                                showPaywall = true
                            } label: {
                                DSRow(icone: "sparkles", titre: "Découvrir Kiwio Premium")
                            }
                            .buttonStyle(.dsPress)
                            DSSeparator(retrait: DS.retraitSeparateurIcone)
                        }

                        if !subscriptionService.isPremium {
                            Button {
                                Task { await saisirCodePromo() }
                            } label: {
                                DSRow(icone: "ticket",
                                      titre: isRedeemingPromo ? "Vérification de ton code…" : "J'ai un code") {
                                    if isRedeemingPromo { ProgressView() } else { DSChevron() }
                                }
                            }
                            .buttonStyle(.dsPress)
                            .disabled(isRedeemingPromo)
                            .accessibilityHint("Ouvre la fenêtre Apple pour saisir un code promotionnel.")
                            DSSeparator(retrait: DS.retraitSeparateurIcone)
                        }

                        // Restaurer : visible quel que soit l'état, un abonné qui
                        // réinstalle doit toujours pouvoir récupérer son accès.
                        Button {
                            Task { await restauration.lancer(contexte: "reglages_abonnement") }
                        } label: {
                            DSRow(icone: "arrow.clockwise", titre: "Restaurer mes achats") {
                                if restauration.enCours { ProgressView() } else { DSChevron() }
                            }
                        }
                        .buttonStyle(.dsPress)
                        .disabled(restauration.enCours)
                        .accessibilityHint("Restaure un abonnement Premium acheté avant avec ce même identifiant Apple.")
                    }
                }
                .padding(.horizontal, DS.marge)
                .padding(.bottom, DS.marge)
            }
        }
        .navigationTitle("Mon abonnement")
        .navigationBarTitleDisplayMode(.inline)
        .kiwiNavigationBarBackground()
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "reglages_abonnement")
                .healthMapFullSheet()
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .alerteRestauration(restauration)
        .alert("Code promo", isPresented: $showPromoResult) {
            Button("OK", role: .cancel) { }
        } message: {
            if let promoResultMessage { Text(promoResultMessage) }
        }
    }

    private var etat: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(subscriptionService.isPremium ? "Kiwio Premium" : "Formule gratuite")
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
            Text(sousTitreEtat)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var sousTitreEtat: String {
        if subscriptionService.isPremium {
            if let ent = subscriptionService.customerInfo?.entitlements[SubscriptionService.entitlementId],
               let exp = ent.expirationDate {
                let date = exp.formatted(date: .abbreviated, time: .omitted)
                return ent.willRenew ? "Renouvellement le \(date)." : "Actif jusqu'au \(date)."
            }
            return "Tout est débloqué."
        }
        return "Scans, dictées et bilan dans la limite du gratuit."
    }

    // MARK: - Code promo

    /// Ouvre la feuille Apple de saisie d'un code, puis attend vraiment que
    /// l'accès s'ouvre avant de répondre. La feuille système ne dit jamais si
    /// un code a été saisi : le message d'échec ne parle donc pas de « code
    /// invalide », il constate seulement qu'aucun accès n'est apparu.
    private func saisirCodePromo() async {
        guard !isRedeemingPromo else { return }
        isRedeemingPromo = true
        defer { isRedeemingPromo = false }

        switch await subscriptionService.saisirCodePromo() {
        case .active:
            var message = "Ton accès Premium est ouvert. Tout est débloqué dès maintenant."
            if let entitlement = subscriptionService.customerInfo?
                .entitlements[SubscriptionService.entitlementId],
               let expiration = entitlement.expirationDate {
                let date = expiration.formatted(date: .abbreviated, time: .omitted)
                message += entitlement.willRenew
                    ? " Renouvellement le \(date)."
                    : " Actif jusqu'au \(date)."
            }
            promoResultMessage = message
            AnalyticsService.shared.track(.subscriptionStarted, properties: [
                "package": "code_promo",
            ])
        case .aucuneActivation:
            promoResultMessage = "Aucun code n'a été appliqué. Si tu viens d'en saisir un, laisse-lui quelques secondes puis touche « Restaurer mes achats »."
        }
        showPromoResult = true
    }
}

// MARK: - Mon compte

/// Le profil au sens strict : prénom, adresse e-mail, mot de passe. Rien
/// d'autre — les objectifs et le questionnaire ont leur propre entrée.
///
/// Le mot de passe ne se change que sur un compte créé par e-mail : un compte
/// Apple ou Google n'en a pas chez nous, on le dit plutôt que de proposer un
/// champ qui ne servirait à rien.
struct CompteReglagesView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var dashboardVM: DashboardViewModel

    /// « email », « apple », « google »… ; `nil` tant qu'on ne sait pas.
    @State private var fournisseur: String?
    @State private var montreMotDePasse = false

    private var prenom: String {
        let nom = dashboardVM.firstName.trimmingCharacters(in: .whitespaces)
        return nom.isEmpty ? "Toi" : nom
    }

    private var noteConnexion: String? {
        switch fournisseur {
        case "apple": return "Tu te connectes avec Apple : ton mot de passe se gère dans ton identifiant Apple."
        case "google": return "Tu te connectes avec Google : ton mot de passe se gère dans ton compte Google."
        default: return nil
        }
    }

    var body: some View {
        ZStack {
            Color.dsFond.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSGroupedList {
                        LigneIdentite(prenom: prenom, email: authViewModel.userEmail,
                                      avatarKey: dashboardVM.profile.avatarKey, taille: 56, chevron: false)
                    }
                    .padding(.top, DS.marge)

                    DSSectionHeader(titre: "Identifiants")
                    DSGroupedList {
                        DSRow(titre: "Prénom", valeur: prenom) { EmptyView() }
                        DSSeparator()
                        DSRow(titre: "Adresse e-mail", valeur: authViewModel.userEmail ?? "Non renseignée") { EmptyView() }
                        if fournisseur == "email" {
                            DSSeparator()
                            Button {
                                HapticService.shared.tap()
                                montreMotDePasse = true
                            } label: {
                                DSRow(titre: "Changer mon mot de passe")
                            }
                            .buttonStyle(.dsPress)
                        }
                    }

                    Text(noteConnexion ?? "Ton prénom se modifie dans les informations du questionnaire, famille Profil.")
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DS.paddingCarte)
                        .padding(.top, 8)
                }
                .padding(.horizontal, DS.marge)
                .padding(.bottom, DS.marge)
                .containerRelativeFrame(.horizontal)
            }
        }
        .navigationTitle("Mon compte")
        .navigationBarTitleDisplayMode(.inline)
        .kiwiNavigationBarBackground()
        .task { fournisseur = await AuthService.shared.fournisseurDuCompte() }
        .sheet(isPresented: $montreMotDePasse) {
            MotDePasseSheet()
        }
    }
}

/// Nouveau mot de passe, saisi deux fois, vérifié par `PasswordValidator`
/// (les mêmes règles qu'à l'inscription) avant tout envoi.
private struct MotDePasseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var nouveau = ""
    @State private var confirmation = ""
    @State private var enCours = false
    @State private var erreur: String?

    private var problemes: [PasswordValidationIssue] { PasswordValidator.validate(nouveau) }
    private var identiques: Bool { !confirmation.isEmpty && nouveau == confirmation }
    private var valide: Bool { problemes.isEmpty && identiques }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSGroupedList {
                        SecureField("Nouveau mot de passe", text: $nouveau)
                            .textContentType(.newPassword)
                            .font(.dsCorps)
                            .padding(.horizontal, DS.paddingCarte)
                            .frame(minHeight: DS.cibleTactile + 6)
                            .accessibilityLabel("Nouveau mot de passe")
                        DSSeparator()
                        SecureField("Confirme-le", text: $confirmation)
                            .textContentType(.newPassword)
                            .font(.dsCorps)
                            .padding(.horizontal, DS.paddingCarte)
                            .frame(minHeight: DS.cibleTactile + 6)
                            .accessibilityLabel("Confirmation du nouveau mot de passe")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if !nouveau.isEmpty {
                            ForEach(Array(problemes.enumerated()), id: \.offset) { _, probleme in
                                Text(probleme.message)
                            }
                        }
                        if !confirmation.isEmpty, !identiques {
                            Text("Les deux mots de passe ne sont pas identiques.")
                        }
                        if let erreur {
                            Text(erreur).foregroundStyle(Color.dsACombler)
                        }
                    }
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.paddingCarte)
                    .padding(.top, 10)

                    DSCapsuleButton(titre: "Enregistrer", chargement: enCours) {
                        Task { await enregistrer() }
                    }
                    .disabled(!valide || enCours)
                    .opacity(valide ? 1 : 0.5)
                    .padding(.top, 22)
                }
                .padding(.horizontal, DS.marge)
                .padding(.top, DS.marge)
                .containerRelativeFrame(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.dsFond.ignoresSafeArea())
            .navigationTitle("Mot de passe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                        .disabled(enCours)
                }
            }
            .interactiveDismissDisabled(enCours)
        }
        .presentationDetents([.medium, .large])
    }

    private func enregistrer() async {
        guard valide, !enCours else { return }
        enCours = true
        erreur = nil
        do {
            try await AuthService.shared.updatePassword(newPassword: nouveau)
            HapticService.shared.success()
            ToastService.shared.confirmer("Mot de passe mis à jour")
            dismiss()
        } catch {
            HapticService.shared.error()
            erreur = "Le changement n'a pas abouti. Vérifie ta connexion puis réessaie."
            AppLogger.app.report(error, context: "Reglages update password")
        }
        enCours = false
    }
}

// MARK: - Mes objectifs

/// Les objectifs du questionnaire, modifiables d'ici. Les options viennent du
/// questionnaire lui-même (`QuestionnaireSection`), jamais d'une liste recopiée :
/// c'est ce qui garantit que le Plan reconnaît la valeur enregistrée.
struct ObjectifsReglagesView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel

    @State private var selection: Set<String> = []
    @State private var charge = false
    @State private var enCours = false
    @State private var erreur: String?

    private let options = QuestionnaireSection.optionPairs(id: "goals")

    /// La sélection dans l'ordre du questionnaire (un `Set` n'en a pas).
    private var ordonnee: [String] { options.map(\.0).filter(selection.contains) }

    private var modifie: Bool { charge && ordonnee != dashboardVM.profile.goals }

    var body: some View {
        ZStack {
            Color.dsFond.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ce que tu veux changer. Ton plan s'organise autour.")
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.marge)
                        .padding(.horizontal, 4)

                    DSGroupedList {
                        ForEach(Array(options.enumerated()), id: \.element.0) { index, option in
                            if index > 0 { DSSeparator() }
                            ligne(id: option.0, libelle: option.1)
                        }
                    }
                    .padding(.top, DS.interCarte)

                    if modifie {
                        DSCapsuleButton(titre: "Enregistrer", chargement: enCours) {
                            Task { await enregistrer() }
                        }
                        .disabled(enCours)
                        .padding(.top, 22)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, DS.marge)
                .padding(.bottom, DS.marge)
                .containerRelativeFrame(.horizontal)
            }
        }
        .navigationTitle("Mes objectifs")
        .navigationBarTitleDisplayMode(.inline)
        .kiwiNavigationBarBackground()
        .onAppear {
            guard !charge else { return }
            selection = Set(dashboardVM.profile.goals)
            charge = true
        }
        .alert(
            "Erreur de sauvegarde",
            isPresented: Binding(get: { erreur != nil }, set: { if !$0 { erreur = nil } })
        ) {
            Button("OK", role: .cancel) { erreur = nil }
        } message: {
            Text(erreur ?? "")
        }
    }

    private func ligne(id: String, libelle: String) -> some View {
        let choisi = selection.contains(id)
        return Button {
            HapticService.shared.selection()
            if choisi { selection.remove(id) } else { selection.insert(id) }
        } label: {
            DSRow(titre: libelle) {
                Image(systemName: choisi ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(choisi ? Color.dsAccent : Color.dsTertiaire)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(libelle)
        .accessibilityValue(choisi ? "choisi" : "non choisi")
        .accessibilityAddTraits(choisi ? [.isButton, .isSelected] : .isButton)
    }

    /// Même écriture que l'éditeur du questionnaire : UPDATE du profil, avec
    /// reprise réseau. En cas d'échec, le profil en mémoire retrouve ses
    /// objectifs d'avant — l'écran ne ment pas sur ce qui est enregistré.
    private func enregistrer() async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }

        guard SupabaseService.shared.safeClient != nil,
              let session = await AuthService.shared.currentSession else {
            erreur = "Connexion indisponible. Réessaie dans un instant."
            HapticService.shared.error()
            return
        }

        let avant = dashboardVM.profile.goals
        dashboardVM.profile.goals = ordonnee
        do {
            try await NetworkService.shared.withRetry {
                try await DatabaseService.shared.saveProfile(
                    userId: session.user.id.uuidString,
                    email: session.user.email ?? "",
                    firstName: dashboardVM.profile.firstName,
                    questionnaireData: dashboardVM.profile
                )
            }
            // Les objectifs pèsent sur les cibles du jour : on recalcule.
            dashboardVM.computeLocalScores()
            HapticService.shared.success()
            ToastService.shared.confirmer("Objectifs mis à jour")
        } catch {
            dashboardVM.profile.goals = avant
            erreur = "Impossible de sauvegarder. Vérifie ta connexion et réessaie."
            HapticService.shared.error()
            AppLogger.database.error("Objectifs save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Supprimer mon compte

/// Suppression du compte (RGPD art. 17, exigée par App Store 5.1.1(v)). Elle
/// garde son double verrou : alerte, puis mot « SUPPRIMER » à taper. L'export
/// (art. 20) et les textes légaux vivent désormais sur la page Réglages.
struct SuppressionCompteView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject private var gamification = GamificationService.shared

    // Suppression de compte (deux étapes, Apple HIG)
    @State private var showDeleteFirstConfirm = false
    @State private var showDeleteSecondConfirm = false
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?

    /// Le bouton de confirmation ne s'active que lorsque l'utilisateur a tapé
    /// le mot « SUPPRIMER ». Comparaison insensible à la casse et espaces
    /// parasites de l'autocomplétion retirés.
    private var isDeleteConfirmed: Bool {
        deleteConfirmationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == "SUPPRIMER"
    }

    var body: some View {
        ZStack {
            Color.dsFond.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Text("Ton compte et tout ce qu'il contient.")
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DS.marge)
                        .padding(.bottom, DS.interCarte)
                        .padding(.horizontal, 4)
                    DSGroupedList {
                        Button(role: .destructive) {
                            showDeleteFirstConfirm = true
                        } label: {
                            DSRow(icone: "trash", iconeCouleur: .dsACombler, titre: "Supprimer mon compte") {
                                EmptyView()
                            }
                        }
                        .buttonStyle(.dsPress)
                        .disabled(isDeletingAccount)
                    }
                    Text("La suppression de ton compte est définitive. Toutes tes données (profil, bilan, historique, scans) seront effacées tout de suite et ne pourront pas être récupérées. Cette action est requise par le RGPD (Article 17 : droit à l'effacement).")
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DS.paddingCarte)
                        .padding(.top, 8)
                }
                .padding(.horizontal, DS.marge)
                .padding(.bottom, DS.marge)
            }
        }
        .navigationTitle("Supprimer mon compte")
        .navigationBarTitleDisplayMode(.inline)
        .kiwiNavigationBarBackground()
        // 1re confirmation : alerte rapide, style Apple.
        .alert("Supprimer ton compte ?", isPresented: $showDeleteFirstConfirm) {
            Button("Annuler", role: .cancel) { }
            Button("Continuer", role: .destructive) {
                deleteConfirmationText = ""
                deleteErrorMessage = nil
                showDeleteSecondConfirm = true
            }
        } message: {
            Text("Cette action est irréversible. Tu vas perdre ton bilan, ton historique, tes scans et tous tes rappels. Continue seulement si tu es sûr(e).")
        }
        // 2e confirmation : mot tapé pour prouver l'intention (RGPD + Apple review).
        .sheet(isPresented: $showDeleteSecondConfirm) {
            deleteAccountConfirmationSheet
                .healthMapFullSheet()
        }
    }

    // MARK: - Feuille de confirmation de suppression (2e étape)
    /// Detent .large + contenu scrollable (aucune superposition, quel que soit
    /// Dynamic Type) ; boutons épinglés via `safeAreaInset` (toujours visibles
    /// au-dessus du clavier) ; « Annuler » doublé dans la barre de navigation.
    /// La logique métier (`performDeleteAccount`) est inchangée.
    private var deleteAccountConfirmationSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingLG) {
                    VStack(spacing: Theme.spacingMD) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.urgencyImmediate)
                            .accessibilityHidden(true)

                        Text("Confirmation finale")
                            .font(.dsSection)
                            .foregroundStyle(Color.dsTexte)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.spacingMD)

                    VStack(alignment: .leading, spacing: Theme.spacingSM) {
                        bulletRow("Ton profil et ton bilan seront effacés")
                        bulletRow("Ton historique de scores sera effacé")
                        bulletRow("Tes scans et tes rappels seront effacés")
                        bulletRow("Ton abonnement Premium ne sera PAS annulé automatiquement (gère-le dans Réglages > Apple ID)")
                        bulletRow("Cette action est IRRÉVERSIBLE")
                    }

                    VStack(alignment: .leading, spacing: Theme.spacingSM) {
                        Text("Pour confirmer, tape le mot **SUPPRIMER** (majuscules ou minuscules) :")
                            .font(.dsCorps)
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)

                        TextField("Tape SUPPRIMER ici", text: $deleteConfirmationText)
                            .font(.dsCorps)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .padding(Theme.spacingMD)
                            .frame(minHeight: 44)
                            .background(Color.dsCarte)
                            .clipShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous)
                                    .strokeBorder(
                                        isDeleteConfirmed ? Color.urgencyImmediate : Color.dsSeparateur,
                                        lineWidth: 1
                                    )
                            )
                            .accessibilityLabel("Champ de confirmation. Tape le mot SUPPRIMER pour activer la suppression.")

                        if isDeleteConfirmed {
                            Label("Confirmation reconnue", systemImage: "checkmark.circle.fill")
                                .font(.dsLegendeMoyenne)
                                .foregroundStyle(Color.urgencyImmediate)
                        }
                    }

                    if let errorMessage = deleteErrorMessage {
                        Text(errorMessage)
                            .font(.dsLegende)
                            .foregroundStyle(Color.urgencyImmediate)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.bottom, Theme.spacingLG)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.dsFond)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.spacingSM) {
                    Button {
                        HapticService.shared.warning()
                        Task { await performDeleteAccount() }
                    } label: {
                        HStack(spacing: Theme.spacingSM) {
                            if isDeletingAccount {
                                ProgressView().tint(.white)
                                Text("Suppression en cours...")
                            } else {
                                Image(systemName: "trash")
                                Text("Supprimer définitivement")
                            }
                        }
                        .font(.dsHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.hauteurBouton)
                        .background(
                            Capsule().fill(isDeleteConfirmed ? Color.urgencyImmediate : Color.dsTertiaire)
                        )
                    }
                    .buttonStyle(.dsPress)
                    .disabled(!isDeleteConfirmed || isDeletingAccount)
                    .accessibilityHint(isDeleteConfirmed
                        ? "Supprime ton compte tout de suite et définitivement."
                        : "Tape d'abord le mot SUPPRIMER dans le champ de confirmation.")

                    Button {
                        showDeleteSecondConfirm = false
                    } label: {
                        Text("Annuler")
                            .font(.dsHeadline)
                            .foregroundStyle(Color.dsAccent)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPress)
                    .disabled(isDeletingAccount)
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.vertical, Theme.spacingSM)
                .background(Color.dsFond)
            }
            .navigationTitle("Supprimer mon compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        showDeleteSecondConfirm = false
                    }
                    .disabled(isDeletingAccount)
                }
            }
            // Swipe-down bloqué UNIQUEMENT pendant la suppression en vol.
            .interactiveDismissDisabled(isDeletingAccount)
            .onDisappear {
                deleteConfirmationText = ""
                deleteErrorMessage = nil
            }
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(Color.urgencyImmediate)
            Text(text)
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func performDeleteAccount() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        deleteErrorMessage = nil

        AnalyticsService.shared.track(.accountDeletionRequested)

        let success = await authViewModel.deleteAccount()
        isDeletingAccount = false

        if success {
            AnalyticsService.shared.track(.accountDeletionCompleted)
            HapticService.shared.success()
            gamification.reset()

            // Refermer la feuille AVANT de basculer `isAuthenticated`, sinon
            // SwiftUI fond MainTabView → AuthView par-dessus la feuille encore
            // ouverte et l'utilisateur voit un flash.
            showDeleteSecondConfirm = false

            // Un tick d'animation pour laisser la feuille se refermer (350 ms =
            // courbe de fermeture par défaut sur iOS 17), puis route vers AuthView.
            try? await Task.sleep(nanoseconds: 350_000_000)
            authViewModel.finaliseSignOutAfterDeletion()
        } else {
            AnalyticsService.shared.track(.accountDeletionFailed)
            HapticService.shared.error()
            deleteErrorMessage = authViewModel.errorMessage ?? "La suppression n'a pas abouti. Réessaie ou écris au support."
        }
    }
}
