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

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        titleBlock
                        SuiviStatsRow(stats: stats)
                        symptomSection
                        SuiviNeedsCard(delta: stats.besoinsDuJourDeltaPct,
                                       stepsToday: stepsToday,
                                       tips: weeklyTips)
                        SuiviCoverageCard(coverage: coverage)
                        SuiviPaliersCard(paliers: paliers)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .kiwiTabBarBottomInset()
            .navigationBarTitleDisplayMode(.inline)
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
                        symptomTrend: primaryTrend,
                        reduceMotion: reduceMotion,
                        onFinish: { feel, energy in
                            SuiviCheckinStore.saveToday(symptomFeel: feel, energyFeel: energy)
                            gamification.recordCheckin()
                            checkinHistory = SuiviCheckinHistory.recentFeelings()
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
                // Présenté UNE fois par jour, jamais si déjà répondu / snoozé.
                if SuiviCheckinStore.shouldPromptToday() {
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
                .font(.system(size: 28, weight: .heavy))
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

    // MARK: - 3. Section symptômes (1 carte auto-explicite par symptôme)
    @ViewBuilder
    private var symptomSection: some View {
        let evolutions = SuiviEngineV4.symptomEvolutions(
            symptomes: dashboardVM.analysisV2?.bilan?.symptomes,
            checkinHistory: checkinHistory
        )
        if !evolutions.isEmpty {
            ForEach(evolutions) { evo in
                SuiviSymptomCard(evolution: evo, reduceMotion: reduceMotion)
            }
        } else if dashboardVM.isLoadingAnalysisV2 {
            SuiviLoadingCard(text: "On regarde tes symptômes déclarés…")
        } else {
            SuiviNoSymptomCard()
        }
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

    /// Sens/libellés du 1er symptôme déclaré — pilote la 1re question du pop-up.
    private var primaryTrend: SymptomTrend? {
        guard let nom = dashboardVM.analysisV2?.bilan?.symptomes?.first?.nom,
              !nom.isEmpty else { return nil }
        return SymptomTrend.make(from: nom)
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
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
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

// MARK: - 3. Carte « Évolution du symptôme » (verdict écrit + graphe posé)
/// Verdict d'abord (pastille), phrase d'insight en gros, variation signée, puis
/// mini-graphe à 3 séries avec labels POSÉS directement sur les courbes (« toi »
/// / « sans Kiwio ») et sur les pôles de l'axe. Plus d'onglets ni de légende.
private struct SuiviSymptomCard: View {
    let evolution: SuiviEngineV4.SymptomEvolution
    let reduceMotion: Bool

    @State private var progress: CGFloat = 0

    private var pillColor: Color { evolution.improving ? Color.kiwiGreenInk : Color(hex: "D9820A") }
    private var pillBg: Color { evolution.improving ? Color.kiwiGreenSoft : Color(hex: "FDECD6") }
    private var pillIcon: String {
        guard evolution.verdict != "Stable" else { return "equal" }
        // La flèche suit le SENS RÉEL de la courbe (baisse d'un problème = flèche
        // vers le bas), indépendamment du fait que ce soit une bonne nouvelle.
        return evolution.variationPct < 0 ? "arrow.down.right" : "arrow.up.right"
    }

    private var insightSentence: String {
        // Phrase d'insight ANCRÉE sur le nom du symptôme + le verdict — jamais
        // sur un pôle d'axe (dont le « bon côté » dépend du sens : un problème
        // s'améliore en descendant, un objectif en montant — s'appuyer sur un
        // libellé de pôle inverserait le sens un jour sur deux). Le nom + verdict
        // est toujours juste, quel que soit le sens.
        let nom = evolution.nom.lowercased()
        switch evolution.verdict {
        case "En amélioration": return "Ton suivi de \(nom) s'améliore depuis ton arrivée."
        case "À surveiller":    return "Ton suivi de \(nom) est à surveiller ces jours-ci."
        default:                return "Ton suivi de \(nom) reste stable depuis ton arrivée."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.kiwiGreenInk)
                    Text(capitalizedNom)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.kiwiGreenInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Image(systemName: pillIcon)
                        .font(.system(size: 11, weight: .heavy))
                    Text(evolution.verdict)
                        .font(.system(size: 11.5, weight: .heavy))
                }
                .foregroundStyle(pillColor)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(pillBg))
            }

            // Pas de pourcentage chiffré ici : la base de comparaison ("sans Kiwio")
            // est une trajectoire de référence illustrative, pas une mesure precise
            // du symptôme — un chiffre à deux décimales de confiance ("-38%")
            // laisserait croire à une precision qui n'existe pas (audit du
            // 2026-07-05). Le verdict (pastille) + la phrase d'insight suffisent.
            Text(insightSentence)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            SuiviPosedChart(evolution: evolution, progress: progress)
                .frame(height: 132)
                .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .kiwiCard()
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
            guard n > 1 else { return }

            func px(_ i: Int) -> CGFloat { w * CGFloat(i) / CGFloat(n - 1) }
            func py(_ v: Double) -> CGFloat {
                let t = CGFloat(v) / 100
                return h * (0.12 + (1 - t) * 0.72)
            }
            func points(_ vals: [Double]) -> [CGPoint] {
                vals.enumerated().map { CGPoint(x: px($0.offset), y: py($0.element)) }
            }

            // Grille horizontale discrète
            for g in stride(from: 0.0, through: 1.0, by: 0.25) {
                let y = h * g
                var gp = Path(); gp.move(to: CGPoint(x: 0, y: y)); gp.addLine(to: CGPoint(x: w, y: y))
                ctx.stroke(gp, with: .color(Color.kiwiCharcoal.opacity(0.05)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 5]))
            }

            // « sans Kiwio » — pointillés gris
            let sansPts = points(sans)
            ctx.stroke(SuiviCurveMath.smoothPath(sansPts),
                       with: .color(Color(hex: "C2BDB0")),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round, dash: [2, 5]))

            // « toi » — plein vert + aire, animée par `progress`
            let reelPts = points(reel)
            let visible = max(2, Int(ceil(CGFloat(n) * progress)))
            let drawn = Array(reelPts.prefix(visible))
            let line = SuiviCurveMath.smoothPath(drawn)
            var area = line
            area.addLine(to: CGPoint(x: drawn.last!.x, y: h))
            area.addLine(to: CGPoint(x: drawn.first!.x, y: h))
            area.closeSubpath()
            ctx.fill(area, with: .color(Color.kiwiGreen.opacity(0.10)))
            ctx.stroke(line, with: .color(Color.kiwiGreen),
                       style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))

            if let p = drawn.last {
                let r: CGFloat = 4.5
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(Color.kiwiGreen))
                ctx.stroke(dot, with: .color(.white), style: StrokeStyle(lineWidth: 2.5))
            }

            // Labels POSÉS sur les courbes (fin de tracé)
            if let tip = reelPts.last {
                ctx.draw(
                    Text(evolution.labelToi)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(Color.kiwiGreenInk),
                    at: CGPoint(x: tip.x - 4, y: max(12, tip.y - 14)),
                    anchor: .trailing
                )
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
        .accessibilityLabel("\(evolution.nom) : \(evolution.verdict)")
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
                    .font(.system(size: 27, weight: .heavy, design: .monospaced))
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
            return "Tu as bougé plus que d'habitude · \(formatSteps(s)) pas via Santé"
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

// MARK: - 5. Carte « Ta progression par nutriment » (socle bilan + gain depuis le départ)
private struct SuiviCoverageCard: View {
    let coverage: [SuiviEngineV4.NutrientCoverage7d]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Moyenne arrondie des gains (aujourd'hui - départ) sur les lignes où le
    /// gain est positif. 0 s'il n'y a aucun progrès à afficher.
    private var averageGain: Int {
        let gains = coverage.map { n -> Int in
            let base = max(0, min(100, n.baselinePct))
            let cur = max(base, max(0, min(100, n.pct)))
            return cur - base
        }
        let positifs = gains.filter { $0 > 0 }
        guard !positifs.isEmpty else { return 0 }
        return Int((Double(positifs.reduce(0, +)) / Double(positifs.count)).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "D9820A"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ta progression par nutriment")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "D9820A"))
                    if averageGain > 0 {
                        Text("Depuis ton bilan · +\(averageGain) pts en moyenne")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 2)

            if coverage.isEmpty {
                emptyState
            } else {
                ForEach(Array(coverage.enumerated()), id: \.element.id) { idx, n in
                    row(n)
                        .overlay(alignment: .top) {
                            if idx > 0 {
                                Rectangle()
                                    .fill(Color.kiwiCharcoal.opacity(0.06))
                                    .frame(height: 1)
                            }
                        }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .kiwiCard()
    }

    private func row(_ n: SuiviEngineV4.NutrientCoverage7d) -> some View {
        let base = max(0, min(100, n.baselinePct))
        let cur = max(base, max(0, min(100, n.pct)))
        let gain = cur - base
        let color = Color.scoreColor(for: cur)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(n.nom)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Spacer()
                Text("\(cur)%")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(color)
            }
            // Barre continue : track + socle (départ) + gain dégradé + repère.
            GeometryReader { g in
                let width = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.13))
                        .frame(height: 12)
                    // Socle = score de départ.
                    Capsule().fill(color)
                        .frame(width: max(0, width * CGFloat(base) / 100), height: 12)
                    // Gain = progrès depuis le départ, teinte claire dégradée.
                    if gain > 0 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.55), color.opacity(0.30)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, width * CGFloat(cur - base) / 100), height: 12)
                            .offset(x: width * CGFloat(base) / 100)
                        // Repère vertical à la position « départ ».
                        Capsule()
                            .fill(color.opacity(0.85))
                            .frame(width: 2, height: 18)
                            .offset(x: width * CGFloat(base) / 100)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: cur)
            }
            .frame(height: 18)
            .padding(.top, 11)

            // Ligne micro « départ / aujourd'hui (+gain) ».
            HStack(spacing: 0) {
                Text("Départ \(base)% · aujourd'hui \(cur)%")
                    .foregroundStyle(Color.healthMapMuted)
                if gain > 0 {
                    Text(" · +\(gain) pts")
                        .foregroundStyle(Color.kiwiGreenInk)
                }
            }
            .font(.system(size: 12))
            .padding(.top, 7)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.system(size: 17))
                .foregroundStyle(Color.kiwiGreen)
            Text("Scanne tes repas : ta barre part de ton bilan et grimpe avec tes progrès.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 18)
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
                    Text("en suivant ton plan — tu es sur la bonne trajectoire")
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
                    + Text("\(paliers.joursRestants) j").font(.system(size: 13.5, weight: .heavy, design: .monospaced)).foregroundColor(Color.kiwiGreenInk))
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
    /// Sens/libellés du 1er symptôme (nil = pas de symptôme → question générique).
    let symptomTrend: SymptomTrend?
    let reduceMotion: Bool
    let onFinish: (_ symptomFeel: Int, _ energyFeel: Int) -> Void
    let onLater: () -> Void
    @Binding var isPresented: Bool

    @State private var symptomChoice: Int?
    @State private var energyChoice: Int?
    @State private var confirmed = false

    /// Libellés de la 1re question (dépend du symptôme, sinon « en forme »).
    private var symptomQuestion: String {
        symptomTrend?.checkinQuestion ?? "En forme cette semaine\u{00A0}?"
    }
    private var symptomBetter: String { symptomTrend?.betterLabel ?? "Mieux" }
    private var symptomWorse: String { symptomTrend?.worseLabel ?? "Moins bien" }

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
                    Text("2 questions rapides")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Text("10 secondes — ça met tes courbes à jour")
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

            // Question 1 — symptôme
            questionBlock(
                icon: "hand.raised.fingers.spread",
                title: symptomQuestion,
                better: symptomBetter,
                worse: symptomWorse,
                selection: $symptomChoice
            )
            .padding(.top, 16)

            // Question 2 — énergie (toujours « plus haut = mieux »)
            questionBlock(
                icon: "bolt.fill",
                title: "Ton énergie, aujourd'hui\u{00A0}?",
                better: "En forme",
                worse: "À plat",
                selection: $energyChoice
            )
            .padding(.top, 14)

            Button { validate() } label: {
                Text("C'est noté")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(bothAnswered ? Color.kiwiGreen : Color.healthMapMuted)
                    )
            }
            .buttonStyle(.healthMapPressed)
            .disabled(!bothAnswered)
            .padding(.top, 18)
            .accessibilityHint(bothAnswered ? "Enregistre tes réponses" : "Réponds aux deux questions d'abord")
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

    private var bothAnswered: Bool { symptomChoice != nil && energyChoice != nil }

    private func validate() {
        guard let symptom = symptomChoice, let energy = energyChoice else { return }
        onFinish(symptom, energy)
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
private enum SuiviCurveMath {
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

    /// Réponse du jour déjà enregistrée (courbe « toi » nourrie) ?
    static func hasAnsweredToday() -> Bool {
        let dict = UserDefaults.standard.dictionary(forKey: checkinKey(dayString())) as? [String: Int]
        return dict?[symptomFeelKey] != nil
    }

    /// Faut-il présenter le pop-up aujourd'hui ? Non si déjà répondu OU reporté.
    static func shouldPromptToday() -> Bool {
        if hasAnsweredToday() { return false }
        return !UserDefaults.standard.bool(forKey: promptedKey(dayString()))
    }

    /// Enregistre les 2 ressentis du jour dans le dictionnaire scopé jour, et
    /// marque le pop-up comme présenté.
    static func saveToday(symptomFeel: Int, energyFeel: Int) {
        var dict = (UserDefaults.standard.dictionary(forKey: checkinKey(dayString())) as? [String: Int]) ?? [:]
        dict[symptomFeelKey] = symptomFeel
        dict[energyFeelKey] = energyFeel
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
