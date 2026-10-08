import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: - Published State

    @Published var profile: UserProfile = .empty
    @Published var aiAnalysis: MergedAnalysis?
    /// Bilan v2 (contrat v2) — nourrit le NOUVEL écran Bilan (v6). Le flux v7
    /// (`aiAnalysis`) continue de nourrir Plan/Compléments jusqu'à la vague V4.
    @Published var analysisV2: AIAnalysisV2? {
        // Un bilan arrive (réseau, cache, test) : ses trois apports prennent
        // aussitôt le statut et le chiffre du calcul local.
        didSet { if !alignementEnCours { alignerBilan() } }
    }
    private var alignementEnCours = false
    @Published var isLoadingProfile = false
    @Published var isLoadingAnalysis = false
    @Published var isLoadingAnalysisV2 = false
    @Published var healthScore: Int = 0
    @Published var nutrientScores: [String: Int] = [:]
    /// Ce que les repas notés des 14 derniers jours ont montré (étape 3 de
    /// l'audit de personnalisation) ; nil tant qu'ils n'en disent pas assez.
    @Published private(set) var observationsJournal: ObservationsJournal?
    /// Les journées de repas notés des 14 derniers jours, au format de
    /// `EstimateurApports` (audit de fiabilité du 8 oct. 2026).
    @Published private(set) var journeesNotees: [JourneeNotee] = []
    /// Les 27 apports estimés en vraies quantités (Ciqual × INCA 3 × ANSES
    /// 2021), journal compris. nil sans questionnaire complet ou si le
    /// référentiel n'est pas lisible (on retombe alors sur l'ancien registre).
    @Published private(set) var estimation: ResultatEstimation?
    /// La prise de sang la plus récente (Premium, 30 sept. 2026) ; nil sans
    /// import. Elle corrige les apports APRÈS le journal (`PriseDeSangApports`).
    @Published private(set) var priseDeSang: PriseDeSang?
    @Published var hasCompletedQuestionnaire = false
    /// Passe à `true` une fois le PREMIER `loadProfile` terminé (succès, échec
    /// ou pas de session) — succès OU échec. Tant qu'il est `false`, la racine
    /// (`MainTabView`) tient un écran de chargement propre AU LIEU de rendre
    /// une branche dont l'état n'est pas encore connu : sinon, au démarrage à
    /// froid, `hasCompletedQuestionnaire` valant `false` par défaut faisait
    /// clignoter le questionnaire (ou les onglets verrouillés) une fraction de
    /// seconde avant de basculer sur le Dashboard (« écrans faux » au réveil).
    @Published var didFinishInitialLoad = false
    /// Questionnaire présenté par-dessus les onglets (feuille plein écran de
    /// MainTabView). Piloté par `demarrerBilan()` ; remis à false à la
    /// fermeture (« Explorer d'abord », la croix, ou fin du questionnaire).
    @Published var questionnaireOuvert = false
    /// Où en est un bilan commencé et pas terminé (« Étape 2 sur 4 »), pour la
    /// carte du Journal. `nil` tant que rien n'est commencé. Posé par
    /// `MainTabView`, qui tient le ViewModel du questionnaire.
    @Published var repriseBilan: RepriseBilan?
    @Published var errorMessage: String?
    /// Erreur dédiée au bilan v2 (écran de chargement/gate onboarding).
    /// Distincte de `errorMessage` (v7, autre bandeau) pour ne pas faire
    /// courir de risque de course entre les deux tâches parallèles — un raté
    /// v7 ne doit jamais afficher/masquer une erreur qui concerne le v2 et
    /// inversement (incident bilan indisponible, 4 juillet : la gate bloquait
    /// sur `aiAnalysis`/v7 alors que le bilan RÉELLEMENT affiché est v2).
    @Published var errorMessageV2: String?
    /// L'utilisateur a demandé à explorer l'app pendant que le bilan se fait
    /// attendre : la gate plein écran (`AnalysisGateView`) ne se rouvre plus de
    /// la session. Le bilan continue d'arriver en tâche de fond.
    @Published var gateContournee = false
    /// Le journal et la prise de sang, qui entrent dans le hash du bilan, ont
    /// été lus au moins une fois. Sans eux, le hash serait faux.
    private var donneesDuBilanChargees = false
    /// La dernière lecture du journal ou de la prise de sang a échoué (réseau).
    /// Le hash calculé ainsi est faux : on ne régénère pas un bilan déjà là
    /// sur cette base, sinon le serveur garde ce hash faux et la prochaine
    /// ouverture normale régénère encore (incident du 7 oct. 2026).
    private var donneesDuBilanIncompletes = false
    /// Le récap animé attend le bilan pour se jouer.
    ///
    /// Armé UNIQUEMENT à la fin du questionnaire, jamais au lancement : sinon
    /// tout utilisateur déjà installé se serait pris la séquence en pleine
    /// figure à la première ouverture après mise à jour. Il se rejoue à la
    /// demande depuis le profil (« Revoir mon bilan animé »).
    @Published var recapArme = false

    // MARK: - Injected Services

    private let authService: AuthServiceProtocol
    private let databaseService: DatabaseServiceProtocol
    private let subscriptionService: SubscriptionServiceProtocol
    private let analyticsService: AnalyticsServiceProtocol
    private let aiAnalysisService: AIAnalysisServiceProtocol
    let gamificationService: GamificationService

    // MARK: - Entrée libre (V12a)

    /// Bilan complété — point d'observation UNIQUE pour toutes les vues.
    /// Source : `questionnaire_data.completed` du profil, portée par le
    /// @Published `hasCompletedQuestionnaire` (mis à jour immédiatement à la
    /// soumission du questionnaire, sans relance de l'app). Alias sémantique :
    /// le nouveau code lit `bilanComplete`, l'existant reste inchangé.
    var bilanComplete: Bool { hasCompletedQuestionnaire }

    /// Décision fondateur (V12a) : aucune porte premium tant que le bilan
    /// n'est pas fait. Toutes les cartes / pills / portes paywall se
    /// conditionnent ici plutôt que sur `!isPremium` copié partout.
    var premiumVisible: Bool { bilanComplete && !subscriptionService.isPremium }

    /// Lance (ou reprend) le bilan depuis n'importe quel onglet. Le draft du
    /// questionnaire est restauré par QuestionnaireViewModel — la reprise se
    /// fait à la question en cours. À la fermeture de la feuille,
    /// l'utilisateur retrouve l'onglet d'où il est parti.
    func demarrerBilan() {
        questionnaireOuvert = true
    }

    // MARK: - État d'affichage de l'onglet Bilan (V12b)

    /// Route du contenu de l'onglet Bilan — miroir EXACT du switch historique
    /// de `DashboardView.content`, extrait ici pour être testable sans UI.
    enum BilanAffichage {
        /// Bilan v2 valide → le dashboard v7 avec les vraies données.
        case bilan
        /// Questionnaire complété, bilan pas encore là (chargement / erreur).
        case attente
        /// Pas encore de bilan → le dashboard v7 en mode découverte (teaser
        /// in-situ V12b : stats France sourcées + CTA questionnaire).
        case decouverte
    }

    var bilanAffichage: BilanAffichage {
        if let v2 = analysisV2, v2.isValidV2 { return .bilan }
        if profile.completed { return .attente }
        return .decouverte
    }

    // MARK: - Computed (PhysicalMetrics)

    var physicalMetrics: PhysicalMetrics {
        PhysicalMetrics(profile: profile)
    }

    // MARK: - Computed (Analysis)

    /// Nutriments affichés par le Dashboard. L'analyse IA enrichit les scores
    /// locaux quand elle est disponible ; sinon on affiche les scores LOCAUX
    /// seuls (HealthCalculator) — le bilan ne doit JAMAIS être vide ou à 0
    /// quand le questionnaire est complété (incident TestFlight 28).
    ///
    /// Un seul chiffre par apport : le v7 est calculé sur le questionnaire
    /// seul ; ses textes restent, mais le score et le statut sont ceux du
    /// registre (journal et prise de sang compris), comme la fiche et la toile.
    /// Audit de fiabilité du 8 oct. 2026 : le Plan et le PDF lisaient un autre
    /// chiffre que la fiche.
    var nutrients: [EnrichedNutrient] {
        guard let merged = aiAnalysis else { return localNutrients }
        return merged.nutrients.map { nutriment in
            guard let score = nutrientScores[nutriment.id] else { return nutriment }
            var aligne = nutriment
            aligne.score = score
            aligne.status = NutrientStatus(score: score).rawValue
            return aligne
        }
    }

    /// Nutriments construits uniquement à partir des scores locaux
    /// (déterministes) — affichés pendant le chargement de l'analyse IA
    /// ou quand elle échoue. Labels/emojis/couleurs : catalogue canonique.
    private var localNutrients: [EnrichedNutrient] {
        guard profile.completed, !nutrientScores.isEmpty else { return [] }
        return NutrientData.all.map { def in
            let score = nutrientScores[def.id.rawValue] ?? 50
            return EnrichedNutrient(
                id: def.id.rawValue,
                label: def.label,
                emoji: def.emoji,
                color: def.colorHex,
                score: score,
                status: NutrientStatus(score: score).rawValue,
                confidence: score < 40 ? "high" : score < 60 ? "moderate" : "low"
            )
        }
    }

    var topDeficiencies: [EnrichedNutrient] {
        Array(deficiencies.prefix(3))
    }

    /// Red flags : ceux du merge IA si disponible, sinon détection LOCALE
    /// (RedFlagDetector est un mirror déterministe de health.js — les alertes
    /// de sécurité ne doivent pas attendre l'analyse IA).
    var redFlags: [RedFlag] {
        if let merged = aiAnalysis { return merged.redFlags }
        guard profile.completed else { return [] }
        return RedFlagDetector.detect(profile: profile)
    }

    var summaryHeadline: String? {
        aiAnalysis?.summary?.headline
    }

    var overallScore: Int {
        aiAnalysis?.overallScore ?? (healthScore / 10)
    }

    var deficiencies: [EnrichedNutrient] {
        // Apports estimés (audit de fiabilité, 8 oct. 2026) : le STATUT dit ce
        // qui est sous la référence, les alertes sûres d'abord. Sans statut,
        // l'échelle HealthScale : « Solide » commence à 70.
        let statuts = self.statuts
        guard !statuts.isEmpty else {
            return nutrients.filter { $0.score < 70 }.sorted { $0.score < $1.score }
        }
        func rang(_ s: StatutApport?) -> Int { s == .aRenforcer ? 0 : (s == .aSurveiller ? 1 : 2) }
        return nutrients
            .filter { statuts[$0.id]?.estSousLaReference == true }
            .sorted { (rang(statuts[$0.id]), $0.score) < (rang(statuts[$1.id]), $1.score) }
    }

    var goodNutrients: Int {
        let statuts = self.statuts
        guard !statuts.isEmpty else { return nutrients.filter { $0.score >= 70 }.count }
        return nutrients.filter { statuts[$0.id].map { !$0.estSousLaReference } ?? ($0.score >= 70) }.count
    }

    var interactionsCount: Int {
        aiAnalysis?.interactions.count ?? 0
    }

    var actionDuJour: (titre: String, description: String?)? {
        // Priority 1: AI action_du_jour (not in current model, use priority_actions)
        if let actions = aiAnalysis?.priorityActions, let first = actions.sorted(by: { ($0.rank ?? 0) < ($1.rank ?? 0) }).first {
            return (titre: first.action ?? "Consulte ton plan", description: first.expectedImpact)
        }
        // Priority 2: First deficiency solution
        if let def = deficiencies.first, let sol = def.solution?.action {
            return (titre: sol, description: "Pour ameliorer ton \(def.label)")
        }
        return nil
    }

    var pepiteDuJour: PracticalTip? {
        let pepites = aiAnalysis?.pepites ?? []
        guard !pepites.isEmpty else { return nil }
        // Deterministic daily rotation
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return pepites[dayOfYear % pepites.count]
    }

    /// Le prénom à afficher. Une seule lettre n'en est pas un (`Prenom`).
    var firstName: String {
        Prenom.affichable(profile.firstName)
    }

    // MARK: - Private

    private var reconnectObserver: Any?
    private var initTask: Task<Void, Never>?
    /// Email du profil chargé — réutilisé lors des UPDATE ciblés (ex. avatar)
    /// pour ne pas écraser la colonne `email` avec une chaîne vide.
    private var loadedEmail: String = ""

    // MARK: - Init

    init(
        auth: AuthServiceProtocol = AuthService.shared,
        database: DatabaseServiceProtocol = DatabaseService.shared,
        subscription: SubscriptionServiceProtocol = SubscriptionService.shared,
        analytics: AnalyticsServiceProtocol = AnalyticsService.shared,
        aiAnalysis: AIAnalysisServiceProtocol = AIAnalysisService.shared,
        gamification: GamificationService = GamificationService.shared
    ) {
        self.authService = auth
        self.databaseService = database
        self.subscriptionService = subscription
        self.analyticsService = analytics
        self.aiAnalysisService = aiAnalysis
        self.gamificationService = gamification

        initTask = Task {
            await loadProfile()
        }
        // Filet de sécurité : ne JAMAIS piéger l'utilisateur sur l'écran de
        // chargement racine si le fetch profil traîne (réseau cassé, SDK bloqué).
        // Passé 8 s, on autorise le routing avec l'état dont on dispose — même
        // esprit que le garde-fou de 10 s d'`AuthViewModel.isLoading`.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.didFinishInitialLoad = true
        }
        observeReconnect()
    }

    deinit {
        initTask?.cancel()
        if let observer = reconnectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Reconnect Observer

    /// Re-triggers AI analysis when the network comes back after an offline period.
    /// Only fires if the bilan (v2, réellement affiché) n'a pas encore de résultat
    /// et que le questionnaire est complet, so a successful cached state is never
    /// disrupted. Gardé sur `analysisV2` (pas `aiAnalysis`/v7) depuis l'incident du
    /// 4 juillet — sinon un raté v7 seul peut redéclencher un appel inutile alors
    /// que le vrai bilan (v2) est déjà là.
    private func observeReconnect() {
        reconnectObserver = NotificationCenter.default.addObserver(
            forName: .healthmapDidReconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.hasCompletedQuestionnaire, self.analysisV2 == nil else { return }
            Task { @MainActor in
                AppLogger.analysis.info("Reconnect: retrying AI analysis")
                await self.triggerAnalysis()
            }
        }
    }

    // MARK: - Load Profile

    func loadProfile() async {
        // Re-entrancy guard: prevent concurrent loads from init Task +
        // explicit call from QuestionnaireContainerView or reconnect.
        guard !isLoadingProfile else { return }

        guard let session = await AuthService.shared.currentSession else {
            // Pas de session résolue : on a « essayé », on débloque le routing
            // pour ne pas rester coincé sur l'écran de chargement racine.
            didFinishInitialLoad = true
            return
        }

        let userId = session.user.id.uuidString
        isLoadingProfile = true
        errorMessage = nil

        do {
            if let profileRow = try await databaseService.loadProfile(userId: userId) {
                self.loadedEmail = profileRow.email ?? self.loadedEmail
                if let questionnaireData = profileRow.questionnaireData {
                    self.profile = questionnaireData
                    self.hasCompletedQuestionnaire = questionnaireData.completed
                } else {
                    self.profile = .empty
                    self.hasCompletedQuestionnaire = false
                }
                // Le prénom déjà connu du compte (inscription par e-mail OU Sign
                // in with Apple → `profiles.first_name`) complète le questionnaire
                // quand celui-ci n'en porte pas, pour ne PAS le redemander (App
                // Review Guideline 4). Posé HORS du `else` : `questionnaire_data`
                // n'est jamais nul en base (défaut `{}`), la branche du dessus ne
                // s'exécutait donc jamais, et le prénom de l'inscription était
                // redemandé à tout le monde.
                self.profile.firstName = Prenom.retenu(
                    questionnaire: self.profile.firstName,
                    compte: profileRow.firstName
                )
                // `baseline_nutrient_scores` est une colonne sœur de
                // `questionnaire_data` (pas imbriquée dedans) : on la fusionne
                // manuellement dans le profil en mémoire.
                self.profile.baselineNutrientScores = profileRow.baselineNutrientScores
            }
        } catch {
            errorMessage = "Impossible de charger ton profil pour le moment."
            AppLogger.database.report(error, context: "Dashboard load profile")
        }

        isLoadingProfile = false

        // Le journal des repas corrige les apports (étape 3) : lu AVANT le hash
        // du bilan, qui en dépend. Un échec laisse le seul questionnaire parler.
        if hasCompletedQuestionnaire {
            await chargerDonneesDuBilan(userId: userId)
        }

        // Pose le DERNIER bilan connu, MÊME si son hash n'est plus le bon —
        // AVANT de débloquer le routing et de lancer l'analyse. Le hash dépend
        // des repas des 14 derniers jours : noter un repas suffisait à le
        // changer, et l'app rouvrait alors sur l'écran « 2 à 3 minutes »
        // (incident du 7 oct. 2026). Désormais la gate plein écran ne s'ouvre
        // que pour un tout premier bilan ; un bilan périmé reste affiché et
        // `triggerAnalysis()` le remplace en arrière-plan (« Mise à jour de
        // l'analyse… »). Lecture DB pure — aucun appel IA.
        if hasCompletedQuestionnaire, analysisV2 == nil {
            await poserDernierBilanConnu(userId: userId)
        }

        #if DEBUG
        // Captures d'écran (workflow `screenshots.yml`) : avec l'argument de
        // lancement `-captureDecouverte`, le compte d'audit se comporte comme
        // un compte sans questionnaire (Journal « avant questionnaire »,
        // onglets en découverte, porte vers le questionnaire). Jamais en
        // Release : le bloc n'existe pas dans le binaire App Store.
        if ProcessInfo.processInfo.arguments.contains("-captureDecouverte") {
            profile.completed = false
            hasCompletedQuestionnaire = false
            analysisV2 = nil
            aiAnalysis = nil
            gateContournee = true
            didFinishInitialLoad = true
            analyticsService.track(.dashboardViewed, properties: nil)
            return
        }
        #endif

        // Le statut de routing (`hasCompletedQuestionnaire`) est désormais
        // connu → on peut afficher la bonne branche sans clignotement.
        didFinishInitialLoad = true

        // Compute local scores immediately (deterministic, no async needed)
        computeLocalScores()

        // Cross-platform sync: merge streaks from web (healthmap.fr)
        // Runs concurrently — does not block AI analysis loading
        Task { await gamificationService.configure(userId: userId) }

        // If questionnaire completed, trigger AI analysis
        if hasCompletedQuestionnaire {
            await triggerAnalysis()
        }

        analyticsService.track(.dashboardViewed, properties: nil)
    }

    // MARK: - Compute Local Scores

    /// Computes health scores from the local profile without a server call.
    /// Called from `loadProfile()` and from the questionnaire submission
    /// flow to populate the dashboard immediately without waiting for a re-fetch.
    func computeLocalScores() {
        // Garde sur `profile.completed` (PAS sur hasCompletedQuestionnaire) :
        // à la soumission du questionnaire, le flag publié reste false tant
        // que la célébration est affichée (il pilote le switch d'onglet dans
        // MainTabView) — mais les scores doivent déjà être calculables.
        // Bug TestFlight 28 : l'ancienne garde laissait healthScore à 0 →
        // célébration « 0/100 » avec croix.
        guard profile.completed else {
            healthScore = 0
            nutrientScores = [:]
            estimation = nil
            return
        }

        healthScore = HealthCalculator.calculateHealthScore(profile: profile)
        estimation = EstimateurApports.partage?.estimer(ProfilEstimation(profile: profile), journees: journeesNotees)
        nutrientScores = registre.mapValues(\.score)
        alignerBilan()

        captureBaselineIfNeeded()
    }

    // MARK: - Le registre, corrigé par le journal (étape 3, 22 sept. 2026)

    /// Le registre des apports de la personne : son questionnaire, puis ce que
    /// ses repas notés ont montré. TOUS les écrans le lisent ici, jamais en
    /// rappelant `HealthCalculator.registreApports` : sinon la fiche et le
    /// tableau de bord ne diraient pas le même chiffre.
    var registre: [String: DetailApport] {
        PriseDeSangApports.appliquer(registreSansPriseDeSang, priseDeSang: priseDeSang)
    }

    /// Questionnaire + journal, sans la prise de sang. Depuis l'audit de
    /// fiabilité (8 oct. 2026), c'est l'estimation en vraies quantités : ses
    /// sources tiennent lieu de contributions, le chiffre est la part de la
    /// référence couverte. L'ancien registre en points ne sert plus que de
    /// repli si le référentiel est illisible.
    private var registreSansPriseDeSang: [String: DetailApport] {
        guard let estimation, profile.completed else {
            return JournalApports.appliquer(HealthCalculator.registreApports(profile: profile), observations: observationsJournal)
        }
        let profil = ProfilEstimation(profile: profile)
        var sortie: [String: DetailApport] = [:]
        for nutriment in NutrientID.allCases {
            let id = nutriment.rawValue
            guard let e = estimation.apports[id] else { continue }
            sortie[id] = LectureEstimation.detail(id, e, profil: profil)
        }
        return sortie
    }

    /// Le statut de chaque apport estimé : ce que l'app peut affirmer. Une
    /// prise de sang récente prime sur l'estimation, sauf pour le calcium et
    /// le magnésium, que le corps tient serrés dans le sang.
    var statuts: [String: StatutApport] {
        guard let estimation else { return [:] }
        var sortie = estimation.apports.mapValues(\.statut)
        guard let priseDeSang, PriseDeSangApports.fraicheur(priseDeSang) > 0 else { return sortie }
        for (id, statut) in sortie where statut != .couvertParComplement {
            guard let m = PriseDeSangApports.marqueur(pour: id, dans: priseDeSang) else { continue }
            let regule = PriseDeSangApports.marqueursRegules.contains(m.code)
            switch m.position {
            case .sousRepere: sortie[id] = .aRenforcer
            case .basDuRepere where !regule: sortie[id] = .aSurveiller
            case .dansRepere where !regule, .auDessus where !regule: sortie[id] = .couvert
            default: break
            }
        }
        return sortie
    }

    /// Les trois apports du bilan rédigé portent le statut et le chiffre du
    /// calcul local : un seul chiffre, un seul statut partout.
    private func alignerBilan() {
        guard var bilan = analysisV2, var apports = bilan.bilan?.apports, !apports.isEmpty else { return }
        let statuts = self.statuts
        guard !statuts.isEmpty else { return }
        for index in apports.indices {
            guard let id = apports[index].id else { continue }
            if let statut = statuts[id] { apports[index].statut = statut.statutV2 }
            if let score = nutrientScores[id] { apports[index].pctBesoin = score }
        }
        bilan.bilan?.apports = apports
        alignementEnCours = true
        analysisV2 = bilan
        alignementEnCours = false
    }

    /// Le hash du bilan : le profil, la version du calcul, ce que le journal
    /// puis la prise de sang changent aux scores (par paliers de 5 points), et
    /// la date de la prise de sang — le bilan la cite.
    var hashDuBilan: String {
        // Le calcul estimé : le bilan se refait quand un statut change, ou
        // quand le journal déplace un chiffre d'un palier de 10.
        if let estimation, profile.completed {
            let statuts = self.statuts
            let signature = NutrientID.allCases.compactMap { nutriment -> String? in
                let id = nutriment.rawValue
                guard let e = estimation.apports[id] else { return nil }
                let palier = Int((Double(LectureEstimation.couverture(e)) / Double(JournalApports.palierDuBilan)).rounded()) * JournalApports.palierDuBilan
                return "\(id)=\((statuts[id] ?? e.statut).rawValue)/\(palier)"
            }.joined(separator: ",")
            return AIAnalysisService.hashProfile(
                profile,
                journal: estimation.journeesRetenues > 0 ? signature : "",
                sang: PriseDeSangApports.signatureDuBilan(priseDeSang, scores: signature)
            )
        }
        let questionnaire = HealthCalculator.registreApports(profile: profile)
        let avecJournal = JournalApports.appliquer(questionnaire, observations: observationsJournal)
        let signature = JournalApports.signature(avant: questionnaire, apres: avecJournal)
        let signatureSang = JournalApports.signature(
            avant: avecJournal,
            apres: PriseDeSangApports.appliquer(avecJournal, priseDeSang: priseDeSang)
        )
        return AIAnalysisService.hashProfile(
            profile,
            journal: signature,
            sang: PriseDeSangApports.signatureDuBilan(priseDeSang, scores: signatureSang)
        )
    }

    // MARK: - La prise de sang (Premium, 30 sept. 2026)

    /// Lit la prise de sang la plus récente. Un échec laisse le calcul sans
    /// elle, sans message : comme le journal, elle corrige, elle ne bloque pas.
    /// Rend `false` si la lecture a échoué (réseau), `true` sinon — y compris
    /// quand il n'y a simplement aucune prise de sang.
    @discardableResult
    func chargerPriseDeSang(userId: String) async -> Bool {
        let derniere: PriseDeSang?
        do {
            derniere = try await PriseDeSangService.shared.derniere(userId: userId)
        } catch {
            return false
        }
        guard let derniere else { return true }
        priseDeSang = derniere
        // Le rappel des 6 mois se planifie sans le bilan en main (retour au
        // premier plan, onglet Progrès) : la date lui est laissée ici.
        RappelsPersonnalises.memoriserPriseDeSang(derniere.date)
        return true
    }

    /// Lit tout ce qui entre dans le hash du bilan, en plus du profil : le
    /// journal des repas et la prise de sang. Retient si une lecture a échoué.
    func chargerDonneesDuBilan(userId: String) async {
        let journalLu = await chargerJournal(userId: userId)
        let sangLu = await chargerPriseDeSang(userId: userId)
        donneesDuBilanChargees = true
        donneesDuBilanIncompletes = !(journalLu && sangLu)
    }

    /// Pose le dernier bilan enregistré, quel que soit son hash : mieux vaut
    /// un bilan d'hier à l'écran que trois minutes d'attente. Le hash ne sert
    /// qu'à décider s'il faut le refaire, en arrière-plan.
    /// Jamais juste après le questionnaire : le récap animé attend le NOUVEAU
    /// bilan, il ne doit pas se jouer sur l'ancien.
    private func poserDernierBilanConnu(userId: String) async {
        // `(try? …) ?? nil` aplatit le double-optionnel (la fonction rend déjà
        // `AIAnalysisV2?`) — même motif que dans AIAnalysisService.fetchBilanV2.
        guard analysisV2 == nil, !recapArme,
              let cached = (try? await databaseService.loadAIAnalysisV2(userId: userId)) ?? nil,
              cached.isValidV2
        else { return }
        analysisV2 = cached
    }

    /// La prise de sang a changé (import, suppression) : le rappel des 6 mois
    /// suit, tout de suite.
    private func replanifierRappelPriseDeSang() {
        RappelsPersonnalises.memoriserPriseDeSang(priseDeSang?.date)
        Task { await RappelsPersonnalises.replanifier() }
    }

    /// Ce que la prise de sang change à chaque apport : le score sans elle,
    /// puis avec elle. Seuls les apports qu'elle a déplacés, dans l'ordre du
    /// canon. Vide avant le questionnaire (aucun score à corriger).
    func effetsPriseDeSang() -> [PriseDeSangApports.Effet] {
        guard profile.completed, priseDeSang != nil else { return [] }
        let sans = registreSansPriseDeSang
        let avec = registre
        return NutrientData.all.compactMap { def in
            let id = def.id.rawValue
            guard let a = sans[id]?.score, let b = avec[id]?.score, a != b else { return nil }
            return PriseDeSangApports.Effet(id: id, avant: a, apres: b)
        }
    }

    /// Une prise de sang vient d'être lue : les scores se refont aussitôt, et
    /// le bilan se régénère (son hash a changé) pour en tenir compte.
    func poserPriseDeSang(_ nouvelle: PriseDeSang?) {
        // La plus récente fait foi : un vieux bilan importé après coup ne
        // remplace pas une mesure plus fraîche.
        if let nouvelle, let actuelle = priseDeSang, nouvelle.id != actuelle.id, nouvelle.takenAt < actuelle.takenAt {
            return
        }
        priseDeSang = nouvelle
        computeLocalScores()
        replanifierRappelPriseDeSang()
        Task { await retryBilanV2() }
    }

    /// La personne efface sa prise de sang : la ligne disparaît du serveur,
    /// puis du calcul.
    func supprimerPriseDeSang() async throws {
        guard let actuelle = priseDeSang else { return }
        try await PriseDeSangService.shared.supprimer(id: actuelle.id)
        priseDeSang = nil
        if let session = await AuthService.shared.currentSession {
            await chargerPriseDeSang(userId: session.user.id.uuidString)
        }
        computeLocalScores()
        replanifierRappelPriseDeSang()
        Task { await retryBilanV2() }
    }

    /// Lit les repas notés des 14 derniers jours (aujourd'hui compris) et en
    /// tire les observations. Un échec réseau laisse le calcul au seul
    /// questionnaire, sans message : le journal corrige, il ne bloque jamais.
    /// Rend `false` si la lecture a échoué.
    @discardableResult
    func chargerJournal(userId: String) async -> Bool {
        let calendrier = Calendar.current
        let aujourdhui = calendrier.startOfDay(for: Date())
        guard let debut = calendrier.date(byAdding: .day, value: -(JournalApports.fenetreJours - 1), to: aujourdhui),
              let demain = calendrier.date(byAdding: .day, value: 1, to: aujourdhui),
              let repas = try? await MealJournalService.shared.loadRange(userId: userId, from: debut, to: demain)
        else { return false }
        // Même mesure que le Journal : la composition exacte des aliments
        // quand la base la connaît, ce que le repas avait enregistré sinon.
        let compositions = await CompositionsStore.shared.completer(pour: repas)
        journeesNotees = LectureEstimation.journees(MesuresRepas.journees(repas: repas, compositions: compositions))
        observationsJournal = JournalApports.observations(
            repas: MesuresRepas.repasPrecises(repas, compositions: compositions),
            profil: profile
        )
        return true
    }

    /// Un repas vient d'être noté, modifié ou retiré : les chiffres se refont
    /// tout de suite (demande d'Arthur du 1er octobre 2026). Le bilan rédigé,
    /// lui, attend le prochain lancement : on ne rappelle pas l'IA à chaque repas.
    func rafraichirApresUnRepas() async {
        guard profile.completed, let session = await AuthService.shared.currentSession else { return }
        await chargerJournal(userId: session.user.id.uuidString)
        computeLocalScores()
        // Le repas noté a corrigé le registre : « Tes apports » et le conseil
        // du jour des widgets suivent.
        SynchroWidgets.apportsRecalcules(self)
    }

    #if DEBUG
    /// Tests : pose des observations sans passer par le réseau.
    func poserObservationsJournal(_ observations: ObservationsJournal?) {
        observationsJournal = observations
    }

    /// Tests : pose des journées notées sans passer par le réseau.
    func poserJourneesNotees(_ journees: [JourneeNotee]) {
        journeesNotees = journees
    }

    /// Tests : pose une prise de sang sans réseau ni bilan.
    func poserPriseDeSangPourTest(_ prise: PriseDeSang?) {
        priseDeSang = prise
    }
    #endif

    // MARK: - Capture one-time de la baseline nutriments

    /// Fige la photo « départ » des scores nutriments au tout premier bilan.
    /// Le check `baselineNutrientScores == nil` garantit une exécution unique :
    /// une fois écrite, la colonne n'est jamais réécrite. Met aussi à jour la
    /// copie en mémoire du profil pour que la barre de couverture utilise la
    /// baseline dès le premier affichage. Non bloquant : un échec d'écriture
    /// n'est que loggué (l'utilisateur retentera au prochain chargement).
    private func captureBaselineIfNeeded() {
        guard profile.baselineNutrientScores == nil, !nutrientScores.isEmpty else { return }

        let baseline = nutrientScores
        // Copie en mémoire immédiate (la barre l'utilise tout de suite).
        profile.baselineNutrientScores = baseline

        Task { [databaseService] in
            guard let session = await AuthService.shared.currentSession else { return }
            let userId = session.user.id.uuidString
            do {
                try await databaseService.saveBaselineNutrientScores(userId: userId, scores: baseline)
            } catch {
                AppLogger.database.report(error, context: "Capture baseline nutrient scores")
            }
        }
    }

    // MARK: - Trigger AI Analysis

    func triggerAnalysis() async {
        // Même logique que computeLocalScores : l'analyse doit pouvoir démarrer
        // pendant la célébration post-questionnaire, avant le flip du flag UI.
        guard profile.completed else { return }
        // Re-entrancy guard: prevent concurrent analysis calls from
        // reconnect observer + loadProfile() + manual retry.
        guard !isLoadingAnalysis else { return }

        guard let session = await AuthService.shared.currentSession else {
            return
        }

        let userId = session.user.id.uuidString
        isLoadingAnalysis = true
        // Clear any previous error so the retry UI disappears immediately
        // when the user taps "Reessayer" — without this, the error card
        // would stay on screen overlapping the loading spinner.
        errorMessage = nil

        analyticsService.track(.analysisStarted, properties: nil)

        // Bilan v2 : part EN PARALLÈLE de l'appel v7 (deux tâches distinctes
        // sur le même endpoint). v2 nourrit le nouvel écran Bilan et n'est pas
        // bloqué par le v7 ; il gère son propre état (isLoadingAnalysisV2).
        Task { await self.fetchBilanV2(userId: userId, forceRefresh: false) }

        do {
            let merged = try await aiAnalysisService.fetchFullAnalysis(
                userId: userId,
                profile: profile
            )

            self.aiAnalysis = merged

            // Update scores from merged result (canonical source)
            if let merged {
                self.healthScore = merged.healthScore
                // Le v7 renvoie les scores du seul questionnaire : on garde
                // ceux du registre, corrigés par le journal.
                self.nutrientScores = registre.mapValues(\.score)

                analyticsService.track(.analysisCompleted, properties: [
                    "health_score": healthScore,
                    "deficiencies_count": merged.topDeficiencies.count,
                ])
            } else {
                // Réponse IA inexploitable (nil après sanitization/validation) :
                // ce n'est PAS un succès. Les scores locaux restent affichés,
                // mais le bandeau de retry doit apparaître — jamais d'état
                // silencieux sans analyse ni erreur (incident TestFlight 28).
                errorMessage = "L'analyse n'a pas pu être générée. Tes scores restent disponibles, réessaie dans un instant."
                analyticsService.track(.analysisFailed, properties: [
                    "error": "nil_analysis_after_validation",
                ])
            }
        } catch {
            AppLogger.analysis.report(error, context: "Dashboard AI analysis")
            analyticsService.track(.analysisFailed, properties: [
                "error": error.localizedDescription,
            ])
            // Surface a user-facing message ONLY if we have nothing cached.
            // If `aiAnalysis` is non-nil (a previous successful run), the
            // user keeps seeing the cached dashboard and we silently fail.
            if aiAnalysis == nil {
                // Fallback: attempt to load the last cached analysis from Supabase.
                // The cached row is a raw AIAnalysisResponse. We can't re-merge it
                // here (mergeWithCanonical is internal to AIAnalysisService), but
                // loading via the service's own fetch path re-uses the cache check
                // that runs before hitting the edge function. If the DB itself is
                // unreachable we surface the user-facing error.
                do {
                    let cachedResponse = try await databaseService.loadAIAnalysis(userId: userId)
                    if cachedResponse != nil {
                        // The service will find the cached row and skip the edge call
                        // since the profile hash hasn't changed.
                        let retried = try await aiAnalysisService.fetchFullAnalysis(userId: userId, profile: profile)
                        if let retried {
                            self.aiAnalysis = retried
                            self.healthScore = retried.healthScore
                            self.nutrientScores = registre.mapValues(\.score)
                            AppLogger.analysis.info("Loaded cached analysis as fallback after AI failure")
                        } else {
                            errorMessage = "Impossible de charger ton analyse pour le moment. Vérifie ta connexion puis réessaie."
                        }
                    } else {
                        errorMessage = "Impossible de charger ton analyse pour le moment. Vérifie ta connexion puis réessaie."
                    }
                } catch {
                    errorMessage = "Impossible de charger ton analyse pour le moment. Vérifie ta connexion puis réessaie."
                    AppLogger.analysis.report(error, context: "Dashboard fallback cache load")
                }
            }
            // Local scores remain available even if AI fails — the
            // deterministic computeLocalScores() in loadProfile already
            // populated `healthScore` so the score ring still works.
        }

        isLoadingAnalysis = false
    }

    // MARK: - Bilan v2 (contrat v2 — nouvel écran Bilan)

    /// Charge le bilan v2 : cache DB d'abord (géré par le service), sinon
    /// Edge Function (tache "bilan"). Tourne en parallèle du flux v7.
    private func fetchBilanV2(userId: String, forceRefresh: Bool) async {
        // Mêmes gardes que triggerAnalysis : l'analyse doit pouvoir démarrer
        // pendant la célébration post-questionnaire.
        guard profile.completed else { return }
        // Re-entrancy guard (reconnect + loadProfile + regenerate).
        guard !isLoadingAnalysisV2 else { return }
        isLoadingAnalysisV2 = true
        errorMessageV2 = nil
        defer { isLoadingAnalysisV2 = false }

        // Le hash dépend du journal et de la prise de sang : sans eux (bilan
        // lancé à la fin du questionnaire, onglet Plan ouvert avant la fin du
        // chargement, lecture ratée), il serait faux. On les lit d'abord.
        if !donneesDuBilanChargees || donneesDuBilanIncompletes {
            await chargerDonneesDuBilan(userId: userId)
        }
        // Un bilan est déjà là : on l'affiche le temps qu'il se refasse, sans
        // jamais rouvrir la gate plein écran.
        await poserDernierBilanConnu(userId: userId)
        // Lecture du journal ou de la prise de sang ratée : le hash est faux.
        // On garde le bilan affiché plutôt que d'en payer un nouveau, que le
        // serveur enregistrerait sous ce hash faux.
        if !forceRefresh, donneesDuBilanIncompletes, analysisV2 != nil {
            AppLogger.analysis.info("Bilan v2 : journal ou prise de sang illisible, bilan affiché conservé")
            return
        }

        // Entrées déterministes — mêmes sources locales que le flux v7
        // (HealthCalculator / RedFlagDetector, mirrors de health.js).
        let localScores = registre.mapValues(\.score)
        let localHealthScore = HealthCalculator.calculateHealthScore(profile: profile)
        let localFlags = RedFlagDetector.detect(profile: profile)
        let profileHash = hashDuBilan

        do {
            // Protégé : quitter l'app pendant la génération lui laisse ~30 s
            // de plus pour aboutir.
            analysisV2 = try await TacheProtegee.executer("Bilan") {
                try await aiAnalysisService.fetchBilanV2(
                    userId: userId,
                    profileHash: profileHash,
                    scores: localScores,
                    statuts: statuts.mapValues(\.codeServeur),
                    healthScore: localHealthScore,
                    redFlags: localFlags,
                    forceRefresh: forceRefresh
                )
            }
        } catch {
            AppLogger.analysis.report(error, context: "Dashboard bilan v2")
            // Surface une erreur exploitable par la gate onboarding UNIQUEMENT
            // si on n'a rien à montrer (pas de cache valide) — sinon le bilan
            // déjà affiché ne doit pas être remplacé par un bandeau d'erreur.
            if analysisV2 == nil {
                errorMessageV2 = (error as? AIAnalysisError)?.errorDescription
                    ?? "Impossible de charger ton bilan pour le moment. Réessaie dans un instant."
            }
        }
    }

    /// Relance le SEUL bilan v2 — celui que l'écran affiche réellement.
    ///
    /// ⚠️ Ne PAS rebrancher le « Réessayer » de la gate sur `triggerAnalysis()` :
    /// celui-ci commence par `guard !isLoadingAnalysis`, or les deux flux
    /// partent ensemble et le v7 tient jusqu'à 185 s. Le v2 pouvant échouer en
    /// deux secondes (429, circuit ouvert), le bouton restait un no-op
    /// totalement silencieux pendant tout ce temps.
    func retryBilanV2() async {
        guard let session = await AuthService.shared.currentSession else { return }
        await fetchBilanV2(userId: session.user.id.uuidString, forceRefresh: false)
    }

    // MARK: - Save Avatar Choice

    /// Persiste l'avatar morphologique choisi dans `questionnaire_data` (JSONB)
    /// sans toucher email/first_name. UPDATE uniquement (policy RLS).
    func saveAvatarKey(_ key: String) {
        profile.avatarKey = key
        Task {
            guard let session = await AuthService.shared.currentSession else { return }
            let userId = session.user.id.uuidString
            let email = session.user.email ?? loadedEmail
            do {
                try await databaseService.saveProfile(
                    userId: userId,
                    email: email,
                    firstName: profile.firstName,
                    questionnaireData: profile
                )
            } catch {
                AppLogger.database.report(error, context: "Save avatar key")
            }
        }
    }

    // MARK: - Poids actuel et poids souhaité (Journal)

    /// Enregistre les deux poids réglés depuis le Journal (valeurs telles
    /// qu'elles s'écrivent dans le profil, voir `ObjectifPoids.stockage`). Si
    /// l'écriture échoue, le profil retrouve ses valeurs d'avant : l'écran ne
    /// ment pas sur ce qui est enregistré.
    func enregistrerPoids(actuel: String, souhaite: String) async {
        let avant = (actuel: profile.weight, souhaite: profile.targetWeight)
        guard avant.actuel != actuel || avant.souhaite != souhaite else { return }
        profile.weight = actuel
        profile.targetWeight = souhaite
        do {
            guard let session = await AuthService.shared.currentSession else {
                throw HealthMapError.auth(.sessionExpired)
            }
            try await databaseService.saveProfile(
                userId: session.user.id.uuidString,
                email: session.user.email ?? loadedEmail,
                firstName: profile.firstName,
                questionnaireData: profile
            )
            // Le poids pèse sur les besoins, donc sur les apports : on recalcule.
            computeLocalScores()
        } catch {
            // Réglage repris pendant l'écriture : le pas suivant enregistrera.
            guard !Task.isCancelled else { return }
            profile.weight = avant.actuel
            profile.targetWeight = avant.souhaite
            ToastService.shared.confirmer("Poids non enregistré. Vérifie ta connexion et réessaie.")
            AppLogger.database.report(error, context: "Save weight")
        }
    }
}
