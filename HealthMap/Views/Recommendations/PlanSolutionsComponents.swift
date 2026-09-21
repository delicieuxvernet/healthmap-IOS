import SwiftUI

// MARK: - Plan : les icônes des nœuds et la feuille de solutions
//
// Le graphe vit dans `PlanGraphComponents.swift` (vue) et `Core/PlanGraph.swift`
// (modèle et placement). Ici, ce qui s'ouvre DERRIÈRE un nœud : la cause en une
// phrase citant les vraies valeurs du bilan, trois leviers de deux puces, le
// délai d'effet. Le contenu est dérivé de l'analyse, tronqué au format court
// (1 phrase de cause, 3 leviers × 2 puces de 12 mots max).

// MARK: - Icône d'un nœud (symptôme ou objectif)

/// Table unique des icônes par famille de symptôme / d'objectif. Partagée avec
/// le Bilan (`BilanV7SymptomesCard`) pour qu'un même symptôme porte la même
/// icône d'un onglet à l'autre.
enum PlanNodeIcon {

    /// Icône d'un symptôme déclaré (mots-clés du questionnaire).
    static func symptome(_ nom: String) -> String {
        let n = normalized(nom)
        if n.contains("ongle") || n.contains("cheveu") { return "hand.point.up" }
        if n.contains("fatigue") || n.contains("energie") { return "battery.25" }
        if n.contains("sommeil") || n.contains("dormir") { return "moon.fill" }
        if n.contains("digest") || n.contains("ventre") { return "circle.dotted" }
        if n.contains("humeur") || n.contains("stress") { return "brain.head.profile" }
        if n.contains("peau") { return "face.smiling" }
        return "waveform.path.ecg"
    }

    /// Icône d'un objectif déclaré. Un objectif parle d'une projection (bouger,
    /// dormir mieux, tenir la forme) — pas des mêmes familles qu'un symptôme.
    static func objectif(_ nom: String) -> String {
        let n = normalized(nom)
        if n.contains("sport") || n.contains("muscl") || n.contains("entrain") || n.contains("course") || n.contains("perf") { return "figure.run" }
        if n.contains("energ") || n.contains("forme") || n.contains("tonus") || n.contains("vitalit") { return "bolt.fill" }
        if n.contains("poids") || n.contains("maigr") || n.contains("mincir") || n.contains("ligne") { return "scalemass" }
        if n.contains("dorm") || n.contains("sommeil") || n.contains("nuit") { return "moon.fill" }
        if n.contains("stress") || n.contains("calme") || n.contains("seren") { return "brain.head.profile" }
        if n.contains("digest") || n.contains("ventre") || n.contains("transit") { return "circle.dotted" }
        if n.contains("peau") || n.contains("cheveu") || n.contains("ongle") { return "sparkles" }
        if n.contains("immun") || n.contains("defense") { return "shield.fill" }
        if n.contains("concentr") || n.contains("memoire") || n.contains("focus") { return "brain.head.profile" }
        return "target"
    }

    /// Icône d'une habitude déclarée (libellé du registre des apports).
    static func habitude(_ nom: String) -> String {
        let n = normalized(nom)
        if n.contains("cafe") || n.contains("the ") || n.contains("cafeine") { return "cup.and.saucer" }
        if n.contains("ecran") { return "iphone" }
        if n.contains("sommeil") || n.contains("nuit") { return "moon" }
        if n.contains("stress") { return "brain.head.profile" }
        if n.contains("tabac") || n.contains("fum") { return "smoke" }
        if n.contains("alcool") { return "wineglass" }
        if n.contains("sport") || n.contains("activite") || n.contains("sedentar") { return "figure.walk" }
        if n.contains("soleil") || n.contains("exterieur") { return "sun.max" }
        if n.contains("cuisson") || n.contains("maison") || n.contains("transform") { return "frying.pan" }
        return "arrow.triangle.2.circlepath"
    }

    private static func normalized(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }
}

// MARK: - Pop-up « solutions » (une porte ouverte)

/// Format court de la maquette : la cause en une phrase citant les vraies
/// valeurs du bilan, puis 3 leviers de 2 puces chacun, le délai d'effet, un
/// seul bouton. Rien de plus — le détail long vit sur l'onglet Compléments.
struct PlanSolutionsSheetV7: View {
    let topic: PlanTopic
    /// Ouvre l'onglet Compléments (depuis le levier « Par les compléments »).
    let onSeeSupplements: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showSources = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                // La cause, en une phrase, avec les vraies valeurs du bilan.
                // Rien à dire honnêtement → aucune amorce vide. Gratuit : si
                // l'intro d'origine est un levier actionnable, la variante
                // teasing (nomme le problème) la remplace.
                let cause = subscriptionService.isPremium ? topic.radialCause : topic.radialCauseFree
                if !cause.isEmpty {
                    Text(cause)
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(DS.paddingCarte)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dsCard()
                        .padding(.top, 18)
                }

                // Les 3 leviers. Gratuit : la silhouette reste lisible sous le
                // flou (le bilan est gratuit, l'ordonnance est Premium).
                if subscriptionService.isPremium {
                    leviers
                } else {
                    GatedOverlay(intensity: .locked) { leviers }
                    UnlockDoor(
                        icon: "lock.fill",
                        title: "Débloque tes solutions pour « \(topic.name) »",
                        subtitle: "Nutrition, compléments et habitudes : le détail à appliquer.",
                        zone: "plan_solutions"
                    )
                    .padding(.top, 12)
                }

                // Le délai d'effet attendu, affiché seulement s'il vient de l'analyse.
                if let delai = topic.radialDelai, subscriptionService.isPremium {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 15, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.dsSecondaire)
                            .accessibilityHidden(true)
                        Text(delai)
                            .font(.dsLegende)
                            .tracking(DSTracking.legende)
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, 4)
                }

                // Un seul bouton.
                DSCapsuleButton(titre: "C'est noté") {
                    HapticService.shared.tap()
                    dismiss()
                }
                .padding(.top, 20)

                // Citation des sources (App Store guideline 1.4.1), discrète,
                // au plus près du conseil qu'elles fondent.
                Button {
                    showSources = true
                } label: {
                    Text("Sources scientifiques")
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsSecondaire)
                        .underline()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .background(Color.dsFond.ignoresSafeArea())
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .sheet(isPresented: $showSources) {
            ScrollView {
                SourcesSection().padding(20)
            }
            .background(Color.dsFond.ignoresSafeArea())
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: En-tête

    private var header: some View {
        // Refonte 23 août 2026 : titre 34 / 700 + rôle en une ligne secondaire,
        // bouton fermer circulaire 32 pt à droite. Plus de tuile teintée.
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.name)
                    .font(.dsGrandTitre)
                    .tracking(DSTracking.grandTitre)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Text(topic.kicker.capitalized)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
            }
            Spacer(minLength: 0)
            DSCloseButton { dismiss() }
        }
    }

    // MARK: Les 3 leviers

    private var leviers: some View {
        VStack(spacing: DS.interCarte) {
            PlanLevierCard(
                symbol: "leaf",
                tint: Color.dsCarte,
                iconColor: Color.dsSecondaire,
                title: "Nutrition",
                titleColor: Color.dsTexte,
                bulletColor: Color.dsTertiaire,
                lines: topic.radialNutrition,
                action: nil
            )
            PlanLevierCard(
                symbol: "pills",
                tint: Color.dsCarte,
                iconColor: Color.dsSecondaire,
                title: "Compléments",
                titleColor: Color.dsTexte,
                bulletColor: Color.dsTertiaire,
                lines: topic.radialComplements,
                // Le seul chemin de sortie de la pop-up : la chaîne vers
                // l'onglet Compléments. Coupé quand la zone est gatée.
                action: subscriptionService.isPremium ? onSeeSupplements : nil
            )
            PlanLevierCard(
                symbol: "sun.max",
                tint: Color.dsCarte,
                iconColor: Color.dsSecondaire,
                title: "Habitudes",
                titleColor: Color.dsTexte,
                bulletColor: Color.dsTertiaire,
                // Le geste est déjà la seule chose que porte une habitude :
                // rien à ranger sous lui, il tient la ligne à lui seul.
                lines: topic.radialHabitudes.map { PlanLevierLine(texte: $0) },
                action: nil
            )
        }
        .padding(.top, DS.interCarte)
    }
}

// MARK: - Un levier (nutrition / compléments / habitudes)

/// Une carte de levier : un kicker de catégorie + 2 puces. Rendue vide quand la
/// source ne fournit rien pour ce levier — on ne pose pas de carte creuse.
///
/// Hiérarchie (charte du 17 août 2026) : « Par la nutrition » n'est qu'une
/// CATÉGORIE, elle annonce en kicker discret ; ce sont les puces qui portent la
/// réponse (« Lentilles ») et prennent donc la plus grande taille et l'encre la
/// plus foncée de la carte. Avant, le rapport était inversé : le titre était
/// 0,5 pt plus gros, deux crans plus gras et posé sur une tuile teintée.
private struct PlanLevierCard: View {
    let symbol: String
    let tint: Color
    let iconColor: Color
    let title: String
    let titleColor: Color
    let bulletColor: Color
    let lines: [PlanLevierLine]
    /// Rend la carte tappable quand un chemin existe (Compléments).
    let action: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if lines.isEmpty {
            EmptyView()
        } else if let action {
            Button {
                HapticService.shared.tap()
                action()
            } label: {
                card.contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)
            .accessibilityHint("Ouvre tes compléments")
        } else {
            card
        }
    }

    private var card: some View {
        // Refonte 23 août 2026 : carte blanche, icône hiérarchique secondaire,
        // catégorie en secondaire, deux puces en corps 17 avec détail 15.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
                    .frame(width: 21)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                Spacer(minLength: 0)
                if action != nil {
                    DSChevron()
                }
            }

            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(bulletColor)
                        .frame(width: 5, height: 5)
                        .padding(.top, 9)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(line.texte)
                                .font(.dsCorps)
                                .tracking(DSTracking.corps)
                                .foregroundStyle(Color.dsTexte)
                                .fixedSize(horizontal: false, vertical: true)
                            if let tag = line.tag {
                                pastille(tag, strong: line.tagStrong)
                            }
                            Spacer(minLength: 0)
                        }
                        if !line.detail.isEmpty {
                            Text(line.detail)
                                .font(.dsSousTitre)
                                .tracking(DSTracking.sousTitre)
                                .foregroundStyle(Color.dsSecondaire)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !line.astuce.isEmpty {
                            Text(line.astuce)
                                .font(.dsLegende)
                                .tracking(DSTracking.legende)
                                .foregroundStyle(Color.dsTertiaire)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, index == 0 ? 12 : 10)
            }
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    /// Pastille de priorité : capsule grise, texte secondaire (« Prioritaire »
    /// prend l'encre principale). Aucun fond coloré.
    private func pastille(_ texte: String, strong: Bool) -> some View {
        let encre = strong ? Color.dsTexte : Color.dsSecondaire
        return Text(texte)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(encre)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .layoutPriority(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.dsRemplissage))
    }
}

// MARK: - Projections « format court » d'un topic

extension PlanTopic {

    /// SF Symbol du nœud dans la refonte (aucun emoji dans l'interface) : un
    /// apport prend le symbole canonique de son nutriment (table du Bilan),
    /// un symptôme ou un objectif garde `radialSymbol`.
    var radialSymbolRefonte: String {
        if kind == .apport {
            let nutrientId = id.hasPrefix("app_") ? String(id.dropFirst(4)) : id
            return BilanV7Nutrient.icon(for: nutrientId)
        }
        return radialSymbol
    }

    /// Couleur du cerclage et de l'icône du nœud. Décoratif : le vert vif de la
    /// marque pour un objectif, le bleu pour un symptôme, la couleur canonique
    /// du nutriment pour un apport (palette nutriments). Les TEXTES accentués
    /// utilisent `accent` (vert encre) — contraste AA sur fond crème.
    var radialRing: Color {
        switch kind {
        case .symptome: return Color(hex: "2F6FE0")
        case .objectif: return Color.dsAccent
        case .apport: return apportColor ?? Color.dsAccent
        }
    }

    /// Icône du nœud, dérivée du libellé. Un apport porte son emoji canonique
    /// (`emojiBadge`) ; ce symbole n'est que le repli s'il venait à manquer.
    var radialSymbol: String {
        switch kind {
        case .symptome: return PlanNodeIcon.symptome(name)
        case .objectif: return PlanNodeIcon.objectif(name)
        case .apport: return "leaf.fill"
        }
    }

    /// La cause, en une phrase : les vraies valeurs du bilan d'abord (jamais un
    /// chiffre inventé), puis la première phrase de l'explication de l'analyse.
    var radialCause: String {
        assembledCause(from: intro)
    }

    /// Variante GRATUITE de la cause : quand l'intro d'origine décrit un geste
    /// (`introTeasing` non nil), sa reformulation nomme le problème à la place —
    /// les vraies valeurs du bilan restent citées, le levier reste premium.
    var radialCauseFree: String {
        assembledCause(from: introTeasing ?? intro)
    }

    private func assembledCause(from text: String) -> String {
        let sentence = KiwiProse.phrase(PlanTopicText.firstSentence(KiwiProse.lisible(text)))
        guard !scoreEvidence.isEmpty else { return sentence }
        return sentence.isEmpty ? "\(scoreEvidence)." : "\(scoreEvidence). \(sentence)"
    }

    /// « Vitamine B12 à 35 % · Fer à 48 % » — les apports attachés à ce nœud.
    private var scoreEvidence: String {
        evidence
            .prefix(2)
            .map { "\($0.label) à \($0.score)\u{202F}%" }
            .joined(separator: " · ")
    }

    /// 2 puces « Par la nutrition ». L'aliment tient la ligne ; les repères
    /// déjà calculés par le builder (combien, quand, avec quoi l'associer) le
    /// suivent au lieu d'être jetés — ils étaient calculés puis perdus.
    /// `cuisson` reste hors puce : c'est la même phrase pour tous les aliments,
    /// elle n'apprend rien (cf. rapport d'audit, cas 18).
    var radialNutrition: [PlanLevierLine] {
        nutrition.prefix(2).map { food in
            PlanLevierLine(
                texte: food.label,
                detail: PlanTopicText.joined([food.qty, food.moment.lowercased()]),
                astuce: PlanTopicText.clip(food.astuce)
            )
        }
    }

    /// 2 puces « Par les compléments ». Le complément tient la ligne, son
    /// dosage suit, et la priorité calculée au bilan (« Prioritaire » sous 45,
    /// « Si besoin » au-dessus) s'affiche enfin en pastille.
    var radialComplements: [PlanLevierLine] {
        complements.prefix(2).map { supplement in
            PlanLevierLine(
                texte: supplement.name,
                detail: PlanTopicText.clip(supplement.note),
                tag: supplement.tag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : supplement.tag,
                tagStrong: supplement.strong
            )
        }
    }

    /// 2 puces « Par les habitudes ».
    var radialHabitudes: [String] {
        habitudes.prefix(2).map { habit in
            let note = PlanTopicText.clip(habit.note)
            return note.isEmpty ? PlanTopicText.clip(habit.text) : note
        }
    }

    /// Délai d'effet — uniquement s'il vient de l'analyse.
    var radialDelai: String? {
        guard let raw = delai?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let sentence = PlanTopicText.firstSentence(raw)
        return sentence.isEmpty ? nil : sentence
    }
}

/// Coupe éditoriale du format court : 1 phrase de cause, des puces de 12 mots.
enum PlanTopicText {

    /// Première phrase d'un texte libre (l'analyse en renvoie parfois trois).
    static func firstSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let end = trimmed.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            let sentence = String(trimmed[...end]).trimmingCharacters(in: .whitespaces)
            // Une « phrase » d'un seul mot est un faux positif (abréviation).
            if sentence.split(separator: " ").count >= 3 { return sentence }
        }
        return trimmed
    }

    /// Assemble des repères courts en une ligne, en ignorant ceux qui sont
    /// vides : une puce ne porte jamais un séparateur suspendu.
    static func joined(_ parts: [String], separator: String = " · ") -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    /// Tronque à 12 mots — la règle de rédaction de la maquette. Si l'analyse
    /// en renvoie plus, on coupe plutôt que de laisser déborder la puce.
    static func clip(_ text: String, maxWords: Int = 12) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        let words = cleaned.split(separator: " ")
        guard words.count > maxWords else { return cleaned }
        return words.prefix(maxWords).joined(separator: " ") + "…"
    }
}
