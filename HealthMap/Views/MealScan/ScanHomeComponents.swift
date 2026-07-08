import SwiftUI

// MARK: - Scan Home (journal calories du jour) — sous-vues
//
// Page d'accueil de l'onglet Scan refondue en JOURNAL DU JOUR : navigation
// jour par jour, jauge kcal « Ta journée », apports micronutriments du jour,
// macros du jour, scans récents. Langage v4 : fond crème, cartes `.kiwiCard`,
// anneaux pleins (recette ZStack track + trim, cap round, rotation -90),
// couleur = sens (vert ≥60 « ok » / ambre ≥30 « à renforcer » / rouge « à
// combler »). Aucun chiffre inventé : une cible absente → anneau gris neutre,
// jamais de fraction fabriquée. La logique (bindings) reste dans MealScanView ;
// ces composants ne sont que de l'habillage.

// MARK: - En-tête de section (icône + titre)
/// En-tête réutilisable : petite icône système + titre. Utilisé à l'intérieur
/// des cartes (apports / macros) comme hors carte (« Ta journée »).
struct ScanCardHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.kiwiGreen)
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
        }
    }
}

// MARK: - Seuils communs (couleur = sens)
private func scanStatusColor(_ pct: Int) -> Color {
    pct >= 60 ? .kiwiGreen : (pct >= 30 ? .scoreLow : .scoreDeficient)
}
private func scanStatusLabel(_ pct: Int) -> String {
    pct >= 60 ? "ok" : (pct >= 30 ? "à renforcer" : "à combler")
}

// MARK: - Navigation jour par jour
/// Chevron gauche (rond blanc) + libellé du jour (bold) et sous-libellé (mono
/// discret) + chevron droit (désactivé/estompé si on est déjà sur aujourd'hui).
/// Le chevron gauche est toujours actif : la borne basse est gérée en amont
/// (fenêtre de la quinzaine). Cibles tactiles 44×44 pt.
struct ScanDayNav: View {
    let label: String
    let sub: String
    let canNext: Bool
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            chevron("chevron.left", enabled: true, hint: "Jour précédent", action: onPrev)
            Spacer()
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text(sub)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.healthMapMuted)
            }
            Spacer()
            chevron("chevron.right", enabled: canNext, hint: "Jour suivant", action: onNext)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func chevron(_ icon: String, enabled: Bool, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.kiwiInk)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.healthMapCard))
                .overlay(Circle().stroke(Color.kiwiCharcoal.opacity(0.06), lineWidth: 1))
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Circle())
        }
        .buttonStyle(.healthMapPressed)
        .disabled(!enabled)
        .accessibilityLabel(hint)
    }
}

// MARK: - Jauge kcal « Ta journée »
/// Carte kcal du jour : consommées · anneau budget · (dépensées, si dispo).
/// Budget = objectif (kcal) + dépensées (Apple Santé). Anneau vert tant que le
/// budget n'est pas dépassé, rouge en surplus. Sans objectif calculable : aucun
/// objectif inventé — l'anneau reste gris neutre et le centre affiche seulement
/// les kcal consommées. `depensees == nil` (V1, Apple Santé pas encore branché) :
/// la colonne dépensées est MASQUÉE, plutôt qu'un « 0 via Apple Santé » trompeur.
/// `isToday` : un jour passé ne parle pas de « restantes » (journée finie).
struct ScanKcalGauge: View {
    let consommees: Int
    let objectif: Int?
    let depensees: Int?
    let isToday: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: CGFloat = 0

    private var budget: Int { (objectif ?? 0) + (depensees ?? 0) }
    private var restantes: Int { budget - consommees }
    private var over: Bool { objectif != nil && restantes < 0 }
    private var fraction: CGFloat {
        guard objectif != nil, budget > 0 else { return 0 }
        if over { return 1 }
        return max(0, min(1, CGFloat(consommees) / CGFloat(max(1, budget))))
    }
    private var arcColor: Color {
        objectif == nil ? Color.healthMapMuted.opacity(0.45) : (over ? .scoreDeficient : .kiwiGreen)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            sideColumn(value: consommees, label: "consommées", sub: nil)
            ring
            if let dep = depensees {
                sideColumn(value: dep, label: "dépensées", sub: "via Apple Santé")
            } else {
                // Apple Santé pas encore branché (V1) : colonne vide pour garder
                // l'anneau centré, sans afficher de « 0 » trompeur.
                Color.clear.frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 20)
        .onAppear {
            if reduceMotion { animated = fraction }
            else { withAnimation(.easeOut(duration: 1.0).delay(0.2)) { animated = fraction } }
        }
        .onChange(of: fraction) { _, new in
            if reduceMotion { animated = new }
            else { withAnimation(.easeOut(duration: 0.7)) { animated = new } }
        }
    }

    private func sideColumn(value: Int, label: String, sub: String?) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.kiwiCharcoal)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.healthMapMuted)
            if let sub {
                Text(sub)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.healthMapMuted)
                    .opacity(0.85)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(arcColor.opacity(0.15), lineWidth: 12)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(arcColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .frame(width: 150, height: 150)
    }

    @ViewBuilder
    private var center: some View {
        if objectif == nil {
            VStack(spacing: 2) {
                Text("\(consommees)")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text("kcal")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
        } else if !isToday {
            // Jour passé : on ne parle pas de « restantes » (journée finie). On
            // montre ce qui a été consommé, rapporté à l'objectif du jour.
            VStack(spacing: 2) {
                Text("\(consommees)")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text("sur \(objectif ?? 0) kcal")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
        } else {
            // Aujourd'hui — en surplus, `restantes` est négatif : on affiche
            // l'ampleur du dépassement avec un « + » (ex. « +150 · kcal de surplus »).
            let shown = over ? abs(restantes) : restantes
            VStack(spacing: 3) {
                Image(systemName: over ? "exclamationmark.triangle.fill" : "leaf.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(arcColor)
                Text((over ? "+" : "") + "\(shown)")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text(over ? "kcal de surplus" : "kcal restantes")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
    }
}

// MARK: - Apports micronutriments du jour
/// En-tête + phrase de synthèse (les 1-2 apports les plus bas) + liste : puce
/// colorée, libellé, chip de statut (ok / à renforcer / à combler) et barre de
/// couverture (largeur = pct, couleur du seuil). Liste vide → invite honnête.
struct ScanMicrosJourCard: View {
    /// (id du nutriment, part du besoin couverte aujourd'hui 0-100).
    let items: [(id: String, pct: Int)]
    let headline: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScanCardHeader(icon: "leaf.fill", title: "Tes apports du jour")
            Text(headline)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)
            if items.isEmpty {
                Text("Scanne un repas pour suivre tes apports du jour.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.healthMapMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 13) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        row(item)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard(radius: 20)
    }

    private func row(_ item: (id: String, pct: Int)) -> some View {
        let color = scanStatusColor(item.pct)
        let label = NutrientData.definition(for: item.id)?.label ?? item.id
        return VStack(spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.nutrientColor(for: item.id))
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Spacer(minLength: 6)
                Text(scanStatusLabel(item.pct))
                    .pillStyle(color: color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15)).frame(height: 5)
                    Capsule().fill(color)
                        .frame(width: max(4, g.size.width * CGFloat(min(100, max(0, item.pct))) / 100), height: 5)
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(item.pct) pour cent du besoin, \(scanStatusLabel(item.pct)).")
    }
}

// MARK: - Macros du jour
/// En-tête + phrase de synthèse (macro la plus en retard) + rangée de 4 anneaux
/// (Protéines / Glucides / Lipides / Fibres). Anneau plein coloré si une cible
/// existe (fraction = apport / cible, plafonnée à 1) ; sinon gris neutre, sans
/// fraction inventée. Fibres : cible = 30 g (RDA, référence honnête).
struct ScanMacrosJourCard: View {
    let prot: (g: Double, target: Int?)
    let carb: (g: Double, target: Int?)
    let fat: (g: Double, target: Int?)
    let fiber: (g: Double, target: Int?)
    let headline: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScanCardHeader(icon: "chart.pie.fill", title: "Tes macros du jour")
            Text(headline)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                macro("Protéines", prot, .macroProtein)
                macro("Glucides", carb, .macroCarb)
                macro("Lipides", fat, .macroFat)
                macro("Fibres", fiber, .kiwiGreen)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard(radius: 20)
    }

    private func macro(_ label: String, _ m: (g: Double, target: Int?), _ color: Color) -> some View {
        let hasTarget = (m.target ?? 0) > 0
        let fraction: CGFloat = hasTarget ? CGFloat(min(1, m.g / Double(m.target!))) : 0
        let ringColor = hasTarget ? color : Color.healthMapMuted.opacity(0.45)
        return VStack(spacing: 7) {
            MacroRing(fraction: fraction, color: ringColor, grams: Int(m.g.rounded()))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.healthMapSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) : \(Int(m.g.rounded())) grammes\(hasTarget ? " sur \(m.target!)" : "").")
    }
}

// MARK: - Anneau macro (centre = grammes)
private struct MacroRing: View {
    let fraction: CGFloat
    let color: Color
    let grams: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(grams)")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text("g")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
            .minimumScaleFactor(0.7)
            .lineLimit(1)
        }
        .frame(width: 54, height: 54)
        .onAppear {
            if reduceMotion { animated = fraction }
            else { withAnimation(.easeOut(duration: 0.9).delay(0.2)) { animated = fraction } }
        }
        .onChange(of: fraction) { _, new in
            if reduceMotion { animated = new }
            else { withAnimation(.easeOut(duration: 0.6)) { animated = new } }
        }
    }
}

// MARK: - Scans récents
/// En-tête + jusqu'à 5 derniers repas (triés du plus récent). Chaque ligne :
/// icône (SF Symbol du 1er micro sinon fourchette), aliments, créneau + kcal,
/// heure relative. La carte entière ouvre le journal complet. Vide → masquée.
struct ScanRecentScansList: View {
    let meals: [MealJournalService.MealRecord]
    let onOpen: () -> Void

    private var recent: [MealJournalService.MealRecord] {
        Array(meals.sorted { $0.consumedAt > $1.consumedAt }.prefix(5))
    }

    var body: some View {
        if !recent.isEmpty {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ScanCardHeader(icon: "clock.arrow.circlepath", title: "Scans récents")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.healthMapMuted)
                    }
                    VStack(spacing: 10) {
                        ForEach(recent) { meal in
                            row(meal)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kiwiCard(radius: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityHint("Ouvre le journal du jour")
        }
    }

    private func row(_ meal: MealJournalService.MealRecord) -> some View {
        let icon = meal.micros.first.map { Fluent3D.symbol(for: $0.id) } ?? "fork.knife"
        let title = meal.foods.isEmpty ? "Repas" : meal.foods.joined(separator: ", ")
        return HStack(spacing: 11) {
            ZStack {
                Circle().fill(Color.kiwiGreenSoft).frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.kiwiGreen)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(meal.slot.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.healthMapMuted)
                    Text("·")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.healthMapMuted)
                    Text("\(meal.macros.calories) kcal")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.healthMapSecondary)
                }
            }
            Spacer(minLength: 6)
            Text(DateFormatters.relative.localizedString(for: meal.consumedAt, relativeTo: Date()))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.healthMapMuted)
                .lineLimit(1)
        }
    }
}
