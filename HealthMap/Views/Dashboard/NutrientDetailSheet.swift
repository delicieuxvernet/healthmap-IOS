import SwiftUI

// MARK: - Nutrient Detail Sheet (fiche nutriment — refonte « valeur d'abord »)
// Sheet TERMINALE (niveau 2, jamais de niveau 3) : X visible 44 pt réels.
// Hiérarchie « valeur -> comprendre -> agir » :
//   1. HERO : grande jauge centrée du score (la VALEUR domine) + icône/nom +
//      état FR (HealthScale) + verdict
//   2. « Pourquoi ce score » : pourquoiCeScore + signals en chips + fiabilité
//   3. « Ta solution » (carte de verre teintée kiwi) — AGIR. Premium : nette
//      ici ; gratuit : elle descend dans la case gatée du bloc 7 (le geste
//      ne s'affiche jamais en clair — principe « le gratuit nomme le
//      problème, jamais la solution »)
//   4. Le déclic : comparaison en citation discrète (après l'action)
//   5. Repliables fermés : mécanisme / symptômes (UN composant réutilisé)
//   6. Recherche approfondie (validate-hypotheses + web, à la demande)
//   7. Hack + synergie (+ solution en gratuit) : premium via GatedOverlay +
//      UnlockDoor partagés (loi 11)
//
// Verre liquide (2 octobre 2026) : la feuille est en verre (`verreFeuille`),
// chaque bloc est une carte de verre qui arrive en cascade, l'anneau prend la
// teinte de l'apport (`Color.nutrientColor`) sur une piste neutre et son
// chiffre compte jusqu'au score. L'état garde sa couleur d'échelle
// (`HealthScale`) dans l'étiquette, sous l'anneau.
struct NutrientDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let nutrient: EnrichedNutrient
    /// Source unique premium (loi 11, politique identique partout), OBSERVÉE :
    /// un achat depuis la fiche défloute le contenu en direct, sans réouverture
    /// (l'ancien snapshot `let isPremium` figeait l'état à l'ouverture).
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    /// État de la « Recherche approfondie » (validate-hypotheses + web).
    @State private var deepState: DeepSearchState = .idle
    /// Les pastilles de signaux surgissent une fois la fiche ouverte.
    @State private var arrive = false

    /// Couleur d'état : échelle unique score (lois 3 & 13). Elle teinte
    /// l'étiquette d'état, jamais l'anneau.
    private var statusColor: Color {
        Color.scoreColor(for: nutrient.score)
    }

    /// Encre de l'étiquette d'état : la version foncée de la couleur d'échelle,
    /// lisible sur le verre. Les paliers restent ceux de `HealthScale`.
    private var statusInk: Color {
        if statusColor == Color.scoreLow { return Color.dsARenforcerTexte }
        if statusColor == Color.scoreExcellent { return Color.teinteKiwiTexte }
        return statusColor
    }

    /// Fond de l'étiquette d'état : la teinte de la palette qui répond à la
    /// couleur d'échelle (ambre, kiwi), à 14 %.
    private var statusFond: Color {
        if statusColor == Color.scoreLow { return Color.teinteVitamineD.opacity(0.14) }
        if statusColor == Color.scoreExcellent { return Color.teinteKiwi.opacity(0.14) }
        return statusColor.opacity(0.14)
    }

    /// Teinte de l'apport (palette par catégorie) : anneau, icône, filet.
    private var teinte: Color {
        Color.nutrientColor(for: nutrient.id)
    }

    /// Sa version foncée, pour un libellé posé sur le verre.
    private var teinteTexte: Color {
        Color.teinteApportTexte(for: nutrient.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Le rond « Fermer » dans le contenu, en haut à droite, comme la
                    // fiche d'un apport : hors de la barre d'outils, il n'a qu'un
                    // anneau (voir `FeuilleEnTeteFermer`). Cible de 44 pt (loi 20).
                    FeuilleEnTeteFermer { dismiss() }

                    VStack(alignment: .leading, spacing: 22) {
                        // 1. HERO — la VALEUR d'abord : grande jauge centrée du score
                        heroSection
                            .kiwiEntrance(0)

                        // 2. Pourquoi ce score — COMPRENDRE : explication + preuve
                        // (signals + fiabilité). Sort pourquoiCeScore du repliable.
                        if hasPourquoi {
                            pourquoiSection
                                .kiwiEntrance(1)
                        }

                        // 3. « Ta solution » — AGIR. Le geste (action, dosage,
                        // moment) est l'ordonnance : net en premium uniquement.
                        // En gratuit, la carte rejoint la case gatée du bloc 7
                        // (un seul voile, une seule porte) — jamais en clair.
                        if subscriptionService.isPremium,
                           let solution = nutrient.solution, hasSolutionContent(solution) {
                            solutionCard(solution)
                                .kiwiEntrance(2)
                        }

                        // 4. Le déclic : comparaison mémorable, APRÈS l'action
                        if let comparaison = nutrient.comparaison, !comparaison.isEmpty {
                            comparisonQuote(comparaison)
                                .kiwiEntrance(3)
                        }

                        // 5. Repliables fermés (un seul composant réutilisé)
                        if hasMechanism || hasSymptoms {
                            collapsibleGroup
                                .kiwiEntrance(4)
                        }

                        // 6. Recherche approfondie (validate-hypotheses + web) —
                        // présente seulement si le nutriment a des hypothèses v1.
                        deepSearchSection

                        // 7. Hack + synergie — LA case premium floutée de la fiche
                        if let premium = premiumSection {
                            premium
                                .kiwiEntrance(5)
                        }
                    }
                    .padding(.horizontal, DS.marge)
                    // 8 sous le rond visible, comme la maquette : la cible de
                    // 44 déborde déjà de 4 sous le rond de 36.
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        // La feuille ne peint plus d'aplat : fond de verre et coins de 38.
        .verreFeuille()
        .onAppear { arrive = true }
    }

    // MARK: - 1. HERO (bloc 1) — la VALEUR d'abord
    // Carte de verre centrée : anneau dans 150 pt (trait de 14, piste neutre,
    // arc à la teinte de l'apport, chiffre SF Pro Rounded qui compte), le nom
    // précédé de son icône, l'état FR via HealthScale (lois 3 & 4) dans une
    // étiquette teintée, puis le `verdict` ; masqué si vide (jamais de
    // coquille — loi 11).
    private var heroSection: some View {
        VStack(spacing: 12) {
            // L'anneau de la maquette : rayon 66, trait de 14, dans une boîte
            // de 150 pt. Le trait est centré sur le cercle : 132 + 14 = 146 pt
            // hors tout, plus 2 pt de marge de chaque côté.
            MiniScoreRing(score: nutrient.score, color: teinte, size: 132, lineWidth: 14,
                          taillePolice: 34, interlettrage: -1)
                .padding(9)

            HStack(spacing: 6) {
                Image(systemName: BilanV7Nutrient.icon(for: nutrient.id))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(teinte)
                    .accessibilityHidden(true)
                Text(nutrient.label)
                    .font(.dsSection)
                    .tracking(DSTracking.section)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(HealthScale.nutrientLabel(for: nutrient.score))
                .font(.dsLegende.weight(.semibold))
                .foregroundStyle(statusInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(statusFond, in: Capsule())

            if let verdict = heroVerdict {
                Text(verdict)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .lineSpacing(2)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .dsCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nutrient.label), \(HealthScale.nutrientLabel(for: nutrient.score)), score \(nutrient.score) sur 100\(heroVerdict.map { ". \($0)" } ?? "")")
    }

    /// Phrase de verdict du héro : champ IA `verdict` s'il est présent. Sinon
    /// rien (le héro reste complet avec jauge + état). On évite tout doublon
    /// avec `pourquoiCeScore` (affiché en clair juste dessous).
    private var heroVerdict: String? {
        guard let v = nutrient.verdict, !v.isEmpty else { return nil }
        return v
    }

    /// Petit titre d'un bloc de la fiche : 15 / 600, secondaire, posé au-dessus
    /// de sa carte (il annonce, il ne rivalise pas).
    private func titreDeBloc(_ titre: String) -> some View {
        Text(titre)
            .font(.dsSousTitreFort)
            .tracking(DSTracking.sousTitre)
            .foregroundStyle(Color.dsSecondaire)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 2. « Pourquoi ce score » (bloc 2) — COMPRENDRE
    // Refonte valeur-d'abord : juste sous le héro, répond à « d'où vient ce
    // chiffre ». Affiche pourquoiCeScore (sorti du repliable mécanisme où il
    // était noyé) + la preuve de personnalisation (signals en chips, 4 max,
    // 1 ligne — loi 9) + badge fiabilité depuis confidence (vocabulaire
    // contrôlé — loi 8). Absente si pourquoiCeScore ET signals vides.
    private var hasPourquoi: Bool {
        nutrient.pourquoiCeScore?.isEmpty == false || nutrient.signals?.isEmpty == false
    }

    private var pourquoiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            titreDeBloc("Pourquoi ce score")

            VStack(alignment: .leading, spacing: 10) {
                if let pourquoi = nutrient.pourquoiCeScore, !pourquoi.isEmpty {
                    Text(pourquoi)
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .lineSpacing(2)
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(4)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let signals = nutrient.signals, !signals.isEmpty {
                    signauxEnTete
                    signauxPastilles(Array(signals.prefix(4)))
                }
            }
            .padding(DS.paddingCarte)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
        }
        .accessibilityElement(children: .combine)
    }

    private var signauxEnTete: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Verre.iconeNeutre)
                .accessibilityHidden(true)
            Text("Détecté dans tes réponses")
                .font(.dsLegende.weight(.semibold))
                .foregroundStyle(Color.dsSecondaire)
            Spacer(minLength: 8)
            if let fiabilite = reliabilityBadge {
                Text(fiabilite)
                    .font(.dsLegendeMoyenne)
                    .foregroundStyle(Color.dsSecondaire)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Verre.remplissage, in: Capsule())
            }
        }
    }

    private func signauxPastilles(_ signals: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(signals.enumerated()), id: \.offset) { index, signal in
                // Signal — texte libre IA : 1 ligne max (loi 9)
                Text(signal)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Verre.remplissage, in: Capsule())
                    .verreSurgir(arrive, delai: 0.3 + Double(index) * 0.06)
            }
        }
    }

    /// Badge fiabilité : mapping vulgarisé du champ `confidence` (vocabulaire
    /// contrôlé — loi 8). Valeur inconnue ou absente → pas de badge.
    private var reliabilityBadge: String? {
        switch nutrient.confidence {
        case "high": return "Fiabilité élevée"
        case "moderate": return "Fiabilité moyenne"
        case "low": return "À confirmer"
        default: return nil
        }
    }

    // MARK: - 3. Comparaison en citation (bloc 3)
    // Source : nutrient.comparaison — phrase mémorable, en citation discrète :
    // filet latéral à la teinte de l'apport + italique, 3 lignes max (loi 9).
    private func comparisonQuote(_ comparaison: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(teinte.opacity(0.5))
                .frame(width: 3)
                .accessibilityHidden(true)

            Text(comparaison)
                // Le serif était la seule occurrence de cette famille dans toute
                // l'app : l'italique suffit à marquer la citation.
                .font(.dsSousTitre)
                .italic()
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }

    // MARK: - 4. « Ta solution » (bloc 4)
    // Sources : solution.action (3 lignes max), quand (ligne secondaire,
    // 2 lignes max), « Effet attendu : [delai] » avec icône horloge — le delai
    // est la promesse motivationnelle. Carte de verre teintée kiwi dans son
    // coin ; le libellé porte le vert foncé du kiwi.
    private func solutionCard(_ solution: NutrientSolutionAI) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.teinteKiwi)
                    .accessibilityHidden(true)

                Text("Ta solution")
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.teinteKiwiTexte)
            }

            // Le geste : donnée-héros textuelle de la carte.
            if let action = solution.action, !action.isEmpty {
                Text(action)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // La dose journalière ne s'affiche plus (20 septembre 2026) : on
            // conseille le complément, la posologie appartient au fabricant et
            // à la personne. Celle-ci était en plus GÉNÉRÉE par l'IA, donc
            // différente d'un profil à l'autre.
            //
            // Le moment de prise reste, et prend la place laissée : ce n'est
            // pas une posologie mais un conseil d'absorption, souvent ce qui
            // sépare un complément utile d'un complément gaspillé. Une
            // donnée-héros de ligne ne descend jamais sous 15 pt.
            if let quand = solution.quand, !quand.isEmpty {
                Text(quand)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let delai = solution.delai, !delai.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.teinteKiwi)
                        .accessibilityHidden(true)

                    Text("Effet attendu\u{202F}: \(delai)")
                        .font(.dsLegende.weight(.semibold))
                        .foregroundStyle(Color.teinteKiwiTexte)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .verreCarte(teinte: Color.teinteKiwi)
        .accessibilityElement(children: .combine)
    }

    /// La carte solution ne s'affiche que si elle a du contenu réel
    /// (jamais de coquille vide — loi 11).
    private func hasSolutionContent(_ solution: NutrientSolutionAI) -> Bool {
        [solution.action, solution.quand, solution.delai]
            .contains { $0?.isEmpty == false }
    }

    // MARK: - 5. Repliables fermés (bloc 5)
    // « Comprendre le mécanisme » (mecanisme — pourquoiCeScore est désormais
    // remonté en clair dans « Pourquoi ce score ») / « Symptômes possibles »
    // (signe_manque) — UN composant repliable réutilisé (loi 22), fermé par défaut.
    private var hasMechanism: Bool {
        nutrient.mecanisme?.isEmpty == false
    }

    private var hasSymptoms: Bool {
        nutrient.signeManque?.isEmpty == false
    }

    private var collapsibleGroup: some View {
        VStack(spacing: DS.interCarte) {
            if hasMechanism, let mecanisme = nutrient.mecanisme {
                FicheCollapsible(title: "Comprendre le mécanisme", icon: "gearshape.2") {
                    collapsibleBody(mecanisme)
                }
            }

            if hasSymptoms, let signe = nutrient.signeManque {
                FicheCollapsible(title: "Symptômes possibles", icon: "exclamationmark.triangle") {
                    collapsibleBody("Tu ressens peut-être\u{202F}: \(signe)")
                }
            }
        }
    }

    /// Texte libre IA dans un repliable : 4 lignes max (loi 9 — limite
    /// déclarée pour le niveau détail).
    private func collapsibleBody(_ text: String) -> some View {
        Text(text)
            .font(.dsLegende)
            .tracking(DSTracking.legende)
            .lineSpacing(2)
            .foregroundStyle(Color.dsSecondaire)
            .lineLimit(4)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 6. Hack + synergie (bloc 6)
    // Sources : nutrient.hack / nutrient.synergie — LA case premium floutée
    // de la fiche (loi 11), via GatedOverlay + UnlockDoor PARTAGÉS (politique
    // premium identique partout). Textes bornés 3 lignes même floutés. Rien de
    // disponible → pas de case (jamais de coquille vide).
    private var premiumSection: AnyView? {
        let hack = nutrient.hack?.isEmpty == false ? nutrient.hack : nil
        let synergie = nutrient.synergie?.isEmpty == false ? nutrient.synergie : nil
        // En gratuit, « Ta solution » (bloc 3) rejoint cette case : un seul
        // voile, une seule porte pour toute l'ordonnance de la fiche.
        let solution = subscriptionService.isPremium
            ? nil
            : nutrient.solution.flatMap { hasSolutionContent($0) ? $0 : nil }
        guard hack != nil || synergie != nil || solution != nil else { return nil }

        // Famille 1 (fiche apport) : le hack + la synergie sont l'ordonnance —
        // floutés en teaser (6px) sous une porte verte au bénéfice spécifique.
        // Premium → rendu net, sans porte.
        let rows = VStack(alignment: .leading, spacing: 0) {
            if let hack {
                premiumRow(icon: "lightbulb", label: "Astuce", text: hack)
            }

            if hack != nil && synergie != nil {
                DSSeparator(retrait: 0)
            }

            if let synergie {
                premiumRow(icon: "arrow.triangle.merge", label: "Synergie", text: synergie)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)

        if subscriptionService.isPremium {
            // (solution est nil en premium : la garde d'entrée vaut hack/synergie)
            return AnyView(rows.dsCard())
        }

        let gatedContent = VStack(spacing: DS.interCarte) {
            if let solution {
                solutionCard(solution)
            }
            if hack != nil || synergie != nil {
                rows.dsCard()
            }
        }

        let doorTitle = solution != nil
            ? "Débloque ta solution \(nutrient.label)"
            : (hack != nil
                ? "Débloque le hack \(nutrient.label)"
                : "Débloque la synergie \(nutrient.label)")
        let doorSubtitle: String
        if solution != nil && (hack != nil || synergie != nil) {
            doorSubtitle = "Le geste précis + l'astuce d'absorption"
        } else if solution != nil {
            doorSubtitle = "Le geste précis, la dose et le bon moment"
        } else if hack != nil && synergie != nil {
            doorSubtitle = "L'astuce d'absorption + la synergie entre nutriments"
        } else {
            doorSubtitle = hack != nil ? "L'astuce d'absorption qui change tout" : "La synergie entre tes nutriments"
        }

        return AnyView(
            VStack(spacing: DS.interCarte) {
                GatedOverlay(intensity: .teaser) { gatedContent }
                UnlockDoor(icon: "lock.fill", title: doorTitle, subtitle: doorSubtitle, zone: "fiche_apport")
            }
        )
    }

    /// Ligne premium (hack ou synergie) — texte libre IA : 3 lignes max
    /// (loi 9), borné même flouté. Pastille neutre de 36 pt, titre 15 / 600,
    /// texte secondaire de 13.
    private func premiumRow(icon: String, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VerrePastilleIcone(symbole: icon, taille: 36, tailleIcone: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)

                Text(text)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .lineSpacing(2)
                    .foregroundStyle(Color.dsSecondaire)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    // MARK: - 4b. Recherche approfondie (validate-hypotheses + recherche web)
    // Bouton à la demande : appelle l'Edge Function avec webSearch:true, qui
    // arbitre les hypothèses v1 du nutriment ET ramène des sources scientifiques
    // RÉELLES (PubMed, EFSA, Cochrane…). Résultat affiché EN PLACE (sheet
    // terminale niveau 2, jamais de niveau 3). Absent si aucune hypothèse v1.
    @ViewBuilder
    private var deepSearchSection: some View {
        if let hypotheses = nutrient.hypotheses, !hypotheses.isEmpty {
            switch deepState {
            case .idle:
                // L'action principale de la fiche : une capsule de verre vert,
                // seule, sans carte autour.
                deepSearchButton(title: "Recherche approfondie",
                                 subtitle: "Croise tes données avec des articles scientifiques")
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.dsAccent)
                    Text("Recherche en cours\u{2026} environ une minute")
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.paddingCarte)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .dsCard()
            case .loaded(let result):
                deepResult(result)
                    .padding(DS.paddingCarte)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsCard()
            case .failed(let message):
                VStack(alignment: .leading, spacing: DS.interCarte) {
                    Text(message)
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    deepSearchButton(title: "Réessayer", subtitle: nil)
                }
            }
        }
    }

    /// Capsule de verre vert, sur le patron du bouton « Dicter » : icône dans
    /// un rond blanc à 22 %, titre 17 / 600, précision de 12 dessous.
    private func deepSearchButton(title: String, subtitle: String?) -> some View {
        Button {
            runDeepSearch()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.22)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(.caption, design: .default))
                            .opacity(0.88)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.leading, 12)
            .padding(.trailing, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: Verre.hauteurSaisie, alignment: .leading)
            .verrePrincipal()
            .contentShape(Capsule())
        }
        .buttonStyle(.dsPress)
    }

    private func deepResult(_ result: ValidateHypothesesResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(teinte)
                    .accessibilityHidden(true)
                Text("Recherche approfondie")
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(teinteTexte)
                Spacer()
                if let n = result.meta?.webResults, n > 0 {
                    Text("\(n) sources")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(Color.dsSecondaire)
                }
            }

            if let confirmed = result.confirmedHypothesis, let label = confirmed.label, !label.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.teinteKiwi)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.dsSousTitreFort)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)
                        if let reason = confirmed.reason, !reason.isEmpty {
                            Text(reason)
                                .font(.dsLegende)
                                .foregroundStyle(Color.dsSecondaire)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let synthesis = result.synthesis, !synthesis.isEmpty {
                Text(synthesis)
                    .font(.dsLegende)
                    .lineSpacing(2)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let evidence = result.webEvidence, !evidence.isEmpty {
                DSSeparator(retrait: 0)
                HStack(spacing: 5) {
                    Image(systemName: "link")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Verre.iconeNeutre)
                        .accessibilityHidden(true)
                    Text("Sources scientifiques")
                        .font(.dsLegende.weight(.semibold))
                        .foregroundStyle(Color.dsSecondaire)
                }
                ForEach(evidence.prefix(6)) { source in
                    sourceRow(source)
                }
            }

            Text("Informatif\u{202F}: ne remplace pas un avis médical.")
                .font(.dsLegende)
                .foregroundStyle(Color.dsSecondaire)
                .padding(.top, 2)
        }
    }

    private func sourceRow(_ source: WebEvidenceItem) -> some View {
        Button {
            if let urlString = source.url, let url = URL(string: urlString) {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title ?? source.host)
                    .font(.dsLegendeMoyenne)
                    .foregroundStyle(Color.dsAccent)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text(source.host)
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(Color.dsSecondaire)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.dsAccent)
                        .accessibilityHidden(true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                    .fill(Verre.tuileInactive)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("Source\u{202F}: \(source.title ?? source.host). Ouvre le lien.")
    }

    private func runDeepSearch() {
        guard let hypotheses = nutrient.hypotheses, !hypotheses.isEmpty else { return }
        HapticService.shared.tap()
        deepState = .loading
        Task {
            do {
                let result = try await HypothesisValidationService.shared.deepSearch(
                    nutrientId: nutrient.id,
                    hypotheses: hypotheses,
                    score: nutrient.score
                )
                deepState = .loaded(result)
            } catch {
                deepState = .failed("La recherche n'a pas abouti. Vérifie ta connexion et réessaie.")
            }
        }
    }
}

// MARK: - État de la recherche approfondie
private enum DeepSearchState {
    case idle
    case loading
    case loaded(ValidateHypothesesResponse)
    case failed(String)
}

// MARK: - Fiche Collapsible (bloc 5 — composant repliable UNIQUE de la fiche)
/// Repliable fermé par défaut : carte de verre, header 44 pt réels dans le
/// label (loi 20), chevron qui pivote, expansion EN PLACE sur le ressort
/// `kiwiFluide`, gelée si Reduce Motion (loi 17), haptic léger au toggle
/// (loi 18). Réutilisé pour « Comprendre le mécanisme » et « Symptômes
/// possibles » (loi 22).
private struct FicheCollapsible<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticService.shared.tap()
                withAnimation(reduceMotion ? nil : Animation.kiwiFluide) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Verre.iconeNeutre)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.dsTertiaire)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                // Zone tactile ≥ 44 pt RÉELLE dans le label (loi 20).
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)
            .accessibilityValue(isExpanded ? "déplié" : "replié")
            .accessibilityHint("Touche deux fois pour \(isExpanded ? "replier" : "déplier") la section.")

            if isExpanded {
                content()
                    .padding(.bottom, 14)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .dsCard()
    }
}

#Preview {
    NutrientDetailSheet(
        nutrient: EnrichedNutrient(
            id: "vitD", label: "Vitamine D", emoji: "☀️", color: "FF9500",
            score: 38, status: "deficient", confidence: "high",
            signals: ["Peu d\u{2019}exposition au soleil", "Pas de poisson gras", "Fatigue persistante"],
            verdict: "Avec peu de soleil et un travail en int\u{00E9}rieur, ton corps fabrique trop peu de vitamine D.",
            mecanisme: "La vitamine D se synthétise surtout quand ta peau est exposée au soleil.",
            comparaison: "Comme une batterie solaire qui ne se recharge plus en hiver.",
            signeManque: "fatigue, baisse de moral, infections à répétition",
            solution: NutrientSolutionAI(
                action: "Prends un complément de vitamine D3 chaque matin.",
                dosage: "2000 UI par jour",
                quand: "Le matin, avec un repas qui contient du gras",
                pourquoi: nil,
                delai: "6 à 8 semaines"
            ),
            hack: "Associe ta D3 à ton petit-déjeuner pour améliorer son absorption.",
            synergie: "Le magnésium aide ton corps à activer la vitamine D.",
            pourquoiCeScore: "Ton score reflète le peu de soleil et l\u{2019}absence de poisson gras dans tes réponses."
        )
    )
}
