import SwiftUI

// MARK: - Supplements View (onglet « Compléments » — design « v7 »)
//
// L'écran part des APPORTS DU BILAN et descend vers la recommandation : une
// carte REPLIABLE par apport. Les chaînes sont générées depuis le bilan, jamais
// depuis une liste de produits figée : si un apport disparaît du bilan, sa
// carte disparaît.
//
// Divulgation progressive (cf. `SupplementsChainV6.swift`) : la carte repliée
// répond à « qu'est-ce que je prends ? » ; le tap déplie le pourquoi (bleu),
// les précautions (ambre) et la ligne panier. UNE carte ouverte à la fois, la
// première s'ouvre seule au premier affichage. La synthèse « En un coup d'œil »
// ouvre la page ; l'engagement transparence est gros à la première visite de
// l'onglet, puis rétrogradé en ligne de pied de page.
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

    /// Feuille « Ma sélection » (qualité des formes + cases à cocher).
    @State private var showSelection = false
    /// Amorçage fait une seule fois quand les chaînes arrivent : première carte
    /// ouverte (sinon personne ne découvre que ça s'ouvre) + panier pré-rempli
    /// avec le plan proposé (la recommandation EST le plan par défaut).
    @State private var defaultsSeeded = false
    /// L'engagement transparence a déjà été montré en grand une fois.
    @AppStorage("complementsEngagementSeen") private var engagementSeen = false
    /// Cette visite-ci est la première : le bloc reste en grand toute la visite.
    @State private var engagementEnGrand = false

    private var complementsV2: ComplementsV2? { dashboardVM.analysisV2?.complements }

    private var complementsSignature: String {
        (complementsV2?.complements ?? []).compactMap { $0.id }.joined(separator: "|")
    }

    /// Détecte l'arrivée (asynchrone) des chaînes pour amorcer les défauts.
    private var chainsSignature: String {
        chains.map(\.id).joined(separator: "|")
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
                // Refonte 23 août 2026 : fond neutre + voile de marque.
                DSPageBackground()

                if !dashboardVM.bilanComplete {
                    // Mode découverte (V12c) : pas de bilan → la liste serait
                    // vide. À l'emplacement des chaînes : la carte d'exemple
                    // + la porte bilan. Rituel masqué (aucune donnée).
                    discoveryContent
                } else if hasContent {
                    mainContent
                } else if dashboardVM.isLoadingAnalysis {
                    VStack(spacing: 16) {
                        KiwiWalkerView(size: 140)
                        Text("Chargement...")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.dsSecondaire)
                    }
                } else {
                    emptyState
                }
            }
            .kiwiTabBarBottomInset()
            .onAppear {
                refreshRituel()
                seedDefaults()
                // L'engagement transparence ne se « consomme » qu'une fois
                // réellement montré : en découverte (pas de bilan), le bloc
                // n'est pas rendu — on ne brûle pas sa première visite.
                if dashboardVM.bilanComplete, !engagementSeen {
                    engagementSeen = true
                    engagementEnGrand = true
                }
            }
            .onChange(of: complementsSignature) { _, _ in refreshRituel() }
            .onChange(of: chainsSignature) { _, _ in seedDefaults() }
            // Grand titre natif (se replie en inline au défilement). Les
            // Réglages sont un onglet : plus de bouton Profil dans la barre.
            .navigationTitle("Compléments")
            .navigationBarTitleDisplayMode(.large)
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
                // Premium : la fiche observe elle-même SubscriptionService.
                NutrientDetailSheet(nutrient: nutrient)
            }
        }
    }

    // MARK: - Mode découverte (V12c — pas encore de bilan)

    /// L'onglet garde son en-tête et l'emplacement des chaînes ; à la place
    /// des cartes d'apports : la carte d'exemple (`ComplementsTeaserCard`) et
    /// la porte bilan. Ni sélecteur de voie, ni synthèse, ni rituel, ni
    /// engagement : tout ça n'existe qu'adossé à de vraies données. La
    /// mention « ne remplace pas l'avis d'un médecin » reste, elle, posée.
    private var discoveryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.kiwiEntrance(0)
                chainHeader.padding(.top, 20).kiwiEntrance(1)
                ComplementsTeaserCard { dashboardVM.demarrerBilan() }
                    .padding(.top, 12)
                    .kiwiEntrance(2)
                infoCard.padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 16)
            // Même verrou anti-dérive horizontale que mainContent.
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    // MARK: - Contenu principal

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // La bascule pilote toute la page : en tête, contrôle natif.
                ComplementsVoieSwitch(voie: $voie)
                    .padding(.top, 4)
                    .kiwiEntrance(0)

                // Première visite de l'onglet : l'engagement mérite un vrai
                // bloc, une fois. Ensuite il descend en ligne de pied de page.
                if engagementEnGrand {
                    ComplementsEngagementCard().padding(.top, 16).kiwiEntrance(1)
                }

                // Le rituel n'a de sens que dans la voie « compléments ».
                if voie == .complements, let rituel {
                    ComplementsRituelStrip(rituel: rituel) { toggleRituel($0) }
                        .padding(.top, DS.interCarte)
                        .kiwiEntrance(2)
                }

                DSSectionHeader(titre: voie == .complements ? "Recommandés pour toi" : "Par l'assiette")
                    .padding(.top, -4)
                    .kiwiEntrance(3)

                if chains.isEmpty {
                    aiFallbackSection.kiwiEntrance(4)
                } else {
                    VStack(spacing: DS.interCarte) {
                        ForEach(Array(chains.enumerated()), id: \.element.id) { index, chain in
                            carteRefonte(for: chain)
                                .kiwiEntrance(4 + index)
                        }
                    }

                    footerBlock.padding(.top, 16)

                    // Le panier, derrière : une ligne discrète vers la sélection.
                    if voie == .complements, !chiffrableChains.isEmpty {
                        ComplementsSelectionLine(
                            nombre: takenChains.count,
                            totalLabel: "\(cartTotalLabel)\(DS.fine)€"
                        ) {
                            HapticService.shared.tap()
                            showSelection = true
                        }
                    }
                }

                if !engagementEnGrand {
                    ComplementsEngagementLine().padding(.top, 18)
                }
                infoCard.padding(.top, engagementEnGrand ? 18 : 10)
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 4)
            .padding(.bottom, 16)
            // Le contenu fait EXACTEMENT la largeur du conteneur, jamais plus.
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .sheet(isPresented: $showSelection) {
            ComplementsSelectionSheet(
                premium: $premium,
                produits: chiffrableChains.compactMap { chain in
                    guard let rec = chain.rec, let prod = product(for: rec) else { return nil }
                    return ComplementsSelectionSheet.Produit(
                        id: chain.id,
                        nom: prod.name,
                        apport: "\(chain.nom) · \(precisionLabel(for: prod))",
                        prixLabel: priceLabel(for: rec),
                        pris: taken.contains(chain.id)
                    )
                },
                totalLabel: "\(cartTotalLabel)\(DS.fine)€",
                onToggle: { toggleCart($0) }
            )
        }
    }

    // MARK: - Carte d'une chaîne (refonte) : titre, précision, lignes d'action

    /// Voie compléments : le produit à chercher en titre, l'apport + dose +
    /// moment en secondaire, puis « Pourquoi celui-là », « Précautions » et
    /// « Ma sélection ». Voie assiette : l'aliment en titre, l'apport et les
    /// alternatives en secondaire, puis « Pourquoi cet aliment » et la fiche.
    private func carteRefonte(for chain: ComplementChain) -> some View {
        var lignes: [ChainCardRefonte.Ligne] = []
        let titre: String
        let sousTitre: String?
        let symbole: String

        switch voie {
        case .complements:
            let rec = chain.rec
            let prod = rec.flatMap { product(for: $0) }
            symbole = prod == nil ? "fork.knife" : "pills"
            if let prod {
                titre = prod.name
                sousTitre = "\(chain.nom) · \(precisionLabel(for: prod))"
            } else {
                titre = "L'assiette suffit"
                sousTitre = "\(chain.nom) · ton écart est petit"
            }
            if let why = whyExplanation(for: chain, product: prod) {
                lignes.append(.init(id: "why", titre: prod == nil ? "Pourquoi pas de gélule" : "Pourquoi celui-là", vert: true) {
                    HapticService.shared.selection()
                    explanation = why
                })
            }
            if let rec {
                let precautions = SupplementsV4.precautions(for: rec, warnings: engineResult?.warnings ?? [])
                if !precautions.isEmpty {
                    lignes.append(.init(id: "care", titre: "Précautions",
                                        valeur: "\(precautions.count) à connaître") {
                        HapticService.shared.selection()
                        precautionRec = rec
                    })
                }
                if prod != nil {
                    lignes.append(.init(id: "cart", titre: "Ma sélection",
                                        valeur: priceLabel(for: rec),
                                        coche: taken.contains(chain.id)) {
                        toggleCart(chain.id)
                    })
                }
            }
        case .assiette:
            let foods = foodList(for: chain)
            symbole = "fork.knife"
            if let food = foods.first {
                titre = food.label.capitalizedFirstLetter
                let autres = foods.dropFirst().map(\.label)
                sousTitre = autres.isEmpty ? chain.nom : "\(chain.nom) · aussi : \(autres.joined(separator: ", "))"
            } else {
                titre = "Par l'assiette"
                sousTitre = chain.nom
            }
            if let why = foodExplanation(for: chain) {
                lignes.append(.init(id: "why", titre: "Pourquoi cet aliment", vert: true) {
                    HapticService.shared.selection()
                    explanation = why
                })
            }
            if let nutrient = nutrientDetail(for: chain.id) {
                lignes.append(.init(id: "fiche", titre: "Voir la fiche",
                                    valeur: "aliments, quantités, moments") {
                    HapticService.shared.selection()
                    assietteNutrient = nutrient
                })
            }
        }

        return ChainCardRefonte(
            tint: chain.tint,
            symbole: symbole,
            titre: titre,
            sousTitre: sousTitre,
            lignes: lignes,
            accessibilite: "\(chain.nom), \(chain.statutLabel). \(titre). \(sousTitre ?? "")"
        )
    }

    /// Le titre « Compléments » est porté par la barre de navigation (grand
    /// titre natif) ; ici, seule la précision, en 17 secondaire.
    private var header: some View {
        Text(subtitle)
            .font(.dsCorps)
            .tracking(DSTracking.corps)
            .foregroundStyle(Color.dsSecondaire)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        let count = chains.count
        guard count > 0 else { return "Calé sur ton bilan" }
        return "Calé sur \(count == 1 ? "ton apport" : "tes \(count) apports") à renforcer"
    }

    /// Kicker seul : la grande phrase d'explication du v6 doublait ce que
    /// chaque carte repliée dit déjà — un titre de section suffit.
    private var chainHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.dsTexte)
                .accessibilityHidden(true)
            // Titre de section : couleur du domaine (le vert de l'onglet),
            // jamais l'encre neutre, et rangé sous le contenu par sa taille.
            Text(voie == .complements ? "Tes apports → tes compléments"
                                      : "Tes apports → ton assiette")
                .font(Theme.sectionLabelFont)
                .foregroundStyle(Color.dsTexte)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    // MARK: - Chaînes chiffrables

    /// Chaînes avec un produit chiffrable — la synthèse et le panier en dérivent.
    private var chiffrableChains: [ComplementChain] {
        chains.filter { chain in
            guard let rec = chain.rec else { return false }
            return product(for: rec) != nil
        }
    }

    /// « 1000 µg, le matin à jeun » : ce qui complète le produit, sous lui.
    private func precisionLabel(for product: SupplementProduct) -> String {
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
            titre: food.label.capitalizedFirstLetter,
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
    // Voie « compléments » : plus rien ici — le budget vit dans la synthèse
    // « En un coup d'œil », en tête de page.

    @ViewBuilder
    private var footerBlock: some View {
        if voie == .assiette {
            ComplementsAssietteZeroCard()
        }
    }

    // MARK: - Actions

    private func refreshRituel() {
        rituel = SuiviEngineV4.complementsRituel(complements: complementsV2)
    }

    /// Une seule fois, quand les chaînes existent : panier pré-rempli avec
    /// tous les produits recommandés (le total affiché répond d'emblée à
    /// « combien ça me coûte ? » ; décocher retire).
    private func seedDefaults() {
        guard !defaultsSeeded, !chains.isEmpty else { return }
        defaultsSeeded = true
        taken = Set(chiffrableChains.map(\.id))
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
                                    .foregroundStyle(Color.dsAccent)
                                    .accessibilityHidden(true)
                                Text(block.0)
                                    .font(Theme.sectionLabelFont)
                                    .foregroundStyle(Color.dsTexte)
                                Spacer()
                            }
                            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.dsRemplissage)
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "pills.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(Color.dsAccent)
                                    }
                                    .accessibilityHidden(true)
                                    Text(entry.displayText)
                                        .font(Theme.insightFont)
                                        .foregroundStyle(Color.dsTexte)
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
                .foregroundStyle(Color.dsSecondaire)
                .accessibilityHidden(true)
            Text("Ces suggestions viennent de ton bilan. Elles ne remplacent pas l'avis d'un médecin.")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.dsSecondaire)
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
                    .fill(Color.dsRemplissage)
                    .frame(width: 88, height: 88)
                Image(systemName: "pills.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.dsAccent)
            }
            .accessibilityHidden(true)
            Text("Rien à ajouter pour l'instant")
                .font(Theme.conclusionFont)
                .tracking(Theme.conclusionTracking)
                .foregroundStyle(Color.dsTexte)
            Text("Ton bilan ne fait ressortir aucun complément utile. Si tu viens de le remplir, laisse-lui un instant.")
                .font(.system(.subheadline).weight(.medium))
                .lineSpacing(3)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    SupplementsView()
        .environmentObject(DashboardViewModel())
}
