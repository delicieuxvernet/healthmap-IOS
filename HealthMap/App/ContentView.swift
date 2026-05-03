import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var connectivity: ConnectivityService
    @EnvironmentObject var pushService: PushNotificationService
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if authViewModel.isLoading {
                    LaunchScreenView()
                } else if !hasSeenOnboarding {
                    OnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
                } else if !authViewModel.isAuthenticated {
                    AuthView()
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
        // AuthView (cold start with a stale token). The single-shot pattern
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
            Color.healthMapBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "heart.text.clipboard")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.healthMapBlue)
                Text("HealthMap")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.healthMapText)
                ProgressView()
                    .tint(Color.healthMapBlue)
            }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var pushService: PushNotificationService
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

    /// Tab tour — shown once after the user completes the questionnaire.
    @AppStorage("hasSeenTabTour") private var hasSeenTabTour = false
    @State private var showTabTour = false

    /// Internal tab identifier. Uses a symbolic enum rather than `Int` so
    /// adding or reordering tabs doesn't silently break the deep-link mapping.
    enum Tab: Hashable {
        case bilan, suivi, scanner, plan, profil
    }

    var body: some View {
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
            .tabItem { Label("Bilan", systemImage: "heart.text.clipboard") }
            .tag(Tab.bilan)

            // Tab 2: Suivi (Checkin)
            Group {
                if dashboardVM.hasCompletedQuestionnaire {
                    CheckinView()
                        .environmentObject(dashboardVM)
                } else {
                    LockedFeatureView(title: "Suivi", message: "Complete ton bilan pour acceder au suivi quotidien.")
                }
            }
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
            .tabItem { Label("Mon Plan", systemImage: "list.bullet.clipboard") }
            .tag(Tab.plan)

            // Tab 5: Profil
            ProfileView()
                .environmentObject(dashboardVM)
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(Tab.profil)
        }
        .tint(Color.healthMapBlue)
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
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.healthMapBlue)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor(Color.healthMapBlue),
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
                case .profil: selectedTab = .profil
                }
            }
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
            selectedTab = .profil
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

    /// The confirmation button unlocks only when the user has typed the exact
    /// word "SUPPRIMER" — whitespace is trimmed so a trailing space from
    /// iOS autocomplete doesn't leave the button stuck disabled.
    private var isDeleteConfirmed: Bool {
        deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == "SUPPRIMER"
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
                    .accessibilityHint("Telecharge toutes tes donnees HealthMap au format JSON (RGPD Article 20).")
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
            }
            .navigationTitle("Profil")
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .healthMapFullSheet()
            }
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
            // 2nd confirmation — typed email/word to prove intent (RGPD + Apple review)
            .sheet(isPresented: $showDeleteSecondConfirm) {
                deleteAccountConfirmationSheet
                    .healthMapActionSheet()
                    .interactiveDismissDisabled(true) // critical: empêche dismiss accidental
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

    // MARK: - Delete account confirmation sheet (2nd step)
    private var deleteAccountConfirmationSheet: some View {
        NavigationStack {
            VStack(spacing: Theme.spacingLG) {
                Spacer().frame(height: Theme.spacingMD)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.urgencyImmediate)

                Text("Confirmation finale")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.healthMapText)

                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    bulletRow("Ton profil et ton bilan seront effaces")
                    bulletRow("Ton historique de scores sera efface")
                    bulletRow("Tes scans et rappels seront effaces")
                    bulletRow("Ton abonnement Premium ne sera PAS annule automatiquement (gere-le dans Reglages > Apple ID)")
                    bulletRow("Cette action est IRREVERSIBLE")
                }
                .padding(.horizontal, Theme.spacingLG)

                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    Text("Pour confirmer, tape le mot **SUPPRIMER** ci-dessous :")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.healthMapText)

                    TextField("SUPPRIMER", text: $deleteConfirmationText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color.healthMapCard)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }
                .padding(.horizontal, Theme.spacingLG)

                if let errorMessage = deleteErrorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.urgencyImmediate)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.spacingLG)
                }

                Spacer()

                VStack(spacing: Theme.spacingSM) {
                    Button {
                        Task { await performDeleteAccount() }
                    } label: {
                        HStack {
                            if isDeletingAccount {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "trash")
                                Text("Supprimer definitivement")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .fill(isDeleteConfirmed ? Color.urgencyImmediate : Color.healthMapMuted)
                        )
                    }
                    .disabled(!isDeleteConfirmed || isDeletingAccount)

                    Button("Annuler") {
                        showDeleteSecondConfirm = false
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(Color.healthMapBlue)
                    .disabled(isDeletingAccount)
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.bottom, Theme.spacingLG)
            }
            .background(Color.healthMapBackground)
            .navigationTitle("Supprimer mon compte")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isDeletingAccount)
            // Defensive: clear the confirmation field whenever the sheet
            // disappears (swipe-down, Annuler tap, successful deletion).
            // The 1st-step alert also resets it before opening the sheet,
            // so this is belt-and-braces — prevents any future refactor
            // from accidentally leaving "SUPPRIMER" pre-filled across
            // sessions.
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
                .font(.system(size: 13))
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
            deleteErrorMessage = authViewModel.errorMessage ?? "Erreur lors de la suppression. Reessaie ou contacte le support."
        }
    }
}
