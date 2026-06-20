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
    @State private var selectedSymptom: SymptomeAnalyse?
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
                // Bouton « régénérer » RETIRÉ (20 juin) : il vidait le cache et
                // refaisait un appel IA PAYANT à chaque tap. Le bilan est généré
                // UNE SEULE fois puis caché ; il ne se régénère QUE si le profil
                // change (édition). Plus aucun re-call manuel possible.

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
            // .sheet(item:) garantit que NutrientDetailSheet reçoit TOUJOURS le
            // nutriment courant — l'ancien pattern (isPresented + état séparé)
            // présentait parfois un sheet VIDE au 1er tap (data pas encore
            // propagée). Fix retour test du 20 juin.
            .sheet(item: $selectedNutrient) { nutrient in
                NutrientDetailSheet(nutrient: nutrient, isPremium: subscriptionService.isPremium)
                    .healthMapSheet(.large)
            }
            // Causes d'un symptôme : affichées UNIQUEMENT au tap "Comprendre les
            // causes" (jamais à l'écran par défaut) — feuille validée par Arthur.
            .sheet(item: $selectedSymptom) { symptom in
                SymptomCausesSheet(item: symptom)
                    .healthMapSheet(.large)
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
        // Même filtre que RecommendationsViewModel : on écarte les entrées
        // dégénérées (sans libellé ou sans cause) pour ne jamais afficher de
        // carte inerte qui ne déplie rien (revue 20 juin).
        (viewModel.aiAnalysis?.symptomesAnalyse ?? [])
            .filter { ($0.symptome?.isEmpty == false) && !($0.causesProbables ?? []).isEmpty }
    }

    // MARK: - Main Content (refonte home 20 juin, validée Arthur)
    // Ordre : score -> apports a renforcer EN LIGNE -> symptômes cliquables
    // (causes) -> gros CTA Mon Plan -> conseil du jour -> mon évolution.
    // Retiré de la home : tuiles points forts/interaction, hack premium,
    // bouton "tous mes nutriments" (remplacé par "Voir tout" sur la section).
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

                // 2. Apports a renforcer EN LIGNE horizontale (gain de place vertical)
                if !viewModel.deficiencies.isEmpty {
                    gapsSection
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

    // MARK: - Apports a renforcer en ligne horizontale (refonte 20 juin, validée Arthur)
    // Source : viewModel.deficiencies (score < 70). Cartes compactes en
    // ScrollView horizontal -> gain de place vertical. « Voir tout » ouvre la
    // grille complète ; tap sur une carte -> fiche nutriment.
    private var gapsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack {
                Text("Tes apports à renforcer")
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
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
            }
            .padding(.horizontal, Theme.spacingLG)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacingSM) {
                    ForEach(viewModel.deficiencies) { nutrient in
                        NutrientGapChip(nutrient: nutrient) {
                            HapticService.shared.tap()
                            selectedNutrient = nutrient
                        }
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
            }
        }
    }

    // MARK: - Symptômes détectés (refonte 20 juin v2) — compact horizontal + causes en feuille
    // Source : symptomes (aiAnalysis.symptomesAnalyse). Cartes compactes en
    // ScrollView horizontal (comme les apports) ; "Comprendre les causes" ouvre
    // une FEUILLE (selectedSymptom). Suivi de 2 CTA : Suivi + Scanner.
    private var symptomesSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Symptômes détectés")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.healthMapText)
                .padding(.horizontal, Theme.spacingLG)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacingSM) {
                    ForEach(symptomes) { item in
                        SymptomCompactCard(item: item) {
                            HapticService.shared.tap()
                            selectedSymptom = item
                        }
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
            }

            // 2 CTA sous les symptômes (validés Arthur)
            HStack(spacing: Theme.spacingSM) {
                navCTA(title: "Commencer mon suivi", icon: "checkmark.circle.fill",
                       colors: [Color.scoreExcellent, Color.healthMapBlue], destination: .suivi)
                navCTA(title: "Scanner mes plats", icon: "camera.fill",
                       colors: [Color.healthMapBlue, Color.accentIndigo], destination: .scanner)
            }
            .padding(.horizontal, Theme.spacingLG)
            .padding(.top, Theme.spacingXS)
        }
    }

    // CTA dégradé vers un onglet (même mécanisme que planReadyCard).
    private func navCTA(title: String, icon: String, colors: [Color], destination: NavCardDestination) -> some View {
        Button {
            HapticService.shared.tap()
            NotificationCenter.default.post(name: .healthmapNavigateToTab, object: destination.rawValue)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 66)
            .padding(.horizontal, Theme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel(title)
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
                .tint(Color.healthMapBlue)
                .frame(maxWidth: 200)
                .animation(.easeInOut(duration: 0.4), value: progress)

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
            // Progression synthétique : avance vite au début puis ralentit
            // (asymptote ~0,95) pour signaler que ça travaille — la durée réelle
            // est inconnue. Les messages tournent toutes les ~3,6 s (hors
            // reduce-motion). La tâche est annulée quand le bilan arrive.
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.4))
                if Task.isCancelled { break }
                ticks += 1
                progress = min(0.95, progress + (0.95 - progress) * 0.03)
                if !reduceMotion && ticks % 9 == 0 {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        messageIndex = (messageIndex + 1) % messages.count
                    }
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

// MARK: - Nutrient gap chip (carte compacte, ligne horizontale)
private struct NutrientGapChip: View {
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

// MARK: - Symptom compact card (horizontal) — tap ouvre la feuille des causes
// Refonte 20 juin v2 : compact, en ligne (comme les apports). Les causes ne
// sont PAS affichées ici ; "Comprendre les causes" déclenche onTap -> feuille.
private struct SymptomCompactCard: View {
    let item: SymptomeAnalyse
    let onTap: () -> Void

    private var causeCount: Int { (item.causesProbables ?? []).count }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentSky)
                        .frame(width: 28, height: 28)
                        .background(Color.accentSky.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)
                    Text(prettifySymptom(item.symptome ?? ""))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Text("\(causeCount) cause\(causeCount > 1 ? "s" : "") possible\(causeCount > 1 ? "s" : "")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.healthMapMuted)

                Spacer(minLength: 0)

                Text("Comprendre les causes")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.healthMapBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.healthMapBlueLight)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .padding(11)
            .frame(width: 158, height: 134, alignment: .topLeading)
            .cardStyle()
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(prettifySymptom(item.symptome ?? "")), \(causeCount) causes possibles. Toucher pour comprendre.")
    }
}

// MARK: - Symptom causes sheet (ouverte au tap "Comprendre les causes")
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
                            .foregroundStyle(Color.accentSky)
                            .frame(width: 36, height: 36)
                            .background(Color.accentSky.opacity(0.14))
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
