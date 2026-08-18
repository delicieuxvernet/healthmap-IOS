import Foundation

/// Journal alimentaire du jour : charge les repas, calcule les totaux,
/// gère l'ajout manuel et la suppression. Lecture/écriture via
/// `MealJournalService` (table `meal_scans`).
@MainActor
final class MealJournalViewModel: ObservableObject {
    @Published var meals: [MealJournalService.MealRecord] = []
    /// 14 derniers jours (semaine courante + précédente) — nourrit le score
    /// de la semaine du Bilan (WeekScoreEngine). `meals` en reste le sous-
    /// ensemble « aujourd'hui », dérivé de la même requête.
    @Published var fortnight: [MealJournalService.MealRecord] = [] { didSet { invaliderJour() } }
    @Published var isLoading = false

    /// Jour affiché par la page d'accueil Scan (jauge kcal / apports / macros /
    /// récents / dernier plat). Toujours borné à la fenêtre `fortnight` réellement
    /// chargée (≈ 2 semaines … aujourd'hui). Le SCAN, lui, agit toujours sur
    /// aujourd'hui — cette navigation ne concerne QUE l'affichage du journal.
    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date()) { didSet { invaliderJour() } }

    /// Repas ANTÉRIEURS à la quinzaine, chargés à la demande quand on remonte
    /// le calendrier. Volontairement séparés de `fortnight` : ce dernier nourrit
    /// le score de la semaine, qui n'a rien à voir avec la profondeur d'archive
    /// que l'utilisateur consulte.
    @Published private(set) var archives: [MealJournalService.MealRecord] = [] { didSet { invaliderJour() } }
    /// Plus ancien jour effectivement chargé (quinzaine, puis archives).
    @Published private(set) var jourLePlusAncienCharge: Date = Calendar.current.startOfDay(for: Date())
    @Published private(set) var chargeLArchive = false

    private let service = MealJournalService.shared

    // MARK: - Mémoïsation du jour affiché
    //
    // `dayMeals` était une propriété calculée : elle reconcaténait
    // `fortnight + archives`, refaisait un `Calendar.current.isDate(...)` par
    // enregistrement puis un tri, À CHAQUE ACCÈS. Le corps de l'accueil Scan
    // en déclenche une vingtaine par passe (kcal, 4 macros, ids de micros,
    // 6 pourcentages…), et ce corps est réévalué 20 à 40 fois par seconde
    // pendant une dictée. On calcule donc une seule fois par état, et le cache
    // tombe dès que `fortnight`, `archives` ou `selectedDay` bougent.
    private let cal = Calendar.autoupdatingCurrent
    private var cacheDayMeals: [MealJournalService.MealRecord]?
    private var cacheDayTotaux: (kcal: Int, prot: Double, carb: Double, fat: Double, fiber: Double)?
    private var cacheDayNutrientIds: [String]?
    private var cacheDayMicroPct: [String: Int] = [:]

    private func invaliderJour() {
        cacheDayMeals = nil
        cacheDayTotaux = nil
        cacheDayNutrientIds = nil
        cacheDayMicroPct = [:]
    }

    // MARK: - Chargement

    /// Requête en vol, PARTAGÉE par tous les journaux montés en même temps.
    /// Le Bilan, le Suivi et le Scan détiennent chacun leur ViewModel et
    /// appellent `load()` à leur montage : les cinq onglets étant montés dès le
    /// lancement, le démarrage à froid lançait trois fois la MÊME requête de
    /// quinzaine, sur le chemin critique. Idem après chaque scan
    /// (`.healthmapMealScanned` est écouté par les trois).
    /// Isolé @MainActor comme la classe : pas de course possible.
    private static var volEnCours: (cle: String, tache: Task<[MealJournalService.MealRecord], Error>)?

    func load() async {
        guard let userId = AuthService.shared.cachedCurrentUserIdString else {
            meals = []
            fortnight = []
            return
        }
        isLoading = true
        do {
            let cal = Calendar.current
            let week = WeekScoreEngine.currentWeekInterval(containing: Date())
            // Fenêtre = union de DEUX besoins : la semaine précédente (score
            // hebdo du Bilan) ET 14 jours glissants pleins (axe + seuil
            // « 3 jours d'affilée » du Suivi). Avant : `week.start − 7` seul —
            // en début de semaine l'axe de 14 jours regardait des jours jamais
            // chargés, une série de jours scannés pouvait « disparaître » le
            // lundi et refermer les vraies courbes.
            let solSemaine = cal.date(byAdding: .day, value: -7, to: week.start) ?? week.start
            let solAxe = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: Date())) ?? solSemaine
            let from = min(solSemaine, solAxe)
            let cle = "\(userId)|\(from.timeIntervalSince1970)|\(week.end.timeIntervalSince1970)"
            let tache: Task<[MealJournalService.MealRecord], Error>
            if let vol = Self.volEnCours, vol.cle == cle {
                tache = vol.tache
            } else {
                let service = self.service
                tache = Task { try await service.loadRange(userId: userId, from: from, to: week.end) }
                Self.volEnCours = (cle, tache)
            }
            defer { if Self.volEnCours?.cle == cle { Self.volEnCours = nil } }
            let all = try await tache.value
            fortnight = all
            meals = all.filter { Calendar.current.isDateInToday($0.consumedAt) }
            jourLePlusAncienCharge = min(jourLePlusAncienCharge, Calendar.current.startOfDay(for: from))
        } catch {
            AppLogger.database.warning("Journal load failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }

    // MARK: - Mutations

    func addManual(name: String, calories: Int, slot: MealJournalService.MealSlot) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let userId = AuthService.shared.cachedCurrentUserIdString else { return }
        do {
            try await service.insertManual(userId: userId, name: trimmed, calories: max(0, calories), slot: slot)
            await load()
            Self.postJournalChanged()
        } catch {
            AppLogger.database.warning("Journal add failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Une seule ÉCRITURE journal à la fois (suppression, quantité, ajout) :
    /// deux mutations rapprochées sur des données périmées écriraient des
    /// états incohérents (revue P1).
    private var writeInFlight = false

    /// Supprime une LIGNE du journal : l'aliment seul quand le repas porte le
    /// détail par aliment (la ligne `meal_scans` est relue puis réécrite,
    /// agrégats recomposés), le repas entier sinon (soft delete).
    func delete(_ row: MealJournalRow) async {
        guard !writeInFlight else { return }
        writeInFlight = true
        defer { writeInFlight = false }
        do {
            if row.deletesWholeRecord {
                try await service.softDelete(id: row.record.id)
                meals.removeAll { $0.id == row.record.id }
                fortnight.removeAll { $0.id == row.record.id }
            } else if let idx = row.itemIndex, row.record.items.indices.contains(idx) {
                let removed = try await service.deleteItem(recordId: row.record.id,
                                                           item: row.record.items[idx])
                if !removed {
                    AppLogger.database.info("Journal deleteItem: item introuvable (état périmé), rien écrit")
                }
                await load()
            }
            Self.postJournalChanged()
        } catch {
            AppLogger.database.warning("Journal delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Change la quantité (grammes) d'une ligne aliment — re-scaling linéaire
    /// persisté, agrégats recomposés. Ne fait rien si la ligne n'est pas
    /// éditable (pas de portion de base) ou si l'état a changé entre-temps.
    func updateQuantity(_ row: MealJournalRow, grams: Double) async {
        guard !writeInFlight, grams > 0,
              let idx = row.itemIndex, row.record.items.indices.contains(idx) else { return }
        writeInFlight = true
        defer { writeInFlight = false }
        do {
            let updated = try await service.updateItemQuantity(recordId: row.record.id,
                                                               item: row.record.items[idx],
                                                               newGrams: grams)
            if !updated {
                AppLogger.database.info("Journal updateQuantity: item introuvable/inéditable, rien écrit")
            }
            await load()
            Self.postJournalChanged()
        } catch {
            AppLogger.database.warning("Journal updateQuantity failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Ajoute un aliment de la recherche au créneau donné (ligne mono-aliment
    /// riche → éditable ensuite). `false` si la fiche est incomptable (OFF
    /// sans kcal) — l'UI désactive le CTA en amont, ceinture et bretelles.
    @discardableResult
    func addFood(detail: MealJournalService.FoodDetail,
                 grams: Double,
                 slot: MealJournalService.MealSlot) async -> Bool {
        guard !writeInFlight,
              let userId = AuthService.shared.cachedCurrentUserIdString,
              let entry = MealJournalService.entry(for: detail, grams: grams) else { return false }
        writeInFlight = true
        defer { writeInFlight = false }
        do {
            try await service.insertFood(userId: userId, entry: entry, slot: slot)
            await load()
            Self.postJournalChanged()
            return true
        } catch {
            AppLogger.database.warning("Journal addFood failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Le journal a changé (ajout/suppression) → mêmes écouteurs que la fin
    /// d'un scan (accueil Scan, Bilan, Suivi, Plan rechargent leurs données).
    /// Nom hérité : `.healthmapMealScanned` signifie « journal modifié ».
    private static func postJournalChanged() {
        NotificationCenter.default.post(name: .healthmapMealScanned, object: nil)
    }

    // MARK: - Totaux du jour

    var totalCalories: Int { meals.reduce(0) { $0 + $1.macros.calories } }
    var totalProteins: Double { meals.reduce(0) { $0 + $1.macros.proteins } }
    var totalCarbs: Double { meals.reduce(0) { $0 + $1.macros.carbs } }
    var totalFats: Double { meals.reduce(0) { $0 + $1.macros.fats } }
    var totalFiber: Double { meals.reduce(0) { $0 + $1.macros.fiber } }

    // MARK: - Par créneau

    func meals(in slot: MealJournalService.MealSlot) -> [MealJournalService.MealRecord] {
        meals.filter { $0.slot == slot }
    }

    func calories(in slot: MealJournalService.MealSlot) -> Int {
        meals(in: slot).reduce(0) { $0 + $1.macros.calories }
    }

    /// Lignes affichables du créneau : une par ALIMENT quand le repas porte
    /// le détail (scans photo récents), une par repas entier sinon
    /// (legacy / ajout manuel) — voir `MealJournalRow`.
    func rows(in slot: MealJournalService.MealSlot) -> [MealJournalRow] {
        meals(in: slot).flatMap { record -> [MealJournalRow] in
            guard record.hasItemDetail else {
                return [MealJournalRow(record: record, itemIndex: nil)]
            }
            return record.items.indices.map { MealJournalRow(record: record, itemIndex: $0) }
        }
    }

    // MARK: - Jour sélectionné (page d'accueil Scan)

    /// Repas du jour sélectionné, triés chronologiquement. Recalculé à chaque
    /// accès → suit `selectedDay` et tout rechargement (ex. après un scan).
    /// Puise dans la quinzaine ET dans les mois plus anciens chargés à la
    /// demande par le calendrier.
    var dayMeals: [MealJournalService.MealRecord] {
        if let cacheDayMeals { return cacheDayMeals }
        let jour = (fortnight + archives)
            .filter { cal.isDate($0.consumedAt, inSameDayAs: selectedDay) }
            .sorted { $0.consumedAt < $1.consumedAt }
        cacheDayMeals = jour
        return jour
    }

    /// Les cinq totaux du jour en UNE passe. Ils étaient calculés chacun de leur
    /// côté, donc cinq parcours de `dayMeals` au lieu d'un.
    private var dayTotaux: (kcal: Int, prot: Double, carb: Double, fat: Double, fiber: Double) {
        if let cacheDayTotaux { return cacheDayTotaux }
        var t = (kcal: 0, prot: 0.0, carb: 0.0, fat: 0.0, fiber: 0.0)
        for repas in dayMeals {
            t.kcal += repas.macros.calories
            t.prot += repas.macros.proteins
            t.carb += repas.macros.carbs
            t.fat += repas.macros.fats
            t.fiber += repas.macros.fiber
        }
        cacheDayTotaux = t
        return t
    }

    /// Lignes affichables d'un créneau POUR LE JOUR SÉLECTIONNÉ. `rows(in:)`
    /// reste sur aujourd'hui : c'est ce que lisent les écrans sans navigation
    /// par date.
    func dayRows(in slot: MealJournalService.MealSlot) -> [MealJournalRow] {
        dayMeals
            .filter { $0.slot == slot }
            .flatMap { record -> [MealJournalRow] in
                guard record.hasItemDetail else {
                    return [MealJournalRow(record: record, itemIndex: nil)]
                }
                return record.items.indices.map { MealJournalRow(record: record, itemIndex: $0) }
            }
    }

    func dayCalories(in slot: MealJournalService.MealSlot) -> Int {
        dayMeals.filter { $0.slot == slot }.reduce(0) { $0 + $1.macros.calories }
    }

    // MARK: - Totaux du jour sélectionné

    var dayCalories: Int { dayTotaux.kcal }
    var dayProteins: Double { dayTotaux.prot }
    var dayCarbs: Double { dayTotaux.carb }
    var dayFats: Double { dayTotaux.fat }
    var dayFiber: Double { dayTotaux.fiber }

    /// Part du besoin couverte aujourd'hui pour un micronutriment : somme des
    /// `pctRDA` des repas du jour portant cet id, plafonnée à 100 (formule
    /// canonique, alignée sur WeekScoreEngine / SuiviEngineV4).
    func dayMicroPct(_ id: String) -> Int {
        if let connu = cacheDayMicroPct[id] { return connu }
        let sum = dayMeals
            .flatMap { $0.micros }
            .filter { $0.id == id }
            .reduce(0) { $0 + $1.pctRDA }
        let pct = min(100, sum)
        cacheDayMicroPct[id] = pct
        return pct
    }

    /// Ids des micronutriments présents dans les repas du jour, en ordre
    /// canonique (NutrientData.all) puis le reste (ids hors catalogue, triés).
    var dayNutrientIds: [String] {
        if let cacheDayNutrientIds { return cacheDayNutrientIds }
        let present = Set(dayMeals.flatMap { $0.micros }.map(\.id))
        let canonical = NutrientData.all.map(\.id.rawValue).filter { present.contains($0) }
        let rest = present.subtracting(canonical).sorted()
        let ids = canonical + rest
        cacheDayNutrientIds = ids
        return ids
    }

    // MARK: - Navigation jour par jour (bornée à la fenêtre `fortnight`)

    /// Jour le plus ancien navigable = le SOL RÉEL de la fenêtre chargée par
    /// `load()` : min(lundi précédent − 7 j hebdo, 14 jours glissants). Aligné
    /// sur la même source que le chargement, pour ne jamais proposer un jour
    /// passé « vide » alors que ses repas existent en base mais hors requête.
    private var earliestDay: Date {
        let cal = Calendar.current
        let weekStart = WeekScoreEngine.currentWeekInterval(containing: Date()).start
        let solSemaine = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: weekStart))
            ?? cal.startOfDay(for: Date())
        let solAxe = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: Date())) ?? solSemaine
        return min(solSemaine, solAxe)
    }

    /// Peut-on avancer d'un jour ? Faux si on est déjà sur aujourd'hui (pas de futur).
    var canGoNext: Bool {
        selectedDay < Calendar.current.startOfDay(for: Date())
    }

    func goPrevDay() {
        let cal = Calendar.current
        guard let prev = cal.date(byAdding: .day, value: -1, to: selectedDay) else { return }
        let clamped = cal.startOfDay(for: prev)
        if clamped >= earliestDay { selectedDay = clamped }
    }

    // MARK: - Calendrier (journal du jour)

    /// Va à une date quelconque du passé et charge ce qu'il faut pour l'afficher.
    /// Le futur est refusé — on ne mange pas demain.
    func allerAuJour(_ date: Date) async {
        let cal = Calendar.current
        let jour = min(cal.startOfDay(for: date), cal.startOfDay(for: Date()))
        selectedDay = jour
        await chargerArchiveSiBesoin(pour: jour)
    }

    /// Charge le mois du jour demandé s'il est plus ancien que ce qu'on a déjà.
    /// On charge par MOIS entier : le calendrier affiche un mois à la fois, et
    /// une requête par jour feuilleté serait absurde.
    func chargerArchiveSiBesoin(pour date: Date) async {
        let cal = Calendar.current
        let jour = cal.startOfDay(for: date)
        guard jour < jourLePlusAncienCharge else { return }
        guard let userId = AuthService.shared.cachedCurrentUserIdString else { return }
        guard let debutMois = cal.date(from: cal.dateComponents([.year, .month], from: jour)) else { return }

        chargeLArchive = true
        defer { chargeLArchive = false }
        do {
            let anciens = try await service.loadRange(
                userId: userId,
                from: debutMois,
                to: jourLePlusAncienCharge
            )
            // Dédoublonnage : la borne haute recouvre le premier jour déjà chargé.
            let dejaLa = Set((fortnight + archives).map(\.id))
            archives.append(contentsOf: anciens.filter { !dejaLa.contains($0.id) })
            jourLePlusAncienCharge = min(jourLePlusAncienCharge, debutMois)
        } catch {
            AppLogger.database.warning("Archive journal indisponible: \(error.localizedDescription, privacy: .public)")
        }
    }

    func goNextDay() {
        guard canGoNext else { return }
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .day, value: 1, to: selectedDay) else { return }
        selectedDay = min(cal.startOfDay(for: next), cal.startOfDay(for: Date()))
    }

    // MARK: - Libellés du jour

    /// Libellé principal : Aujourd'hui / Hier / Avant-hier / date courte.
    var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDay) { return "Aujourd'hui" }
        if cal.isDateInYesterday(selectedDay) { return "Hier" }
        if daysAgo == 2 { return "Avant-hier" }
        return Self.shortDayFormatter.string(from: selectedDay)
    }

    /// Sous-libellé : « il y a N jours » quand le libellé est déjà une date,
    /// sinon la date courte (ex. « dim. 5 juil. »).
    var daySub: String {
        if daysAgo >= 3 { return "il y a \(daysAgo) jours" }
        return Self.shortDayFormatter.string(from: selectedDay)
    }

    private var daysAgo: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: selectedDay, to: cal.startOfDay(for: Date())).day ?? 0
    }

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    // MARK: - Phrases de synthèse (pures — testables sans I/O)

    /// En-tête de la carte « apports du jour » : nomme les 1-2 apports les plus
    /// bas (< 60 % du besoin). Tout couvert → message positif. Aucun item →
    /// invite à scanner (aujourd'hui) ou constat neutre (jour passé). Formulation
    /// sans article de genre (« ton apport en … ») + relative au jour sélectionné.
    nonisolated static func dayMicroHeadline(_ items: [(id: String, pct: Int)], isToday: Bool) -> String {
        let low = items.filter { $0.pct < 60 }.sorted { $0.pct < $1.pct }
        func label(_ id: String) -> String { (NutrientData.definition(for: id)?.label ?? id).lowercased() }
        let quand = isToday ? "aujourd'hui" : "ce jour-là"
        switch low.count {
        case 0:
            if items.isEmpty {
                return isToday
                    ? "Scanne un repas pour suivre tes apports du jour."
                    : "Aucun repas enregistré ce jour-là."
            }
            return "Tes apports du jour sont bien couverts."
        case 1:
            return "Ton apport en \(label(low[0].id)) est en retard \(quand)."
        default:
            return "Tes apports en \(label(low[0].id)) et \(label(low[1].id)) sont en retard \(quand)."
        }
    }

    /// En-tête de la carte macros : nomme la macro la plus en retard (plus grand
    /// écart cible − apport, en grammes). Rien à combler → journée équilibrée.
    /// Prescriptif pour aujourd'hui (« vise … de plus »), rétrospectif pour un
    /// jour passé (« il manquait … »).
    nonisolated static func dayMacroHeadline(
        prot: (g: Double, target: Int?),
        carb: (g: Double, target: Int?),
        fat: (g: Double, target: Int?),
        fiber: (g: Double, target: Int?),
        isToday: Bool
    ) -> String {
        func gap(_ m: (g: Double, target: Int?)) -> Double {
            guard let t = m.target, t > 0 else { return 0 }
            return max(0, Double(t) - m.g)
        }
        let macros: [(name: String, gap: Double)] = [
            ("protéines", gap(prot)),
            ("glucides", gap(carb)),
            ("lipides", gap(fat)),
            ("fibres", gap(fiber)),
        ]
        guard let worst = macros.max(by: { $0.gap < $1.gap }), worst.gap >= 1 else {
            return isToday ? "Équilibré aujourd'hui." : "Journée équilibrée."
        }
        let g = Int(worst.gap.rounded())
        return isToday
            ? "Vise \(g) g de \(worst.name) de plus aujourd'hui."
            : "Il manquait \(g) g de \(worst.name) ce jour-là."
    }
}

// MARK: - Ligne du journal (une par aliment quand le détail existe)

/// Une ligne affichable du journal : UN aliment d'un repas riche, ou le repas
/// entier quand le détail par aliment n'existe pas (legacy / ajout manuel).
/// Hors de `MealJournalViewModel` (donc hors @MainActor) — pure et testable.
struct MealJournalRow: Identifiable, Equatable {
    let record: MealJournalService.MealRecord
    /// Index dans `record.items` — nil = ligne « repas entier ».
    let itemIndex: Int?

    var id: String { itemIndex.map { "\(record.id)#\($0)" } ?? record.id }

    var name: String {
        if let i = itemIndex, record.items.indices.contains(i) {
            return record.items[i].name
        }
        let joined = record.foods.prefix(3).joined(separator: ", ")
        return joined.isEmpty ? "Repas" : joined
    }

    /// Portion en grammes — nil = inconnue (jamais inventée, pas affichée).
    var grams: Double? {
        guard let i = itemIndex, record.items.indices.contains(i) else { return nil }
        return record.items[i].portionG
    }

    var calories: Int {
        if let i = itemIndex, record.items.indices.contains(i) {
            return record.items[i].macros?.calories ?? 0
        }
        return record.macros.calories
    }

    /// Macros affichées : celles de l'aliment pour une ligne item, celles du
    /// repas entier pour une ligne agrégée.
    var macros: MealJournalService.MealMacros {
        if let i = itemIndex, record.items.indices.contains(i),
           let m = record.items[i].macros {
            return m
        }
        return record.macros
    }

    /// Id du 1er micro apporté — sert d'icône à la ligne (fourchette sinon).
    var iconMicroId: String? {
        if let i = itemIndex, record.items.indices.contains(i),
           let first = record.items[i].micros?.first {
            return first.id
        }
        return record.micros.first?.id
    }

    /// La suppression retire-t-elle le repas entier ? (ligne agrégée, ou
    /// dernier aliment du repas)
    var deletesWholeRecord: Bool {
        itemIndex == nil || record.items.count == 1
    }

    /// Ligne « repas entier » sans détail par aliment.
    var isAggregate: Bool { itemIndex == nil }

    /// La quantité est-elle modifiable ? (item avec une portion de base
    /// exploitable pour le re-scaling — jamais de base inventée)
    var isQuantityEditable: Bool {
        guard let i = itemIndex, record.items.indices.contains(i),
              let g = record.items[i].portionG else { return false }
        return g > 0 && record.items[i].macros != nil
    }
}
