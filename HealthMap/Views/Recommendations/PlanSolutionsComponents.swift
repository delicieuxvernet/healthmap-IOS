import SwiftUI

// MARK: - Plan : les icônes des nœuds et la feuille de solutions
//
// Le graphe vit dans `PlanGraphComponents.swift` (vue) et `Core/PlanGraph.swift`
// (modèle et placement). Ici, ce qui s'ouvre DERRIÈRE un nœud (`PlanNoeudSheet`) :
// la cause, à quoi c'est relié, quoi changer dans l'assiette, les habitudes,
// un complément en dernier, le délai d'effet. Le contenu est dérivé de l'analyse, tronqué au format court
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

// MARK: - La feuille d'un nœud (maquette « Plan · graphe de liens », 20 sept. 2026)

/// Un voisin du nœud sur le graphe, prêt à s'afficher : son état et la force du
/// lien. Un ÉTAT, jamais un geste — cette rangée est lisible en gratuit.
struct PlanLienCarte: Identifiable {
    let id: String
    let nom: String
    let teinte: Color
    /// « 42 % », « −22 points », « suivi ».
    let etat: String
    let etatTeinte: Color
    /// Ce qui relie les deux, en quelques mots.
    let comment: String
    /// 1 faible · 2 moyen · 3 fort.
    let force: Int
}

/// Ce qui s'ouvre derrière un nœud. L'ordre est celui des questions qu'on se
/// pose : pourquoi, à quoi c'est relié, quoi changer dans l'assiette, quelles
/// habitudes, et seulement ensuite un complément. Tout vient de l'analyse et du
/// graphe — rien n'est inventé ; aucune dose (doctrine du 20 septembre).
///
/// Gratuit : la cause et les liens restent en clair (le bilan est gratuit) ;
/// les trois blocs de solutions sont voilés, la porte est dessous.
struct PlanNoeudSheet: View {
    let topic: PlanTopic
    let liens: [PlanLienCarte]
    /// Ouvre l'onglet Compléments (depuis le bloc « En complément »).
    let onSeeSupplements: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showSources = false
    /// L'aliment dont la pastille est dépliée.
    @State private var alimentOuvert: UUID?

    private var genre: PlanGraph.Genre {
        switch topic.kind {
        case .objectif: return .objectif
        case .symptome: return .symptome
        case .apport: return .apport
        }
    }

    private var surTitre: String {
        switch topic.kind {
        case .objectif: return "Ton objectif"
        case .symptome: return "Symptôme suivi"
        case .apport: return "Apport à renforcer"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                enTete

                // La cause, avec les vraies valeurs du bilan. Gratuit : si
                // l'intro d'origine est un levier actionnable, la variante
                // teasing (nomme le problème) la remplace.
                let cause = subscriptionService.isPremium ? topic.radialCause : topic.radialCauseFree
                if !cause.isEmpty {
                    Text(cause)
                        .font(.dsCorps)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte.opacity(0.75))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                }

                if !liens.isEmpty {
                    titre("point.3.connected.trianglepath.dotted", "À quoi c'est relié",
                          "\(liens.count) lien\(liens.count > 1 ? "s" : "") sur ton graphe",
                          teinte: Color.dsAccent)
                    rangeeDeLiens
                }

                // Les solutions. Gratuit : la silhouette reste lisible sous le
                // voile (le bilan est gratuit, l'ordonnance est Premium).
                if subscriptionService.isPremium {
                    solutions
                } else {
                    GatedOverlay(intensity: .locked) { solutions }
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
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.dsSecondaire)
                            .padding(.top, 1)
                            .accessibilityHidden(true)
                        Text(delai)
                            .font(.dsLegende)
                            .tracking(DSTracking.legende)
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 4)
                }

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
            .padding(.top, 22)
            .padding(.bottom, 26)
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(Color.dsFond.ignoresSafeArea())
        .presentationDetents([.fraction(0.92), .large])
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

    private var enTete: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(PlanGraphTeintes.fond(genre))
                Image(systemName: topic.radialSymbolRefonte)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(PlanGraphTeintes.encre(genre))
            }
            .frame(width: 48, height: 48)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(surTitre)
                    .font(.dsLegende.weight(.semibold))
                    .foregroundStyle(PlanGraphTeintes.encre(genre))
                Text(topic.name)
                    .font(.system(.title2, design: .default).weight(.bold))
                    .tracking(-0.7)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            DSCloseButton { dismiss() }
        }
        .accessibilityElement(children: .contain)
    }

    /// Un titre de bloc : pastille 30, titre 17 gras, sous-titre.
    private func titre(_ symbole: String, _ texte: String, _ sousTitre: String, teinte: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(teinte.opacity(0.12))
                Image(systemName: symbole)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(teinte)
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(texte)
                    .font(.dsHeadline.weight(.bold))
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                Text(sousTitre)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: À quoi c'est relié

    private var rangeeDeLiens: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(liens) { lien in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 7) {
                            Circle().fill(lien.teinte).frame(width: 9, height: 9)
                            Text(lien.nom)
                                .font(.system(.footnote, design: .default).weight(.semibold))
                                .foregroundStyle(Color.dsTexte)
                                .lineLimit(1)
                        }
                        Text(lien.etat)
                            .font(.system(.title3, design: .default).weight(.bold).monospacedDigit())
                            .tracking(-0.6)
                            .foregroundStyle(lien.etatTeinte)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.top, 6)
                        Text(lien.comment)
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(Color.dsSecondaire)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 3)
                        Spacer(minLength: 8)
                        HStack(spacing: 4) {
                            Capsule().fill(Self.teinteForce(lien.force)).frame(width: 14, height: 3)
                            Text(PlanHabitudeSheet.libelleForce(lien.force))
                                .font(.system(.caption2, design: .default).weight(.semibold))
                                .foregroundStyle(Self.teinteForce(lien.force))
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .frame(width: 150, alignment: .leading)
                    .frame(minHeight: 128, alignment: .top)
                    .dsCard()
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, DS.marge)
        }
        // La rangée défile bord à bord ; le reste de la feuille garde ses marges.
        .padding(.horizontal, -DS.marge)
    }

    static func teinteForce(_ force: Int) -> Color {
        force >= 3 ? .kiwiGreenInk : (force == 2 ? Color(hex: "B36B00") : .dsSecondaire)
    }

    // MARK: Les solutions (assiette, habitudes, complément)

    @ViewBuilder
    private var solutions: some View {
        if !topic.nutrition.isEmpty {
            titre("fork.knife", "Quoi changer dans ton assiette", "ajoute-les quand tu peux, sans compter",
                  teinte: Color.dsAccent)
            assiette
        }

        if !topic.habitudes.isEmpty {
            titre("repeat", "Tes habitudes", "ce qui bloque ou aide, sans rien acheter",
                  teinte: PlanGraphTeintes.symptome)
            habitudes
        }

        titre("pills", "En complément",
              topic.complements.isEmpty ? "l'assiette suffit" : "Kiwio ne gagne rien dessus",
              teinte: Color(hex: "5856D6"))
        complements
    }

    /// Des pastilles : l'aliment seul, sans grammage. En toucher une la déplie —
    /// combien, quand, comment le préparer, l'astuce.
    private var assiette: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSFlow(espacement: 8) {
                ForEach(topic.nutrition) { aliment in
                    let ouverte = alimentOuvert == aliment.id
                    Button {
                        HapticService.shared.selection()
                        let cible: UUID? = ouverte ? nil : aliment.id
                        if reduceMotion { alimentOuvert = cible }
                        else { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { alimentOuvert = cible } }
                    } label: {
                        HStack(spacing: 8) {
                            SafeFluent3DIcon(name: aliment.asset, size: 26)
                            Text(aliment.label)
                                .font(.system(.subheadline, design: .default).weight(.semibold))
                                .foregroundStyle(Color.dsTexte)
                                .lineLimit(1)
                        }
                        .padding(.leading, 9)
                        .padding(.trailing, 13)
                        .frame(minHeight: DS.cibleTactile)
                        .background(Capsule().fill(Color.dsCarte))
                        .overlay(Capsule().stroke(ouverte ? Color.dsAccent : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.dsPress)
                    .accessibilityAddTraits(ouverte ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint("Affiche comment l'intégrer")
                }
            }

            if let aliment = topic.nutrition.first(where: { $0.id == alimentOuvert }) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Self.details(aliment), id: \.cle) { detail in
                        HStack(alignment: .top, spacing: 10) {
                            Text(detail.cle)
                                .font(.dsLegende)
                                .foregroundStyle(Color.dsSecondaire)
                                .frame(width: 64, alignment: .leading)
                            Text(detail.valeur)
                                .font(.dsSousTitre)
                                .tracking(DSTracking.sousTitre)
                                .foregroundStyle(Color.dsTexte)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(DS.paddingCarte)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Ce que l'analyse a rédigé pour cet aliment — les champs vides sont sautés.
    static func details(_ aliment: PlanNutritionSolution) -> [(cle: String, valeur: String)] {
        [("combien", aliment.qty), ("quand", aliment.moment), ("comment", aliment.cuisson),
         ("astuce", aliment.astuce), ("note", aliment.note)]
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { (cle: $0.0, valeur: $0.1) }
    }

    private var habitudes: some View {
        VStack(spacing: 0) {
            ForEach(Array(topic.habitudes.enumerated()), id: \.element.id) { index, habitude in
                if index > 0 {
                    Rectangle().fill(Color.dsSeparateur).frame(height: 0.5)
                }
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.dsAccent.opacity(0.12))
                        Image(systemName: habitude.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.kiwiGreenInk)
                    }
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habitude.text)
                            .font(.dsCorps)
                            .tracking(DSTracking.corps)
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)
                        if !habitude.note.isEmpty {
                            Text(habitude.note)
                                .font(.dsLegende)
                                .tracking(DSTracking.legende)
                                .foregroundStyle(Color.dsSecondaire)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    private var complements: some View {
        VStack(alignment: .leading, spacing: 0) {
            if topic.complements.isEmpty {
                ligneComplement(nom: "Aucun complément nécessaire", etiquette: "assiette d'abord", forte: true,
                                note: "L'assiette et les habitudes suffisent ici. Kiwio ne recommande un complément que quand l'alimentation ne peut pas combler l'écart.")
            } else {
                ForEach(Array(topic.complementsSansDose.enumerated()), id: \.element.id) { index, complement in
                    if index > 0 {
                        Rectangle().fill(Color.dsSeparateur).frame(height: 0.5).padding(.vertical, 12)
                    }
                    ligneComplement(nom: complement.name, etiquette: complement.tag,
                                    forte: complement.strong, note: complement.note)
                }
                // La forme et le moment vivent sur l'onglet Compléments —
                // jamais la dose (doctrine du 20 septembre 2026).
                Button {
                    HapticService.shared.tap()
                    onSeeSupplements()
                } label: {
                    HStack(spacing: 6) {
                        Text("Voir la forme et le moment de prise")
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(.subheadline, design: .default).weight(.medium))
                    .foregroundStyle(Color.dsAccent)
                    .frame(minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private func ligneComplement(nom: String, etiquette: String, forte: Bool, note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(nom)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if !etiquette.isEmpty {
                    Text(etiquette.lowercased())
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(forte ? Color.kiwiGreenInk : Color.dsSecondaire)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(forte ? Color.dsAccent.opacity(0.12) : Color(uiColor: .systemGray5)))
                }
            }
            if !note.isEmpty {
                Text(note)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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

    /// La note d'un complément, sans jamais de dose : la posologie appartient
    /// au fabricant et à la personne (doctrine du 20 septembre 2026). Une note
    /// qui en porte une n'est pas affichée du tout — on ne la réécrit pas.
    var complementsSansDose: [PlanSupplementSolution] {
        complements.map { complement in
            PlanSupplementSolution(name: complement.name, note: PlanTopicText.sansDose(complement.note),
                                   tag: complement.tag, strong: complement.strong)
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

    /// Une quantité suivie d'une unité de dose : « 14 mg », « 2,5 µg », « 1000 UI ».
    private static let motifDose = try? NSRegularExpression(
        pattern: "\\d+(?:[.,]\\d+)?\\s?(?:mg|µg|mcg|ug|UI|IU|g)\\b", options: [.caseInsensitive])

    /// Le texte s'il ne porte aucune dose, sinon rien.
    static func sansDose(_ texte: String) -> String {
        guard let motifDose else { return texte }
        let etendue = NSRange(texte.startIndex..., in: texte)
        return motifDose.firstMatch(in: texte, options: [], range: etendue) == nil ? texte : ""
    }


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
}
