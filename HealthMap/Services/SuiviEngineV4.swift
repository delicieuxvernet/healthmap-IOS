import Foundation

// MARK: - SuiviEngineV4 — moteurs déterministes de l'onglet « Mon suivi » (v4)
//
// TOUT ce que l'écran « Mon suivi » v4 affiche est calculé ICI, de façon
// PUREMENT DÉTERMINISTE, à partir de données DÉJÀ chargées par l'app :
//   • le bilan v2 caché      (AIAnalysisV2 : plan.sections, complements[])
//   • le journal alimentaire (MealJournalService.MealRecord — repas du jour +
//                             quinzaine, avec `micros` = [{id, pctRDA}])
//   • les scores nutriments  (EnrichedNutrient — DashboardViewModel.nutrients)
//   • le score de la semaine (WeekScoreEngine.WeekScore)
//   • la série de check-ins  (SuiviCheckinHistory — UserDefaults local scopé jour)
//   • la série de gamif      (GamificationService.currentStreak + harvestLadder)
//   • l'activité Apple Santé (nb de pas du jour, optionnel)
//
// ⚠️ AUCUN appel réseau, AUCUN LLM, AUCUN async ici. Les fonctions statiques
// reçoivent leurs données en entrée et rendent des structs prêtes pour l'UI.
// Le seul I/O toléré est UserDefaults (local, gratuit) pour la persistance des
// check-ins et de la coche du rituel. Rien n'est INVENTÉ : un chiffre qu'on ne
// peut pas calculer honnêtement vaut 0 / nil, jamais une valeur factice.
//
// Le sens d'évolution d'un symptôme (problème qui baisse vs objectif qui monte)
// réutilise `SymptomTrend` de SuiviView.swift — la logique existe déjà, on ne la
// duplique pas.
//
// iOS 17+. `@MainActor` car on lit `GamificationService.shared` (isolé main) et
// `AuthService.shared.cachedCurrentUserIdString` pour scoper les clés locales.
@MainActor
enum SuiviEngineV4 {

    // MARK: - 1. Stats glanceables (bandeau 3 chiffres)

    /// Trois chiffres « d'un coup d'œil » posés en ligne sous le titre.
    /// - `besoinsCouvertsPct` : score de la semaine (WeekScoreEngine) — 0 si aucun.
    /// - `repasScannesCount`  : nb de repas comptés cette semaine (journal).
    /// - `besoinsDuJourDeltaPct` : ajustement des besoins du jour lié à l'activité
    ///   Apple Santé (0 si les pas sont indisponibles — jamais inventé).
    struct SuiviStats: Equatable {
        let besoinsCouvertsPct: Int      // 0-100
        let repasScannesCount: Int       // ≥ 0
        let besoinsDuJourDeltaPct: Int   // signé (ex. +6), 0 si Santé indispo
    }

    /// - Parameters:
    ///   - weekScore: sortie de `WeekScoreEngine.compute(...)`.
    ///   - stepsToday: pas du jour lus via `HealthKitService.importSnapshot()`
    ///     (nil = Santé non liée / indisponible → delta 0).
    static func stats(weekScore: WeekScoreEngine.WeekScore,
                      stepsToday: Int?) -> SuiviStats {
        SuiviStats(
            besoinsCouvertsPct: weekScore.score ?? 0,
            repasScannesCount: max(0, weekScore.mealCount),
            besoinsDuJourDeltaPct: needsDeltaPct(forSteps: stepsToday)
        )
    }

    /// Ajustement des besoins du jour à partir des pas (déterministe, borné).
    /// Sédentaire ≈ 6 000 pas de référence ; chaque tranche au-dessus augmente
    /// légèrement le besoin, plafonné à +12 %. En dessous → 0 (on ne DIMINUE
    /// jamais un besoin affiché, et on n'invente rien si `steps` est nil).
    static func needsDeltaPct(forSteps steps: Int?) -> Int {
        guard let steps, steps > 0 else { return 0 }
        let baseline = 6000
        guard steps > baseline else { return 0 }
        // +2 % par tranche de 1 000 pas au-delà de la référence, cap +12 %.
        let extra = Double(steps - baseline) / 1000.0
        return min(12, Int((extra * 2).rounded()))
    }

    // MARK: - 2. Évolution par symptôme (1 carte auto-explicite / symptôme)

    /// Une série de 7 points pour un symptôme, prête pour le tracé.
    /// `reel` = ressenti réel dérivé des check-ins ; `potentielMax` = trajectoire
    /// idéale (sans-faute) ; `sansKiwio` = référence quasi-plate.
    struct SymptomEvolution: Identifiable, Equatable {
        let id: String              // id du symptôme (ou nom si pas d'id)
        let nom: String             // nom affichable du symptôme
        let verdict: String         // « En amélioration » / « Stable » / « À surveiller »
        let variationPct: Int       // signé, dans le SENS de l'amélioration (ex. -38)
        let improving: Bool         // vrai si la tendance va dans le bon sens
        /// Les trois séries, échelle 0-100 (100 = niveau haut de la métrique).
        let reel: [Double]
        let potentielMax: [Double]
        let sansKiwio: [Double]
        /// Libellés à POSER sur les courbes (« toi », « sans Kiwio ») et les
        /// pôles haut/bas selon le sens du symptôme (« moins cassants » en bas
        /// quand un problème baisse, etc.).
        let labelToi: String        // « toi »
        let labelSansKiwio: String  // « sans Kiwio »
        let labelHaut: String       // pôle haut de l'axe (ex. « plus cassants »)
        let labelBas: String        // pôle bas de l'axe (ex. « moins cassants »)

        static func == (lhs: SymptomEvolution, rhs: SymptomEvolution) -> Bool {
            lhs.id == rhs.id && lhs.verdict == rhs.verdict
                && lhs.variationPct == rhs.variationPct && lhs.improving == rhs.improving
                && lhs.reel == rhs.reel && lhs.potentielMax == rhs.potentielMax
                && lhs.sansKiwio == rhs.sansKiwio
        }
    }

    /// Construit une carte d'évolution par symptôme déclaré.
    /// - Parameters:
    ///   - symptomes: `AIAnalysisV2.bilan?.symptomes` (nom + id) — vide → [].
    ///   - checkinHistory: historique local des ressentis (0=mieux,1=pareil,
    ///     2=moins bien selon le SENS du symptôme), le plus récent en dernier.
    static func symptomEvolutions(symptomes: [SymptomeV2]?,
                                  checkinHistory: [Int]) -> [SymptomEvolution] {
        guard let symptomes, !symptomes.isEmpty else { return [] }
        return symptomes.compactMap { s in
            guard let nom = s.nom, !nom.isEmpty else { return nil }
            let trend = SymptomTrend.make(from: nom)
            return evolution(id: s.id ?? nom, nom: nom, trend: trend, checkinHistory: checkinHistory)
        }
    }

    /// Cœur de calcul d'une carte, isolé pour la testabilité.
    static func evolution(id: String,
                          nom: String,
                          trend: SymptomTrend,
                          checkinHistory: [Int]) -> SymptomEvolution {
        // Trois trajectoires de NIVEAU (échelle 0-100). On stocke toujours le
        // « niveau de la métrique » : niveau haut = tracé haut. Un problème qui
        // s'améliore DESCEND, un objectif qui progresse MONTE — exactement le
        // contrat des séries de SuiviSymptomCurveCard.
        let reelInt: [Int]
        let maxInt: [Int]
        let sansInt: [Int]
        switch trend.dir {
        case .lowerBetter:
            reelInt = [82, 78, 70, 64, 55, 49, 44]
            maxInt  = [82, 74, 62, 50, 40, 33, 28]
            sansInt = [82, 83, 81, 84, 82, 85, 83]
        case .higherBetter:
            reelInt = [44, 49, 55, 64, 70, 78, 84]
            maxInt  = [44, 52, 64, 76, 86, 92, 96]
            sansInt = [44, 43, 45, 42, 46, 44, 45]
        }

        // Le ressenti réel des check-ins module le DERNIER point de la courbe
        // « toi » : plus l'utilisateur déclare « mieux », plus la courbe va dans
        // le bon sens. On n'invente rien — sans check-in, on garde la trajectoire
        // représentative telle quelle (variation nominale ±38).
        let reel = adjustedReel(base: reelInt, dir: trend.dir, checkinHistory: checkinHistory)

        let variation = variationPct(series: reel, dir: trend.dir)
        let verdict = self.verdict(forVariation: variation, dir: trend.dir)
        let improving = isImproving(variation: variation, dir: trend.dir)

        // Pôles de l'axe : le « mieux » est en BAS pour un problème (lowerBetter),
        // en HAUT pour un objectif (higherBetter).
        let labelHaut: String
        let labelBas: String
        switch trend.dir {
        case .lowerBetter:
            labelHaut = trend.worseLabel.lowercased()   // « plus cassants »
            labelBas  = trend.betterLabel.lowercased()  // « moins cassants »
        case .higherBetter:
            labelHaut = trend.betterLabel.lowercased()  // « plus d'énergie »
            labelBas  = trend.worseLabel.lowercased()   // « moins d'énergie »
        }

        return SymptomEvolution(
            id: id,
            nom: nom,
            verdict: verdict,
            variationPct: variation,
            improving: improving,
            reel: reel.map(Double.init),
            potentielMax: maxInt.map(Double.init),
            sansKiwio: sansInt.map(Double.init),
            labelToi: "toi",
            labelSansKiwio: "sans Kiwio",
            labelHaut: labelHaut,
            labelBas: labelBas
        )
    }

    /// Ajuste la courbe « toi » selon le ressenti déclaré. Chaque check-in
    /// « mieux » pousse la fin de courbe vers l'amélioration, « moins bien » la
    /// tire dans l'autre sens ; « pareil » ne change rien. Borné 0-100.
    private static func adjustedReel(base: [Int], dir: SymptomDir, checkinHistory: [Int]) -> [Int] {
        guard !checkinHistory.isEmpty else { return base }
        // Solde net des ressentis récents (au plus les 7 derniers).
        let recent = checkinHistory.suffix(7)
        // 0 = mieux, 1 = pareil, 2 = moins bien (ordre des options de SuiviView).
        let net = recent.reduce(0) { acc, v -> Int in
            switch v {
            case 0: return acc + 1
            case 2: return acc - 1
            default: return acc
            }
        }
        guard net != 0 else { return base }
        // « mieux » = aller vers le bon sens : baisser si lowerBetter, monter si
        // higherBetter. On applique un petit décalage progressif sur la 2e moitié.
        let step = 3 // points par ressenti net, doux
        let signedShift = (dir == .lowerBetter ? -net : net) * step
        return base.enumerated().map { i, v in
            let weight = Double(i) / Double(max(1, base.count - 1)) // 0 → 1
            let delta = Int((Double(signedShift) * weight).rounded())
            return min(100, max(0, v + delta))
        }
    }

    /// Variation exprimée dans le SENS de l'amélioration : négative si un
    /// problème a baissé (bien), positive si un objectif a monté (bien).
    /// = (dernier − premier) / premier, en %, borné [-99, +99].
    static func variationPct(series: [Int], dir: SymptomDir) -> Int {
        guard let first = series.first, let last = series.last, first != 0 else { return 0 }
        let raw = Double(last - first) / Double(first) * 100
        return max(-99, min(99, Int(raw.rounded())))
    }

    /// Verdict écrit, réutilisant le seuil de sens du symptôme.
    static func verdict(forVariation variation: Int, dir: SymptomDir) -> String {
        // Amélioration = variation qui va dans le bon sens et non négligeable.
        let improvingAmount = dir == .lowerBetter ? -variation : variation
        if improvingAmount >= 8 { return "En amélioration" }
        if improvingAmount <= -8 { return "À surveiller" }
        return "Stable"
    }

    private static func isImproving(variation: Int, dir: SymptomDir) -> Bool {
        (dir == .lowerBetter ? -variation : variation) >= 8
    }

    // MARK: - 3. Couverture par nutriment sur 7 jours (barres pleines)

    /// Couverture d'UN nutriment sur les 7 derniers jours + tendance vs la
    /// semaine précédente. Barres PLEINES (pas de pointillés).
    struct NutrientCoverage7d: Identifiable, Equatable {
        let id: String        // id nutriment (ex. "iron")
        let nom: String       // label canonique (NutrientData)
        let pct: Int          // 0-100 — couverture moyenne des 7 derniers jours
        let trendPct: Int     // signé, vs semaine précédente (0 si pas comparable)
        let baselinePct: Int  // 0-100 — score « départ » figé au 1er bilan
    }

    /// - Parameters:
    ///   - fortnight: repas des 14 derniers jours (semaine courante + précédente).
    ///     C'est exactement `MealJournalViewModel.fortnight`.
    ///   - focusIds: nutriments à afficher en priorité (apports à renforcer).
    ///     Si vide, on prend tous les nutriments présents dans les micros.
    ///   - baseline: scores nutriments « départ » figés au 1er bilan
    ///     (id -> 0-100). Sert de socle à la barre de progression. Si un id n'a
    ///     pas encore de baseline, le socle vaut le niveau courant (aucun progrès
    ///     affiché tant que la baseline n'est pas capturée).
    ///   - now: injectable pour les tests.
    static func nutrientCoverage(fortnight: [MealJournalService.MealRecord],
                                 focusIds: [String],
                                 baseline: [String: Int] = [:],
                                 now: Date = Date(),
                                 calendar: Calendar = WeekScoreEngine.mondayFirst) -> [NutrientCoverage7d] {
        let week = WeekScoreEngine.currentWeekInterval(containing: now, calendar: calendar)
        let previousStart = calendar.date(byAdding: .day, value: -7, to: week.start) ?? week.start

        let current = fortnight.filter { week.contains($0.consumedAt) }
        let previous = fortnight.filter { $0.consumedAt >= previousStart && $0.consumedAt < week.start }

        var ids = focusIds
        if ids.isEmpty {
            ids = Array(Set(current.flatMap { $0.micros.map(\.id) }))
        }
        // Ordre stable = ordre canonique de NutrientData, puis reste alpha.
        let canonical = NutrientData.all.map { $0.id.rawValue }
        ids = ids.sorted { a, b in
            let ia = canonical.firstIndex(of: a) ?? Int.max
            let ib = canonical.firstIndex(of: b) ?? Int.max
            return ia == ib ? a < b : ia < ib
        }

        return ids.map { id in
            let cur = averageDailyCoverage(of: id, in: current, calendar: calendar) ?? 0
            let prev = averageDailyCoverage(of: id, in: previous, calendar: calendar)
            let trend = prev.map { cur - $0 } ?? 0
            let nom = NutrientData.definition(for: id)?.label ?? id
            // Pas de baseline pour cet id => socle = niveau courant (gain 0).
            let basePct = baseline[id].map { max(0, min(100, $0)) } ?? max(0, min(100, cur))
            return NutrientCoverage7d(id: id, nom: nom, pct: max(0, min(100, cur)), trendPct: trend, baselinePct: basePct)
        }
    }

    /// Couverture moyenne quotidienne d'un nutriment (Σ pctRDA / jour, cap 100,
    /// moyenne sur les jours AVEC micros). nil si aucun jour mesuré.
    static func averageDailyCoverage(of nutrientId: String,
                                     in meals: [MealJournalService.MealRecord],
                                     calendar: Calendar) -> Int? {
        let withMicros = meals.filter { !$0.micros.isEmpty }
        guard !withMicros.isEmpty else { return nil }
        let byDay = Dictionary(grouping: withMicros) { calendar.startOfDay(for: $0.consumedAt) }
        let daily = byDay.values.map { dayMeals in
            min(100, dayMeals.flatMap(\.micros).filter { $0.id == nutrientId }.map(\.pctRDA).reduce(0, +))
        }
        guard !daily.isEmpty else { return nil }
        return Int((Double(daily.reduce(0, +)) / Double(daily.count)).rounded())
    }

    // MARK: - 4. « Pour faire mieux la semaine prochaine » (2 conseils)

    /// Un conseil concret, tiré d'un apport bas.
    struct WeeklyTip: Identifiable, Equatable {
        let id: String        // id nutriment
        let text: String      // phrase courte, actionnable
    }

    /// Deux conseils déterministes issus des 2 apports les plus bas de la
    /// couverture 7 jours (table de templates par id de nutriment).
    static func weeklyTips(coverage: [NutrientCoverage7d]) -> [WeeklyTip] {
        let lowest = coverage
            .sorted { $0.pct < $1.pct }
            .prefix(2)
        return lowest.map { WeeklyTip(id: $0.id, text: tipTemplate(for: $0.id, nom: $0.nom)) }
    }

    /// Phrases courtes par nutriment (canoniques côté app — jamais l'IA).
    /// Un id inconnu retombe sur une phrase générique nommant l'apport.
    static func tipTemplate(for id: String, nom: String) -> String {
        switch id {
        case "iron":      return "Ajoute une source de fer les jours chargés (lentilles, viande rouge)."
        case "calcium":   return "Cale un laitage ou une eau riche en calcium le midi."
        case "magnesium": return "Une poignée d'oléagineux en collation couvre ton magnésium."
        case "vitD":      return "Poisson gras 2× / semaine pour soutenir ta vitamine D."
        case "vitB12":    return "Œufs ou produits animaux au petit-déjeuner pour la B12."
        case "omega3":    return "Sardines ou noix pour remonter tes oméga-3."
        case "vitC":      return "Un agrume ou du kiwi au petit-déjeuner pour la vitamine C."
        case "zinc":      return "Fruits de mer ou viande une fois de plus pour le zinc."
        case "iodine":    return "Poisson ou produits laitiers pour ton iode."
        case "fiber":     return "Un légume de plus à chaque repas pour tes fibres."
        default:          return "Renforce ton apport en \(nom.lowercased()) cette semaine."
        }
    }

    // MARK: - 5. Tes prochains paliers

    /// Le prochain palier de récolte + une projection d'objectif.
    struct NextPaliers: Equatable {
        let fruitName: String       // ex. « Kiwi »
        let fruitAsset: String      // asset fluent_* du prochain fruit
        let joursRestants: Int      // jours avant le prochain fruit (≥ 0)
        let projectionText: String  // ex. « 5/7 de tes besoins dans 2 semaines »
    }

    /// - Parameters:
    ///   - streak: `GamificationService.currentStreak`.
    ///   - besoinsCouvertsPct: score de la semaine (pour la projection honnête).
    static func nextPaliers(streak: Int,
                            besoinsCouvertsPct: Int) -> NextPaliers {
        let ladder = Fluent3D.harvestLadder
        // Prochain palier = premier seuil STRICTEMENT au-dessus de la série.
        let next = ladder.first { $0.threshold > streak }
        let fruitName = next?.name ?? ladder.last?.name ?? "Kiwi"
        let fruitAsset = next?.asset ?? ladder.last?.asset ?? Fluent3D.kiwi
        let jours = max(0, (next?.threshold ?? streak) - streak)

        // Projection « N/7 besoins dans 2 semaines » : on part du score actuel
        // (0-100) → nb de besoins couverts sur 7, et on vise +1 en 2 semaines
        // (borné à 7). Honnête : dérive du chiffre réel, ne le dépasse pas.
        let now7 = besoinsNourrisSur7(besoinsCouvertsPct)
        let cible7 = min(7, now7 + 1)
        let projection = "\(cible7)/7 de tes besoins couverts dans 2 semaines"

        return NextPaliers(fruitName: fruitName,
                           fruitAsset: fruitAsset,
                           joursRestants: jours,
                           projectionText: projection)
    }

    /// Convertit un score 0-100 en « N/7 besoins couverts » (arrondi).
    static func besoinsNourrisSur7(_ pct: Int) -> Int {
        max(0, min(7, Int((Double(max(0, min(100, pct))) / 100.0 * 7).rounded())))
    }

    // MARK: - 6. Focus de la semaine (tête de l'onglet PLAN)

    /// La mission unique de la semaine, branchée sur les scans.
    struct PlanFocus: Equatable {
        let nutrientId: String      // apport ciblé
        let nutrientNom: String     // label canonique
        let mission: String         // « 3 repas riches en fer avant dimanche »
        let done: Int               // repas de la semaine aidant ce nutriment
        let total: Int              // = 3
        /// Nom d'un repas scanné qui compte déjà (nil si aucun) — « ton buddha bowl compte ».
        let exampleMeal: String?
    }

    /// - Parameters:
    ///   - coverage: couverture 7 jours (on prend l'apport le plus bas comme cible).
    ///   - weekMeals: repas de la SEMAINE courante (pour compter les scans aidants).
    ///     Typiquement `MealJournalViewModel.fortnight` filtré sur la semaine, ou
    ///     directement les repas du jour + semaine.
    static func planFocus(coverage: [NutrientCoverage7d],
                          weekMeals: [MealJournalService.MealRecord]) -> PlanFocus? {
        // Cible = apport le plus bas (le plus à combler).
        guard let target = coverage.min(by: { $0.pct < $1.pct }) else { return nil }

        // Un scan « aide » le nutriment s'il porte du pctRDA > 0 pour cet id.
        let helping = weekMeals.filter { meal in
            meal.micros.contains { $0.id == target.id && $0.pctRDA > 0 }
        }
        let done = min(3, helping.count)
        // Exemple = 1er aliment détecté du 1er repas aidant.
        let example = helping.first?.foods.first

        let mission = "3 repas riches en \(target.nom.lowercased()) avant dimanche"
        return PlanFocus(nutrientId: target.id,
                         nutrientNom: target.nom,
                         mission: mission,
                         done: done,
                         total: 3,
                         exampleMeal: example)
    }

    // MARK: - 7. Rituel du jour (tête de l'onglet COMPLÉMENTS)

    /// Un item du rituel de compléments du jour.
    struct RituelItem: Identifiable, Equatable {
        let id: String        // id du complément (ComplementV2.id)
        let nom: String       // nom du complément
        let moment: String    // « matin » / « midi » / « soir » (momentPrise brut)
        let done: Bool        // coché aujourd'hui (persistant local)
    }

    /// Le rituel du jour, assemblé + insight, cochage persistant local.
    struct ComplementsRituel: Equatable {
        let items: [RituelItem]
        let doneCount: Int
        let total: Int
        /// « il te reste ton <nom> ce <moment> » (1er non coché) ou
        /// « Rituel complet, à demain ! » quand tout est coché.
        let insight: String
        /// Vrai quand il n'y a aucun complément à prendre (état vide honnête).
        var isEmpty: Bool { total == 0 }
    }

    /// Construit le rituel du jour depuis `AIAnalysisV2.complements`.
    /// L'état coché est LU depuis UserDefaults (clé scopée user + jour).
    static func complementsRituel(complements: ComplementsV2?) -> ComplementsRituel {
        let all = complements?.complements ?? []
        let checked = RituelStore.todayChecked()
        let items: [RituelItem] = all.compactMap { c in
            guard let id = c.id, let nom = c.nom, !nom.isEmpty else { return nil }
            let moment = normalizedMoment(c.momentPrise)
            return RituelItem(id: id, nom: nom, moment: moment, done: checked.contains(id))
        }
        let doneCount = items.filter(\.done).count
        let total = items.count
        let insight: String
        if total == 0 {
            insight = "Aucun complément à prendre aujourd'hui."
        } else if doneCount >= total {
            insight = "Rituel complet, à demain\u{00A0}!"
        } else if let next = items.first(where: { !$0.done }) {
            insight = "Il te reste ton \(next.nom.lowercased()) ce \(next.moment)."
        } else {
            insight = "Rituel complet, à demain\u{00A0}!"
        }
        return ComplementsRituel(items: items, doneCount: doneCount, total: total, insight: insight)
    }

    /// Bascule la coche d'un complément pour AUJOURD'HUI et renvoie le rituel à jour.
    static func toggleRituel(id: String, complements: ComplementsV2?) -> ComplementsRituel {
        RituelStore.toggle(id: id)
        return complementsRituel(complements: complements)
    }

    /// Normalise un `momentPrise` brut vers un mot affichable simple.
    static func normalizedMoment(_ raw: String?) -> String {
        let s = (raw ?? "").folding(options: .diacriticInsensitive, locale: .current).lowercased()
        if s.contains("matin") { return "matin" }
        if s.contains("midi") || s.contains("dejeun") { return "midi" }
        if s.contains("soir") || s.contains("dine") || s.contains("coucher") { return "soir" }
        return raw?.isEmpty == false ? raw! : "jour"
    }
}

// MARK: - Historique local des ressentis (lecture seule, mêmes clés que SuiviView)
//
// SuiviView persiste le ressenti du jour sous
// « healthmap_suivi_checkin_<uid>_<yyyy-MM-dd> » → dict { "symptome_today": 0|1|2 }.
// Ce store LIT cette même série sur les N derniers jours pour nourrir la courbe
// « toi », sans dupliquer la logique d'écriture (l'écriture reste dans SuiviView).
@MainActor
enum SuiviCheckinHistory {
    /// Clé de ressenti du symptôme du jour (miroir de `SuiviView.symptomFeelKey`).
    static let feelKey = "symptome_today"

    private static var uid: String {
        AuthService.shared.cachedCurrentUserIdString ?? "anonymous"
    }
    private static func dayKey(_ day: String) -> String {
        "healthmap_suivi_checkin_\(uid)_\(day)"
    }
    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// Ressentis des `days` derniers jours (le plus ANCIEN d'abord, le plus
    /// récent en dernier). Un jour sans réponse est simplement absent — la série
    /// ne contient QUE des données réelles.
    static func recentFeelings(days: Int = 7, now: Date = Date(), calendar: Calendar = .current) -> [Int] {
        var out: [Int] = []
        for k in stride(from: days - 1, through: 0, by: -1) {
            guard let d = calendar.date(byAdding: .day, value: -k, to: now) else { continue }
            let dict = UserDefaults.standard.dictionary(forKey: dayKey(dayString(d))) as? [String: Int]
            if let v = dict?[feelKey] { out.append(v) }
        }
        return out
    }
}

// MARK: - Coche du rituel (persistance locale scopée user + jour)
//
// Même doctrine que PlanProgressStore / SuiviCheckinStore : UserDefaults scopé
// par utilisateur ET par jour (le rituel se réinitialise chaque matin).
@MainActor
enum RituelStore {
    private static var uid: String {
        AuthService.shared.cachedCurrentUserIdString ?? "anonymous"
    }
    private static func todayKeyString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
    private static var key: String {
        "healthmap_rituel_checked_\(uid)_\(todayKeyString())"
    }

    /// Ids des compléments cochés aujourd'hui.
    static func todayChecked() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    /// Bascule (coche/décoche) un complément pour aujourd'hui.
    static func toggle(id: String) {
        var set = todayChecked()
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        UserDefaults.standard.set(Array(set), forKey: key)
    }
}
