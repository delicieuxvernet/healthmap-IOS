import SwiftUI
import UIKit
import RevenueCat

// MARK: - Bilan « v6 — vivant » (contrat API v2, juillet 2026)
//
// Composants du nouvel écran Bilan, fidèles à la maquette validée
// « Bilan v6 - vivant » : greeting + petit anneau de score, carte « Ta
// journée » (repas scannés), jauges d'apports cliquables (contrat v2),
// tuiles Symptôme / Ta récolte, interactions détectées, derniers repas.
// Source de données : `DashboardViewModel.analysisV2` (AIAnalysisV2) +
// journal `meal_scans` + `GamificationService` (récolte).
//
// Couleur = sens partout : le statut d'un apport (`StatutV2`) porte sa
// couleur et son encre (mapping du contrat, côté client).

// MARK: - Libellé d'un statut (badge de la fiche apport)
extension StatutV2 {
    /// Libellé court affiché dans les badges / pastilles.
    var displayLabel: String {
        switch self {
        case .couvre:      return "Couvert"
        case .aRenforcer:  return "À renforcer"
        case .aCombler:    return "À combler"
        case .neutre:      return "À suivre"
        }
    }
}

// MARK: - Illustration 3D sûre (icône venant du contrat)
/// L'`icone` du contrat v2 est un id NU de la liste fermée du serveur
/// (ex. "fish", cf. VALID_ICONS de contract-v2.ts) — les imagesets iOS sont
/// préfixés `fluent_`. On résout donc `fluent_<id>` (et on tolère un id déjà
/// préfixé). Un id inconnu (asset absent du bundle) retombe sur l'étincelle —
/// jamais d'image vide à l'écran.
struct SafeFluent3DIcon: View {
    let name: String?
    var size: CGFloat
    var fallback: String = Fluent3D.sparkles

    private var resolved: String {
        guard let name, !name.isEmpty else { return fallback }
        let candidate = name.hasPrefix("fluent_") ? name : "fluent_\(name)"
        guard UIImage(named: candidate) != nil else { return fallback }
        return candidate
    }

    var body: some View {
        Fluent3DIcon(name: resolved, size: size)
    }
}

// MARK: - En-tête : « Bonjour {prénom} » + date + besoins nourris + petit anneau
// Refonte 3 juillet 2026 (maquette « Option B » validée) : le score figé du
// questionnaire disparaît — l'anneau affiche le SCORE DE LA SEMAINE, calculé
// sur les repas scannés (WeekScoreEngine), avec les 7 barres des jours et une
// phrase d'insight (vert = progression, ambre = recul, neutre = pas de donnée).
struct BilanGreetingHeader: View {
    let firstName: String
    let week: WeekScoreEngine.WeekScore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: CGFloat = 0

    private static let amberInk = Color(hex: "D9820A")
    private static let dayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(firstName.isEmpty ? "Bonjour" : "Bonjour \(firstName)")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    subtitle
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                ring
            }
            dayBars
            insightCard
        }
        .onAppear { animateRing(to: week.score ?? 0) }
        .onChange(of: week.score) { _, newValue in animateRing(to: newValue ?? 0) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Insight (une seule phrase, couleur = sens)

    private enum Mood { case up, down, flat, empty }

    private var mood: Mood {
        guard week.score != nil else { return .empty }
        guard let delta = week.delta else { return .flat }
        if delta >= 3 { return .up }
        if delta <= -3 { return .down }
        return .flat
    }

    private var insightText: String {
        switch mood {
        case .up:
            var t = "Ton score gagne \(week.delta ?? 0) pts vs la semaine dernière."
            if let mover = week.topMover, mover.delta > 0,
               let def = NutrientData.definition(for: mover.id) {
                t += " \(def.label) en tête."
            }
            return t
        case .down:
            var t = "Ton score perd \(abs(week.delta ?? 0)) pts vs la semaine dernière."
            if let mover = week.topMover, mover.delta < 0,
               let def = NutrientData.definition(for: mover.id) {
                t += " \(def.label) en recul — ton plan a des idées simples."
            }
            return t
        case .flat:
            if week.delta != nil {
                return "Score stable vs la semaine dernière. Chaque scan affine ton suivi."
            }
            let n = week.mealCount
            return "\(n) repas compté\(n > 1 ? "s" : "") cette semaine — ton score suit tes apports à renforcer."
        case .empty:
            return "Scanne ton premier repas pour lancer ton score de la semaine."
        }
    }

    private var insightIcon: String {
        switch mood {
        case .up:    return "arrow.up.right"
        case .down:  return "arrow.down.right"
        case .flat:  return "equal"
        case .empty: return "camera"
        }
    }

    private var insightInk: Color {
        switch mood {
        case .up:          return .kiwiGreenInk
        case .down:        return Self.amberInk
        case .flat, .empty: return .healthMapSecondary
        }
    }

    private var insightBackground: Color {
        switch mood {
        case .up:          return .kiwiTint
        case .down:        return Self.amberInk.opacity(0.12)
        case .flat, .empty: return .healthMapCard
        }
    }

    private var insightCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: insightIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(insightInk)
            Text(insightText)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(insightInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(insightBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Barres des 7 jours (lundi → dimanche)

    private var dayBars: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(barColor(day))
                        .frame(height: barHeight(day))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 36, alignment: .bottom)
            HStack(spacing: 6) {
                ForEach(Array(week.days.enumerated()), id: \.offset) { index, day in
                    Text(Self.dayLetters[index % 7])
                        .font(.system(size: 10, weight: day.isToday ? .bold : .medium))
                        .foregroundStyle(day.isToday ? Color.kiwiGreenInk : Color.healthMapSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func barHeight(_ day: WeekScoreEngine.DayScore) -> CGFloat {
        guard let s = day.score, s > 0 else { return 4 }
        return max(6, CGFloat(s) * 0.32)
    }

    private func barColor(_ day: WeekScoreEngine.DayScore) -> Color {
        guard day.score != nil else { return Color.kiwiCharcoal.opacity(0.07) }
        return day.isToday ? .kiwiGreen : Color.kiwiGreen.opacity(0.35)
    }

    // MARK: - Sous-titre + anneau

    private var subtitle: Text {
        var t = Text(dateLabel)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color.healthMapSecondary)
        if week.mealCount > 0 {
            t = t + Text(" · ")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
            t = t + Text("\(week.mealCount) repas cette semaine")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Color.kiwiGreenInk)
        }
        return t
    }

    // Anneau 64 pt : progress = score semaine / 100, vert kiwi, chiffre mono
    // + libellé « semaine ». Sans donnée : tiret, anneau vide.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.kiwiGreen.opacity(0.16), lineWidth: 6)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(Color.kiwiGreen, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                if let score = week.score {
                    AnimatedNumberView(
                        targetValue: score,
                        font: .system(size: 16, weight: .bold, design: .monospaced),
                        color: .kiwiCharcoal
                    )
                } else {
                    Text("—")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.healthMapSecondary)
                }
                Text("semaine")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
            }
        }
        .frame(width: 64, height: 64)
    }

    private var accessibilityText: String {
        var parts = [firstName.isEmpty ? "Bonjour" : "Bonjour \(firstName)", dateLabel]
        if let score = week.score {
            parts.append("Score de la semaine \(score) sur 100")
        }
        parts.append(insightText)
        return parts.joined(separator: ". ")
    }

    private func animateRing(to value: Int) {
        let target = CGFloat(min(100, max(0, value))) / 100
        if reduceMotion {
            animated = target
        } else {
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) { animated = target }
        }
    }
}

// MARK: - Carte « Ta journée » (repas du jour, source meal_scans)
/// 3 créneaux Matin / Midi / Soir : scanné (tuile verte) ou à scanner
/// (pointillé). `meal_scans` ne stocke pas de photo : la vignette est
/// l'illustration 3D du créneau (soleil / assiette / lune).
struct TaJourneeV6Card: View {
    let meals: [MealJournalService.MealRecord]
    let onScan: () -> Void

    private struct Slot: Identifiable {
        let id: String
        let title: String
        let mealName: String   // pour l'insight (« ton dîner »)
        let asset: String
        let done: Bool
    }

    private var slots: [Slot] {
        func done(_ s: MealJournalService.MealSlot) -> Bool { meals.contains { $0.slot == s } }
        return [
            Slot(id: "matin", title: "Matin", mealName: "petit-déjeuner", asset: Fluent3D.sun, done: done(.breakfast)),
            Slot(id: "midi", title: "Midi", mealName: "déjeuner", asset: Fluent3D.spaghetti, done: done(.lunch)),
            Slot(id: "soir", title: "Soir", mealName: "dîner", asset: Fluent3D.moon, done: done(.dinner)),
        ]
    }

    private var doneCount: Int { slots.filter(\.done).count }

    private var insight: String {
        let missing = slots.filter { !$0.done }
        switch missing.count {
        case 0:  return "Tes 3 repas du jour sont scannés."
        case 1:  return "Il te reste ton \(missing[0].mealName) à scanner."
        case 2:  return "Il te reste 2 repas à scanner."
        default: return "Scanne ton premier repas de la journée."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.kiwiGreenInk)
                        .accessibilityHidden(true)
                    Text("Ta journée")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.kiwiGreenInk)
                }
                Spacer()
                HStack(spacing: 4) {
                    (Text("\(doneCount)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.kiwiCharcoal)
                     + Text("/3 repas")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                        .accessibilityHidden(true)
                }
            }

            Text(insight)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            HStack(spacing: 9) {
                ForEach(slots) { slot in
                    Button {
                        onScan()
                    } label: {
                        tile(slot)
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel(slot.done
                        ? "\(slot.title), repas scanné."
                        : "\(slot.title), à scanner. Touche pour ouvrir le scanner.")
                }
            }
            .padding(.top, 13)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 22)
        .contentShape(Rectangle())
        .onTapGesture { onScan() }
    }

    @ViewBuilder
    private func tile(_ slot: Slot) -> some View {
        VStack(spacing: 5) {
            Fluent3DIcon(name: slot.asset, size: 34)
                .opacity(slot.done ? 1 : 0.45)
            Text(slot.title)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(slot.done ? Color.kiwiGreenInk : Color.healthMapMuted)
            HStack(spacing: 2) {
                Text(slot.done ? "scanné" : "scanner")
                    .font(.system(size: 9.5, weight: .bold))
                Image(systemName: slot.done ? "checkmark" : "arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.kiwiGreen)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(slot.done ? Color.kiwiGreenSoft : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    slot.done ? Color.kiwiGreen.opacity(0.4) : Color.kiwiCharcoal.opacity(0.18),
                    style: StrokeStyle(lineWidth: 1.5, dash: slot.done ? [] : [4, 4])
                )
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Jauge horizontale d'un apport (9 pt, animée, couleur = statut)
struct ApportGaugeBar: View {
    let pct: Int
    let statut: StatutV2

    @State private var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(statut.color.opacity(0.20))
                Capsule()
                    .fill(statut.color)
                    .frame(width: geo.size.width * CGFloat(min(100, max(0, pct))) / 100 * (animated ? 1 : 0))
            }
        }
        .frame(height: 9)
        .onAppear {
            if reduceMotion {
                animated = true
            } else {
                withAnimation(.easeOut(duration: 1.0).delay(0.4)) { animated = true }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Carte « Apports à renforcer » (contrat v2 : insight + 3 jauges)
struct ApportsV6Card: View {
    let insight: String?
    let apports: [ApportV2]
    let onTap: (ApportV2) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StatutV2.aRenforcer.inkColor)
                        .accessibilityHidden(true)
                    Text("Apports à renforcer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(StatutV2.aRenforcer.inkColor)
                }
                Spacer()
                Text("Auj.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.healthMapMuted)
            }

            if let insight, !insight.isEmpty {
                Text(insight)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(apports.enumerated()), id: \.offset) { _, apport in
                    column(apport)
                }
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 22)
    }

    @ViewBuilder
    private func column(_ apport: ApportV2) -> some View {
        let pct = min(100, max(0, apport.pctBesoin ?? 0))
        Button {
            onTap(apport)
        } label: {
            VStack(spacing: 7) {
                Text("\(pct)%")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(apport.statut.inkColor)
                ApportGaugeBar(pct: pct, statut: apport.statut)
                    .padding(.horizontal, 2)
                Text(apport.nom ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.healthMapSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ZStack {
                    Circle()
                        .fill(Color.kiwiGreenSoft)
                        .frame(width: 26, height: 26)
                        .shadow(color: Color.kiwiGreen.opacity(0.22), radius: 4, x: 0, y: 3)
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.kiwiGreenInk)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(apport.nom ?? "Apport"), \(pct) pour cent du besoin, \(apport.statut.displayLabel). Touche pour le détail.")
    }
}

// MARK: - Tuile « Symptôme » (première entrée du contrat)
struct SymptomeV6Tile: View {
    let nom: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Symptôme")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.healthMapBlue)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.healthMapBlue.opacity(0.5))
                        .accessibilityHidden(true)
                }

                Text(nom)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                Spacer(minLength: 12)

                HStack(spacing: 5) {
                    Text("Voir pourquoi")
                        .font(.system(size: 12, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.healthMapBlue))
                .shadow(color: Color.healthMapBlue.opacity(0.26), radius: 6, x: 0, y: 5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.healthMapBlueLight)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("Symptôme : \(nom). Voir pourquoi.")
    }
}

// MARK: - Tuile « Ta récolte » (compacte — gamification adossée à la série)
/// Version demi-largeur du bloc récolte : le PROCHAIN fruit à débloquer
/// flotte au centre, ses voisins de l'échelle sont estompés. Données réelles :
/// `GamificationService.currentStreak` + `Fluent3D.harvestLadder`.
/// Tap → détail (RecolteDetailSheet, existant).
struct RecolteV6Tile: View {
    let streak: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floaty = false
    @State private var barAnimated = false
    @State private var showDetail = false

    private var ladder: [Fluent3D.HarvestRung] { Fluent3D.harvestLadder }
    private var unlockedCount: Int { ladder.filter { streak >= $0.threshold }.count }
    private var nextIndex: Int? { ladder.firstIndex { streak < $0.threshold } }
    private var complete: Bool { nextIndex == nil }
    /// Fruit au centre : le prochain à débloquer (le dernier si récolte finie).
    private var centerIndex: Int { nextIndex ?? ladder.count - 1 }
    private var centerRung: Fluent3D.HarvestRung { ladder[centerIndex] }
    private var daysLeft: Int { complete ? 0 : max(0, centerRung.threshold - streak) }
    private var progress: Double {
        guard let n = nextIndex else { return 1 }
        let base = n > 0 ? ladder[n - 1].threshold : 0
        let span = max(1, ladder[n].threshold - base)
        return min(1, max(0, Double(streak - base) / Double(span)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Ta récolte")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color.kiwiGreenInk)
                Spacer()
                (Text("\(unlockedCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.kiwiCharcoal)
                 + Text("/\(ladder.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted))
            }

            HStack(spacing: 0) {
                if centerIndex > 0 {
                    Fluent3DIcon(name: ladder[centerIndex - 1].asset, size: 26)
                        .opacity(0.45)
                        .offset(x: 9)
                }
                Fluent3DIcon(name: centerRung.asset, size: 46)
                    .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 6)
                    .offset(y: floaty ? -4 : 0)
                    .zIndex(1)
                if centerIndex + 1 < ladder.count {
                    Fluent3DIcon(name: ladder[centerIndex + 1].asset, size: 26)
                        .opacity(0.45)
                        .offset(x: -9)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .padding(.top, 6)

            Spacer(minLength: 6)

            VStack(spacing: 7) {
                caption
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.kiwiCharcoal.opacity(0.10))
                    Capsule()
                        .fill(Color.kiwiGreen)
                        .frame(width: 92 * CGFloat(progress) * (barAnimated ? 1 : 0))
                }
                .frame(width: 92, height: 5)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .kiwiCard(radius: 20)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticService.shared.tap()
            showDetail = true
        }
        .onAppear {
            if reduceMotion {
                barAnimated = true
            } else {
                withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { floaty = true }
                withAnimation(.easeOut(duration: 1.0).delay(0.6)) { barAnimated = true }
            }
        }
        .sheet(isPresented: $showDetail) {
            RecolteDetailSheet(streak: streak)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(complete
            ? "Ta récolte est complète, \(ladder.count) fruits obtenus."
            : "Ta récolte : \(unlockedCount) sur \(ladder.count). \(centerRung.name) dans \(daysLeft) jour\(daysLeft > 1 ? "s" : "").")
        .accessibilityHint("Touche pour voir le détail de ta récolte.")
    }

    private var caption: some View {
        Group {
            if complete {
                Text("Récolte complète !")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
            } else {
                (Text("\(centerRung.name) dans ")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                 + Text("\(daysLeft) j")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.kiwiGreenInk))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

// MARK: - Carte « Interactions détectées » (≤2, contrat v2)
struct InteractionsV6Card: View {
    let interactions: [InteractionV2]

    /// On n'affiche que les entrées qui ont du texte (id stable garanti).
    private var visible: [InteractionV2] {
        interactions.filter { ($0.tipBold?.isEmpty == false) || ($0.tipRest?.isEmpty == false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.healthMapBlue)
                    .accessibilityHidden(true)
                Text("Interactions détectées")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.healthMapBlue)
                Spacer()
            }

            ForEach(Array(visible.enumerated()), id: \.offset) { idx, interaction in
                if idx > 0 {
                    Divider()
                        .background(Color.kiwiCharcoal.opacity(0.06))
                        .padding(.top, 12)
                }
                HStack(alignment: .top, spacing: 11) {
                    SafeFluent3DIcon(name: interaction.icone, size: 32)
                    interactionText(interaction)
                        .foregroundStyle(Color.kiwiCharcoal)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 20)
        .accessibilityElement(children: .combine)
    }

    private func interactionText(_ i: InteractionV2) -> Text {
        var t = Text("")
        if let bold = i.tipBold, !bold.isEmpty {
            t = t + Text(bold).font(.system(size: 13, weight: .bold))
        }
        if let rest = i.tipRest, !rest.isEmpty {
            let sep = (i.tipBold?.isEmpty == false) ? " — " : ""
            t = t + Text(sep + rest).font(.system(size: 13, weight: .medium))
        }
        return t
    }
}

// MARK: - Carte « Tes derniers repas » (journal du jour, v6)
/// `meal_scans` ne stocke ni photo ni couverture par repas : la ligne montre
/// une vignette teintée + les aliments détectés (point vert) + les kcal si
/// connues. Le call-site masque la carte quand le journal est vide.
struct DerniersRepasV6Card: View {
    let meals: [MealJournalService.MealRecord]
    let onOpenScanner: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.kiwiGreenInk)
                    .accessibilityHidden(true)
                Text("Tes derniers repas")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiGreenInk)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 6)

            ForEach(Array(meals.prefix(3).enumerated()), id: \.element.id) { idx, meal in
                if idx > 0 {
                    Divider().background(Color.kiwiCharcoal.opacity(0.07)).padding(.leading, 16)
                }
                Button {
                    onOpenScanner()
                } label: {
                    row(meal)
                }
                .buttonStyle(.healthMapPressed)
            }
        }
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 20)
    }

    @ViewBuilder
    private func row(_ meal: MealJournalService.MealRecord) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.kiwiGreenSoft).frame(width: 52, height: 52)
                Image(systemName: "fork.knife")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.kiwiGreen)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meal.foods.first ?? meal.slot.label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .lineLimit(1)
                    Spacer()
                    Text(timeLabel(meal.consumedAt))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                }
                if !meal.foods.isEmpty {
                    HStack(spacing: 6) {
                        Circle().fill(Color.kiwiGreen).frame(width: 7, height: 7)
                        Text(meal.foods.prefix(3).joined(separator: " · "))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.kiwiCharcoal.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                if meal.macros.calories > 0 {
                    HStack(spacing: 6) {
                        Circle().fill(Color.healthMapMuted.opacity(0.5)).frame(width: 7, height: 7)
                        Text("≈ \(meal.macros.calories) kcal")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.healthMapSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 15))
                .foregroundStyle(Color.healthMapMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func timeLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let hm = DateFormatter()
        hm.locale = Locale(identifier: "fr_FR")
        hm.dateFormat = "HH:mm"
        let t = hm.string(from: date)
        if cal.isDateInToday(date) { return "Auj. · \(t)" }
        if cal.isDateInYesterday(date) { return "Hier · \(t)" }
        let dm = DateFormatter()
        dm.locale = Locale(identifier: "fr_FR")
        dm.dateFormat = "d MMM"
        return "\(dm.string(from: date)) · \(t)"
    }
}

// MARK: - Bottom sheet : détail d'un apport (contrat v2)
/// Fiche fidèle à la maquette : poignée, en-tête icône + nom + badge statut,
/// grand anneau 132 pt (pctBesoin, couleur du statut), « Pourquoi », « Où le
/// trouver » (aliments du contrat, icônes 3D), encart bleu « Interaction à
/// connaître », CTA « Voir mon plan détaillé ».
struct ApportV2DetailSheet: View {
    let apport: ApportV2
    let onSeePlan: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedPct: CGFloat = 0

    private var pct: Int { min(100, max(0, apport.pctBesoin ?? 0)) }
    private var statut: StatutV2 { apport.statut }
    private var whyTitle: String {
        statut == .couvre ? "Pourquoi c'est bien couvert" : "Pourquoi à renforcer"
    }
    private var aliments: [AlimentV2] {
        (apport.aliments ?? []).filter { $0.nom?.isEmpty == false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                HStack { Spacer(); ring; Spacer() }
                    .padding(.top, 18)

                Text(whyTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .padding(.top, 16)
                    .padding(.bottom, 6)
                Text(apport.why ?? "Tes assiettes récentes en apportent peu. Un apport régulier cette semaine t'aidera à mieux couvrir ce besoin.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.kiwiCharcoal.opacity(0.85))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !aliments.isEmpty {
                    Text("Où le trouver")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                    HStack(spacing: 10) {
                        ForEach(Array(aliments.prefix(3).enumerated()), id: \.offset) { _, aliment in
                            VStack(spacing: 8) {
                                SafeFluent3DIcon(name: aliment.icone, size: 40)
                                Text(aliment.nom ?? "")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.kiwiCharcoal)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.healthMapCard))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.kiwiCharcoal.opacity(0.05), lineWidth: 1))
                        }
                    }
                }

                if (apport.tipBold?.isEmpty == false) || (apport.tipRest?.isEmpty == false) {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.healthMapBlue)
                            .padding(.top, 1)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("INTERACTION À CONNAÎTRE")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(Color.healthMapBlue)
                            tipText
                                .foregroundStyle(Color.kiwiCharcoal)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.healthMapBlueLight))
                    .padding(.top, 18)
                }

                Button {
                    onSeePlan()
                } label: {
                    HStack(spacing: 8) {
                        Text("Voir mon plan détaillé")
                            .font(.system(size: 15, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kiwiGreen))
                    .shadow(color: Color.kiwiGreen.opacity(0.34), radius: 12, x: 0, y: 8)
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.kiwiCream)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .onAppear {
            let target = CGFloat(pct) / 100
            if reduceMotion {
                animatedPct = target
            } else {
                withAnimation(.easeOut(duration: 1.0).delay(0.15)) { animatedPct = target }
            }
        }
    }

    private var tipText: Text {
        var t = Text("")
        if let bold = apport.tipBold, !bold.isEmpty {
            t = t + Text(bold).font(.system(size: 13, weight: .bold))
        }
        if let rest = apport.tipRest, !rest.isEmpty {
            let sep = (apport.tipBold?.isEmpty == false) ? " — " : ""
            t = t + Text(sep + rest).font(.system(size: 13, weight: .medium))
        }
        return t
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(statut.color.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: Fluent3D.symbol(for: apport.id ?? ""))
                    .font(.system(size: 24))
                    .foregroundStyle(statut.color)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(apport.nom ?? "Apport")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                HStack(spacing: 5) {
                    Circle().fill(statut.inkColor).frame(width: 7, height: 7)
                    Text(statut.displayLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statut.inkColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(statut.color.opacity(0.14)))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.healthMapSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.kiwiCharcoal.opacity(0.06)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("Fermer")
        }
        .accessibilityElement(children: .combine)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(statut.color.opacity(0.16), lineWidth: 12)
            Circle()
                .trim(from: 0, to: animatedPct)
                .stroke(statut.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(pct)%")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(statut.inkColor)
                Text("de ton besoin")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pct) pour cent de ton besoin couvert.")
    }
}

// MARK: - Bottom sheet : « Voir pourquoi » d'un symptôme (contrat v2)
/// Les causes du symptôme sont des ids d'apports : on les mappe sur les
/// apports du contrat (nom + statut + %). Id inconnu → libellé du catalogue
/// canonique (NutrientData), jamais l'id brut anglais.
struct SymptomeV6Sheet: View {
    let symptome: SymptomeV2
    let apports: [ApportV2]
    let onSeePlan: () -> Void

    @Environment(\.dismiss) private var dismiss

    private struct CauseRow: Identifiable {
        let id: String
        let nom: String
        let statut: StatutV2
        let pct: Int?
    }

    private var causeRows: [CauseRow] {
        (symptome.causes ?? []).enumerated().compactMap { (idx, causeId) -> CauseRow? in
            guard !causeId.isEmpty else { return nil }
            if let match = apports.first(where: { $0.id == causeId }) {
                return CauseRow(
                    id: "\(causeId)-\(idx)",
                    nom: match.nom ?? NutrientData.definition(for: causeId)?.label ?? causeId,
                    statut: match.statut,
                    pct: match.pctBesoin
                )
            }
            return CauseRow(
                id: "\(causeId)-\(idx)",
                nom: NutrientData.definition(for: causeId)?.label ?? causeId,
                statut: .neutre,
                pct: nil
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // En-tête
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.healthMapBlueLight)
                            .frame(width: 48, height: 48)
                        Image(systemName: "hand.tap")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.healthMapBlue)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(symptome.nom ?? "Symptôme")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.kiwiCharcoal)
                        Text("\(causeRows.count) apport\(causeRows.count > 1 ? "s" : "") lié\(causeRows.count > 1 ? "s" : "")")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.healthMapSecondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.kiwiCharcoal.opacity(0.06)))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel("Fermer")
                }

                if !causeRows.isEmpty {
                    Text("Ce symptôme peut être lié à ces apports :")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.kiwiCharcoal.opacity(0.85))
                        .padding(.top, 16)
                        .padding(.bottom, 10)

                    VStack(spacing: 0) {
                        ForEach(Array(causeRows.enumerated()), id: \.element.id) { idx, row in
                            if idx > 0 {
                                Divider().background(Color.kiwiCharcoal.opacity(0.07))
                            }
                            HStack(spacing: 10) {
                                Circle().fill(row.statut.inkColor).frame(width: 8, height: 8)
                                Text(row.nom)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.kiwiCharcoal)
                                Spacer()
                                if let pct = row.pct {
                                    Text("\(min(100, max(0, pct)))%")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(row.statut.inkColor)
                                }
                            }
                            .padding(.vertical, 12)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(row.nom), \(row.statut.displayLabel)\(row.pct.map { ", \($0) pour cent du besoin" } ?? "")")
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .kiwiCard(radius: 18)
                }

                Button {
                    onSeePlan()
                } label: {
                    HStack(spacing: 8) {
                        Text("Voir mon plan détaillé")
                            .font(.system(size: 15, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kiwiGreen))
                    .shadow(color: Color.kiwiGreen.opacity(0.34), radius: 12, x: 0, y: 8)
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 22)

                Text("Informatif\u{202F}: ne remplace pas un avis médical.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.healthMapMuted)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.kiwiCream)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }
}

// MARK: - Carte « Kiwio Premium » (entrée paywall visible sur le Bilan)
/// Entrée Premium directement sur l'écran principal — maquette validée le
/// 20 juillet 2026. Raison d'être : l'unique entrée paywall était l'avatar
/// Profil (invisible pour App Review → refus 2.1(b) « cannot locate the
/// In-App Purchases »). Affichée uniquement pour les non-premium.
/// Le sous-titre (essai gratuit + prix hebdo/mensuel) est lu depuis StoreKit
/// via l'offering RevenueCat — jamais codé en dur. Sans offering chargée,
/// repli sur la promesse produit, sans prix.
struct PremiumEntryCard: View {
    let onTap: () -> Void

    @ObservedObject private var subscriptionService = SubscriptionService.shared

    /// Formule courte de l'offering courante (hebdo prioritaire, sinon mensuel)
    /// — même logique que PaywallView.shortPlan.
    private var shortPackage: Package? {
        let packages = subscriptionService.offerings?.current?.availablePackages
        return packages?.first { $0.packageType == .weekly }
            ?? packages?.first { $0.packageType == .monthly }
    }

    private var subtitle: String {
        guard let package = shortPackage else {
            return "Toute ton analyse, sans limite"
        }
        let price = package.localizedPriceString
        let unit = package.packageType == .weekly ? "sem" : "mois"
        if let discount = package.storeProduct.introductoryDiscount,
           discount.paymentMode == .freeTrial {
            let period = discount.subscriptionPeriod
            let days: Int
            switch period.unit {
            case .day: days = period.value
            case .week: days = period.value * 7
            case .month: days = period.value * 30
            case .year: days = period.value * 365
            }
            return "\(days) jours offerts, puis \(price) / \(unit)"
        }
        return "\(price) / \(unit) · Annulable à tout moment"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.kiwiGreenInk)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Kiwio Premium")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kiwiGreenInk)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.kiwiGreenInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.kiwiTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.kiwiGreen, lineWidth: 1.5)
            )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("Kiwio Premium. \(subtitle). Touche pour voir les formules.")
    }
}
