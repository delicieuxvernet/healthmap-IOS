import SwiftUI

// MARK: - Supplements View (Mes compléments — DESIGN-PAGES §5, premium « Foodvisor »)
//
// Refonte du 14 juin (maquette validée par Arthur) : timeline Matin/Midi/Soir +
// FICHES DÉPLIABLES. Chaque fiche compacte (anneau de dose, priorité, bénéfice,
// dose + moment) se déplie au clic sur le détail : pourquoi TOI (causal), niveau
// actuel → cible, comment le prendre, durée de cure, sources alimentaires,
// produit conseillé + prix, précaution.
//
// Données : `SupplementEngine` (score, whyText causal, produit, prix, contre-
// indications) + `SupplementGuide` (bénéfice, prise, cure, sources — curé, jamais
// l'IA). Avertissement ambre toujours visible + interaction premium floutée.
struct SupplementsView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Set<String> = []

    // Moteur (à partir des scores + profil)
    private var engineResult: SupplementEngineResult? {
        let scores = dashboardVM.nutrientScores
        guard !scores.isEmpty else { return nil }
        return SupplementEngine.generateRecommendations(scores: scores, profile: dashboardVM.profile)
    }

    // Repli : planning IA de l'analyse
    private var aiSchedule: SupplementsSchedule? {
        dashboardVM.aiAnalysis?.supplementsSchedule
    }

    private var hasEngineResults: Bool {
        guard let result = engineResult else { return false }
        return !result.topRecommendations.isEmpty
    }

    private var hasAISchedule: Bool {
        guard let schedule = aiSchedule else { return false }
        return !(schedule.morning ?? []).isEmpty
            || !(schedule.afternoon ?? []).isEmpty
            || !(schedule.evening ?? []).isEmpty
    }

    private var hasContent: Bool { hasEngineResults || hasAISchedule }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()
                    .ignoresSafeArea()

                if hasContent {
                    mainContent
                } else if dashboardVM.isLoadingAnalysis {
                    VStack(spacing: Theme.spacingMD) {
                        ProgressView()
                            .tint(Color.healthMapBlue)
                        Text("Chargement...")
                            .font(Theme.bodyFont)
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                } else {
                    emptyState
                }
            }
            .navigationTitle("Mes compléments")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Contenu principal
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: Theme.spacingLG) {
                Text("Issus de ton bilan · à confirmer par une prise de sang")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.spacingLG)

                if let result = engineResult, !result.topRecommendations.isEmpty {
                    timeline(result.topRecommendations)
                    costSummaryCard(result.cost)
                    if !result.warnings.isEmpty {
                        interactionWarningsCard(result.warnings)
                    }
                    premiumInteractionCard(result.topRecommendations)
                } else {
                    aiFallbackSection
                }

                infoCard
            }
            .padding(.vertical, Theme.spacingMD)
        }
    }

    // MARK: - Timeline (moteur) : Matin / Midi / Soir → fiches dépliables
    @ViewBuilder
    private func timeline(_ recs: [SupplementRecommendation]) -> some View {
        ForEach(["Matin", "Midi", "Soir"], id: \.self) { group in
            let groupRecs = recs.filter { ($0.bestProduct?.timing.displayGroup ?? "Matin") == group }
            if !groupRecs.isEmpty {
                sectionHeader(group: group)
                ForEach(groupRecs) { rec in
                    SupplementDetailCard(
                        rec: rec,
                        target: 70,
                        isExpanded: expanded.contains(rec.id),
                        onToggle: { toggle(rec.id) }
                    )
                    .padding(.horizontal, Theme.spacingLG)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        HapticService.shared.selection()
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    private func sectionHeader(group: String) -> some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: groupIcon(group))
                .font(.system(size: 13))
                .foregroundStyle(groupColor(group))
                .accessibilityHidden(true)
            Text(group)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.healthMapSecondary)
            Spacer()
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.top, Theme.spacingXS)
    }

    private func groupIcon(_ g: String) -> String {
        switch g {
        case "Matin": return "sunrise.fill"
        case "Midi": return "sun.max.fill"
        default: return "moon.fill"
        }
    }

    private func groupColor(_ g: String) -> Color {
        switch g {
        case "Matin": return .accentSky
        case "Midi": return .healthMapBlue
        default: return .accentIndigo
        }
    }

    // MARK: - Coût mensuel
    private func costSummaryCard(_ cost: CostSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "eurosign.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.healthMapBlue)
                Text("Coût mensuel estimé")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapText)
                Spacer()
            }
            HStack(spacing: Theme.spacingMD) {
                VStack(spacing: 4) {
                    Text("Économique")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                    Text(String(format: "%.0f €", cost.valueTotal))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.healthMapText)
                    Text("/ mois")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapMuted)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.healthMapMuted.opacity(0.2))
                    .frame(width: 1, height: 50)

                VStack(spacing: 4) {
                    Text("Premium")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                    Text(String(format: "%.0f €", cost.premiumTotal))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.healthMapBlue)
                    Text("/ mois")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Avertissement ambre (toujours visible, sécurité)
    private func interactionWarningsCard(_ warnings: [InteractionWarning]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.scoreLow)
                Text("À savoir")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.scoreLow)
            }
            ForEach(warnings) { warning in
                HStack(alignment: .top, spacing: Theme.spacingSM) {
                    Text(warning.emoji)
                        .font(.system(size: 14))
                    Text(warning.message)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.scoreLow.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Color.scoreLow.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Interaction premium floutée (contenu RÉEL borné — loi 11)
    @ViewBuilder
    private func premiumInteractionCard(_ recs: [SupplementRecommendation]) -> some View {
        let lines = recs.compactMap { rec -> String? in
            guard let product = rec.bestProduct, !product.antiInteractions.isEmpty else { return nil }
            return "\(rec.nutrientLabel) : à distance de \(product.antiInteractions.prefix(2).joined(separator: ", "))."
        }
        if !lines.isEmpty {
            BlurredSection(isPremium: true, title: "Interactions personnalisées") {
                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: Theme.spacingXS) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentIndigo)
                                .accessibilityHidden(true)
                            Text(line)
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.healthMapText)
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
    }

    // MARK: - Repli planning IA (rare : moteur vide mais analyse présente)
    @ViewBuilder
    private var aiFallbackSection: some View {
        if let schedule = aiSchedule {
            let blocks: [(String, [SupplementEntry])] = [
                ("Matin", schedule.morning ?? []),
                ("Midi", schedule.afternoon ?? []),
                ("Soir", schedule.evening ?? []),
            ]
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                let label = block.0
                let entries = block.1
                if !entries.isEmpty {
                    sectionHeader(group: label)
                    VStack(alignment: .leading, spacing: Theme.spacingSM) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            HStack(spacing: Theme.spacingSM) {
                                Image(systemName: "pills.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.healthMapBlue)
                                Text(entry.displayText)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.healthMapText)
                                Spacer()
                            }
                        }
                    }
                    .padding(Theme.spacingMD)
                    .cardStyle()
                    .padding(.horizontal, Theme.spacingLG)
                }
            }
        }
    }

    // MARK: - Disclaimer
    private var infoCard: some View {
        HStack(alignment: .center, spacing: Theme.spacingSM) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapMuted)
            Text("Suggestions basées sur ton bilan · ne remplacent pas un avis médical.")
                .font(.system(size: 11))
                .foregroundStyle(Color.healthMapMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacingSM)
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - État vide
    private var emptyState: some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "pills")
                .font(.system(size: 48))
                .foregroundStyle(Color.healthMapMuted)
            Text("Aucun complément recommandé")
                .font(Theme.headlineFont)
                .foregroundStyle(Color.healthMapText)
            Text("Ton analyse n'a pas identifié de complément nécessaire, ou l'analyse IA n'a pas encore été effectuée.")
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)
        }
    }
}

// MARK: - Supplement Detail Card (fiche dépliable)
private struct SupplementDetailCard: View {
    let rec: SupplementRecommendation
    let target: Int
    let isExpanded: Bool
    let onToggle: () -> Void

    private var guide: SupplementGuideInfo? { SupplementGuide.info(for: rec.nutrientID.rawValue) }
    private var essential: Bool { rec.score < 45 }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: Theme.spacingSM) {
                    NutrientDoseRing(emoji: rec.nutrientEmoji, score: rec.score, color: rec.nutrientColor)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: Theme.spacingSM) {
                            Text(rec.nutrientLabel)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.healthMapText)
                                .lineLimit(1)
                            Text(essential ? "Essentiel" : "Utile")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(essential ? Color.healthMapBlue : Color.healthMapSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background((essential ? Color.healthMapBlue : Color.healthMapMuted).opacity(0.12))
                                .clipShape(Capsule())
                        }
                        if let benefit = guide?.benefit {
                            Text(benefit)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.scoreExcellent)
                                .lineLimit(1)
                        }
                        if let product = rec.bestProduct {
                            Text("\(product.dosage) · \(product.timing.label)")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.healthMapSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("\(rec.nutrientLabel), \(essential ? "essentiel" : "utile")")
            .accessibilityHint(isExpanded ? "Touche pour replier le détail" : "Touche pour voir le détail")

            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    Divider().padding(.vertical, 2)
                    detailRow(icon: "lightbulb", tint: .accentIndigo, label: "Pourquoi toi", text: rec.whyText)
                    detailRow(icon: "target", tint: .healthMapBlue, label: "Niveau actuel", text: "\(rec.score) → cible \(target)")
                    if let guide {
                        detailRow(icon: "pills", tint: .healthMapBlue, label: "Comment le prendre", text: guide.howToTake)
                        detailRow(icon: "calendar", tint: .healthMapBlue, label: "Durée de cure", text: guide.cureDuration)
                        detailRow(icon: "leaf", tint: .scoreExcellent, label: "Aussi dans l'assiette", text: guide.foodSources)
                    }
                    if let product = rec.bestProduct {
                        detailRow(icon: "bag", tint: .healthMapBlue, label: "Exemple", text: "\(product.brand) — \(String(format: "%.2f", product.dailyCost)) €/jour")
                        let precautions = product.contraindications + product.antiInteractions
                        if !precautions.isEmpty {
                            detailRow(icon: "exclamationmark.triangle", tint: .scoreLow, label: "Précaution", text: precautions.prefix(3).joined(separator: " · "))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(Theme.spacingMD)
        .cardStyle()
    }

    private func detailRow(icon: String, tint: Color, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Nutrient Dose Ring (petit anneau coloré par nutriment, emoji au centre)
private struct NutrientDoseRing: View {
    let emoji: String
    let score: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, score))) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(emoji)
                .font(.system(size: 16))
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    SupplementsView()
        .environmentObject(DashboardViewModel())
}
