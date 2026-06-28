import SwiftUI
import Foundation

// MARK: - Suivi View (onglet 2 — refonte « v4 » 3D)
//
// Refonte de l'habillage dans le langage v4 (crème, .kiwiCard, accent vert kiwi,
// illustrations 3D Fluent3D), fidèle à la maquette « Suivi v3 - 3D ». La logique
// (SuiviStore, check-in, série hebdo, projection calculée, gamification) est
// CONSERVÉE telle quelle — seul l'habillage change.
//
// Deux états :
//   • État A — DÉCOUVERTE (suivi non activé) : aperçu « exemple » (courbe,
//     ce que le suivi change, série/récolte) + CTA « Commencer mon suivi ».
//   • État B — ACTIF : carte score héros (anneau plein + tendance + barres
//     hebdo réelles), « Ce que ton suivi a changé » (illustrations 3D adossées
//     au check-in du jour + apport réel le plus proche), check-in du jour
//     segmenté, projection de score (calculée, jamais inventée).
//
// Tout en local (UserDefaults scopé par utilisateur, cf. SuiviStore) : données
// honnêtes, aucune dépendance réseau. Reduce-motion respecté (loi 17).
struct SuiviView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @ObservedObject private var gamification = GamificationService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var started = false
    @State private var showObjectives = false
    @State private var checkin: [String: Int] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()

                ScrollView {
                    VStack(spacing: 22) {
                        header

                        if started {
                            activeState
                        } else {
                            discoveryState
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Mon suivi")
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
            .onAppear {
                started = SuiviStore.isStarted
                checkin = SuiviStore.todayCheckin()
                if started { SuiviStore.recordWeeklyScore(dashboardVM.healthScore) }
            }
            .sheet(isPresented: $showObjectives) {
                SuiviObjectivesSheet {
                    SuiviStore.markStarted(baseline: dashboardVM.healthScore)
                    SuiviStore.recordWeeklyScore(dashboardVM.healthScore)
                    withAnimation(reduceMotion ? .none : .healthMapSpring) { started = true }
                    HapticService.shared.success()
                }
                .healthMapFullSheet()
            }
        }
    }

    // MARK: - En-tête (sous-titre sous le grand titre natif)
    private var header: some View {
        Text("Tes progrès, semaine après semaine")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.healthMapSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - État A : découverte
    @ViewBuilder private var discoveryState: some View {
        previewPill
        SuiviScoreHeroCard(
            score: max(dashboardVM.healthScore, 1),
            delta: 8,
            bars: exampleBars,
            isExample: true,
            reduceMotion: reduceMotion
        )
        SuiviChangedCard(rows: exampleChangedRows)
        RecolteCard(streak: gamification.currentStreak)
        startCTA
        projectionCard
    }

    // MARK: - État B : actif
    @ViewBuilder private var activeState: some View {
        let bars = realBars
        SuiviScoreHeroCard(
            score: dashboardVM.healthScore,
            delta: liveDelta,
            bars: bars.count >= 2 ? bars : [],
            isExample: false,
            reduceMotion: reduceMotion
        )

        if !changedRows.isEmpty {
            sectionTitle("Ce que ton suivi a changé")
            SuiviChangedCard(rows: changedRows)
        }

        sectionTitle("Check-in du jour", trailing: "30s")
        DailyCheckinCard(values: $checkin, reduceMotion: reduceMotion) {
            SuiviStore.saveCheckin(checkin)
        }

        RecolteCard(streak: gamification.currentStreak)
            .padding(.horizontal, 4)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .kiwiCard()

        projectionCard
    }

    // MARK: - Titre de section
    private func sectionTitle(_ text: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
    }

    // MARK: - Pill « Aperçu · exemple » (état A)
    private var previewPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text("Aperçu · exemple")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color.kiwiGreenInk)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(Capsule().fill(Color.kiwiGreenSoft))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - CTA « Commencer » (état A)
    private var startCTA: some View {
        Button {
            HapticService.shared.primary()
            showObjectives = true
        } label: {
            VStack(spacing: 2) {
                Text("Commencer mon suivi personnalisé")
                    .font(.system(size: 15, weight: .bold))
                Text("3 questions · 1 minute")
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.kiwiGreen)
            )
            .shadow(color: Color.kiwiGreen.opacity(0.32), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.healthMapPressed)
    }

    // MARK: - Projection (calculée, jamais inventée) — carte teintée vert
    private var projectionCard: some View {
        BlurredSection(isPremium: true, title: "Ta projection de score personnalisée") {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.kiwiGreen)
                        .frame(width: 44, height: 44)
                    Image(systemName: "target")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Continue ton suivi")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.kiwiGreenInk)
                    Text("Dans 6 semaines\u{202F}: \(projectedScore)/100 estimé si tu tiens ton plan.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.kiwiGreenInk.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.kiwiGreenSoft)
            )
        }
    }

    // MARK: - Données calculées
    /// Delta réel depuis le début du suivi (score actuel - baseline figé).
    private var liveDelta: Int {
        SuiviStore.baseline > 0 ? dashboardVM.healthScore - SuiviStore.baseline : 0
    }

    /// Estimation transparente : score actuel + 5 pts par besoin prioritaire
    /// traité (plafonné à +15, et à 100). Dérivée du vrai score, jamais inventée.
    private var projectedScore: Int {
        let gain = min(15, dashboardVM.deficiencies.prefix(3).count * 5)
        return min(100, dashboardVM.healthScore + gain)
    }

    private var exampleBars: [BarPoint] {
        let scores = [48, 44, 52, 58, 64, 70]
        return scores.enumerated().map { i, s in
            BarPoint(label: dayLabels[min(i, dayLabels.count - 1)], score: s)
        }
    }

    private var realBars: [BarPoint] {
        let series = SuiviStore.weeklySeries()
        return series.enumerated().map { i, e in
            BarPoint(label: dayLabels[min(i, dayLabels.count - 1)], score: e.score)
        }
    }

    private let dayLabels = ["L", "M", "M", "J", "V", "S", "D"]

    // MARK: - Lignes « Ce que ton suivi a changé »
    /// État A : exemple illustratif. État B : adossé au check-in du jour réel +
    /// à l'apport réel le plus proche (jamais de faux pourcentages inventés).
    private var exampleChangedRows: [ChangedRow] {
        [
            ChangedRow(asset: Fluent3D.voltage, title: "Énergie", value: "ressentie en hausse", positive: true),
            ChangedRow(asset: Fluent3D.sleeping, title: "Sommeil", value: "plus stable", positive: true),
            ChangedRow(asset: Fluent3D.droplet, title: "Apport à renforcer", value: "se comble", positive: true)
        ]
    }

    private var changedRows: [ChangedRow] {
        var rows: [ChangedRow] = []

        if let energie = checkin["energie"] {
            rows.append(ChangedRow(
                asset: Fluent3D.voltage,
                title: "Énergie",
                value: levelPhrase(energie),
                positive: energie >= 2
            ))
        }
        if let sommeil = checkin["sommeil"] {
            rows.append(ChangedRow(
                asset: Fluent3D.sleeping,
                title: "Sommeil",
                value: levelPhrase(sommeil),
                positive: sommeil >= 2
            ))
        }
        if let n = dashboardVM.deficiencies.first {
            rows.append(ChangedRow(
                asset: Fluent3D.droplet,
                title: n.label,
                value: "\(n.score)% du besoin",
                positive: n.score >= 70
            ))
        }
        return rows
    }

    private func levelPhrase(_ level: Int) -> String {
        switch level {
        case 1: return "à surveiller"
        case 2: return "correcte"
        default: return "au top"
        }
    }
}

// MARK: - Bar Point (un point de la courbe hebdo)
private struct BarPoint: Identifiable {
    let id = UUID()
    let label: String
    let score: Int
}

// MARK: - Changed Row (une ligne « Ce que ton suivi a changé »)
private struct ChangedRow: Identifiable {
    let id = UUID()
    let asset: String
    let title: String
    let value: String
    let positive: Bool
}

// MARK: - Carte score héros (anneau plein + tendance + barres hebdo)
/// Fidèle à la maquette : anneau plein vert kiwi (% du score), pastille tendance
/// « +N cette sem. », mini-histogramme des semaines réelles. Couleur de palier
/// portée par l'anneau (HealthScale). Les barres = série hebdo réelle (ou exemple).
private struct SuiviScoreHeroCard: View {
    let score: Int
    let delta: Int
    let bars: [BarPoint]
    let isExample: Bool
    let reduceMotion: Bool

    @State private var animated: CGFloat = 0
    @State private var barsIn = false

    private var color: Color { Color.globalScoreColor(for: score) }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                ring
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ton score bien-être")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.healthMapSecondary)

                    if delta > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .bold))
                            Text("+\(delta)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                            Text("cette sem.")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(Color.kiwiGreenInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.kiwiGreenSoft))
                    }

                    Text(isExample
                         ? "Il grimpe à mesure que tu suis tes apports."
                         : (delta > 0
                            ? "Il grimpe depuis que tu suis tes apports."
                            : "Continue ton suivi pour le voir progresser."))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !bars.isEmpty {
                barChart
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .kiwiCard()
        .onAppear {
            if reduceMotion {
                animated = CGFloat(score) / 100
                barsIn = true
            } else {
                withAnimation(.easeOut(duration: 1.2).delay(0.2)) { animated = CGFloat(score) / 100 }
                withAnimation(.easeOut(duration: 0.7).delay(0.35)) { barsIn = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ton score bien-être : \(score) sur 100." + (delta > 0 ? " En hausse de \(delta) cette semaine." : ""))
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: 9)
                .frame(width: 104, height: 104)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .frame(width: 104, height: 104)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                AnimatedNumberView(
                    targetValue: score,
                    font: .system(size: 34, weight: .bold, design: .monospaced),
                    color: color
                )
                Text("/ 100")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .frame(width: 104, height: 104)
    }

    private var barChart: some View {
        let maxScore = max(bars.map(\.score).max() ?? 100, 1)
        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(bars.enumerated()), id: \.element.id) { idx, bar in
                    let frac = CGFloat(bar.score) / CGFloat(maxScore)
                    let isLast = idx == bars.count - 1
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isLast ? Color.kiwiGreen : Color.kiwiGreen.opacity(0.28 + 0.5 * frac))
                        .frame(maxWidth: .infinity)
                        .frame(height: barsIn ? max(8, 54 * frac) : 0)
                }
            }
            .frame(height: 54)

            HStack(spacing: 8) {
                ForEach(Array(bars.enumerated()), id: \.element.id) { idx, bar in
                    Text(bar.label)
                        .font(.system(size: 9, weight: idx == bars.count - 1 ? .bold : .semibold, design: .monospaced))
                        .foregroundStyle(idx == bars.count - 1 ? Color.kiwiGreenInk : Color.healthMapMuted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Carte « Ce que ton suivi a changé » (illustrations 3D)
private struct SuiviChangedCard: View {
    let rows: [ChangedRow]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floaty = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                if idx > 0 {
                    Divider().background(Color.kiwiCharcoal.opacity(0.06))
                }
                HStack(spacing: 13) {
                    Fluent3DIcon(name: row.asset, size: 34)
                        .offset(y: floaty ? -3 : 0)
                    Text(row.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        if row.positive {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text(row.value)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(row.positive ? Color.kiwiGreenInk : Color.healthMapSecondary)
                }
                .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 20)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { floaty = true }
        }
    }
}

// MARK: - Daily Checkin Card (Énergie / Sommeil / Stress — segmenté v4)
private struct DailyCheckinCard: View {
    @Binding var values: [String: Int]
    let reduceMotion: Bool
    let onChange: () -> Void

    private let metrics: [(key: String, label: String, icon: String)] = [
        ("energie", "Énergie", "bolt.fill"),
        ("sommeil", "Sommeil", "moon.fill"),
        ("stress", "Stress", "wind")
    ]
    private let levels = ["Bas", "Moyen", "Haut"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(metrics, id: \.key) { m in
                HStack(spacing: 12) {
                    Image(systemName: m.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.healthMapMuted)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(m.label)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Spacer(minLength: 8)
                    segmented(for: m.key, label: m.label)
                }
            }

            if values.count >= metrics.count {
                Label("C'est noté pour aujourd'hui", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiGreenInk)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard(radius: 20)
        .animation(reduceMotion ? .none : .healthMapQuick, value: values.count)
    }

    private func segmented(for key: String, label: String) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { idx, lvl in
                let level = idx + 1
                let selected = values[key] == level
                Button {
                    HapticService.shared.selection()
                    values[key] = level
                    onChange()
                } label: {
                    Text(lvl)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(selected ? .white : Color.healthMapMuted)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.kiwiGreen)
                                    .shadow(color: Color.kiwiGreen.opacity(0.3), radius: 5, x: 0, y: 2)
                            }
                        }
                }
                .buttonStyle(.healthMapPressed)
                .accessibilityLabel("\(label), \(lvl)\(selected ? ", sélectionné" : "")")
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.kiwiCharcoal.opacity(0.04))
        )
    }
}

// MARK: - Suivi Objectives Sheet (mini-questionnaire « 3 questions · 1 minute »)
private struct SuiviObjectivesSheet: View {
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var objectif: String?
    @State private var rappel: String?
    @State private var moment: String?

    private let objectifs = ["Plus d'énergie", "Mieux dormir", "Moins de stress", "Renforcer mes apports"]
    private let rappels = ["Chaque jour", "En semaine", "Pas de rappel"]
    private let moments = ["Matin", "Midi", "Soir"]

    private var ready: Bool { objectif != nil && rappel != nil && moment != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    questionBlock(title: "Ton objectif principal\u{202F}?", options: objectifs, selection: $objectif)
                    questionBlock(title: "Tu veux un rappel\u{202F}?", options: rappels, selection: $rappel)
                    questionBlock(title: "Le meilleur moment pour toi\u{202F}?", options: moments, selection: $moment)
                }
                .padding(24)
            }
            .background(Color.kiwiCream)
            .navigationTitle("Mon suivi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    SuiviStore.saveObjectives(objectif: objectif, rappel: rappel, moment: moment)
                    onComplete()
                    dismiss()
                } label: {
                    Text("Activer mon suivi")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(ready ? Color.kiwiGreen : Color.healthMapMuted)
                        )
                }
                .buttonStyle(.healthMapPressed)
                .disabled(!ready)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.kiwiCream)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    private func questionBlock(title: String, options: [String], selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
            ForEach(options, id: \.self) { opt in
                optionRow(opt, selected: selection.wrappedValue == opt) {
                    HapticService.shared.selection()
                    selection.wrappedValue = opt
                }
            }
        }
    }

    private func optionRow(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 14, weight: selected ? .bold : .medium))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .multilineTextAlignment(.leading)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.kiwiGreen)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.kiwiGreenSoft : Color.healthMapCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected ? Color.kiwiGreen.opacity(0.35) : Color.kiwiCharcoal.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(label)\(selected ? ", sélectionné" : "")")
    }
}

// MARK: - Suivi Store (persistance locale scopée par utilisateur)
// Même esprit que PlanCheckStore : clé scopée par uid, tout en UserDefaults.
@MainActor
private enum SuiviStore {
    private static var uid: String {
        AuthService.shared.cachedCurrentUserIdString ?? "anonymous"
    }
    private static var startedKey: String { "healthmap_suivi_started_\(uid)" }
    private static var baselineKey: String { "healthmap_suivi_baseline_\(uid)" }
    private static var seriesKey: String { "healthmap_suivi_series_\(uid)" }
    private static func checkinKey(_ day: String) -> String { "healthmap_suivi_checkin_\(uid)_\(day)" }

    static var isStarted: Bool {
        UserDefaults.standard.bool(forKey: startedKey)
    }

    static var baseline: Int {
        UserDefaults.standard.integer(forKey: baselineKey)
    }

    static func markStarted(baseline: Int) {
        UserDefaults.standard.set(true, forKey: startedKey)
        // Le baseline n'est figé qu'une fois (au premier démarrage du suivi).
        if UserDefaults.standard.object(forKey: baselineKey) == nil {
            UserDefaults.standard.set(baseline, forKey: baselineKey)
        }
    }

    static func saveObjectives(objectif: String?, rappel: String?, moment: String?) {
        UserDefaults.standard.set(objectif, forKey: "healthmap_suivi_obj_\(uid)")
        UserDefaults.standard.set(rappel, forKey: "healthmap_suivi_rappel_\(uid)")
        UserDefaults.standard.set(moment, forKey: "healthmap_suivi_moment_\(uid)")
    }

    // Série hebdomadaire du score (un point par semaine ISO, dernier gagne).
    static func recordWeeklyScore(_ score: Int) {
        guard score > 0 else { return }
        var dict = (UserDefaults.standard.dictionary(forKey: seriesKey) as? [String: Int]) ?? [:]
        dict[currentWeekKey()] = score
        UserDefaults.standard.set(dict, forKey: seriesKey)
    }

    static func weeklySeries() -> [(week: String, score: Int)] {
        let dict = (UserDefaults.standard.dictionary(forKey: seriesKey) as? [String: Int]) ?? [:]
        return dict.sorted { $0.key < $1.key }.suffix(7).map { (week: $0.key, score: $0.value) }
    }

    // Check-in du jour (Énergie/Sommeil/Stress → 1..3).
    static func todayCheckin() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: checkinKey(todayKey())) as? [String: Int]) ?? [:]
    }

    static func saveCheckin(_ values: [String: Int]) {
        UserDefaults.standard.set(values, forKey: checkinKey(todayKey()))
    }

    private static func currentWeekKey() -> String {
        let cal = Calendar.current
        let week = cal.component(.weekOfYear, from: Date())
        let year = cal.component(.yearForWeekOfYear, from: Date())
        return String(format: "%04d-W%02d", year, week)
    }

    private static func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

#Preview {
    SuiviView()
        .environmentObject(DashboardViewModel())
}
