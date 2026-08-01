import SwiftUI

// MARK: - Supplements View (onglet « Compléments » — design « v6 »)
//
// L'écran part des APPORTS DU BILAN et descend vers la recommandation : une
// chaîne visuelle par apport (pastille colorée → rail pointillé → flèche →
// carte). Les 3 chaînes sont générées depuis le bilan, jamais depuis une liste
// de produits figée : si un apport disparaît du bilan, sa chaîne disparaît.
//
// Hiérarchie (cf. `SupplementsChainV6.swift`) : 1. le nutriment · 2. le pourquoi
// (carte bleue) · 3. les précautions (carte ambre) · hors hiérarchie : le panier,
// une ligne de texte discrète — on ne gagne rien sur ces compléments.
//
// Un SEUL sélecteur, figé au-dessus de la tab bar, bascule toute la page entre
// « Compléments » et « Par l'assiette ».
//
// Sources INCHANGÉES : `SupplementEngine` (score, whyText, produits, prix,
// interactions) et le bilan v2 déjà chargé (`AIAnalysisV2`). Aucun nouvel appel.
struct SupplementsView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// Voie affichée — pilote TOUTE la page (chaînes + pied de page + rituel).
    @State private var voie: ComplementsVoie = .complements
    /// Qualité des produits chiffrés dans le budget mensuel.
    @State private var premium = true
    /// Compléments mis au panier (ids de nutriment).
    @State private var taken: Set<String> = []

    /// Explication ouverte en bottom sheet (carte bleue « pourquoi »).
    @State private var explanation: ChainExplanation?
    /// Recommandation dont les précautions sont ouvertes (carte ambre).
    @State private var precautionRec: SupplementRecommendation?
    /// Apport dont la fiche « comment le couvrir par l'assiette » est ouverte.
    @State private var assietteNutrient: EnrichedNutrient?

    /// Rituel du jour — dérivé du bilan v2 de façon déterministe, coche
    /// persistée localement. Aucun appel réseau / IA.
    @State private var rituel: SuiviEngineV4.ComplementsRituel?

    private var complementsV2: ComplementsV2? { dashboardVM.analysisV2?.complements }

    private var complementsSignature: String {
        (complementsV2?.complements ?? []).compactMap { $0.id }.joined(separator: "|")
    }

    // Moteur (scores + profil) — source des produits, prix et interactions.
    private var engineResult: SupplementEngineResult? {
        let scores = dashboardVM.nutrientScores
        guard !scores.isEmpty else { return nil }
        return SupplementEngine.generateRecommendations(scores: scores, profile: dashboardVM.profile)
    }

    private var aiSchedule: SupplementsSchedule? {
        dashboardVM.aiAnalysis?.supplementsSchedule
    }

    private var hasAISchedule: Bool {
        guard let schedule = aiSchedule else { return false }
        return !(schedule.morning ?? []).isEmpty
            || !(schedule.afternoon ?? []).isEmpty
            || !(schedule.evening ?? []).isEmpty
    }

    private var hasContent: Bool { !chains.isEmpty || hasAISchedule }

    // MARK: - Les chaînes (bilan → recommandation)

    /// Une chaîne par apport du bilan v2 (source canonique, exactement 3), jointe
    /// aux recommandations du moteur. Repli : les recommandations seules, quand
    /// le bilan v2 n'est pas encore disponible.
    private var chains: [ComplementChain] {
        let recs = engineResult?.topRecommendations ?? []
        let apports = dashboardVM.analysisV2?.bilan?.apports ?? []

        guard apports.isEmpty else {
            return apports.compactMap { apport in
                guard let id = apport.id, !id.isEmpty else { return nil }
                let rec = recs.first { $0.nutrientID.rawValue == id }
                return ComplementChain(
                    id: id,
                    nom: apport.nom ?? rec?.nutrientLabel ?? id,
                    pct: apport.pctBesoin,
                    statut: apport.statut,
                    symbol: Fluent3D.symbol(for: id),
                    tint: Color.nutrientColor(for: id),
                    rec: rec,
                    apport: apport
                )
            }
        }

        return recs.map { rec in
            ComplementChain(
                id: rec.id,
                nom: rec.nutrientLabel,
                pct: rec.score,
                statut: Self.statut(forScore: rec.score),
                symbol: Fluent3D.symbol(for: rec.nutrientID.rawValue),
                tint: rec.nutrientColor,
                rec: rec,
                apport: nil
            )
        }
    }

    /// Repli de statut quand le bilan v2 n'a pas encore répondu. Mêmes paliers
    /// que le reste de l'app (< 40 à combler, < 70 à renforcer).
    private static func statut(forScore score: Int) -> StatutV2 {
        if score < 40 { return .aCombler }
        if score < 70 { return .aRenforcer }
        return .couvre
    }

    // MARK: - Panier

    /// Chaînes réellement chiffrables et cochées (une chaîne sans produit n'a
    /// pas de ligne panier — cas « plutôt par l'assiette »).
    private var takenChains: [ComplementChain] {
        chains.filter { chain in
            guard let rec = chain.rec, product(for: rec) != nil else { return false }
            return taken.contains(chain.id)
        }
    }

    private var cartTotal: Double {
        takenChains.reduce(0) { total, chain in
            guard let rec = chain.rec else { return total }
            return total + SupplementsV4.monthlyPrice(rec, premium: premium)
        }
    }

    private var cartTotalLabel: String { String(format: "%.0f", cartTotal) }

    private func product(for rec: SupplementRecommendation) -> SupplementProduct? {
        SupplementsV4.product(rec, premium: premium)
    }

    private func priceLabel(for rec: SupplementRecommendation) -> String {
        String(format: "%.0f €", SupplementsV4.monthlyPrice(rec, premium: premium))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()

                if hasContent {
                    mainContent
                } else if dashboardVM.isLoadingAnalysis {
                    VStack(spacing: 16) {
                        KiwiWalkerView(size: 140)
                        Text("Chargement...")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                } else {
                    emptyState
                }
            }
            .kiwiTabBarBottomInset()
            .onAppear { refreshRituel() }
            .onChange(of: complementsSignature) { _, _ in refreshRituel() }
            .navigationBarTitleDisplayMode(.inline)
            .kiwiNavigationBarBackground()
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
            .sheet(item: $explanation) { item in
                ChainExplanationSheet(explanation: item) { explanation = nil }
            }
            .sheet(item: $precautionRec) { rec in
                let warnings = engineResult?.warnings ?? []
                let items = SupplementsV4.precautions(for: rec, warnings: warnings)
                SupplementPrecautionsSheet(rec: rec, items: items, tip: SupplementsV4.tip(for: items))
            }
            // La MÊME fiche que depuis le Bilan : quels aliments couvrent cet
            // apport, en quelle quantité, à quel moment.
            .sheet(item: $assietteNutrient) { nutrient in
                NutrientDetailSheet(
                    nutrient: nutrient,
                    isPremium: SubscriptionService.shared.isPremium
                )
            }
        }
    }

    // MARK: - Contenu principal

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                ComplementsEngagementCard().padding(.top, 14)

                // Le rituel n'a de sens que dans la voie « compléments ».
                if voie == .complements, let rituel {
                    ComplementsRituelStrip(rituel: rituel) { toggleRituel($0) }
                        .padding(.top, 12)
                }

                chainHeader.padding(.top, 22)

                if chains.isEmpty {
                    aiFallbackSection.padding(.top, 14)
                } else {
                    VStack(spacing: 16) {
                        ForEach(chains) { chain in
                            ChainRow(chain: chain) { chainCard(for: chain) }
                        }
                    }
                    .padding(.top, 14)

                    footerBlock.padding(.top, 20)
                }

                infoCard.padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 16)
            // Le contenu fait EXACTEMENT la largeur du conteneur, jamais plus.
            // C'est la seule garantie qui tienne : `scrollBounceBehavior` ne
            // suffit pas, `.basedOnSize` laisse justement rebondir quand le
            // contenu est plus large. Ici un enfant trop large se comprime au
            // lieu d'élargir la zone défilable, donc la page ne peut plus
            // glisser de côté ni laisser voir de marge vide.
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        // Le sélecteur est FIGÉ : `safeAreaInset` réserve sa place, donc le
        // budget mensuel ne passe jamais dessous.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComplementsVoieSwitch(voie: $voie)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Compléments")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(Color.kiwiCharcoal)
            Text(subtitle)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.healthMapMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private var subtitle: String {
        let count = chains.count
        guard count > 0 else { return "Calé sur ton bilan" }
        return "Calé sur \(count == 1 ? "ton apport" : "tes \(count) apports") à renforcer"
    }

    private var chainHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.healthMapMuted)
                    .accessibilityHidden(true)
                Text(voie == .complements ? "Tes apports → tes compléments"
                                          : "Tes apports → ton assiette")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
            Text(voie == .complements
                 ? "Chaque complément répond à un apport détecté dans ton bilan."
                 : "Chaque apport se comble aussi par un aliment précis.")
                .font(.system(size: 16.5, weight: .heavy))
                .tracking(-0.35)
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    // MARK: - Carte au bout de la chaîne (selon la voie)

    @ViewBuilder
    private func chainCard(for chain: ComplementChain) -> some View {
        switch voie {
        case .complements: complementCard(for: chain)
        case .assiette: assietteCard(for: chain)
        }
    }

    // MARK: Voie « compléments »

    @ViewBuilder
    private func complementCard(for chain: ComplementChain) -> some View {
        let rec = chain.rec
        let prod = rec.flatMap { product(for: $0) }

        VStack(alignment: .leading, spacing: 0) {
            // Ligne de tête : visuel + nom / dose · moment + priorité.
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "F4F1EA"))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: prod == nil ? "carrot" : "pills.fill")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(prod == nil ? Color.kiwiGreen : chain.tint)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(prod?.name ?? "Plutôt par l'assiette")
                        .font(.system(size: 13.5, weight: .heavy))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(momentLabel(for: prod, chain: chain))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(prod == nil ? "0 €" : priorityLabel(for: chain))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            // PRIORITÉ 2 — le pourquoi.
            if let why = whyExplanation(for: chain, product: prod) {
                ChainWhyCard(
                    title: prod == nil ? "Pourquoi pas de gélule ?" : "Pourquoi ce format ?",
                    resume: why.resume
                ) {
                    HapticService.shared.selection()
                    explanation = why
                }
                .padding(.top, 11)
            }

            // PRIORITÉ 3 — les précautions.
            if let rec, let care = careSummary(for: rec) {
                ChainCareCard(title: care.title, resume: care.resume) {
                    HapticService.shared.selection()
                    precautionRec = rec
                }
                .padding(.top, 8)
            }

            // Hors hiérarchie — l'acte d'achat, discret.
            if let rec, prod != nil {
                ChainCartLine(
                    priceLabel: priceLabel(for: rec),
                    taken: taken.contains(chain.id)
                ) {
                    toggleCart(chain.id)
                }
            }
        }
    }

    /// « 1000 µg, le matin à jeun ». Sans produit, on explique pourquoi.
    private func momentLabel(for product: SupplementProduct?, chain: ComplementChain) -> String {
        guard let product else {
            return "Ton écart est petit, l'assiette suffit"
        }
        let dosage = product.dosage.trimmingCharacters(in: .whitespaces)
        let moment = momentPhrase(product.timing)
        guard !dosage.isEmpty else { return moment.capitalizedFirstLetter }
        return "\(dosage), \(moment)"
    }

    /// Formulation parlée du moment de prise. `TimingSlot.label` est écrit sans
    /// accents et sur un ton d'étiquette (« Soir avec diner ») ; ici on
    /// s'adresse à quelqu'un.
    private func momentPhrase(_ slot: TimingSlot) -> String {
        switch slot {
        case .matinAJeun: return "le matin à jeun"
        case .matinRepas: return "le matin au petit-déjeuner"
        case .midiRepas: return "le midi, pendant le repas"
        case .soirRepas: return "le soir, pendant le dîner"
        case .coucher: return "au coucher"
        case .entreRepas: return "entre deux repas"
        }
    }

    /// Priorité affichée en petit texte gris (jamais un badge criard).
    private func priorityLabel(for chain: ComplementChain) -> String {
        switch chain.statut {
        case .aCombler: return "essentiel"
        case .aRenforcer: return "utile"
        default: return "confort"
        }
    }

    // MARK: Voie « par l'assiette »

    @ViewBuilder
    private func assietteCard(for chain: ComplementChain) -> some View {
        let foods = foodList(for: chain)

        VStack(alignment: .leading, spacing: 0) {
            if let first = foods.first {
                Button {
                    HapticService.shared.selection()
                    assietteNutrient = nutrientDetail(for: chain.id)
                } label: {
                    HStack(spacing: 11) {
                        SafeFluent3DIcon(name: first.icon, size: 38)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(first.label)
                                .font(.system(size: 13.5, weight: .heavy))
                                .foregroundStyle(Color.kiwiCharcoal)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Couvre ton apport en \(chain.nom.lowercased())")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.kiwiGreenInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.healthMapMuted)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
                .accessibilityHint("Ouvre la fiche de l'apport : aliments, quantités, moments")
            }

            // PRIORITÉ 2 — le pourquoi (texte réel du bilan, jamais inventé).
            if let why = foodExplanation(for: chain) {
                ChainWhyCard(title: "Pourquoi cet aliment ?", resume: why.resume) {
                    HapticService.shared.selection()
                    explanation = why
                }
                .padding(.top, 11)
            }

            // Les alternatives, en une ligne discrète.
            if foods.count > 1 {
                HStack(spacing: 7) {
                    SafeFluent3DIcon(name: foods[1].icon, size: 22)
                        .accessibilityHidden(true)
                    Text("Aussi : " + foods.dropFirst().map(\.label).joined(separator: ", "))
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineSpacing(2)
                        .foregroundStyle(Color.healthMapSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 11)
            }
        }
    }

    private struct ChainFood {
        let icon: String?
        let label: String
    }

    /// Aliments de l'apport : ceux du bilan v2 (personnalisés) en priorité,
    /// sinon les sources canoniques du catalogue. Aucune donnée inventée.
    private func foodList(for chain: ComplementChain) -> [ChainFood] {
        if let aliments = chain.apport?.aliments, !aliments.isEmpty {
            return aliments.compactMap { aliment in
                guard let nom = aliment.nom, !nom.isEmpty else { return nil }
                return ChainFood(icon: aliment.icone, label: nom)
            }
        }
        return Fluent3D.foodSources(for: chain.id).map {
            ChainFood(icon: $0.asset, label: $0.label)
        }
    }

    // MARK: - Explications

    /// « Pourquoi ce format ? » — construit sur le texte du catalogue (la forme
    /// choisie) et la raison causale du moteur. Sans produit : pourquoi l'assiette
    /// suffit, expliqué par le bilan.
    private func whyExplanation(for chain: ComplementChain, product: SupplementProduct?) -> ChainExplanation? {
        guard let product else {
            guard let why = chain.apport?.why, !why.isEmpty else { return nil }
            return ChainExplanation(
                id: "\(chain.id)-nopill",
                kind: .why,
                kicker: "POURQUOI PAS DE GÉLULE",
                titre: "L'assiette suffit pour cet apport",
                resume: "Ton écart est petit, l'alimentation le comble seule.",
                body: KiwiProse.lisible(why),
                practice: practiceText(for: chain)
            )
        }

        let brand = KiwiProse.lisible(product.whyBrand)
        let causal = KiwiProse.lisible(chain.rec?.whyText ?? "")
        let body = [causal, brand].filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !body.isEmpty else { return nil }

        return ChainExplanation(
            id: "\(chain.id)-why",
            kind: .why,
            kicker: "POURQUOI CE FORMAT",
            titre: product.name,
            resume: firstSentence(brand.isEmpty ? causal : brand),
            body: body,
            practice: "\(product.dosage), \(momentPhrase(product.timing))."
        )
    }

    /// « Pourquoi cet aliment ? » — uniquement du texte réel du bilan.
    private func foodExplanation(for chain: ComplementChain) -> ChainExplanation? {
        guard let apport = chain.apport,
              let why = apport.why, !why.isEmpty,
              let food = foodList(for: chain).first else { return nil }
        return ChainExplanation(
            id: "\(chain.id)-food",
            kind: .why,
            kicker: "POURQUOI CET ALIMENT",
            titre: food.label,
            resume: firstSentence(KiwiProse.lisible(why)),
            body: KiwiProse.lisible(why),
            practice: practiceText(for: chain)
        )
    }

    /// Bloc « EN PRATIQUE » du bilan (conseil court + suite), sans rien inventer.
    private func practiceText(for chain: ComplementChain) -> String {
        let bold = KiwiProse.lisible(chain.apport?.tipBold ?? "")
        let rest = KiwiProse.lisible(chain.apport?.tipRest ?? "")
        return [bold, rest].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Résumé de la carte ambre : combien d'interactions, et laquelle en premier.
    private func careSummary(for rec: SupplementRecommendation) -> (title: String, resume: String)? {
        let items = SupplementsV4.precautions(for: rec, warnings: engineResult?.warnings ?? [])
        guard let first = items.first else { return nil }
        let title = items.count > 1
            ? "\(items.count) précautions à connaître"
            : "1 précaution à connaître"
        return (title, firstSentence(first.note.isEmpty ? first.title : first.note))
    }

    /// Accroche de carte : la première phrase, plafonnée. La carte n'a la place
    /// que d'une accroche, pas d'un paragraphe ; on coupe sur un mot entier.
    private func firstSentence(_ text: String, limite: Int = 90) -> String {
        let propre = KiwiProse.lisible(text)
        let phrase = propre.firstIndex(of: ".").map { String(propre[...$0]) } ?? propre
        guard phrase.count > limite else { return phrase }
        let coupe = phrase.prefix(limite)
        guard let espace = coupe.lastIndex(of: " ") else { return String(coupe) + "…" }
        return String(coupe[..<espace]) + "…"
    }

    // MARK: - Pied de page (selon la voie)

    @ViewBuilder
    private var footerBlock: some View {
        switch voie {
        case .complements:
            ComplementsBudgetCard(
                premium: $premium,
                count: takenChains.count,
                totalLabel: cartTotalLabel
            )
        case .assiette:
            ComplementsAssietteZeroCard()
        }
    }

    // MARK: - Actions

    private func refreshRituel() {
        rituel = SuiviEngineV4.complementsRituel(complements: complementsV2)
    }

    private func toggleRituel(_ id: String) {
        HapticService.shared.selection()
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) {
            rituel = SuiviEngineV4.toggleRituel(id: id, complements: complementsV2)
        }
    }

    private func toggleCart(_ id: String) {
        HapticService.shared.selection()
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) {
            if taken.contains(id) { taken.remove(id) } else { taken.insert(id) }
        }
    }

    /// Fiche détaillée de l'apport, si l'analyse l'a produite. `nil` → on
    /// n'ouvre rien plutôt que d'afficher une coquille.
    private func nutrientDetail(for id: String) -> EnrichedNutrient? {
        dashboardVM.nutrients.first { $0.id == id }
    }

    // MARK: - Repli planning IA (rare : moteur vide mais analyse présente)

    @ViewBuilder
    private var aiFallbackSection: some View {
        if let schedule = aiSchedule {
            let blocks: [(String, String, [SupplementEntry])] = [
                ("Matin", "sunrise.fill", schedule.morning ?? []),
                ("Midi", "sun.max.fill", schedule.afternoon ?? []),
                ("Soir", "moon.fill", schedule.evening ?? []),
            ]
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    let entries = block.2
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: block.1)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.kiwiGreen)
                                    .accessibilityHidden(true)
                                Text(block.0)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.kiwiCharcoal)
                                Spacer()
                            }
                            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.kiwiGreenSoft)
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "pills.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(Color.kiwiGreen)
                                    }
                                    .accessibilityHidden(true)
                                    Text(entry.displayText)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.kiwiCharcoal)
                                    Spacer()
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .kiwiCard(radius: 20)
                    }
                }
            }
        }
    }

    // MARK: - Disclaimer

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapMuted)
                .accessibilityHidden(true)
            Text("Ces suggestions viennent de ton bilan. Elles ne remplacent pas l'avis d'un médecin.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.healthMapMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - État vide

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.kiwiGreenSoft)
                    .frame(width: 88, height: 88)
                Image(systemName: "pills.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.kiwiGreen)
            }
            .accessibilityHidden(true)
            Text("Rien à ajouter pour l'instant")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
            Text("Ton bilan ne fait ressortir aucun complément utile. Si tu viens de le remplir, laisse-lui un instant.")
                .font(.system(size: 14, weight: .medium))
                .lineSpacing(3)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    SupplementsView()
        .environmentObject(DashboardViewModel())
}
