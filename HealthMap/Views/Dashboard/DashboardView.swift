import SwiftUI

// MARK: - Dashboard View (onglet Bilan — refonte « v6 vivant », juillet 2026)
//
// Langage v6 : greeting « Bonjour {prénom} » + petit anneau de score (58 pt),
// carte « Ta journée » (repas du jour, meal_scans), carte « Apports à
// renforcer » (insight + 3 jauges du CONTRAT v2, pop-up bottom-sheet), tuiles
// Symptôme / Ta récolte côte à côte, « Interactions détectées », derniers
// repas du journal. Source maquette : « Bilan v6 - vivant ».
//
// Source de données : `DashboardViewModel.analysisV2` (contrat API v2,
// tache "bilan"). Tant que le bilan v2 n'est pas là, le flux de chargement
// existant reste inchangé (FullAnalysisLoadingView « 2-3 min » /
// AnalysisErrorRetryView).
//
// Inchangé côté sécurité : les red flags URGENTS passent TOUJOURS au-dessus
// du contenu (une alerte ne doit pas attendre l'IA).
struct DashboardView: View {
    @EnvironmentObject var viewModel: DashboardViewModel
    @ObservedObject var gamification = GamificationService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    /// Journal du jour (table `meal_scans`) — nourrit « Ta journée » et
    /// « Tes derniers repas ». Lecture seule, aucun calcul touché.
    @StateObject private var journal = MealJournalViewModel()

    @State private var selectedApport: ApportV2?
    @State private var selectedSymptome: SymptomeV2?
    @State private var showAvatarPicker = false
    @State private var didOfferAvatarPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                content
            }
            // v6 : le greeting fait office de titre — la barre reste inline et
            // vide, seul l'avatar Profil y demeure.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Avatar Profil en haut à droite (ouvre le Profil en sheet via
                // NotificationCenter, consommé par MainTabView). Accent vert kiwi.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        NotificationCenter.default.post(name: .healthmapOpenProfile, object: nil)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.kiwiGreen)
                    }
                    .accessibilityLabel("Profil")
                }
            }
            // Pop-up détail d'un apport (contrat v2). .sheet(item:) garantit que
            // la feuille reçoit toujours l'apport courant.
            .sheet(item: $selectedApport) { apport in
                ApportV2DetailSheet(apport: apport) {
                    selectedApport = nil
                    openTab(.plan)
                }
            }
            // « Voir pourquoi » d'un symptôme — causes mappées sur les apports v2.
            .sheet(item: $selectedSymptome) { symptome in
                SymptomeV6Sheet(
                    symptome: symptome,
                    apports: viewModel.analysisV2?.bilan?.apports ?? []
                ) {
                    selectedSymptome = nil
                    openTab(.plan)
                }
            }
            .sheet(isPresented: $showAvatarPicker) {
                AvatarPickerView(profile: viewModel.profile) { key in
                    viewModel.saveAvatarKey(key)
                }
                .healthMapSheet(.large)
            }
            .onChange(of: viewModel.isLoadingProfile, initial: true) { _, _ in
                maybeOfferAvatarPicker()
            }
            .onChange(of: viewModel.profile.avatarKey) { _, _ in
                maybeOfferAvatarPicker()
            }
        }
    }

    // MARK: - Contenu (v6 si bilan v2 dispo, sinon flux chargement existant)
    @ViewBuilder
    private var content: some View {
        if let v2 = viewModel.analysisV2, v2.isValidV2 {
            mainContent(v2)
        } else if viewModel.profile.completed {
            VStack(spacing: 0) {
                if !immediateRedFlags.isEmpty {
                    RedFlagsCardView(flags: immediateRedFlags)
                        .padding(.horizontal, Theme.spacingLG)
                        .padding(.top, Theme.spacingMD)
                }
                if viewModel.isLoadingAnalysisV2 {
                    FullAnalysisLoadingView()
                } else if let errorMessageV2 = viewModel.errorMessageV2 {
                    // Le bilan RÉELLEMENT affiché (v2) a échoué sans repli en
                    // cache. Gardé sur errorMessageV2 (pas aiAnalysis/errorMessage,
                    // v7) depuis l'incident du 4 juillet : un échec v7 seul ne
                    // doit jamais bloquer l'affichage du vrai bilan v2.
                    AnalysisErrorRetryView(
                        message: errorMessageV2,
                        isRetrying: false,
                        onRetry: { Task { await viewModel.triggerAnalysis() } }
                    )
                } else {
                    // Analyse pas encore déclenchée (transition post-questionnaire).
                    FullAnalysisLoadingView()
                }
            }
        } else {
            DashboardSkeletonView()
        }
    }

    // MARK: - Red flags (sécurité — inchangé)
    private var immediateRedFlags: [RedFlag] {
        viewModel.redFlags.filter { $0.urgency == .immediate }
    }

    private var otherRedFlags: [RedFlag] {
        viewModel.redFlags.filter { $0.urgency != .immediate }
    }

    // MARK: - Main Content (langage v6)
    // Ordre maquette : greeting+score → ta journée → apports → tuiles
    // symptôme/récolte → interactions → derniers repas. (Red flags urgents
    // au-dessus pour la sécurité ; disclaimer + red flags non urgents en bas.)
    private func mainContent(_ v2: AIAnalysisV2) -> some View {
        ScrollView {
            VStack(spacing: 13) {
                if !immediateRedFlags.isEmpty {
                    RedFlagsCardView(flags: immediateRedFlags)
                        .padding(.horizontal, Theme.spacingLG)
                }

                // 1. Greeting + date + besoins nourris + petit anneau de score
                BilanGreetingHeader(
                    firstName: viewModel.firstName,
                    besoinsNourris: v2.besoinsNourris,
                    score: v2.score ?? viewModel.healthScore
                )
                .padding(.horizontal, Theme.spacingLG)
                .staggeredAppear(index: 0)

                // 2. Ta journée (repas scannés du jour — tap → onglet Scanner)
                TaJourneeV6Card(meals: journal.meals) {
                    HapticService.shared.tap()
                    openTab(.scanner)
                }
                .padding(.horizontal, Theme.spacingLG)
                .staggeredAppear(index: 1)

                // 3. Apports à renforcer (insight + jauges cliquables)
                if let apports = v2.bilan?.apports, !apports.isEmpty {
                    ApportsV6Card(
                        insight: v2.bilan?.apportsInsight,
                        apports: Array(apports.prefix(3))
                    ) { apport in
                        HapticService.shared.tap()
                        selectedApport = apport
                    }
                    .padding(.horizontal, Theme.spacingLG)
                    .staggeredAppear(index: 2)
                }

                // 4. Tuiles Symptôme + Ta récolte (récolte masquée en mode zen)
                tilesRow(v2)
                    .padding(.horizontal, Theme.spacingLG)
                    .staggeredAppear(index: 3)

                // 5. Interactions détectées (≤2, contrat v2)
                if let interactions = v2.bilan?.interactions,
                   interactions.contains(where: { ($0.tipBold?.isEmpty == false) || ($0.tipRest?.isEmpty == false) }) {
                    InteractionsV6Card(interactions: Array(interactions.prefix(2)))
                        .padding(.horizontal, Theme.spacingLG)
                        .staggeredAppear(index: 4)
                }

                // 6. Tes derniers repas (journal réel — masquée si vide)
                if !journal.meals.isEmpty {
                    DerniersRepasV6Card(meals: journal.meals) {
                        HapticService.shared.tap()
                        openTab(.scanner)
                    }
                    .padding(.horizontal, Theme.spacingLG)
                    .staggeredAppear(index: 5)
                }

                // Indicateur de rafraîchissement (bilan déjà présent)
                if viewModel.isLoadingAnalysis || viewModel.isLoadingAnalysisV2 {
                    HStack(spacing: Theme.spacingSM) {
                        ProgressView().tint(Color.kiwiGreen)
                        Text("Mise à jour de l'analyse…")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                    .padding()
                }

                // 7. Disclaimer + red flags non urgents
                disclaimerCard

                if !otherRedFlags.isEmpty {
                    RedFlagsCardView(flags: otherRedFlags)
                        .padding(.horizontal, Theme.spacingLG)
                }
            }
            .padding(.vertical, Theme.spacingMD)
        }
        .task { await journal.load() }
        .refreshable {
            await viewModel.triggerAnalysis()
            await journal.load()
        }
    }

    // MARK: - Rangée de tuiles (symptôme du contrat + récolte)
    @ViewBuilder
    private func tilesRow(_ v2: AIAnalysisV2) -> some View {
        let symptome = v2.bilan?.symptomes?.first(where: { $0.nom?.isEmpty == false })
        if symptome != nil || !gamification.isZenMode {
            HStack(alignment: .top, spacing: 12) {
                if let symptome {
                    SymptomeV6Tile(nom: symptome.nom ?? "") {
                        HapticService.shared.tap()
                        selectedSymptome = symptome
                    }
                }
                if !gamification.isZenMode {
                    RecolteV6Tile(streak: gamification.currentStreak)
                }
            }
        }
    }

    // MARK: - Navigation onglets (mécanisme existant)
    private func openTab(_ destination: NavCardDestination) {
        NotificationCenter.default.post(
            name: .healthmapNavigateToTab,
            object: destination.rawValue
        )
    }

    /// Présente le sélecteur d'avatar une seule fois quand le profil est
    /// chargé et complété mais qu'aucun avatar n'a encore été choisi.
    private func maybeOfferAvatarPicker() {
        guard !didOfferAvatarPicker,
              !viewModel.isLoadingProfile,
              viewModel.profile.completed,
              !viewModel.profile.weight.isEmpty,
              viewModel.profile.avatarKey.isEmpty else { return }
        didOfferAvatarPicker = true
        showAvatarPicker = true
    }
}

// MARK: - Staggered Appear (loi 17)
/// Apparition des sections en léger stagger : fondu + petite montée, une
/// seule courbe (`.healthMapSpring`), délai croissant par index. Reduce
/// Motion → affichage immédiat sans animation.
private struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.healthMapSpring.delay(Double(index) * 0.06)) {
                        appeared = true
                    }
                }
            }
    }
}

private extension View {
    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

// MARK: - Écran de chargement plein (flux du 20 juin — inchangé)
// Tant que le bilan IA n'est pas prêt, on n'affiche AUCUN résultat : juste la
// mascotte kiwi qui marche + un message qui tourne. Référencé par
// ContentView (AnalysisGateView) : NE PAS retirer.
struct FullAnalysisLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var messageIndex = 0
    @State private var progress: Double = 0

    private let messages = [
        "On croise tes symptômes, ton alimentation et ton mode de vie.",
        "On cherche ce qui peut expliquer tes symptômes.",
        "On repère tes points forts et tes vraies priorités.",
        "On prépare des conseils personnalisés, rien que pour toi.",
    ]

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            KiwiWalkerView(size: 140)

            VStack(spacing: Theme.spacingSM) {
                Text("On analyse ton profil…")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Color.healthMapText)

                Text(messages[messageIndex])
                    .font(Theme.bodyFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 48)
                    .id(messageIndex)
                    .transition(.opacity)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Color.kiwiGreen)
                .frame(maxWidth: 200)
                .animation(.easeInOut(duration: 0.4), value: progress)

            VStack(spacing: Theme.spacingSM) {
                Text("Compte 2 à 3 minutes")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.kiwiGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.kiwiGreen.opacity(0.12), in: Capsule())

                Text("Tu peux laisser l'app ouverte, on s'occupe de tout.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapMuted)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Theme.spacingLG)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Analyse de ton profil en cours. Compte deux à trois minutes.")
        .task {
            // Progression calibrée sur la durée réelle (~2-3 min) : montée douce qui
            // plafonne vers 90 % et n'atteint JAMAIS 100 % — la barre disparaît quand
            // le vrai bilan arrive (la vue est remplacée par le contenu). Fini le
            // « 95 % figé en 25 s » suivi d'une fausse erreur réseau.
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                if Task.isCancelled { break }
                ticks += 1
                progress = min(0.9, progress + (0.9 - progress) * 0.012)
                if !reduceMotion && ticks % 8 == 0 {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        messageIndex = (messageIndex + 1) % messages.count
                    }
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(DashboardViewModel())
}
