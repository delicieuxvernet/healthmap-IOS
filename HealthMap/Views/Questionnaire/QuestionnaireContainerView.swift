import SwiftUI

// MARK: - Questionnaire Container View
struct QuestionnaireContainerView: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @State private var showPathwayChoice = true
    @State private var questionAppeared = false
    @State private var showCelebration = false
    @State private var celebrationScore: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Dynamic button label: changes to "Reessayer" after an error so the
    /// user understands they can tap again without losing answers.
    private var submitButtonLabel: String {
        if !viewModel.isLastSection { return "Suivant" }
        if viewModel.isSubmitting { return "Envoi en cours..." }
        if viewModel.errorMessage != nil { return "Reessayer" }
        return "Voir mes resultats"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.healthMapBackground
                    .ignoresSafeArea()

                if showPathwayChoice {
                    pathwayChoiceView
                } else if viewModel.isSubmitting {
                    submittingView
                } else {
                    questionnaireContent
                }
            }
            .navigationTitle(showPathwayChoice ? "Bilan" : viewModel.currentSection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !showPathwayChoice && !viewModel.isSubmitting {
                    ToolbarItem(placement: .topBarLeading) {
                        if !viewModel.isFirstSection {
                            Button {
                                withAnimation(reduceMotion ? .none : .healthMapSpring) {
                                    viewModel.previousSection()
                                    questionAppeared = true
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Retour")
                                }
                                .font(.system(size: 16))
                                .foregroundStyle(Color.healthMapBlue)
                            }
                        }
                    }
                }
            }
            .animation(reduceMotion ? .none : .healthMapSpring, value: viewModel.currentSectionIndex)
            .animation(reduceMotion ? .none : .healthMapSpring, value: showPathwayChoice)
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
            withAnimation(reduceMotion ? .none : .healthMapSpring) {
                showPathwayChoice = false
                questionAppeared = true
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
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Color.healthMapMuted.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Questionnaire Content
    /// ID de la question vers laquelle scroller automatiquement. Mis à jour :
    ///   - au changement de section (→ header de la nouvelle section)
    ///   - au tap d'une réponse single-choice (→ question suivante non répondue)
    @State private var autoScrollTargetId: String?

    private var questionnaireContent: some View {
        VStack(spacing: 0) {
            // Progress bar
            progressBar

            // Questions scroll
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Theme.spacingXL) {
                        // Section header — ancre de scroll pour le retour-au-top.
                        HStack(spacing: Theme.spacingSM) {
                            Text(viewModel.currentSection.emoji)
                                .font(.system(size: 24))

                            Text(viewModel.currentSection.title)
                                .font(Theme.headlineFont)
                                .foregroundStyle(Color.healthMapText)

                            Spacer()

                            Text("\(viewModel.currentSectionIndex + 1)/\(viewModel.totalSections)")
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.healthMapMuted)
                        }
                        .padding(.horizontal, Theme.spacingLG)
                        .padding(.top, Theme.spacingMD)
                        .id("section-header")

                        // Questions
                        ForEach(viewModel.visibleQuestions) { question in
                            questionView(for: question)
                                .padding(.horizontal, Theme.spacingLG)
                                .opacity(questionAppeared ? 1 : 0)
                                .offset(y: questionAppeared ? 0 : 20)
                                .id(question.id)
                        }

                        // Error message
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(Theme.captionFont)
                                .foregroundStyle(.red)
                                .padding(.horizontal, Theme.spacingLG)
                        }
                    }
                    .padding(.bottom, 100) // Space for button
                }
                .scrollDismissesKeyboard(.interactively)
                // Auto-scroll quand on change de section → revenir tout en haut.
                // Sans ce listener, l'user atterrissait au milieu de la nouvelle
                // section avec les premières questions hors champ (UX dégueulasse,
                // signalé par Arthur).
                .onChange(of: viewModel.currentSectionIndex) { _, _ in
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.4)) {
                        proxy.scrollTo("section-header", anchor: .top)
                    }
                }
                // Auto-scroll vers la question ciblée après réponse single-choice.
                // Le ViewModel positionne l'id ; le listener fait défiler en douceur
                // pour amener la question en haut du viewport (~64pt de marge).
                .onChange(of: autoScrollTargetId) { _, newId in
                    guard let newId else { return }
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.45)) {
                        proxy.scrollTo(newId, anchor: .top)
                    }
                }
            }

            // Bottom action button
            bottomButton
        }
    }

    // MARK: - Progress Bar
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.healthMapMuted.opacity(0.12))

                Rectangle()
                    .fill(Color.healthMapBlue)
                    .frame(width: geo.size.width * viewModel.progress)
                    .animation(reduceMotion ? .none : .healthMapSpring, value: viewModel.progress)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Question View Router
    @ViewBuilder
    private func questionView(for question: Question) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text(question.text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.healthMapText)

            switch question.type {
            case .singleChoice:
                SingleChoiceView(
                    question: question,
                    currentValue: currentStringValue(for: question.id)
                ) { value in
                    viewModel.updateAnswer(questionId: question.id, value: value)
                    // Auto-advance vers la question suivante : 350ms pour que
                    // l'user voie son choix se valider visuellement, puis scroll
                    // doux. Pas de skip de questions déjà répondues — l'user qui
                    // revient en arrière retrouve sa progression normale.
                    scheduleAutoAdvance(after: question.id)
                }

            case .multiChoice:
                MultiChoiceView(
                    question: question,
                    currentValues: currentArrayValue(for: question.id)
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

            // Precision picker (multi-select chips) — appears under sliders
            // and numeric inputs for vegetables, fruits, meat, dairy, grains.
            // Mirrors the web `precisions.*` structure from Home.jsx.
            if !PrecisionCatalog.options(for: question.id).isEmpty {
                PrecisionPicker(
                    title: PrecisionCatalog.title(for: question.id),
                    options: PrecisionCatalog.options(for: question.id),
                    selection: precisionBinding(for: question.id)
                )
                .padding(.top, Theme.spacingSM)
            }
        }
    }

    // MARK: - Bottom Button
    /// Tracks whether we should show the submission error as an alert
    /// rather than inline text — an alert is impossible to miss.
    @State private var showSubmitError = false

    private var bottomButton: some View {
        Button {
            if viewModel.isLastSection {
                HapticService.shared.strong()
                Task {
                    await viewModel.submitQuestionnaire()
                    if viewModel.profile.completed {
                        HapticService.shared.success()
                        // Pass data directly to DashboardVM to avoid
                        // re-fetch timing issues (Supabase replication lag).
                        dashboardVM.profile = viewModel.profile
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
            } else {
                HapticService.shared.primary()
                withAnimation(reduceMotion ? .none : .healthMapSpring) {
                    viewModel.nextSection()
                    questionAppeared = true
                }
            }
        } label: {
            Text(submitButtonLabel)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(viewModel.isSubmitting ? Color.healthMapMuted : Color.healthMapBlue)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .disabled(viewModel.isSubmitting)
        .padding(.horizontal, Theme.spacingLG)
        .padding(.bottom, Theme.spacingSM)
        .alert("Erreur", isPresented: $showSubmitError) {
            Button("Reessayer") {
                Task { await viewModel.submitQuestionnaire() }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "Erreur lors de la sauvegarde.")
        }
        .background(
            LinearGradient(
                colors: [Color.healthMapBackground.opacity(0), Color.healthMapBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 30)
            .offset(y: -30),
            alignment: .top
        )
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

    // MARK: - Auto-advance

    /// Programme un scroll vers la question suivante 350ms après le tap d'une
    /// réponse single-choice. Pourquoi 350ms : laisse le temps à l'user de voir
    /// le checkmark/highlight de sa sélection (feedback visuel) avant qu'on
    /// déplace la vue. Plus court = saccadé ; plus long = lent.
    private func scheduleAutoAdvance(after questionId: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let next = nextQuestion(after: questionId) else { return }
            autoScrollTargetId = next.id
            HapticService.shared.primary()
        }
    }

    /// Renvoie la question juste après `questionId` dans la liste visible, ou
    /// `nil` si c'est la dernière. On scroll juste vers la suivante littérale —
    /// pas de skip de questions déjà répondues, l'user qui revient en arrière
    /// retrouve son parcours intuitif.
    private func nextQuestion(after questionId: String) -> Question? {
        let questions = viewModel.visibleQuestions
        guard let idx = questions.firstIndex(where: { $0.id == questionId }),
              idx + 1 < questions.count else { return nil }
        return questions[idx + 1]
    }

    // MARK: - Value Helpers

    private func currentStringValue(for questionId: String) -> String? {
        let p = viewModel.profile
        switch questionId {
        case "gender": return p.gender.rawValue
        case "weightTrend": return p.weightTrend
        case "indoorWork": return p.indoorWork
        case "sunExposure": return p.sunExposure
        case "skinType": return p.skinType
        case "strengthTraining": return p.strengthTraining
        case "stressLevel": return p.stressLevel
        case "sleepHours": return p.sleepHours
        case "wakeFeeling": return p.wakeFeeling
        case "screenBeforeBed": return p.screenBeforeBed
        case "caffeineIntake": return p.caffeineIntake
        case "caffeineTiming": return p.caffeineTiming
        case "waterIntake": return p.waterIntake
        case "smoking": return p.isSmoker ? "yes" : "no"
        case "alcohol": return p.alcohol
        case "bloating": return p.bloating
        case "antibiotics": return p.antibiotics
        case "dietType": return p.dietType
        case "mealsPerDay": return p.mealsPerDay
        case "homeCookedPct": return p.homeCookedPct
        case "cookingMethod": return p.cookingMethod
        case "breadType": return p.breadType
        case "fermentedFoods": return p.fermentedFoods
        case "ultraProcessedFrequency": return p.ultraProcessedFrequency
        case "snacking": return p.snacking
        case "saltLevel": return p.saltLevel
        case "iodizedSalt": return p.iodizedSalt
        case "eatLiver": return p.eatLiver
        case "lowCarbDiet": return p.lowCarbDiet
        case "periodFlow": return p.periodFlow
        case "pregnancyStatus": return p.pregnancyStatus
        default: return nil
        }
    }

    private func currentArrayValue(for questionId: String) -> [String] {
        let p = viewModel.profile
        switch questionId {
        case "goals": return p.goals
        case "supplementsCurrent": return p.supplementsCurrent
        case "symptoms": return p.symptoms
        case "medications": return p.medications
        case "digestiveConditions": return p.digestiveConditions
        default: return []
        }
    }

    private func bindingForString(_ questionId: String) -> Binding<String> {
        Binding<String>(
            get: {
                let p = viewModel.profile
                switch questionId {
                case "firstName": return p.firstName
                case "age": return p.age
                case "height": return p.height
                case "weight": return p.weight
                case "vegetableServings": return p.vegetableServings
                case "fruitServings": return p.fruitServings
                case "fattyFish": return p.fattyFish
                case "meatPoultry": return p.meatPoultry
                case "eggsPerWeek": return p.eggsPerWeek
                case "dairyServings": return p.dairyServings
                case "legumesPerWeek": return p.legumesPerWeek
                case "nutsPerWeek": return p.nutsPerWeek
                case "seedsPerDay": return p.seedsPerDay
                case "wholegrainPerWeek": return p.wholegrainPerWeek
                default: return ""
                }
            },
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
        var current = currentArrayValue(for: questionId)

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
