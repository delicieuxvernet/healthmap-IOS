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
    @State private var showPathwayChoice = true
    @State private var showCelebration = false
    @State private var celebrationScore: Int = 0
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
        return "Terminer"
    }

    var body: some View {
        ZStack {
            Color.healthMapBackground
                .ignoresSafeArea()

            if showPathwayChoice {
                pathwayChoiceView
            } else if viewModel.isSubmitting {
                submittingView
            } else {
                questionFlow
            }
        }
        .onAppear {
            // Draft restauré → reprendre le flux à la question où
            // l'utilisateur s'était arrêté, sans lui redemander le parcours.
            if viewModel.hasDraftInProgress {
                showPathwayChoice = false
            }
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
        }
        .fullScreenCover(isPresented: $showCelebration) {
            CelebrationView(score: celebrationScore) {
                // User tape "Continuer" → ferme la célébration ET active le
                // switch vers le Dashboard. L'analyse IA tournait en parallèle,
                // elle sera affichée dès que prête (ou loading si encore en cours).
                showCelebration = false
                dashboardVM.hasCompletedQuestionnaire = true
            }
            .interactiveDismissDisabled(true) // L'utilisateur doit tap Continuer
        }
    }

    // MARK: - Pathway Choice
    private var pathwayChoiceView: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            VStack(spacing: Theme.spacingMD) {
                Image(systemName: "clipboard.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.healthMapBlue)

                Text("Ton bilan nutritionnel")
                    .font(Theme.titleFont)
                    .brandTitleKerning()
                    .foregroundStyle(Color.healthMapText)

                Text("Reponds a quelques questions pour decouvrir ton profil nutritionnel.")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacingXL)
            }

            Spacer()

            VStack(spacing: Theme.spacingMD) {
                // Express pathway
                pathwayButton(
                    title: "Express",
                    subtitle: "~3 min — 21 questions essentielles",
                    icon: "bolt.fill",
                    pathway: .express
                )

                // Complete pathway
                pathwayButton(
                    title: "Complet",
                    subtitle: "~8 min — 46 questions detaillees",
                    icon: "list.bullet.clipboard.fill",
                    pathway: .complet
                )
            }
            .padding(.horizontal, Theme.spacingLG)

            Spacer()
        }
    }

    private func pathwayButton(title: String, subtitle: String, icon: String, pathway: UserProfile.Pathway) -> some View {
        Button {
            HapticService.shared.primary()
            viewModel.selectPathway(pathway)
            introSection = nil
            isNavigatingForward = true
            withAnimation(stepAnimation) {
                showPathwayChoice = false
            }
        } label: {
            HStack(spacing: Theme.spacingMD) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.healthMapBlue)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)

                    Text(subtitle)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.healthMapMuted)
            }
            .padding(Theme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.healthMapCard)
                    .shadow(
                        color: .black.opacity(Theme.shadowCard.opacity),
                        radius: Theme.shadowCard.radius,
                        x: 0,
                        y: Theme.shadowCard.y
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Color.healthMapMuted.opacity(Theme.opacityStrong), lineWidth: 1)
            )
        }
        .buttonStyle(.healthMapPressed)
    }

    // MARK: - Flux une question par écran
    private var questionFlow: some View {
        VStack(spacing: 0) {
            flowHeader

            // Étape courante : question OU intro de section. L'`.id(...)`
            // force SwiftUI à traiter chaque question comme une nouvelle vue,
            // ce qui déclenche la transition slide entre les écrans.
            ZStack {
                if let section = introSection {
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

            bottomBar
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
            // Lot B : si la question a une config de slider (range borné),
            // on utilise SliderInputView (UX au pouce). Sinon fallback sur
            // NumericInputView avec clavier numérique.
            if let config = sliderConfig(for: question.id) {
                SliderInputView(
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
        }
    }

    // MARK: - Bottom Button
    private var bottomBar: some View {
        Button {
            if introSection != nil {
                dismissIntro()
            } else if viewModel.isLastQuestion {
                HapticService.shared.strong()
                submitAndCelebrate()
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

    /// Flux de soumission existant, inchangé : sauvegarde serveur confirmée
    /// → célébration + bascule Dashboard (l'analyse IA part en parallèle).
    private func submitAndCelebrate() {
        Task {
            await viewModel.submitQuestionnaire()
            if viewModel.profile.completed {
                HapticService.shared.success()
                // Pass data directly to DashboardVM to avoid
                // re-fetch timing issues (Supabase replication lag).
                dashboardVM.profile = viewModel.profile
                // NOTE : computeLocalScores/triggerAnalysis se basent sur
                // profile.completed — PAS sur hasCompletedQuestionnaire, qui
                // doit rester false ici (l'activer maintenant swaperait
                // l'onglet Bilan sous la célébration via MainTabView).
                // Bug TestFlight 28 : l'ancienne garde sur le flag laissait
                // healthScore à 0 → célébration « 0/100 » avec croix, et
                // l'analyse IA ne démarrait jamais en parallèle.
                dashboardVM.computeLocalScores()
                // Capture local score pour la célébration AVANT de switcher.
                celebrationScore = dashboardVM.healthScore
                // Afficher CelebrationView en overlay. L'analyse IA
                // démarre en parallèle — ready quand user tape "Continuer".
                showCelebration = true
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
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.healthMapBlue)

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
            introSection = nil
            viewModel.previousQuestion()
        }
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

#Preview {
    QuestionnaireContainerView()
        .environmentObject(QuestionnaireViewModel())
        .environmentObject(DashboardViewModel())
}
