import SwiftUI
import Combine

// MARK: - Recommendations View (Mon Plan)
struct RecommendationsView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color.healthMapBackground
                    .ignoresSafeArea()

                if let analysis = dashboardVM.aiAnalysis {
                    RecommendationsContentView(analysis: analysis)
                } else if dashboardVM.isLoadingAnalysis {
                    VStack(spacing: Theme.spacingMD) {
                        MascotView(mood: .thinking, size: 72)
                        ProgressView()
                            .tint(Color.healthMapBlue)
                        Text("Chargement du plan...")
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
        }
    }
}

// MARK: - Recommendations Content (ViewModel stable)
/// Contenu du plan une fois l'analyse disponible. Le ViewModel est un
/// `@StateObject` : il n'est créé qu'UNE fois par cycle de vie de la vue
/// (l'ancien code instanciait `RecommendationsViewModel(analysis:)` à chaque
/// évaluation de `body`). Si l'analyse est régénérée pendant que l'écran est
/// affiché, `onReceive` resynchronise le ViewModel existant sans recréation.
struct RecommendationsContentView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @StateObject private var vm: RecommendationsViewModel
    @State private var expandedNutrientIDs: Set<String> = []
    @State var showPaywall = false

    init(analysis: MergedAnalysis) {
        _vm = StateObject(wrappedValue: RecommendationsViewModel(analysis: analysis))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacingLG) {
                if vm.hasRedFlags { redFlagsSection(vm: vm) }
                if vm.hasInteractions { interactionsSection(vm: vm) }
                if vm.hasPriorityActions { priorityActionsSection(vm: vm) }
                if vm.hasDeficiencies { deficienciesSection(vm: vm) }
                if vm.hasPositiveFindings { positiveFindingsSection(vm: vm) }
                if vm.hasPepites { pepitesSection(vm: vm) }
                if vm.shouldDoBloodTest { bloodTestsSection(vm: vm) }
                if vm.hasSuppSchedule { supplementsTeaser(vm: vm) }

                planSection
                statsSection(vm: vm)

                if !SubscriptionService.shared.isPremium {
                    premiumCTASection
                }

                MedicalDisclaimerView()
                    .padding(.horizontal, Theme.spacingLG)
            }
            .padding(.vertical, Theme.spacingMD)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .healthMapFullSheet()
        }
        .onReceive(dashboardVM.$aiAnalysis) { newAnalysis in
            if let newAnalysis {
                vm.updateAnalysis(newAnalysis)
            }
        }
    }

    // MARK: - Sections

    private func redFlagsSection(vm: RecommendationsViewModel) -> some View {
        sectionContainer(title: "Points d'attention", icon: "exclamationmark.triangle.fill", iconColor: .urgencyImmediate) {
            RedFlagsCardView(flags: vm.redFlags)
        }
    }

    private func interactionsSection(vm: RecommendationsViewModel) -> some View {
        sectionContainer(title: "Interactions detectees", icon: "arrow.triangle.merge", iconColor: .healthMapBlue) {
            VStack(spacing: Theme.spacingSM) {
                if let first = vm.interactions.first {
                    InteractionCardView(interaction: first)
                }
                if vm.interactions.count > 1 {
                    let remaining = Array(vm.interactions.dropFirst())
                    BlurredSection(isPremium: true, title: "\(remaining.count) autres interactions") {
                        VStack(spacing: Theme.spacingSM) {
                            ForEach(remaining) { interaction in
                                InteractionCardView(interaction: interaction)
                            }
                        }
                    }
                }
            }
        }
    }

    private func priorityActionsSection(vm: RecommendationsViewModel) -> some View {
        sectionContainer(title: "Actions prioritaires", icon: "target", iconColor: .healthMapBlue) {
            VStack(spacing: Theme.spacingSM) {
                ForEach(vm.priorityActions) { action in
                    HStack(alignment: .top, spacing: Theme.spacingSM) {
                        Text("\(action.rank ?? 0)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.healthMapBlue)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            if let actionText = action.action {
                                Text(actionText)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.healthMapText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack(spacing: Theme.spacingSM) {
                                if let impact = action.expectedImpact {
                                    Label(impact, systemImage: "bolt.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.healthMapBlue)
                                }
                                if let difficulty = action.difficulty {
                                    Label(difficulty, systemImage: "gauge.low")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.healthMapSecondary)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(Theme.spacingSM)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                            .fill(Color.healthMapCard)
                    )
                }
            }
        }
    }

    private func deficienciesSection(vm: RecommendationsViewModel) -> some View {
        sectionContainer(title: "Nutriments a renforcer", icon: "chart.bar.doc.horizontal", iconColor: .scoreLow) {
            VStack(spacing: Theme.spacingSM) {
                ForEach(vm.topDeficiencies) { nutrient in
                    let isExpanded = expandedNutrientIDs.contains(nutrient.id)
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if isExpanded { expandedNutrientIDs.remove(nutrient.id) }
                                else { expandedNutrientIDs.insert(nutrient.id) }
                            }
                        } label: {
                            deficiencyHeader(nutrient: nutrient, isExpanded: isExpanded)
                        }
                        .buttonStyle(.healthMapPressed)

                        if isExpanded {
                            deficiencyDetail(nutrient: nutrient)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                            .fill(Color.healthMapCard)
                    )
                }
            }
        }
    }

    private func deficiencyHeader(nutrient: EnrichedNutrient, isExpanded: Bool) -> some View {
        HStack(spacing: Theme.spacingSM) {
            Text(nutrient.emoji).font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(nutrient.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                if let verdict = nutrient.verdict {
                    Text(verdict)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                        .lineLimit(isExpanded ? nil : 2)
                }
            }
            Spacer()
            MiniScoreRing(score: nutrient.score, color: Color.nutrientColor(for: nutrient.id), size: 36)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.healthMapMuted)
        }
        .padding(Theme.spacingSM)
    }

    private func deficiencyDetail(nutrient: EnrichedNutrient) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Divider().padding(.horizontal, Theme.spacingSM)

            if let mecanisme = nutrient.mecanisme {
                nutrientDetailRow(icon: "gearshape.2", title: "Mecanisme", content: mecanisme, color: .healthMapBlue)
            }
            if let signe = nutrient.signeManque {
                nutrientDetailRow(icon: "exclamationmark.triangle", title: "Signes de manque", content: signe, color: .scoreLow)
            }
            if let sol = nutrient.solution {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Solution", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.scoreGood)
                    if let action = sol.action { nutrientDetailInlineRow(label: "Action", value: action) }
                    if let dosage = sol.dosage { nutrientDetailInlineRow(label: "Dosage", value: dosage) }
                }
                .padding(.horizontal, Theme.spacingSM)
            }
            if let hack = nutrient.hack {
                nutrientDetailRow(icon: "star.fill", title: "Astuce", content: hack, color: .accentSky)
            }
            if let synergie = nutrient.synergie {
                nutrientDetailRow(icon: "arrow.triangle.merge", title: "Synergie", content: synergie, color: .accentIndigo)
            }
        }
        .padding(.bottom, Theme.spacingSM)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func nutrientDetailRow(icon: String, title: String, content: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
            Text(content)
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.spacingSM)
    }

    private func nutrientDetailInlineRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.healthMapSecondary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func positiveFindingsSection(vm: RecommendationsViewModel) -> some View {
        sectionContainer(title: "Points forts", icon: "hand.thumbsup.fill", iconColor: .scoreGood) {
            VStack(spacing: Theme.spacingSM) {
                ForEach(vm.positiveFindings) { finding in
                    HStack(alignment: .top, spacing: Theme.spacingSM) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.scoreGood)
                        VStack(alignment: .leading, spacing: 2) {
                            if let text = finding.finding {
                                Text(text).font(Theme.bodyFont).foregroundStyle(Color.healthMapText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            // Labels canoniques via NutrientData (jamais d'ids
                            // bruts type « vitD ») ; un id hors catalogue est
                            // ignoré proprement (compactMap).
                            if let ids = finding.nutrientsCovered, !ids.isEmpty {
                                let covered = ids.compactMap { NutrientData.definition(for: $0) }
                                if !covered.isEmpty {
                                    HStack(spacing: 4) {
                                        ForEach(covered) { def in
                                            Text("\(def.emoji) \(def.label)")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(Color.scoreGood)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color.scoreGood.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(Theme.spacingSM)
                }
            }
            .padding(Theme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.scoreGood.opacity(0.04))
            )
        }
    }

    private func pepitesSection(vm: RecommendationsViewModel) -> some View {
        sectionContainer(title: "Pepites sante", icon: "lightbulb.fill", iconColor: .healthMapBlue) {
            VStack(spacing: Theme.spacingSM) {
                ForEach(Array(vm.pepites.prefix(2))) { pepite in pepiteCard(pepite) }
                if vm.pepites.count > 2 {
                    let remaining = Array(vm.pepites.dropFirst(2))
                    BlurredSection(isPremium: true, title: "\(remaining.count) autres pepites") {
                        VStack(spacing: Theme.spacingSM) {
                            ForEach(remaining) { pepite in pepiteCard(pepite) }
                        }
                    }
                }
            }
        }
    }

    private func pepiteCard(_ pepite: PracticalTip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.spacingSM) {
                Text(pepite.emoji ?? "\u{1F4A1}").font(.system(size: 18))
                Text(pepite.hook ?? pepite.tip ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = pepite.detail ?? pepite.why {
                Text(detail).font(Theme.captionFont).foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 34)
            }
        }
        .padding(Theme.spacingSM)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous).fill(Color.healthMapCard))
    }

    private func bloodTestsSection(vm: RecommendationsViewModel) -> some View {
        sectionContainer(title: "Analyses sanguines", icon: "cross.vial.fill", iconColor: .urgencySoon) {
            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                if let why = vm.bloodTestReason {
                    Text(why).font(Theme.bodyFont).foregroundStyle(Color.healthMapText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !vm.recommendedTests.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Analyses recommandees :").font(Theme.captionBoldFont).foregroundStyle(Color.healthMapSecondary)
                        ForEach(vm.recommendedTests, id: \.self) { test in
                            HStack(spacing: Theme.spacingSM) {
                                Image(systemName: "drop.fill").font(.system(size: 10)).foregroundStyle(Color.urgencySoon)
                                Text(test).font(Theme.bodyFont).foregroundStyle(Color.healthMapText)
                            }
                        }
                    }
                }
            }
            .padding(Theme.spacingMD)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Color.urgencySoon.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).stroke(Color.urgencySoon.opacity(0.15), lineWidth: 1))
        }
    }

    private func supplementsTeaser(vm: RecommendationsViewModel) -> some View {
        sectionContainer(title: "Complements", icon: "pills.fill", iconColor: .healthMapBlue) {
            HStack(spacing: Theme.spacingMD) {
                Image(systemName: "pills.fill").font(.system(size: 28)).foregroundStyle(Color.healthMapBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Planning complements").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.healthMapText)
                    Text("Matin, midi, soir -- tout est organise.").font(Theme.captionFont).foregroundStyle(Color.healthMapSecondary)
                }
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 14)).foregroundStyle(Color.healthMapBlue)
            }
            .padding(Theme.spacingMD)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Color.healthMapBlueLight))
        }
    }

}

// MARK: - Medical Disclaimer
private struct MedicalDisclaimerView: View {
    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: "info.circle.fill").font(.system(size: 14)).foregroundStyle(Color.healthMapMuted)
            Text("HealthMap fournit des informations a titre indicatif. Ces recommandations ne remplacent pas un avis medical. Consultez un professionnel de sante.")
                .font(.system(size: 11)).foregroundStyle(Color.healthMapMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacingSM)
    }
}

#Preview {
    RecommendationsView()
        .environmentObject(DashboardViewModel())
}
