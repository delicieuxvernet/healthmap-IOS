import Foundation

@MainActor
final class QuestionnaireViewModel: ObservableObject {

    // MARK: - Published State

    /// Index plat de la question courante dans `visibleQuestions` (toutes
    /// sections confondues). Le flux UI est "une question par écran" (Lot D) :
    /// la navigation se fait question par question, plus section par section.
    @Published var currentQuestionIndex: Int = 0
    @Published var profile: UserProfile = .empty
    @Published var pathway: UserProfile.Pathway = .express
    /// Blocs « profonds » (questions au-delà de l'express) que l'utilisateur a
    /// choisi d'approfondir via un carrefour. Le tronc commun = questions
    /// express ; chaque carrefour déverrouille un bloc (nutrition / symptômes /
    /// médical). Parcours adaptatif (remplace le choix express/complet).
    @Published var unlockedDeepSections: Set<QuestionnaireSection> = []
    /// Ids des questions que l'utilisateur a RÉELLEMENT renseignées d'un geste.
    /// Distinct de `isAnswered`, qui compte un champ à valeur par défaut (gender,
    /// smoking, dietType) comme répondu : c'est ce suivi qui permet de n'afficher
    /// AUCUNE présélection sur une question à choix unique tant que l'utilisateur
    /// n'a pas choisi (fini le « Homme » déjà coché).
    @Published private(set) var interactedQuestionIds: Set<String> = []
    /// Le compte connaît déjà le prénom (inscription par e-mail, Sign in with
    /// Apple) : la question « prénom » n'est pas posée (App Review, Gl. 4).
    ///
    /// Figé à l'ouverture du questionnaire par `adopterPrenomDuCompte`, jamais
    /// dérivé du champ en cours de saisie : sinon la question disparaît à la
    /// première lettre tapée. Non persisté dans le draft, recalculé à chaque
    /// ouverture.
    @Published private(set) var prenomConnuDuCompte = false
    /// Écran courant du parcours en quatre étapes (refonte du 1er oct. 2026,
    /// voir `ParcoursBilan`). Persisté dans le draft : on reprend là où on
    /// s'est arrêté.
    @Published private(set) var ecran: EcranBilan = .accueil
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    /// L'âge choisi est sous le minimum (`AgeMinimum`) : rien n'est gardé, ni
    /// l'âge ni le brouillon, et l'écran ne laisse pas avancer.
    @Published private(set) var sousAgeMinimum = false

    // MARK: - Draft persistence
    /// Local UserDefaults key used to survive an app kill mid-questionnaire.
    /// Follows the `healthmap_*` prefix convention so it's wiped automatically
    /// by `AuthViewModel.clearLocalCaches()` on sign out — that way a new
    /// account can never inherit a previous user's partial answers.
    private static let draftKey = "healthmap_questionnaire_draft"
    /// Clé du draft CHIFFRÉ (AES-256-GCM via SecureStorageService, clé en Keychain).
    /// Le questionnaire contient des données de santé (RGPD art.9) : médicaments,
    /// conditions, symptômes — jamais en clair au repos. `draftKey` ci-dessus n'est
    /// conservé que pour purger d'éventuels anciens drafts en clair (migration).
    private static let draftSecureKey = "questionnaire_draft"

    /// On-disk shape of the draft. Versioned (`schema`) so a future breaking
    /// change to `UserProfile` can cleanly discard old drafts instead of
    /// crashing during decode.
    /// `userId` was added in schema v2 to prevent cross-user draft leaks.
    private struct Draft: Codable {
        let schema: Int
        let userId: String?
        /// Index de section historique (flux par section, pré-Lot D). Toujours
        /// écrit pour rester lisible par d'anciennes versions de l'app ; plus
        /// utilisé à la restauration (on se repositionne par question).
        let currentSectionIndex: Int
        /// Id de la question courante (flux une-question-par-écran, Lot D).
        /// Optionnel pour que les drafts v2 existants décodent sans crash —
        /// absent, on retombe sur la première question non répondue.
        let currentQuestionId: String?
        let profile: UserProfile
        let pathway: UserProfile.Pathway
        /// Blocs profonds déverrouillés (rawValues de QuestionnaireSection) —
        /// parcours adaptatif (schema v4). Optionnel pour le décodage robuste.
        let unlockedDeepSections: [Int]?
        /// Ids des questions réellement renseignées par l'utilisateur. Optionnel :
        /// un ancien draft sans ce champ décode et on dérive à la reprise.
        let interactedQuestionIds: [String]?
        /// Écran courant du parcours en quatre étapes (`EcranBilan.rawValue`).
        /// Optionnel : un draft d'avant la refonte décode, et on reprend alors
        /// au premier écran qui n'est pas terminé.
        let currentScreenId: String?
        let savedAt: Date
    }
    /// Bumped 1→2 (userId), 2→3 (refonte nutrition "Faites vos courses"),
    /// 3→4 (parcours adaptatif : le choix express/complet est remplacé par les
    /// blocs déverrouillables `unlockedDeepSections`). Les drafts v3 sont écartés.
    private static let draftSchemaVersion = 4

    // MARK: - Init
    init() {
        restoreDraftIfAvailable()
    }

    // MARK: - Computed

    var sections: [QuestionnaireSection] {
        QuestionnaireSection.allCases
    }

    /// Nombre total de sections — conservé pour l'event analytics
    /// `questionnaire_completed` (propriété `sections_count`).
    var totalSections: Int {
        sections.count
    }

    /// Questions visibles d'une section donnée, filtrées par le parcours
    /// Express/Complet et les conditions showIf.
    func visibleQuestions(in section: QuestionnaireSection) -> [Question] {
        section.questions.filter { question in
            // Tronc commun = questions express. Les questions « profondes »
            // (non-express) n'apparaissent que si l'utilisateur a déverrouillé
            // ce bloc via son carrefour (parcours adaptatif).
            let isExpress = QuestionnaireSection.expressKeys.contains(question.id)
            if !isExpress && !unlockedDeepSections.contains(section) {
                return false
            }

            // showIf conditional visibility
            if let showIf = question.showIf, !showIf(profile) {
                return false
            }

            // Le prénom n'est pas redemandé quand le compte le connaît déjà.
            if question.id == "firstName" && prenomConnuDuCompte {
                return false
            }

            return true
        }
    }

    /// Reprend le prénom que le compte connaît déjà et retire la question
    /// correspondante du parcours. Appelé à l'ouverture du questionnaire.
    ///
    /// Le prénom du compte l'emporte sur celui d'un draft : la question étant
    /// masquée, la personne n'a aucun moyen de corriger une valeur restée là
    /// (une lettre seule, typiquement), et c'est elle qui partirait en base.
    func adopterPrenomDuCompte(_ prenom: String) {
        let courante = currentQuestion?.id
        profile.firstName = prenom
        guard !prenomConnuDuCompte else { return }
        prenomConnuDuCompte = true
        // La liste visible vient de perdre une question : on reste sur la même.
        if let courante, let index = visibleQuestions.firstIndex(where: { $0.id == courante }) {
            currentQuestionIndex = index
        }
        // Même chose pour le parcours en quatre étapes : son écran « prénom »
        // vient de sortir de la liste.
        if ecran == .prenom {
            ecran = ParcoursBilan.suivant(apres: .prenom, contexteBilan) ?? .reperes
        }
    }

    // MARK: - Carrefours d'approfondissement (parcours adaptatif)

    /// Blocs profonds proposés via carrefour, dans l'ordre du flux
    /// (alimentation → symptômes → médical).
    static let deepGateSections: [QuestionnaireSection] = [.nutrition, .symptomes, .medical]

    /// La section a-t-elle des questions profondes (non-express) pertinentes
    /// (showIf inclus) à proposer ?
    func hasDeepContent(_ section: QuestionnaireSection) -> Bool {
        section.questions.contains { q in
            !QuestionnaireSection.expressKeys.contains(q.id) && (q.showIf?(profile) ?? true)
        }
    }

    /// Prochain bloc profond verrouillé à proposer en carrefour — nil si plus
    /// aucun (l'utilisateur peut alors terminer).
    var nextLockedGate: QuestionnaireSection? {
        Self.deepGateSections.first { !unlockedDeepSections.contains($0) && hasDeepContent($0) }
    }

    /// Déverrouille un bloc profond (« Analyser… ») et repositionne le flux sur
    /// sa première question (le carrefour remplace l'intro de section).
    func unlockDeep(_ gate: QuestionnaireSection) {
        unlockedDeepSections.insert(gate)
        let questions = visibleQuestions
        if let idx = questions.firstIndex(where: {
            section(of: $0) == gate && !QuestionnaireSection.expressKeys.contains($0.id)
        }) {
            currentQuestionIndex = idx
        }
        saveDraft()
    }

    /// Liste APLATIE de toutes les questions visibles, toutes sections
    /// confondues. Recalculée à chaque accès : une réponse peut révéler ou
    /// cacher des questions suivantes (ex. caffeineIntake → caffeineTiming,
    /// gender → periodFlow/pregnancyStatus) — le compteur s'ajuste en direct.
    var visibleQuestions: [Question] {
        sections.flatMap { visibleQuestions(in: $0) }
    }

    /// Nombre total de questions visibles (dénominateur du compteur).
    var totalQuestions: Int {
        visibleQuestions.count
    }

    /// Question affichée à l'écran. Clampée sur la dernière question si la
    /// liste a rétréci suite à un changement de réponse (showIf).
    var currentQuestion: Question? {
        let questions = visibleQuestions
        guard !questions.isEmpty else { return nil }
        return questions[min(currentQuestionIndex, questions.count - 1)]
    }

    /// Numéro 1-based de la question courante (numérateur du compteur).
    var currentQuestionNumber: Int {
        guard totalQuestions > 0 else { return 0 }
        return min(currentQuestionIndex, totalQuestions - 1) + 1
    }

    /// Section à laquelle appartient une question. Scan linéaire — les
    /// sections sont petites (≤23 questions), le coût est négligeable.
    func section(of question: Question) -> QuestionnaireSection {
        sections.first(where: { section in
            section.questions.contains(where: { $0.id == question.id })
        }) ?? .profil
    }

    /// Section de la question courante (libellé du header).
    var currentSection: QuestionnaireSection {
        currentQuestion.map { section(of: $0) } ?? .profil
    }

    /// Progress from 0 to 1 — pourcentage sur l'ensemble des questions visibles.
    var progress: Double {
        guard totalQuestions > 0 else { return 0 }
        return Double(currentQuestionNumber) / Double(totalQuestions)
    }

    /// Nombre de questions visibles dans la SECTION courante.
    var totalQuestionsInSection: Int {
        visibleQuestions(in: currentSection).count
    }

    /// Position 1-based de la question courante DANS sa section.
    var currentQuestionNumberInSection: Int {
        guard let q = currentQuestion else { return 0 }
        let inSection = visibleQuestions(in: currentSection)
        guard let idx = inSection.firstIndex(where: { $0.id == q.id }) else { return 0 }
        return idx + 1
    }

    /// Progression 0→1 DANS la section courante (la barre du header n'est plus
    /// globale). Repart de 0 à chaque nouvelle section. Basée sur (position-1)/N :
    /// la 1re question vaut 0 ; le dernier segment est rempli par l'animation de
    /// fin de section au moment de valider (SectionCompletionOverlay).
    var sectionProgress: Double {
        let total = totalQuestionsInSection
        guard total > 0 else { return 0 }
        return Double(currentQuestionNumberInSection - 1) / Double(total)
    }

    var isFirstQuestion: Bool {
        currentQuestionIndex == 0
    }

    var isLastQuestion: Bool {
        currentQuestionIndex >= totalQuestions - 1
    }

    // MARK: - Pathway Selection

    func selectPathway(_ selected: UserProfile.Pathway) {
        pathway = selected
        profile.pathway = selected
        currentQuestionIndex = 0

        // Track pathway in gamification so the "Explorer" badge unlocks once
        // both `express` and `complet` have been tried at least once.
        GamificationService.shared.recordPathway(selected.rawValue)

        AnalyticsService.shared.track(.questionnairePathwayChosen, properties: [
            "pathway": selected.rawValue,
        ])
        AnalyticsService.shared.track(.questionnaireStarted, properties: [
            "pathway": selected.rawValue,
        ])

        saveDraft()
    }

    // MARK: - Navigation (une question par écran)

    /// Avance d'une question dans la liste aplatie. Retourne la section
    /// nouvellement entamée si ce pas franchit une frontière de section
    /// (la vue affiche alors un écran d'intro), `nil` sinon.
    @discardableResult
    func nextQuestion() -> QuestionnaireSection? {
        let questions = visibleQuestions
        guard currentQuestionIndex < questions.count - 1 else { return nil }

        let fromSection = section(of: questions[currentQuestionIndex])
        currentQuestionIndex += 1
        let toSection = section(of: questions[currentQuestionIndex])

        if toSection != fromSection {
            AnalyticsService.shared.track(.questionnaireSectionCompleted, properties: [
                "section": fromSection.title,
                "index": fromSection.rawValue,
            ])
        }

        saveDraft()
        return toSection != fromSection ? toSection : nil
    }

    func previousQuestion() {
        guard currentQuestionIndex > 0 else { return }
        currentQuestionIndex -= 1
        saveDraft()
    }

    // MARK: - Update Answers

    /// Update a single-value answer by question ID (maps to UserProfile property)
    /// Un brouillon d'avant la mise à jour peut porter 14 ou 15 ans : on le
    /// voit dès la reprise. L'âge est retiré, le brouillon effacé, et la
    /// reprise retombe sur l'écran de l'âge (il n'est plus complet), où le
    /// message s'affiche.
    func verifierAgeRepris() {
        guard AgeMinimum.estSousLeMinimum(profile.age) else { return }
        sousAgeMinimum = true
        profile.age = ""
        Self.clearDraft()
    }

    /// L'âge de la molette. Sous 16 ans, aucune collecte : l'âge n'est pas
    /// enregistré et le brouillon déjà écrit sur le téléphone est effacé.
    func choisirAge(_ ans: Int) {
        guard AgeMinimum.estAtteint(ans) else {
            sousAgeMinimum = true
            profile.age = ""
            Self.clearDraft()
            return
        }
        sousAgeMinimum = false
        updateAnswer(questionId: "age", value: String(ans))
    }

    func updateAnswer(questionId: String, value: Any) {
        switch questionId {
        // Section 1: Profil
        case "goals":
            if let arr = value as? [String] { profile.goals = arr }
        case "firstName":
            if let str = value as? String { profile.firstName = str }
        case "age":
            if let str = value as? String { profile.age = str }
        case "gender":
            if let str = value as? String, let g = UserProfile.Gender(rawValue: str) { profile.gender = g }
        case "height":
            if let str = value as? String {
                if !str.isEmpty, Double(str) == nil {
                    errorMessage = "La taille doit être un nombre valide (ex. 175)."
                    return
                }
                profile.height = str
            }
        case "weight":
            if let str = value as? String {
                if !str.isEmpty, Double(str) == nil {
                    errorMessage = "Le poids doit être un nombre valide (ex. 70)."
                    return
                }
                profile.weight = str
            }
        case "weightTrend":
            if let str = value as? String { profile.weightTrend = str }

        // Section 2: Mode de vie
        case "indoorWork":
            if let str = value as? String { profile.indoorWork = str }
        case "sunExposure":
            if let str = value as? String { profile.sunExposure = str }
        case "skinType":
            if let str = value as? String { profile.skinType = str }
        case "strengthTraining":
            if let str = value as? String { profile.strengthTraining = str }

        // Section 3: Sante
        case "stressLevel":
            if let str = value as? String { profile.stressLevel = str }
        case "sleepHours":
            if let str = value as? String { profile.sleepHours = str }
        case "sleepDuration":
            if let str = value as? String { profile.sleepDuration = str }
        case "wakeFeeling":
            if let str = value as? String { profile.wakeFeeling = str }
        case "screenBeforeBed":
            if let str = value as? String { profile.screenBeforeBed = str }
        case "caffeineIntake":
            if let str = value as? String { profile.caffeineIntake = str }
        case "caffeineTiming":
            if let str = value as? String { profile.caffeineTiming = str }
        case "waterIntake":
            if let str = value as? String { profile.waterIntake = str }
        case "smoking":
            if let str = value as? String {
                profile.smoking = str == "yes" ? .yes : .no
            }
        case "alcohol":
            if let str = value as? String { profile.alcohol = str }
        case "bloating":
            if let str = value as? String { profile.bloating = str }
        case "antibiotics":
            if let str = value as? String { profile.antibiotics = str }

        // Section 4: Nutrition
        case "dietType":
            if let str = value as? String { profile.dietType = str }
        case "mealsPerDay":
            if let str = value as? String { profile.mealsPerDay = str }
        case "mealFrequency":
            if let str = value as? String { profile.mealFrequency = str }
        case "homeCookedPct":
            if let str = value as? String { profile.homeCookedPct = str }
        case "cookingMethod":
            if let str = value as? String { profile.cookingMethod = str }
        case "vegetableServings":
            if let str = value as? String { profile.vegetableServings = str }
        case "fruitServings":
            if let str = value as? String { profile.fruitServings = str }
        case "fattyFish":
            if let str = value as? String { profile.fattyFish = str }
        case "meatPoultry":
            if let str = value as? String { profile.meatPoultry = str }
        case "eggsPerWeek":
            if let str = value as? String { profile.eggsPerWeek = str }
        case "dairyServings":
            if let str = value as? String { profile.dairyServings = str }
        case "legumesPerWeek":
            if let str = value as? String { profile.legumesPerWeek = str }
        case "nutsPerWeek":
            if let str = value as? String { profile.nutsPerWeek = str }
        case "seedsPerDay":
            if let str = value as? String { profile.seedsPerDay = str }
        case "wholegrainPerWeek":
            if let str = value as? String { profile.wholegrainPerWeek = str }
        case "breadType":
            if let str = value as? String { profile.breadType = str }
        case "fermentedFoods":
            if let str = value as? String { profile.fermentedFoods = str }
        case "ultraProcessedFrequency":
            if let str = value as? String { profile.ultraProcessedFrequency = str }
        case "snacking":
            if let str = value as? String { profile.snacking = str }
        case "saltLevel":
            if let str = value as? String { profile.saltLevel = str }
        case "iodizedSalt":
            if let str = value as? String { profile.iodizedSalt = str }
        case "eatLiver":
            if let str = value as? String { profile.eatLiver = str }
        case "lowCarbDiet":
            if let str = value as? String { profile.lowCarbDiet = str }
        case "supplementsCurrent":
            if let arr = value as? [String] { profile.supplementsCurrent = arr }

        // Section 5: Symptomes
        case "symptoms":
            if let arr = value as? [String] { profile.symptoms = arr }

        // Section 6: Medical
        case "medications":
            if let arr = value as? [String] { profile.medications = arr }
        case "digestiveConditions":
            if let arr = value as? [String] { profile.digestiveConditions = arr }
        case "digestiveIssues":
            if let arr = value as? [String] { profile.digestiveIssues = arr }
        case "surgicalHistory":
            if let arr = value as? [String] { profile.surgicalHistory = arr }
        case "medicalHistory":
            if let arr = value as? [String] { profile.medicalHistory = arr }
        case "allergies":
            if let arr = value as? [String] { profile.allergies = arr }
        case "periodFlow":
            if let str = value as? String { profile.periodFlow = str }
        case "pregnancyStatus":
            if let str = value as? String { profile.pregnancyStatus = str }

        default:
            AppLogger.ui.warning("Unknown question ID: \(questionId, privacy: .public)")
        }

        // La réponse vient d'un geste explicite → on la marque comme renseignée
        // (les retours anticipés ci-dessus, ex. taille/poids invalides, l'évitent).
        interactedQuestionIds.insert(questionId)
        saveDraft()
    }

    // MARK: - Precisions
    // Mirrors the web `precisions.*` structure from Home.jsx and is
    // consumed by the generate-analysis Edge Function.
    func updatePrecision(key: String, value: [String]) {
        if profile.precisions == nil {
            profile.precisions = UserProfile.Precisions()
        }
        let cleaned = value.isEmpty ? nil : value
        switch key {
        case "vegetableServings": profile.precisions?.vegetables = cleaned
        case "fruitServings":     profile.precisions?.fruits = cleaned
        case "meatPoultry":       profile.precisions?.meat = cleaned
        case "dairyServings":     profile.precisions?.dairy = cleaned
        case "wholegrainPerWeek": profile.precisions?.grains = cleaned
        default: break
        }

        saveDraft()
    }

    // MARK: - Groceries ("Faites vos courses")

    /// Écrit le caddie de l'utilisateur (id aliment GroceryCatalog -> portions
    /// par semaine). Source de la partie nutrition du nouveau questionnaire.
    func updateGroceries(_ groceries: [String: Int]) {
        profile.groceries = groceries
        saveDraft()
    }

    // MARK: - Lecture des réponses
    // Pendants LECTURE de `updateAnswer` (écriture). Utilisés par la vue pour
    // afficher la sélection courante, et par la restauration de draft pour
    // retrouver la première question non répondue.

    /// Valeur à AFFICHER comme sélectionnée sur une question à choix unique :
    /// `nil` tant que l'utilisateur n'a pas fait un vrai choix, même si le champ
    /// profil porte une valeur par défaut. C'est ce qui supprime la présélection.
    func displaySingleChoiceValue(for questionId: String) -> String? {
        guard interactedQuestionIds.contains(questionId) else { return nil }
        return stringValue(for: questionId)
    }

    /// Valeur single-choice courante d'une question (nil si non mappée).
    func stringValue(for questionId: String) -> String? {
        switch questionId {
        case "gender": return profile.gender.rawValue
        case "weightTrend": return profile.weightTrend
        case "indoorWork": return profile.indoorWork
        case "sunExposure": return profile.sunExposure
        case "skinType": return profile.skinType
        case "strengthTraining": return profile.strengthTraining
        case "stressLevel": return profile.stressLevel
        case "sleepHours": return profile.sleepHours
        case "wakeFeeling": return profile.wakeFeeling
        case "screenBeforeBed": return profile.screenBeforeBed
        case "caffeineIntake": return profile.caffeineIntake
        case "caffeineTiming": return profile.caffeineTiming
        case "waterIntake": return profile.waterIntake
        case "smoking": return profile.isSmoker ? "yes" : "no"
        case "alcohol": return profile.alcohol
        case "bloating": return profile.bloating
        case "antibiotics": return profile.antibiotics
        case "dietType": return profile.dietType
        case "mealsPerDay": return profile.mealsPerDay
        case "homeCookedPct": return profile.homeCookedPct
        case "cookingMethod": return profile.cookingMethod
        case "breadType": return profile.breadType
        case "fermentedFoods": return profile.fermentedFoods
        case "ultraProcessedFrequency": return profile.ultraProcessedFrequency
        case "snacking": return profile.snacking
        case "saltLevel": return profile.saltLevel
        case "iodizedSalt": return profile.iodizedSalt
        case "eatLiver": return profile.eatLiver
        case "lowCarbDiet": return profile.lowCarbDiet
        case "periodFlow": return profile.periodFlow
        case "pregnancyStatus": return profile.pregnancyStatus
        default: return nil
        }
    }

    /// Valeurs multi-choice courantes d'une question.
    func arrayValue(for questionId: String) -> [String] {
        switch questionId {
        case "goals": return profile.goals
        case "supplementsCurrent": return profile.supplementsCurrent
        case "symptoms": return profile.symptoms
        case "medications": return profile.medications
        case "digestiveConditions": return profile.digestiveConditions
        case "surgicalHistory": return profile.surgicalHistory
        case "medicalHistory": return profile.medicalHistory
        case "allergies": return profile.allergies
        default: return []
        }
    }

    /// Texte courant d'une question saisie (texte, numérique ou slider).
    func inputText(for questionId: String) -> String {
        switch questionId {
        case "firstName": return profile.firstName
        case "age": return profile.age
        case "height": return profile.height
        case "weight": return profile.weight
        case "vegetableServings": return profile.vegetableServings
        case "fruitServings": return profile.fruitServings
        case "fattyFish": return profile.fattyFish
        case "meatPoultry": return profile.meatPoultry
        case "eggsPerWeek": return profile.eggsPerWeek
        case "dairyServings": return profile.dairyServings
        case "legumesPerWeek": return profile.legumesPerWeek
        case "nutsPerWeek": return profile.nutsPerWeek
        case "seedsPerDay": return profile.seedsPerDay
        case "wholegrainPerWeek": return profile.wholegrainPerWeek
        default: return ""
        }
    }

    /// Une question compte comme répondue dès que son champ profil n'est plus
    /// vide. Les champs avec valeur par défaut (gender, smoking, dietType,
    /// periodFlow, pregnancyStatus) comptent donc comme répondus — c'est le
    /// comportement d'affichage existant : l'option par défaut apparaît déjà
    /// présélectionnée à l'écran.
    func isAnswered(_ question: Question) -> Bool {
        switch question.type {
        case .singleChoice:
            return !(stringValue(for: question.id) ?? "").isEmpty
        case .multiChoice:
            return !arrayValue(for: question.id).isEmpty
        case .textInput, .numericInput:
            return !inputText(for: question.id).isEmpty
        case .groceries:
            return !profile.groceries.isEmpty
        }
    }

    /// Index de la première question non répondue — point de reprise après
    /// restauration d'un draft. Si tout est répondu, renvoie la dernière
    /// question (l'utilisateur n'a plus qu'à terminer).
    func firstUnansweredQuestionIndex() -> Int {
        let questions = visibleQuestions
        guard let index = questions.firstIndex(where: { !isAnswered($0) }) else {
            return max(questions.count - 1, 0)
        }
        return index
    }

    // MARK: - Parcours en quatre étapes (refonte du 1er octobre 2026)
    //
    // La navigation écran par écran du nouveau questionnaire. Toutes les règles
    // (ordre, écrans visibles, ce qu'il faut avoir répondu pour avancer) vivent
    // dans `ParcoursBilan` ; ici, seulement l'état et les écritures. Les
    // réponses passent par `updateAnswer`, comme avant : mêmes clés, mêmes
    // valeurs, même brouillon chiffré.

    /// Ce dont `ParcoursBilan` a besoin pour décider.
    var contexteBilan: ContexteBilan {
        ContexteBilan(
            profil: profile,
            renseignees: interactedQuestionIds,
            prenomConnu: prenomConnuDuCompte,
            approfondi: !unlockedDeepSections.isEmpty
        )
    }

    /// Vrai quand l'écran courant a toutes ses réponses : le bouton s'allume.
    /// Un écran qui vient de sortir du parcours ne retient jamais personne.
    var ecranComplet: Bool {
        let contexte = contexteBilan
        return !ParcoursBilan.visible(ecran, contexte) || ParcoursBilan.estComplet(ecran, contexte)
    }

    /// « encore ~2 min », pour l'en-tête. Vide sur le dernier écran.
    var resteDuParcours: String {
        ParcoursBilan.texteReste(
            secondes: ParcoursBilan.secondesRestantes(depuis: ecran, contexteBilan)
        )
    }

    /// Ce que le mode de vie dit déjà de chaque apport.
    var lectureBilan: LectureBilan {
        PistesBilan.lecture(profil: profile)
    }

    /// La carte à montrer sous les réponses d'un écran. Celle des besoins
    /// attend que les quatre repères soient donnés.
    func carte(pour ecran: EcranBilan) -> CartePiste? {
        if ecran == .reperes && !ParcoursBilan.estComplet(.reperes, contexteBilan) { return nil }
        return PistesBilan.carte(pour: ecran, profil: profile)
    }

    /// La carte de l'écran courant.
    var carteDeLEcran: CartePiste? {
        carte(pour: ecran)
    }

    /// Ce que le Journal affiche pendant que le bilan attend.
    var repriseBilan: RepriseBilan? {
        ParcoursBilan.reprise(ecran: ecran, contexteBilan)
    }

    /// Avance d'un écran. Faux si l'écran n'est pas terminé, ou s'il n'y a
    /// plus rien après (c'est alors le moment d'envoyer).
    @discardableResult
    func ecranSuivant() -> Bool {
        guard ecranComplet else { return false }
        ecrireLesReponsesTacites()
        guard let suivant = ParcoursBilan.suivant(apres: ecran, contexteBilan) else { return false }

        // Une étape se termine quand on quitte sa dernière question, pas
        // quand on quitte son récapitulatif.
        if let etape = ecran.etape, !ecran.estFinDEtape,
           suivant.estFinDEtape || suivant.etape != etape {
            AnalyticsService.shared.track(.questionnaireSectionCompleted, properties: [
                "section": etape.titre,
                "index": etape.rawValue,
            ])
        }

        ecran = suivant
        saveDraft()
        return true
    }

    /// Recule d'un écran. Sans effet sur l'accueil.
    func ecranPrecedent() {
        guard let precedent = ParcoursBilan.precedent(avant: ecran, contexteBilan) else { return }
        ecran = precedent
        saveDraft()
    }

    /// Les onglets des repas : d'un repas à l'autre, dans n'importe quel ordre.
    func allerAu(repas: RepasBilan) {
        guard ecran.repas != nil,
              let cible = EcranBilan.allCases.first(where: { $0.repas == repas }) else { return }
        ecran = cible
        saveDraft()
    }

    /// Ce qu'un écran dit sans geste, écrit au moment de continuer : une
    /// bascule laissée éteinte vaut « non », une liste où rien n'est coché
    /// vaut « aucun ». Les valeurs sont celles des options existantes.
    private func ecrireLesReponsesTacites() {
        switch ecran {
        case .motif:
            aucunSiVide("symptoms", profile.symptoms)
            // Aucun objectif coché reste une liste vide : la question n'a pas
            // d'option « aucun ». Elle a été vue, elle compte comme répondue.
            interactedQuestionIds.insert("goals")
        case .prenom:
            // Les espaces tapés autour du prénom ne partent pas en base.
            let propre = profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            if propre != profile.firstName { profile.firstName = propre }
        case .soleil:
            nonSiVide("indoorWork", profile.indoorWork)
        case .alcoolTabac:
            if !interactedQuestionIds.contains("smoking") {
                updateAnswer(questionId: "smoking", value: "no")
            }
        case .ventre:
            nonSiVide("bloating", profile.bloating)
            nonSiVide("antibiotics", profile.antibiotics)
        case .jamais:
            aucunSiVide("allergies", profile.allergies)
        case .placard:
            nonSiVide("eatLiver", profile.eatLiver)
            nonSiVide("lowCarbDiet", profile.lowCarbDiet)
        case .complements:
            aucunSiVide("supplementsCurrent", profile.supplementsCurrent)
        case .traitements:
            aucunSiVide("medications", profile.medications)
        case .digestion:
            aucunSiVide("digestiveConditions", profile.digestiveConditions)
            aucunSiVide("surgicalHistory", profile.surgicalHistory)
        case .antecedents:
            aucunSiVide("medicalHistory", profile.medicalHistory)
        default:
            break
        }
    }

    private func nonSiVide(_ id: String, _ valeur: String) {
        if valeur.isEmpty { updateAnswer(questionId: id, value: "no") }
    }

    private func aucunSiVide(_ id: String, _ valeurs: [String]) {
        if valeurs.isEmpty { updateAnswer(questionId: id, value: ["none"]) }
    }

    /// Coche ou décoche une réponse d'une liste. La réponse « aucun »
    /// (`"none"`) et les autres s'excluent.
    func basculer(_ valeur: String, question id: String) {
        var courant = arrayValue(for: id)
        if valeur == "none" {
            courant = courant == ["none"] ? [] : ["none"]
        } else {
            courant.removeAll { $0 == "none" }
            if let index = courant.firstIndex(of: valeur) {
                courant.remove(at: index)
            } else {
                courant.append(valeur)
            }
        }
        updateAnswer(questionId: id, value: courant)
    }

    /// Le sexe décide si l'écran « ton cycle » existe. S'il disparaît, ses
    /// réponses repartent avec lui : sinon une grossesse cochée par erreur
    /// continuerait de peser sur le fer d'un homme.
    func choisirSexe(_ valeur: String) {
        updateAnswer(questionId: "gender", value: valeur)
        guard profile.gender != .femme else { return }
        profile.periodFlow = UserProfile.empty.periodFlow
        profile.pregnancyStatus = UserProfile.empty.pregnancyStatus
        interactedQuestionIds.subtract(["periodFlow", "pregnancyStatus"])
        saveDraft()
    }

    /// Le moment du café n'est demandé qu'à partir de trois par jour : en
    /// dessous, une réponse donnée plus tôt ne doit pas rester.
    func choisirCafe(_ valeur: String) {
        updateAnswer(questionId: "caffeineIntake", value: valeur)
        guard !ParcoursBilan.cafeDemandeLeMoment(profile), !profile.caffeineTiming.isEmpty else { return }
        profile.caffeineTiming = ""
        interactedQuestionIds.remove("caffeineTiming")
        saveDraft()
    }

    // MARK: Les aliments, en trois mots

    /// Le niveau enregistré pour cet aliment, `nil` s'il n'est pas coché.
    func niveau(de aliment: String) -> NiveauConsommation? {
        guard let portions = profile.groceries[aliment], portions > 0 else { return nil }
        return NiveauConsommation.depuis(portions: portions)
    }

    /// Coche un aliment, au niveau par défaut.
    func cocher(_ aliment: String) {
        regler(aliment, .parDefaut)
    }

    /// « Pas beaucoup, modérément, beaucoup » : écrit les portions par semaine.
    func regler(_ aliment: String, _ niveau: NiveauConsommation) {
        var caddie = profile.groceries
        caddie[aliment] = niveau.portions
        updateGroceries(caddie)
    }

    /// Décoche un aliment.
    func retirer(_ aliment: String) {
        var caddie = profile.groceries
        caddie.removeValue(forKey: aliment)
        updateGroceries(caddie)
    }

    // MARK: Affiner

    /// Vrai si la personne a répondu à cette question. Un champ qui porte une
    /// valeur par défaut ne compte que si elle l'a confirmée d'un geste.
    func aRepondu(_ question: Question) -> Bool {
        switch question.type {
        case .singleChoice:
            return interactedQuestionIds.contains(question.id)
                && !(stringValue(for: question.id) ?? "").isEmpty
        case .multiChoice:
            return interactedQuestionIds.contains(question.id)
                || !arrayValue(for: question.id).isEmpty
        case .textInput, .numericInput:
            return !inputText(for: question.id).isEmpty
        case .groceries:
            return !profile.groceries.isEmpty
        }
    }

    /// Combien de questions ont reçu une réponse, sur combien de posables à
    /// cette personne. C'est ce que dit l'écran de fin : un décompte, pas une
    /// note de précision qu'on ne saurait pas justifier.
    var decompteDesReponses: (repondues: Int, total: Int) {
        let posables = QuestionnaireSection.allQuestions.filter { $0.showIf?(profile) ?? true }
        let repondues = posables.filter { aRepondu($0) }.count
        return (repondues, posables.count)
    }

    private func toutEstRepondu(_ ecran: EcranBilan) -> Bool {
        ecran.questions.allSatisfy { id in
            guard let question = QuestionnaireSection.question(id: id) else { return true }
            if let visible = question.showIf, !visible(profile) { return true }
            return aRepondu(question)
        }
    }

    /// Vrai s'il reste des questions d'approfondissement sans réponse.
    var resteAAffiner: Bool {
        EcranBilan.allCases.contains { $0.estAffinage && !toutEstRepondu($0) }
    }

    /// « Affiner d'abord » : ouvre les écrans d'approfondissement et se place
    /// sur le premier qui attend encore une réponse. Le bilan devient
    /// « complet » au sens du champ `pathway`, comme avec les anciens carrefours.
    func affiner() {
        unlockedDeepSections = [.nutrition, .medical]
        let affinage = ParcoursBilan.ecrans(contexteBilan).filter { $0.estAffinage }
        ecran = affinage.first { !toutEstRepondu($0) } ?? affinage.first ?? .fin
        saveDraft()
    }

    // MARK: - Submit

    func submitQuestionnaire() async {
        // Double-tap guard: prevent concurrent submissions
        guard !isSubmitting else { return }

        // Moins de 16 ans : le bilan ne part jamais (`AgeMinimum`).
        if sousAgeMinimum || AgeMinimum.estSousLeMinimum(profile.age) {
            errorMessage = AgeMinimum.message
            return
        }

        // Force a session refresh to prevent JWT expiry during the update.
        // Supabase Auth rafraîchit normalement tout seul ; on force ici un
        // refresh explicite juste avant l'écriture critique.
        try? await AuthService.shared.refreshSession()

        guard let session = await AuthService.shared.currentSession else {
            errorMessage = "Tu dois être connecté pour envoyer ton questionnaire."
            return
        }

        isSubmitting = true
        errorMessage = nil

        let userId = session.user.id.uuidString
        let email = session.user.email ?? ""

        // Build the submission profile with completed=true, but do NOT mutate
        // self.profile yet — we only commit the flag AFTER the server confirms.
        // This prevents the optimistic flag from leaking to SwiftUI views
        // (which check profile.completed to switch to DashboardView) while the
        // network call is still in flight.
        // Parcours adaptatif : `pathway` est désormais DÉRIVÉ — express si
        // l'utilisateur n'a approfondi aucun bloc, complet sinon. Conserve la
        // sémantique du champ DB existant (web ↔ iOS).
        let derivedPathway: UserProfile.Pathway = unlockedDeepSections.isEmpty ? .express : .complet
        var submissionProfile = profile
        submissionProfile.completed = true
        submissionProfile.pathway = derivedPathway

        do {
            try await DatabaseService.shared.saveProfile(
                userId: userId,
                email: email,
                firstName: submissionProfile.firstName,
                questionnaireData: submissionProfile
            )

            // Server confirmed — NOW commit the flag to the published state
            profile.completed = true
            profile.pathway = derivedPathway

            AnalyticsService.shared.track(.questionnaireCompleted, properties: [
                "pathway": derivedPathway.rawValue,
                "sections_count": totalSections,
            ])

            // Unlock the "Bilan complet" badge on successful save.
            GamificationService.shared.unlockQuestionnaireComplete()

            // Draft has been persisted to the server — safe to drop the local
            // copy. Done AFTER the badge unlock so a crash between save and
            // badge would still leave the draft around for a retry.
            Self.clearDraft()
        } catch {
            // Map to a user-readable message based on the error type
            let desc = error.localizedDescription.lowercased()
            if desc.contains("offline") || desc.contains("network") || desc.contains("internet") {
                errorMessage = "Pas de connexion. Vérifie ton réseau puis réessaie."
            } else if desc.contains("timeout") {
                errorMessage = "Le serveur met trop de temps à répondre. Réessaie dans un instant."
            } else if desc.contains("401") || desc.contains("jwt") || desc.contains("token") {
                errorMessage = "Ta session a expiré. Reconnecte-toi puis réessaie."
            } else {
                errorMessage = "La sauvegarde a échoué. Réessaie dans un instant."
            }
            AppLogger.database.report(error, context: "Questionnaire submit — \(error)")
            // Intentionally keep the draft on failure so the user can retry
            // after reconnecting without losing their answers.
        }

        isSubmitting = false
    }

    // MARK: - Draft persistence helpers

    /// Serializes the current in-progress state and writes it to UserDefaults.
    /// Called after every state-changing method (pathway selection, answer
    /// update, precision update, question navigation). Failures are swallowed
    /// — if we can't write the draft, the user still gets the normal
    /// questionnaire flow; losing the draft is acceptable, crashing isn't.
    private func saveDraft() {
        // Don't write a draft while submission is in flight — the in-memory
        // profile state is in a transient state during the await, and writing
        // it to disk could persist inconsistent data (e.g. completed=true
        // from the submission copy leaking to the draft).
        guard !isSubmitting else { return }
        // Moins de 16 ans : rien ne s'écrit sur le téléphone (`AgeMinimum`).
        guard !sousAgeMinimum else { return }

        // Grab current userId synchronously from cached session if available.
        // Depuis Clerk : lookup sync dans le cache `ClerkProfileResolver`. nil
        // si l'async resolve n'a jamais tourné (boot à froid, fresh signin) —
        // on accepte : le draft sera juste non-scopé, la prochaine écriture
        // (dès que resolve async aura tourné) le re-scopera.
        let currentUserId = AuthService.shared.cachedCurrentUserIdString

        let draft = Draft(
            schema: Self.draftSchemaVersion,
            userId: currentUserId,
            currentSectionIndex: currentSection.rawValue,
            currentQuestionId: currentQuestion?.id,
            profile: profile,
            pathway: pathway,
            unlockedDeepSections: unlockedDeepSections.map { $0.rawValue },
            interactedQuestionIds: Array(interactedQuestionIds),
            currentScreenId: ecran.rawValue,
            savedAt: Date()
        )

        // Stockage CHIFFRÉ (AES-256-GCM + clé Keychain) — les données de santé du
        // questionnaire ne sont jamais écrites en clair sur le disque (RGPD art.32).
        SecureStorageService.shared.save(draft, forKey: Self.draftSecureKey)
        AppLogger.ui.debug("Questionnaire draft saved (question \(self.currentQuestionIndex, privacy: .public))")
    }

    /// Reads and decodes a previously saved draft. Called once from `init()`.
    /// Silently ignored if nothing is stored, if the schema version doesn't
    /// match (forward-compat: next schema bump drops old drafts cleanly),
    /// or if the stored payload is older than 30 days (we don't want a
    /// six-month-old draft to suddenly reappear — stale data is worse than
    /// no data for a health questionnaire).
    private func restoreDraftIfAvailable() {
        var draft: Draft? = SecureStorageService.shared.load(forKey: Self.draftSecureKey)

        // Migration : un ancien draft en clair (UserDefaults) est récupéré, re-chiffré,
        // puis purgé — pour ne plus jamais laisser de données de santé en clair au repos.
        if draft == nil,
           let legacy = UserDefaults.standard.data(forKey: Self.draftKey),
           let decoded = try? JSONDecoder().decode(Draft.self, from: legacy) {
            draft = decoded
            SecureStorageService.shared.save(decoded, forKey: Self.draftSecureKey)
        }
        UserDefaults.standard.removeObject(forKey: Self.draftKey)

        guard let draft else { return }

        guard draft.schema == Self.draftSchemaVersion else {
            AppLogger.ui.notice("Discarding draft with mismatched schema \(draft.schema, privacy: .public)")
            Self.clearDraft()
            return
        }

        // Cross-user safety: discard drafts that belong to a different
        // authenticated user. The clearLocalCaches() prefix sweep on sign-out is
        // the first line of defense; this check is the safety net. Drafts with NO
        // userId (legacy or saved during a token-refresh window) are also discarded.
        let currentUserId = AuthService.shared.cachedCurrentUserIdString
        guard let draftUserId = draft.userId, let currentUserId else {
            AppLogger.ui.notice("Discarding draft with missing userId (draft: \(draft.userId ?? "nil", privacy: .private(mask: .hash)), current: \(currentUserId ?? "nil", privacy: .private(mask: .hash)))")
            Self.clearDraft()
            return
        }
        if draftUserId != currentUserId {
            AppLogger.ui.notice("Discarding draft from different user (draft: \(draftUserId, privacy: .private(mask: .hash)) vs current: \(currentUserId, privacy: .private(mask: .hash)))")
            Self.clearDraft()
            return
        }

        // Guard against zombie drafts: a partially completed questionnaire from
        // months ago almost certainly no longer reflects the user's situation
        // (symptoms, weight, medications).
        let maxAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
        if Date().timeIntervalSince(draft.savedAt) > maxAge {
            AppLogger.ui.notice("Discarding draft older than 30 days")
            Self.clearDraft()
            return
        }

        self.profile = draft.profile
        self.pathway = draft.pathway
        self.unlockedDeepSections = Set((draft.unlockedDeepSections ?? []).compactMap { QuestionnaireSection(rawValue: $0) })

        // Reprise volontairement AU DÉBUT du questionnaire (décision produit,
        // 6 juil. 2026). Rouvrir l'app en plein flux ne doit plus rejeter
        // l'utilisateur au milieu (déroutant : il a oublié où il en était, ou
        // veut simplement recommencer / revenir en arrière). On restaure ses
        // réponses — rien n'est perdu, les sélections déjà faites restent
        // visibles — mais on repositionne le flux sur la première question :
        // il repart de la « home » du questionnaire et re-parcourt à son rythme.
        // `currentQuestionId` du draft est donc ignoré à dessein.
        self.currentQuestionIndex = 0
        // Suivi d'interaction : soit on relit ce qui a été explicitement
        // renseigné (draft récent), soit — vieux draft sans ce champ — on le
        // dérive des réponses non vides pour qu'un utilisateur qui reprend son
        // questionnaire retrouve ses sélections déjà faites.
        if let saved = draft.interactedQuestionIds {
            self.interactedQuestionIds = Set(saved)
        } else {
            self.interactedQuestionIds = Set(
                QuestionnaireSection.allCases
                    .flatMap { $0.questions }
                    .filter { isAnswered($0) }
                    .map { $0.id }
            )
        }
        // Âge sous le minimum dans le brouillon : vu AVANT de choisir l'écran
        // de reprise, qui retombe alors sur celui de l'âge.
        verifierAgeRepris()
        // Parcours en quatre étapes : on rouvre là où la personne s'est arrêtée,
        // sans jamais sauter un écran qu'elle n'a pas terminé.
        self.ecran = ParcoursBilan.ecranDeReprise(
            enregistre: draft.currentScreenId.flatMap { EcranBilan(rawValue: $0) },
            contexteBilan
        )
        AppLogger.ui.info("Questionnaire draft restored (answers kept, saved \(draft.savedAt, privacy: .public))")
    }

    /// Removes the stored draft. Called after a successful
    /// `submitQuestionnaire()` and when a draft is found to be invalid or
    /// stale. Static so it's callable from paths that don't have a view
    /// model instance (e.g. a hypothetical "discard my answers" button).
    static func clearDraft() {
        SecureStorageService.shared.remove(forKey: draftSecureKey)
        UserDefaults.standard.removeObject(forKey: draftKey) // purge legacy clair
        AppLogger.ui.debug("Questionnaire draft cleared")
    }
}
