import SwiftUI

// MARK: - Supplements View (onglet « Compléments » — l'anneau de cause)
//
// Maquette « Compléments anneau de cause » (20 septembre 2026). L'écran part
// des APPORTS DU BILAN : une tuile par apport, jamais une liste de produits
// figée — si un apport disparaît du bilan, sa tuile disparaît.
//
//   • le rituel du jour en tête : c'est l'action quotidienne ;
//   • la bascule Compléments / Par l'assiette, qui pilote toute la page ;
//   • la mosaïque : un héros pleine largeur (l'anneau et ses freins nommés),
//     puis des tuiles deux par deux. Ni dose, ni prix, ni marque sur une tuile ;
//   • la fiche, au toucher : six blocs, dont la cascade du calcul.
//
// Le chiffre affiché est le SCORE DÉTERMINISTE du registre
// (`HealthCalculator.registreApports`) : le seul dont les parts de l'anneau
// ferment à 100 et dont on sait montrer le calcul ligne à ligne. Le pourcentage
// rédigé par le bilan (`ApportV2.pctBesoin`) n'est plus affiché ici — il ne
// sert que de dernier repli quand aucun score local n'existe.
//
// Sources INCHANGÉES : `SupplementEngine` (produits, prix, interactions) et le
// bilan v2 déjà chargé (`AIAnalysisV2`). Aucun nouvel appel.
struct SupplementsView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Voie affichée — pilote TOUTE la page (mosaïque + fiche + note de pied).
    @State private var voie: ComplementsVoie = .complements
    /// Qualité des produits chiffrés dans le budget mensuel.
    @State private var premium = true
    /// Compléments mis au panier (ids de nutriment).
    @State private var taken: Set<String> = []

    /// Fiche ouverte au toucher d'une tuile.
    @State private var fiche: FicheApportContexte?

    /// Rituel du jour — dérivé du bilan v2 de façon déterministe, coche
    /// persistée localement. Aucun appel réseau / IA.
    @State private var rituel: SuiviEngineV4.ComplementsRituel?

    /// Feuille « Ma sélection » (qualité des formes + cases à cocher).
    @State private var showSelection = false
    /// Amorçage fait une seule fois quand les chaînes arrivent : panier
    /// pré-rempli avec le plan proposé (la recommandation EST le plan par défaut).
    @State private var defaultsSeeded = false

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
                symbol: Fluent3D.symbol(for: rec.nutrientID.rawValue),
                tint: rec.nutrientColor,
                rec: rec,
                apport: nil
            )
        }
    }

    // MARK: - Les tuiles (chaîne + détail du registre)

    /// Une tuile prête à dessiner : la chaîne, et le calcul de son apport.
    private struct Tuile: Identifiable {
        let chain: ComplementChain
        let detail: DetailApport
        var id: String { chain.id }
    }

    /// Le registre donne le score ET ses facteurs nommés. Quand il se tait
    /// (profil hors bornes), on garde le score connu, sans facteur nommé :
    /// l'anneau se réduit à « couvert » + « autres facteurs ». Sans aucun
    /// score, pas de tuile — on n'affiche pas un zéro inventé.
    private var tuiles: [Tuile] {
        let registre = HealthCalculator.registreApports(profile: dashboardVM.profile)
        return chains.compactMap { chain -> Tuile? in
            if let detail = registre[chain.id] {
                return Tuile(chain: chain, detail: detail)
            }
            guard let score = dashboardVM.nutrientScores[chain.id]
                    ?? chain.rec?.score
                    ?? chain.apport?.pctBesoin else { return nil }
            return Tuile(chain: chain, detail: DetailApport(contributions: [], score: max(0, min(100, score))))
        }
    }

    // MARK: - Panier

    /// Chaînes avec un produit chiffrable — le panier en dérive.
    private var chiffrableChains: [ComplementChain] {
        chains.filter { chain in
            guard let rec = chain.rec else { return false }
            return product(for: rec) != nil
        }
    }

    /// Chaînes chiffrables ET cochées.
    private var takenChains: [ComplementChain] {
        chiffrableChains.filter { taken.contains($0.id) }
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
                DSPageBackground()

                if !dashboardVM.bilanComplete {
                    // Mode découverte (V12c) : pas de bilan → la mosaïque serait
                    // vide. À sa place : la carte d'exemple + la porte bilan.
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
            }
            .onChange(of: complementsSignature) { _, _ in refreshRituel() }
            .onChange(of: chainsSignature) { _, _ in seedDefaults() }
            // Grand titre natif (se replie en inline au défilement).
            .navigationTitle("Compléments")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $fiche) { contexte in
                FicheApportSheet(
                    contexte: contexte,
                    nutrimentDetail: nutrientDetail(for: contexte.id),
                    surAlternative: { basculerVoie() }
                )
            }
        }
    }

    // MARK: - Mode découverte (V12c — pas encore de bilan)

    /// L'onglet garde son en-tête et l'emplacement de la mosaïque ; à sa
    /// place : la carte d'exemple (`ComplementsTeaserCard`) et la porte bilan.
    /// Ni bascule, ni rituel : tout ça n'existe qu'adossé à de vraies données.
    /// La mention « ne remplace pas l'avis d'un médecin » reste, elle, posée.
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
            .padding(.horizontal, DS.marge)
            .padding(.top, 4)
            .padding(.bottom, 16)
            // Même verrou anti-dérive horizontale que mainContent.
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    // MARK: - Contenu principal

    private var mainContent: some View {
        let items = tuiles
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.kiwiEntrance(0)

                // Le rituel reste en tête dans les deux voies : c'est l'action
                // du jour, et la bascule ne doit pas sauter sous le doigt.
                if let rituel {
                    ComplementsRituelStrip(rituel: rituel) { toggleRituel($0) }
                        .padding(.top, 14)
                        .kiwiEntrance(1)
                }

                ComplementsVoieSwitch(voie: $voie)
                    .padding(.top, 18)
                    .kiwiEntrance(2)

                if items.isEmpty {
                    aiFallbackSection
                        .padding(.top, 18)
                        .kiwiEntrance(3)
                } else {
                    enTeteMosaique(nombre: items.count).kiwiEntrance(3)

                    mosaique(items).padding(.top, 11)

                    Text(noteMosaique(items))
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .padding(.horizontal, 2)

                    // Le panier, derrière : une ligne discrète vers la sélection.
                    if voie == .complements, !chiffrableChains.isEmpty {
                        ComplementsSelectionLine(
                            nombre: takenChains.count,
                            totalLabel: "\(cartTotalLabel)\(DS.fine)€"
                        ) {
                            HapticService.shared.tap()
                            showSelection = true
                        }
                        .padding(.top, 6)
                    }
                }

                infoCard.padding(.top, 18)
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

    // MARK: - En-têtes

    /// Le titre « Compléments » est porté par la barre de navigation (grand
    /// titre natif) ; ici, l'engagement de transparence, en secondaire.
    private var header: some View {
        Text("Kiwio ne gagne rien sur ce qu'il te recommande")
            .font(.dsSousTitre)
            .tracking(DSTracking.sousTitre)
            .foregroundStyle(Color.dsSecondaire)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Kicker de la carte d'exemple (mode découverte).
    private var chainHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.dsTexte)
                .accessibilityHidden(true)
            Text("Tes apports → tes compléments")
                .font(Theme.sectionLabelFont)
                .foregroundStyle(Color.dsTexte)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func enTeteMosaique(nombre: Int) -> some View {
        let unite = voie == .complements ? "apport" : "aliment"
        return HStack(alignment: .firstTextBaseline) {
            Text(voie == .complements ? "Recommandés pour toi" : "Par l'assiette")
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text("\(nombre) \(unite)\(nombre > 1 ? "s" : "")")
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
        }
        .padding(.top, 18)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - La mosaïque (1 héros, puis deux par deux)

    /// Trois apports : un héros et une rangée de deux. Deux apports : un héros
    /// et une tuile pleine largeur, en ligne. Un seul : le héros. Jamais de trou.
    private func mosaique(_ items: [Tuile]) -> some View {
        let reste = Array(items.dropFirst())
        let rangs = Array(stride(from: 0, to: reste.count, by: 2))
        return VStack(spacing: 10) {
            if let premier = items.first {
                heros(premier).kiwiEntrance(4)
            }
            ForEach(rangs, id: \.self) { rang in
                if rang + 1 < reste.count {
                    HStack(alignment: .top, spacing: 10) {
                        tuile(reste[rang])
                        tuile(reste[rang + 1])
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .kiwiEntrance(5 + rang / 2)
                } else {
                    tuile(reste[rang], enLigne: true)
                        .kiwiEntrance(5 + rang / 2)
                }
            }
        }
    }

    private func heros(_ item: Tuile) -> some View {
        TuileApportHero(
            nom: titre(item),
            symbole: symbole(item),
            couleur: item.chain.tint,
            statutLigne: statutLigne(item, complet: true),
            parts: item.detail.parts,
            score: item.detail.score,
            lignes: lignesHeros(item),
            cta: ctaHeros(item)
        ) { ouvrir(item) }
    }

    private func tuile(_ item: Tuile, enLigne: Bool = false) -> some View {
        TuileApport(
            nom: titre(item),
            symbole: symbole(item),
            couleur: item.chain.tint,
            statutLigne: statutLigne(item, complet: false),
            parts: item.detail.parts,
            score: item.detail.score,
            enLigne: enLigne
        ) { ouvrir(item) }
    }

    /// Voie compléments : l'apport. Voie assiette : le premier aliment qui le couvre.
    private func titre(_ item: Tuile) -> String {
        guard voie == .assiette, let aliment = aliments(for: item.chain).first else {
            return item.chain.nom
        }
        return aliment.capitalizedFirstLetter
    }

    private func symbole(_ item: Tuile) -> String {
        voie == .assiette ? "fork.knife" : item.chain.symbol
    }

    /// « à combler · 3 causes » sur une tuile, « … causes nommées » sur le
    /// héros ; en voie assiette, l'apport que l'aliment sert.
    private func statutLigne(_ item: Tuile, complet: Bool) -> String {
        guard voie == .complements else { return "pour \(item.chain.avecArticle)" }
        let mot = FicheApportContexte.statutMot(forScore: item.detail.score)
        let causes = item.detail.freins.count
        switch causes {
        case 0: return "\(mot) · sans cause nommée"
        case 1: return "\(mot) · 1 cause\(complet ? " nommée" : "")"
        default: return "\(mot) · \(causes) causes\(complet ? " nommées" : "")"
        }
    }

    /// Les trois freins les plus lourds, puis le premier appui : au-delà, la
    /// carte deviendrait la fiche. Le compte exact reste dans la ligne de statut.
    private func lignesHeros(_ item: Tuile) -> [LigneCauseTuile] {
        let freins = item.detail.freins.prefix(3).enumerated().map { rang, frein in
            LigneCauseTuile(id: frein.id, libelle: frein.libelle, delta: frein.delta, teinte: AnneauTeintes.cause(rang: rang))
        }
        let appuis = item.detail.appuis.prefix(1).map { appui in
            LigneCauseTuile(id: appui.id, libelle: appui.libelle, delta: appui.delta, teinte: item.chain.tint)
        }
        return freins + appuis
    }

    private func ctaHeros(_ item: Tuile) -> String {
        if voie == .assiette { return "Comment l'intégrer" }
        return item.detail.contributions.isEmpty ? "Voir la fiche" : "Voir le calcul"
    }

    private func noteMosaique(_ items: [Tuile]) -> String {
        if voie == .assiette {
            return "Aucun aliment ne se compte en pourcentage : c'est la régularité qui remonte un apport."
        }
        return items.contains { !$0.detail.freins.isEmpty }
            ? "Le creux de l'anneau, ce sont tes réponses. Touche un apport pour voir le calcul."
            : "Touche un apport pour voir comment le renforcer."
    }

    // MARK: - La fiche (contexte assemblé depuis les sources existantes)

    private func ouvrir(_ item: Tuile) {
        HapticService.shared.selection()
        fiche = contexte(for: item)
    }

    private func contexte(for item: Tuile) -> FicheApportContexte {
        let chain = item.chain
        let produit = chain.rec.flatMap { product(for: $0) }
        let aliments = aliments(for: chain)
        let enAssiette = voie == .assiette

        let specs: [FicheApportContexte.Spec]
        let note: String?
        let precautions: [SupplementPrecaution]
        let alternatives: [FicheApportContexte.Alternative]
        let cta: String?

        if enAssiette {
            // Pas de portion ni de pourcentage par aliment : la donnée n'existe
            // pas. On donne les autres aliments et le conseil rédigé du bilan ;
            // quantités et moments vivent dans la fiche existante, liée depuis ici.
            let autres = aliments.dropFirst().map(\.capitalizedFirstLetter)
            specs = autres.isEmpty
                ? []
                : [FicheApportContexte.Spec(cle: "aussi", valeur: autres.joined(separator: ", "))]
            let pratique = practiceText(for: chain)
            let pourquoi = KiwiProse.lisible(chain.apport?.why ?? "")
            note = [pratique, pourquoi].first { !$0.isEmpty }
            precautions = []
            if let produit {
                alternatives = [FicheApportContexte.Alternative(
                    id: produit.id,
                    symbole: "pills",
                    nom: produit.name,
                    sousTitre: precisionLabel(for: produit)
                )]
                cta = "Voir le complément"
            } else {
                alternatives = []
                cta = nil
            }
        } else {
            if let produit {
                // La forme et le moment, jamais la dose : on conseille le
                // complément, la posologie appartient au fabricant et à la
                // personne (doctrine du 20 septembre 2026). La maquette prévoyait
                // une colonne « dose » : elle n'est pas reprise.
                specs = [
                    FicheApportContexte.Spec(cle: "forme", valeur: produit.name),
                    FicheApportContexte.Spec(cle: "prise", valeur: precisionLabel(for: produit)),
                ]
                // Pourquoi CETTE forme. Le « pourquoi toi » du moteur n'est pas
                // repris ici : la cascade (bloc 02) et l'éclairage (bloc 01) le
                // disent déjà, et il porte la même phrase sur les symptômes.
                let forme = KiwiProse.lisible(produit.whyBrand)
                note = forme.isEmpty ? nil : forme
            } else {
                specs = []
                note = "Ton écart est petit : l'alimentation le comble seule, sans gélule."
            }
            precautions = chain.rec.map {
                SupplementsV4.precautions(for: $0, warnings: engineResult?.warnings ?? [])
            } ?? []
            alternatives = aliments.map {
                FicheApportContexte.Alternative(id: $0, symbole: "fork.knife", nom: $0.capitalizedFirstLetter, sousTitre: nil)
            }
            cta = "Voir la voie par l'assiette"
        }

        return FicheApportContexte(
            id: chain.id,
            voie: enAssiette ? .assiette : .complements,
            titre: titre(item),
            apportAvecArticle: chain.avecArticle,
            symbole: symbole(item),
            couleur: chain.tint,
            statutMot: FicheApportContexte.statutMot(forScore: item.detail.score),
            detail: item.detail,
            eclairage: eclairage(for: chain.id),
            role: ApportRole.role(for: chain.id),
            specs: specs,
            noteDePrise: note,
            precautions: precautions,
            conseilPrecautions: precautions.isEmpty ? nil : SupplementsV4.tip(for: precautions),
            alternatives: alternatives,
            ctaAlternative: cta
        )
    }

    /// Ce que les symptômes déclarés permettent d'éclairer sur cet apport bas,
    /// d'après la table déterministe `SymptomesApports` — jamais le texte libre
    /// du bilan. Le score a déjà décidé ; la phrase explique, et se tait quand
    /// rien de solide ne se dit.
    private func eclairage(for id: String) -> String? {
        guard let nutriment = NutrientID(rawValue: id) else { return nil }
        return SymptomesApports.explication(pour: nutriment, symptomes: dashboardVM.profile.symptoms)
    }

    /// « Le matin à jeun » : ce qui complète le produit, sous lui.
    ///
    /// La dose n'y figure plus (20 septembre 2026) : on conseille le
    /// complément, la posologie appartient au fabricant et à la personne. Le
    /// moment reste — ce n'est pas une posologie mais un conseil d'absorption.
    private func precisionLabel(for product: SupplementProduct) -> String {
        momentPhrase(product.timing).capitalizedFirstLetter
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

    /// Aliments de l'apport : ceux du bilan v2 (personnalisés) en priorité,
    /// sinon les sources canoniques du catalogue. Aucune donnée inventée.
    private func aliments(for chain: ComplementChain) -> [String] {
        if let aliments = chain.apport?.aliments, !aliments.isEmpty {
            return aliments.compactMap { aliment -> String? in
                guard let nom = aliment.nom, !nom.isEmpty else { return nil }
                return nom
            }
        }
        return Fluent3D.foodSources(for: chain.id).map(\.label)
    }

    /// Bloc « en pratique » du bilan (conseil court + suite), sans rien inventer.
    private func practiceText(for chain: ComplementChain) -> String {
        let bold = KiwiProse.lisible(chain.apport?.tipBold ?? "")
        let rest = KiwiProse.lisible(chain.apport?.tipRest ?? "")
        return [bold, rest].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Fiche détaillée de l'apport (aliments, quantités, moments), si l'analyse
    /// l'a produite. `nil` → la fiche ne propose pas le lien.
    private func nutrientDetail(for id: String) -> EnrichedNutrient? {
        dashboardVM.nutrients.first { $0.id == id }
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

    /// Le lien de fin de fiche : on referme, et la page passe sur l'autre voie.
    private func basculerVoie() {
        fiche = nil
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.18)) {
            voie = voie == .complements ? .assiette : .complements
        }
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
