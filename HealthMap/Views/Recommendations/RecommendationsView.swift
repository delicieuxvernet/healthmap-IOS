import SwiftUI
import Combine

// MARK: - Recommendations View (Mon Plan — DESIGN-PAGES §3)
// Refonte du 12 juin (maquette validée par Arthur) :
//   1. Header « Mon plan » + sous-titre discret « N besoin(s) identifié(s) »
//   2. UNE CARTE PAR BESOIN (top 3) : actions cochables (persistées par
//      utilisateur) + footer vert « [bénéfice], [délai] »
//   3. Rangée symétrique 2 tuiles : Compléments / Analyses
//   4. 1 ligne interaction (titre, 1 ligne max)
//   5. Case premium floutée « Le timing parfait de tes compléments »
//   6. Disclaimer 1 ligne (loi 12)
// Supprimés : red flags et points forts dupliqués (vivent sur le Bilan),
// « plan 3 phases » codé en dur (fausse personnalisation), stats IMC/TDEE
// (→ Profil), CTA premium plein écran, listes de pépites (vivent sur le Bilan).
struct RecommendationsView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                // Fond chaud unifié, statique (WarmBackground).
                WarmBackground()

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
            .navigationTitle("Mon Plan")
            .navigationBarTitleDisplayMode(.large)
            .healthMapProfileToolbar()
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
            VStack(spacing: Theme.spacingLG) {
                // 0. Héro gamifié : anneau « objectif » qui se referme + niveau + série
                //    (dopamine premium validée par Arthur, 14 juin). Données RÉELLES :
                //    actions cochées / total (anneau), XP/niveau + série (GamificationService).
                if !allActionItems.isEmpty {
                    PlanGoalHero(
                        done: doneCount,
                        total: allActionItems.count,
                        level: gamification.level,
                        xpInLevel: gamification.xpInLevel,
                        xpPerLevel: GamificationService.xpPerLevel,
                        streak: gamification.currentStreak,
                        reduceMotion: reduceMotion
                    )
                    .padding(.horizontal, Theme.spacingLG)
                }

                // 1. Sous-titre d'orientation (pluriel dynamique — loi 15)
                if !vm.topDeficiencies.isEmpty {
                    Text(needsSubtitle)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.spacingLG)
                }

                // 2. Une carte par besoin (top 3)
                ForEach(Array(vm.topDeficiencies.prefix(3).enumerated()), id: \.element.id) { index, nutrient in
                    NeedCard(
                        nutrient: nutrient,
                        actions: actionItems(for: nutrient, isFirst: index == 0),
                        footerText: footerText(for: nutrient),
                        checkedIds: $checkedIds,
                        onToggle: { id in toggle(id) }
                    )
                    .padding(.horizontal, Theme.spacingLG)
                }

                // 3. Rangée symétrique Compléments / Analyses (loi 6)
                planTilesRow
                    .padding(.horizontal, Theme.spacingLG)

                // 4. Interaction (1 ligne — le détail vit sur le Bilan/fiche)
                if let interaction = vm.interactions.first, let titre = interaction.titre, !titre.isEmpty {
                    HStack(spacing: Theme.spacingSM) {
                        Text(interaction.emoji ?? "\u{26A1}")
                            .font(.system(size: 16))
                        Text(titre)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.healthMapText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                    }
                    .padding(Theme.spacingMD)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    .padding(.horizontal, Theme.spacingLG)
                }

                // 5. Case premium floutée : contenu RÉEL borné (loi 11)
                if let warnings = vm.analysis.supplementsSchedule?.warnings, !warnings.isEmpty {
                    BlurredSection(isPremium: true, title: "Le timing parfait de tes compléments") {
                        VStack(alignment: .leading, spacing: Theme.spacingSM) {
                            ForEach(Array(warnings.prefix(3).enumerated()), id: \.offset) { _, warning in
                                HStack(alignment: .top, spacing: Theme.spacingXS) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.healthMapBlue)
                                        .accessibilityHidden(true)
                                    Text(warning)
                                        .font(Theme.captionFont)
                                        .foregroundStyle(Color.healthMapText)
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(Theme.spacingMD)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                    }
                    .padding(.horizontal, Theme.spacingLG)
                }

                // 6. Disclaimer unique, 1 ligne (loi 12)
                HStack(alignment: .center, spacing: Theme.spacingSM) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.healthMapMuted)
                    Text("Informatif\u{202F}: ne remplace pas un avis médical.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.healthMapMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(Theme.spacingSM)
            }
            .padding(.vertical, Theme.spacingMD)
        }
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
        return n > 1 ? "\(n) besoins identifiés dans ton bilan" : "1 besoin identifié dans ton bilan"
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
                // Célébration : haptique de succès. L'anneau se referme en coche
                // et un petit burst de confettis joue dans la carte (PlanGoalHero).
                HapticService.shared.success()
            }
        }
    }

    // MARK: - Tuiles Compléments / Analyses (loi 6 : strictement jumelles)
    private var planTilesRow: some View {
        HStack(spacing: Theme.spacingSM) {
            planTile(title: "Compléments", subtitle: supplementsSummary)
            planTile(title: "Analyses", subtitle: bloodTestsSummary)
        }
    }

    private func planTile(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.healthMapText)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color.healthMapSecondary)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

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

// MARK: - Plan Action Item
private struct PlanActionItem: Identifiable {
    let id: String
    let text: String
}

// MARK: - Need Card (une carte par besoin — bloc 2)
// Source : EnrichedNutrient (état HealthScale) + actions rattachées.
// Action cochée = cercle vert + texte barré ; haptic au tap ; footer vert
// « bénéfice, délai ». Couleur d'état = f(score) (loi 3). Textes IA bornés.
private struct NeedCard: View {
    let nutrient: EnrichedNutrient
    let actions: [PlanActionItem]
    let footerText: String?
    @Binding var checkedIds: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Text("\(nutrient.label) \(nutrient.emoji)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                    .lineLimit(1)

                Spacer()

                Text(HealthScale.nutrientLabel(for: nutrient.score))
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.scoreColor(for: nutrient.score))
            }

            ForEach(actions) { action in
                Button {
                    onToggle(action.id)
                } label: {
                    HStack(alignment: .top, spacing: Theme.spacingSM) {
                        Image(systemName: checkedIds.contains(action.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(checkedIds.contains(action.id) ? Color.scoreExcellent : Color.healthMapMuted)
                            .accessibilityHidden(true)

                        Text(action.text)
                            .font(Theme.captionFont)
                            .foregroundStyle(checkedIds.contains(action.id) ? Color.healthMapMuted : Color.healthMapText)
                            .strikethrough(checkedIds.contains(action.id))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
                .accessibilityLabel("\(checkedIds.contains(action.id) ? "Fait" : "À faire")\u{202F}: \(action.text)")
            }

            if let footerText {
                HStack(spacing: Theme.spacingXS) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.scoreExcellent)
                        .accessibilityHidden(true)
                    Text("Résultat attendu\u{202F}: \(footerText)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.scoreExcellent)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .padding(Theme.spacingSM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.scoreExcellent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - Plan Goal Hero (anneau objectif + niveau + série — gamification)
private struct PlanGoalHero: View {
    let done: Int
    let total: Int
    let level: Int
    let xpInLevel: Int
    let xpPerLevel: Int
    let streak: Int
    let reduceMotion: Bool

    @State private var burst = false
    private var complete: Bool { total > 0 && done >= total }

    var body: some View {
        HStack(spacing: Theme.spacingMD) {
            PlanGoalRing(done: done, total: total, reduceMotion: reduceMotion)
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text(complete ? "Objectif du jour atteint, bravo\u{202F}!" : "Ton objectif du jour")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.spacingXS) {
                    Text("Niveau \(level)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentIndigo)
                    Spacer(minLength: 0)
                    Text("\(xpInLevel) / \(xpPerLevel) XP")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.healthMapSecondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.accentIndigo.opacity(0.15))
                        Capsule().fill(Color.accentIndigo)
                            .frame(width: geo.size.width * CGFloat(min(1, Double(xpInLevel) / Double(max(1, xpPerLevel)))))
                    }
                }
                .frame(height: 7)

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentSky)
                        .accessibilityHidden(true)
                    Text(streak > 0 ? "Série de \(streak) jour\(streak > 1 ? "s" : "")" : "Commence ta série aujourd'hui")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .overlay {
            if burst && !reduceMotion {
                PlanConfettiBurst().allowsHitTesting(false)
            }
        }
        .onChange(of: complete) { _, now in
            // Confetti seulement à l'objectif atteint, hors reduce-motion et hors mode zen.
            if now && !reduceMotion && !GamificationService.shared.isZenMode {
                burst = true
            }
            if !now { burst = false }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Objectif du jour : \(done) actions sur \(total) faites. Niveau \(level). Série de \(streak) jours.")
    }
}

// MARK: - Plan Goal Ring (anneau qui se referme, dégradé premium bleu → indigo)
private struct PlanGoalRing: View {
    let done: Int
    let total: Int
    let reduceMotion: Bool

    @State private var animated: CGFloat = 0

    private var progress: CGFloat {
        total > 0 ? CGFloat(done) / CGFloat(total) : 0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.healthMapBlue.opacity(0.14), lineWidth: 9)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(
                    LinearGradient(
                        colors: [Color.healthMapBlue, Color.accentIndigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if total > 0 && done >= total {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.accentIndigo)
            } else {
                VStack(spacing: 0) {
                    Text("\(done)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.healthMapText)
                    Text("/ \(total)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.healthMapMuted)
                }
            }
        }
        .onAppear { setProgress() }
        .onChange(of: progress) { _, _ in setProgress() }
    }

    private func setProgress() {
        if reduceMotion {
            animated = progress
        } else {
            withAnimation(.easeOut(duration: 0.6)) { animated = progress }
        }
    }
}

// MARK: - Plan Confetti Burst (petite célébration in-carte à l'objectif atteint)
// Auto-contenu (l'émetteur de CelebrationView est privé). Pièces qui partent du
// centre vers l'extérieur puis s'effacent. Gelé si reduce-motion (côté appelant).
private struct PlanConfettiBurst: View {
    private let pieces = 16
    private let colors: [Color] = [.healthMapBlue, .accentIndigo, .accentSky, .scoreExcellent, Color(hex: "FFB8EC")]

    var body: some View {
        ZStack {
            ForEach(0..<pieces, id: \.self) { i in
                PlanConfettiPiece(
                    color: colors[i % colors.count],
                    angle: Double(i) / Double(pieces) * 2 * .pi,
                    distance: CGFloat.random(in: 60...120),
                    size: CGFloat.random(in: 6...10),
                    delay: Double(i) * 0.012
                )
            }
        }
    }
}

private struct PlanConfettiPiece: View {
    let color: Color
    let angle: Double
    let distance: CGFloat
    let size: CGFloat
    let delay: Double
    @State private var go = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: size, height: size * 0.6)
            .offset(x: go ? CGFloat(cos(angle)) * distance : 0,
                    y: go ? CGFloat(sin(angle)) * distance : 0)
            .rotationEffect(.degrees(go ? 220 : 0))
            .opacity(go ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.7).delay(delay)) { go = true }
            }
    }
}

// MARK: - Plan Check Store (persistance des actions cochées)
// Clé scopée par utilisateur (même esprit que le draft questionnaire) ;
// ids stables (sol_<nutrient> / pa_<rank>) → l'état survit aux relances.
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
