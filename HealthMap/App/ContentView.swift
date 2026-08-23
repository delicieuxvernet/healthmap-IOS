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
            "Ta session a expiré",
            isPresented: $authViewModel.sessionExpiredNotice
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Pour ta sécurité, tu as été déconnecté. Reconnecte-toi pour continuer.")
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
                Text("Hors ligne. Certaines données ne sont pas à jour")
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
                    Text("Reconnecté. Synchronisation...")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.healthMapBlue)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hors ligne. Certaines données ne sont pas à jour.")
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
                // Le logo EST l'indicateur d'attente : même dessin qu'au repos
                // (`KiwiContourMark`), pépins qui s'allument en traînée. Le
                // spinner sous le nom devenait redondant — il a sauté.
                KiwiLoader(size: 104, color: .kiwiCharcoal, showFibers: true)
                Text("Kiwio")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.kiwiCharcoal)
            }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var pushService: PushNotificationService
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var subscriptionService: SubscriptionService
    @StateObject private var dashboardVM = DashboardViewModel()
    @StateObject private var questionnaireVM = QuestionnaireViewModel()
    @ObservedObject private var gamification = GamificationService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Currently selected tab. Driven by user taps in the normal flow and by
    /// `PushNotificationService.pendingRoute` when the app is launched or
    /// resumed from a notification tap (see `consumePendingRoute`).
    @State private var selectedTab: Tab = .journal

    /// Shown when a notification or deep link asks us to surface the paywall
    /// (e.g. renewal reminder, upsell). Kept separate from the `Profil` tab
    /// so the route doesn't force a tab switch on top of the sheet.
    @State private var showPaywallFromDeepLink = false

    /// Tab tour — shown once after the user completes the questionnaire.
    @AppStorage("hasSeenTabTour") private var hasSeenTabTour = false
    @State private var showTabTour = false

    /// Récap animé : la séquence qui délivre le bilan juste après le
    /// questionnaire. Les slides sont construits UNE fois, au moment de
    /// présenter — pendant la lecture, plus rien n'est calculé ni chargé.
    @State private var slidesRecap: [RecapSlide] = []
    @State private var afficheRecap = false

    /// Tutoriel de première visite du Journal (3 bulles). Il vit ICI, au
    /// niveau de MainTabView, et PAS dans JournalView : la barre d'onglets est
    /// posée en `.overlay` sur `mainInterface`, donc elle se dessine par-dessus
    /// tout ce que l'onglet contient. Monté dans l'onglet, son voile sombre
    /// laissait la barre et le bouton d'ajout en pleine lumière, et tappables.
    /// Même placement que `TabTourOverlay`, pour la même raison.
    @AppStorage("hasSeenScanTour") private var scanTourVu = false
    @State private var montreTutoScan = false

    /// Identifiant d'onglet. Refonte du 23 août 2026 : cinq onglets qui
    /// nomment des OBJETS, pas des concepts. Le Bilan a fusionné dans le
    /// Journal (le tableau de bord du jour EST le journal), le Scan a quitté
    /// la barre (bouton d'ajout flottant du Journal), les Réglages y entrent.
    enum Tab: Hashable, CaseIterable, Identifiable {
        case journal, progres, plan, complements, reglages

        var id: Self { self }

        /// Position dans la barre d'onglets : c'est elle qui donne le SENS de
        /// la transition (aller vers un onglet à gauche = l'écran glisse vers
        /// la droite). Ne pas dériver de `allCases` ailleurs : l'ordre visuel
        /// de la barre est la seule référence.
        var position: Int {
            switch self {
            case .journal: return 0
            case .progres: return 1
            case .plan: return 2
            case .complements: return 3
            case .reglages: return 4
            }
        }

        /// Identifiant partagé avec les deep links (`NavCardDestination`), pour
        /// que les écrans puissent réagir à leur propre apparition. Les
        /// identifiants historiques sont conservés (contrats analytics et
        /// listeners existants) : `scanner` désigne le Journal, `suivi` les
        /// Progrès, `profil` les Réglages.
        var route: String {
            switch self {
            case .journal: return NavCardDestination.scanner.rawValue
            case .progres: return NavCardDestination.suivi.rawValue
            case .plan: return NavCardDestination.plan.rawValue
            case .complements: return NavCardDestination.complements.rawValue
            case .reglages: return NavCardDestination.profil.rawValue
            }
        }

        /// Onglet visé par une destination de navigation interne.
        static func pour(_ destination: NavCardDestination) -> Tab {
            switch destination {
            case .bilan, .scanner: return .journal
            case .suivi: return .progres
            case .plan: return .plan
            case .complements: return .complements
            case .profil: return .reglages
            }
        }
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

    /// Conteneur d'onglets maison (remplace `TabView` depuis le 28 juillet).
    ///
    /// Raison : un `TabView` bascule sans transition — on ne comprenait pas le
    /// LIEN entre les écrans. Ici, changer d'onglet fait GLISSER le contenu dans
    /// le sens de la barre : aller vers un onglet situé à gauche (ex. Compléments
    /// → Bilan via « combler par l'assiette ») fait glisser vers la droite.
    ///
    /// Les cinq onglets restent MONTÉS en permanence (comme le faisait TabView) :
    /// leur état — position de scroll, données déjà chargées, `@StateObject` —
    /// survit au changement d'onglet. Seuls l'offset, l'opacité et la capture
    /// tactile changent.
    /// Décalage horizontal d'un onglet. L'onglet courant est à 0 ; les autres
    /// attendent hors écran, du côté qui correspond à leur position dans la
    /// barre — c'est ce qui produit un sens de glissement toujours cohérent.
    /// Le sortant ne parcourt que 35 % de la largeur (effet de parallaxe).
    private func decalage(for tab: Tab, largeur: CGFloat) -> CGFloat {
        guard tab != selectedTab else { return 0 }
        let aGauche = tab.position < selectedTab.position
        return aGauche ? -largeur * 0.35 : largeur
    }

    /// Contenu d'un onglet. Entrée libre (V12a) : plus AUCUN verrou — les cinq
    /// onglets s'ouvrent sans questionnaire. Chaque écran porte son propre état
    /// vide sûr (le Bilan invite à faire le bilan, le Suivi montre ses courbes
    /// d'exemple, le Plan et les Compléments leur état vide existant) et aucun
    /// ViewModel ne déclenche `generate-analysis` sans `profile.completed`.
    /// Le questionnaire, lui, se présente en feuille via `demarrerBilan()`.
    @ViewBuilder
    private func tabContent(_ tab: Tab) -> some View {
        switch tab {
        case .journal:
            JournalView().environmentObject(dashboardVM)
        case .progres:
            SuiviView().environmentObject(dashboardVM)
        case .plan:
            RecommendationsView().environmentObject(dashboardVM)
        case .complements:
            SupplementsView().environmentObject(dashboardVM)
        case .reglages:
            ReglagesView()
                .environmentObject(dashboardVM)
                .environmentObject(authViewModel)
        }
    }

    private var mainInterface: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Tab.allCases) { tab in
                    tabContent(tab)
                        // Parallaxe : le sortant part à 35 % de la course, ce
                        // qui donne la profondeur (l'entrant « pousse »).
                        .offset(x: decalage(for: tab, largeur: geo.size.width))
                        .opacity(tab == selectedTab ? 1 : 0)
                        .allowsHitTesting(tab == selectedTab)
                        .accessibilityHidden(tab != selectedTab)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Pas de `.clipped()` ici : il rognait les fonds `ignoresSafeArea`
            // des onglets à la ligne de la barre d'état (bande blanche « hors
            // de l'app » en haut de chaque onglet). Rien à rogner par ailleurs :
            // les onglets non sélectionnés sont invisibles (opacity 0) et les
            // décalages horizontaux sortent de l'écran.
            .animation(reduceMotion ? .none : .easeOut(duration: 0.28), value: selectedTab)
        }
        // Les cinq onglets restent montés : `onAppear` ne se déclenche qu'une
        // fois, au lancement. Un écran qui rejoue une entrée à chaque visite
        // (la carte radiale du Plan) a besoin de ce signal-là.
        .onChange(of: selectedTab) { _, nouvel in
            NotificationCenter.default.post(
                name: .healthmapTabDidChange,
                object: nouvel.route
            )
            // Retour sur le Journal sans avoir vu ses 3 bulles : on les montre
            // (une seule fois dans la vie du compte). Jamais par-dessus le
            // tour d'onglets.
            if nouvel == .journal { armerTutoJournal() }
        }
        .ignoresSafeArea(.keyboard)
        .tint(Color.kiwiGreen)
        // Tab bar flottante (langage v4). ⚠️ SURIMPRESSION, pas `safeAreaInset` :
        // depuis le passage au conteneur maison (plus de TabView UIKit), un
        // inset posé ici se propagerait aux écrans — qui réservent DÉJÀ la
        // hauteur via `.kiwiTabBarBottomInset()`. On aurait donc un double
        // espacement. La réservation reste dans chaque écran, la barre se
        // contente de se dessiner par-dessus.
        .overlay(alignment: .bottom) {
            // Entrée libre (V12a) : la barre flottante est TOUJOURS visible —
            // les onglets s'ouvrent sans questionnaire. Le questionnaire ne
            // vit plus dans l'onglet Bilan mais dans une feuille plein écran
            // (voir la .sheet `questionnaireOuvert` plus bas), donc plus de
            // chevauchement possible avec son bouton « Continuer ».
            // v7 : la barre dessine elle-même son fond translucide pleine
            // largeur + sa hairline ; aucun encart ici, sinon le bouton
            // Scan surélevé se retrouverait rogné.
            KiwiFloatingTabBar(selected: $selectedTab)
        }
        // Overlay de célébrations gamification (« Badge débloqué / Niveau
        // supérieur ») retiré le 28 juin 2026 : feedback jugé « cheap ».
        // Les badges/XP/séries restent suivis en silence côté GamificationService.
        .onAppear {
            // Barre de navigation (refonte 23 août 2026) : grand titre 34 / 700
            // avec tracking optique −0,95, titre inline 17 / 600. Polices
            // mises à l'échelle par `UIFontMetrics` : Dynamic Type suit.
            let nav = UINavigationBar.appearance()
            nav.largeTitleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .largeTitle)
                    .scaledFont(for: UIFont.systemFont(ofSize: 34, weight: .bold)),
                .kern: -0.95,
                .foregroundColor: UIColor.label,
            ]
            nav.titleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .headline)
                    .scaledFont(for: UIFont.systemFont(ofSize: 17, weight: .semibold)),
                .foregroundColor: UIColor.label,
            ]

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
            // Le Journal est l'accueil : tableau de bord du jour et journal ne
            // font qu'un. Un lien profond ou une notification peut l'écraser.
            // Consume any pending route queued while MainTabView did not exist
            // (e.g. cold start from a notification tap — the delegate fires
            // before SwiftUI has built this view).
            consumePendingRoute()

            armerTourOnglets()
            armerTutoJournal()
        }
        .sheet(isPresented: $showPaywallFromDeepLink) {
            PaywallView()
                .healthMapFullSheet()
        }
        // Entrée libre (V12a) : le questionnaire se lance/reprend depuis
        // n'importe quel onglet via `dashboardVM.demarrerBilan()`. Feuille
        // plein écran (même style que l'édition du profil) : le glissement
        // vers le bas permet de sortir à tout moment — le draft est sauvegardé
        // en continu par QuestionnaireViewModel, la reprise se fait à la
        // question en cours. À la fermeture, l'onglet d'origine est intact.
        .sheet(isPresented: $dashboardVM.questionnaireOuvert) {
            QuestionnaireContainerView()
                .environmentObject(questionnaireVM)
                .environmentObject(dashboardVM)
                .healthMapFullSheet()
        }
        // Les deux coach marks sont posés ICI, APRÈS `mainInterface` : leur
        // voile couvre donc AUSSI la barre d'onglets flottante (elle-même en
        // overlay de `mainInterface`). Ne jamais les remonter dans un onglet.
        .overlay {
            if montreTutoScan && !showTabTour {
                ScanTutorialOverlay {
                    scanTourVu = true
                    withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) {
                        montreTutoScan = false
                    }
                }
            }
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
        .onChange(of: dashboardVM.hasCompletedQuestionnaire) { _, _ in
            armerTourOnglets()
        }
        // Le tour d'onglets attend que le bilan soit RÉELLEMENT à l'écran : tant
        // que `analysisV2` est nil, `AnalysisGateView` couvre tout en plein
        // écran. Armé sur un minuteur, le tour se révélait pile au moment où le
        // bilan apparaissait enfin — et le recouvrait.
        .onChange(of: dashboardVM.analysisV2 == nil) { _, _ in
            preparerRecap()
            armerTourOnglets()
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
                selectedTab = Tab.pour(dest)
            }
            // « Scanner » = le Journal avec sa feuille d'ajout ouverte : c'est
            // là que vit toute la saisie désormais.
            if dest == .scanner {
                NotificationCenter.default.post(name: .healthmapOuvrirAjout, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .healthmapOpenProfile)) { _ in
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) {
                selectedTab = .reglages
            }
        }
        // Relecture demandée depuis les Réglages (onglet, plus une feuille) :
        // la séquence est présentée ICI, par la racine, jamais depuis l'onglet.
        .onReceive(NotificationCenter.default.publisher(for: .healthmapRejouerRecap)) { _ in
            let slides = dashboardVM.construireRecap(estPremium: subscriptionService.isPremium)
            guard !slides.isEmpty else {
                // Ne jamais rester muet : si la séquence ne peut pas se construire,
                // on le dit au lieu de laisser croire à un bouton mort.
                ToastService.shared.showÉchecRecap()
                return
            }
            slidesRecap = slides
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                afficheRecap = true
            }
        }
        // Le récap se joue par-dessus tout, barre d'onglets comprise : c'est un
        // moment, pas un écran de plus. Il ne s'ouvre QUE s'il y a une séquence
        // — une analyse inexploitable laisse l'utilisateur sur son Bilan, sans
        // rien casser.
        .fullScreenCover(isPresented: $afficheRecap) {
            RecapView(slides: slidesRecap) {
                afficheRecap = false
                // Le tour d'onglets attendait la fin du récap : il peut passer.
                armerTourOnglets()
            }
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
        // `gateContournee` : la seule porte de sortie. Sans elle, un échec du
        // bilan enfermait l'utilisateur dans l'app — écran plein, aucun bouton
        // de fermeture, aucun onglet accessible.
        .fullScreenCover(isPresented: Binding(
            get: {
                !dashboardVM.gateContournee
                    && dashboardVM.analysisV2 == nil
                    && (dashboardVM.isLoadingAnalysisV2 || dashboardVM.errorMessageV2 != nil)
            },
            set: { _ in }
        )) {
            AnalysisGateView()
                .environmentObject(dashboardVM)
        }
    }

    /// Joue le récap animé si le questionnaire vient d'être terminé et que le
    /// bilan est arrivé. `recapArme` n'est posé que par la fin du questionnaire :
    /// un compte déjà installé ne se prend jamais la séquence à l'ouverture.
    private func preparerRecap() {
        guard dashboardVM.recapArme, dashboardVM.analysisV2 != nil, !afficheRecap else { return }
        let slides = dashboardVM.construireRecap(estPremium: subscriptionService.isPremium)
        // Séquence vide = analyse inexploitable : on désarme et on laisse le
        // Bilan classique faire son travail. Le récap ne bloque JAMAIS le parcours.
        dashboardVM.recapArme = false
        guard !slides.isEmpty else { return }
        slidesRecap = slides
        // Le récap s'ouvre à l'instant PRÉCIS où la gate d'analyse se referme
        // (les deux sont pilotées par l'arrivée de `analysisV2`). Deux
        // présentations plein écran qui se croisent dans le même cycle et
        // SwiftUI en avale une : on laisse la première finir de sortir.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !slidesRecap.isEmpty else { return }
            afficheRecap = true
        }
    }

    /// Arme le tour d'onglets — une seule fois par compte, et seulement quand
    /// il y a quelque chose à commenter : questionnaire fait ET bilan affiché
    /// (la gate d'analyse refermée). Appelé depuis les trois endroits qui
    /// peuvent réunir ces conditions ; les appels en trop sont sans effet.
    private func armerTourOnglets() {
        guard dashboardVM.hasCompletedQuestionnaire,
              dashboardVM.analysisV2 != nil,
              // Le récap passe AVANT le tour : deux surcouches en même temps,
              // et on ne lit ni l'une ni l'autre.
              !dashboardVM.recapArme,
              !afficheRecap,
              !hasSeenTabTour,
              !showTabTour else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard !hasSeenTabTour else { return }
            showTabTour = true
        }
    }

    /// Les 3 bulles du Journal : une seule fois dans la vie du compte, quand
    /// le Journal est à l'écran, jamais par-dessus le tour d'onglets.
    private func armerTutoJournal() {
        guard selectedTab == .journal, !scanTourVu, !montreTutoScan, !showTabTour else { return }
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.25)) {
            montreTutoScan = true
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
            selectedTab = .journal
        case .checkin:
            selectedTab = .progres
        case .mealScan:
            selectedTab = .journal
            NotificationCenter.default.post(name: .healthmapOuvrirAjout, object: nil)
        case .recommendations:
            selectedTab = .plan
        case .profile:
            selectedTab = .reglages
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
                    isRetrying: dashboardVM.isLoadingAnalysisV2,
                    onRetry: { Task { await dashboardVM.retryBilanV2() } },
                    onExplorer: {
                        dashboardVM.gateContournee = true
                        Task { await dashboardVM.retryBilanV2() }
                    }
                )
            } else {
                FullAnalysisLoadingView()
            }
        }
    }
}
