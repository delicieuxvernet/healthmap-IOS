import SwiftUI

// MARK: - Supplements View (Mes compléments — design FINAL « v4 »)
//
// Écran « Mes compléments » FINAL : titre + sous-titre, encart de transparence,
// section « Recommandés pour toi » avec toggle Premium / Éco, une carte par
// complément (source réelle `SupplementEngine.generateRecommendations` +
// catalogue), panier dynamique « D'après tes choix » (somme des prix cochés),
// et deux pop-up (détail « Pourquoi pour toi » + « Précautions »).
//
// Logique INCHANGÉE : `SupplementEngine` (score, whyText causal, produits, prix,
// interactions) + repli planning IA. Panier (coché + total) = @State local.
// Premium / Éco = @State toggle local. Aucun nouvel appel service.
struct SupplementsView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // États locaux du design final
    @State private var premium = true
    /// Choix par complément : panier (complément) ou couverture par l'assiette.
    @State private var choices: [String: SupplementChoice] = [:]
    @State private var whyRec: SupplementRecommendation?
    @State private var interRec: SupplementRecommendation?

    /// Rituel du jour (tête de l'onglet) — dérivé du bilan v2 caché de façon
    /// déterministe, coche persistée localement. Recalculé à l'apparition et à
    /// chaque bascule (le moteur relit UserDefaults). Aucun appel réseau/IA.
    @State private var rituel: SuiviEngineV4.ComplementsRituel?

    /// Compléments du bilan v2 caché (source du rituel du jour). nil si le bilan
    /// n'est pas encore disponible → carte en état vide propre, jamais de crash.
    private var complementsV2: ComplementsV2? {
        dashboardVM.analysisV2?.complements
    }

    /// Signature légère (Equatable) des compléments du bilan, pour ré-armer le
    /// rituel quand le bilan v2 arrive/change sans exiger `AIAnalysisV2: Equatable`.
    private var complementsSignature: String {
        (complementsV2?.complements ?? [])
            .compactMap { $0.id }
            .joined(separator: "|")
    }

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

    // Compléments cochés (dans l'ordre de la liste recommandée)
    private var takenRecs: [SupplementRecommendation] {
        engineResult?.topRecommendations.filter { choices[$0.id] == .complement } ?? []
    }

    private var cartTotal: Double {
        takenRecs.reduce(0) { $0 + SupplementsV4.monthlyPrice($1, premium: premium) }
    }

    private var cartTotalLabel: String { String(format: "%.0f €", cartTotal) }

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
            .kiwiTabBarBottomInset()
            .onAppear { refreshRituel() }
            .onChange(of: complementsSignature) { _, _ in refreshRituel() }
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
            .sheet(item: $whyRec) { rec in
                SupplementWhySheet(rec: rec) { addToCart(rec) }
            }
            .sheet(item: $interRec) { rec in
                let warnings = engineResult?.warnings ?? []
                let items = SupplementsV4.precautions(for: rec, warnings: warnings)
                SupplementPrecautionsSheet(rec: rec, items: items, tip: SupplementsV4.tip(for: items))
            }
        }
    }

    // MARK: - Contenu principal
    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Titre + sous-titre
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mes compléments")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Text("Choisis ce que tu prends — le reste passe par l'assiette")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // « Ton rituel du jour » EN TÊTE (cochable, persistant local).
                if let rituel {
                    ComplementsRituelCard(rituel: rituel) { id in
                        toggleRituel(id)
                    }
                }

                SupplementTransparencyCard()

                if let result = engineResult, !result.topRecommendations.isEmpty {
                    // Section header + toggle Premium / Éco
                    HStack {
                        Text("Recommandés pour toi")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(Color.kiwiCharcoal)
                        Spacer()
                        SupplementQualityToggle(premium: $premium)
                    }

                    VStack(spacing: 12) {
                        ForEach(result.topRecommendations) { rec in
                            SupplementCardV4(
                                rec: rec,
                                premium: premium,
                                interCount: interactionCount(for: rec, warnings: result.warnings),
                                choice: choices[rec.id] ?? .none,
                                onCapsule: { openWhy(rec) },
                                onInteractions: { openInter(rec) },
                                onComplement: { chooseComplement(rec) },
                                onAssiette: { chooseAssiette(rec) },
                                onSeeFoodPlan: { goToPlan() }
                            )
                        }
                    }

                    // Panier dynamique « D'après tes choix »
                    SupplementCartCard(
                        taken: takenRecs,
                        premium: premium,
                        totalLabel: cartTotalLabel,
                        onOrder: { goToPlan() }
                    )
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

    // MARK: - Actions

    /// (Re)construit le rituel du jour à partir du bilan v2 caché (déterministe).
    private func refreshRituel() {
        rituel = SuiviEngineV4.complementsRituel(complements: complementsV2)
    }

    /// Coche/décoche un item du rituel pour aujourd'hui (persisté localement).
    private func toggleRituel(_ id: String) {
        HapticService.shared.selection()
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) {
            rituel = SuiviEngineV4.toggleRituel(id: id, complements: complementsV2)
        }
    }

    private func openWhy(_ rec: SupplementRecommendation) {
        HapticService.shared.selection()
        whyRec = rec
    }

    private func openInter(_ rec: SupplementRecommendation) {
        HapticService.shared.selection()
        interRec = rec
    }

    /// « Je le prends » : (dé)sélectionne le mode complément (panier).
    private func chooseComplement(_ rec: SupplementRecommendation) {
        HapticService.shared.selection()
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) {
            choices[rec.id] = (choices[rec.id] == .complement) ? SupplementChoice.none : .complement
        }
    }

    /// « Par l'assiette » : (dé)sélectionne le mode assiette (affiche le CTA Plan).
    private func chooseAssiette(_ rec: SupplementRecommendation) {
        HapticService.shared.selection()
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) {
            choices[rec.id] = (choices[rec.id] == .assiette) ? SupplementChoice.none : .assiette
        }
    }

    /// Depuis la fiche « Pourquoi pour toi » → ajoute au panier (mode complément).
    private func addToCart(_ rec: SupplementRecommendation) {
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) {
            choices[rec.id] = .complement
        }
    }

    private func goToPlan() {
        HapticService.shared.selection()
        NotificationCenter.default.post(
            name: .healthmapNavigateToTab,
            object: NavCardDestination.plan.rawValue
        )
    }

    /// Nombre d'interactions du profil concernant ce complément (badge rouge).
    private func interactionCount(for rec: SupplementRecommendation, warnings: [InteractionWarning]) -> Int {
        SupplementsV4.precautions(for: rec, warnings: warnings).count
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
            Text("Aucun complément à ajouter")
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
