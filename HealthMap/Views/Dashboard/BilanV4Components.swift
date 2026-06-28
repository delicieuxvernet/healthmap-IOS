import SwiftUI

// MARK: - Bilan « v4 » (refonte 3D — direction validée juin 2026)
//
// Composants de l'onglet Bilan dans le langage v4 : fond crème, cartes
// blanches arrondies, anneaux pleins, illustrations 3D (Fluent3D), pop-up
// bottom-sheet. Couleur = sens partout (échelle unique HealthScale).
// Source maquette : « Bilan v4 - 3D » (Corrections design et interface app).

// MARK: - Carte score (héros)
/// Anneau plein du score global + étincelle 3D + adjectif d'état + résumé IA.
struct BilanScoreCard: View {
    let score: Int
    let summary: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: CGFloat = 0
    @State private var floaty = false

    private var color: Color { Color.globalScoreColor(for: score) }

    /// Adjectif d'état dérivé de l'échelle unique (loi 4), reformulé pour rester
    /// naturel et dans le vocabulaire autorisé.
    private var adjective: String {
        switch HealthScale.globalLabel(for: score) {
        case "Optimal":      return "Bilan optimal"
        case "Solide":       return "Bilan solide"
        case "À surveiller": return "Bilan à consolider"
        default:             return "Bilan à renforcer"
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            ring
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Fluent3DIcon(name: Fluent3D.sparkles, size: 24)
                        .offset(y: floaty ? -3 : 0)
                    Text(adjective)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .kiwiCard()
        .onAppear {
            if reduceMotion {
                animated = CGFloat(score) / 100
            } else {
                withAnimation(.easeOut(duration: 1.2).delay(0.2)) { animated = CGFloat(score) / 100 }
                withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { floaty = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(adjective). Score \(score) sur 100.\(summary.map { " " + $0 } ?? "")")
    }

    // Anneau réduit de moitié (retour Arthur build #162) : il ne doit plus
    // dominer le héros. Ø 72 (vs 132), trait 7, chiffres mono ~24.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: 7)
                .frame(width: 72, height: 72)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                AnimatedNumberView(
                    targetValue: score,
                    font: .system(size: 24, weight: .bold, design: .monospaced),
                    color: color
                )
                Text("/ 100")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .frame(width: 72, height: 72)
    }
}

// MARK: - Jauge en champ de points (16 × 4)
/// Couverture d'un apport sous forme de grille de points : colonnes remplies =
/// part du besoin couverte. Couleur = statut (loi 3).
struct DotFieldGauge: View {
    let pct: Double          // 0...1
    let color: Color
    private let cols = 16
    private let rows = 4

    var body: some View {
        let fill = Int((pct * Double(cols)).rounded())
        VStack(spacing: 4) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { c in
                        Circle()
                            .fill(c < fill ? color : color.opacity(0.20))
                            .frame(width: 4, height: 4)
                        if c < cols - 1 { Spacer(minLength: 0) }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Colonne d'un apport (carte cliquable)
private struct ApportColumn: View {
    let nutrient: EnrichedNutrient
    let onTap: () -> Void

    private var color: Color { Color.scoreColor(for: nutrient.score) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 9) {
                DotFieldGauge(pct: Double(nutrient.score) / 100, color: color)
                Text("\(nutrient.score)%")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(nutrient.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ZStack {
                    Circle().fill(Color.kiwiCream).frame(width: 22, height: 22)
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.healthMapSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(nutrient.label), \(nutrient.score) pour cent, \(HealthScale.nutrientLabel(for: nutrient.score)). Touche pour le détail.")
    }
}

// MARK: - Carte « Tes apports à renforcer »
struct ApportsCard: View {
    let deficiencies: [EnrichedNutrient]
    let onTap: (EnrichedNutrient) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Tes apports à renforcer")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Spacer()
                Text("Touche pour le détail")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.healthMapMuted)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(deficiencies) { nutrient in
                    ApportColumn(nutrient: nutrient) { onTap(nutrient) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .kiwiCard()
    }
}

// MARK: - Carte « Symptôme détecté » (CTA compact)
struct SymptomeCardV4: View {
    let label: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.healthMapBlueLight)
                        .frame(width: 46, height: 46)
                    Image(systemName: "hand.tap")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.healthMapBlue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Symptôme détecté")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.healthMapBlue)
                    Text(label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Text("Voir pourquoi")
                        .font(.system(size: 13, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.healthMapBlue))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .kiwiCard(radius: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("Symptôme détecté : \(label). Voir pourquoi.")
    }
}

// MARK: - Carte « Ta récolte » (gamification adossée à la série)
/// Coverflow de fruits débloqués par la série de check-ins. Centre = prochain
/// fruit à débloquer ; barre = progression vers son palier. Le kiwi est la
/// récompense finale. (Mappé sur `GamificationService.currentStreak` — pas de
/// nouvelle mécanique de jeu introduite ici.)
struct RecolteCard: View {
    let streak: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floaty = false
    @State private var showDetail = false

    private var ladder: [Fluent3D.HarvestRung] { Fluent3D.harvestLadder }
    private var unlockedCount: Int { ladder.filter { streak >= $0.threshold }.count }
    private var goalIndex: Int {
        ladder.firstIndex(where: { streak < $0.threshold }) ?? (ladder.count - 1)
    }
    private var goal: Fluent3D.HarvestRung { ladder[goalIndex] }
    private var progress: Double {
        goal.threshold > 0 ? min(1, Double(streak) / Double(goal.threshold)) : 1
    }
    private var daysLeft: Int { max(0, goal.threshold - streak) }
    private var complete: Bool { unlockedCount >= ladder.count }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Ta récolte")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Spacer()
                Text("\(unlockedCount) / \(ladder.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }

            HStack(spacing: 0) {
                ForEach(Array(ladder.enumerated()), id: \.element.id) { idx, rung in
                    let dist = abs(idx - goalIndex)
                    let isGoal = idx == goalIndex
                    Fluent3DIcon(name: rung.asset, size: isGoal ? 84 : (dist == 1 ? 58 : 46))
                        .opacity(isGoal ? 1 : (dist == 1 ? 0.7 : 0.4))
                        .offset(y: isGoal && floaty ? -4 : 0)
                        .zIndex(isGoal ? 2 : (dist == 1 ? 1 : 0))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 104)

            Text(goal.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)

            if complete {
                Text("Récolte complète. Bravo !")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
            } else {
                HStack(spacing: 0) {
                    Text("Plus que ").foregroundStyle(Color.healthMapSecondary)
                    Text("\(daysLeft) jour\(daysLeft > 1 ? "s" : "")")
                        .foregroundStyle(Color.kiwiGreenInk)
                        .fontWeight(.bold)
                    Text(" pour le débloquer").foregroundStyle(Color.healthMapSecondary)
                }
                .font(.system(size: 11.5, weight: .medium))
            }

            ZStack(alignment: .leading) {
                Capsule().fill(Color.kiwiCharcoal.opacity(0.10)).frame(width: 200, height: 6)
                Capsule().fill(Color.kiwiGreen).frame(width: 200 * CGFloat(progress), height: 6)
            }
            .padding(.top, 8)
        }
        // Visuel inchangé (validé Arthur build #162) — on rend juste le bloc
        // tappable : le tap ouvre le détail de la récolte (sans rien changer à
        // l'affichage au repos).
        .contentShape(Rectangle())
        .onTapGesture {
            HapticService.shared.tap()
            showDetail = true
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { floaty = true }
        }
        .sheet(isPresented: $showDetail) {
            RecolteDetailSheet(streak: streak)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(complete
            ? "Ta récolte est complète."
            : "Ta récolte : \(unlockedCount) sur \(ladder.count). Plus que \(daysLeft) jours pour débloquer \(goal.name).")
        .accessibilityHint("Touche pour voir le détail de ta récolte.")
    }
}

// MARK: - Pop-up détail de la récolte (au tap sur le bloc récolte)
/// Détail de la gamification « récolte » : série en cours + chaque fruit, son
/// palier de jours d'affilée et s'il est obtenu. N'altère pas l'affichage au
/// repos du bloc récolte (retour Arthur : « si on ne clique pas, ça reste tel quel »).
struct RecolteDetailSheet: View {
    let streak: Int
    @Environment(\.dismiss) private var dismiss

    private var ladder: [Fluent3D.HarvestRung] { Fluent3D.harvestLadder }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Ta récolte")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.healthMapSecondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.kiwiCharcoal.opacity(0.06)))
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel("Fermer")
                }

                // Série en cours (le « trophée » de jours d'affilée)
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.kiwiGreenSoft).frame(width: 56, height: 56)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.kiwiGreen)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(streak) jour\(streak > 1 ? "s" : "") d'affilée")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.kiwiCharcoal)
                        Text("Chaque palier de série débloque un fruit.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.healthMapSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 18)

                Text("Tes fruits")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .padding(.top, 22)
                    .padding(.bottom, 10)

                VStack(spacing: 0) {
                    ForEach(Array(ladder.enumerated()), id: \.element.id) { idx, rung in
                        if idx > 0 {
                            Divider().background(Color.kiwiCharcoal.opacity(0.07))
                        }
                        rungRow(rung)
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .kiwiCard(radius: 18)
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

    @ViewBuilder
    private func rungRow(_ rung: Fluent3D.HarvestRung) -> some View {
        let earned = streak >= rung.threshold
        let left = max(0, rung.threshold - streak)
        HStack(spacing: 13) {
            Fluent3DIcon(name: rung.asset, size: 40)
                .grayscale(earned ? 0 : 1)
                .opacity(earned ? 1 : 0.35)
            VStack(alignment: .leading, spacing: 2) {
                Text(rung.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text("Débloqué à \(rung.threshold) jour\(rung.threshold > 1 ? "s" : "") d'affilée")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
            }
            Spacer(minLength: 8)
            if earned {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                    Text("Obtenu").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.kiwiGreenInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.kiwiGreenSoft))
            } else {
                Text("Dans \(left) j")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.kiwiCharcoal.opacity(0.06)))
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Carte « Tes derniers repas »
/// Liste les repas du jour (journal `meal_scans`). Vide → invite à scanner.
/// Note : `meal_scans` ne stocke pas de photo ni de couverture par repas — on
/// affiche donc une vignette teintée + aliments + heure (et non la photo/les
/// puces « bien couvert » de la maquette).
struct DerniersRepasCard: View {
    let meals: [MealJournalService.MealRecord]
    let onScan: () -> Void

    var body: some View {
        if meals.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ForEach(Array(meals.prefix(3).enumerated()), id: \.element.id) { idx, meal in
                    if idx > 0 {
                        Divider().background(Color.kiwiCharcoal.opacity(0.07)).padding(.leading, 16)
                    }
                    Button { onScan() } label: { row(meal) }
                        .buttonStyle(.healthMapPressed)
                }
            }
            .frame(maxWidth: .infinity)
            .kiwiCard(radius: 20)
        }
    }

    private func row(_ meal: MealJournalService.MealRecord) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.kiwiGreenSoft).frame(width: 52, height: 52)
                Image(systemName: "fork.knife")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.kiwiGreen)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title(meal))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .lineLimit(1)
                    Spacer()
                    Text(timeLabel(meal.consumedAt))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                }
                Text(subtitle(meal))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 16))
                .foregroundStyle(Color.healthMapMuted)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4]))
                    .foregroundStyle(Color.kiwiCharcoal.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: "camera")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.healthMapMuted)
            }
            Text("Tu n'as encore rien scanné")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
                .padding(.top, 14)
            Text("Scanne ton prochain repas pour découvrir les apports qu'il couvre.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            Button(action: onScan) {
                HStack(spacing: 8) {
                    Image(systemName: "camera").font(.system(size: 19))
                    Text("Scanner un plat").font(.system(size: 14.5, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 230, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.kiwiGreen))
                .shadow(color: Color.kiwiGreen.opacity(0.32), radius: 10, x: 0, y: 8)
            }
            .buttonStyle(.healthMapPressed)
            .padding(.top, 18)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 20)
    }

    private func title(_ meal: MealJournalService.MealRecord) -> String {
        meal.foods.first ?? meal.slot.label
    }

    private func subtitle(_ meal: MealJournalService.MealRecord) -> String {
        var parts: [String] = []
        if meal.foods.count > 1 {
            parts.append(meal.foods.dropFirst().prefix(2).joined(separator: " · "))
        }
        if meal.macros.calories > 0 {
            parts.append("\(meal.macros.calories) kcal")
        }
        return parts.isEmpty ? meal.slot.label : parts.joined(separator: " · ")
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

// MARK: - Pop-up détail d'un apport (bottom sheet)
/// Fiche courte d'un apport : anneau (% du besoin), « Pourquoi à renforcer »,
/// « Où le trouver » (sources 3D) et CTA vers le plan. Source maquette.
struct ApportDetailSheet: View {
    let nutrient: EnrichedNutrient
    let onSeePlan: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var color: Color { Color.scoreColor(for: nutrient.score) }
    private var statusLabel: String { HealthScale.nutrientLabel(for: nutrient.score) }
    private var foods: [Fluent3D.Food] { Fluent3D.foodSources(for: nutrient.id) }

    private var why: String {
        if let p = nutrient.pourquoiCeScore, !p.isEmpty { return p }
        if let v = nutrient.verdict, !v.isEmpty { return v }
        return "Tes assiettes récentes en apportent peu. Un apport régulier cette semaine t'aidera à mieux couvrir ce besoin."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                HStack { Spacer(); ring; Spacer() }
                    .padding(.top, 18)

                Text("Pourquoi à renforcer")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .padding(.top, 16)
                    .padding(.bottom, 6)
                Text(why)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !foods.isEmpty {
                    Text("Où le trouver")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                    HStack(spacing: 10) {
                        ForEach(Array(foods.enumerated()), id: \.offset) { _, food in
                            VStack(spacing: 8) {
                                Fluent3DIcon(name: food.asset, size: 40)
                                Text(food.label)
                                    .font(.system(size: 12, weight: .semibold))
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
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: Fluent3D.symbol(for: nutrient.id))
                    .font(.system(size: 24))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(nutrient.label)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(color.opacity(0.14)))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.healthMapSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.kiwiCharcoal.opacity(0.06)))
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("Fermer")
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: 12)
                .frame(width: 132, height: 132)
            Circle()
                .trim(from: 0, to: CGFloat(nutrient.score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 132, height: 132)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(nutrient.score)%")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text("de ton besoin")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .frame(width: 132, height: 132)
    }
}
