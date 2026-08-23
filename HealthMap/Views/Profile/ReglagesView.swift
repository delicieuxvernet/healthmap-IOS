import SwiftUI
import StoreKit
import RevenueCat

// MARK: - Réglages (refonte « qualité Apple », 23 août 2026)
//
// Ex-`ProfileView` (feuille ouverte depuis un avatar), devenu le 5e ONGLET.
// Voir en permanence où l'on gère son abonnement et ses données est un signal
// de contrôle massif. C'est aussi LE SEUL endroit de l'app qui parle d'argent :
// la carte Premium vit ici, calme, sans capitales, sans emoji, sans compte à
// rebours. Les autres onglets ne portent plus de CTA vert pleine largeur.
//
// Structure (maquette `Kiwio iOS - refonte.dc.html`, écran 6) :
//   1. avatar 88 pt sur pastille `#E9F2E2` + prénom 22 / 700 ;
//   2. carte Kiwio Premium (3 bénéfices, bouton capsule, mention de prix) ;
//   3. « Mon compte » : profil et objectifs · sauvegarde · abonnement · Apple Santé ;
//   4. transparence : données et confidentialité · méthode et sources.
// Puis, pour ne perdre AUCUNE fonction de l'ancien profil : mon bilan
// (récap animé, évolution du score), progression (série, badges), mode Zen,
// déconnexion, numéro de build.
//
// Toute la logique (restauration, code promo, export RGPD, suppression de
// compte, récap) est reprise telle quelle de l'ancien `ProfileView`.
struct ReglagesView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @ObservedObject private var gamification = GamificationService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    /// Liaison Apple Santé : HealthKit ne révèle pas le statut d'autorisation de
    /// lecture, l'intention est portée par l'app (même clé que `EditProfileView`).
    @AppStorage("healthkit_linked") private var healthLinked = false
    @State private var showPaywall = false
    @State private var showManageSubscriptions = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dsFond.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        identite
                            .padding(.top, 16)

                        if subscriptionService.isPremium {
                            premiumActiveCard.padding(.top, 18)
                        } else if dashboardVM.bilanComplete {
                            // Entrée libre (V12a) : la porte premium n'apparaît
                            // qu'une fois le bilan fait (décision fondateur).
                            premiumCard.padding(.top, 18)
                        }

                        DSSectionHeader(titre: "Mon compte")
                        compteList

                        transparenceList
                            .padding(.top, 14)

                        DSSectionHeader(titre: "Mon bilan")
                        bilanList

                        if !gamification.isZenMode {
                            DSSectionHeader(titre: "Progression")
                            progressionList
                        }

                        DSSectionHeader(titre: "Préférences")
                        preferencesList

                        deconnexion
                            .padding(.top, DS.avantSection)

                        version
                            .padding(.top, DS.marge)
                            .padding(.bottom, DS.marge)
                    }
                    .padding(.horizontal, DS.marge)
                    .containerRelativeFrame(.horizontal)
                }
            }
            .kiwiTabBarBottomInset()
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .kiwiNavigationBarBackground()
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "reglages")
                    .healthMapFullSheet()
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        }
    }

    // MARK: - Identité

    private var identite: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.dsAccentPale)
                if let variant = AvatarVariant(key: dashboardVM.profile.avatarKey) {
                    Image(variant.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 30, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.dsAccent)
                }
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            Text(prenom)
                .font(.system(.title3, design: .default).weight(.bold))
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Profil de \(prenom)")
    }

    private var prenom: String {
        let nom = dashboardVM.firstName.trimmingCharacters(in: .whitespaces)
        if !nom.isEmpty { return nom }
        if let email = authViewModel.userEmail, let local = email.split(separator: "@").first {
            return String(local)
        }
        return "Toi"
    }

    // MARK: - Carte Premium (le seul paywall de l'app)

    private var premiumCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Kiwio Premium")
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)

            VStack(alignment: .leading, spacing: 12) {
                benefice("testtube.2", "Toutes tes vitamines et minéraux")
                benefice("map", "Ton plan complet, pas à pas")
                benefice("chart.xyaxis.line", "Tes courbes dans le temps")
            }
            .padding(.top, 16)

            DSCapsuleButton(titre: PremiumOffre.titreEssai(offerings: subscriptionService.offerings,
                                                          produits: subscriptionService.directProducts)) {
                HapticService.shared.tap()
                showPaywall = true
            }
            .padding(.top, 20)

            Text(PremiumOffre.mentionPrix(offerings: subscriptionService.offerings,
                                          produits: subscriptionService.directProducts))
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .task {
            // Les formules arrivent en cache au lancement ; si elles manquent
            // encore (réseau lent), on les demande pour afficher le vrai prix.
            if subscriptionService.offerings == nil && subscriptionService.directProducts.isEmpty {
                await subscriptionService.loadOfferings()
            }
        }
    }

    private func benefice(_ icone: String, _ texte: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icone)
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.dsAccent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(texte)
                .font(.dsCorps)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Abonné : la carte ne vend rien, elle rassure. Échéance lue depuis
    /// l'entitlement RevenueCat, jamais inventée.
    private var premiumActiveCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.dsAccent)
                    .accessibilityHidden(true)
                Text("Kiwio Premium")
                    .font(.dsSection)
                    .tracking(DSTracking.section)
                    .foregroundStyle(Color.dsTexte)
            }
            Text(echeance ?? "Actif. Tout est débloqué.")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showManageSubscriptions = true
            } label: {
                HStack(spacing: 6) {
                    Text("Gérer mon abonnement")
                        .font(.dsSousTitreFort)
                        .foregroundStyle(Color.dsAccent)
                    DSChevron(couleur: .dsAccent)
                }
                .frame(minHeight: DS.cibleTactile)
                .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)
            .padding(.top, 8)
            .accessibilityHint("Ouvre la gestion de ton abonnement (modifier ou annuler) dans les réglages Apple.")
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var echeance: String? {
        guard let ent = subscriptionService.customerInfo?.entitlements[SubscriptionService.entitlementId],
              let exp = ent.expirationDate else { return nil }
        let date = exp.formatted(date: .abbreviated, time: .omitted)
        return ent.willRenew ? "Actif. Renouvellement le \(date)." : "Actif jusqu'au \(date)."
    }

    // MARK: - Mon compte

    private var compteList: some View {
        DSGroupedList {
            NavigationLink {
                EditProfileView()
                    .environmentObject(dashboardVM)
            } label: {
                DSRow(icone: "person.crop.circle", titre: "Mon profil et mes objectifs",
                      sousTitre: authViewModel.userEmail)
            }
            .buttonStyle(.dsPress)

            DSSeparator(retrait: DS.retraitSeparateurIcone)

            NavigationLink {
                AbonnementReglagesView()
                    .environmentObject(dashboardVM)
            } label: {
                DSRow(icone: "creditcard", titre: "Mon abonnement",
                      valeur: subscriptionService.isPremium ? "Premium" : "Gratuit")
            }
            .buttonStyle(.dsPress)

            DSSeparator(retrait: DS.retraitSeparateurIcone)

            // La liaison Apple Santé se fait dans le profil (import poids,
            // pas, sommeil) : la ligne y mène et dit l'état courant.
            NavigationLink {
                EditProfileView()
                    .environmentObject(dashboardVM)
            } label: {
                DSRow(icone: "heart", titre: "Apple Santé",
                      valeur: healthLinked ? "Connecté" : "Non connecté")
            }
            .buttonStyle(.dsPress)
        }
    }

    // MARK: - Transparence

    private var transparenceList: some View {
        DSGroupedList {
            NavigationLink {
                DonneesReglagesView()
                    .environmentObject(authViewModel)
            } label: {
                DSRow(icone: "lock", titre: "Mes données et confidentialité")
            }
            .buttonStyle(.dsPress)

            DSSeparator(retrait: DS.retraitSeparateurIcone)

            NavigationLink {
                MethodeView()
            } label: {
                DSRow(icone: "book.closed", titre: "Notre méthode et nos sources")
            }
            .buttonStyle(.dsPress)
        }
    }

    // MARK: - Mon bilan

    private var bilanList: some View {
        DSGroupedList {
            // Rejouer le récap : la séquence se regarde une fois à chaud, et se
            // revoit à froid. Présentée par la racine (MainTabView) : une feuille
            // plein écran ouverte depuis un onglet ne s'ouvrait pas (21 août 2026).
            if dashboardVM.analysisV2 != nil {
                Button {
                    HapticService.shared.tap()
                    NotificationCenter.default.post(name: .healthmapRejouerRecap, object: nil)
                } label: {
                    DSRow(icone: "play.circle", titre: "Revoir mon bilan animé")
                }
                .buttonStyle(.dsPress)

                DSSeparator(retrait: DS.retraitSeparateurIcone)
            }

            NavigationLink {
                ScoreHistoryView()
                    .environmentObject(dashboardVM)
            } label: {
                DSRow(icone: "chart.line.uptrend.xyaxis", titre: "Évolution du score")
            }
            .buttonStyle(.dsPress)
        }
    }

    // MARK: - Progression (gamification, silencieuse en mode Zen)

    private var progressionList: some View {
        DSGroupedList {
            DSRow(icone: "flame", titre: "Série actuelle",
                  valeur: "\(gamification.currentStreak) jours") { EmptyView() }
            DSSeparator(retrait: DS.retraitSeparateurIcone)
            DSRow(icone: "star", titre: "Meilleure série",
                  valeur: "\(gamification.bestStreak) jours") { EmptyView() }
            DSSeparator(retrait: DS.retraitSeparateurIcone)
            DSRow(icone: "checkmark.seal", titre: "Total des check-ins",
                  valeur: "\(gamification.totalCheckins)") { EmptyView() }
            DSSeparator(retrait: DS.retraitSeparateurIcone)
            DSRow(icone: "medal", titre: "Badges",
                  valeur: "\(gamification.earnedBadges.count)/\(BadgeType.allCases.count)") { EmptyView() }
        }
    }

    // MARK: - Préférences

    private var preferencesList: some View {
        DSGroupedList {
            Toggle(isOn: Binding(
                get: { gamification.isZenMode },
                set: { _ in gamification.toggleZenMode() }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: "leaf")
                        .font(.system(size: 21, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.dsSecondaire)
                        .frame(width: 21)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mode Zen")
                            .font(.dsCorps)
                            .tracking(DSTracking.corps)
                            .foregroundStyle(Color.dsTexte)
                        Text("Désactive les badges, les confettis et les notifications")
                            .font(.dsLegende)
                            .tracking(DSTracking.legende)
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(Color.dsAccent)
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Déconnexion, version

    private var deconnexion: some View {
        Button(role: .destructive) {
            Task {
                gamification.reset()
                await authViewModel.signOut()
            }
        } label: {
            Text("Se déconnecter")
                .font(.dsCorps)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsACombler)
                .frame(maxWidth: .infinity, minHeight: DS.cibleTactile + 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .dsCard()
    }

    /// Numéro de version + build : permet de vérifier d'un coup d'œil QUEL
    /// build TestFlight tourne réellement sur l'appareil.
    private var version: some View {
        Text("Kiwio v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
            .font(.dsLegende)
            .foregroundStyle(Color.dsSecondaire)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Formules : titre d'essai et mention de prix (depuis StoreKit, jamais codés en dur)

/// Lit l'offre réelle (RevenueCat ou repli StoreKit) pour écrire le bouton et
/// la mention de la carte Premium. On ne promet jamais un essai ou un prix qui
/// n'existe pas côté App Store : sans formule chargée, on reste générique.
enum PremiumOffre {
    private static func options(offerings: Offerings?, produits: [StoreProduct]) -> [PlanOption] {
        var options = (offerings?.current?.availablePackages ?? [])
            .map { PlanOption(product: $0.storeProduct, package: $0) }
        let known = Set(options.map(\.id))
        options += produits
            .filter { !known.contains($0.productIdentifier) }
            .map { PlanOption(product: $0, package: nil) }
        return options
    }

    /// La formule mise en avant : l'annuelle (celle qui porte l'essai), sinon
    /// la première disponible.
    private static func formule(offerings: Offerings?, produits: [StoreProduct]) -> PlanOption? {
        let all = options(offerings: offerings, produits: produits)
        return all.first { $0.periodUnit == .year } ?? all.first
    }

    /// « 7 jours » / « 1 mois », lu depuis l'offre d'introduction StoreKit.
    static func essai(_ plan: PlanOption?) -> String? {
        guard let discount = plan?.introductoryDiscount, discount.paymentMode == .freeTrial else { return nil }
        let period = discount.subscriptionPeriod
        switch period.unit {
        case .day: return "\(period.value) jours"
        case .week: return "\(period.value * 7) jours"
        case .month: return period.value == 1 ? "1 mois" : "\(period.value) mois"
        case .year: return period.value == 1 ? "1 an" : "\(period.value) ans"
        }
    }

    /// « Essayer 7 jours gratuits », ou « Découvrir Kiwio Premium » sans essai.
    static func titreEssai(offerings: Offerings?, produits: [StoreProduct]) -> String {
        if let essai = essai(formule(offerings: offerings, produits: produits)) {
            return "Essayer \(essai) gratuits"
        }
        return "Découvrir Kiwio Premium"
    }

    /// « Puis 30,00 € par an. Résiliable à tout moment. »
    static func mentionPrix(offerings: Offerings?, produits: [StoreProduct]) -> String {
        guard let plan = formule(offerings: offerings, produits: produits) else {
            return "Résiliable à tout moment."
        }
        let periode: String
        switch plan.periodUnit {
        case .year: periode = "par an"
        case .week: periode = "par semaine"
        case .day: periode = "par jour"
        default: periode = "par mois"
        }
        let prefixe = essai(plan) == nil ? "" : "Puis "
        return "\(prefixe)\(plan.localizedPriceString) \(periode). Résiliable à tout moment."
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

    @State private var isRestoringPurchases = false
    @State private var restoreResultMessage: String?
    @State private var showRestoreResult = false

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
                            Task { await restorePurchases() }
                        } label: {
                            DSRow(icone: "arrow.clockwise", titre: "Restaurer mes achats") {
                                if isRestoringPurchases { ProgressView() } else { DSChevron() }
                            }
                        }
                        .buttonStyle(.dsPress)
                        .disabled(isRestoringPurchases)
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
        .alert("Restaurer mes achats", isPresented: $showRestoreResult) {
            Button("OK", role: .cancel) { }
        } message: {
            if let restoreResultMessage { Text(restoreResultMessage) }
        }
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

    // MARK: - Restore Purchases (App Store Guideline 3.1.1)

    private func restorePurchases() async {
        guard !isRestoringPurchases else { return }
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            try await subscriptionService.restorePurchases()
            if subscriptionService.isPremium {
                restoreResultMessage = "Achats restaurés. Bienvenue dans Premium !"
                AnalyticsService.shared.track(.subscriptionRestored, properties: [
                    "outcome": "success",
                ])
            } else {
                restoreResultMessage = "Aucun achat à restaurer pour cet identifiant Apple. Si tu penses qu'il y a une erreur, écris au support."
                AnalyticsService.shared.track(.subscriptionRestored, properties: [
                    "outcome": "no_purchase",
                ])
            }
        } catch {
            restoreResultMessage = "La restauration n'a pas abouti. Vérifie ta connexion puis réessaie, ou écris au support."
            AnalyticsService.shared.track(.subscriptionRestored, properties: [
                "outcome": "error",
            ])
            AppLogger.subscription.report(error, context: "ReglagesView restore purchases")
        }

        showRestoreResult = true
    }
}

// MARK: - Mes données et confidentialité

/// RGPD en un seul endroit : export (art. 20), textes légaux, suppression du
/// compte (art. 17, exigée par App Store 5.1.1(v)). La suppression garde son
/// double verrou : alerte, puis mot « SUPPRIMER » à taper.
struct DonneesReglagesView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject private var gamification = GamificationService.shared

    // Export RGPD
    @State private var isExportingData = false
    @State private var showExportOfflineAlert = false

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
                    DSSectionHeader(titre: "Mes données")
                        .padding(.top, -DS.avantSection + DS.marge)
                    DSGroupedList {
                        Button {
                            Task { await exportUserData() }
                        } label: {
                            DSRow(icone: "square.and.arrow.up", titre: "Exporter mes données",
                                  sousTitre: "Pour les confier à une IA, les archiver ou les réutiliser ailleurs") {
                                if isExportingData { ProgressView() } else { DSChevron() }
                            }
                        }
                        .buttonStyle(.dsPress)
                        .disabled(isExportingData)
                        .accessibilityHint("Télécharge toutes tes données Kiwio au format JSON (RGPD Article 20).")
                    }

                    DSSectionHeader(titre: "Légal")
                    DSGroupedList {
                        Link(destination: URL(string: "https://healthmap.fr/privacy")!) {
                            DSRow(icone: "hand.raised", titre: "Politique de confidentialité") {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.dsTertiaire)
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.dsPress)
                        DSSeparator(retrait: DS.retraitSeparateurIcone)
                        Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                            DSRow(icone: "doc.text", titre: "Conditions d'utilisation") {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.dsTertiaire)
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.dsPress)
                    }

                    DSSectionHeader(titre: "Supprimer mon compte")
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
        .navigationTitle("Mes données")
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
        .alert("Hors ligne", isPresented: $showExportOfflineAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("L'export a besoin d'une connexion internet pour récupérer toutes tes données. Reconnecte-toi puis réessaie.")
        }
    }

    // MARK: - RGPD Data Export (Article 20)

    private func exportUserData() async {
        guard !isExportingData else { return }

        guard ConnectivityService.shared.isOnline else {
            showExportOfflineAlert = true
            return
        }

        isExportingData = true
        defer { isExportingData = false }

        guard let session = await AuthService.shared.currentSession else { return }
        let userId = session.user.id.uuidString

        do {
            let (data, filename) = try await DataExportService.shared.generateExport(
                userId: userId,
                authEmail: authViewModel.userEmail
            )
            DataExportService.shared.presentShareSheet(data: data, filename: filename)
        } catch {
            AppLogger.app.report(error, context: "ReglagesView data export")
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
