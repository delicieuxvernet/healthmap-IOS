import SwiftUI
import StoreKit

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var connectivity: ConnectivityService
    @EnvironmentObject var pushService: PushNotificationService
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Durée plancher du splash : garantit que le réveil du kiwi (≈550 ms) est
    /// toujours vu, même quand l'auth se résout instantanément (utilisateur
    /// déconnecté / première ouverture, sans aller-retour réseau).
    @State private var minSplashElapsed = false

    /// Le splash reste affiché tant que l'auth charge OU que la durée plancher
    /// n'est pas écoulée.
    private var showLaunch: Bool { authViewModel.isLoading || !minSplashElapsed }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if showLaunch {
                    LaunchScreenView()
                } else if !hasSeenOnboarding {
                    OnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
                } else if !authViewModel.isAuthenticated {
                    // Page de garde animée (mascotte + wordmark + CTA).
                    // L'authentification s'ouvre en sheet depuis LandingView —
                    // un utilisateur non connecté n'atterrit JAMAIS directement
                    // sur un formulaire de connexion plein écran.
                    LandingView()
                } else {
                    MainTabView()
                        // Force SwiftUI to destroy and recreate MainTabView (and
                        // its @StateObject DashboardViewModel/QuestionnaireViewModel)
                        // whenever the authenticated user changes. Without this,
                        // SwiftUI may REUSE the same @StateObject across different
                        // users since the structural identity ("else" branch) is
                        // the same, causing User B to see User A's cached data.
                        .id(authViewModel.session?.user.id ?? UUID())
                }
            }
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: authViewModel.isAuthenticated)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: hasSeenOnboarding)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: showLaunch)

            // Global offline banner — shows above every screen when the phone
            // loses connectivity. Sits at the top because the tab bar already
            // occupies the bottom and anything pinned there would fight with
            // iOS home indicator gestures.
            if !connectivity.isOnline {
                OfflineBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }

            // Global toast overlay — surfaces ToastService messages (nutrient
            // facts, motivational tips) across all tabs. Zero-config for
            // callers : just call `ToastService.shared.showActionToast()`.
            ToastOverlayView()
                .zIndex(2)
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: connectivity.isOnline)
        .task {
            // Premium au démarrage (cold start), non bloquant pour le splash :
            // l'app connaît l'état d'abonnement et a les offerings en cache même
            // si le paywall n'a pas encore été ouvert (robustesse RevenueCat).
            Task {
                await SubscriptionService.shared.checkPremiumStatus()
                await SubscriptionService.shared.loadOfferings()
            }
            // Durée plancher du splash (≈0,9 s) — le réveil du kiwi est toujours vu.
            try? await Task.sleep(for: .seconds(0.9))
            minSplashElapsed = true
        }
        // Universal Links: when the user taps a `https://healthmap.fr/...`
        // link in Mail, Messages, Safari, or any other app, iOS routes the
        // activity here because the app's entitlements declare
        // `applinks:healthmap.fr` and the apex domain serves a valid
        // `apple-app-site-association` file.
        //
        // We translate the URL into the SAME `DeepLinkRoute` primitive that
        // push notifications use, then queue it on
        // `PushNotificationService.pendingRoute`. From there,
        // `MainTabView.consumePendingRoute()` handles cold start (`.onAppear`)
        // and warm start (`.onChange`) — keeping push, universal link, and
        // marketing-link cold-launch flows on a single converged path.
        //
        // Sitting on the root `ContentView` (not `MainTabView`) is
        // intentional: a Universal Link tapped while the user is signed
        // out still queues `pendingRoute`, so the moment they finish auth
        // and `MainTabView` mounts, `.onAppear` consumes it. The link
        // never gets dropped just because the app was at the auth wall.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            handleUniversalLink(activity)
        }
        // Session-expiry notice. `AuthViewModel.startRefreshTimer` flips this
        // flag right before signing out when the refresh token has been
        // revoked or expired (10-minute background tick). Surfacing the
        // alert here on the root means it works regardless of whether the
        // user is currently in MainTabView (got bounced) or already at
        // LandingView (cold start with a stale token). The single-shot pattern
        // (`isPresented:` bool flipped back to false on dismissal) ensures
        // the alert never re-fires after the user acknowledges it.
        .alert(
            "Votre session a expire",
            isPresented: $authViewModel.sessionExpiredNotice
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Pour des raisons de securite, vous avez ete deconnecte. Reconnectez-vous pour continuer.")
        }
    }

    /// Parses an incoming Universal Link and queues a `DeepLinkRoute` for
    /// `MainTabView` to consume. Defensive at every step:
    ///   - Wrong activity type → ignore (shouldn't happen because the
    ///     modifier filters by `NSUserActivityTypeBrowsingWeb`, but a
    ///     belt-and-braces guard costs nothing).
    ///   - Missing `webpageURL` → ignore.
    ///   - Wrong host → ignore. Apple's AASA validation already enforces
    ///     this on its side, but we double-check in case Apple ever
    ///     loosens the contract or a malicious sibling app re-broadcasts
    ///     a NSUserActivity. Subdomains are NOT accepted — only `healthmap.fr`.
    ///   - Unknown path → falls back to `.dashboard` via
    ///     `DeepLinkRoute.fromURLPath` so the user always lands somewhere
    ///     usable instead of being silently swallowed.
    private func handleUniversalLink(_ activity: NSUserActivity) {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL else {
            AppLogger.push.notice("Ignoring continueUserActivity without browsing-web URL")
            return
        }

        guard let host = url.host?.lowercased(), host == "healthmap.fr" else {
            AppLogger.push.notice("Rejecting universal link with unexpected host: \(url.host ?? "nil", privacy: .public)")
            return
        }

        let route = PushNotificationService.DeepLinkRoute.fromURLPath(url.path)

        AppLogger.push.info("Universal link received: \(url.absoluteString, privacy: .public) -> \(route.rawValue, privacy: .public)")
        CrashReportingService.shared.breadcrumb(
            "universal link \(route.rawValue)",
            category: "navigation",
            level: .info
        )
        AnalyticsService.shared.track(.screenViewed, properties: [
            "from_universal_link": "true",
            "route": route.rawValue,
        ])

        pushService.pendingRoute = route
    }
}

// MARK: - Offline Banner
/// Thin red pill shown at the top of the screen while `ConnectivityService`
/// reports no reachability. Non-blocking — the user can still tap underneath,
/// which is the correct behavior because cached data (questionnaire progress,
/// dashboard snapshot, score history) remains usable offline.
private struct OfflineBanner: View {
    @State private var showReconnected = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 13, weight: .semibold))
                Text("Hors ligne — certaines donnees ne sont pas a jour")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.urgencyImmediate)
            )

            if showReconnected {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Reconnecte — synchronisation...")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.healthMapBlue)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hors ligne. Certaines donnees ne sont pas a jour.")
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("healthmapDidReconnect"))) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                showReconnected = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showReconnected = false
                }
            }
        }
    }
}

// MARK: - Launch Screen
struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            WarmBackground()
            VStack(spacing: 22) {
                // Logo en contour épuré (le demi-kiwi réduit à ses traits, monochrome).
                KiwiContourMark(size: 104, color: .kiwiCharcoal)
                Text("Kiwio")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.kiwiCharcoal)
                ProgressView()
                    .tint(Color.kiwiGreen)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var pushService: PushNotificationService
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var dashboardVM = DashboardViewModel()
    @StateObject private var questionnaireVM = QuestionnaireViewModel()
    @ObservedObject private var gamification = GamificationService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Currently selected tab. Driven by user taps in the normal flow and by
    /// `PushNotificationService.pendingRoute` when the app is launched or
    /// resumed from a notification tap (see `consumePendingRoute`).
    @State private var selectedTab: Tab = .bilan

    /// Shown when a notification or deep link asks us to surface the paywall
    /// (e.g. renewal reminder, upsell). Kept separate from the `Profil` tab
    /// so the route doesn't force a tab switch on top of the sheet.
    @State private var showPaywallFromDeepLink = false

    /// Profil présenté en sheet (l'onglet Profil a été remplacé par Mes
    /// compléments — P6) : ouvert par l'avatar du Bilan, la route deep-link
    /// `.profile`, ou une nav-card `.profil`.
    @State private var showProfile = false

    /// Tab tour — shown once after the user completes the questionnaire.
    @AppStorage("hasSeenTabTour") private var hasSeenTabTour = false
    @State private var showTabTour = false

    /// Internal tab identifier. Uses a symbolic enum rather than `Int` so
    /// adding or reordering tabs doesn't silently break the deep-link mapping.
    enum Tab: Hashable {
        case bilan, suivi, scanner, plan, complements
    }

    // La réservation d'espace pour la barre flottante vit désormais DANS
    // chaque écran d'onglet (`.kiwiTabBarBottomInset()` appliqué au contenu
    // racine, à l'intérieur de son NavigationStack) : posée ici — sur le
    // TabView ou sur les Groups d'onglets — elle ne se propage pas à la safe
    // area du scroll (hébergement UIKit), le contenu défilait sous la barre
    // (bug persistant builds 179→202).

    var body: some View {
        // Tant que le PREMIER chargement du profil n'est pas terminé, on tient
        // le MÊME écran de chargement que le splash racine : la transition
        // splash → ici est invisible (pixels identiques), et surtout on ne rend
        // JAMAIS le questionnaire / les onglets verrouillés avec un état encore
        // inconnu (fin du clignotement d'« écrans faux » au démarrage à froid).
        Group {
            if dashboardVM.didFinishInitialLoad {
                mainInterface
            } else {
                LaunchScreenView()
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.3),
                   value: dashboardVM.didFinishInitialLoad)
    }

    private var mainInterface: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Bilan (Dashboard or Questionnaire)
            Group {
                if dashboardVM.hasCompletedQuestionnaire {
                    DashboardView()
                        .environmentObject(dashboardVM)
                } else {
                    QuestionnaireContainerView()
                        .environmentObject(questionnaireVM)
                        .environmentObject(dashboardVM)
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("Bilan", systemImage: "heart.text.clipboard") }
            .tag(Tab.bilan)

            // Tab 2: Suivi (DESIGN-PAGES §4 — découverte + actif)
            Group {
                if dashboardVM.hasCompletedQuestionnaire {
                    SuiviView()
                        .environmentObject(dashboardVM)
                } else {
                    LockedFeatureView(title: "Suivi", message: "Complete ton bilan pour acceder au suivi quotidien.")
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("Suivi", systemImage: "checkmark.circle") }
            .tag(Tab.suivi)

            // Tab 3: Scanner (MealScan)
            Group {
                if dashboardVM.hasCompletedQuestionnaire {
                    MealScanView()
                        .environmentObject(dashboardVM)
                } else {
                    LockedFeatureView(title: "Scanner", message: "Complete ton bilan pour scanner tes repas.")
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("Scanner", systemImage: "camera") }
            .tag(Tab.scanner)

            // Tab 4: Mon Plan (Recommendations)
            Group {
                if dashboardVM.hasCompletedQuestionnaire {
                    RecommendationsView()
                        .environmentObject(dashboardVM)
                } else {
                    LockedFeatureView(title: "Mon Plan", message: "Complete ton bilan pour acceder a ton plan personnalise.")
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("Plan", systemImage: "list.bullet.clipboard") }
            .tag(Tab.plan)

            // Tab 5: Mes compléments (remplace Profil — P6). Le Profil devient
            // un bouton avatar en haut à droite du Bilan (sheet ci-dessous).
            Group {
                if dashboardVM.hasCompletedQuestionnaire {
                    SupplementsView()
                        .environmentObject(dashboardVM)
                } else {
                    LockedFeatureView(title: "Mes compléments", message: "Complete ton bilan pour voir tes compléments.")
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("Compléments", systemImage: "pills") }
            .tag(Tab.complements)
        }
        .tint(Color.kiwiGreen)
        // Tab bar flottante (langage v4). ⚠️ L'inset posé sur le TabView dessine
        // la barre mais NE se propage PAS aux écrans des onglets (TabView =
        // conteneur UIKit : chaque onglet a sa propre safe area) — le contenu
        // passait dessous (bug build 198). La réservation d'espace se fait donc
        // DANS chaque écran via `.kiwiTabBarBottomInset()` ; ici on ne fait que
        // dessiner la pill au-dessus du home indicator.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // La barre flottante n'apparaît qu'une fois le bilan complété.
            // Pendant le questionnaire (onglet Bilan = QuestionnaireContainerView),
            // elle est masquée : sinon elle chevauche le bouton « Continuer » et
            // laisse miroiter des onglets verrouillés. EmptyView sinon → l'inset
            // ne réserve aucune hauteur, le questionnaire occupe tout l'écran.
            if dashboardVM.hasCompletedQuestionnaire {
                KiwiFloatingTabBar(selected: $selectedTab)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .background(Color.kiwiCream.ignoresSafeArea(edges: .bottom))
            }
        }
        // Overlay de célébrations gamification (« Badge débloqué / Niveau
        // supérieur ») retiré le 28 juin 2026 : feedback jugé « cheap ».
        // Les badges/XP/séries restent suivis en silence côté GamificationService.
        .onAppear {
            // Tab bar appearance
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.systemBackground
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.secondaryLabel
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.secondaryLabel,
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
            ]
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.kiwiGreen)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor(Color.kiwiGreen),
                .font: UIFont.systemFont(ofSize: 11, weight: .bold)
            ]
            appearance.shadowColor = UIColor.black.withAlphaComponent(0.08)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance

            gamification.recordCheckin()
            // Consume any pending route queued while MainTabView did not exist
            // (e.g. cold start from a notification tap — the delegate fires
            // before SwiftUI has built this view).
            consumePendingRoute()

            // Trigger tab tour for first-time users who completed the questionnaire
            if dashboardVM.hasCompletedQuestionnaire && !hasSeenTabTour {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showTabTour = true
                }
            }
        }
        .sheet(isPresented: $showPaywallFromDeepLink) {
            PaywallView()
                .healthMapFullSheet()
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
                .environmentObject(dashboardVM)
                .environmentObject(authViewModel)
        }
        .overlay {
            if showTabTour {
                TabTourOverlay(isShowing: $showTabTour)
            }
        }
        .onChange(of: showTabTour) { _, newValue in
            if !newValue && !hasSeenTabTour {
                hasSeenTabTour = true
            }
        }
        // Fix: onAppear doesn't re-fire when the questionnaire is completed
        // inside MainTabView (Bilan tab). This onChange catches the transition.
        .onChange(of: dashboardVM.hasCompletedQuestionnaire) { _, completed in
            if completed && !hasSeenTabTour {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showTabTour = true
                }
            }
        }
        .onChange(of: pushService.pendingRoute) { _, newValue in
            // Consume routes arriving while the view is already alive
            // (warm start — user taps notification while app is backgrounded).
            guard newValue != nil else { return }
            consumePendingRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: .healthmapNavigateToTab)) { notification in
            guard let raw = notification.object as? String,
                  let dest = NavCardDestination(rawValue: raw) else { return }
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) {
                switch dest {
                case .bilan: selectedTab = .bilan
                case .suivi: selectedTab = .suivi
                case .scanner: selectedTab = .scanner
                case .plan: selectedTab = .plan
                case .complements: selectedTab = .complements
                case .profil: showProfile = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .healthmapOpenProfile)) { _ in
            showProfile = true
        }
        // BLOCAGE pendant la 1re analyse IA (retour test 20 juin) : tant que le
        // bilan n'est pas prêt, on couvre TOUTE l'app (barre d'onglets comprise)
        // -> impossible de naviguer ailleurs. Se ferme automatiquement dès que le
        // résultat arrive (analysisV2 != nil). En cas d'échec : écran Réessayer,
        // jamais de scores bruts. Un utilisateur revenant avec un bilan en cache
        // ne voit pas cet écran (analysisV2 est non-nil quasi immédiatement).
        //
        // ⚠️ Gardé sur analysisV2 (bilan v2, réellement affiché par DashboardView
        // v6), PAS sur aiAnalysis (v7, legacy) — incident du 4 juillet : la gate
        // bloquait sur un raté du flux v7 pendant que le VRAI bilan (v2) avait
        // déjà réussi en arrière-plan, forçant des "Réessayer" inutiles qui
        // épuisaient le quota gratuit partagé (v7+v2 comptent sur le même
        // endpoint côté serveur) sur le tout premier bilan d'un compte neuf.
        .fullScreenCover(isPresented: Binding(
            get: { dashboardVM.analysisV2 == nil && (dashboardVM.isLoadingAnalysisV2 || dashboardVM.errorMessageV2 != nil) },
            set: { _ in }
        )) {
            AnalysisGateView()
                .environmentObject(dashboardVM)
        }
    }

    /// Routes a queued `DeepLinkRoute` to the matching tab or modal, then
    /// clears `pendingRoute` so it's not processed twice. Called from both
    /// `.onAppear` (cold start) and `.onChange` (warm start) — the nil-check
    /// inside makes both paths safe no-ops when there's nothing queued.
    private func consumePendingRoute() {
        guard let route = pushService.pendingRoute else { return }

        switch route {
        case .dashboard:
            selectedTab = .bilan
        case .checkin:
            selectedTab = .suivi
        case .mealScan:
            selectedTab = .scanner
        case .recommendations:
            selectedTab = .plan
        case .profile:
            showProfile = true
        case .paywall:
            // Don't force a tab switch on top of the modal — keep the user
            // on whatever tab they were already looking at when the paywall
            // appears so the dismissal feels continuous.
            showPaywallFromDeepLink = true
        }

        AppLogger.push.info("Consumed deep-link route \(route.rawValue, privacy: .public)")
        pushService.pendingRoute = nil
    }
}

// MARK: - Analysis Gate (bloque la navigation pendant la 1re analyse IA)
// Présenté en fullScreenCover par MainTabView : couvre toute l'app (barre
// d'onglets incluse) tant que le bilan n'est pas prêt. Affiche l'écran de
// chargement, ou un écran « Réessayer » en cas d'échec — jamais de scores
// bruts, et l'utilisateur ne peut pas naviguer ailleurs (retour test 20 juin).
private struct AnalysisGateView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel

    var body: some View {
        ZStack {
            WarmBackground().ignoresSafeArea()
            if !dashboardVM.isLoadingAnalysisV2, let errorMessage = dashboardVM.errorMessageV2 {
                AnalysisErrorRetryView(
                    message: errorMessage,
                    isRetrying: false,
                    onRetry: { Task { await dashboardVM.triggerAnalysis() } }
                )
            } else {
                FullAnalysisLoadingView()
            }
        }
    }
}

// MARK: - Locked Feature Placeholder
struct LockedFeatureView: View {
    let title: String
    let message: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.healthMapMuted)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.healthMapBackground)
            .navigationTitle(title)
        }
    }
}

// MARK: - Profile View (complete with gamification, settings, etc.)
struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @ObservedObject private var gamification = GamificationService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showPaywall = false
    @State private var showManageSubscriptions = false

    // Delete account flow state (two-step confirmation per Apple HIG).
    @State private var showDeleteFirstConfirm = false
    @State private var showDeleteSecondConfirm = false
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?

    // Restore Purchases state — required by Apple App Store Review for any
    // app with subscriptions (Guideline 3.1.1). Without an explicit Restore
    // affordance, a user who reinstalls the app or signs in on a new device
    // has no way to recover their existing entitlement and Apple rejects
    // the build automatically.
    @State private var isRestoringPurchases = false
    @State private var restoreResultMessage: String?
    @State private var showRestoreResult = false

    // RGPD Data Export state
    @State private var isExportingData = false

    /// Le bouton de confirmation ne s'active que lorsque l'utilisateur a tapé
    /// le mot « SUPPRIMER ». Comparaison insensible à la casse (taper
    /// « supprimer » suffit — pas de piège lié au clavier iOS) et espaces
    /// parasites de l'autocomplétion retirés, pour ne jamais laisser le
    /// bouton bloqué à tort.
    private var isDeleteConfirmed: Bool {
        deleteConfirmationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == "SUPPRIMER"
    }

    var body: some View {
        NavigationStack {
            List {
                // Account section
                Section("Compte") {
                    if let email = authViewModel.userEmail {
                        LabeledContent("Email", value: email)
                    }

                    if subscriptionService.isPremium {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(Color.healthMapBlue)
                            Text("Premium")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.healthMapText)
                        }

                        // Date de renouvellement / expiration — lue depuis le SDK
                        // RevenueCat (customerInfo), pas besoin d'appel serveur.
                        if let ent = subscriptionService.customerInfo?.entitlements["premium"],
                           let exp = ent.expirationDate {
                            LabeledContent(
                                ent.willRenew ? "Renouvellement" : "Expire le",
                                value: exp.formatted(date: .abbreviated, time: .omitted)
                            )
                        }

                        // Gerer / annuler — ouvre la feuille systeme d'abonnements
                        // Apple (l'annulation in-app passe obligatoirement par la).
                        Button {
                            showManageSubscriptions = true
                        } label: {
                            HStack {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(Color.healthMapBlue)
                                Text("Gerer mon abonnement")
                                    .foregroundStyle(Color.healthMapBlue)
                            }
                        }
                        .accessibilityHint("Ouvre la gestion de ton abonnement (modifier ou annuler) dans les reglages Apple.")
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(Color.healthMapBlue)
                                Text("Passer a Premium")
                                    .foregroundStyle(Color.healthMapBlue)
                            }
                        }
                    }

                    // Restore Purchases — visible regardless of `isPremium` so
                    // that an existing subscriber who reinstalls the app or
                    // signs in on a new device can always recover their
                    // entitlement. Required by App Store Review Guideline
                    // 3.1.1; reviewers actively look for this affordance.
                    Button {
                        Task { await restorePurchases() }
                    } label: {
                        HStack {
                            if isRestoringPurchases {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(Color.healthMapBlue)
                            }
                            Text("Restaurer mes achats")
                                .foregroundStyle(Color.healthMapBlue)
                        }
                    }
                    .disabled(isRestoringPurchases)
                    .accessibilityHint("Restaure un abonnement Premium achete precedemment avec ce meme identifiant Apple.")
                }

                // Quick links
                Section("Mon bilan") {
                    NavigationLink {
                        EditProfileView()
                            .environmentObject(dashboardVM)
                    } label: {
                        Label("Modifier mon profil", systemImage: "pencil.circle")
                    }

                    NavigationLink {
                        ScoreHistoryView()
                            .environmentObject(dashboardVM)
                    } label: {
                        Label("Evolution du score", systemImage: "chart.xyaxis.line")
                    }

                    if dashboardVM.hasCompletedQuestionnaire {
                        NavigationLink {
                            SupplementsView()
                                .environmentObject(dashboardVM)
                        } label: {
                            Label("Mes complements", systemImage: "pills")
                        }
                    }

                    NavigationLink {
                        MethodeView()
                    } label: {
                        Label("Notre methode", systemImage: "brain")
                    }
                }

                // Gamification
                if !gamification.isZenMode {
                    Section("Progression") {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(Color.accentSky)
                            Text("Serie actuelle")
                            Spacer()
                            Text("\(gamification.currentStreak) jours")
                                .foregroundStyle(Color.healthMapSecondary)
                        }

                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Color.accentSky)
                            Text("Meilleure serie")
                            Spacer()
                            Text("\(gamification.bestStreak) jours")
                                .foregroundStyle(Color.healthMapSecondary)
                        }

                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color.healthMapBlue)
                            Text("Check-ins total")
                            Spacer()
                            Text("\(gamification.totalCheckins)")
                                .foregroundStyle(Color.healthMapSecondary)
                        }

                        HStack {
                            Image(systemName: "medal.fill")
                                .foregroundStyle(Color.healthMapBlue)
                            Text("Badges")
                            Spacer()
                            Text("\(gamification.earnedBadges.count)/\(BadgeType.allCases.count)")
                                .foregroundStyle(Color.healthMapSecondary)
                        }
                    }
                }

                // Legal
                Section("Legal") {
                    Link(destination: URL(string: "https://healthmap.fr/privacy")!) {
                        Label("Politique de confidentialite", systemImage: "hand.raised.fill")
                    }

                    Link(destination: URL(string: "https://healthmap.fr/terms")!) {
                        Label("Conditions d'utilisation", systemImage: "doc.text.fill")
                    }
                }

                // Settings
                Section("Preferences") {
                    Toggle(isOn: Binding(
                        get: { gamification.isZenMode },
                        set: { _ in gamification.toggleZenMode() }
                    )) {
                        HStack {
                            Image(systemName: "leaf.fill")
                                .foregroundStyle(Color.healthMapBlue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mode Zen")
                                Text("Desactive badges, confetti et notifications")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.healthMapSecondary)
                            }
                        }
                    }
                }

                // RGPD — Data Export (Article 20)
                Section("Mes donnees") {
                    Button {
                        Task { await exportUserData() }
                    } label: {
                        HStack {
                            if isExportingData {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(Color.healthMapBlue)
                            }
                            Text("Exporter mes donnees")
                                .foregroundStyle(Color.healthMapBlue)
                        }
                    }
                    .disabled(isExportingData)
                    .accessibilityHint("Telecharge toutes tes donnees Kiwio au format JSON (RGPD Article 20).")
                }

                // Sign out
                Section {
                    Button("Se deconnecter", role: .destructive) {
                        Task {
                            gamification.reset()
                            await authViewModel.signOut()
                        }
                    }
                }

                // Danger zone — permanent account deletion
                // Required by Apple App Store guideline 5.1.1(v): apps that support
                // account creation must provide in-app account deletion.
                // We intentionally let SwiftUI apply the system destructive tint
                // (red) here, matching the "Se deconnecter" button above. Brand
                // rule "tout bleu" applies to decorative accents, not safety
                // affordances — Apple HIG explicitly reserves red for danger.
                Section {
                    Button(role: .destructive) {
                        showDeleteFirstConfirm = true
                    } label: {
                        Label("Supprimer mon compte", systemImage: "trash")
                    }
                    .disabled(isDeletingAccount)
                } header: {
                    Text("Zone dangereuse")
                } footer: {
                    Text("La suppression de ton compte est definitive. Toutes tes donnees (profil, bilan, historique, scans) seront effacees immediatement et ne pourront pas etre recuperees. Cette action est requise par le RGPD (Article 17 — droit a l'effacement).")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.healthMapSecondary)
                }

                // Numero de version + build, visible en bas du profil. Permet de
                // verifier d'un coup d'oeil QUEL build TestFlight tourne reellement
                // sur l'appareil (le build number = github.run_number du workflow).
                Section {
                    HStack {
                        Spacer()
                        Text("Kiwio v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.healthMapSecondary)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
            // Ruban de fond aussi sur le Profil (loi 2) : on masque le fond
            // système de la List puis on glisse le ruban derrière.
            .scrollContentBackground(.hidden)
            .background(WarmBackground())
            .navigationTitle("Profil")
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .healthMapFullSheet()
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            // 1st confirmation — quick Apple-style alert
            .alert("Supprimer ton compte ?", isPresented: $showDeleteFirstConfirm) {
                Button("Annuler", role: .cancel) { }
                Button("Continuer", role: .destructive) {
                    deleteConfirmationText = ""
                    deleteErrorMessage = nil
                    showDeleteSecondConfirm = true
                }
            } message: {
                Text("Cette action est irreversible. Tu vas perdre ton bilan, ton historique, tes scans et tous tes rappels. Continue uniquement si tu es sur(e).")
            }
            // 2e confirmation — mot tapé pour prouver l'intention (RGPD + Apple review).
            // Detent .large obligatoire : le contenu (icône + bullets + champ +
            // boutons) ne tient PAS en .medium — en build 28 les textes se
            // superposaient (illisible) et le clavier masquait le bouton
            // Annuler. Le swipe-down reste actif : seul `isDeletingAccount`
            // le bloque (géré dans le sheet), jamais de blocage inconditionnel.
            .sheet(isPresented: $showDeleteSecondConfirm) {
                deleteAccountConfirmationSheet
                    .healthMapFullSheet()
            }
            // Export offline alert — the export needs Supabase data, so
            // block the request and explain why when offline.
            .alert("Hors ligne", isPresented: $showExportOfflineAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("L'export necessite une connexion internet pour recuperer toutes tes donnees. Reconnecte-toi puis reessaie.")
            }
            // Restore Purchases result alert. Uses the existing-message
            // pattern (no `presenting:`) so the alert can be reused for
            // both success ("Achats restaures") and failure ("Erreur...")
            // states without spinning up two separate alerts.
            .alert("Restaurer mes achats", isPresented: $showRestoreResult) {
                Button("OK", role: .cancel) { }
            } message: {
                if let restoreResultMessage {
                    Text(restoreResultMessage)
                }
            }
        }
    }

    // MARK: - Restore Purchases (App Store Guideline 3.1.1)

    /// Calls RevenueCat's `restorePurchases` and surfaces the result via an
    /// alert. Three branches:
    ///   1. Success + entitlement now active → "Achats restaures..."
    ///   2. Success + still no entitlement → "Aucun achat a restaurer..."
    ///      (the user genuinely never bought anything with this Apple ID)
    ///   3. Failure → "Erreur lors de la restauration..." with a retry hint
    /// All three are accompanied by analytics so we can monitor the
    /// real-world success rate of restores. The success path also fires
    /// `subscriptionRestored`, which the funnel uses to attribute later
    /// engagement to recovered subscribers.
    private func restorePurchases() async {
        guard !isRestoringPurchases else { return }
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            try await subscriptionService.restorePurchases()
            if subscriptionService.isPremium {
                restoreResultMessage = "Achats restaures. Bienvenue dans Premium !"
                AnalyticsService.shared.track(.subscriptionRestored, properties: [
                    "outcome": "success",
                ])
            } else {
                restoreResultMessage = "Aucun achat a restaurer pour cet identifiant Apple. Si tu penses qu'il y a une erreur, contacte le support."
                AnalyticsService.shared.track(.subscriptionRestored, properties: [
                    "outcome": "no_purchase",
                ])
            }
        } catch {
            restoreResultMessage = "Erreur lors de la restauration. Verifie ta connexion puis reessaie, ou contacte le support."
            AnalyticsService.shared.track(.subscriptionRestored, properties: [
                "outcome": "error",
            ])
            AppLogger.subscription.report(error, context: "ProfileView restore purchases")
        }

        showRestoreResult = true
    }

    // MARK: - RGPD Data Export (Article 20)

    @State private var showExportOfflineAlert = false

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
            AppLogger.app.report(error, context: "ProfileView data export")
        }
    }

    // MARK: - Delete account confirmation sheet (2e étape)
    /// Refonte UX (plainte fondateur, build 28) : l'ancien layout vivait dans
    /// un detent .medium sans ScrollView — les textes `fixedSize` débordaient
    /// et se chevauchaient (illisible), et le clavier masquait le bouton
    /// Annuler (utilisateur piégé, obligé de fermer l'app). Désormais :
    ///   - detent .large + contenu scrollable → plus aucune superposition,
    ///     quel que soit le réglage Dynamic Type ;
    ///   - boutons épinglés via `safeAreaInset` → TOUJOURS visibles
    ///     au-dessus du clavier pendant la saisie ;
    ///   - « Annuler » doublé dans la barre de navigation, actif en
    ///     permanence sauf pendant l'appel réseau de suppression.
    /// La logique métier (`performDeleteAccount`) est inchangée.
    private var deleteAccountConfirmationSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingLG) {
                    // En-tête avertissement
                    VStack(spacing: Theme.spacingMD) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.urgencyImmediate)
                            .accessibilityHidden(true)

                        Text("Confirmation finale")
                            .font(Theme.titleFont)
                            .foregroundStyle(Color.healthMapText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.spacingMD)

                    // Rappel des conséquences
                    VStack(alignment: .leading, spacing: Theme.spacingSM) {
                        bulletRow("Ton profil et ton bilan seront effaces")
                        bulletRow("Ton historique de scores sera efface")
                        bulletRow("Tes scans et rappels seront effaces")
                        bulletRow("Ton abonnement Premium ne sera PAS annule automatiquement (gere-le dans Reglages > Apple ID)")
                        bulletRow("Cette action est IRREVERSIBLE")
                    }

                    // Champ de confirmation — TextField natif : le placeholder
                    // disparaît dès la première lettre tapée, donc aucun label
                    // ne peut se superposer au texte saisi.
                    VStack(alignment: .leading, spacing: Theme.spacingSM) {
                        Text("Pour confirmer, tape le mot **SUPPRIMER** (majuscules ou minuscules) :")
                            .font(Theme.bodyFont)
                            .foregroundStyle(Color.healthMapText)
                            .fixedSize(horizontal: false, vertical: true)

                        TextField("Tape SUPPRIMER ici", text: $deleteConfirmationText)
                            .font(Theme.bodyFont)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .padding(Theme.spacingMD)
                            .frame(minHeight: 44)
                            .background(Color.healthMapCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                    .strokeBorder(
                                        isDeleteConfirmed ? Color.urgencyImmediate : Color.healthMapMuted.opacity(0.35),
                                        lineWidth: 1.5
                                    )
                            )
                            .accessibilityLabel("Champ de confirmation. Tape le mot SUPPRIMER pour activer la suppression.")

                        // Feedback immédiat : confirme que la saisie est reconnue.
                        if isDeleteConfirmed {
                            Label("Confirmation reconnue", systemImage: "checkmark.circle.fill")
                                .font(Theme.captionBoldFont)
                                .foregroundStyle(Color.urgencyImmediate)
                        }
                    }

                    // Erreur serveur éventuelle (suppression échouée)
                    if let errorMessage = deleteErrorMessage {
                        Text(errorMessage)
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.urgencyImmediate)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.bottom, Theme.spacingLG)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.healthMapBackground)
            // Boutons d'action épinglés en bas : `safeAreaInset` les maintient
            // au-dessus du clavier — « Annuler » et « Supprimer » restent donc
            // TOUJOURS visibles, même pendant la saisie (bug build 28 :
            // Annuler passait sous le clavier).
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
                                Text("Supprimer definitivement")
                            }
                        }
                        .font(Theme.headlineFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .fill(isDeleteConfirmed ? Color.urgencyImmediate : Color.healthMapMuted)
                        )
                    }
                    .buttonStyle(.healthMapPressed)
                    .disabled(!isDeleteConfirmed || isDeletingAccount)
                    .accessibilityHint(isDeleteConfirmed
                        ? "Supprime ton compte immediatement et definitivement."
                        : "Tape d'abord le mot SUPPRIMER dans le champ de confirmation.")

                    Button {
                        showDeleteSecondConfirm = false
                    } label: {
                        Text("Annuler")
                            .font(Theme.headlineFont)
                            .foregroundStyle(Color.healthMapBlue)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.healthMapPressed)
                    .disabled(isDeletingAccount)
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.vertical, Theme.spacingSM)
                .background(Color.healthMapBackground)
            }
            .navigationTitle("Supprimer mon compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Sortie évidente en permanence : « Annuler » dans la barre de
                // navigation (même pattern que EditFieldSheet), inactif
                // uniquement pendant l'appel réseau de suppression.
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        showDeleteSecondConfirm = false
                    }
                    .disabled(isDeletingAccount)
                }
            }
            // Swipe-down bloqué UNIQUEMENT pendant la suppression en vol
            // (état non-annulable côté serveur) — jamais inconditionnellement.
            .interactiveDismissDisabled(isDeletingAccount)
            // Défensif : on vide le champ à chaque disparition du sheet
            // (swipe-down, Annuler, suppression réussie). L'alerte de 1re
            // étape le réinitialise aussi avant ouverture — ceinture et
            // bretelles pour qu'aucun refactor futur ne laisse « SUPPRIMER »
            // pré-rempli d'une session à l'autre.
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
            // Text style relatif (pas de taille fixe) → suit Dynamic Type ;
            // le ScrollView parent absorbe le débordement éventuel.
            Text(text)
                .font(Theme.subheadlineFont)
                .foregroundStyle(Color.healthMapText)
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
            // Haptique de clôture — confirme physiquement que la suppression
            // a abouti (pattern HapticService déjà utilisé dans EditProfileView).
            HapticService.shared.success()
            // Reset local state (gamification cache, etc.) first.
            gamification.reset()

            // Dismiss the sheet BEFORE flipping `isAuthenticated`, otherwise
            // SwiftUI cross-fades MainTabView → AuthView over the still-open
            // confirmation sheet and the user sees a visible flash.
            showDeleteSecondConfirm = false

            // Give SwiftUI one animation tick to finish the sheet dismissal,
            // then route to AuthView. 350ms matches the default sheet
            // dismissal animation curve on iOS 17.
            try? await Task.sleep(nanoseconds: 350_000_000)
            authViewModel.finaliseSignOutAfterDeletion()
        } else {
            AnalyticsService.shared.track(.accountDeletionFailed)
            // Haptique d'erreur : la suppression a échoué, le sheet reste
            // ouvert avec le message d'erreur affiché.
            HapticService.shared.error()
            deleteErrorMessage = authViewModel.errorMessage ?? "Erreur lors de la suppression. Reessaie ou contacte le support."
        }
    }
}
