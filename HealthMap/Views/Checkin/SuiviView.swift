import SwiftUI
import Foundation

// MARK: - Suivi View (onglet 2 — DESIGN-PAGES §4)
//
// Remplace l'ancien CheckinView (grille 2x2 + picker) qui n'était PAS la §4.
// Deux états :
//   • État A — DÉCOUVERTE (suivi non activé) : aperçu « exemple » de ce que le
//     suivi apportera (courbe 6 semaines, nutriment qui progresse, série/badges)
//     + gros CTA « Commencer mon suivi personnalisé » (3 questions, 1 minute)
//     + projection de score premium (CALCULÉE à partir du vrai score, jamais
//     inventée).
//   • État B — ACTIF : check-in du jour (Énergie/Sommeil/Stress, boutons glass),
//     delta vert depuis le début du suivi, courbe réelle qui se construit
//     semaine après semaine (jamais de faux chiffres — état « en construction »
//     tant qu'il n'y a pas 2 points), nutriment réel, série/badges réels.
//
// Tout en local (UserDefaults scopé par utilisateur, cf. SuiviStore) : aucune
// dépendance réseau, données honnêtes. Ruban de fond (loi 2), reduce-motion
// respecté (loi 17).
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
                AnimatedBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.spacingLG) {
                        if started {
                            activeState
                        } else {
                            discoveryState
                        }
                    }
                    .padding(.vertical, Theme.spacingMD)
                }
            }
            .navigationTitle("Mon suivi")
            .navigationBarTitleDisplayMode(.large)
            .healthMapProfileToolbar()
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

    // MARK: - État A : découverte
    @ViewBuilder private var discoveryState: some View {
        previewPill
        WeeklyScoreCard(points: exampleBars, isExample: true)
        exampleNutrientLine
        exampleStatRow
        startCTA
        projectionCard
    }

    // MARK: - État B : actif
    @ViewBuilder private var activeState: some View {
        deltaHeader
        DailyCheckinCard(values: $checkin, reduceMotion: reduceMotion) {
            SuiviStore.saveCheckin(checkin)
        }
        if realBars.count >= 2 {
            WeeklyScoreCard(points: realBars, isExample: false)
        } else {
            buildingCard
        }
        realNutrientLine
        realStatRow
        projectionCard
    }

    // MARK: - Pill « Aperçu · exemple »
    private var previewPill: some View {
        HStack(spacing: Theme.spacingXS) {
            Image(systemName: "eye")
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text("Aperçu · exemple")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color.healthMapBlue)
        .padding(.horizontal, Theme.spacingMD)
        .frame(minHeight: 32)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.healthMapBlue.opacity(Theme.opacityMedium), lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Nutriment exemple (état A)
    private var exampleNutrientLine: some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.scoreExcellent)
                .accessibilityHidden(true)
            Text("Fer\u{202F}: 38 → 64")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.healthMapText)
            Spacer()
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Nutriment réel (état B)
    @ViewBuilder private var realNutrientLine: some View {
        if let n = dashboardVM.deficiencies.first {
            HStack(spacing: Theme.spacingSM) {
                Text(n.emoji)
                    .font(.system(size: 16))
                Text("\(n.label)\u{202F}: \(n.score) / 70 visé")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.healthMapText)
                    .lineLimit(1)
                Spacer()
                Text(HealthScale.nutrientLabel(for: n.score))
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.scoreColor(for: n.score))
            }
            .padding(Theme.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - Série / Badges (exemple vs réel)
    private var exampleStatRow: some View {
        HStack(spacing: Theme.spacingSM) {
            statTile(icon: "flame.fill", value: "5 jours", caption: "1 joker dispo")
            statTile(icon: "medal.fill", value: "3/8", caption: "badges")
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    private var realStatRow: some View {
        HStack(spacing: Theme.spacingSM) {
            statTile(
                icon: "flame.fill",
                value: "\(gamification.currentStreak) jours",
                caption: "meilleure\u{202F}: \(gamification.bestStreak)"
            )
            statTile(
                icon: "medal.fill",
                value: "\(gamification.earnedBadges.count)/\(BadgeType.allCases.count)",
                caption: "badges"
            )
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    private func statTile(icon: String, value: String, caption: String) -> some View {
        VStack(spacing: Theme.spacingXS) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.healthMapBlue)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.healthMapText)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Color.healthMapSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.spacingMD)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Delta vert (état B)
    @ViewBuilder private var deltaHeader: some View {
        let delta = SuiviStore.baseline > 0 ? dashboardVM.healthScore - SuiviStore.baseline : 0
        if delta > 0 {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.scoreExcellent)
                    .accessibilityHidden(true)
                Text("+\(delta) depuis le début de ton suivi")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.scoreExcellent)
                Spacer()
            }
            .padding(Theme.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.scoreExcellent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - CTA « Commencer »
    private var startCTA: some View {
        Button {
            HapticService.shared.primary()
            showObjectives = true
        } label: {
            VStack(spacing: 2) {
                Text("Commencer mon suivi personnalisé")
                    .font(.system(size: 15, weight: .semibold))
                Text("3 questions · 1 minute")
                    .font(.system(size: 12))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.healthMapBlue)
            )
        }
        .buttonStyle(.healthMapPressed)
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Projection premium (calculée, jamais inventée)
    private var projectionCard: some View {
        BlurredSection(isPremium: true, title: "Ta projection de score personnalisée") {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.healthMapBlue)
                    .accessibilityHidden(true)
                Text("Dans 6 semaines\u{202F}: \(projectedScore)/100 estimé si tu tiens ton plan.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Theme.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Données calculées
    /// Estimation transparente : score actuel + 5 pts par besoin prioritaire
    /// traité (plafonné à +15, et à 100). Dérivée du vrai score, jamais inventée.
    private var projectedScore: Int {
        let gain = min(15, dashboardVM.deficiencies.prefix(3).count * 5)
        return min(100, dashboardVM.healthScore + gain)
    }

    private var exampleBars: [BarPoint] {
        let scores = [48, 44, 52, 58, 64, 70]
        return scores.enumerated().map { i, s in
            BarPoint(label: "S\(i + 1)", score: s, isUp: i == 0 ? true : s >= scores[i - 1])
        }
    }

    private var realBars: [BarPoint] {
        let series = SuiviStore.weeklySeries()
        return series.enumerated().map { i, e in
            BarPoint(label: "S\(i + 1)", score: e.score, isUp: i == 0 ? true : e.score >= series[i - 1].score)
        }
    }

    // MARK: - Carte « courbe en construction » (état B, < 2 points)
    private var buildingCard: some View {
        VStack(spacing: Theme.spacingSM) {
            MascotView(mood: .thinking, size: 56)
            Text("Ta courbe se construit")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.healthMapText)
            Text("Reviens chaque semaine\u{202F}: ton score s'affichera ici, semaine après semaine.")
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacingLG)
        .frame(maxWidth: .infinity)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }
}

// MARK: - Bar Point (un point de la courbe hebdo)
private struct BarPoint: Identifiable {
    let id = UUID()
    let label: String
    let score: Int
    let isUp: Bool
}

// MARK: - Weekly Score Card (« Ton score, semaine après semaine »)
private struct WeeklyScoreCard: View {
    let points: [BarPoint]
    let isExample: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            Text("Ton score, semaine après semaine")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.healthMapText)

            // Courbe lissée + aire (façon courbe de poids Foodvisor) : fini les
            // barres et les ronds ✓/✗. Une seule couleur de marque, point final
            // mis en valeur. La couleur de PALIER vit dans l'anneau, pas ici.
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let pts: [CGPoint] = points.enumerated().map { i, bp in
                    let x = points.count <= 1 ? w / 2 : CGFloat(i) / CGFloat(points.count - 1) * w
                    let t = CGFloat(max(0, min(100, bp.score))) / 100
                    return CGPoint(x: x, y: h - 6 - t * (h - 12))
                }
                ZStack {
                    Path { path in
                        guard let first = pts.first, let last = pts.last else { return }
                        path.move(to: CGPoint(x: first.x, y: h))
                        for pt in pts { path.addLine(to: pt) }
                        path.addLine(to: CGPoint(x: last.x, y: h))
                        path.closeSubpath()
                    }
                    .fill(Color.healthMapBlue.opacity(isExample ? 0.08 : 0.14))

                    Path { path in
                        for (i, pt) in pts.enumerated() {
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(
                        Color.healthMapBlue.opacity(isExample ? 0.55 : 1.0),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )

                    if let last = pts.last {
                        Circle()
                            .fill(Color.healthMapBlue.opacity(isExample ? 0.55 : 1.0))
                            .frame(width: 8, height: 8)
                            .position(x: last.x, y: last.y)
                    }
                }
            }
            .frame(height: 88)

            HStack(spacing: 0) {
                ForEach(points) { p in
                    Text(p.label)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.healthMapSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Évolution du score sur \(points.count) semaines")
    }
}

// MARK: - Daily Checkin Card (Énergie / Sommeil / Stress — état B)
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
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            Text("Check-in du jour")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.healthMapText)

            ForEach(metrics, id: \.key) { m in
                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    HStack(spacing: Theme.spacingSM) {
                        Image(systemName: m.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.healthMapBlue)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(m.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.healthMapText)
                    }

                    HStack(spacing: Theme.spacingSM) {
                        ForEach(Array(levels.enumerated()), id: \.offset) { idx, lvl in
                            let level = idx + 1
                            let selected = values[m.key] == level
                            Button {
                                HapticService.shared.selection()
                                values[m.key] = level
                                onChange()
                            } label: {
                                Text(lvl)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(selected ? .white : Color.healthMapBlue)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 44)
                                    .background {
                                        if selected {
                                            Capsule().fill(Color.healthMapBlue)
                                        } else {
                                            Capsule().fill(.ultraThinMaterial)
                                        }
                                    }
                                    .overlay(
                                        Capsule().stroke(Color.healthMapBlue.opacity(Theme.opacityMedium), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.healthMapPressed)
                            .accessibilityLabel("\(m.label), \(lvl)\(selected ? ", sélectionné" : "")")
                        }
                    }
                }
            }

            if values.count >= metrics.count {
                Label("C'est noté pour aujourd'hui", systemImage: "checkmark.circle.fill")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.scoreExcellent)
                    .transition(.opacity)
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
        .animation(reduceMotion ? .none : .healthMapQuick, value: values.count)
    }
}

// MARK: - Suivi Objectives Sheet (mini-questionnaire « 3 questions · 1 minute »)
private struct SuiviObjectivesSheet: View {
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var objectif: String?
    @State private var rappel: String?
    @State private var moment: String?

    private let objectifs = ["Plus d'énergie", "Mieux dormir", "Moins de stress", "Renforcer mes carences"]
    private let rappels = ["Chaque jour", "En semaine", "Pas de rappel"]
    private let moments = ["Matin", "Midi", "Soir"]

    private var ready: Bool { objectif != nil && rappel != nil && moment != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingLG) {
                    questionBlock(title: "Ton objectif principal\u{202F}?", options: objectifs, selection: $objectif)
                    questionBlock(title: "Tu veux un rappel\u{202F}?", options: rappels, selection: $rappel)
                    questionBlock(title: "Le meilleur moment pour toi\u{202F}?", options: moments, selection: $moment)
                }
                .padding(Theme.spacingLG)
            }
            .background(Color.healthMapBackground)
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
                        .font(Theme.headlineFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .fill(ready ? Color.healthMapBlue : Color.healthMapMuted)
                        )
                }
                .buttonStyle(.healthMapPressed)
                .disabled(!ready)
                .padding(.horizontal, Theme.spacingLG)
                .padding(.vertical, Theme.spacingSM)
                .background(Color.healthMapBackground)
            }
        }
    }

    private func questionBlock(title: String, options: [String], selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.healthMapText)
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
            HStack(spacing: Theme.spacingSM) {
                Text(label)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Color.healthMapText)
                    .multilineTextAlignment(.leading)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.healthMapBlue)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Theme.spacingMD)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(selected ? Color.healthMapBlueLight : Color.healthMapCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(
                        selected ? Color.healthMapBlue.opacity(0.3) : Color.healthMapMuted.opacity(Theme.opacityStrong),
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
        return dict.sorted { $0.key < $1.key }.suffix(6).map { (week: $0.key, score: $0.value) }
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
