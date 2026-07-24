import SwiftUI
import Combine

// MARK: - Recommendations View (« Ton plan » — langage v4 3D, maquette FINALE)
//
// Refonte FINALE (maquette « impl_Plan.html ») : fond crème, cartes blanches
// arrondies (.kiwiCard). Plus de héros gamifié (XP / niveau retirés). Pour
// chaque symptôme déclaré et chaque objectif : une carte « la cause, quoi faire,
// et quand » avec un rituel matin/midi/soir et un bouton « Voir mes solutions »
// qui ouvre une pop-up (bottom sheet) détaillant les solutions par la nutrition,
// les habitudes et les compléments.
//
// Les bindings au ViewModel sont conservés : le contenu est dérivé de
// dashboardVM.aiAnalysis (symptomesAnalyse, objectifsAnalyse, priorityActions,
// nutriments + solutions) et du catalogue de sources d'aliments (Fluent3D).
struct RecommendationsView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel

    /// Topics dérivés du contrat v2 (repli quand `aiAnalysis` v7 manque).
    private var v2Topics: [PlanTopic] {
        guard let v2 = dashboardVM.analysisV2 else { return [] }
        return planTopicsFromV2(v2)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Fond crème chaud du langage v4.
                Color.kiwiCream.ignoresSafeArea()

                if let analysis = dashboardVM.aiAnalysis {
                    RecommendationsContentView(analysis: analysis)
                } else if !v2Topics.isEmpty {
                    // Repli : le v7 (aiAnalysis) manque mais le bilan v2 a un
                    // plan → on le rend depuis le contrat v2 (le Plan ne reste
                    // plus jamais vide quand le Bilan, lui, s'affiche).
                    RecommendationsV2ContentView(topics: v2Topics)
                } else if dashboardVM.isLoadingAnalysis || dashboardVM.isLoadingAnalysisV2 {
                    VStack(spacing: Theme.spacingMD) {
                        // Loader signature : le kiwi qui marche remplace le
                        // spinner nu — l'attente reste non bloquante.
                        KiwiWalkerView(size: 140)
                        Text("Chargement du plan…")
                            .font(Theme.bodyFont)
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                } else {
                    VStack(spacing: Theme.spacingMD) {
                        // Mascotte en réflexion plutôt qu'une icône système
                        // froide — l'état vide reste accueillant.
                        MascotView(mood: .thinking, size: 72)
                        Text("Aucune analyse disponible")
                            .font(Theme.bodyFont)
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                }
            }
            .kiwiTabBarBottomInset()
            // Sécurité : si l'utilisateur ouvre le Plan sans qu'aucune analyse
            // n'ait été déclenchée (ni v7 ni v2), on lance (garde de ré-entrance
            // dans le VM). N'écrase rien si une analyse est déjà là / en cours.
            .task {
                if dashboardVM.aiAnalysis == nil, dashboardVM.analysisV2 == nil,
                   !dashboardVM.isLoadingAnalysis, !dashboardVM.isLoadingAnalysisV2 {
                    await dashboardVM.triggerAnalysis()
                }
            }
            .navigationTitle("Ton plan")
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
        }
    }
}

// MARK: - Recommendations Content (ViewModel stable)
/// Contenu du plan une fois l'analyse disponible. `@StateObject` créé une
/// seule fois ; `onReceive` resynchronise si l'analyse est régénérée.
struct RecommendationsContentView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @StateObject private var vm: RecommendationsViewModel
    /// Journal alimentaire (repas scannés de la quinzaine) — nourrit la carte
    /// « Focus de la semaine » en tête du Plan. Chargé une fois via `.task`.
    @StateObject private var journalVM = MealJournalViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Topic dont la pop-up « Voir mes solutions » est ouverte.
    @State private var activeTopic: PlanTopic?

    init(analysis: MergedAnalysis) {
        _vm = StateObject(wrappedValue: RecommendationsViewModel(analysis: analysis))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. Titre éditorial (sentence case — maquette « Ton plan »).
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ton plan")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Text("La cause, quoi faire, et quand — pour chaque symptôme")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 4)

                // 1 bis. « Focus de la semaine » : une mission unique dérivée des
                // scans (moteur déterministe). Affichée seulement si on peut la
                // calculer honnêtement (des repas scannés existent) — sinon rien,
                // jamais de chiffre inventé.
                if let focus = planFocus {
                    PlanFocusCardV6(focus: focus, reduceMotion: reduceMotion)
                        .padding(.horizontal, 24)
                }

                // 2. Une carte par symptôme / objectif.
                ForEach(topics) { topic in
                    PlanTopicCardV4(topic: topic) {
                        HapticService.shared.tap()
                        activeTopic = topic
                    }
                    .padding(.horizontal, 24)
                }

                // État vide : aucun symptôme/objectif exploitable dans l'analyse.
                if topics.isEmpty {
                    VStack(spacing: 10) {
                        MascotView(mood: .happy, size: 64)
                        Text("Rien à signaler pour l'instant")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.kiwiCharcoal)
                        Text("Ton plan s'enrichira au fil de tes bilans et de tes scans.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.healthMapSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .kiwiCard()
                    .padding(.horizontal, 24)
                }

                // Sources scientifiques (App Store guideline 1.4.1) — citations
                // cliquables des références fondant les recommandations du plan.
                SourcesSection()
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $activeTopic) { topic in
            PlanSolutionsSheetV4(topic: topic) {
                // CTA « Voir mes compléments recommandés » : ferme la pop-up et
                // bascule vers l'onglet Compléments (best effort via le canal de
                // navigation partagé). cf. gap si l'onglet n'est pas routé.
                activeTopic = nil
                NotificationCenter.default.post(
                    name: .healthmapNavigateToTab,
                    object: "complements"
                )
            }
        }
        .onReceive(dashboardVM.$aiAnalysis) { newAnalysis in
            if let newAnalysis {
                vm.updateAnalysis(newAnalysis)
            }
        }
        .task {
            // Repas scannés de la quinzaine (lecture seule) pour la carte Focus.
            // Aucun LLM : la mission est ensuite calculée localement (SuiviEngineV4).
            await journalVM.load()
        }
        // Un scan fait dans l'onglet Scanner ne relance pas ce .task : on recharge
        // pour que la carte Focus (repas qui comptent) intègre le nouveau scan.
        .onReceive(NotificationCenter.default.publisher(for: .healthmapMealScanned)) { _ in
            Task { await journalVM.load() }
        }
    }

    // MARK: - Focus de la semaine (carte en tête, 100 % déterministe)
    /// Mission unique de la semaine, dérivée des repas réellement scannés :
    /// couverture 7 jours des apports à renforcer → apport le plus à combler →
    /// mission « 3 repas riches en X » + progrès compté sur les scans de la
    /// semaine. `nil` s'il n'y a rien à calculer honnêtement (aucun scan) →
    /// la carte n'est pas affichée (jamais de chiffre inventé).
    private var planFocus: SuiviEngineV4.PlanFocus? {
        // Apports à renforcer = ids des nutriments faibles (< 70, cf. deficiencies).
        let focusIds = dashboardVM.deficiencies.map(\.id)
        let coverage = SuiviEngineV4.nutrientCoverage(
            fortnight: journalVM.fortnight,
            focusIds: focusIds
        )
        // Repas de la SEMAINE courante (sous-ensemble de la quinzaine).
        let week = WeekScoreEngine.currentWeekInterval(containing: Date())
        let weekMeals = journalVM.fortnight.filter { week.contains($0.consumedAt) }
        return SuiviEngineV4.planFocus(coverage: coverage, weekMeals: weekMeals)
    }

    // MARK: - Construction des topics (symptômes + objectifs)
    /// Source : symptômes déclarés (cause croisée IA) + objectifs (priorityActions
    /// d'abord, sinon objectifsAnalyse). Le contenu de chaque pop-up est dérivé
    /// des nutriments à renforcer associés + du catalogue de sources d'aliments.
    private var topics: [PlanTopic] {
        var result: [PlanTopic] = []
        // Pool d'apports à DISTRIBUER de façon distincte entre les cartes :
        // chaque carte consomme SES propres apports, plus aucun fond commun
        // partagé (corrige le doublon de solutions d'une carte à l'autre).
        var pool = vm.topDeficiencies

        // Apports pertinents cités dans le texte IA ET réellement insuffisants.
        // `fallbackToDeficiencies` : pour un SYMPTÔME, à défaut de correspondance
        // on retombe sur les apports les plus faibles (lien défendable). Pour un
        // OBJECTIF, JAMAIS : on n'injecte pas un apport hors-sujet sous un titre
        // comme « Mieux dormir » — la carte s'appuie alors sur ses leviers de vie.
        func focus(matching text: String, fallbackToDeficiencies: Bool) -> [EnrichedNutrient] {
            let matched = nutrientsMentioned(in: text).filter { e in pool.contains { $0.id == e.id } }
            let picked: [EnrichedNutrient]
            if matched.isEmpty {
                picked = fallbackToDeficiencies ? Array(pool.prefix(2)) : []
            } else {
                picked = Array(matched.prefix(2))
            }
            for n in picked { pool.removeAll { $0.id == n.id } }
            return picked
        }

        // SYMPTÔMES — titre = le symptôme (ex. « Ongles cassants »).
        for s in vm.symptomesAnalyse.prefix(3) {
            guard let name = s.symptome, !name.isEmpty else { continue }
            result.append(makeTopic(
                id: "sym_\(name)",
                kind: .symptome,
                name: prettify(name),
                intro: symptomeIntro(s),
                focus: focus(matching: (s.causesProbables ?? []).joined(separator: " "), fallbackToDeficiencies: true)
            ))
        }

        // OBJECTIFS — titre = le NOM de l'objectif (ex. « Plus d'énergie »),
        // jamais une phrase d'action longue. L'explication passe en intro.
        for o in vm.objectifsAnalyse.prefix(3) {
            guard let name = o.objectif, !name.isEmpty else { continue }
            let levierText = (o.leviers ?? []).first
            result.append(makeTopic(
                id: "obj_\(name)",
                kind: .objectif,
                name: prettify(name),
                intro: levierText.map { "Ton levier principal\u{202F}: \($0)." }
                    ?? "Voici comment t'en rapprocher au quotidien.",
                focus: focus(matching: ((o.leviers ?? []) + (o.freins ?? [])).joined(separator: " "), fallbackToDeficiencies: false)
            ))
        }

        return result
    }

    /// Assemble un PlanTopic à partir des apports DÉJÀ attribués à cette carte
    /// (distincts des autres cartes — voir `topics`).
    private func makeTopic(id: String, kind: PlanTopic.Kind, name: String, intro: String, focus: [EnrichedNutrient]) -> PlanTopic {
        PlanTopic(
            id: id,
            kind: kind,
            name: name,
            intro: intro,
            ritual: ritual(for: focus, kind: kind),
            nutrition: nutritionSolutions(for: focus),
            habitudes: habits(for: focus, kind: kind, objectifName: name),
            complements: supplementSolutions(for: focus)
        )
    }

    // MARK: - Rituel matin / midi / soir
    // Dérivé du moment de prise de la solution IA quand il est connu ; sinon
    // exemple borné (le créneau « à jeun / avec vitamine C / pas de thé-café »
    // est un repère générique, jamais un dosage inventé). cf. gaps.
    private func ritual(for nutrients: [EnrichedNutrient], kind: PlanTopic.Kind) -> [PlanRitualStep] {
        let names = nutrients.map { $0.label.lowercased() }
        let primary = nutrients.first?.label ?? "tes apports"

        if kind == .symptome {
            let matinDetail = nutrients.isEmpty
                ? "Tes apports clés"
                : nutrients.prefix(2).map { $0.label }.joined(separator: " + ")
            return [
                PlanRitualStep(slot: .matin, title: "Matin", detail: "\(matinDetail)\nà jeun"),
                PlanRitualStep(slot: .journee, title: "Midi",
                               detail: names.contains("fer") ? "Fer +\nvitamine C" : "\(primary)\nau repas"),
                PlanRitualStep(slot: .soir, title: "Soir",
                               detail: names.contains("fer") ? "Pas de\nthé / café" : "Repas\nléger")
            ]
        } else {
            // Objectif sans apport ciblé : rituel d'hygiène de vie (aucun nutriment
            // parachuté). Sinon, repère lié à l'apport principal.
            if nutrients.isEmpty {
                return [
                    PlanRitualStep(slot: .matin, title: "Matin", detail: "Lumière\n+ mouvement"),
                    PlanRitualStep(slot: .journee, title: "Journée", detail: "20 min\nde marche"),
                    PlanRitualStep(slot: .soir, title: "Soir", detail: "Routine\nau calme")
                ]
            }
            return [
                PlanRitualStep(slot: .matin, title: "Matin",
                               detail: names.contains("vitb12") || names.contains("b12") ? "B12\nsublinguale" : "\(primary)\nau réveil"),
                PlanRitualStep(slot: .journee, title: "Journée", detail: "20 min\nde marche"),
                PlanRitualStep(slot: .soir, title: "Soir", detail: "Sommeil\nrégulier")
            ]
        }
    }

    // MARK: - Solutions « Par la nutrition »
    // Sources concrètes du catalogue (Fluent3D.foodSources) pour chaque nutriment
    // ciblé. Combien / Quand / Préparation / Astuce : repères génériques bornés
    // (le dosage précis vit côté serveur / fiche bilan). cf. gaps.
    private func nutritionSolutions(for nutrients: [EnrichedNutrient]) -> [PlanNutritionSolution] {
        var out: [PlanNutritionSolution] = []
        var seen = Set<String>()
        for n in nutrients {
            for food in Fluent3D.foodSources(for: n.id) where !seen.contains(food.label) {
                seen.insert(food.label)
                out.append(PlanNutritionSolution(
                    asset: food.asset,
                    label: food.label,
                    note: "Riche en \(n.label.lowercased())",
                    qty: "1 portion par jour",
                    moment: n.solution?.quand?.isEmpty == false ? n.solution!.quand! : "Au repas principal",
                    cuisson: "Cuisson douce pour préserver les apports",
                    astuce: n.synergie?.isEmpty == false ? n.synergie! : "À associer à une source de vitamine C"
                ))
                if out.count >= 4 { return out }
            }
        }
        return out
    }

    // MARK: - Solutions « Par les habitudes »
    private func habitSolutions(for nutrients: [EnrichedNutrient], kind: PlanTopic.Kind) -> [PlanHabitSolution] {
        var out: [PlanHabitSolution] = [
            PlanHabitSolution(symbol: "sun.max.fill", text: "Un peu de lumière le matin",
                              note: "10 min dehors réveillent ton horloge interne"),
            PlanHabitSolution(symbol: "bed.double.fill", text: "Un sommeil régulier",
                              note: "Couche-toi à heure fixe pour mieux récupérer")
        ]
        if nutrients.contains(where: { $0.id == "iron" }) {
            out.append(PlanHabitSolution(symbol: "cup.and.saucer.fill", text: "Décale thé et café",
                                         note: "Loin des repas riches en fer pour mieux l'absorber"))
        }
        return Array(out.prefix(3))
    }

    // MARK: - Habitudes par objectif (leviers d'hygiène de vie)
    /// Habitudes affichées : pour un OBJECTIF, des leviers d'hygiène de vie ciblés
    /// par thème (sommeil, énergie, poids, stress, digestion) — jamais une reco
    /// nutriment hors-sujet. Pour un SYMPTÔME, comportement existant inchangé.
    private func habits(for nutrients: [EnrichedNutrient], kind: PlanTopic.Kind, objectifName: String) -> [PlanHabitSolution] {
        guard kind == .objectif else { return habitSolutions(for: nutrients, kind: kind) }
        return lifestyleHabits(forObjective: objectifName)
    }

    /// Leviers d'hygiène de vie par grand thème d'objectif. Conseils de bien-être
    /// génériques (jamais de l'ordre du soin) ; un apport n'apparaît que s'il est
    /// pertinent ET réellement insuffisant (cf. `focus`).
    private func lifestyleHabits(forObjective name: String) -> [PlanHabitSolution] {
        let key = name.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { key.contains($0) } }

        if has(["dorm", "sommeil", "endorm", "nuit"]) {
            return [
                PlanHabitSolution(symbol: "sun.max.fill", text: "Lumière le matin",
                                  note: "10 min dehors recalent ton horloge interne"),
                PlanHabitSolution(symbol: "bed.double.fill", text: "Un sommeil régulier",
                                  note: "Couche-toi à heure fixe pour mieux récupérer"),
                PlanHabitSolution(symbol: "cup.and.saucer.fill", text: "Décale la caféine",
                                  note: "Évite café et thé après 14h")
            ]
        }
        if has(["énerg", "energ", "fatigue", "forme", "vitalit", "tonus"]) {
            return [
                PlanHabitSolution(symbol: "figure.walk", text: "Bouge chaque jour",
                                  note: "20 min de marche relancent ton énergie"),
                PlanHabitSolution(symbol: "sun.max.fill", text: "Lumière le matin",
                                  note: "Elle cale ton rythme et ton réveil"),
                PlanHabitSolution(symbol: "drop.fill", text: "Bois régulièrement",
                                  note: "Le manque d'eau fatigue vite")
            ]
        }
        if has(["poids", "maigr", "mince", "ligne", "perdre", "affin"]) {
            return [
                PlanHabitSolution(symbol: "fork.knife", text: "Des portions repérées",
                                  note: "Sers-toi une fois, dans une assiette plus petite"),
                PlanHabitSolution(symbol: "figure.walk", text: "Marche après les repas",
                                  note: "10 min aident à rester actif au quotidien"),
                PlanHabitSolution(symbol: "drop.fill", text: "Bois avant de grignoter",
                                  note: "La soif se confond souvent avec la faim")
            ]
        }
        if has(["stress", "anxi", "calme", "sérén", "seren", "détente", "detente", "zen"]) {
            return [
                PlanHabitSolution(symbol: "wind", text: "Respire en conscience",
                                  note: "3 min de respiration lente apaisent le tempo"),
                PlanHabitSolution(symbol: "figure.walk", text: "Bouge pour décharger",
                                  note: "Une marche dehors aère la tête"),
                PlanHabitSolution(symbol: "moon.stars.fill", text: "Coupe les écrans le soir",
                                  note: "30 min sans écran avant le coucher")
            ]
        }
        if has(["digest", "ventre", "transit", "ballonn", "intestin"]) {
            return [
                PlanHabitSolution(symbol: "fork.knife", text: "Mange posément",
                                  note: "Mâche bien, sans précipiter le repas"),
                PlanHabitSolution(symbol: "figure.walk", text: "Marche après manger",
                                  note: "Quelques minutes facilitent la digestion"),
                PlanHabitSolution(symbol: "drop.fill", text: "Hydrate-toi dans la journée",
                                  note: "L'eau soutient un transit régulier")
            ]
        }
        // Objectif générique : leviers universels.
        return [
            PlanHabitSolution(symbol: "figure.walk", text: "Bouge chaque jour",
                              note: "20 min de marche, c'est déjà beaucoup"),
            PlanHabitSolution(symbol: "bed.double.fill", text: "Un sommeil régulier",
                              note: "Couche-toi à heure fixe pour mieux récupérer")
        ]
    }

    // MARK: - Solutions « Par les compléments »
    // Priorité dérivée du score de l'apport (plus le score est bas, plus c'est
    // prioritaire). Le détail timing/dose vit sur l'onglet Compléments.
    private func supplementSolutions(for nutrients: [EnrichedNutrient]) -> [PlanSupplementSolution] {
        nutrients.prefix(3).map { n in
            let strong = n.score < 45
            return PlanSupplementSolution(
                name: n.label,
                note: n.solution?.dosage?.isEmpty == false ? n.solution!.dosage! : "À envisager si l'alimentation ne suffit pas",
                tag: strong ? "Prioritaire" : "Si besoin",
                strong: strong
            )
        }
    }

    // MARK: - Textes d'intro
    private func symptomeIntro(_ s: SymptomeAnalyse) -> String {
        if let causes = s.causesProbables, !causes.isEmpty {
            return causes.prefix(2).joined(separator: " ")
        }
        return "On regarde ce qui pourrait l'expliquer sur ton profil."
    }

    private func objectifIntro(impact: String?) -> String {
        if let impact, !impact.isEmpty { return impact }
        return "Voici sur quoi agir pour t'en rapprocher."
    }

    // MARK: - Helpers
    /// Détecte les apports cités dans un texte libre (cause, levier…).
    private func nutrientsMentioned(in text: String) -> [EnrichedNutrient] {
        guard !text.isEmpty else { return [] }
        return vm.topDeficiencies.filter { text.localizedCaseInsensitiveContains($0.label) }
    }

    /// Rend une clé brute (« fatigue_persistante ») présentable.
    private func prettify(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        guard let first = cleaned.first else { return cleaned }
        return first.uppercased() + cleaned.dropFirst()
    }
}

#Preview {
    RecommendationsView()
        .environmentObject(DashboardViewModel())
}
