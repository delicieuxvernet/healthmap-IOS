import SwiftUI

// MARK: - Dashboard View (onglet Bilan — refonte « v4 3D », direction validée juin 2026)
//
// Langage v4 : fond crème, anneau plein du score, apports en champs de points
// cliquables (pop-up bottom-sheet), symptôme en CTA compact, récolte 3D
// (gamification adossée à la série), derniers repas du journal.
// Source maquette : « Bilan v4 - 3D ». Structure de référence : DESIGN-PAGES.md.
//
// Inchangé côté sécurité : les red flags URGENTS passent TOUJOURS au-dessus du
// héros (une alerte ne doit pas attendre l'IA) ; le flux de chargement / d'échec
// (FullAnalysisLoadingView / AnalysisErrorRetryView) reste identique.
struct DashboardView: View {
    @EnvironmentObject var viewModel: DashboardViewModel
    @ObservedObject var gamification = GamificationService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    /// Journal du jour (table `meal_scans`) — chargé localement pour le bloc
    /// « Tes derniers repas ». Lecture seule, aucun calcul touché.
    @StateObject private var journal = MealJournalViewModel()

    @State private var selectedNutrient: EnrichedNutrient?
    @State private var selectedSymptom: SymptomeAnalyse?
    @State private var showAvatarPicker = false
    @State private var didOfferAvatarPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()

                if viewModel.aiAnalysis != nil {
                    mainContent
                } else if viewModel.profile.completed {
                    VStack(spacing: 0) {
                        if !immediateRedFlags.isEmpty {
                            RedFlagsCardView(flags: immediateRedFlags)
                                .padding(.horizontal, Theme.spacingLG)
                                .padding(.top, Theme.spacingMD)
                        }
                        if !viewModel.isLoadingAnalysis, let errorMessage = viewModel.errorMessage {
                            AnalysisErrorRetryView(
                                message: errorMessage,
                                isRetrying: false,
                                onRetry: { Task { await viewModel.triggerAnalysis() } }
                            )
                        } else {
                            FullAnalysisLoadingView()
                        }
                    }
                } else {
                    DashboardSkeletonView()
                }
            }
            .navigationTitle("Mon bilan")
            .navigationBarTitleDisplayMode(.large)
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
            // Pop-up détail d'un apport (langage v4). .sheet(item:) garantit que
            // la feuille reçoit toujours le nutriment courant.
            .sheet(item: $selectedNutrient) { nutrient in
                ApportDetailSheet(nutrient: nutrient) {
                    selectedNutrient = nil
                    NotificationCenter.default.post(
                        name: .healthmapNavigateToTab,
                        object: NavCardDestination.plan.rawValue
                    )
                }
            }
            // Causes d'un symptôme — uniquement au tap "Voir pourquoi".
            .sheet(item: $selectedSymptom) { symptom in
                SymptomCausesSheet(item: symptom)
                    .healthMapSheet(.large)
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

    // MARK: - Red flags (sécurité — inchangé)
    private var immediateRedFlags: [RedFlag] {
        viewModel.redFlags.filter { $0.urgency == .immediate }
    }

    private var otherRedFlags: [RedFlag] {
        viewModel.redFlags.filter { $0.urgency != .immediate }
    }

    // MARK: - Symptômes détectés (source : symptomes_analyse du bilan IA)
    private var symptomes: [SymptomeAnalyse] {
        (viewModel.aiAnalysis?.symptomesAnalyse ?? [])
            .filter { ($0.symptome?.isEmpty == false) && !($0.causesProbables ?? []).isEmpty }
    }

    // MARK: - Main Content (langage v4)
    // Ordre maquette : score → apports → symptôme → récolte → derniers repas.
    // (Red flags urgents au-dessus pour la sécurité ; disclaimer + red flags non
    // urgents en bas.)
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !immediateRedFlags.isEmpty {
                    RedFlagsCardView(flags: immediateRedFlags)
                        .padding(.horizontal, Theme.spacingLG)
                }

                // 1. Héros : score global (anneau plein)
                BilanScoreCard(
                    score: viewModel.healthScore,
                    summary: viewModel.aiAnalysis?.summary?.headline
                )
                .padding(.horizontal, Theme.spacingLG)
                .staggeredAppear(index: 0)

                // 2. Apports à renforcer (champs de points cliquables)
                if !topDeficiencies.isEmpty {
                    ApportsCard(deficiencies: topDeficiencies) { nutrient in
                        HapticService.shared.tap()
                        selectedNutrient = nutrient
                    }
                    .padding(.horizontal, Theme.spacingLG)
                    .staggeredAppear(index: 1)
                }

                // 3. Symptôme détecté (CTA compact → causes en feuille)
                if let symptom = symptomes.first {
                    SymptomeCardV4(label: prettifySymptom(symptom.symptome ?? "")) {
                        HapticService.shared.tap()
                        selectedSymptom = symptom
                    }
                    .padding(.horizontal, Theme.spacingLG)
                    .staggeredAppear(index: 2)
                }

                // 4. Ta récolte (gamification — masquée en mode zen)
                if !gamification.isZenMode {
                    RecolteCard(streak: gamification.currentStreak)
                        .padding(.horizontal, Theme.spacingLG)
                        .padding(.top, 8)
                        .staggeredAppear(index: 3)
                }

                // 5. Tes derniers repas (journal du jour)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tes derniers repas")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DerniersRepasCard(meals: journal.meals) {
                        HapticService.shared.tap()
                        NotificationCenter.default.post(
                            name: .healthmapNavigateToTab,
                            object: NavCardDestination.scanner.rawValue
                        )
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.top, 8)
                .staggeredAppear(index: 4)

                // Indicateur de rafraîchissement (analyse déjà présente)
                if viewModel.isLoadingAnalysis && viewModel.aiAnalysis != nil {
                    HStack(spacing: Theme.spacingSM) {
                        ProgressView().tint(Color.kiwiGreen)
                        Text("Mise à jour de l'analyse…")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                    .padding()
                }

                // 6. Disclaimer + red flags non urgents
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

    // MARK: - Top deficiencies (3 apports les plus bas)
    private var topDeficiencies: [EnrichedNutrient] {
        Array(viewModel.deficiencies.prefix(3))
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

// MARK: - Libellé lisible pour les clés de symptôme (fatigue_persistante → Fatigue persistante)
private func prettifySymptom(_ raw: String) -> String {
    let cleaned = raw.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    guard let first = cleaned.first else { return cleaned }
    return first.uppercased() + cleaned.dropFirst()
}

// MARK: - Symptom causes sheet (ouverte au tap "Voir pourquoi")
private struct SymptomCausesSheet: View {
    let item: SymptomeAnalyse
    @Environment(\.dismiss) private var dismiss

    private var causes: [String] { item.causesProbables ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingMD) {
                    HStack(spacing: Theme.spacingSM) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.healthMapBlue)
                            .frame(width: 36, height: 36)
                            .background(Color.healthMapBlueLight)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prettifySymptom(item.symptome ?? ""))
                                .font(Theme.headlineFont)
                                .foregroundStyle(Color.healthMapText)
                            Text("\(causes.count) cause\(causes.count > 1 ? "s" : "") possible\(causes.count > 1 ? "s" : "")")
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.healthMapSecondary)
                        }
                        Spacer()
                    }

                    ForEach(Array(causes.enumerated()), id: \.offset) { _, cause in
                        Text(cause)
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.spacingMD)
                            .background(Color.healthMapCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
                    }

                    if let aVerifier = item.aVerifier, !aVerifier.isEmpty {
                        HStack(alignment: .top, spacing: Theme.spacingSM) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.healthMapBlue)
                                .padding(.top, 1)
                                .accessibilityHidden(true)
                            Text("À vérifier\u{202F}: \(aVerifier)")
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.healthMapBlue)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Theme.spacingMD)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.healthMapBlueLight)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
                    }

                    Text("Informatif\u{202F}: ne remplace pas un avis médical.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.healthMapMuted)
                        .padding(.top, Theme.spacingXS)
                }
                .padding(Theme.spacingLG)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.healthMapBackground)
            .navigationTitle("Causes possibles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.healthMapMuted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Fermer")
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(DashboardViewModel())
}
