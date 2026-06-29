import SwiftUI

// MARK: - Questionnaire Container View (Lot D — une question par écran)
//
// Flux façon Foodvisor, miroir du site web : chaque question occupe son
// propre écran, navigation par slide horizontal, header compact (chevron
// retour + progression globale + compteur), bouton primaire collé en bas.
// Des écrans d'intro légers rythment l'entrée dans chaque nouvelle section.
//
// La couche données (réponses, validation, draft, soumission) vit dans
// QuestionnaireViewModel — cette vue ne fait QUE la présentation.
struct QuestionnaireContainerView: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel
    @EnvironmentObject var dashboardVM: DashboardViewModel
    /// Carrefour d'approfondissement actuellement affiché (parcours adaptatif).
    /// nil = on affiche la question / l'intro de section.
    @State private var activeGate: QuestionnaireSection?
    @State private var hasTrackedStart = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - État du flux par question

    /// Section dont l'écran d'intro est affiché. `nil` = la question courante
    /// est affichée. Positionné quand `nextQuestion()` franchit une frontière
    /// de section ; remis à nil par « C'est parti » (ou le chevron retour).
    @State private var introSection: QuestionnaireSection?

    /// Direction de la dernière navigation — pilote le sens du slide
    /// (avance : entre par la droite ; retour : entre par la gauche).
    @State private var isNavigatingForward = true

    /// Auto-advance programmé après une réponse single-choice. Conservé pour
    /// pouvoir l'annuler si l'utilisateur re-tape (autre option, retour,
    /// Continuer) avant l'échéance des 350ms.
    @State private var autoAdvanceTask: Task<Void, Never>?

    /// Tracks whether we should show the submission error as an alert
    /// rather than inline text — an alert is impossible to miss.
    @State private var showSubmitError = false

    // MARK: - État des teasers (Lot E — carotte au bout du nez)

    /// Teaser affiché sur l'écran d'intro courant. `nil` = intro sans teaser.
    /// Choisi par `pickTeaserForIntro()` au moment où l'intro s'ouvre.
    @State private var introTeaser: Teaser?

    /// Ids des teasers déjà montrés dans la session — jamais deux fois le même.
    @State private var shownTeaserIds: Set<String> = []

    /// Vrai si l'intro précédente portait un teaser. Règle anti-spam :
    /// jamais deux intros d'affilée avec teaser.
    @State private var lastIntroShowedTeaser = false

    /// Libellé du bouton primaire selon l'étape : intro de section, question
    /// intermédiaire, ou dernière question (avec état d'envoi / retry).
    private var primaryButtonLabel: String {
        if introSection != nil { return "C'est parti" }
        if !viewModel.isLastQuestion { return "Continuer" }
        if viewModel.isSubmitting { return "Envoi en cours..." }
        if viewModel.errorMessage != nil { return "Reessayer" }
        // Dernière question visible : s'il reste un bloc à approfondir, on
        // propose le carrefour (« Continuer ») ; sinon on termine.
        return viewModel.nextLockedGate != nil ? "Continuer" : "Terminer"
    }

    var body: some View {
        ZStack {
            Color.healthMapBackground
                .ignoresSafeArea()

            if viewModel.isSubmitting {
                submittingView
            } else {
                questionFlow
            }
        }
        .onAppear {
            // Parcours unique adaptatif : plus d'écran de choix express/complet,
            // on démarre directement (draft restauré ou non). Trace le début une
            // seule fois par session.
            if !hasTrackedStart {
                hasTrackedStart = true
                AnalyticsService.shared.track(.questionnaireStarted, properties: nil)
            }
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
        }
        // Célébration post-questionnaire retirée le 28 juin 2026 : après la
        // dernière question on bascule directement sur le Bilan (écran de
        // chargement honnête) — cf. submitAndContinue().
    }

    // MARK: - Flux une question par écran
    private var questionFlow: some View {
        VStack(spacing: 0) {
            flowHeader

            // Étape courante : question OU intro de section. L'`.id(...)`
            // force SwiftUI à traiter chaque question comme une nouvelle vue,
            // ce qui déclenche la transition slide entre les écrans.
            ZStack {
                if let gate = activeGate {
                    // Carrefour d'approfondissement (remplace l'intro de section).
                    QuestionnaireGateView(
                        gate: gate,
                        onDeepen: { acceptGate(gate) },
                        onSkip: { skipGate() }
                    )
                    .transition(stepTransition)
                } else if let section = introSection {
                    SectionIntroView(
                        section: section,
                        questionCount: viewModel.visibleQuestions(in: section).count,
                        teaser: introTeaser
                    )
                    .transition(stepTransition)
                } else if let question = viewModel.currentQuestion {
                    questionScreen(for: question)
                        .id(question.id)
                        .transition(stepTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped() // les écrans qui slident ne débordent pas sur header/bouton

            // Le carrefour porte ses propres CTA (Analyser / Ignorer) → on masque
            // la barre du bas tant qu'il est affiché.
            if activeGate == nil {
                bottomBar
            }
        }
    }

    // MARK: - Header compact (retour + progression + compteur)
    private var flowHeader: some View {
        VStack(spacing: Theme.spacingXS) {
            HStack(spacing: Theme.spacingSM) {
                // Chevron retour 44×44pt (HIG). Masqué sur la toute première
                // question (même comportement que l'ancien bouton toolbar) —
                // le placeholder conserve l'alignement de la barre.
                if introSection != nil || !viewModel.isFirstQuestion {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.healthMapBlue)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel("Retour")
                } else {
                    Color.clear
                        .frame(width: 44, height: 44)
                }

                progressBar
                    .padding(.trailing, Theme.spacingMD)
            }

            HStack {
                Text("\(viewModel.currentSection.emoji) Section · \(viewModel.currentSection.title)")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapSecondary)

                Spacer()

                Text("Question \(viewModel.currentQuestionNumber)/\(viewModel.totalQuestions)")
                    .font(Theme.captionFont)
                    .monospacedDigit()
                    .foregroundStyle(Color.healthMapMuted)
            }
            .padding(.horizontal, Theme.spacingMD)
        }
        .padding(.horizontal, Theme.spacingSM)
        .padding(.top, Theme.spacingXS)
    }

    // MARK: - Progress Bar
    /// Barre fine de progression GLOBALE : pourcentage sur l'ensemble des
    /// questions visibles (le total s'ajuste si une réponse révèle ou cache
    /// des questions conditionnelles).
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.healthMapMuted.opacity(0.12))

                Capsule()
                    .fill(LinearGradient.healthMapBrand)
                    .frame(width: max(geo.size.width * viewModel.progress, 6))
                    .animation(reduceMotion ? .none : .healthMapSpring, value: viewModel.progress)
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progression du bilan")
        .accessibilityValue("\(Int((viewModel.progress * 100).rounded())) pour cent")
    }

    // MARK: - Écran question
    /// Plein écran, sans scroll pour la grande majorité des questions.
    /// ViewThatFits bascule sur un ScrollView discret UNIQUEMENT si le
    /// contenu déborde (Dynamic Type accessibilité, listes >6 options,
    /// chips de précision sous les sliders).
    private func questionScreen(for question: Question) -> some View {
        ViewThatFits(in: .vertical) {
            // Variante privilégiée : tout tient à l'écran, contenu centré.
            VStack(spacing: 0) {
                Spacer(minLength: Theme.spacingMD)
                questionContent(for: question)
                Spacer(minLength: Theme.spacingMD)
            }

            // Fallback : le contenu déborde → scroll discret.
            ScrollView(showsIndicators: false) {
                questionContent(for: question)
                    .padding(.vertical, Theme.spacingLG)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func questionContent(for question: Question) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            // Titre de la question — gros et lisible (suit Dynamic Type)
            Text(question.text)
                .font(Theme.titleFont)
                .brandTitleKerning()
                .foregroundStyle(Color.healthMapText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            answerControl(for: question)

            // Fun fact vivant (Lot E) — petite ligne animée sous le slider
            // (taille, âge) qui réagit en direct à la valeur. Purement
            // décoratif : aucun geste, aucun délai — ne retarde JAMAIS la
            // navigation ni l'auto-advance existant.
            if let config = sliderConfig(for: question.id), FunFactCatalog.hasFacts(for: question.id) {
                FunFactLabel(
                    questionId: question.id,
                    value: currentSliderValue(for: question.id, config: config)
                )
            }

            // Precision picker (multi-select chips) — appears under sliders
            // and numeric inputs for vegetables, fruits, meat, dairy, grains.
            // Mirrors the web `precisions.*` structure from Home.jsx.
            if !PrecisionCatalog.options(for: question.id).isEmpty {
                PrecisionPicker(
                    title: PrecisionCatalog.title(for: question.id),
                    options: PrecisionCatalog.options(for: question.id),
                    selection: precisionBinding(for: question.id)
                )
            }

            // Erreur inline (validation existante du ViewModel, ex. taille /
            // poids non numérique). L'erreur de soumission passe par l'alert.
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(Theme.captionFont)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Question View Router
    @ViewBuilder
    private func answerControl(for question: Question) -> some View {
        switch question.type {
        case .singleChoice:
            SingleChoiceView(
                question: question,
                currentValue: viewModel.stringValue(for: question.id)
            ) { value in
                viewModel.updateAnswer(questionId: question.id, value: value)
                // Auto-advance : 350ms pour que l'utilisateur voie son choix
                // se valider visuellement, puis écran suivant avec haptique.
                // Jamais sur la dernière question — la soumission reste un
                // geste explicite via « Terminer ».
                scheduleAutoAdvance(from: question.id)
            }

        case .multiChoice:
            MultiChoiceView(
                question: question,
                currentValues: viewModel.arrayValue(for: question.id)
            ) { value in
                toggleMultiChoice(questionId: question.id, value: value)
            }

        case let .numericInput(placeholder, suffix):
            // Si la question a une config bornée (age/poids/taille), on utilise
            // la molette type Apple (WheelInputView). Sinon, clavier numérique.
            if let config = sliderConfig(for: question.id) {
                WheelInputView(
                    question: question,
                    text: bindingForString(question.id),
                    range: config.range,
                    step: config.step,
                    suffix: suffix ?? config.suffix,
                    defaultValue: config.defaultValue
                )
            } else {
                NumericInputView(
                    question: question,
                    text: bindingForString(question.id),
                    placeholder: placeholder,
                    suffix: suffix
                )
            }

        case let .textInput(placeholder):
            TextInputView(
                question: question,
                text: bindingForString(question.id),
                placeholder: placeholder
            )

        case .groceries:
            // "Faites vos courses" : bouton qui ouvre le caddie en plein écran
            // (8 rayons + page quantités). Écrit profile.groceries au "Valider".
            GroceryQuestionControl()
        }
    }

    // MARK: - Bottom Button
    private var bottomBar: some View {
        Button {
            if introSection != nil {
                dismissIntro()
            } else if viewModel.isLastQuestion {
                if viewModel.nextLockedGate != nil {
                    presentGate()
                } else {
                    HapticService.shared.strong()
                    submitAndContinue()
                }
            } else {
                HapticService.shared.primary()
                advance()
            }
        } label: {
            // CTA premium : même recette que le bouton d'onboarding (gradient
            // brand + glow doux), état envoi en gris muted sans glow.
            Text(primaryButtonLabel)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    if viewModel.isSubmitting {
                        Color.healthMapMuted
                    } else {
                        LinearGradient.healthMapBrand
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .shadow(
                    color: viewModel.isSubmitting
                        ? Color.clear
                        : Color.healthMapBlue.opacity(Theme.shadowBrandGlow.opacity),
                    radius: Theme.shadowBrandGlow.radius,
                    x: 0,
                    y: Theme.shadowBrandGlow.y
                )
        }
        .buttonStyle(.healthMapPressed)
        .disabled(viewModel.isSubmitting)
        .padding(.horizontal, Theme.spacingLG)
        .padding(.top, Theme.spacingSM)
        .padding(.bottom, Theme.spacingSM)
        .alert("Erreur", isPresented: $showSubmitError) {
            Button("Reessayer") {
                Task { await viewModel.submitQuestionnaire() }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "Erreur lors de la sauvegarde.")
        }
    }

    /// Soumission → bascule directe sur le Bilan (plus de célébration).
    /// La sauvegarde serveur confirmée, on calcule les scores locaux PUIS on
    /// active `hasCompletedQuestionnaire` (MainTabView affiche alors le Bilan,
    /// càd l'écran de chargement tant que l'analyse IA n'est pas prête). L'analyse
    /// part en parallèle.
    private func submitAndContinue() {
        Task {
            await viewModel.submitQuestionnaire()
            if viewModel.profile.completed {
                HapticService.shared.success()
                // Pass data directly to DashboardVM to avoid
                // re-fetch timing issues (Supabase replication lag).
                dashboardVM.profile = viewModel.profile
                // computeLocalScores AVANT de basculer : garantit un healthScore
                // calculé (≠ 0) dès l'affichage du Bilan. Cf. bug TestFlight 28.
                dashboardVM.computeLocalScores()
                // Bascule immédiate vers l'onglet Bilan : il affiche l'écran de
                // chargement honnête (« 2-3 min ») jusqu'à ce que l'analyse arrive.
                dashboardVM.hasCompletedQuestionnaire = true
                Task { await dashboardVM.triggerAnalysis() }
            } else if viewModel.errorMessage != nil {
                HapticService.shared.error()
                showSubmitError = true
            }
        }
    }

    // MARK: - Submitting View
    private var submittingView: some View {
        VStack(spacing: Theme.spacingLG) {
            // Loader signature : le kiwi qui marche (remplace le spinner nu).
            KiwiWalkerView(size: 140)

            Text("Sauvegarde en cours...")
                .font(Theme.headlineFont)
                .foregroundStyle(Color.healthMapText)
        }
    }

    // MARK: - Navigation entre écrans

    /// Animation des transitions d'écran. Reduce motion → crossfade simple
    /// (aucun déplacement), sinon spring maison.
    private var stepAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .healthMapSpring
    }

    /// Transition slide horizontale asymétrique : en avançant, le nouvel
    /// écran entre par la droite ; en reculant, par la gauche. Reduce motion
    /// → simple fondu.
    private var stepTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: isNavigatingForward ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: isNavigatingForward ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    /// Avance d'un écran. Si on franchit une frontière de section, c'est
    /// l'écran d'intro de la nouvelle section qui s'affiche d'abord (la
    /// question apparaîtra après « C'est parti »).
    private func advance() {
        guard !viewModel.isLastQuestion else { return }
        autoAdvanceTask?.cancel()
        isNavigatingForward = true
        withAnimation(stepAnimation) {
            if let enteredSection = viewModel.nextQuestion() {
                // Teaser choisi AVANT d'afficher l'intro, à partir des
                // réponses déjà saisies (règles anti-spam incluses).
                introTeaser = pickTeaserForIntro()
                introSection = enteredSection
            }
        }
    }

    /// Choisit le teaser de l'écran d'intro qui s'ouvre. Règles anti-spam :
    /// max un teaser par intro (donc par section), jamais deux intros
    /// d'affilée avec teaser, jamais deux fois le même dans la session.
    /// Le choix est déterministe : premier candidat non encore montré,
    /// dans l'ordre de priorité de TeaserEngine.
    private func pickTeaserForIntro() -> Teaser? {
        if lastIntroShowedTeaser {
            lastIntroShowedTeaser = false
            return nil
        }
        let candidates = TeaserEngine.teasers(for: viewModel.profile)
        guard let teaser = candidates.first(where: { !shownTeaserIds.contains($0.id) }) else {
            return nil
        }
        shownTeaserIds.insert(teaser.id)
        lastIntroShowedTeaser = true
        return teaser
    }

    /// Ferme l'écran d'intro de section → révèle sa première question
    /// (l'index avait déjà avancé au moment d'afficher l'intro).
    private func dismissIntro() {
        HapticService.shared.primary()
        isNavigatingForward = true
        withAnimation(stepAnimation) {
            introSection = nil
        }
    }

    /// Recule d'un écran. Depuis une intro de section, revient à la dernière
    /// question de la section précédente.
    private func goBack() {
        autoAdvanceTask?.cancel()
        HapticService.shared.tap()
        isNavigatingForward = false
        withAnimation(stepAnimation) {
            if activeGate != nil {
                // Retour depuis un carrefour → revient à la dernière question.
                activeGate = nil
            } else {
                introSection = nil
                viewModel.previousQuestion()
            }
        }
    }

    // MARK: - Carrefours d'approfondissement (parcours adaptatif)

    /// Affiche le carrefour du prochain bloc verrouillé (au tap « Continuer »
    /// sur la dernière question visible).
    private func presentGate() {
        autoAdvanceTask?.cancel()
        HapticService.shared.primary()
        isNavigatingForward = true
        withAnimation(stepAnimation) {
            introSection = nil
            activeGate = viewModel.nextLockedGate
        }
    }

    /// « Analyser… » : déverrouille le bloc et enchaîne sur sa première question.
    private func acceptGate(_ gate: QuestionnaireSection) {
        HapticService.shared.primary()
        isNavigatingForward = true
        withAnimation(stepAnimation) {
            viewModel.unlockDeep(gate) // déverrouille + repositionne sur la 1re question
            activeGate = nil
            introSection = nil          // le carrefour a déjà servi d'intro
        }
    }

    /// « Ignorer… » : on arrête là et on file au bilan (résultat partiel).
    private func skipGate() {
        HapticService.shared.strong()
        activeGate = nil
        submitAndContinue()
    }

    // MARK: - Auto-advance (single-choice)

    /// Programme le passage à l'écran suivant 350ms après le tap d'une réponse
    /// single-choice. Pourquoi 350ms : laisse le temps de voir le highlight de
    /// la sélection (feedback visuel) avant la transition. Plus court =
    /// saccadé ; plus long = lent. Annulé si l'utilisateur re-tape avant
    /// l'échéance (changement d'avis, retour, Continuer manuel).
    private func scheduleAutoAdvance(from questionId: String) {
        autoAdvanceTask?.cancel()

        // Jamais d'auto-advance sur la dernière question : la soumission
        // doit rester un geste explicite (« Terminer »).
        guard !viewModel.isLastQuestion else { return }

        autoAdvanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            // L'utilisateur a pu naviguer entre-temps — on n'avance que si
            // la question d'origine est toujours affichée.
            guard introSection == nil, viewModel.currentQuestion?.id == questionId else { return }
            HapticService.shared.primary()
            advance()
        }
    }

    // MARK: - Slider configs (Lot B — UX au pouce)
    //
    // Pour chaque question numericInput "bornée" (la valeur a un range raisonnable),
    // on retourne la config qui rend le SliderInputView utilisable au pouce.
    // Les valeurs par défaut correspondent à la médiane française pour
    // pré-positionner le slider sans biaiser la réponse.
    //
    // Si une question n'apparaît pas ici → fallback sur le clavier numérique
    // standard (NumericInputView).
    private func sliderConfig(for questionId: String) -> (range: ClosedRange<Double>, step: Double, suffix: String?, defaultValue: Double)? {
        switch questionId {
        // ── Personnel ──────────────────────────────────────────────────────
        case "age":      return (14...100, 1, "ans", 30)
        case "height":   return (140...220, 1, "cm", 170)
        case "weight":   return (35...180, 0.5, "kg", 70)

        // ── Fréquences alimentaires / semaine ──────────────────────────────
        // Range 0-21 = jusqu'à 3 portions par jour (cas extrême honnête).
        case "vegetableServings", "fruitServings",
             "wholegrainPerWeek", "dairyServings":
            return (0...21, 1, "/sem", 7)
        case "legumesPerWeek", "nutsPerWeek", "seedsPerDay":
            return (0...14, 1, "/sem", 3)
        case "fattyFish":
            return (0...7, 1, "/sem", 2)
        case "meatPoultry":
            return (0...14, 1, "/sem", 4)
        case "eggsPerWeek":
            return (0...14, 1, "/sem", 4)

        default: return nil
        }
    }

    /// Valeur numérique courante d'une question slider — miroir de la
    /// logique de restauration de SliderInputView : texte saisi si présent
    /// (clampé au range, virgule tolérée), valeur par défaut sinon. Sert au
    /// fun fact pour refléter EXACTEMENT le grand chiffre affiché.
    private func currentSliderValue(
        for questionId: String,
        config: (range: ClosedRange<Double>, step: Double, suffix: String?, defaultValue: Double)
    ) -> Double {
        let raw = viewModel.inputText(for: questionId).replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(raw) else { return config.defaultValue }
        return min(max(parsed, config.range.lowerBound), config.range.upperBound)
    }

    // MARK: - Value Helpers
    // La lecture des réponses vit dans le ViewModel (stringValue/arrayValue/
    // inputText) — la vue ne fait que construire les bindings par-dessus.

    private func bindingForString(_ questionId: String) -> Binding<String> {
        Binding<String>(
            get: { viewModel.inputText(for: questionId) },
            set: { newValue in
                viewModel.updateAnswer(questionId: questionId, value: newValue)
            }
        )
    }

    private func precisionBinding(for questionId: String) -> Binding<Set<String>> {
        Binding<Set<String>>(
            get: {
                let p = viewModel.profile.precisions
                let array: [String]?
                switch questionId {
                case "vegetableServings": array = p?.vegetables
                case "fruitServings":     array = p?.fruits
                case "meatPoultry":       array = p?.meat
                case "dairyServings":     array = p?.dairy
                case "wholegrainPerWeek": array = p?.grains
                default: array = nil
                }
                return Set(array ?? [])
            },
            set: { newValue in
                viewModel.updatePrecision(key: questionId, value: Array(newValue))
            }
        )
    }

    private func toggleMultiChoice(questionId: String, value: String) {
        var current = viewModel.arrayValue(for: questionId)

        if value == "none" {
            current = ["none"]
        } else {
            current.removeAll { $0 == "none" }
            if current.contains(value) {
                current.removeAll { $0 == value }
            } else {
                current.append(value)
            }
        }

        if current.isEmpty {
            current = ["none"]
        }

        viewModel.updateAnswer(questionId: questionId, value: current)
    }
}

// MARK: - Carrefour d'approfondissement (vue)
/// Écran de décision contextuel à chaque bloc profond : « Analyser… »
/// (déverrouille et approfondit) ou « Ignorer… » (bilan partiel). Une icône 3D
/// et un message DIFFÉRENTS par bloc — on incite à approfondir, le skip assume
/// sa perte de fiabilité. Vocabulaire conforme (jamais le mot interdit).
private struct QuestionnaireGateView: View {
    let gate: QuestionnaireSection
    let onDeepen: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private struct Copy {
        let asset: String
        let kicker: String
        let title: String
        let sub: String
        let cta: String
        let skip: String
    }

    private var copy: Copy {
        switch gate {
        case .nutrition:
            return Copy(asset: Fluent3D.kiwi, kicker: "On a repéré quelque chose",
                       title: "Certains apports semblent sous tes besoins",
                       sub: "Voyons lesquels à partir de ton alimentation.",
                       cta: "Analyser mon alimentation", skip: "Ignorer l'analyse")
        case .symptomes:
            return Copy(asset: Fluent3D.loupe, kicker: "Tes signaux comptent",
                       title: "Tes symptômes en disent long",
                       sub: "On relie ongles, énergie, digestion à tes apports.",
                       cta: "Analyser mes symptômes", skip: "Ignorer mes symptômes")
        case .medical:
            return Copy(asset: Fluent3D.pill, kicker: "Point sécurité",
                       title: "Tes traitements changent la donne",
                       sub: "Certains interagissent avec tes vitamines et minéraux.",
                       cta: "Vérifier mes interactions", skip: "Ignorer les interactions")
        default:
            return Copy(asset: Fluent3D.kiwi, kicker: "On a repéré quelque chose",
                       title: "Quelques questions de plus",
                       sub: "Pour rendre ton bilan plus fiable.",
                       cta: "Continuer", skip: "Ignorer")
        }
    }

    var body: some View {
        let c = copy
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Fluent3DIcon(name: c.asset, size: 34)
                    Text(c.kicker)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.kiwiGreen)
                }
                Text(c.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Text(c.sub)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                Button(action: onDeepen) {
                    HStack {
                        Text(c.cta).font(.system(size: 16, weight: .bold))
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kiwiGreen))
                    .shadow(color: Color.kiwiGreen.opacity(0.32), radius: 12, x: 0, y: 8)
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 24)

                Button(action: onSkip) {
                    VStack(spacing: 2) {
                        Text(c.skip)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.healthMapMuted)
                            .underline()
                        Text("plus rapide, mais ton bilan sera moins fiable")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.healthMapMuted.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 18)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.healthMapCard)
                    .shadow(color: Color.kiwiCharcoal.opacity(0.08), radius: 24, x: 0, y: 12)
            )
            .padding(.horizontal, Theme.spacingLG)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            Spacer()
        }
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.easeOut(duration: 0.45)) { appeared = true } }
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    QuestionnaireContainerView()
        .environmentObject(QuestionnaireViewModel())
        .environmentObject(DashboardViewModel())
}
