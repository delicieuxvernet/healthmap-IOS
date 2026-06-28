import SwiftUI
import Combine

// MARK: - Recommendations View (Mon plan — langage v4 3D)
//
// Refonte v4 (maquette « Plan v4 - 3D ») : fond crème, cartes blanches
// arrondies (.kiwiCard), héro gamifié (niveau + XP en vert kiwi + série +
// anneau objectif), une carte par besoin avec actions cochables, sections
// symptômes/objectifs, tuiles jumelles Compléments/Analyses, case premium
// floutée, disclaimer.
//
// La LOGIQUE est conservée à l'identique : mêmes bindings au ViewModel, même
// persistance des coches (PlanCheckStore), même attribution d'XP une seule fois
// par action (GamificationService.awardXPOnce). Seul l'habillage change.
struct RecommendationsView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                // Fond crème chaud du langage v4 (= healthMapWarm).
                Color.kiwiCream.ignoresSafeArea()

                if let analysis = dashboardVM.aiAnalysis {
                    RecommendationsContentView(analysis: analysis)
                } else if dashboardVM.isLoadingAnalysis {
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
            .navigationTitle("Mon plan")
            .navigationBarTitleDisplayMode(.large)
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

    /// Actions cochées (ids stables), persistées par utilisateur.
    @State private var checkedIds: Set<String> = []
    @ObservedObject private var gamification = GamificationService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(analysis: MergedAnalysis) {
        _vm = StateObject(wrappedValue: RecommendationsViewModel(analysis: analysis))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // En-tête éditorial (sentence case — maquette « Ton plan »).
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ton plan")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Text(needsSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 4)

                // 0. Héro gamifié : niveau + XP (vert kiwi) + série + anneau objectif.
                if !allActionItems.isEmpty {
                    PlanLevelHeroV4(
                        done: doneCount,
                        total: allActionItems.count,
                        level: gamification.level,
                        xpInLevel: gamification.xpInLevel,
                        xpPerLevel: GamificationService.xpPerLevel,
                        streak: gamification.currentStreak,
                        reduceMotion: reduceMotion
                    )
                    .padding(.horizontal, 24)
                }

                // 1. Une carte par besoin (top 3) — actions cochables.
                ForEach(Array(vm.topDeficiencies.prefix(3).enumerated()), id: \.element.id) { index, nutrient in
                    NeedCardV4(
                        nutrient: nutrient,
                        actions: actionItems(for: nutrient, isFirst: index == 0),
                        footerText: footerText(for: nutrient),
                        checkedIds: $checkedIds,
                        onToggle: { id in toggle(id) }
                    )
                    .padding(.horizontal, 24)
                }

                // 2. Enquête par symptôme : causes croisées issues de TOUT le profil.
                if !vm.symptomesAnalyse.isEmpty {
                    SymptomesAnalyseSectionV4(symptomes: vm.symptomesAnalyse)
                        .padding(.horizontal, 24)
                }

                // 3. Enquête par objectif : freins + leviers personnalisés.
                if !vm.objectifsAnalyse.isEmpty {
                    ObjectifsAnalyseSectionV4(objectifs: vm.objectifsAnalyse)
                        .padding(.horizontal, 24)
                }

                // 4. Rangée symétrique Compléments / Analyses.
                HStack(spacing: 12) {
                    PlanTileV4(title: "Compléments", subtitle: supplementsSummary, systemImage: "pills.fill")
                    PlanTileV4(title: "Analyses", subtitle: bloodTestsSummary, systemImage: "drop.fill")
                }
                .padding(.horizontal, 24)

                // 5. Interaction (1 ligne — le détail vit sur le Bilan/fiche).
                if let interaction = vm.interactions.first, let titre = interaction.titre, !titre.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.scoreLow)
                            .accessibilityHidden(true)
                        Text(titre)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.kiwiCharcoal)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kiwiCard(radius: 20)
                    .padding(.horizontal, 24)
                }

                // 6. Case premium floutée : contenu RÉEL borné (loi 11).
                if let warnings = vm.analysis.supplementsSchedule?.warnings, !warnings.isEmpty {
                    BlurredSection(isPremium: true, title: "Le timing parfait de tes compléments") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(warnings.prefix(3).enumerated()), id: \.offset) { _, warning in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.kiwiGreen)
                                        .accessibilityHidden(true)
                                    Text(warning)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.kiwiCharcoal)
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .kiwiCard(radius: 20)
                    }
                    .padding(.horizontal, 24)
                }

                // 7. Disclaimer unique, 1 ligne (loi 12).
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.healthMapMuted)
                    Text("Informatif\u{202F}: ne remplace pas un avis médical.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.healthMapMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.vertical, 8)
            }
            .padding(.vertical, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            checkedIds = PlanCheckStore.load()
            // Expose le total d'actions du plan au Bilan (« Mon évolution »)
            // pour calculer l'adhésion (done/total) sans recopier la logique.
            PlanProgressStore.saveTotal(allActionItems.count)
        }
        .onReceive(dashboardVM.$aiAnalysis) { newAnalysis in
            if let newAnalysis {
                vm.updateAnalysis(newAnalysis)
            }
        }
    }

    // MARK: - Anneau « objectif » : actions du plan cochées / total
    /// Toutes les actions du plan (top 3 besoins), dédupliquées par id.
    private var allActionItems: [PlanActionItem] {
        var items: [PlanActionItem] = []
        var seen = Set<String>()
        for (index, nutrient) in vm.topDeficiencies.prefix(3).enumerated() {
            for item in actionItems(for: nutrient, isFirst: index == 0) where !seen.contains(item.id) {
                seen.insert(item.id)
                items.append(item)
            }
        }
        return items
    }

    private var doneCount: Int {
        allActionItems.filter { checkedIds.contains($0.id) }.count
    }

    // MARK: - Sous-titre (pluriel dynamique)
    private var needsSubtitle: String {
        let n = min(vm.topDeficiencies.count, 3)
        guard n > 0 else { return "Ce qu'il faut faire, et quand." }
        return n > 1
            ? "\(n) besoins du jour identifiés dans ton bilan"
            : "1 besoin du jour identifié dans ton bilan"
    }

    // MARK: - Actions par besoin
    // Rattachement : la solution du nutriment d'abord, puis les actions IA
    // qui mentionnent son nom ; les actions générales restantes vont au
    // besoin n°1. Dédupliquées, 3 max par carte.
    private func actionItems(for nutrient: EnrichedNutrient, isFirst: Bool) -> [PlanActionItem] {
        var items: [PlanActionItem] = []
        var seen = Set<String>()
        func add(_ id: String, _ text: String?) {
            guard let text, !text.isEmpty, !seen.contains(text.lowercased()) else { return }
            seen.insert(text.lowercased())
            items.append(PlanActionItem(id: id, text: text))
        }

        add("sol_\(nutrient.id)", nutrient.solution?.action)

        for pa in vm.analysis.priorityActions
        where (pa.action ?? "").localizedCaseInsensitiveContains(nutrient.label) {
            add("pa_\(pa.rank)", pa.action)
        }

        if isFirst {
            for pa in vm.analysis.priorityActions {
                let matchesADeficiency = vm.topDeficiencies.prefix(3).contains { deficiency in
                    (pa.action ?? "").localizedCaseInsensitiveContains(deficiency.label)
                }
                if !matchesADeficiency {
                    add("pa_\(pa.rank)", pa.action)
                }
            }
        }

        return Array(items.prefix(3))
    }

    /// Footer vert « [bénéfice], [délai] » — vocabulaire calibré serveur,
    /// jamais de tiret long.
    private func footerText(for nutrient: EnrichedNutrient) -> String? {
        let benefit = vm.analysis.priorityActions
            .first { ($0.action ?? "").localizedCaseInsensitiveContains(nutrient.label) }?
            .expectedImpact
        let delai = nutrient.solution?.delai
        let parts = [benefit, delai].compactMap { $0?.isEmpty == false ? $0 : nil }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    private func toggle(_ id: String) {
        let willCheck = !checkedIds.contains(id)
        HapticService.shared.primary()
        withAnimation(reduceMotion ? .none : .healthMapSpring) {
            if checkedIds.contains(id) {
                checkedIds.remove(id)
            } else {
                checkedIds.insert(id)
            }
        }
        PlanCheckStore.save(checkedIds)

        // Gamification (dopamine) : XP crédité une seule fois par action, et
        // célébration quand TOUTES les actions du plan sont cochées.
        if willCheck {
            gamification.awardXPOnce(key: "plan_\(id)", amount: 45)
            if !allActionItems.isEmpty && doneCount == allActionItems.count {
                HapticService.shared.success()
            }
        }
    }

    // MARK: - Résumés des tuiles Compléments / Analyses
    private var supplementsSummary: String {
        guard let schedule = vm.analysis.supplementsSchedule else { return "Aucun pour l'instant" }
        let morning = schedule.morning ?? []
        let afternoon = schedule.afternoon ?? []
        let evening = schedule.evening ?? []
        var parts: [String] = []
        if !morning.isEmpty { parts.append("\(morning.count) le matin") }
        if !afternoon.isEmpty { parts.append("\(afternoon.count) le midi") }
        if !evening.isEmpty { parts.append("\(evening.count) le soir") }
        return parts.isEmpty ? "Aucun pour l'instant" : parts.joined(separator: " · ")
    }

    private var bloodTestsSummary: String {
        guard let tests = vm.analysis.bloodTests?.tests, !tests.isEmpty else {
            return "Aucune analyse conseillée"
        }
        return tests.prefix(3).joined(separator: ", ")
    }
}

// MARK: - Plan Check Store (persistance des actions cochées)
// Clé scopée par utilisateur ; ids stables (sol_<nutrient> / pa_<rank>) →
// l'état survit aux relances.
@MainActor
private enum PlanCheckStore {
    private static var key: String {
        let uid = AuthService.shared.cachedCurrentUserIdString ?? "anonymous"
        return "healthmap_plan_checked_\(uid)"
    }

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func save(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids).sorted(), forKey: key)
    }
}

#Preview {
    RecommendationsView()
        .environmentObject(DashboardViewModel())
}
