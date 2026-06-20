import SwiftUI
import UIKit

// MARK: - Dashboard View (main screen after analysis)
// Structure : DESIGN-PAGES.md §1 (blocs 0 → 9). Chaque section déclare son
// champ source, ses lignes max et sa couleur = f(score) (loi 13).
struct DashboardView: View {
    @EnvironmentObject var viewModel: DashboardViewModel
    @ObservedObject var gamification = GamificationService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var selectedNutrient: EnrichedNutrient?
    @State private var showNutrientDetail = false
    @State private var showAllNutrients = false
    @State private var showScoreInfo = false
    @State private var showAvatarPicker = false
    @State private var didOfferAvatarPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Fond chaud unifié, statique (WarmBackground) — remplace le
                // ruban animé retiré (perf).
                WarmBackground()

                // NOUVEAU FLUX (20 juin, validé Arthur) : on n'affiche AUCUN
                // résultat tant que le bilan IA n'est pas prêt — pas de scores
                // bruts « cash ». Pendant l'analyse -> écran de chargement plein ;
                // si l'IA échoue -> écran « Réessayer ». Seules les alertes de
                // sécurité URGENTES (red flags immédiats, calcul local) passent
                // au-dessus : une urgence ne doit pas attendre ni disparaître si
                // l'IA échoue.
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
            .navigationTitle("Mon Bilan")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.regenerateAnalysis() }
                    } label: {
                        Group {
                            if #available(iOS 18.0, *) {
                                Image(systemName: "arrow.clockwise")
                                    .symbolEffect(.rotate.byLayer, options: .repeat(.continuous), isActive: viewModel.isLoadingAnalysis)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .symbolEffect(.pulse, options: .repeating, isActive: viewModel.isLoadingAnalysis)
                            }
                        }
                        .font(.system(size: 16))
                        .foregroundStyle(Color.healthMapBlue)
                    }
                    .disabled(viewModel.isLoadingAnalysis)
                }
                // Avatar Profil en haut à droite (P6 : l'onglet Profil a été
                // remplacé par Mes compléments). Ouvre le Profil en sheet via
                // NotificationCenter (consommé par MainTabView).
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        NotificationCenter.default.post(name: .healthmapOpenProfile, object: nil)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.healthMapBlue)
                    }
                    .accessibilityLabel("Profil")
                }
            }
            .sheet(isPresented: $showNutrientDetail) {
                if let nutrient = selectedNutrient {
                    NutrientDetailSheet(nutrient: nutrient, isPremium: subscriptionService.isPremium)
                        .healthMapSheet(.large)
                }
            }
            .sheet(isPresented: $showAllNutrients) {
                AllNutrientsSheet(
                    nutrients: viewModel.nutrients,
                    isPremium: subscriptionService.isPremium
                )
                .healthMapSheet(.large)
            }
            .sheet(isPresented: $showScoreInfo) {
                scoreInfoSheet
                    .healthMapActionSheet()
            }
            .refreshable {
                await viewModel.triggerAnalysis()
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

    // MARK: - Red flags filtrés (DESIGN-PAGES §1 blocs 0 et 9)
    // Source : viewModel.redFlags (merge IA ou détection locale).
    // Seuls les `urgency == .immediate` passent AVANT le héro (sécurité) ;
    // les autres descendent en bas de page, après le disclaimer.
    private var immediateRedFlags: [RedFlag] {
        viewModel.redFlags.filter { $0.urgency == .immediate }
    }

    private var otherRedFlags: [RedFlag] {
        viewModel.redFlags.filter { $0.urgency != .immediate }
    }

    // MARK: - Symptômes détectés (source : symptomes_analyse du bilan IA)
    // Refonte 20 juin : les symptômes déclarés + leurs causes croisées
    // (déjà générées par generate-analysis) s'affichent sur la home.
    private var symptomes: [SymptomeAnalyse] {
        viewModel.aiAnalysis?.symptomesAnalyse ?? []
    }

    // MARK: - Main Content (refonte home 20 juin, validée Arthur)
    // Ordre : score -> carences EN LIGNE horizontale -> symptômes cliquables
    // (causes) -> gros CTA Mon Plan -> conseil du jour -> mon évolution.
    // Retiré de la home : tuiles points forts/interaction, hack premium,
    // bouton "tous mes nutriments" (remplacé par "Voir tout" sur les carences).
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: Theme.spacingLG) {
                // 0. Red flags URGENTS (sécurité avant tout)
                if !immediateRedFlags.isEmpty {
                    RedFlagsCardView(flags: immediateRedFlags)
                        .padding(.horizontal, Theme.spacingLG)
                }

                // 1. Héro : score global
                heroSection
                    .staggeredAppear(index: 0)

                // 2. Carences en LIGNE horizontale (gain de place vertical)
                if !viewModel.deficiencies.isEmpty {
                    carencesSection
                        .staggeredAppear(index: 1)
                }

                // 3. Symptômes détectés — accordéon vers les causes
                if !symptomes.isEmpty {
                    symptomesSection
                        .staggeredAppear(index: 2)
                }

                // 4. Gros CTA -> Mon Plan
                planReadyCard
                    .staggeredAppear(index: 3)

                // 5. Conseil du jour (compact)
                if let pepite = viewModel.pepiteDuJour {
                    conseilDuJourCard(pepite)
                        .staggeredAppear(index: 4)
                }

                // 6. Mon évolution — avatar (conservé, sous le plan)
                if viewModel.profile.completed {
                    MonEvolutionSection(profile: viewModel.profile) {
                        showAvatarPicker = true
                    }
                    .staggeredAppear(index: 5)
                }

                // 7. Export + partage (premium uniquement)
                if subscriptionService.isPremium {
                    premiumActionsSection
                        .staggeredAppear(index: 6)
                }

                // Indicateur de rafraîchissement (refresh d'une analyse déjà là)
                if viewModel.isLoadingAnalysis && viewModel.aiAnalysis != nil {
                    HStack(spacing: Theme.spacingSM) {
                        ProgressView()
                            .tint(Color.healthMapBlue)
                        Text("Mise a jour de l'analyse...")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                    .padding()
                }

                // 8. Disclaimer + red flags non urgents
                disclaimerCard

                if !otherRedFlags.isEmpty {
                    RedFlagsCardView(flags: otherRedFlags)
                        .padding(.horizontal, Theme.spacingLG)
                }
            }
            .padding(.vertical, Theme.spacingMD)
        }
    }

    // MARK: - Héro intégré (bloc 1)
    // Sources : healthScore local (anneau, arc = score/100 — loi 5),
    // HealthScale.globalLabel (pill, vocabulaire contrôlé — lois 4 & 8),
    // summary.headline (2 lignes max) + summary.metaphore (2 lignes max, loi 9).
    // Le reveal anime déjà le trim (~1,2 s ease-out) et le count-up dans
    // ScoreRingView/AnimatedNumberView — gelés si reduce-motion.
    private var heroSection: some View {
        VStack(spacing: Theme.spacingMD) {
            ScoreRingView(score: viewModel.healthScore, size: 140, lineWidth: 12)

            // Pill état global + streak discret
            HStack(spacing: Theme.spacingSM) {
                Text(scoreLabel)
                    .pillStyle(color: Color.globalScoreColor(for: viewModel.healthScore))

                if gamification.currentStreak > 0 && !gamification.isZenMode {
                    HStack(spacing: Theme.spacingXS) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                        Text("\(gamification.currentStreak)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color.accentSky)
                    .padding(.horizontal, Theme.spacingSM)
                    .padding(.vertical, Theme.spacingXS)
                    .background(Color.accentSky.opacity(Theme.opacityMedium))
                    .clipShape(Capsule())
                    .accessibilityLabel("Série de \(gamification.currentStreak) \(gamification.currentStreak > 1 ? "jours" : "jour")")
                }
            }

            // Headline IA — texte libre : 2 lignes max (loi 9)
            if let headline = viewModel.aiAnalysis?.summary?.headline, !headline.isEmpty {
                Text(headline)
                    .font(Theme.headlineFont)
                    .foregroundStyle(Color.healthMapText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // (Épure du 12 juin : la métaphore IA a quitté le héro — elle vit
            // désormais en citation d'ouverture de la sheet ci-dessous.)

            // Ligne discrète « Comment ce score est calculé » → petite sheet
            Button {
                HapticService.shared.selection()
                showScoreInfo = true
            } label: {
                HStack(spacing: Theme.spacingXS) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .accessibilityHidden(true)
                    Text("Comment ce score est calculé")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.healthMapSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityHint("Ouvre une courte explication du calcul du score.")
        }
        .padding(Theme.spacingLG)
        .frame(maxWidth: .infinity)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Sheet « Comment ce score est calculé »
    private var scoreInfoSheet: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "function")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.healthMapBlue)
                    .accessibilityHidden(true)

                Text("Comment ce score est calculé")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Color.healthMapText)
            }

            // Métaphore IA en citation d'ouverture (déplacée du héro — épure
            // du 12 juin). Texte libre : 3 lignes max (loi 9).
            if let metaphore = viewModel.aiAnalysis?.summary?.metaphore, !metaphore.isEmpty {
                Text("«\u{202F}\(metaphore)\u{202F}»")
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(Color.healthMapSecondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Tes scores sont calculés localement, à partir de tes réponses au questionnaire\u{202F}: alimentation, mode de vie, besoins spécifiques. Chaque nutriment reçoit un score de 0 à 100, et le score global les combine. L\u{2019}analyse IA ajoute des explications personnalisées, mais ne modifie jamais tes scores. HealthMap ne remplace pas un avis médical.")
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(Theme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Carences en ligne horizontale (refonte 20 juin, validée Arthur)
    // Source : viewModel.deficiencies (score < 70). Cartes compactes en
    // ScrollView horizontal -> gain de place vertical. « Voir tout » ouvre la
    // grille complète ; tap sur une carte -> fiche nutriment.
    private var carencesSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack {
                Text("Tes carences potentielles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                Spacer()
                Button {
                    HapticService.shared.tap()
                    showAllNutrients = true
                } label: {
                    Text("Voir tout")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapBlue)
                }
            }
            .padding(.horizontal, Theme.spacingLG)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacingSM) {
                    ForEach(viewModel.deficiencies) { nutrient in
                        CarenceChip(nutrient: nutrient) {
                            HapticService.shared.tap()
                            selectedNutrient = nutrient
                            showNutrientDetail = true
                        }
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
            }
        }
    }

    // MARK: - Symptômes détectés (refonte 20 juin) — accordéon vers les causes
    // Source : symptomes (aiAnalysis.symptomesAnalyse). Tap sur un symptôme ->
    // ses causes probables se déplient en place.
    private var symptomesSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack {
                Text("Symptômes détectés")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                Spacer()
                Text("touche pour les causes")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.healthMapSecondary)
            }

            ForEach(symptomes) { item in
                SymptomCard(item: item)
            }
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Conseil du jour (compact) — remplace l'ancienne pépite pleine
    private func conseilDuJourCard(_ pepite: PracticalTip) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.accentIndigo)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Conseil du jour")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapText)
                Text(pepite.tip ?? pepite.hook ?? "")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.accentIndigo.opacity(Theme.opacityLight))
        )
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Fin positive (bloc 8)
    // « Ton plan est prêt → » ouvre l'onglet Plan via le mécanisme de
    // navigation existant (NotificationCenter → MainTabView.selectedTab).
    private var planReadyCard: some View {
        Button {
            HapticService.shared.tap()
            NotificationCenter.default.post(
                name: .healthmapNavigateToTab,
                object: NavCardDestination.plan.rawValue
            )
        } label: {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.18)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ton plan est prêt")
                        .font(Theme.headlineFont)
                        .foregroundStyle(.white)
                    Text("Tes actions t'attendent")
                        .font(Theme.captionFont)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            .padding(Theme.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            // CTA plein dégradé bleu → indigo : attire l'œil, appelle au clic.
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.healthMapBlue, Color.accentIndigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
            )
            .shadow(color: Color.healthMapBlue.opacity(0.3), radius: 14, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.healthMapPressed)
        .padding(.horizontal, Theme.spacingLG)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ton plan est prêt. Tes actions t'attendent.")
        .accessibilityHint("Ouvre l\u{2019}onglet Mon Plan.")
    }

    // MARK: - Score Label
    // Mot d'état du score global : échelle unique HealthScale (loi 4).
    var scoreLabel: String {
        HealthScale.globalLabel(for: viewModel.healthScore)
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

// MARK: - Écran de chargement plein (nouveau flux du 20 juin)
// Tant que le bilan IA n'est pas prêt, on n'affiche AUCUN résultat : juste la
// mascotte kiwi qui marche + un message qui tourne, pour rendre l'attente
// (~1 à 2 min) vivante. Reduce-motion : pas de rotation, 1er message figé.
private struct FullAnalysisLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var messageIndex = 0

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

            ProgressView()
                .progressViewStyle(.linear)
                .tint(Color.healthMapBlue)
                .frame(maxWidth: 200)

            Text("Ça prend environ une minute. On te prépare un bilan complet.")
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapMuted)
                .multilineTextAlignment(.center)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Theme.spacingLG)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Analyse de ton profil en cours. Cela prend environ une minute.")
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.4)) {
                    messageIndex = (messageIndex + 1) % messages.count
                }
            }
        }
    }
}

// MARK: - Libellé lisible pour les clés de symptôme (fatigue_persistante -> Fatigue persistante)
private func prettifySymptom(_ raw: String) -> String {
    let cleaned = raw.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    guard let first = cleaned.first else { return cleaned }
    return first.uppercased() + cleaned.dropFirst()
}

// MARK: - Carence chip (carte compacte, ligne horizontale)
private struct CarenceChip: View {
    let nutrient: EnrichedNutrient
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Text(nutrient.emoji).font(.system(size: 14))
                    Text(nutrient.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)
                        .lineLimit(1)
                }
                Text("\(nutrient.score)%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.scoreColor(for: nutrient.score))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.healthMapMuted.opacity(0.15))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.scoreColor(for: nutrient.score))
                        .frame(width: max(6, CGFloat(nutrient.score) / 100 * 88), height: 4)
                }
                Text(HealthScale.nutrientLabel(for: nutrient.score))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.scoreColor(for: nutrient.score))
            }
            .padding(11)
            .frame(width: 112, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(nutrient.label), \(nutrient.score) pour cent, \(HealthScale.nutrientLabel(for: nutrient.score))")
    }
}

// MARK: - Symptom card (accordéon : tap -> causes probables)
// Source : SymptomeAnalyse (symptome + causes_probables + a_verifier).
private struct SymptomCard: View {
    let item: SymptomeAnalyse
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var causes: [String] { item.causesProbables ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticService.shared.tap()
                withAnimation(reduceMotion ? .none : .healthMapSpring) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentSky)
                        .frame(width: 30, height: 30)
                        .background(Color.accentSky.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)

                    Text(prettifySymptom(item.symptome ?? ""))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)
                        .lineLimit(1)

                    Spacer()

                    if !causes.isEmpty {
                        Text("\(causes.count) cause\(causes.count > 1 ? "s" : "")")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.healthMapMuted)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityValue(isExpanded ? "déplié" : "replié")

            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.spacingXS) {
                    ForEach(Array(causes.prefix(4).enumerated()), id: \.offset) { _, cause in
                        HStack(alignment: .top, spacing: Theme.spacingXS) {
                            Circle()
                                .fill(Color.accentSky)
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                                .accessibilityHidden(true)
                            Text(cause)
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.healthMapSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let aVerifier = item.aVerifier, !aVerifier.isEmpty {
                        HStack(alignment: .top, spacing: Theme.spacingXS) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.healthMapBlue)
                                .padding(.top, 1)
                                .accessibilityHidden(true)
                            Text("À vérifier\u{202F}: \(aVerifier)")
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.healthMapBlue)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.top, Theme.spacingSM)
                .padding(.leading, 38)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.spacingMD)
        .cardStyle()
    }
}

#Preview {
    DashboardView()
        .environmentObject(DashboardViewModel())
}
