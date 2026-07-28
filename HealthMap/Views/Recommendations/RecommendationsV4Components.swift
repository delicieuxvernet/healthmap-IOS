import SwiftUI

// MARK: - Plan « v4 » (refonte 3D — direction validée juin 2026, maquette FINALE)
//
// Sous-vues de l'onglet « Ton plan » dans le langage v4 : fond crème, cartes
// blanches arrondies (.kiwiCard). Plus de héros gamifié (XP/niveau retirés) :
// une carte par symptôme/objectif (la cause, le rituel du jour matin/midi/soir,
// un bouton « Voir mes solutions » + badge), et une pop-up bottom-sheet qui
// détaille les solutions par la nutrition / les habitudes / les compléments.
// Source maquette : « impl_Plan.html » (vérité pixel).
//
// La LOGIQUE reste branchée au ViewModel : les données viennent de
// dashboardVM.aiAnalysis (symptômes, objectifs, priorityActions, nutriments,
// solutions) + des sources d'aliments du catalogue (Fluent3D.foodSources).

// MARK: - Modèle de présentation d'un bloc « Ton plan »

/// Une carte du plan : un symptôme déclaré OU un objectif. Tout le contenu de
/// la carte et de sa pop-up est dérivé de l'analyse IA (jamais inventé) ; le
/// rituel matin/midi/soir et les sources d'aliments retombent sur un exemple
/// borné du catalogue quand l'IA ne fournit rien (signalé dans gaps).
struct PlanTopic: Identifiable {
    enum Kind { case symptome, objectif }

    let id: String
    let kind: Kind
    let name: String          // « Ongles cassants » / « Plus d'énergie »
    let intro: String         // cause / explication (texte IA borné)
    let ritual: [PlanRitualStep]
    let nutrition: [PlanNutritionSolution]
    let habitudes: [PlanHabitSolution]
    let complements: [PlanSupplementSolution]

    var kicker: String { kind == .symptome ? "SYMPTÔME" : "OBJECTIF" }
    /// Accent éditorial : bleu pour un symptôme, vert kiwi pour un objectif
    /// (exactement la maquette : #2F6FE0 / #3B6D11).
    var accent: Color { kind == .symptome ? Color(hex: "2F6FE0") : Color.kiwiGreenInk }
    var tint: Color { kind == .symptome ? Color(hex: "EAF0FB") : Color.kiwiGreenSoft }
    var iconSymbol: String { kind == .symptome ? "hand.point.up.left.fill" : "bolt.fill" }
    /// Nombre affiché dans le badge du bouton (= total des solutions).
    var solutionsCount: Int { nutrition.count + habitudes.count + complements.count }
}

struct PlanRitualStep: Identifiable {
    enum Slot { case matin, journee, soir }
    let id = UUID()
    let slot: Slot
    let title: String         // « Matin » / « Midi » / « Soir »
    let detail: String        // « Zinc + fer à jeun »
}

struct PlanNutritionSolution: Identifiable {
    let id = UUID()
    let asset: String         // imageset fluent_*
    let label: String         // « Lentilles »
    let note: String          // sous-titre court
    let qty: String           // Combien
    let moment: String        // Quand
    let cuisson: String       // Préparation
    let astuce: String        // Astuce
}

struct PlanHabitSolution: Identifiable {
    let id = UUID()
    let symbol: String        // SF Symbol
    let text: String
    let note: String
}

struct PlanSupplementSolution: Identifiable {
    let id = UUID()
    let name: String
    let note: String
    let tag: String           // « Prioritaire » / « Si besoin »
    let strong: Bool          // priorité haute -> teinte verte, sinon neutre
}

// MARK: - Carte d'un topic (symptôme / objectif) — maquette FINALE

struct PlanTopicCardV4: View {
    let topic: PlanTopic
    let onSeeSolutions: () -> Void

    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // En-tête : kicker accentué + nom + pastille icône teintée.
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(topic.kicker)
                        .font(.system(size: 11, weight: .heavy))
                        .kerning(0.4)
                        .foregroundStyle(topic.accent)
                    Text(topic.name)
                        .font(.system(size: 23, weight: .heavy))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(topic.tint)
                        .frame(width: 48, height: 48)
                    Image(systemName: topic.iconSymbol)
                        .font(.system(size: 23))
                        .foregroundStyle(topic.accent)
                }
            }

            // Intro / cause (texte IA borné).
            Text(topic.intro)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "3a3833"))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            // « Ton rituel du jour » : matin / midi / soir. Famille 3 (locked) —
            // l'en-tête et la silhouette des 3 créneaux restent visibles (le
            // programme existe), le pas-à-pas est gaté. Net pour les abonnés.
            if !topic.ritual.isEmpty {
                Text("TON RITUEL DU JOUR")
                    .font(.system(size: 11, weight: .heavy))
                    .kerning(0.4)
                    .foregroundStyle(Color(hex: "B0A99B"))
                    .padding(.top, 20)

                if subscriptionService.isPremium {
                    PlanRitualRowV4(steps: topic.ritual)
                        .padding(.top, 14)
                } else {
                    GatedOverlay(intensity: .locked) {
                        PlanRitualRowV4(steps: topic.ritual)
                    }
                    .padding(.top, 14)

                    UnlockDoor(
                        icon: "lock.fill",
                        title: "Débloque ton rituel du jour",
                        subtitle: nil,
                        zone: "plan_rituel",
                        compact: true
                    )
                    .padding(.top, 12)
                }
            }

            // Les détails du plan ne doivent pas rester accessibles par ce
            // raccourci lorsque le rituel est verrouillé.
            Button {
                if subscriptionService.isPremium {
                    onSeeSolutions()
                } else {
                    showPaywall = true
                }
            } label: {
                HStack(spacing: 12) {
                    Text(subscriptionService.isPremium ? "Voir mes solutions" : "Débloquer mes solutions")
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 40, height: 40)
                            Image(systemName: subscriptionService.isPremium ? "arrow.right" : "lock.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.kiwiGreen)
                        }
                        if topic.solutionsCount > 0 {
                            Text("\(topic.solutionsCount)")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(
                                    Capsule().fill(Color(hex: "2F6FE0"))
                                        .overlay(Capsule().stroke(Color.kiwiGreen, lineWidth: 2))
                                )
                                .offset(x: 6, y: -6)
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .padding(.leading, 18)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.kiwiGreen)
                )
                .shadow(color: Color.kiwiGreen.opacity(0.30), radius: 14, x: 0, y: 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .padding(.top, 20)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard()
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "plan_solutions")
                .healthMapFullSheet()
        }
    }
}

// MARK: - Rituel matin / midi / soir (chemin pointillé + 3 paliers)

private struct PlanRitualRowV4: View {
    let steps: [PlanRitualStep]

    var body: some View {
        ZStack {
            // Chemin pointillé arqué reliant les paliers (≥ 2 étapes).
            if steps.count >= 2 {
                GeometryReader { geo in
                    let w = geo.size.width
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.17, y: 22))
                        p.addQuadCurve(
                            to: CGPoint(x: w * 0.83, y: 22),
                            control: CGPoint(x: w * 0.5, y: 4)
                        )
                    }
                    .stroke(
                        Color(hex: "E7E2D6"),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 6])
                    )
                }
                .frame(height: 48)
                .allowsHitTesting(false)
            }

            HStack(alignment: .top, spacing: 0) {
                ForEach(steps) { step in
                    PlanRitualStepV4(step: step)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PlanRitualStepV4: View {
    let step: PlanRitualStep

    private var tileBg: Color {
        switch step.slot {
        case .matin: return Color(hex: "FFF4E2")
        case .journee: return Color(hex: "EBF4E1")
        case .soir: return Color.kiwiCharcoal.opacity(0.05)
        }
    }
    private var tileFg: Color {
        switch step.slot {
        case .matin: return Color.scoreLow
        case .journee: return Color.kiwiGreenInk
        case .soir: return Color(hex: "6B7280")
        }
    }
    private var symbol: String {
        switch step.slot {
        case .matin: return "sunrise.fill"
        case .journee: return "figure.walk"
        case .soir: return "moon.stars.fill"
        }
    }
    private var titleColor: Color {
        step.slot == .soir ? Color(hex: "C0322A") : Color.kiwiCharcoal
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tileBg)
                    .frame(width: 42, height: 42)
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(tileFg)
            }
            .shadow(color: tileFg.opacity(0.18), radius: 6, x: 0, y: 5)

            Text(step.title)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(titleColor)
            Text(step.detail)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color(hex: "6B7280"))
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Pop-up « Voir mes solutions » (bottom sheet)

struct PlanSolutionsSheetV4: View {
    let topic: PlanTopic
    let onSeeSupplements: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<UUID> = []
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    /// Abonné : tout est net, aucune porte.
    private var premium: Bool { subscriptionService.isPremium }

    /// Bloc de lignes rendu net ou flouté (verrouillé) selon l'abonnement.
    /// `rows` doit être `@escaping` : `GatedOverlay` la stocke.
    @ViewBuilder
    private func gatedRows<Content: View>(locked: Bool,
                                          @ViewBuilder rows: @escaping () -> Content) -> some View {
        Group {
            if locked {
                GatedOverlay(intensity: .locked) { VStack(spacing: 0) { rows() } }
            } else {
                VStack(spacing: 0) { rows() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .kiwiCard(radius: 18)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // En-tête : pastille icône + kicker/nom + bouton fermer.
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(topic.tint)
                            .frame(width: 48, height: 48)
                        Image(systemName: topic.iconSymbol)
                            .font(.system(size: 23))
                            .foregroundStyle(topic.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topic.kicker)
                            .font(.system(size: 11, weight: .heavy))
                            .kerning(0.4)
                            .foregroundStyle(topic.accent)
                        Text(topic.name)
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(Color.kiwiCharcoal)
                    }
                    Spacer(minLength: 8)
                    Button {
                        dismiss()
                    } label: {
                        ZStack {
                            Circle().fill(Color(hex: "EFEBE2")).frame(width: 34, height: 34)
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: "6B7280"))
                        }
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel("Fermer")
                }

                Text(topic.intro)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color(hex: "3a3833"))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                // Par la nutrition — TEASER (famille 1/3 du handoff) : le premier
                // aliment reste net et dépliable, le reste est flouté sous une
                // porte. On prouve la matière sans livrer toute l'ordonnance.
                if !topic.nutrition.isEmpty {
                    sectionHeader(symbol: "leaf.fill", tint: Color.kiwiGreenInk,
                                  bg: Color.kiwiGreenSoft, title: "Par la nutrition")
                    let visibles = premium ? topic.nutrition : Array(topic.nutrition.prefix(1))
                    let gatees = premium ? [] : Array(topic.nutrition.dropFirst())
                    VStack(spacing: 0) {
                        ForEach(Array(visibles.enumerated()), id: \.element.id) { idx, n in
                            PlanNutritionRowV4(
                                solution: n,
                                isExpanded: expanded.contains(n.id),
                                showDivider: idx > 0,
                                onToggle: { toggle(n.id) }
                            )
                        }
                        if !gatees.isEmpty {
                            GatedOverlay(intensity: .teaser) {
                                VStack(spacing: 0) {
                                    ForEach(Array(gatees.enumerated()), id: \.element.id) { idx, n in
                                        PlanNutritionRowV4(solution: n, isExpanded: false,
                                                           showDivider: true, onToggle: {})
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .kiwiCard(radius: 18)

                    if !gatees.isEmpty {
                        UnlockDoor(
                            icon: "leaf.fill",
                            title: "Débloque tes \(gatees.count) autres aliments",
                            subtitle: "Combien, quand, comment les préparer",
                            zone: "plan_nutrition"
                        )
                    }
                }

                // Par les habitudes — VERROUILLÉ : la catégorie reste visible
                // (on voit qu'il y a des leviers), le contenu est gaté.
                if !topic.habitudes.isEmpty {
                    sectionHeader(symbol: "arrow.triangle.2.circlepath", tint: Color(hex: "2F6FE0"),
                                  bg: Color(hex: "EAF0FB"), title: "Par les habitudes")
                    gatedRows(locked: !premium) {
                        ForEach(Array(topic.habitudes.enumerated()), id: \.element.id) { idx, ha in
                            PlanHabitRowV4(solution: ha, showDivider: idx > 0)
                        }
                    }
                    if !premium {
                        UnlockDoor(
                            icon: "lock.fill",
                            title: "Débloque tes leviers d'hygiène de vie",
                            subtitle: "Ce qui joue au-delà de l'assiette",
                            zone: "plan_habitudes"
                        )
                    }
                }

                // Par les compléments — VERROUILLÉ (même logique).
                if !topic.complements.isEmpty {
                    sectionHeader(symbol: "pills.fill", tint: topic.accent,
                                  bg: topic.tint, title: "Par les compléments")
                    gatedRows(locked: !premium) {
                        ForEach(Array(topic.complements.enumerated()), id: \.element.id) { idx, c in
                            PlanSupplementRowV4(solution: c, showDivider: idx > 0)
                        }
                    }
                    if !premium {
                        UnlockDoor(
                            icon: "pills.fill",
                            title: "Débloque ton protocole de compléments",
                            subtitle: "Lesquels, à quelle dose, à quel moment",
                            zone: "plan_complements"
                        )
                    }
                }

                // CTA « Voir mes compléments recommandés ».
                Button {
                    onSeeSupplements()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                        Text("Voir mes compléments recommandés")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.kiwiGreen)
                    )
                    .shadow(color: Color.kiwiGreen.opacity(0.34), radius: 14, x: 0, y: 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Color.kiwiCream.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    @ViewBuilder
    private func sectionHeader(symbol: String, tint: Color, bg: Color, title: String) -> some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(bg)
                    .frame(width: 28, height: 28)
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color.kiwiCharcoal)
            Spacer(minLength: 0)
        }
        .padding(.top, 22)
        .padding(.bottom, 11)
    }
}

// MARK: - Ligne « Par la nutrition » (dépliable : Combien / Quand / Préparation / Astuce)

private struct PlanNutritionRowV4: View {
    let solution: PlanNutritionSolution
    let isExpanded: Bool
    let showDivider: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 13) {
                    Fluent3DIcon(name: solution.asset, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(solution.label)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.kiwiCharcoal)
                        Text(solution.note)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color(hex: "6B7280"))
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().fill(Color(hex: "F4F1EA")).frame(width: 26, height: 26)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "6B7280"))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .overlay(alignment: .top) {
                    if showDivider {
                        Rectangle().fill(Color.kiwiCharcoal.opacity(0.06)).frame(height: 1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)

            if isExpanded {
                VStack(spacing: 0) {
                    detailRow(symbol: "scalemass", tint: Color.kiwiGreenInk, label: "Combien", value: solution.qty, divider: false)
                    detailRow(symbol: "clock", tint: Color.kiwiGreenInk, label: "Quand", value: solution.moment, divider: true)
                    detailRow(symbol: "fork.knife", tint: Color.kiwiGreenInk, label: "Préparation", value: solution.cuisson, divider: true)
                    detailRow(symbol: "lightbulb.fill", tint: Color(hex: "C2710A"), label: "Astuce", value: solution.astuce, divider: true)
                }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.kiwiCream)
                )
                .padding(.bottom, 13)
            }
        }
    }

    @ViewBuilder
    private func detailRow(symbol: String, tint: Color, label: String, value: String, divider: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .padding(.top, 1)
            (Text("\(label) · ").font(.system(size: 12.5, weight: .heavy))
                + Text(value).font(.system(size: 12.5, weight: .medium)))
                .foregroundStyle(Color(hex: "3a3833"))
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            if divider {
                Rectangle().fill(Color.kiwiCharcoal.opacity(0.06)).frame(height: 1)
            }
        }
    }
}

// MARK: - Ligne « Par les habitudes »

private struct PlanHabitRowV4: View {
    let solution: PlanHabitSolution
    let showDivider: Bool

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(hex: "F4F1EA"))
                    .frame(width: 34, height: 34)
                Image(systemName: solution.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: "6B7280"))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(solution.text)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text(solution.note)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color(hex: "6B7280"))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .overlay(alignment: .top) {
            if showDivider {
                Rectangle().fill(Color.kiwiCharcoal.opacity(0.06)).frame(height: 1)
            }
        }
    }
}

// MARK: - Ligne « Par les compléments »

private struct PlanSupplementRowV4: View {
    let solution: PlanSupplementSolution
    let showDivider: Bool

    private var color: Color { solution.strong ? Color.kiwiGreenInk : Color(hex: "6B7280") }
    private var tint: Color { solution.strong ? Color.kiwiGreenSoft : Color(hex: "F4F1EA") }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint)
                    .frame(width: 34, height: 34)
                Image(systemName: "pills.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(solution.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text(solution.note)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color(hex: "6B7280"))
            }
            Spacer(minLength: 0)
            Text(solution.tag)
                .font(.system(size: 10.5, weight: .heavy))
                .foregroundStyle(color)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(tint))
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .overlay(alignment: .top) {
            if showDivider {
                Rectangle().fill(Color.kiwiCharcoal.opacity(0.06)).frame(height: 1)
            }
        }
    }
}
