import SwiftUI

// MARK: - Bilan « v7 — dashboard » (maquette « Kiwio - Bilan (standalone) », 22 juillet 2026)
//
// Portage à l'identique de la maquette HTML autonome (iPhone 393 pt). Les
// composants nommés de la maquette deviennent des vues SwiftUI :
//   .card        → `bilanV7Card()`
//   .section-label → `BilanV7SectionLabel`
//   .metric-row  → lignes des cartes apports / attention / symptômes
//   .ring        → `BilanV7ScoreRing`
//   .bar         → `BilanV7Bar`
//   .cta         → bouton « Voir mes solutions »
//   .tabbar      → `KiwiFloatingTabBar` (Scan central surélevé)
//
// Ordre de lecture Z1 → Z7 : en-tête · score compact · apports (héros) ·
// points d'attention · symptômes suivis · série · derniers repas · Premium.
//
// Règle : couleur = sens. Le statut d'un apport porte sa couleur, la pastille
// d'un nutriment porte SA couleur mémo (alignée sur `Color.nutrientColor`).
// Aucune donnée n'est inventée : une section sans donnée réelle est masquée.

// MARK: - Palette de l'écran (hex de la maquette)
enum BilanV7 {
    static let ink = Color(hex: "211F1A")
    static let secondary = Color(hex: "6B7280")
    static let soft = Color(hex: "9CA3AF")
    static let chevron = Color(hex: "C2BDB0")
    static let hairline = Color(hex: "211F1A").opacity(0.06)

    /// Libellés de section.
    static let amber = Color(hex: "D9820A")      // « Tes apports à renforcer »
    static let alertInk = Color(hex: "C0322A")   // « Points d'attention » + % bas
    static let warnInk = Color(hex: "B36B00")    // % intermédiaire
    static let blue = Color(hex: "2F6FE0")       // « Tes symptômes suivis » + badge
    static let flame = Color(hex: "FB8500")      // « Ta série »

    /// Statuts (mêmes teintes que le contrat côté serveur).
    static let statusCovered = Color(hex: "5DA838")
    static let statusReinforce = Color(hex: "FF9500")
    static let statusFill = Color(hex: "FF3B30")
    static let statusNeutral = Color(hex: "C2BDB0")

    static let sourcesInk = Color(hex: "B7B1A4")

    /// Marges de l'écran (maquette : 20 pt de marge, 14 pt entre les cartes).
    static let gutter: CGFloat = 20
    static let cardGap: CGFloat = 14
}

// MARK: - Couleur + encre d'un statut d'apport
extension StatutV2 {
    /// Couleur pleine (jauge, pastille).
    var v7Color: Color {
        switch self {
        case .couvre:     return BilanV7.statusCovered
        case .aRenforcer: return BilanV7.statusReinforce
        case .aCombler:   return BilanV7.statusFill
        case .neutre:     return BilanV7.statusNeutral
        }
    }

    /// Encre du pourcentage (contraste AA sur fond blanc).
    var v7Ink: Color {
        switch self {
        case .couvre:     return Color.kiwiInk
        case .aRenforcer: return BilanV7.warnInk
        case .aCombler:   return BilanV7.alertInk
        case .neutre:     return BilanV7.secondary
        }
    }
}

// MARK: - Carte blanche (.card)
/// `border-radius:16 · box-shadow:0 1px 3px rgba(33,31,26,.05) · border 1px`.
struct BilanV7CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.healthMapCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BilanV7.ink.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: BilanV7.ink.opacity(0.05), radius: 1.5, x: 0, y: 1)
    }
}

extension View {
    func bilanV7Card() -> some View { modifier(BilanV7CardStyle()) }
}

// MARK: - Appui (.tap:active → scale .98)
struct BilanV7PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Libellé de section (.section-label)
struct BilanV7SectionLabel: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(color)
    }
}

// MARK: - Jauge hairline (.bar)
/// Largeur = `value` (0-1) de la piste ; remplissage animé à l'apparition.
struct BilanV7Bar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 7
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * (grown ? min(1, max(0, value)) : 0))
            }
        }
        .frame(height: height)
        .onAppear {
            guard !grown else { return }
            if reduceMotion {
                grown = true
            } else {
                withAnimation(.easeOut(duration: 1).delay(delay)) { grown = true }
            }
        }
    }
}

// MARK: - Anneau de score (.ring)
/// Piste vert 15 %, arc plein, départ à midi. Le chiffre central est en
/// monospace et compte de 0 jusqu'à la valeur.
struct BilanV7ScoreRing: View {
    let score: Int?
    var size: CGFloat = 64
    var lineWidth: CGFloat = 7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var shown: Int = 0

    private var target: Double { Double(score ?? 0) / 100 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.kiwiGreen.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.kiwiGreen, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(score == nil ? "—" : "\(shown)")
                .font(.system(size: 19, weight: .heavy, design: .rounded).monospacedDigit())
                .tracking(-0.8)
                .foregroundStyle(BilanV7.ink)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .onAppear(perform: animate)
        .onChange(of: score) { _, _ in
            progress = 0
            shown = 0
            animate()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score == nil ? "Score du jour indisponible" : "Score du jour : \(score ?? 0) sur 100")
    }

    private func animate() {
        guard let score else { return }
        if reduceMotion {
            progress = target
            shown = score
            return
        }
        withAnimation(.easeOut(duration: 1).delay(0.2)) { progress = target }
        // Compteur 0 → score (easeOutCubic, ~1 s), sans Timer à nettoyer.
        Task { @MainActor in
            let steps = max(1, min(score, 60))
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(1000 / steps))
                let p = Double(step) / Double(steps)
                shown = Int((Double(score) * (1 - pow(1 - p, 3))).rounded())
            }
            shown = score
        }
    }
}

// MARK: - Z1 · En-tête « Bilan » + pill Premium
struct BilanV7Header: View {
    let date: Date
    let showsPremiumPill: Bool
    let onPremium: () -> Void

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Bilan")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(BilanV7.ink)
                Text(Self.dayFormatter.string(from: date))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(BilanV7.soft)
            }
            Spacer(minLength: 0)
            if showsPremiumPill {
                Button(action: onPremium) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Premium")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.kiwiInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.kiwiTint, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BilanV7PressStyle())
                .accessibilityLabel("Découvrir Kiwio Premium")
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Z2 · Score du jour (compact)
struct BilanV7ScoreCard: View {
    let score: Int?
    let delta: Int?
    let insight: String?
    let onTap: () -> Void

    /// « En hausse : +5 cette semaine » (le delta en monospace, teinté sens).
    private var trendLine: Text {
        guard let delta, delta != 0 else {
            return Text(insight ?? "Ton suivi démarre. Scanne tes repas pour le faire vivre.")
        }
        let lead = delta > 0 ? "En hausse : " : "En baisse : "
        let value = delta > 0 ? "+\(delta)" : "\(delta)"
        let color = delta > 0 ? Color.kiwiInk : BilanV7.alertInk
        var line = Text(lead)
            + Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
            + Text(" cette semaine.")
        if let insight, !insight.isEmpty {
            line = line + Text(" \(insight)")
        }
        return line
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                BilanV7ScoreRing(score: score)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ton score du jour")
                        .font(.system(size: 15, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(BilanV7.ink)
                    trendLine
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BilanV7.secondary)
                        .lineSpacing(1.5)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BilanV7.chevron)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .bilanV7Card()
            .contentShape(Rectangle())
        }
        .buttonStyle(BilanV7PressStyle())
        .accessibilityHint("Voir le détail de ton score")
    }
}

// MARK: - Icône + article d'un nutriment
enum BilanV7Nutrient {
    /// SF Symbol par nutriment (table Tabler → SF Symbols du cahier).
    static func icon(for id: String) -> String {
        switch id {
        case "vitD":      return "sun.max.fill"
        case "vitB12":    return "cross.vial"
        case "iron":      return "drop.fill"
        case "magnesium": return "bolt.heart.fill"
        case "omega3":    return "fish.fill"
        case "vitC":      return "leaf.fill"
        case "calcium":   return "figure.stand"
        case "zinc":      return "bolt.fill"
        case "iodine":    return "drop.triangle.fill"
        case "fiber":     return "leaf.circle.fill"
        default:          return "circle.hexagongrid.fill"
        }
    }

    /// Article défini (le genre porte la phrase de priorité).
    static func article(for id: String) -> String {
        switch id {
        case "vitD", "vitB12", "vitC": return "La"
        case "omega3", "fiber":        return "Les"
        case "iodine":                 return "L'"
        default:                       return "Le"
        }
    }

    /// « La B12 est ta priorité aujourd'hui. »
    static func prioritySentence(id: String?, nom: String) -> String {
        guard let id, !nom.isEmpty else { return "\(nom) est ta priorité aujourd'hui." }
        let art = article(for: id)
        let joint = art == "L'" ? "" : " "
        return "\(art)\(joint)\(nom) est ta priorité aujourd'hui."
    }
}

// MARK: - Z3 · Tes apports à renforcer (HÉROS)
struct BilanV7ApportsCard: View {
    let apports: [ApportV2]
    let total: Int
    let onTap: (ApportV2) -> Void

    private var priority: String {
        guard let first = apports.first, let nom = first.nom, !nom.isEmpty else {
            return "Tes apports sont au vert aujourd'hui."
        }
        return BilanV7Nutrient.prioritySentence(id: first.id, nom: nom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BilanV7SectionLabel(icon: "target", text: "Tes apports à renforcer", color: BilanV7.amber)
                Spacer()
                Text("\(apports.count) sur \(total)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BilanV7.soft)
            }

            Text(priority)
                .font(.system(size: 17, weight: .heavy))
                .tracking(-0.35)
                .lineSpacing(2)
                .foregroundStyle(BilanV7.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
                .padding(.bottom, 4)

            ForEach(Array(apports.enumerated()), id: \.offset) { index, apport in
                row(apport, delay: 0.35 + Double(index) * 0.05)
                    .padding(.top, index == 0 ? 10 : 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bilanV7Card()
    }

    @ViewBuilder
    private func row(_ apport: ApportV2, delay: Double) -> some View {
        let id = apport.id ?? ""
        let tint = Color.nutrientColor(for: id)
        let pct = max(0, min(100, apport.pctBesoin ?? 0))

        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.1))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: BilanV7Nutrient.icon(for: id))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                )
                .accessibilityHidden(true)

            VStack(spacing: 7) {
                HStack {
                    Text(apport.nom ?? "")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(BilanV7.ink)
                    Spacer()
                    Text("\(pct)%")
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(apport.statut.v7Ink)
                }
                BilanV7Bar(value: Double(pct) / 100, color: apport.statut.v7Color, delay: delay)
            }

            Button {
                HapticService.shared.tap()
                onTap(apport)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.kiwiInk)
                    .frame(width: 26, height: 26)
                    .background(Color(hex: "787880").opacity(0.1), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BilanV7PressStyle())
            .accessibilityLabel("Voir comment renforcer \(apport.nom ?? "cet apport")")
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) {
            Rectangle().fill(BilanV7.hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticService.shared.tap()
            onTap(apport)
        }
    }
}

// MARK: - Z3b · Points d'attention
struct BilanV7AttentionCard: View {
    let items: [InteractionV2]
    /// Le titre IA (`tipBold`) est un GESTE actionnable (« Ne prends pas fer
    /// et calcium ensemble ») : c'est ce que la porte du pop-up vend. En
    /// gratuit, la carte nomme donc le PROBLÈME (teasing déterministe du
    /// catalogue), jamais la solution — le titre IA reste réservé au premium.
    let isPremium: Bool
    let onTap: (InteractionV2) -> Void

    /// Icône du contrat (id NU) → SF Symbol de la maquette.
    private func icon(for raw: String?) -> String {
        switch raw {
        case "coffee", "cup", "tea":     return "cup.and.saucer"
        case "pill", "pills", "capsule": return "pills"
        case "milk", "dairy":            return "waterbottle"
        case "fish":                     return "fish"
        default:                         return "exclamationmark.triangle"
        }
    }

    /// Titre de la ligne : IA en premium, teasing « problème » en gratuit.
    private func title(for item: InteractionV2) -> String? {
        if isPremium {
            guard let bold = item.tipBold, !bold.isEmpty else { return nil }
            return bold
        }
        return AttentionMechanismCatalog.freeTitle(for: item)
    }

    /// Sous-titre : détail IA en premium ; en gratuit, une provenance neutre
    /// (le détail IA peut lui aussi porter le geste — jamais en clair).
    private func detail(for item: InteractionV2) -> String? {
        if isPremium {
            guard let rest = item.tipRest, !rest.isEmpty else { return nil }
            return rest
        }
        return "Détecté dans tes réponses"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BilanV7SectionLabel(
                icon: "exclamationmark.triangle",
                text: "Points d'attention",
                color: BilanV7.alertInk
            )

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                // Maquette : la 1re ligne porte l'accent rouge, les suivantes l'ambre.
                let tint = index == 0 ? BilanV7.statusFill : BilanV7.statusReinforce
                Button {
                    HapticService.shared.tap()
                    onTap(item)
                } label: {
                    HStack(spacing: 11) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(tint.opacity(index == 0 ? 0.1 : 0.12))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: icon(for: item.icone))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(tint)
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 1) {
                            if let title = title(for: item) {
                                Text(title)
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundStyle(BilanV7.ink)
                                    .multilineTextAlignment(.leading)
                            }
                            if let detail = detail(for: item) {
                                Text(detail)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(BilanV7.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BilanV7.chevron)
                            .accessibilityHidden(true)
                    }
                    .padding(.top, index == 0 ? 6 : 0)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BilanV7PressStyle())
                .overlay(alignment: .bottom) {
                    if index < items.count - 1 {
                        Rectangle().fill(BilanV7.hairline).frame(height: 1)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bilanV7Card()
    }
}

// MARK: - Z4 · Tes symptômes suivis
/// Ligne prête à afficher : le verdict vient de `SuiviEngineV4` (mêmes courbes
/// que l'onglet Suivi). `showsTrend` est faux tant que le suivi n'a pas démarré
/// (on n'affiche jamais une tendance qui serait un simple exemple) ET en
/// gratuit : le verdict d'évolution est la trajectoire, réservée au premium —
/// la ligne nomme alors le symptôme, sans son évolution.
struct BilanV7SymptomRow: Identifiable {
    let id: String
    let nom: String
    let verdict: String
    let improving: Bool
    let showsTrend: Bool
}

struct BilanV7SymptomesCard: View {
    let rows: [BilanV7SymptomRow]
    let solutionsCount: Int
    let onTapSymptom: (BilanV7SymptomRow) -> Void
    let onSolutions: () -> Void

    /// Icône par famille de symptôme (mots-clés du questionnaire). Table unique
    /// partagée avec la carte radiale du Plan : un même symptôme porte la même
    /// icône d'un onglet à l'autre.
    private func icon(for nom: String) -> String {
        PlanNodeIcon.symptome(nom)
    }

    private func trendIcon(_ row: BilanV7SymptomRow) -> String {
        row.improving ? "arrow.down.right" : "arrow.left.and.right"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BilanV7SectionLabel(
                icon: "waveform.path.ecg",
                text: "Tes symptômes suivis",
                color: BilanV7.blue
            )

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let tint = row.showsTrend && !row.improving ? BilanV7.statusReinforce : BilanV7.blue
                Button {
                    HapticService.shared.tap()
                    onTapSymptom(row)
                } label: {
                    HStack(spacing: 11) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(tint.opacity(0.1))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: icon(for: row.nom))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(tint)
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.nom)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(BilanV7.ink)
                                .multilineTextAlignment(.leading)
                            if row.showsTrend {
                                HStack(spacing: 4) {
                                    Image(systemName: trendIcon(row))
                                        .font(.system(size: 11, weight: .bold))
                                    Text(row.verdict.lowercased())
                                        .font(.system(size: 11.5, weight: .semibold))
                                }
                                .foregroundStyle(row.improving ? Color.kiwiInk : BilanV7.soft)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BilanV7.chevron)
                            .accessibilityHidden(true)
                    }
                    .padding(.top, index == 0 ? 6 : 0)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BilanV7PressStyle())
                .overlay(alignment: .bottom) {
                    if index < rows.count - 1 {
                        Rectangle().fill(BilanV7.hairline).frame(height: 1)
                    }
                }
            }

            Button {
                HapticService.shared.tap()
                onSolutions()
            } label: {
                HStack(spacing: 8) {
                    Text("Voir mes solutions")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.white)
                    if solutionsCount > 0 {
                        Text("\(solutionsCount)")
                            .font(.system(size: 11.5, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(BilanV7.blue, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.kiwiGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(BilanV7PressStyle())
            .padding(.top, 6)
            .accessibilityLabel(
                solutionsCount > 0
                    ? "Voir mes solutions, \(solutionsCount) disponibles"
                    : "Voir mes solutions"
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bilanV7Card()
    }
}

// MARK: - Z5 · Ta série (streak + prochain trophée)
struct BilanV7SerieCard: View {
    let streak: Int
    let onTrophies: () -> Void

    private var ladder: [Fluent3D.HarvestRung] { Fluent3D.harvestLadder }
    private var nextIndex: Int? { ladder.firstIndex { streak < $0.threshold } }
    private var complete: Bool { nextIndex == nil }
    private var rung: Fluent3D.HarvestRung { ladder[nextIndex ?? ladder.count - 1] }
    private var daysLeft: Int { complete ? 0 : max(0, rung.threshold - streak) }
    private var progress: Double {
        guard let n = nextIndex else { return 1 }
        let base = n > 0 ? ladder[n - 1].threshold : 0
        let span = max(1, ladder[n].threshold - base)
        return min(1, max(0, Double(streak - base) / Double(span)))
    }

    /// « Prochain trophée : Mandarine dans 2 jours » (le nom et le compte en gras).
    private var nextLine: Text {
        guard !complete else {
            return Text("Récolte complète. Tous les trophées sont à toi.")
        }
        return Text("Prochain trophée : ")
            + Text(rung.name).font(.system(size: 12, weight: .bold)).foregroundStyle(BilanV7.ink)
            + Text(" dans ")
            + Text("\(daysLeft)").font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            + Text(daysLeft > 1 ? " jours" : " jour")
    }

    var body: some View {
        Button {
            HapticService.shared.tap()
            onTrophies()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BilanV7SectionLabel(icon: "flame.fill", text: "Ta série", color: BilanV7.flame)
                    Spacer()
                    HStack(spacing: 3) {
                        Text("trophées")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(BilanV7.soft)
                }

                HStack(spacing: 13) {
                    Fluent3DIcon(name: rung.asset, size: 46)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        (Text("\(streak)").font(.system(size: 14.5, weight: .heavy, design: .rounded).monospacedDigit())
                            + Text(streak > 1 ? " jours d'affilée" : " jour d'affilée")
                                .font(.system(size: 14.5, weight: .heavy)))
                            .tracking(-0.2)
                            .foregroundStyle(BilanV7.ink)

                        nextLine
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(BilanV7.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        BilanV7Bar(value: progress, color: Color.kiwiGreen, height: 6, delay: 0.5)
                            .padding(.top, 6)
                    }
                }
                .padding(.top, 12)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bilanV7Card()
            .contentShape(Rectangle())
        }
        .buttonStyle(BilanV7PressStyle())
        .accessibilityLabel("Ta série : \(streak) jours d'affilée. Voir les trophées.")
    }
}

// MARK: - Z6 · Tes derniers repas
/// Ligne de bilan du journal : positive (✓ vert) ou à renforcer (⚠ ambre).
struct BilanV7RepasLine: Identifiable {
    let id: String
    let positive: Bool
    let text: String
}

struct BilanV7RepasCard: View {
    let lines: [BilanV7RepasLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BilanV7SectionLabel(icon: "fork.knife", text: "Tes derniers repas", color: Color.kiwiInk)

            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: line.positive ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(line.positive ? Color.kiwiGreen : BilanV7.statusReinforce)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    Text(line.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineSpacing(2.5)
                        .foregroundStyle(Color(hex: "3A3833"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, index == 0 ? 11 : 9)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bilanV7Card()
    }
}

// MARK: - Z7 · Kiwio Premium (grande carte verte pleine)
struct BilanV7PremiumCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Kiwio Premium")
                        .font(.system(size: 16.5, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(.white)
                    Text("30 scans par jour, plan détaillé et suivi avancé")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 19)
            .frame(maxWidth: .infinity)
            .background(Color.kiwiGreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("Kiwio Premium : 30 scans par jour, plan détaillé et suivi avancé")
    }
}

// MARK: - Sources scientifiques (pied de page — exigence App Review 1.4.1)
/// Reprend le pied discret de la maquette en gardant les références cliquables
/// (`ScientificSources`), condition de la revue App Store.
struct BilanV7SourcesFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "book")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Sources scientifiques")
                    .font(.system(size: 11.5, weight: .bold))
            }
            .foregroundStyle(BilanV7.soft)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(ScientificSources.all) { source in
                    Link(destination: source.url) {
                        Text("\(source.name) — \(source.subtitle)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(BilanV7.sourcesInk)
                            .underline()
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Kiwio ne remplace pas un avis médical.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(BilanV7.sourcesInk)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}
