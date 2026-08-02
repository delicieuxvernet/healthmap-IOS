import SwiftUI
import Foundation

// MARK: - Suivi View (onglet 2 — « Mon suivi » v4 « zéro effort »)
//
// Refonte v4 (maquette « impl_Suivi.html ») : philosophie « zéro effort ». TOUT
// se calcule seul à partir de données DÉJÀ chargées par l'app — l'utilisateur ne
// cherche rien. Aucun appel réseau / LLM à l'affichage : tous les chiffres
// viennent de `SuiviEngineV4` (moteurs déterministes) nourris par :
//   • le score de la semaine  → WeekScoreEngine.compute(meals:weakNutrients:)
//   • le journal alimentaire  → MealJournalViewModel.fortnight (14 derniers jours)
//   • les symptômes déclarés  → DashboardViewModel.analysisV2?.bilan?.symptomes
//   • les scores nutriments   → DashboardViewModel.nutrients (< 60 = à renforcer)
//   • l'activité Apple Santé  → HealthKitService.importSnapshot().steps (optionnel)
//   • les ressentis locaux    → SuiviCheckinHistory (UserDefaults scopé jour)
//   • la série de gamif       → GamificationService.currentStreak + harvestLadder
//
// Blocs, dans l'ordre de la maquette :
//   0. Pop-up check-in « 2 questions rapides » À L'ARRIVÉE (une fois par jour,
//      bouton « Plus tard », confirmation verte quand répondu).
//   1. Titre « Mon suivi » / sous-titre « Mis à jour tout seul… ».
//   2. 3 stats glanceables (Besoins couverts · Repas scannés · Besoins du jour).
//   3. 1 carte par symptôme : verdict ÉCRIT + variation signée + mini-graphe à
//      labels POSÉS (toi / sans Kiwio) — plus d'onglets ni de légende.
//   4. « Besoins vs apports » : bandeau « besoins augmentés » (activité Santé) +
//      « Pour faire mieux la semaine prochaine » (2 conseils tirés des manques).
//   5. « Ta progression par nutriment » : socle bilan + gain depuis le départ.
//   6. « Tes prochains paliers » : prochain fruit + projection besoins couverts.
//
// État vide propre partout : bilan / journal indisponibles → carte d'attente ou
// d'invitation, JAMAIS de crash ni de chiffre inventé. Reduce-motion respecté.
struct SuiviView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @ObservedObject private var gamification = GamificationService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Journal alimentaire (14 derniers jours) — chargé À L'AFFICHAGE (lecture
    /// Supabase RLS de meal_scans, pas d'IA/LLM). Nourrit WeekScoreEngine et la
    /// couverture 7 jours. Détenu ici : `SuiviView` est monté avec le seul
    /// `dashboardVM` en environnement (cf. ContentView), le journal n'y est pas.
    @StateObject private var journal = MealJournalViewModel()

    /// Pas du jour lus via Apple Santé (nil = non lié / indispo → delta 0,
    /// jamais inventé). Lu une fois à l'affichage.
    @State private var stepsToday: Int?

    /// Ressentis locaux des 7 derniers jours (courbe « toi » des symptômes).
    /// Rechargé après chaque réponse au check-in du jour.
    @State private var checkinHistory: [Int] = []

    /// Pop-up check-in du jour : présenté une fois par jour si pas déjà répondu.
    @State private var showCheckin = false

    /// Le vrai suivi est-il démarré ? Faux → les courbes sont des EXEMPLES badgés
    /// avec un bandeau « Commencer mon suivi ». Vrai → courbes nourries UNIQUEMENT
    /// par les check-ins réels. Initialisé depuis SuiviTrackingStore à l'affichage.
    @State private var isTracking = false

    /// Incrémenté après chaque check-in pour forcer le recalcul des courbes
    /// symptômes (qui relisent les ressentis persistés à la volée).
    @State private var checkinTick = 0

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        titleBlock
                        SuiviStatsRow(stats: stats)
                        macroCarousel
                        microCarousel
                        symptomCarousel
                        SuiviNeedsCard(delta: stats.besoinsDuJourDeltaPct,
                                       stepsToday: stepsToday,
                                       tips: weeklyTips)
                        SuiviPaliersCard(paliers: paliers)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    // Verrou anti-dérive horizontale : la largeur du contenu est
                    // épinglée à celle du ScrollView → plus de slide latéral vers
                    // une marge vide (l'écran ne bouge plus qu'en vertical).
                    .containerRelativeFrame(.horizontal)
                }
            }
            .kiwiTabBarBottomInset()
            .navigationBarTitleDisplayMode(.inline)
            .kiwiNavigationBarBackground()
            .toolbar {
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
            // Pop-up check-in « 2 questions rapides » à l'arrivée.
            .overlay {
                if showCheckin {
                    SuiviCheckinPopup(
                        symptoms: checkinSymptoms,
                        reduceMotion: reduceMotion,
                        onFinish: { feels, energy in
                            SuiviCheckinStore.saveToday(symptomFeels: feels, energyFeel: energy)
                            gamification.recordCheckin()
                            checkinTick += 1
                            HapticService.shared.success()
                        },
                        onLater: {
                            SuiviCheckinStore.snoozeToday()
                            HapticService.shared.selection()
                        },
                        isPresented: $showCheckin
                    )
                    .transition(.opacity)
                    .zIndex(60)
                }
            }
            .task {
                isTracking = SuiviTrackingStore.isStarted()
                // Suivi déjà démarré → on (re)planifie les rappels en silence
                // (idempotent, sans redemander la permission). Couvre ceux qui
                // suivaient déjà avant l'arrivée des rappels quotidiens.
                if isTracking {
                    await LocalNotificationService.scheduleDailyReminders()
                }
                await journal.load()
                stepsToday = await Self.loadSteps()
                checkinHistory = SuiviCheckinHistory.recentFeelings()
            }
            // Un scan fait dans l'onglet Scanner ne relance pas ce .task (le Suivi
            // reste vivant) : on recharge pour que couverture/paliers intègrent le scan.
            .onReceive(NotificationCenter.default.publisher(for: .healthmapMealScanned)) { _ in
                Task { await journal.load() }
            }
            .onAppear {
                // Présenté UNE fois par jour, jamais si déjà répondu / snoozé, et
                // uniquement s'il y a au moins un symptôme déclaré à suivre (sinon
                // le pop-up n'aurait aucune question exploitable).
                if SuiviCheckinStore.shouldPromptToday(), !checkinSymptoms.isEmpty {
                    if reduceMotion {
                        showCheckin = true
                    } else {
                        withAnimation(.easeOut(duration: 0.25)) { showCheckin = true }
                    }
                }
            }
        }
    }

    // MARK: - 1. Titre « Mon suivi »
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mon suivi")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.kiwiCharcoal)
            Text("Mis à jour tout seul, d'après tes scans et Santé")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Seuil « 3 jours d'affilée » avant les vraies courbes
    /// Tant que l'utilisateur n'a pas scanné 3 jours consécutifs, macros et
    /// micros affichent une courbe d'EXEMPLE badgée (comme les symptômes) au
    /// lieu de graphiques vides / à trous. Ses vraies données restent masquées
    /// jusque-là (demande produit : pas de résultats avant 3 jours complétés).
    private var hasEnoughScanData: Bool {
        SuiviEngineV4.maxConsecutiveScannedDays(fortnight: journal.fortnight) >= 3
    }

    // MARK: - 3. Carrousel MACROS (vraies grammes/kcal par jour, scannées)
    private var macroCarousel: some View {
        let kinds = SuiviEngineV4.MacroKind.allCases
        let showExample = !hasEnoughScanData
        return SuiviCarouselBlock(
            title: "Macros du jour",
            systemIcon: "flame.fill",
            tint: Color.kiwiGreen,
            pageTitles: kinds.map(\.label),
            pageHeight: 168
        ) { i in
            let kind = kinds[i]
            let series = showExample
                ? SuiviEngineV4.exampleMacroSeries(kind)
                : SuiviEngineV4.macroDailySeries(fortnight: journal.fortnight, macro: kind)
            VStack(alignment: .leading, spacing: 10) {
                SuiviValueChart(points: series, color: macroColor(kind), fixedPercent: false)
                    .frame(height: 112)
                if showExample {
                    SuiviExampleNote()
                } else {
                    SuiviCurveInsight(summary: SuiviEngineV4.seriesSummary(series), unit: kind.unit)
                }
            }
        }
    }

    // MARK: - 4. Carrousel MICROS (couverture % AJR par jour, apports à renforcer)
    @ViewBuilder
    private var microCarousel: some View {
        let showExample = !hasEnoughScanData
        // En mode exemple, on garde des courbes vivantes même sans scan : à
        // défaut d'apports à renforcer détectés, on illustre sur 3 micros types.
        let ids = showExample && microIds.isEmpty ? ["iron", "magnesium", "vitD"] : microIds
        if ids.isEmpty {
            emptyMicroCard
        } else {
            VStack(spacing: 12) {
                SuiviCarouselBlock(
                    title: "Micros à renforcer",
                    systemIcon: "flask.fill",
                    tint: Color(hex: "C9A227"),
                    pageTitles: ids.map { NutrientData.definition(for: $0)?.label ?? $0 },
                    pageHeight: 168,
                    isLocked: !subscriptionService.isPremium
                ) { i in
                    let id = ids[i]
                    let series = showExample
                        ? SuiviEngineV4.exampleMicroSeries()
                        : SuiviEngineV4.microDailySeries(fortnight: journal.fortnight, id: id)
                    VStack(alignment: .leading, spacing: 10) {
                        SuiviValueChart(points: series, color: microColor(id), fixedPercent: true)
                            .frame(height: 112)
                        if showExample {
                            SuiviExampleNote()
                        } else {
                            SuiviCurveInsight(summary: SuiviEngineV4.seriesSummary(series), unit: "%")
                        }
                    }
                }

                if !subscriptionService.isPremium {
                    UnlockDoor(
                        icon: "chart.xyaxis.line",
                        title: "Débloque la tendance de tes apports",
                        subtitle: "Visualise leur évolution jour après jour",
                        zone: "suivi_micros"
                    )
                }
            }
        }
    }

    private var emptyMicroCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "flask")
                .font(.system(size: 18))
                .foregroundStyle(Color.healthMapMuted)
            Text("Scanne des repas pour suivre tes apports à renforcer.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .kiwiCard()
    }

    // MARK: - 5. Carrousel SYMPTÔMES (cumulé +/- PAR symptôme, indépendant)
    @ViewBuilder
    private var symptomCarousel: some View {
        // `checkinTick` est LU ici pour forcer le recalcul après un check-in
        // (les ressentis sont relus depuis UserDefaults à la volée).
        let _ = checkinTick
        let ids = checkinSymptomIds
        // Mode réel dès le suivi démarré : chaque courbe ne réagit qu'aux
        // check-ins réels de SON symptôme (`feelingsById`). Sinon EXEMPLE badgé.
        let feelingsById = isTracking
            ? SuiviCheckinHistory.feelingsById(symptomIds: ids,
                                               since: SuiviTrackingStore.startDate() ?? Date())
            : [:]
        let evolutions = SuiviEngineV4.symptomEvolutions(
            symptomes: dashboardVM.analysisV2?.bilan?.symptomes,
            feelingsById: feelingsById,
            isTracking: isTracking
        )
        if !evolutions.isEmpty {
            VStack(spacing: 10) {
                if !isTracking {
                    SuiviStartBanner(action: startTracking)
                }
                SuiviCarouselBlock(
                    title: "Symptômes",
                    systemIcon: "heart.text.square",
                    tint: Color(hex: "5B49B5"),
                    pageTitles: evolutions.map { capitalized($0.nom) },
                    pageHeight: 214
                ) { i in
                    SuiviSymptomPage(evolution: evolutions[i],
                                     reduceMotion: reduceMotion,
                                     locked: !subscriptionService.isPremium)
                }

                // Porte affichée seulement s'il y a une VRAIE trajectoire à
                // débloquer (en mode exemple, la courbe est déjà visible).
                if !subscriptionService.isPremium, evolutions.contains(where: { !$0.isExample }) {
                    UnlockDoor(
                        icon: "chart.xyaxis.line",
                        title: "Vois l'évolution de tes symptômes",
                        subtitle: "Ta trajectoire, semaine après semaine",
                        zone: "suivi_symptomes"
                    )
                }
            }
        } else if dashboardVM.isLoadingAnalysisV2 {
            SuiviLoadingCard(text: "On regarde tes symptômes déclarés…")
        } else {
            SuiviNoSymptomCard()
        }
    }

    // MARK: - Sélecteurs de données des carrousels

    /// Symptômes déclarés (id + nom + sens) — pilotent le carrousel ET le check-in.
    private var checkinSymptoms: [(id: String, nom: String, trend: SymptomTrend)] {
        (dashboardVM.analysisV2?.bilan?.symptomes ?? []).compactMap { s in
            guard let nom = s.nom, !nom.isEmpty else { return nil }
            return (s.id ?? nom, nom, SymptomTrend.make(from: nom))
        }
    }
    private var checkinSymptomIds: [String] { checkinSymptoms.map(\.id) }

    /// Micros du carrousel : apports à renforcer (< 60) en priorité ; à défaut,
    /// tous les micros réellement présents dans les scans. Ordre canonique, ≤ 8.
    private var microIds: [String] {
        let weak = weakNutrientIds
        let base = weak.isEmpty
            ? Array(Set(journal.fortnight.flatMap { $0.micros.map(\.id) }))
            : weak
        let canonical = NutrientData.all.map { $0.id.rawValue }
        let sorted = base.sorted { a, b in
            let ia = canonical.firstIndex(of: a) ?? Int.max
            let ib = canonical.firstIndex(of: b) ?? Int.max
            return ia == ib ? a < b : ia < ib
        }
        return Array(sorted.prefix(8))
    }

    private func macroColor(_ k: SuiviEngineV4.MacroKind) -> Color {
        switch k {
        case .calories: return Color.kiwiCharcoal
        case .proteins: return Color.macroProtein
        case .carbs:    return Color.macroCarb
        case .fats:     return Color.macroFat
        case .fiber:    return Color.kiwiGreen
        }
    }
    private func microColor(_ id: String) -> Color { Color.nutrientColor(for: id) }

    private func capitalized(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }

    /// Bascule vers le VRAI suivi : fige la date de début et recharge la série
    /// réelle. À partir de là, les courbes ne reflètent que les check-ins réels.
    private func startTracking() {
        SuiviTrackingStore.start()
        isTracking = true
        checkinHistory = SuiviCheckinHistory.recentFeelings()
        HapticService.shared.success()
        // Active les 2 rappels quotidiens (12 h 30 « photographie ton repas » +
        // 19 h 30 « suis l'évolution de tes symptômes »). La permission
        // notifications est demandée ICI, au moment de valeur — jamais au
        // lancement (règle App Store). Refus → le suivi marche quand même, sans rappel.
        Task { await LocalNotificationService.enableReminders() }
    }

    // MARK: - Dérivés déterministes (aucun appel réseau)

    /// Score de la semaine calculé localement à partir du journal + des apports
    /// à renforcer (score local < 60, même seuil que le scan).
    private var weekScore: WeekScoreEngine.WeekScore {
        WeekScoreEngine.compute(meals: journal.fortnight, weakNutrients: weakNutrientIds)
    }

    /// Ids des apports à renforcer (score < 60) — priorise l'affichage de la
    /// couverture et cible le score de la semaine.
    private var weakNutrientIds: [String] {
        dashboardVM.nutrients.filter { $0.score < 60 }.map(\.id)
    }

    private var stats: SuiviEngineV4.SuiviStats {
        SuiviEngineV4.stats(weekScore: weekScore, stepsToday: stepsToday)
    }

    private var coverage: [SuiviEngineV4.NutrientCoverage7d] {
        // Socle « départ » = baseline persistée (scores figés au 1er bilan).
        // Tant qu'elle n'est pas capturée, on passe [:] : la barre affiche alors
        // juste le niveau courant sans progrès (évite un socle transitoire faux).
        let baseline = dashboardVM.profile.baselineNutrientScores ?? [:]
        return SuiviEngineV4.nutrientCoverage(fortnight: journal.fortnight,
                                              focusIds: weakNutrientIds,
                                              baseline: baseline)
    }

    private var weeklyTips: [SuiviEngineV4.WeeklyTip] {
        SuiviEngineV4.weeklyTips(coverage: coverage)
    }

    private var paliers: SuiviEngineV4.NextPaliers {
        SuiviEngineV4.nextPaliers(streak: gamification.currentStreak,
                                  besoinsCouvertsPct: stats.besoinsCouvertsPct)
    }

    // MARK: - Apple Santé (lecture des pas du jour, hors main pour ne pas bloquer)
    private static func loadSteps() async -> Int? {
        await HealthKitService.shared.importSnapshot().steps
    }
}

// MARK: - Sens d'évolution d'un symptôme (logique métier)
// Un symptôme « problème » (ongles cassants, digestion, cheveux, humeur,
// sommeil, fatigue…) s'améliore quand sa courbe DESCEND. Un objectif positif
// (énergie, concentration…) s'améliore quand sa courbe MONTE.
enum SymptomDir { case lowerBetter, higherBetter }

struct SymptomTrend {
    let dir: SymptomDir
    let noun: String        // « tes ongles », « ton énergie »
    let betterLabel: String // « Moins cassants », « Plus d'énergie »
    let worseLabel: String  // « Plus cassants », « Moins d'énergie »

    var evolutionTitle: String { "Évolution de \(noun)" }
    var checkinQuestion: String {
        let cap = noun.prefix(1).uppercased() + noun.dropFirst()
        return "\(cap) cette semaine\u{00A0}?"
    }
    var improvingDown: Bool { dir == .lowerBetter }

    static func make(from symptom: String) -> SymptomTrend {
        let s = symptom.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        func has(_ ks: [String]) -> Bool { ks.contains { s.contains($0) } }
        if has(["energie", "vitalit", "tonus", "entrain", "peche", "forme"]) {
            return SymptomTrend(dir: .higherBetter, noun: "ton énergie", betterLabel: "Plus d'énergie", worseLabel: "Moins d'énergie")
        }
        if has(["concentr", "memoire", "focus", "clart", "vigilan"]) {
            return SymptomTrend(dir: .higherBetter, noun: "ta concentration", betterLabel: "Plus nette", worseLabel: "Moins nette")
        }
        if has(["ongle"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "tes ongles", betterLabel: "Moins cassants", worseLabel: "Plus cassants")
        }
        if has(["cheveu", "chute", "alopec"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "tes cheveux", betterLabel: "Moins de chute", worseLabel: "Plus de chute")
        }
        if has(["digest", "ballonn", "transit", "intestin", "constip"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "ta digestion", betterLabel: "Plus légère", worseLabel: "Plus lourde")
        }
        if has(["humeur", "moral", "irritab", "nervos"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "ton humeur", betterLabel: "Plus stable", worseLabel: "Moins stable")
        }
        if has(["sommeil", "dormir", "insomn", "reveil"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "ton sommeil", betterLabel: "Meilleur", worseLabel: "Moins bon")
        }
        if has(["fatigue", "epuis", "las"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "ta fatigue", betterLabel: "Moins fatigué", worseLabel: "Plus fatigué")
        }
        if has(["peau", "acne", "bouton", "teint"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "ta peau", betterLabel: "Plus nette", worseLabel: "Moins nette")
        }
        if has(["stress", "anxi"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "ton stress", betterLabel: "Moins de stress", worseLabel: "Plus de stress")
        }
        let tail = (symptom.split(separator: " ").first.map(String.init) ?? symptom).lowercased()
        return SymptomTrend(dir: .lowerBetter, noun: "tes \(tail)", betterLabel: "Mieux", worseLabel: "Moins bien")
    }
}

// MARK: - 2. Bandeau de 3 stats glanceables
private struct SuiviStatsRow: View {
    let stats: SuiviEngineV4.SuiviStats

    var body: some View {
        HStack(spacing: 10) {
            statCard(label: "Besoins couverts",
                     value: "\(stats.besoinsCouvertsPct)",
                     suffix: "%",
                     color: Color.kiwiGreenInk)
            statCard(label: "Repas scannés",
                     value: "\(stats.repasScannesCount)",
                     suffix: "· 7 j",
                     color: Color(hex: "D9820A"))
            statCard(label: "Besoins du jour",
                     value: signed(stats.besoinsDuJourDeltaPct),
                     suffix: "%",
                     color: Color(hex: "2F6FE0"))
        }
    }

    private func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : "\(v)" }

    private func statCard(label: String, value: String, suffix: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Color.healthMapMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                Text(suffix)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 14)
        .kiwiCard(radius: 20)
    }
}

// MARK: - Bilan pas encore chargé / aucun symptôme — états vides honnêtes
private struct SuiviLoadingCard: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Color.kiwiGreen)
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .kiwiCard()
    }
}

private struct SuiviNoSymptomCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aucun symptôme à suivre")
                .font(.system(size: 16.5, weight: .heavy))
                .foregroundStyle(Color.kiwiCharcoal)
            Text("Tu n'as déclaré aucun symptôme dans ton questionnaire, il n'y a donc rien à suivre ici pour le moment.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .kiwiCard()
    }
}

// MARK: - Bandeau « Commencer mon suivi » (uniquement en mode exemple)
/// Bandeau UNIQUE posé en tête de la section symptômes tant que le vrai suivi
/// n'est pas démarré : explique que les courbes sont un exemple et propose un
/// seul bouton pour basculer vers un suivi nourri par les vrais check-ins.
private struct SuiviStartBanner: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.kiwiGreenInk)
                    .padding(.top, 1)
                Text("Ces courbes sont un exemple. Démarre ton suivi pour les remplir avec tes vraies données.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            Button(action: action) {
                Text("Commencer mon suivi")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.kiwiGreen)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityHint("Bascule tes courbes vers un vrai suivi nourri par tes réponses")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.kiwiGreenSoft))
    }
}

// MARK: - 3. Carte « Évolution du symptôme » (verdict écrit + graphe posé)
/// Verdict d'abord (pastille), phrase d'insight en gros, variation signée, puis
/// mini-graphe à 3 séries avec labels POSÉS directement sur les courbes (« toi »
/// / « sans Kiwio ») et sur les pôles de l'axe. Plus d'onglets ni de légende.
private struct SuiviSymptomPage: View {
    let evolution: SuiviEngineV4.SymptomEvolution
    let reduceMotion: Bool
    /// Famille 2 du handoff Premium : le verdict du jour reste NET, seule la
    /// trajectoire dans le temps est gatée. On ne floute jamais une courbe
    /// d'EXEMPLE (le suivi n'a pas démarré) : ce serait cacher une démo.
    var locked: Bool = false

    private var chartLocked: Bool { locked && !evolution.isExample }

    @State private var progress: CGFloat = 0

    /// Nb de points réels de la courbe « toi » (baseline + 1 par check-in).
    private var realPointCount: Int { evolution.reel.count }
    /// Mode réel mais aucun check-in encore : la courbe « démarre » (jour 0).
    private var isDayZero: Bool { !evolution.isExample && realPointCount < 2 }

    // La pastille change selon l'état : Exemple / Jour 0 / verdict réel.
    private var pillText: String {
        if evolution.isExample { return "Exemple" }
        if isDayZero { return "Jour 0" }
        return evolution.verdict
    }
    private var pillColor: Color {
        if evolution.isExample { return Color(hex: "5F5E5A") }
        if isDayZero { return Color.kiwiGreenInk }
        return evolution.improving ? Color.kiwiGreenInk : Color(hex: "D9820A")
    }
    private var pillBg: Color {
        if evolution.isExample { return Color(hex: "F1EFE8") }
        if isDayZero { return Color.kiwiGreenSoft }
        return evolution.improving ? Color.kiwiGreenSoft : Color(hex: "FDECD6")
    }
    /// Icône de pastille : neutre en exemple / jour 0, flèche de sens en réel.
    private var pillIcon: String? {
        if evolution.isExample { return "sparkles" }
        if isDayZero { return "circle.dashed" }
        guard evolution.verdict != "Stable" else { return "equal" }
        // La flèche suit le SENS RÉEL de la courbe (baisse d'un problème = flèche
        // vers le bas), indépendamment du fait que ce soit une bonne nouvelle.
        return evolution.variationPct < 0 ? "arrow.down.right" : "arrow.up.right"
    }

    private var insightSentence: String {
        // Phrase d'insight ANCRÉE sur le nom du symptôme + l'état — jamais sur un
        // pôle d'axe (dont le « bon côté » dépend du sens). Le nom + verdict est
        // toujours juste, quel que soit le sens.
        let nom = evolution.nom.lowercased()
        if evolution.isExample {
            return "Voici à quoi ressemblera ton suivi de \(nom)."
        }
        if isDayZero {
            return "Ton suivi de \(nom) démarre, tes réponses vont le dessiner."
        }
        switch evolution.verdict {
        case "En amélioration": return "Ton suivi de \(nom) s'améliore depuis ton arrivée."
        case "À surveiller":    return "Ton suivi de \(nom) est à surveiller ces jours-ci."
        default:                return "Ton suivi de \(nom) reste stable depuis ton arrivée."
        }
    }

    var body: some View {
        // Le nom du symptôme est déjà porté par l'en-tête du carrousel : ici on
        // ne garde que la pastille de verdict, l'insight et la courbe (pas de
        // carte — le bloc carrousel fournit déjà la carte crème).
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    if let icon = pillIcon {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .heavy))
                    }
                    Text(pillText)
                        .font(.system(size: 11.5, weight: .heavy))
                }
                .foregroundStyle(pillColor)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(pillBg))
            }

            // Pas de pourcentage chiffré : la référence ("sans Kiwio") est une
            // trajectoire illustrative, pas une mesure précise du symptôme — un
            // "-38%" laisserait croire à une précision qui n'existe pas (audit
            // 2026-07-05). Le verdict (pastille) + l'insight suffisent.
            Text(insightSentence)
                .font(.system(size: 15.5, weight: .heavy))
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            if chartLocked {
                GatedOverlay(intensity: .teaser) {
                    SuiviPosedChart(evolution: evolution, progress: progress)
                        .frame(height: 132)
                }
                .padding(.top, 10)
            } else {
                SuiviPosedChart(evolution: evolution, progress: progress)
                    .frame(height: 132)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if reduceMotion { progress = 1 }
            else { withAnimation(.easeOut(duration: 1.0).delay(0.1)) { progress = 1 } }
        }
    }

    private var capitalizedNom: String {
        let n = evolution.nom
        guard let first = n.first else { return n }
        return first.uppercased() + n.dropFirst()
    }
}

// MARK: - Mini-graphe à labels posés (toi / sans Kiwio + pôles d'axe)
/// 2 séries : « toi » (plein vert, animée) et « sans Kiwio » (pointillés gris).
/// Les libellés sont écrits DIRECTEMENT sur le tracé — plus de légende séparée.
/// Échelle 0-100, niveau haut = tracé haut.
private struct SuiviPosedChart: View {
    let evolution: SuiviEngineV4.SymptomEvolution
    let progress: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let reel = evolution.reel
            let sans = evolution.sansKiwio
            let n = reel.count
            // Rien à tracer sans point « toi » ; « sans Kiwio » garantit ≥ 2 points.
            guard n >= 1 else { return }
            let padL: CGFloat = 6

            // Position horizontale d'un point « toi » : si un seul point, calé à
            // gauche (jour 0) ; sinon réparti sur toute la largeur utile.
            func px(_ i: Int) -> CGFloat {
                guard n > 1 else { return padL }
                return padL + (w - padL) * CGFloat(i) / CGFloat(n - 1)
            }
            // « sans Kiwio » a sa propre longueur (≥ 2) et occupe toute la largeur.
            func pxSans(_ i: Int, count: Int) -> CGFloat {
                guard count > 1 else { return padL }
                return w * CGFloat(i) / CGFloat(count - 1)
            }
            func py(_ v: Double) -> CGFloat {
                let t = CGFloat(v) / 100
                return h * (0.12 + (1 - t) * 0.72)
            }
            func reelPoints(_ vals: [Double]) -> [CGPoint] {
                vals.enumerated().map { CGPoint(x: px($0.offset), y: py($0.element)) }
            }
            func sansPoints(_ vals: [Double]) -> [CGPoint] {
                vals.enumerated().map { CGPoint(x: pxSans($0.offset, count: vals.count), y: py($0.element)) }
            }

            // Grille horizontale discrète
            for g in stride(from: 0.0, through: 1.0, by: 0.25) {
                let y = h * g
                var gp = Path(); gp.move(to: CGPoint(x: 0, y: y)); gp.addLine(to: CGPoint(x: w, y: y))
                ctx.stroke(gp, with: .color(Color.kiwiCharcoal.opacity(0.05)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 5]))
            }

            // « sans Kiwio » — pointillés gris (toujours ≥ 2 points → ligne visible)
            let sansPts = sansPoints(sans)
            if sansPts.count > 1 {
                ctx.stroke(SuiviCurveMath.smoothPath(sansPts),
                           with: .color(Color(hex: "C2BDB0")),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round, dash: [2, 5]))
            }

            // « toi » — plein vert + aire, animée par `progress`. En EXEMPLE, tracé
            // fondu + tirets ; sinon plein. Avec un seul point (jour 0), on ne
            // trace pas de ligne, juste le point.
            let reelPts = reelPoints(reel)
            let toiColor = Color.kiwiGreen
            let toiOpacity: Double = evolution.isExample ? 0.42 : 1.0
            let toiDash: [CGFloat] = evolution.isExample ? [7, 5] : []

            if reelPts.count > 1 {
                let visible = max(2, Int(ceil(CGFloat(n) * progress)))
                let drawn = Array(reelPts.prefix(visible))
                let line = SuiviCurveMath.smoothPath(drawn)
                if !evolution.isExample {
                    // Aire de remplissage réservée au vrai suivi (l'exemple reste léger).
                    var area = line
                    area.addLine(to: CGPoint(x: drawn.last!.x, y: h))
                    area.addLine(to: CGPoint(x: drawn.first!.x, y: h))
                    area.closeSubpath()
                    ctx.fill(area, with: .color(toiColor.opacity(0.10)))
                }
                ctx.stroke(line, with: .color(toiColor.opacity(toiOpacity)),
                           style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round, dash: toiDash))

                if let p = drawn.last {
                    let r: CGFloat = 4.5
                    let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    ctx.fill(dot, with: .color(toiColor.opacity(toiOpacity)))
                    ctx.stroke(dot, with: .color(.white), style: StrokeStyle(lineWidth: 2.5))
                }
            } else if let p = reelPts.first {
                // Un seul point (jour 0) : pas de ligne, juste le repère « toi ».
                let r: CGFloat = 4.5
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(toiColor))
                ctx.stroke(dot, with: .color(.white), style: StrokeStyle(lineWidth: 2.5))
            }

            // Labels POSÉS sur les courbes (fin de tracé). Point unique (jour 0) :
            // le label part À DROITE du point pour ne pas déborder à gauche.
            if let tip = reelPts.last {
                if reelPts.count > 1 {
                    ctx.draw(
                        Text(evolution.labelToi)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(Color.kiwiGreenInk),
                        at: CGPoint(x: tip.x - 4, y: max(12, tip.y - 14)),
                        anchor: .trailing
                    )
                } else {
                    ctx.draw(
                        Text(evolution.labelToi)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(Color.kiwiGreenInk),
                        at: CGPoint(x: tip.x + 10, y: max(12, tip.y - 14)),
                        anchor: .leading
                    )
                }
            }
            if let tip = sansPts.last {
                ctx.draw(
                    Text(evolution.labelSansKiwio)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Color(hex: "9CA3AF")),
                    at: CGPoint(x: tip.x - 4, y: min(h - 10, tip.y + 13)),
                    anchor: .trailing
                )
            }
        }
        .overlay(alignment: .topLeading) {
            Text(evolution.labelHaut)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.healthMapMuted)
                .padding(.leading, 2)
        }
        .overlay(alignment: .bottomLeading) {
            Text(evolution.labelBas)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.healthMapMuted)
                .padding(.leading, 2)
        }
        .accessibilityElement()
        .accessibilityLabel("\(evolution.nom) : \(chartA11yStatus)")
    }

    /// Statut lu par VoiceOver — cohérent avec la pastille de la carte.
    private var chartA11yStatus: String {
        if evolution.isExample { return "exemple" }
        if evolution.reel.count < 2 { return "jour 0, suivi qui démarre" }
        return evolution.verdict
    }
}

// MARK: - 4. Carte « Besoins vs apports » (activité Santé + conseils semaine)
/// Bandeau « besoins augmentés » quand l'activité Apple Santé fait monter les
/// besoins du jour (delta > 0, sinon le bandeau est masqué — jamais de valeur
/// factice), suivi de « Pour faire mieux la semaine prochaine » : 2 conseils
/// concrets tirés des 2 apports les plus bas.
private struct SuiviNeedsCard: View {
    let delta: Int
    let stepsToday: Int?
    let tips: [SuiviEngineV4.WeeklyTip]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "camera")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kiwiGreenInk)
                Text("Besoins vs apports")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiGreenInk)
                Spacer()
                Text("7 j")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.healthMapMuted)
            }
            .padding(.horizontal, 2)

            if delta > 0 {
                needsBanner
                    .padding(.top, 12)
            }

            if !tips.isEmpty {
                Rectangle()
                    .fill(Color.kiwiCharcoal.opacity(0.06))
                    .frame(height: 1)
                    .padding(.top, 14)

                Text("POUR FAIRE MIEUX LA SEMAINE PROCHAINE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Color(hex: "2F6FE0"))
                    .padding(.top, 14)
                    .padding(.horizontal, 2)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tips) { tip in
                        tipRow(tip)
                    }
                }
                .padding(.top, 10)
            } else if delta <= 0 {
                // Ni activité en hausse ni conseil (journal sans micros) —
                // message d'invitation honnête, jamais de faux chiffre.
                Text("Scanne tes repas pour voir tes apports se comparer à tes besoins, jour après jour.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .kiwiCard()
    }

    private var needsBanner: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.healthMapCard)
                    .frame(width: 50, height: 50)
                    .shadow(color: Color.kiwiCharcoal.opacity(0.08), radius: 4, x: 0, y: 2)
                Image(systemName: "heart.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.scoreDeficient)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Tes besoins ont augmenté aujourd'hui")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.kiwiGreenInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(stepsSubtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color(hex: "4f7a2a"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            VStack(spacing: 2) {
                Text("+\(delta)%")
                    .font(.system(size: 27, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.kiwiGreenInk)
                Text("besoins")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: "6f9a3f"))
            }
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.kiwiGreenSoft))
    }

    private var stepsSubtitle: String {
        if let s = stepsToday {
            return "Tu as bougé plus que d'habitude : \(formatSteps(s)) pas via Santé"
        }
        return "Tu as bougé plus que d'habitude aujourd'hui"
    }

    private func formatSteps(_ steps: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{202F}"
        return f.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    private func tipRow(_ tip: SuiviEngineV4.WeeklyTip) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Fluent3DIcon(name: SuiviTipIcon.asset(for: tip.id), size: 30)
            Text(tip.text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color(hex: "3a3833"))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Choix d'illustration 3D par apport pour les conseils (assets `fluent_*`
/// existants uniquement — un id inconnu retombe sur un pictogramme sûr).
private enum SuiviTipIcon {
    static func asset(for id: String) -> String {
        switch id {
        case "calcium":   return Fluent3D.milk
        case "iron":      return Fluent3D.meat
        case "magnesium": return Fluent3D.peanuts
        case "vitD":      return Fluent3D.fish
        case "vitB12":    return Fluent3D.egg
        case "omega3":    return Fluent3D.fish
        case "vitC":      return Fluent3D.tangerine
        case "zinc":      return Fluent3D.oyster
        case "iodine":    return Fluent3D.fish
        case "fiber":     return Fluent3D.broccoli
        default:          return Fluent3D.leafyGreen
        }
    }
}


// MARK: - 6. Carte « Tes prochains paliers »
private struct SuiviPaliersCard: View {
    let paliers: SuiviEngineV4.NextPaliers

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kiwiGreenInk)
                Text("Tes prochains paliers")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiGreenInk)
            }
            .padding(.horizontal, 2)

            // Prochain fruit de la récolte
            HStack(spacing: 13) {
                Fluent3DIcon(name: paliers.fruitAsset, size: 38)
                VStack(alignment: .leading, spacing: 7) {
                    fruitTitle
                    GaugeBar(fraction: fruitFraction)
                    Text("en continuant à scanner tes repas")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.healthMapMuted)
                }
            }
            .padding(.top, 14)

            // Projection besoins couverts
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.kiwiGreenSoft)
                        .frame(width: 38, height: 38)
                    Image(systemName: "trophy")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.kiwiGreenInk)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(paliers.projectionText)
                        .font(.system(size: 13.5, weight: .heavy))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("en suivant ton plan, tu es sur la bonne trajectoire")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.healthMapMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.kiwiCharcoal.opacity(0.06))
                    .frame(height: 1)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .kiwiCard()
    }

    private var fruitTitle: some View {
        Group {
            if paliers.joursRestants > 0 {
                (Text("\(paliers.fruitName) débloqué dans ")
                    + Text("\(paliers.joursRestants) j").font(.system(size: 13.5, weight: .heavy, design: .rounded).monospacedDigit()).foregroundColor(Color.kiwiGreenInk))
            } else {
                Text("\(paliers.fruitName) débloqué\u{00A0}!")
            }
        }
        .font(.system(size: 13.5, weight: .heavy))
        .foregroundStyle(Color.kiwiCharcoal)
    }

    /// Progression vers le prochain fruit : plus il reste de jours, moins la
    /// jauge est remplie (repère visuel, bornée 8-95 %).
    private var fruitFraction: CGFloat {
        guard paliers.joursRestants > 0 else { return 1 }
        // 0 jour restant = plein ; au-delà d'une quinzaine on plafonne bas.
        let remaining = min(14, paliers.joursRestants)
        return max(0.08, min(0.95, 1 - CGFloat(remaining) / 15))
    }
}

// MARK: - Jauge pleine (progression d'un palier)
private struct GaugeBar: View {
    let fraction: CGFloat

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: "E3DFD5")).frame(height: 6)
                Capsule().fill(Color.kiwiGreen)
                    .frame(width: max(6, g.size.width * max(0, min(1, fraction))), height: 6)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - 0. Pop-up check-in « 2 questions rapides » (à l'arrivée)
/// Modale légère (une fois par jour) : 2 questions à gros boutons-icônes (ongles
/// / énergie), bouton « Plus tard », confirmation verte quand les 2 sont
/// répondues. Écrit dans SuiviCheckinStore (mêmes clés que SuiviCheckinHistory).
private struct SuiviCheckinPopup: View {
    /// Symptômes déclarés (id + nom + sens) — UNE question 1-tap par symptôme,
    /// pour que chaque courbe évolue indépendamment.
    let symptoms: [(id: String, nom: String, trend: SymptomTrend)]
    let reduceMotion: Bool
    /// Ressenti PAR symptôme (id → 0/1/2) + énergie optionnelle.
    let onFinish: (_ symptomFeels: [String: Int], _ energyFeel: Int?) -> Void
    let onLater: () -> Void
    @Binding var isPresented: Bool

    @State private var choices: [String: Int] = [:]
    @State private var energyChoice: Int?
    @State private var confirmed = false

    private func choiceBinding(_ id: String) -> Binding<Int?> {
        Binding(get: { choices[id] }, set: { choices[id] = $0 })
    }
    private func capitalized(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.kiwiCharcoal.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismissLater() }

            card
                .padding(.horizontal, 14)
                .padding(.top, 56)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            // Poignée
            Capsule()
                .fill(Color.kiwiCharcoal.opacity(0.16))
                .frame(width: 38, height: 5)
                .padding(.top, 14)
                .padding(.bottom, 16)

            if confirmed {
                confirmationView
            } else {
                questionsView
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.kiwiCream))
        .shadow(color: Color.black.opacity(0.22), radius: 40, x: 0, y: 20)
    }

    private var questionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Comment tu te sens ?")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Text("Un tap par symptôme, ça met tes courbes à jour")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.healthMapMuted)
                }
                Spacer()
                Button { dismissLater() } label: {
                    Text("Plus tard")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Color.healthMapMuted)
                        .padding(8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
                .accessibilityLabel("Plus tard")
            }

            // Une question 1-tap par symptôme déclaré, puis l'énergie du jour.
            // Scrollable + hauteur bornée : reste utilisable même avec 3 symptômes.
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(symptoms, id: \.id) { s in
                        questionBlock(
                            icon: "heart.text.square",
                            title: capitalized(s.nom),
                            better: s.trend.betterLabel,
                            worse: s.trend.worseLabel,
                            selection: choiceBinding(s.id)
                        )
                    }
                    questionBlock(
                        icon: "bolt.fill",
                        title: "Ton énergie, aujourd'hui\u{00A0}?",
                        better: "En forme",
                        worse: "À plat",
                        selection: $energyChoice
                    )
                }
                .padding(.top, 16)
            }
            .frame(maxHeight: 356)
            .scrollBounceBehavior(.basedOnSize)

            Button { validate() } label: {
                Text("C'est noté")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(anyAnswered ? Color.kiwiGreen : Color.healthMapMuted)
                    )
            }
            .buttonStyle(.healthMapPressed)
            .disabled(!anyAnswered)
            .padding(.top, 16)
            .accessibilityHint(anyAnswered ? "Enregistre tes réponses" : "Réponds à au moins un symptôme")
        }
    }

    private var confirmationView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.kiwiGreenSoft).frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Color.kiwiGreen)
            }
            Text("C'est enregistré\u{00A0}!")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.kiwiCharcoal)
            Text("Tes courbes se mettent à jour. À demain\u{00A0}!")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func questionBlock(icon: String, title: String, better: String, worse: String, selection: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.kiwiGreenInk)
                Text(title)
                    .font(.system(size: 14.5, weight: .heavy))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: 8) {
                // Ordre des options = celui de la série (0=mieux, 1=pareil, 2=moins bien)
                optionTile(index: 0, icon: "face.smiling", label: better, selection: selection)
                optionTile(index: 1, icon: "minus", label: "Pareil", selection: selection)
                optionTile(index: 2, icon: "face.dashed", label: worse, selection: selection)
            }
        }
    }

    private func optionTile(index: Int, icon: String, label: String, selection: Binding<Int?>) -> some View {
        let isSelected = selection.wrappedValue == index
        return Button {
            selection.wrappedValue = index
            HapticService.shared.selection()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? Color.kiwiGreenInk : Color.healthMapMuted)
                Text(label)
                    .font(.system(size: 11.5, weight: isSelected ? .heavy : .bold))
                    .foregroundStyle(isSelected ? Color.kiwiGreenInk : Color.healthMapSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.vertical, 13)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.kiwiGreenSoft : Color.healthMapCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.kiwiGreen : Color.kiwiCharcoal.opacity(0.07),
                            lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(label)\(isSelected ? ", sélectionné" : "")")
    }

    private var anyAnswered: Bool { !choices.isEmpty }

    private func validate() {
        guard !choices.isEmpty else { return }
        onFinish(choices, energyChoice)
        if reduceMotion {
            confirmed = true
        } else {
            withAnimation(.easeOut(duration: 0.2)) { confirmed = true }
        }
        // La confirmation verte reste visible un court instant puis se ferme.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            if reduceMotion { isPresented = false }
            else { withAnimation(.easeOut(duration: 0.25)) { isPresented = false } }
        }
    }

    private func dismissLater() {
        guard !confirmed else { return }
        onLater()
        if reduceMotion { isPresented = false }
        else { withAnimation(.easeOut(duration: 0.25)) { isPresented = false } }
    }
}

// MARK: - Maths partagées des courbes (lissage Catmull-Rom → Bézier)
// Interne (pas `private`) : réutilisé par `SuiviValueChart` (autre fichier).
enum SuiviCurveMath {
    static func smoothPath(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard p.count > 1 else { return path }
        path.move(to: p[0])
        for i in 0..<(p.count - 1) {
            let p0 = i > 0 ? p[i - 1] : p[i]
            let p1 = p[i]
            let p2 = p[i + 1]
            let p3 = i + 2 < p.count ? p[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

// MARK: - Store du check-in (persistance locale scopée utilisateur + jour)
//
// Écrit EXACTEMENT dans les mêmes clés que lit `SuiviCheckinHistory` (moteur) :
// « healthmap_suivi_checkin_<uid>_<yyyy-MM-dd> » → dict { "symptome_today": 0|1|2 }.
// Le ressenti « énergie » du jour est stocké sous une 2e clé (« energie_today »)
// dans le MÊME dictionnaire — ignoré par la série symptôme, disponible plus tard.
// Le drapeau « présenté aujourd'hui » (répondu OU reporté) vit sur une clé à part
// pour ne présenter le pop-up qu'une fois par jour.
@MainActor
enum SuiviCheckinStore {
    static let symptomFeelKey = "symptome_today"   // mirror de SuiviCheckinHistory.feelKey
    static let energyFeelKey = "energie_today"

    private static var uid: String {
        AuthService.shared.cachedCurrentUserIdString ?? "anonymous"
    }
    private static func dayString(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
    private static func checkinKey(_ day: String) -> String {
        "healthmap_suivi_checkin_\(uid)_\(day)"
    }
    private static func promptedKey(_ day: String) -> String {
        "healthmap_suivi_prompted_\(uid)_\(day)"
    }

    /// Réponse du jour déjà enregistrée (au moins un symptôme) ?
    static func hasAnsweredToday() -> Bool {
        guard let dict = UserDefaults.standard.dictionary(forKey: checkinKey(dayString())) as? [String: Int]
        else { return false }
        // Nouveau format : au moins une clé `feel_<id>` ; repli ancien format.
        return dict.keys.contains { $0.hasPrefix("feel_") } || dict[symptomFeelKey] != nil
    }

    /// Faut-il présenter le pop-up aujourd'hui ? Non si déjà répondu OU reporté.
    static func shouldPromptToday() -> Bool {
        if hasAnsweredToday() { return false }
        return !UserDefaults.standard.bool(forKey: promptedKey(dayString()))
    }

    /// Enregistre le ressenti de CHAQUE symptôme répondu (`feel_<id>`) + l'énergie
    /// optionnelle dans le dictionnaire scopé jour, et marque le pop-up présenté.
    static func saveToday(symptomFeels: [String: Int], energyFeel: Int?) {
        var dict = (UserDefaults.standard.dictionary(forKey: checkinKey(dayString())) as? [String: Int]) ?? [:]
        for (sid, feel) in symptomFeels {
            dict[SuiviCheckinHistory.feelKeyFor(sid)] = feel
        }
        if let energyFeel { dict[energyFeelKey] = energyFeel }
        UserDefaults.standard.set(dict, forKey: checkinKey(dayString()))
        UserDefaults.standard.set(true, forKey: promptedKey(dayString()))
    }

    /// « Plus tard » : ne réenregistre rien mais évite de re-présenter le pop-up
    /// aujourd'hui (l'utilisateur pourra répondre demain).
    static func snoozeToday() {
        UserDefaults.standard.set(true, forKey: promptedKey(dayString()))
    }
}

#Preview {
    SuiviView()
        .environmentObject(DashboardViewModel())
}
