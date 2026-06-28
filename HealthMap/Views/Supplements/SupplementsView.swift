import SwiftUI

// MARK: - Supplements View (Mes compléments — langage « v4 » 3D)
//
// Refonte v4 (maquette « Compléments v4 - 3D ») : fond crème, cartes de
// compléments blanches arrondies (`kiwiCard`), pastilles teintées avec pilule
// SF Symbol (pas d'illustration 3D Fluent ici — choix de la maquette), carte
// « cure Kiwio » (coût éco/premium), carte « À savoir » (interactions), gating
// premium conservé, pop-up bottom-sheet « Pourquoi ce complément ».
//
// Logique INCHANGÉE : `SupplementEngine` (score, whyText causal, produits, prix,
// interactions) + repli planning IA. Aucun nouvel appel service — uniquement
// l'habillage v4.
struct SupplementsView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedRec: SupplementRecommendation?

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
                WarmBackground()

                if hasContent {
                    mainContent
                } else if dashboardVM.isLoadingAnalysis {
                    VStack(spacing: 16) {
                        KiwiWalkerView(size: 140)
                        Text("Chargement...")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                } else {
                    emptyState
                }
            }
            .navigationTitle("Mes compléments")
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
            .sheet(item: $selectedRec) { rec in
                SupplementDetailSheet(rec: rec)
            }
        }
    }

    // MARK: - Contenu principal
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Ta routine du jour, calée sur ton bilan")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let result = engineResult, !result.topRecommendations.isEmpty {
                    // Recommandés pour toi → cartes v4 cliquables
                    sectionHeader("Recommandés pour toi")
                    ForEach(result.topRecommendations) { rec in
                        SupplementV4Card(rec: rec) { open(rec) }
                    }

                    // À savoir (interactions — sécurité, toujours visible)
                    if !result.warnings.isEmpty {
                        SupplementWarningsV4Card(warnings: result.warnings)
                    }

                    // Interactions personnalisées (premium floutée — contenu réel)
                    premiumInteractionCard(result.topRecommendations)

                    // Ta cure Kiwio (coût éco / premium)
                    SupplementCureV4Card(cost: result.cost)
                } else {
                    aiFallbackSection
                }

                infoCard
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func open(_ rec: SupplementRecommendation) {
        HapticService.shared.selection()
        selectedRec = rec
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.kiwiGreen)
                                .accessibilityHidden(true)
                            Text(line)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.healthMapSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kiwiCard(radius: 20)
            }
        }
    }

    // MARK: - Repli planning IA (rare : moteur vide mais analyse présente)
    @ViewBuilder
    private var aiFallbackSection: some View {
        if let schedule = aiSchedule {
            let blocks: [(String, String, [SupplementEntry])] = [
                ("Matin", "sunrise.fill", schedule.morning ?? []),
                ("Midi", "sun.max.fill", schedule.afternoon ?? []),
                ("Soir", "moon.fill", schedule.evening ?? []),
            ]
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                let label = block.0
                let icon = block.1
                let entries = block.2
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: icon)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.kiwiGreen)
                                .accessibilityHidden(true)
                            Text(label)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.kiwiCharcoal)
                            Spacer()
                        }
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.kiwiGreenSoft)
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "pills.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color.kiwiGreen)
                                }
                                .accessibilityHidden(true)
                                Text(entry.displayText)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.kiwiCharcoal)
                                Spacer()
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .kiwiCard(radius: 20)
                }
            }
        }
    }

    // MARK: - Disclaimer
    private var infoCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapMuted)
            Text("Suggestions basées sur ton bilan · ne remplacent pas un avis médical.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.healthMapMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - État vide
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.kiwiGreenSoft)
                    .frame(width: 88, height: 88)
                Image(systemName: "pills.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.kiwiGreen)
            }
            .accessibilityHidden(true)
            Text("Aucun complément recommandé")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
            Text("Ton bilan n'a pas identifié de complément à ajouter, ou l'analyse n'a pas encore été effectuée.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    SupplementsView()
        .environmentObject(DashboardViewModel())
}
