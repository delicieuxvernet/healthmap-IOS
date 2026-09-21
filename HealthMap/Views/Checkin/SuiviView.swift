import SwiftUI
import Foundation

// MARK: - Progrès (onglet 2, maquette « Progrès v3 » du 20 septembre 2026)
//
// Le verdict d'abord, le graphe ensuite. La page répond en trois phrases à
// « est-ce que ça avance ? », puis montre UN graphe à la fois (symptômes,
// apports, calories), puis les apports en « avant → après ».
//
// Tout se calcule seul à partir de données DÉJÀ chargées — aucun appel réseau
// ni LLM à l'affichage :
//   • le journal alimentaire  → MealJournalViewModel.fortnight (14 derniers jours)
//   • les symptômes déclarés  → DashboardViewModel.analysisV2?.bilan?.symptomes
//   • les scores d'apports    → DashboardViewModel.nutrients (< 60 = à renforcer)
//   • les ressentis locaux    → SuiviCheckinHistory (UserDefaults scopé jour)
//   • les phrases du verdict  → ProgresVerdict (pur, testé)
//
// Frontière Premium INCHANGÉE par la refonte : l'évolution des symptômes et la
// tendance des apports restent derrière leurs portes (`suivi_symptomes`,
// `suivi_micros`) ; en gratuit le verdict nomme le sujet, jamais sa tendance.
//
// Le check-in (un symptôme par écran) n'est proposé qu'À L'ARRIVÉE sur
// l'onglet : les cinq onglets restant montés, un `onAppear` l'ouvrirait au
// lancement, par-dessus le Journal — donc en pleine saisie.
struct SuiviView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @ObservedObject private var gamification = GamificationService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Journal alimentaire (14 derniers jours) — chargé À L'AFFICHAGE (lecture
    /// Supabase RLS de meal_scans, pas d'IA/LLM). Détenu ici : `SuiviView` est
    /// monté avec le seul `dashboardVM` en environnement (cf. ContentView).
    @StateObject private var journal = MealJournalViewModel()

    @State private var showCheckin = false
    /// Incrémenté après chaque check-in : les ressentis sont relus depuis
    /// UserDefaults à la volée, ce compteur force le recalcul des courbes.
    @State private var checkinTick = 0
    @State private var segment: ProgresSegment = .symptomes
    /// Symptôme affiché dans le graphe (menu quand il y en a plusieurs).
    @State private var symptomeIndex = 0
    @State private var courbeProgress: CGFloat = 0
    /// Fiche d'un apport ouverte depuis « Depuis ton premier jour ».
    @State private var selectedNutrient: EnrichedNutrient?
    /// Le brief du matin peut-il se rejouer ? (lu hors du `body` : il décode
    /// un cache.)
    @State private var briefDisponible = false

    var body: some View {
        // Calculés UNE fois par passe de rendu, passés à toutes les cartes.
        let reponses = reponsesParSymptome
        let evolutions = evolutionsSymptomes(reponses)
        let couverture = coverage
        let calories = pointsGraphe(.calories)
        let verrouille = dashboardVM.premiumVisible

        return NavigationStack {
            ZStack {
                DSPageBackground()

                ScrollView {
                    VStack(spacing: DS.interCarte) {
                        let lignes = lignesVerdict(evolutions: evolutions, couverture: couverture,
                                                   calories: calories, verrouille: verrouille)
                        if !lignes.isEmpty {
                            ProgresVerdictCard(lignes: lignes)
                        }

                        if aucunRepas {
                            // Premier jour : on le dit, on n'illustre pas.
                            ProgresPremierJourCard { ouvrirAjout() }
                        }

                        grapheCard(evolutions: evolutions, reponses: reponses,
                                   couverture: couverture, verrouille: verrouille)

                        if verrouille, segment == .symptomes,
                           evolutions.contains(where: { ProgresVerdict.aUneTendance($0) }) {
                            UnlockDoor(
                                icon: "chart.xyaxis.line",
                                title: "Vois l'évolution de tes symptômes",
                                subtitle: "Ta trajectoire, semaine après semaine",
                                zone: "suivi_symptomes"
                            )
                        }

                        if !aucunRepas {
                            depuisLeDebut(couverture, verrouille: verrouille)
                        }

                        // Découverte (V12c) : la porte vers le bilan. Uniquement
                        // sans bilan ; l'onglet ne déclenche AUCUN appel IA.
                        if !dashboardVM.bilanComplete {
                            BilanDoorButton(
                                title: BilanDoorButton.Libelle.suivi,
                                accessibilityText: "Suivre mes vrais chiffres, faire le bilan en 3 minutes",
                                zone: .suivi
                            ) {
                                dashboardVM.demarrerBilan()
                            }
                            .padding(.top, 14)
                        }

                        if briefDisponible {
                            ProgresRecapRow {
                                HapticService.shared.tap()
                                NotificationCenter.default.post(name: .healthmapRevoirBrief, object: nil)
                            }
                        }
                    }
                    .padding(.horizontal, DS.marge)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                    // Verrou anti-dérive horizontale : la largeur du contenu est
                    // épinglée à celle du ScrollView.
                    .containerRelativeFrame(.horizontal)
                }
            }
            .kiwiTabBarBottomInset()
            // Grand titre natif : se replie en titre inline au défilement.
            .navigationTitle("Progrès")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedNutrient) { nutrient in
                // La même fiche que depuis le Journal ou le Bilan.
                ApportV2DetailSheet(apport: .pourLaFiche(nutrient, bilan: dashboardVM.analysisV2?.bilan)) {
                    selectedNutrient = nil
                    NotificationCenter.default.post(
                        name: .healthmapNavigateToTab,
                        object: NavCardDestination.plan.rawValue
                    )
                }
            }
            .sheet(isPresented: $showCheckin) {
                CheckinSymptomesSheet(
                    symptomes: checkinSymptoms,
                    onTerminer: { ressentis in
                        SuiviCheckinStore.saveToday(symptomFeels: ressentis)
                        gamification.recordCheckin()
                        checkinTick += 1
                        HapticService.shared.success()
                        // Rappels quotidiens proposés ICI, au moment de valeur
                        // (1re réponse) — jamais au lancement.
                        Task { await LocalNotificationService.enableReminders() }
                    },
                    onPasser: { SuiviCheckinStore.snoozeToday() }
                )
            }
            .task {
                // Le suivi démarre tout seul à la première visite (retour
                // d'Arthur du 23 août : des vrais points dès le premier jour).
                // Un compte avec d'anciens check-ins garde son ancrage au
                // premier d'entre eux.
                SuiviTrackingStore.startFromExistingCheckinsIfNeeded()
                SuiviTrackingStore.start()
                // Idempotent, sans redemander la permission : couvre ceux qui
                // suivaient déjà avant l'arrivée des rappels quotidiens.
                await LocalNotificationService.scheduleDailyReminders()
                await journal.load()
            }
            // Un repas ajouté dans le Journal ne relance pas ce `.task` (l'onglet
            // reste vivant) : on recharge pour que le verdict l'intègre.
            .onReceive(NotificationCenter.default.publisher(for: .healthmapMealScanned)) { _ in
                Task { await journal.load() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .healthmapTabDidChange)) { notification in
                guard notification.object as? String == NavCardDestination.suivi.rawValue else { return }
                arriveeSurLOnglet()
            }
        }
    }

    /// L'onglet vient d'être choisi : la courbe rejoue son tracé, le brief est
    /// relu, et le check-in du jour se propose — une fois par jour, jamais s'il
    /// est déjà fait ou reporté, jamais sans symptôme à suivre.
    private func arriveeSurLOnglet() {
        briefDisponible = BriefDuJourBuilder.depuisLeCache() != nil
        animerCourbe()
        if SuiviCheckinStore.shouldPromptToday(), !checkinSymptoms.isEmpty {
            showCheckin = true
        }
    }

    private func animerCourbe() {
        guard !reduceMotion else { courbeProgress = 1; return }
        courbeProgress = 0
        withAnimation(.easeOut(duration: 0.9).delay(0.15)) { courbeProgress = 1 }
    }

    // MARK: - Le verdict, en trois lignes

    private func lignesVerdict(evolutions: [SuiviEngineV4.SymptomEvolution],
                               couverture: [SuiviEngineV4.NutrientCoverage7d],
                               calories: [ProgresBarPoint],
                               verrouille: Bool) -> [ProgresVerdict.Ligne] {
        let suivis = calories.filter { $0.valeur != nil }
        return [
            ProgresVerdict.ligneSymptome(evolutions, verrouille: verrouille),
            ProgresVerdict.ligneApport(couverture: couverture, joursSuivis: suivis.count, verrouille: verrouille),
            ProgresVerdict.ligneCalories(joursSuivis: suivis.count,
                                         joursDansLaCible: suivis.filter { !$0.horsCible }.count,
                                         besoinConnu: besoin(.calories) != nil),
        ].compactMap { $0 }
    }

    // MARK: - Le graphe : un seul à la fois

    private func grapheCard(evolutions: [SuiviEngineV4.SymptomEvolution],
                            reponses: [String: [(jour: Date, ressenti: Int)]],
                            couverture: [SuiviEngineV4.NutrientCoverage7d],
                            verrouille: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Vue", selection: $segment) {
                ForEach(ProgresSegment.allCases) { s in
                    Text(s.libelle).tag(s)
                }
            }
            .pickerStyle(.segmented)

            switch segment {
            case .symptomes:
                grapheSymptomes(evolutions, reponses: reponses, couverture: couverture, verrouille: verrouille)
            case .apports, .calories:
                grapheBarres(segment)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .onChange(of: segment) { _, nouveau in
            if nouveau == .symptomes { animerCourbe() }
        }
        .onChange(of: symptomeIndex) { _, _ in animerCourbe() }
    }

    @ViewBuilder
    private func grapheSymptomes(_ evolutions: [SuiviEngineV4.SymptomEvolution],
                                 reponses: [String: [(jour: Date, ressenti: Int)]],
                                 couverture: [SuiviEngineV4.NutrientCoverage7d],
                                 verrouille: Bool) -> some View {
        if evolutions.isEmpty {
            Text(dashboardVM.isLoadingAnalysisV2
                 ? "On regarde tes symptômes déclarés…"
                 : "Tu n'as déclaré aucun symptôme dans ton questionnaire : il n'y a rien à suivre ici pour le moment.")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        } else {
            let evolution = evolutions[min(symptomeIndex, evolutions.count - 1)]
            let trend = SymptomTrend.make(from: evolution.nom)
            let mesuree = ProgresVerdict.aUneTendance(evolution)
            // Gratuit : la trajectoire ENTIÈRE est gatée — courbe voilée ET
            // verdict neutralisé (fuite corrigée le 4 août 2026). Sans réponse
            // encore, il n'y a rien à cacher.
            let gatee = verrouille && mesuree

            ProgresSymptomeEntete(
                noms: evolutions.map { ProgresVerdict.majuscule($0.nom) },
                index: $symptomeIndex,
                verdict: gatee ? "Ta tendance" : (mesuree ? evolution.verdict : "Ton suivi démarre"),
                niveaux: (gatee || !mesuree) ? nil
                    : ProgresVerdict.niveauxGagnes(ressentis: (reponses[evolution.id] ?? []).map(\.ressenti))
            )
            .padding(.top, 16)

            let courbe = ProgresCourbeSymptome(
                jours: evolution.jours,
                mieuxVersLeHaut: trend.dir == .higherBetter,
                libelleHaut: trend.betterLabel.lowercased(),
                libelleBas: trend.worseLabel.lowercased(),
                progress: courbeProgress
            )
            if gatee {
                GatedOverlay(intensity: .teaser) { courbe }
                    .padding(.top, 14)
            } else {
                courbe.padding(.top, 14)
            }

            if !gatee, let lien = lienAvecUnApport(evolution, couverture: couverture) {
                ProgresEncart(symbole: "link", texte: lien)
                    .padding(.top, 14)
            }

            // Reporté ou fermé ce matin : le check-in reste à portée de main.
            if !SuiviCheckinStore.hasAnsweredToday() {
                Button {
                    HapticService.shared.tap()
                    showCheckin = true
                } label: {
                    Text("Répondre au check-in du jour")
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundStyle(Color.dsAccent)
                        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
    }

    private func grapheBarres(_ segment: ProgresSegment) -> some View {
        let points = pointsGraphe(segment)
        return VStack(alignment: .leading, spacing: 0) {
            Text(conclusion(points, segment: segment))
                .font(.system(.title3, design: .default).weight(.bold))
                .tracking(-0.55)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            ProgresBarChart(points: points, besoin: besoin(segment))
                .frame(height: 132)
                .padding(.top, 12)

            HStack(spacing: 16) {
                Text("Barres : tes apports")
                Text("Pointillé : tes besoins")
            }
            .font(.dsLegende)
            .tracking(DSTracking.legende)
            .foregroundStyle(Color.dsSecondaire)
            .padding(.top, 4)
        }
    }

    /// « Ce suivi va avec ton apport en fer, en hausse depuis ton départ. » Le
    /// lien vient du bilan (`SymptomeV2.causes`), la tendance du journal : on
    /// rapproche deux faits, on ne promet aucun effet.
    private func lienAvecUnApport(_ evolution: SuiviEngineV4.SymptomEvolution,
                                  couverture: [SuiviEngineV4.NutrientCoverage7d]) -> String? {
        let symptome = (dashboardVM.analysisV2?.bilan?.symptomes ?? [])
            .first { ($0.id ?? $0.nom) == evolution.id }
        guard let cause = symptome?.causes?.first,
              let apport = dashboardVM.nutrients.first(where: { $0.id == cause }) else { return nil }
        let nom = apport.label.lowercased()
        if let mesure = couverture.first(where: { $0.id == cause }),
           mesure.pct - mesure.baselinePct >= ProgresVerdict.ecartMinimum {
            return "Ce suivi va avec ton apport en \(nom), en hausse depuis ton départ."
        }
        return "Ce suivi va avec ton apport en \(nom) : c'est lui qu'on regarde en premier."
    }

    // MARK: - Depuis ton premier jour (avant → après)

    @ViewBuilder
    private func depuisLeDebut(_ couverture: [SuiviEngineV4.NutrientCoverage7d], verrouille: Bool) -> some View {
        let lignes = couverture.map {
            ProgresDepuisLeDebutCard.Ligne(id: $0.id, nom: $0.nom, avant: $0.baselinePct, apres: $0.pct)
        }
        if lignes.isEmpty {
            EmptyView()
        } else if verrouille {
            // Verrou (et porte) seulement une fois le bilan fait : la carte
            // reste devinable derrière le voile, l'ouverture attend l'abonnement.
            GatedOverlay(intensity: .locked) {
                ProgresDepuisLeDebutCard(lignes: lignes, duree: dureeDuSuivi) { _ in }
            }
            UnlockDoor(
                icon: "chart.xyaxis.line",
                title: "Débloque la tendance de tes apports",
                subtitle: "Visualise leur évolution jour après jour",
                zone: "suivi_micros"
            )
        } else {
            ProgresDepuisLeDebutCard(lignes: lignes, duree: dureeDuSuivi) { ligne in
                guard let nutrient = dashboardVM.nutrients.first(where: { $0.id == ligne.id }) else { return }
                HapticService.shared.tap()
                selectedNutrient = nutrient
            }
        }
    }

    /// « 14 jours » depuis le début du suivi ; `nil` le premier jour.
    private var dureeDuSuivi: String? {
        guard let depart = SuiviTrackingStore.startDate() else { return nil }
        let cal = Calendar.current
        let jours = (cal.dateComponents([.day], from: cal.startOfDay(for: depart),
                                        to: cal.startOfDay(for: Date())).day ?? 0) + 1
        return jours > 1 ? "\(jours) jours" : nil
    }

    // MARK: - Symptômes (série quotidienne, un point par jour répondu)

    /// Symptômes déclarés (id + nom + sens) — pilotent le graphe ET le check-in.
    private var checkinSymptoms: [(id: String, nom: String, trend: SymptomTrend)] {
        (dashboardVM.analysisV2?.bilan?.symptomes ?? []).compactMap { s in
            guard let nom = s.nom, !nom.isEmpty else { return nil }
            return (s.id ?? nom, nom, SymptomTrend.make(from: nom))
        }
    }

    private var reponsesParSymptome: [String: [(jour: Date, ressenti: Int)]] {
        // `checkinTick` est LU ici pour forcer le recalcul après un check-in.
        let _ = checkinTick
        return SuiviCheckinHistory.reponsesParJour(symptomIds: checkinSymptoms.map(\.id),
                                                   since: SuiviTrackingStore.startDate() ?? Date())
    }

    private func evolutionsSymptomes(_ reponses: [String: [(jour: Date, ressenti: Int)]]) -> [SuiviEngineV4.SymptomEvolution] {
        SuiviEngineV4.symptomEvolutionsQuotidiennes(
            symptomes: dashboardVM.analysisV2?.bilan?.symptomes,
            reponsesById: reponses,
            depart: SuiviTrackingStore.startDate() ?? Date()
        )
    }

    // MARK: - Apports et calories (fenêtre glissante de sept jours)

    /// Aucun repas sur la fenêtre chargée.
    private var aucunRepas: Bool { journal.fortnight.isEmpty }

    /// Ouvre la saisie du Journal.
    private func ouvrirAjout() {
        HapticService.shared.tap()
        NotificationCenter.default.post(
            name: .healthmapNavigateToTab,
            object: NavCardDestination.scanner.rawValue
        )
    }

    /// Initiale du jour d'une date (D L M M J V S, indexée par weekday 1-7).
    private static let initialesParWeekday = ["D", "L", "M", "M", "J", "V", "S"]

    private static func initiale(_ jour: Date) -> String {
        let weekday = WeekScoreEngine.mondayFirst.component(.weekday, from: jour)
        return initialesParWeekday[(weekday - 1) % 7]
    }

    /// Fenêtre GLISSANTE : les 7 derniers jours, aujourd'hui en dernier.
    /// (La semaine calendaire vidait tout l'historique chaque lundi matin —
    /// « hier j'avais des datas, aujourd'hui elles n'y sont plus », 24 août.)
    private var joursSemaine: [Date] {
        let cal = WeekScoreEngine.mondayFirst
        let aujourdHui = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0 - 6, to: aujourdHui) }
    }

    /// Calories par jour ; nil = aucun repas ce jour-là (un trou honnête,
    /// jamais un zéro fabriqué).
    private var caloriesParJour: [Double?] {
        let cal = WeekScoreEngine.mondayFirst
        return joursSemaine.map { jour in
            let repas = journal.fortnight.filter { cal.isDate($0.consumedAt, inSameDayAs: jour) }
            guard !repas.isEmpty else { return nil }
            return repas.reduce(0.0) { $0 + Double($1.macros.calories) }
        }
    }

    /// Besoin de la vue : l'objectif calorique du profil, ou 100 % pour les
    /// apports. nil = inconnu → pas de ligne, pas de verdict.
    private func besoin(_ segment: ProgresSegment) -> Double? {
        switch segment {
        case .calories: return dashboardVM.physicalMetrics.macros.map { Double($0.calories) }
        case .apports: return 100
        case .symptomes: return nil
        }
    }

    /// Un jour est hors cible à plus de 15 % de l'objectif calorique, ou sous
    /// 60 % de couverture des apports (le seuil « couvert » de l'app).
    private func horsCible(_ valeur: Double, segment: ProgresSegment) -> Bool {
        guard let besoin = besoin(segment), besoin > 0 else { return false }
        if segment == .apports { return valeur < 60 }
        return abs(valeur - besoin) / besoin > 0.15
    }

    private func pointsGraphe(_ segment: ProgresSegment) -> [ProgresBarPoint] {
        let jours = joursSemaine
        let valeurs: [Double?]
        switch segment {
        case .calories: valeurs = caloriesParJour
        case .apports:
            // Fenêtre glissante : les scores se calculent sur CES jours-là,
            // pas sur la semaine calendaire du moteur.
            valeurs = WeekScoreEngine.scoresQuotidiens(meals: journal.fortnight,
                                                       weakNutrients: weakNutrientIds,
                                                       jours: jours).map { $0.map(Double.init) }
        case .symptomes: valeurs = []
        }
        return jours.enumerated().map { index, jour in
            let valeur = index < valeurs.count ? valeurs[index] : nil
            return ProgresBarPoint(
                id: index,
                libelle: Self.initiale(jour),
                valeur: valeur,
                horsCible: valeur.map { horsCible($0, segment: segment) } ?? false,
                futur: false
            )
        }
    }

    private func conclusion(_ points: [ProgresBarPoint], segment: ProgresSegment) -> String {
        let mesures = points.filter { $0.valeur != nil }
        guard !mesures.isEmpty else { return "Pas encore de repas sur les sept derniers jours." }
        guard besoin(segment) != nil else { return "Complète ton profil pour connaître tes besoins." }
        let dansLaCible = mesures.filter { !$0.horsCible }.count
        let sujet = segment == .apports ? "avec tes besoins couverts" : "dans ta cible"
        return "\(Self.enLettres(dansLaCible).capitalized) jour\(dansLaCible > 1 ? "s" : "") sur \(Self.enLettres(mesures.count)) \(sujet)."
    }

    /// Les petits nombres s'écrivent en lettres dans une phrase.
    private static func enLettres(_ n: Int) -> String {
        let mots = ["zéro", "un", "deux", "trois", "quatre", "cinq", "six", "sept"]
        return n >= 0 && n < mots.count ? mots[n] : "\(n)"
    }

    // MARK: - Dérivés déterministes (aucun appel réseau)

    /// Ids des apports à renforcer (score < 60) — priorisent la couverture.
    private var weakNutrientIds: [String] {
        dashboardVM.nutrients.filter { $0.score < 60 }.map(\.id)
    }

    private var coverage: [SuiviEngineV4.NutrientCoverage7d] {
        // Socle « départ » = baseline persistée (scores figés au 1er bilan).
        // Tant qu'elle n'est pas capturée, on passe [:] : avant = après, aucun
        // écart affiché (évite un socle transitoire faux).
        let baseline = dashboardVM.profile.baselineNutrientScores ?? [:]
        return SuiviEngineV4.nutrientCoverage(fortnight: journal.fortnight,
                                              focusIds: weakNutrientIds,
                                              baseline: baseline)
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

    /// La question du check-in, TOUJOURS dans le sens du mieux (« Plus nette
    /// qu'avant ? ») : une question neutre ne dit pas ce qu'on espère voir.
    var questionVersLeMieux: String { "\(betterLabel) qu'avant\u{00A0}?" }

    /// Le symbole de l'écran de question.
    var symbole: String {
        switch noun {
        case "ton énergie": return "bolt"
        case "ta concentration": return "brain.head.profile"
        case "tes ongles": return "hand.raised"
        case "tes cheveux": return "comb"
        case "ta digestion": return "fork.knife"
        case "ton humeur": return "face.smiling"
        case "ton sommeil": return "moon"
        case "ta fatigue": return "battery.25percent"
        case "ta peau": return "drop"
        case "ton stress": return "wind"
        default: return "heart.text.square"
        }
    }

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

// MARK: - Maths partagées des courbes (lissage Catmull-Rom → Bézier)
// Interne (pas `private`) : partagé avec d'autres courbes du Suivi.
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
// « healthmap_suivi_checkin_<uid>_<yyyy-MM-dd> » → dict { "feel_<id>": 0|1|2 }.
// Le drapeau « présenté aujourd'hui » (répondu OU reporté) vit sur une clé à part
// pour ne proposer le check-in qu'une fois par jour.
@MainActor
enum SuiviCheckinStore {
    static let symptomFeelKey = "symptome_today"   // mirror de SuiviCheckinHistory.feelKey

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

    /// Enregistre le ressenti de CHAQUE symptôme répondu (`feel_<id>`) dans le
    /// dictionnaire scopé jour, et marque le check-in présenté.
    static func saveToday(symptomFeels: [String: Int]) {
        var dict = (UserDefaults.standard.dictionary(forKey: checkinKey(dayString())) as? [String: Int]) ?? [:]
        for (sid, feel) in symptomFeels {
            dict[SuiviCheckinHistory.feelKeyFor(sid)] = feel
        }
        UserDefaults.standard.set(dict, forKey: checkinKey(dayString()))
        UserDefaults.standard.set(true, forKey: promptedKey(dayString()))
        // Répondre au pop-up vaut démarrage du suivi : la promesse « ça met
        // tes courbes à jour » ne dépend plus du bandeau « Commencer mon suivi ».
        SuiviTrackingStore.startFromExistingCheckinsIfNeeded()
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
