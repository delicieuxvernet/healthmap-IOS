import SwiftUI
import UIKit

// MARK: - Scan Home (journal calories du jour) — sous-vues
//
// Page d'accueil de l'onglet Scan refondue en JOURNAL DU JOUR : navigation
// jour par jour, carte « Ta journée » (kcal + macros), ce qui a été mangé,
// apports micronutriments du jour. Langage v4 : fond crème, cartes `.kiwiCard`,
// couleur = sens (vert ≥60 « ok » / ambre ≥30 « à renforcer » / rouge « à
// combler »). Aucun chiffre inventé : une cible absente → pas de fraction
// fabriquée. La logique (bindings) reste dans MealScanView ; ces composants ne
// sont que de l'habillage.
//
// Hiérarchie (charte du 17 août 2026) : les titres de section passent par
// `ScanCardHeader` — 13/bold à l'encre du DOMAINE, jamais l'encre neutre — et
// les conclusions de carte portent `Theme.conclusionFont` (17/heavy), ce qui
// fait d'elles le pic de leur carte. Les chiffres qui justifient une carte
// (kcal restantes, % de couverture) sont des données-héros : jamais sous 15 pt,
// arrondis et à chasse fixe.

// MARK: - Encres de domaine des titres de section
/// Un titre de section n'est jamais neutre (règle 1 de la charte) : il porte
/// l'encre de son domaine. Les deux domaines de l'onglet Scan sont l'ÉNERGIE
/// (kcal, budget du jour, repas comptés) et les APPORTS (micronutriments).
/// Les deux encres tiennent 4,5:1 sur carte blanche — l'orange du lavis de
/// l'onglet (`macroFat`) ne le tient pas à 13 pt, d'où cette version foncée.
enum ScanDomaine {
    static let energie = Color(hex: "9A5A00")
    static let apports = Color.kiwiGreenInk
}

// MARK: - En-tête de section (icône + titre)
/// En-tête réutilisable : petite icône système + titre, tous deux à l'encre du
/// domaine. C'est LE patron de titre de section de l'onglet (même grammaire que
/// `BilanV7SectionLabel` côté Bilan) : 13/bold teinté, icône 15/semibold.
struct ScanCardHeader: View {
    let icon: String
    let title: String
    /// Encre du domaine. Par défaut les apports (vert), domaine majoritaire.
    var color: Color = ScanDomaine.apports

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.sectionLabelFont)
        }
        .foregroundStyle(color)
    }
}

// MARK: - Seuils communs (couleur = sens)
private func scanStatusColor(_ pct: Int) -> Color {
    pct >= 60 ? .kiwiGreen : (pct >= 30 ? .scoreLow : .scoreDeficient)
}
/// Encre du statut — la version lisible sur blanc de `scanStatusColor`. Les
/// teintes vives conviennent à une barre ou à une pastille, pas à du texte de
/// 15 pt : la donnée-héros chiffrée prend donc l'encre, jamais la teinte.
private func scanStatusInk(_ pct: Int) -> Color {
    pct >= 60 ? Color.kiwiInk : (pct >= 30 ? BilanV7.warnInk : BilanV7.alertInk)
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
            ScanCardHeader(icon: "flame.fill", title: "Ta journée", color: ScanDomaine.energie)

            if objectif == nil {
                // Objectif non calculable : le consommé, rien d'autre.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(consommees)")
                        .font(Theme.heroValueFont)
                        .foregroundStyle(Color.kiwiCharcoal)
                    Text("kcal")
                        .font(Theme.dataSecondaryFont)
                        .foregroundStyle(Color.healthMapSecondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(abs(isToday ? restantes : consommees))")
                        .font(Theme.heroValueFont)
                        .foregroundStyle(over ? Color.scoreDeficient : Color.kiwiGreenInk)
                    Text(titreKcal)
                        .font(Theme.dataSecondaryFont)
                        .foregroundStyle(Color.healthMapSecondary)
                    Spacer(minLength: 8)
                    Text("\(consommees) / \(budget)")
                        .font(Theme.dataSecondaryFont.monospacedDigit())
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
                        .font(Theme.chromeFont)
                        .foregroundStyle(Color.healthMapMuted)
                }
            }

            // La conclusion de la carte : le plus gros texte du bloc, jamais
            // tronqué (règle 2 de la charte).
            Text(headline)
                .font(Theme.conclusionFont)
                .tracking(Theme.conclusionTracking)
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
                .font(Theme.chromeFont)
                .foregroundStyle(Color.healthMapMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(hasTarget ? "\(grammes)/\(m.target!) g" : "\(grammes) g")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
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

// MARK: - « Mangé aujourd'hui » + porte vers la journée
/// Ce que la page doit raconter en premier : ce qui a DÉJÀ été enregistré
/// aujourd'hui. Une ligne par repas (aliments à gauche, créneau + kcal à
/// droite), puis une ligne-lien qui ouvre le journal du jour complet.
///
/// Aucun repas enregistré → la carte ne s'affiche pas du tout : une coquille
/// vide n'apprend rien et pousse la vraie information vers le bas.
struct ScanMangeAujourdhuiCard: View {
    let meals: [MealJournalService.MealRecord]
    /// kcal restantes sur le budget du jour. nil = aucun objectif calculable :
    /// on annonce alors le consommé, jamais une cible inventée.
    let kcalRestantes: Int?
    let consommees: Int
    /// Jour passé : on ne parle plus de « restantes » (la journée est finie) et
    /// le titre cesse de dire « aujourd'hui ».
    let isToday: Bool
    let onOpenJournee: () -> Void

    private var trie: [MealJournalService.MealRecord] {
        meals.sorted { $0.consumedAt < $1.consumedAt }
    }
    /// Reste réellement affichable : seul aujourd'hui a des kcal « restantes ».
    private var reste: Int? { isToday ? kcalRestantes : nil }
    private var depassement: Bool { (reste ?? 0) < 0 }

    var body: some View {
        if !trie.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ScanCardHeader(
                    icon: "fork.knife",
                    title: isToday ? "Mangé aujourd'hui" : "Mangé ce jour-là",
                    color: ScanDomaine.energie
                )

                VStack(spacing: 0) {
                    ForEach(Array(trie.enumerated()), id: \.element.id) { index, meal in
                        if index > 0 {
                            Divider().overlay(Color.kiwiCharcoal.opacity(0.06))
                        }
                        ligne(meal)
                    }
                }

                lienJournee
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kiwiCard(radius: 20)
        }
    }

    private func ligne(_ meal: MealJournalService.MealRecord) -> some View {
        let titre = meal.foods.isEmpty ? "Repas" : meal.foods.joined(separator: ", ")
        return HStack(spacing: 10) {
            vignette(meal)
            Text(titre)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.kiwiCharcoal)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(meal.slot.label) · \(meal.macros.calories) kcal")
                .font(Theme.dataSecondaryFont.monospacedDigit())
                .foregroundStyle(Color.healthMapMuted)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(meal.slot.label) : \(titre), \(meal.macros.calories) kilocalories.")
    }

    /// Mini-photo du scan quand elle existe (vignette locale, retour build
    /// 319) ; sinon la pastille fourchette — dictée, recherche, ou scan fait
    /// depuis un autre appareil.
    @ViewBuilder
    private func vignette(_ meal: MealJournalService.MealRecord) -> some View {
        if let thumb = MealThumbnailStore.image(mealId: meal.id, consumedAt: meal.consumedAt) {
            Image(uiImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        } else {
            ZStack {
                Circle().fill(Color.kiwiGreenSoft).frame(width: 30, height: 30)
                Image(systemName: meal.micros.first.map { Fluent3D.symbol(for: $0.id) } ?? "fork.knife")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kiwiGreen)
            }
            .accessibilityHidden(true)
        }
    }

    /// La porte vers la journée complète : fond gris très pâle, 44 pt de haut,
    /// le chiffre qui compte en donnée-héros de ligne.
    private var lienJournee: some View {
        Button(action: onOpenJournee) {
            HStack(spacing: 8) {
                texteLien
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.kiwiCharcoal.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel(libelleVocal)
        .accessibilityHint("Ouvre le journal du jour")
    }

    /// « Ta journée : **420** kcal restantes · macros · micros ». Le chiffre
    /// porte la donnée-héros de ligne, le reste est de l'habillage.
    private var texteLien: Text {
        let prefixe = Text("Ta journée : ")
            .font(Theme.dataSecondaryFont)
            .foregroundStyle(Color.healthMapSecondary)
        let valeur = Text(chiffre)
            .font(Theme.heroValueRowFont)
            .foregroundStyle(depassement ? Color.scoreDeficient : Color.kiwiGreenInk)
        let suffixe = Text(" \(unite) · macros · micros")
            .font(Theme.dataSecondaryFont)
            .foregroundStyle(Color.healthMapSecondary)
        return prefixe + valeur + suffixe
    }

    private var chiffre: String {
        guard let reste else { return "\(consommees)" }
        return "\(abs(reste))"
    }

    private var unite: String {
        guard let reste else { return "kcal comptées" }
        return reste >= 0 ? "kcal restantes" : "kcal au-dessus"
    }

    private var libelleVocal: String {
        "Ta journée : \(chiffre) \(unite). Macros et apports détaillés."
    }
}

// MARK: - Apports micronutriments du jour
/// En-tête + phrase de synthèse (les 1-2 apports les plus bas) + liste : puce
/// colorée, libellé, PART DU BESOIN COUVERTE (la donnée-héros de la ligne),
/// chip de statut et barre de couverture. Liste vide → invite honnête.
struct ScanMicrosJourCard: View {
    /// (id du nutriment, part du besoin couverte aujourd'hui 0-100).
    let items: [(id: String, pct: Int)]
    let headline: String
    /// Découverte (V12e) : sans bilan, les % listés rapportent la journée aux
    /// références d'un adulte moyen — la mention le précise sous la liste.
    var reperesGeneriques: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScanCardHeader(icon: "leaf.fill", title: "Tes apports du jour", color: ScanDomaine.apports)
            Text(headline)
                .font(Theme.conclusionFont)
                .tracking(Theme.conclusionTracking)
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
        let ink = scanStatusInk(item.pct)
        let label = NutrientData.definition(for: item.id)?.label ?? item.id
        return VStack(spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.nutrientColor(for: item.id))
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(Color.kiwiCharcoal)
                Spacer(minLength: 6)
                // La valeur était calculée depuis toujours et ne servait qu'à la
                // largeur de la barre : elle est la raison d'être de la ligne,
                // elle se lit donc (charte : jamais sous 15 pt).
                Text("\(item.pct)\u{202F}%")
                    .font(Theme.heroValueRowFont)
                    .foregroundStyle(ink)
                Text(scanStatusLabel(item.pct))
                    .pillStyle(color: ink)
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

// MARK: - Tutoriel de première visite (3 bulles)
/// Montré UNE fois, à la première arrivée sur l'onglet Scan, puis plus jamais.
/// Trois bulles, une par geste de la page : les deux gros boutons, la carte de
/// ce qui a été mangé, la carte des apports. Toujours passable d'un tap.
///
/// Patron repris de `TabTourOverlay` (le coach mark déjà en place) : voile
/// sombre, carte posée en bas, points de progression, « Passer » / « Suivant ».
/// Ici la carte est sombre et la DA kiwi, pour ne pas se confondre avec les
/// cartes blanches de la page qu'elle commente.
struct ScanTutorialOverlay: View {
    /// Fermeture : le parent mémorise la visite (AppStorage) et retire l'overlay.
    var onTermine: () -> Void

    @State private var etape = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Bulle {
        let icone: String
        let titre: String
        let texte: String
    }

    private let bulles: [Bulle] = [
        Bulle(icone: "mic.fill",
              titre: "Dicte ou photographie ton repas",
              texte: "Les deux gros boutons en haut. Maintiens le micro pour dicter, ou prends ton assiette en photo."),
        Bulle(icone: "fork.knife",
              titre: "Tes aliments s'ajoutent ici",
              texte: "Juste sous la recherche, la carte « Mangé aujourd'hui » liste tes repas du jour et ouvre ta journée complète."),
        Bulle(icone: "leaf.fill",
              titre: "Et tes apports du jour se mettent à jour là",
              texte: "Plus bas, la carte des apports montre ce que tu as déjà couvert et ce qu'il reste à renforcer."),
    ]

    private var derniere: Bool { etape == bulles.count - 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {} // le voile absorbe les taps, il ne ferme pas par erreur

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // Le repère de direction : ce dont parle la bulle est au-dessus.
                Image(systemName: "chevron.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)

                carte
                    .padding(.horizontal, Theme.spacingLG)
                    .padding(.bottom, 120)
            }
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Découverte de l'onglet Scan, étape \(etape + 1) sur \(bulles.count)")
    }

    private var carte: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: bulles[etape].icone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.kiwiGreen)
                    .accessibilityHidden(true)
                Text(bulles[etape].titre)
                    .font(Theme.insightFont)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(bulles[etape].texte)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(0..<bulles.count, id: \.self) { index in
                    Capsule()
                        .fill(index == etape ? Color.kiwiGreen : Color.white.opacity(0.28))
                        .frame(width: index == etape ? 16 : 6, height: 6)
                }
                Spacer(minLength: 0)
            }
            .accessibilityHidden(true)

            HStack(spacing: 10) {
                Button {
                    HapticService.shared.tap()
                    onTermine()
                } label: {
                    Text("Passer")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)

                Button {
                    HapticService.shared.tap()
                    if derniere {
                        onTermine()
                    } else {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                            etape += 1
                        }
                    }
                } label: {
                    Text(derniere ? "Terminer" : "Suivant")
                        .font(Theme.ctaFont)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.kiwiGreen)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.kiwiCharcoal)
        )
    }
}
