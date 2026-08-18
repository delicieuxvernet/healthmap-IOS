import SwiftUI
import UIKit

// MARK: - Scan Home (journal calories du jour) — sous-vues
//
// Page d'accueil de l'onglet Scan refondue en JOURNAL DU JOUR : navigation
// jour par jour, carte « Ta journée » (kcal + macros), apports micronutriments
// du jour, scans récents. Langage v4 : fond crème, cartes `.kiwiCard`,
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

    // Version compacte intégrée au header (retour build 319) : le bloc
    // monospace + gros cercles blancs détonnait de la DA — la nav jour vit
    // désormais sur UNE ligne discrète sous le titre « Scan », chevrons
    // inline vert kiwi (zone tactile 44 pt conservée via frame).
    var body: some View {
        HStack(spacing: 2) {
            chevron("chevron.left", enabled: true, hint: "Jour précédent", action: onPrev)
            Text("\(label) · \(sub)")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .lineLimit(1)
            chevron("chevron.right", enabled: canNext, hint: "Jour suivant", action: onNext)
        }
        .accessibilityElement(children: .combine)
    }

    private func chevron(_ icon: String, enabled: Bool, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Color.kiwiGreenInk : Color.healthMapMuted.opacity(0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .disabled(!enabled)
        .accessibilityLabel(hint)
    }
}

// MARK: - Carte « Ta journée » (kcal restantes + macros)
/// Le bloc que porte l'en-tête du journal du jour, remonté sur l'accueil Scan
/// (retour Arthur du 29 juil. 2026 : « très concis, beaucoup d'informations
/// clés rapidement »). Il remplace l'ancienne jauge à trois colonnes, où les
/// nombres consommées / restantes se touchaient faute de place.
///
/// Une seule carte porte donc désormais : kcal restantes vs budget, la barre de
/// progression, l'énergie dépensée (Apple Santé) et les quatre macros. Le budget
/// reste `objectif + dépensées`, comme la jauge qu'elle remplace.
///
/// Sans objectif calculable : aucun objectif inventé — on affiche les kcal
/// consommées seules, sans barre. Jour passé : on ne parle pas de « restantes »
/// (la journée est finie), on rapporte le consommé à l'objectif du jour.
struct ScanJourneeCard: View {
    let consommees: Int
    let objectif: Int?
    let depensees: Int?
    let isToday: Bool
    let prot: (g: Double, target: Int?)
    let carb: (g: Double, target: Int?)
    let fat: (g: Double, target: Int?)
    let fiber: (g: Double, target: Int?)
    /// Phrase de synthèse des macros (`dayMacroHeadline`) — reprise de la carte
    /// à anneaux qu'on remplace : elle disait ce qui manque, on ne la perd pas.
    let headline: String

    private var budget: Int { (objectif ?? 0) + (depensees ?? 0) }
    private var restantes: Int { budget - consommees }
    private var over: Bool { objectif != nil && restantes < 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScanCardHeader(icon: "flame.fill", title: "Ta journée")

            if objectif == nil {
                // Objectif non calculable : le consommé, rien d'autre.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(consommees)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Text("kcal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(abs(isToday ? restantes : consommees))")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(over ? Color.scoreDeficient : Color.kiwiGreenInk)
                    Text(titreKcal)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                    Spacer(minLength: 8)
                    Text("\(consommees) / \(budget)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.healthMapSecondary)
                        .layoutPriority(1)
                }

                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.kiwiGreen.opacity(0.14))
                        Capsule()
                            .fill(over ? Color.scoreDeficient : Color.kiwiGreen)
                            .frame(width: max(4, g.size.width * fractionRemplie))
                    }
                }
                .frame(height: 8)

                if let depensees, depensees > 0 {
                    Text("Budget élargi de \(depensees) kcal dépensées · Apple Santé")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.healthMapMuted)
                }
            }

            Text(headline)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                macroBar("Protéines", prot, .macroProtein)
                macroBar("Glucides", carb, .macroCarb)
                macroBar("Lipides", fat, .macroFat)
                macroBar("Fibres", fiber, .kiwiGreen)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard(radius: 20)
        .accessibilityElement(children: .contain)
    }

    private var titreKcal: String {
        if !isToday { return "kcal sur \(budget)" }
        return over ? "kcal au-dessus" : "kcal restantes"
    }

    private var fractionRemplie: CGFloat {
        guard budget > 0 else { return 0 }
        return max(0, min(1, CGFloat(consommees) / CGFloat(budget)))
    }

    /// Barre macro : rempli vs cible réelle du profil ; SANS cible → grammes
    /// seuls sur piste neutre vide (jamais un ratio inventé).
    private func macroBar(_ label: String, _ m: (g: Double, target: Int?), _ color: Color) -> some View {
        let grammes = Int(m.g.rounded())
        let hasTarget = (m.target ?? 0) > 0
        return VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.healthMapMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(hasTarget ? "\(grammes)/\(m.target!) g" : "\(grammes) g")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.healthMapSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.16))
                    if hasTarget {
                        Capsule().fill(color)
                            .frame(width: max(2, g.size.width * CGFloat(min(1, m.g / Double(m.target!)))))
                    }
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) : \(grammes) grammes\(hasTarget ? " sur \(m.target!)" : "").")
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
    /// Découverte (V12e) : sans bilan, les % listés rapportent la journée aux
    /// références d'un adulte moyen — la mention le précise sous la liste.
    var reperesGeneriques: Bool = false

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
                if reperesGeneriques {
                    ReperesGeneriquesMention()
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
            // Mini-photo du scan quand elle existe (vignette locale — retour
            // build 319) ; sinon l'illustration existante (dictée, recherche,
            // scan fait sur un autre appareil).
            if let thumb = MealThumbnailStore.image(mealId: meal.id, consumedAt: meal.consumedAt) {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
            } else {
                ZStack {
                    Circle().fill(Color.kiwiGreenSoft).frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.kiwiGreen)
                }
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
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
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


