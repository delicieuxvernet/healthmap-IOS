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
//   • la fiche, au toucher : la tête, ce qui pèse, ce que tu peux faire,
//     puis la prise, les précautions, l'autre voie et le calcul replié.
//
// Le chiffre affiché est le SCORE DÉTERMINISTE du registre
// (`HealthCalculator.registreApports`) : le seul dont les parts de l'anneau
// ferment à 100 et dont on sait montrer le calcul ligne à ligne. Le pourcentage
// rédigé par le bilan (`ApportV2.pctBesoin`) n'est plus affiché ici — il ne
// sert que de dernier repli quand aucun score local n'existe.
//
// Sources INCHANGÉES : `SupplementEngine` (produits, prix, interactions) et le
// bilan v2 déjà chargé (`AIAnalysisV2`). Aucun nouvel appel.
//
// Verre liquide (2 octobre 2026) : le titre devient une ligne de 17 / 600 qui
// défile avec la page (la barre de navigation est masquée, le bord haut flouté
// de la racine fait le reste), la bascule est en verre, la voie assiette une
// seule carte de lignes. À chaque arrivée sur l'onglet et à chaque bascule,
// les anneaux se retracent et les causes reviennent en cascade.
struct SupplementsView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Les onglets restent montés : c'est ce signal, pas `onAppear`, qui dit
    /// qu'on vient d'arriver sur la page.
    @Environment(\.estOngletActif) private var estOngletActif

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
    /// Compte les arrivées sur l'onglet : la mosaïque est reconstruite à
    /// chacune, donc ses anneaux et ses cascades se rejouent.
    @State private var passage = 0
    /// Rythme du retracé des anneaux : la maquette ne le joue pas à la même
    /// vitesse à l'arrivée sur l'onglet (1,1 s) et au retour par la bascule
    /// (0,9 s). Posé AVANT le changement qui reconstruit la mosaïque.
    @State private var cadenceAnneaux: AnneauDeCause.Cadence = .ongletArrivee

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
        return SupplementEngine.generateRecommendations(scores: scores, profile: dashboardVM.profile,
                                                        statuts: dashboardVM.statuts)
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
        let registre = dashboardVM.registre
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
                    sousLeTitre {
                        VStack(spacing: 16) {
                            KiwiLoader(size: 72)
                            Text("Chargement...")
                                .font(.dsSousTitreMoyen)
                                .foregroundStyle(Color.dsSecondaire)
                        }
                    }
                } else {
                    sousLeTitre { emptyState }
                }
            }
            .kiwiTabBarBottomInset()
            .onAppear {
                refreshRituel()
                seedDefaults()
            }
            .onChange(of: estOngletActif) { _, actif in
                guard actif else { return }
                cadenceAnneaux = .ongletArrivee
                passage += 1
            }
            .onChange(of: complementsSignature) { _, _ in refreshRituel() }
            // Le rituel a été coché depuis un widget : les coches se relisent.
            .onReceive(NotificationCenter.default.publisher(for: .healthmapRituelModifie)) { _ in
                refreshRituel()
            }
            .onChange(of: chainsSignature) { _, _ in seedDefaults() }
            // Le titre est une ligne de la page (17 / 600, voir `titreOnglet`) :
            // la barre native poserait son propre fond flou par-dessus le verre.
            .navigationTitle("Compléments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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
                chainHeader.padding(.top, 22).kiwiEntrance(1)
                ComplementsTeaserCard { dashboardVM.demarrerBilan() }
                    .padding(.top, 12)
                    .kiwiEntrance(2)
                infoCard.padding(.top, 18)
            }
            .padding(.horizontal, DS.marge)
            // Ligne de titre à 54 pt du haut, comme la maquette (la zone sûre
            // en fait 59).
            .padding(.top, -5)
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
                // L'en-tête, le rituel et la bascule sont posés d'emblée :
                // dans la maquette, seuls les anneaux et les causes se rejouent.
                header

                // Le rituel reste en tête dans les deux voies : c'est l'action
                // du jour, et la bascule ne doit pas sauter sous le doigt.
                if let rituel {
                    ComplementsRituelStrip(rituel: rituel) { toggleRituel($0) }
                        .padding(.top, 12)
                }

                ComplementsVoieSwitch(voie: voieParLaBascule)
                    .padding(.top, 16)

                if items.isEmpty {
                    aiFallbackSection
                        .padding(.top, 18)
                } else {
                    enTeteMosaique(nombre: items.count)

                    // Reconstruit à chaque bascule et à chaque arrivée sur
                    // l'onglet : les anneaux se retracent part par part, les
                    // causes et les lignes reviennent en cascade.
                    corps(items)
                        .id("\(voie.rawValue)#\(passage)")
                        .modifier(EchangeDuCorps(cle: voie))
                        .padding(.top, 12)

                    Text(noteMosaique(items))
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
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
            // Ligne de titre à 54 pt du haut, comme la maquette (la zone sûre
            // en fait 59).
            .padding(.top, -5)
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

    /// La bascule passe par ici : le rythme du retracé est posé avant que
    /// la voie change (et donc avant que la mosaïque se reconstruise).
    private var voieParLaBascule: Binding<ComplementsVoie> {
        Binding(
            get: { voie },
            set: { nouvelle in
                cadenceAnneaux = .bascule
                voie = nouvelle
            }
        )
    }

    // MARK: - En-têtes

    /// Le titre de l'onglet : une ligne de 17 / 600 centrée, haute de 44,
    /// qui défile avec la page.
    private var titreOnglet: some View {
        Text("Compléments")
            .font(.dsTitreInline)
            .tracking(DSTracking.corps)
            .foregroundStyle(Color.dsTexte)
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .center)
            .accessibilityAddTraits(.isHeader)
    }

    /// Le titre, puis l'engagement de transparence, en secondaire.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            titreOnglet
            Text("Kiwio ne gagne rien sur ce qu'il te recommande")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Un état sans liste (chargement, rien à proposer) : le titre reste en
    /// haut, le contenu se centre dans ce qui reste.
    private func sousLeTitre<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(spacing: 0) {
            titreOnglet
                .padding(.horizontal, DS.marge)
                .padding(.top, -5)
            Spacer(minLength: 0)
            contenu()
            Spacer(minLength: 0)
        }
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

    /// Le même dans les deux voies : la maquette le pose hors du corps qui
    /// bascule. `nombre` compte des apports, quelle que soit la voie.
    private func enTeteMosaique(nombre: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Recommandés pour toi")
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text("\(nombre) apport\(nombre > 1 ? "s" : "")")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .contentTransition(.numericText())
        }
        .padding(.top, 22)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Le corps (mosaïque d'anneaux, ou lignes de l'assiette)

    /// Voie compléments : la mosaïque. Voie assiette : une seule carte, une
    /// ligne par apport.
    @ViewBuilder
    private func corps(_ items: [Tuile]) -> some View {
        if voie == .complements {
            mosaique(items)
        } else {
            ComplementsAssietteCarte(lignes: lignesAssiette(items)) { id in
                guard let item = items.first(where: { $0.id == id }) else { return }
                ouvrir(item)
            }
        }
    }

    /// Trois apports : un héros et une rangée de deux. Deux apports : un héros
    /// et une tuile pleine largeur, en ligne. Un seul : le héros. Jamais de trou.
    private func mosaique(_ items: [Tuile]) -> some View {
        let reste = Array(items.dropFirst())
        let rangs = Array(stride(from: 0, to: reste.count, by: 2))
        return VStack(spacing: 10) {
            if let premier = items.first {
                heros(premier)
            }
            ForEach(rangs, id: \.self) { rang in
                if rang + 1 < reste.count {
                    HStack(alignment: .top, spacing: 10) {
                        tuile(reste[rang])
                        tuile(reste[rang + 1])
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    tuile(reste[rang], enLigne: true)
                }
            }
        }
    }

    /// Une ligne par apport : son premier aliment en titre (le même que celui
    /// de sa fiche), les suivants en précision. Sans autre aliment, la ligne
    /// dit l'apport qu'elle sert. Ni portion ni fréquence : la donnée n'existe
    /// pas par aliment.
    private func lignesAssiette(_ items: [Tuile]) -> [LigneAssiette] {
        items.map { item in
            let autres = aliments(for: item.chain).dropFirst().map { LectureApport.enCoursDePhrase($0) }
            let precision = autres.isEmpty
                ? "pour \(item.chain.avecArticle)"
                : "ou " + autres.joined(separator: ", ")
            return LigneAssiette(
                id: item.id,
                symbole: symbole(item),
                iconeAliment: iconeAliment(for: item.chain),
                teinte: item.chain.tint,
                teinteTexte: Color.teinteApportTexte(for: item.chain.id),
                titre: titre(item),
                sousTitre: precision,
                apport: item.chain.nom
            )
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
            cta: ctaHeros(item),
            cadence: cadenceAnneaux
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
            enLigne: enLigne,
            statutMot: FicheApportContexte.statutMot(detail: item.detail),
            cadence: cadenceAnneaux
        ) { ouvrir(item) }
    }

    /// Voie compléments : l'apport. Voie assiette : le premier aliment qui le couvre.
    private func titre(_ item: Tuile) -> String {
        guard voie == .assiette, let aliment = aliments(for: item.chain).first else {
            return item.chain.nom
        }
        return aliment.capitalizedFirstLetter
    }

    /// Le symbole de l'apport, dans les deux voies : en voie assiette, il
    /// n'est plus que le repli d'une ligne dont l'aliment n'a pas d'illustration.
    private func symbole(_ item: Tuile) -> String {
        item.chain.symbol
    }

    /// L'illustration du premier aliment (celui qui donne son titre à la
    /// ligne) : l'icône rédigée par le bilan, sinon celle du catalogue. Gardée
    /// seulement si l'asset existe dans le bundle — sinon, le symbole de l'apport.
    private func iconeAliment(for chain: ComplementChain) -> String? {
        let brute: String?
        if let aliments = chain.apport?.aliments, !aliments.isEmpty {
            brute = aliments.first { !($0.nom ?? "").isEmpty }?.icone
        } else {
            brute = Fluent3D.foodSources(for: chain.id).first?.asset
        }
        // Un autre nom que `brute` : un `guard let` ne peut pas redéclarer une
        // constante de la même portée.
        guard let nom = brute, !nom.isEmpty else { return nil }
        let asset = nom.hasPrefix("fluent_") ? nom : "fluent_\(nom)"
        return UIImage(named: asset) == nil ? nil : asset
    }

    /// « à combler · 3 causes nommées » sur le héros ; « 3 causes » seul sur
    /// une tuile, comme la maquette (le mot du statut passe à VoiceOver par
    /// `TuileApport.statutMot`). En voie assiette, l'apport que l'aliment sert.
    private func statutLigne(_ item: Tuile, complet: Bool) -> String {
        guard voie == .complements else { return "pour \(item.chain.avecArticle)" }
        // Apport estimé : ses contributions sont des sources, pas des causes.
        if item.detail.estimation != nil {
            let n = item.detail.appuis.count
            let sources = n == 1 ? "1 source" : "\(n) sources"
            return complet ? "\(FicheApportContexte.statutMot(detail: item.detail)) · \(sources)" : sources
        }
        let causes = item.detail.freins.count
        guard complet else {
            switch causes {
            case 0: return "sans cause nommée"
            case 1: return "1 cause"
            default: return "\(causes) causes"
            }
        }
        let mot = FicheApportContexte.statutMot(detail: item.detail)
        switch causes {
        case 0: return "\(mot) · sans cause nommée"
        case 1: return "\(mot) · 1 cause nommée"
        default: return "\(mot) · \(causes) causes nommées"
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

    /// La même dans les deux voies : la maquette la pose hors du corps qui bascule.
    private func noteMosaique(_ items: [Tuile]) -> String {
        items.contains { !$0.detail.freins.isEmpty }
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
                // repris ici : les freins (« Ce qui pèse le plus ») et
                // l'éclairage le disent déjà, et il porte la même phrase sur
                // les symptômes.
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
            statutMot: FicheApportContexte.statutMot(detail: item.detail),
            detail: item.detail,
            eclairage: eclairage(for: chain.id),
            role: ApportRole.role(for: chain.id),
            specs: specs,
            noteDePrise: note,
            precautions: precautions,
            conseilPrecautions: precautions.isEmpty ? nil : SupplementsV4.tip(for: precautions),
            alternatives: alternatives,
            ctaAlternative: cta,
            // La quantité dit l'APPORT : sous le nom d'un aliment (voie
            // assiette), elle se lirait comme celle de l'aliment.
            quantite: enAssiette ? nil : QuantiteApport.libelle(
                id: chain.id, score: item.detail.score, profil: dashboardVM.profile
            ),
            // Voie assiette : le conseil du bilan est déjà la note de « Comment
            // l'intégrer », on ne le redit pas dans les gestes.
            conseil: enAssiette ? nil : texteOuNil(chain.apport?.tipBold),
            conseilSuite: enAssiette ? nil : texteOuNil(chain.apport?.tipRest)
        )
    }

    /// Un texte du bilan, nettoyé ; `nil` s'il est vide.
    private func texteOuNil(_ texte: String?) -> String? {
        let propre = KiwiProse.lisible(texte ?? "")
        return propre.isEmpty ? nil : propre
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

    /// Le retour haptique est donné par la tuile du créneau (réussite à la
    /// coche), une fois par geste et non une fois par prise.
    private func toggleRituel(_ id: String) {
        withAnimation(reduceMotion ? .none : Animation.kiwiVif) {
            rituel = SuiviEngineV4.toggleRituel(id: id, complements: complementsV2)
        }
        // Les widgets montrent le même rituel : ils suivent la coche.
        SynchroWidgets.rafraichir()
    }

    private func toggleCart(_ id: String) {
        HapticService.shared.selection()
        withAnimation(reduceMotion ? .none : Animation.kiwiVif) {
            if taken.contains(id) { taken.remove(id) } else { taken.insert(id) }
        }
    }

    /// Le lien de fin de fiche : on referme, et la page passe sur l'autre voie
    /// (le curseur de la bascule et l'échange du corps s'animent d'eux-mêmes).
    private func basculerVoie() {
        fiche = nil
        cadenceAnneaux = .bascule
        voie = voie == .complements ? .assiette : .complements
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
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.dsSecondaire)
                                    .accessibilityHidden(true)
                                Text(block.0)
                                    .font(.dsSousTitreFort)
                                    .tracking(DSTracking.sousTitre)
                                    .foregroundStyle(Color.dsSecondaire)
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
                                            .foregroundStyle(Verre.iconeNeutre)
                                    }
                                    .accessibilityHidden(true)
                                    Text(entry.displayText)
                                        .font(.dsSousTitreFort)
                                        .tracking(DSTracking.sousTitre)
                                        .foregroundStyle(Color.dsTexte)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                }
                            }
                        }
                        .padding(DS.paddingCarte)
                        .frame(maxWidth: .infinity)
                        .dsCard()
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
                .font(.system(.caption, design: .default).weight(.medium))
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
                    .foregroundStyle(Verre.iconeNeutre)
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

// MARK: - L'échange du corps (à la bascule)

/// Ce qui vient de remplacer l'autre voie arrive en fondu, remonte de 8 pt et
/// sort d'un flou de 4 pt, en 0,38 s. Sous « Réduire les animations », un
/// fondu seul.
private struct EchangeDuCorps<Cle: Equatable>: ViewModifier {
    let cle: Cle

    @State private var pose = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(pose ? 1 : 0)
            .offset(y: (pose || reduceMotion) ? 0 : 8)
            .blur(radius: (pose || reduceMotion) ? 0 : 4)
            .onChange(of: cle) { _, _ in
                // Le départ est sec : c'est l'arrivée qui se joue.
                var seche = Transaction()
                seche.disablesAnimations = true
                withTransaction(seche) { pose = false }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(30))
                    withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.38)) { pose = true }
                }
            }
    }
}

#Preview {
    SupplementsView()
        .environmentObject(DashboardViewModel())
}
