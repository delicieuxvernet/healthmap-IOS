import SwiftUI

// MARK: - Nutrient Detail Sheet (fiche nutriment — refonte « valeur d'abord »)
// Sheet TERMINALE (niveau 2, jamais de niveau 3) : X visible 44 pt réels.
// Hiérarchie « valeur -> comprendre -> agir » :
//   1. HERO : grande jauge centrée du score (la VALEUR domine) + emoji/nom +
//      état FR (HealthScale) + verdict. Couleur = échelle score (lois 3 & 13).
//   2. « Pourquoi ce score » : pourquoiCeScore + signals en chips + fiabilité
//   3. « Ta solution » (carte teintée verte douce) — AGIR. Premium : nette
//      ici ; gratuit : elle descend dans la case gatée du bloc 7 (le geste
//      ne s'affiche jamais en clair — principe « le gratuit nomme le
//      problème, jamais la solution »)
//   4. Le déclic : comparaison en citation discrète (après l'action)
//   5. Repliables fermés : mécanisme / symptômes (UN composant réutilisé)
//   6. Recherche approfondie (validate-hypotheses + web, à la demande)
//   7. Hack + synergie (+ solution en gratuit) : premium via GatedOverlay +
//      UnlockDoor partagés (loi 11)
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

    /// Couleur d'état : échelle unique score (lois 3 & 13) — jamais la
    /// couleur d'identité du nutriment dans cette fiche.
    private var statusColor: Color {
        Color.scoreColor(for: nutrient.score)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingLG) {
                    // 1. HERO — la VALEUR d'abord : grande jauge centrée du score
                    heroSection

                    // 2. Pourquoi ce score — COMPRENDRE : explication + preuve
                    // (signals + fiabilité). Sort pourquoiCeScore du repliable.
                    if hasPourquoi {
                        pourquoiSection
                    }

                    // 3. « Ta solution » — AGIR. Le geste (action, dosage,
                    // moment) est l'ordonnance : net en premium uniquement.
                    // En gratuit, la carte rejoint la case gatée du bloc 7
                    // (un seul voile, une seule porte) — jamais en clair.
                    if subscriptionService.isPremium,
                       let solution = nutrient.solution, hasSolutionContent(solution) {
                        solutionCard(solution)
                    }

                    // 4. Le déclic : comparaison mémorable, APRÈS l'action
                    if let comparaison = nutrient.comparaison, !comparaison.isEmpty {
                        comparisonQuote(comparaison)
                    }

                    // 5. Repliables fermés (un seul composant réutilisé)
                    if hasMechanism || hasSymptoms {
                        collapsibleGroup
                    }

                    // 6. Recherche approfondie (validate-hypotheses + web) —
                    // présente seulement si le nutriment a des hypothèses v1.
                    deepSearchSection

                    // 7. Hack + synergie — LA case premium floutée de la fiche
                    if let premium = premiumSection {
                        premium
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.vertical, Theme.spacingMD)
            }
            .background(Color.dsFond)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.dsSecondaire)
                            // Zone tactile ≥ 44 pt RÉELLE (loi 20) — l'icône
                            // seule fait ~20 pt (même fix qu'AllNutrientsSheet).
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel("Fermer")
                }
            }
        }
    }

    // MARK: - 1. HERO (bloc 1) — la VALEUR d'abord
    // Refonte « valeur d'abord » : le score devient l'élément dominant (grande
    // jauge centrée ~128 pt, vs 52 pt à droite avant). Couleur = échelle score
    // (lois 3 & 13), jamais la couleur d'identité. Statut FR via HealthScale
    // (lois 3 & 4). On ACTIVE enfin `verdict` (présent mais inutilisé) ; masqué
    // si vide (jamais de coquille — loi 11).
    private var heroSection: some View {
        VStack(spacing: Theme.spacingSM) {
            MiniScoreRing(score: nutrient.score, color: statusColor, size: 128, lineWidth: 11)
                .padding(.top, Theme.spacingXS)

            HStack(spacing: 6) {
                Text(nutrient.emoji)
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
                Text(nutrient.label)
                    .font(Theme.headlineFont)
                    .foregroundStyle(Color.dsTexte)
            }

            Text(HealthScale.nutrientLabel(for: nutrient.score))
                .font(Theme.captionBoldFont)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(statusColor.opacity(Theme.opacityLight))
                .clipShape(Capsule())

            if let verdict = heroVerdict {
                Text(verdict)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            // Charte : le titre annonce, il ne rivalise pas. Il était à la
            // même taille que l'explication qu'il introduit (delta 0).
            Text("Pourquoi ce score")
                .font(Theme.subLabelFont)
                .foregroundStyle(Color.dsAccent)

            if let pourquoi = nutrient.pourquoiCeScore, !pourquoi.isEmpty {
                Text(pourquoi)
                    .font(Theme.insightFont)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let signals = nutrient.signals, !signals.isEmpty {
                HStack(spacing: Theme.spacingXS) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsAccent)
                        .accessibilityHidden(true)
                    Text("Détecté dans tes réponses")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.dsSecondaire)
                    Spacer()
                    if let fiabilite = reliabilityBadge {
                        Text(fiabilite)
                            .pillStyle(color: Color.dsAccent)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: Theme.spacingXS) {
                    ForEach(Array(signals.prefix(4).enumerated()), id: \.offset) { _, signal in
                        // Signal — texte libre IA : 1 ligne max (loi 9)
                        Text(signal)
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.dsTexte)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, Theme.pillPaddingH)
                            .padding(.vertical, Theme.pillPaddingV)
                            .background(Color.dsRemplissage)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
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
    // barre latérale fine + italique, 3 lignes max (loi 9).
    private func comparisonQuote(_ comparaison: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.dsAccent.opacity(Theme.opacityOverlay))
                .frame(width: 3)
                .accessibilityHidden(true)

            Text(comparaison)
                // Le serif était la seule occurrence de cette famille dans toute
                // l'app : l'italique suffit à marquer la citation.
                .font(.system(size: 14, weight: .regular))
                .italic()
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.spacingXS)
    }

    // MARK: - 4. « Ta solution » (bloc 4)
    // Sources : solution.action (3 lignes max), dosage + quand (lignes
    // secondaires, 2 lignes max), « Effet attendu : [delai] » avec icône
    // horloge — le delai est la promesse motivationnelle. Carte teintée
    // verte douce (tokens scoreExcellent existants).
    private func solutionCard(_ solution: NutrientSolutionAI) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.scoreExcellent)
                    .accessibilityHidden(true)

                Text("Ta solution")
                    .font(Theme.subLabelFont)
                    .foregroundStyle(Color.scoreExcellent)
            }

            // Le geste : donnée-héros textuelle de la carte.
            if let action = solution.action, !action.isEmpty {
                Text(action)
                    .font(Theme.heroTextFont)
                    .tracking(Theme.conclusionTracking)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // La dose et le moment SONT l'ordonnance : elles étaient rendues
            // en légende grise, deux tiers de la solution perdus en route.
            // Une donnée-héros de ligne ne descend jamais sous 15 pt.
            if let dosage = solution.dosage, !dosage.isEmpty {
                Text(dosage)
                    .font(Theme.heroValueRowFont)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let quand = solution.quand, !quand.isEmpty {
                Text(quand)
                    .font(Theme.insightFont)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let delai = solution.delai, !delai.isEmpty {
                HStack(spacing: Theme.spacingXS) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scoreExcellent)
                        .accessibilityHidden(true)

                    Text("Effet attendu\u{202F}: \(delai)")
                        .font(Theme.subLabelFont)
                        .foregroundStyle(Color.scoreExcellent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.scoreExcellent.opacity(Theme.opacityLight))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Color.scoreExcellent.opacity(Theme.opacityMedium), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// La carte solution ne s'affiche que si elle a du contenu réel
    /// (jamais de coquille vide — loi 11).
    private func hasSolutionContent(_ solution: NutrientSolutionAI) -> Bool {
        [solution.action, solution.dosage, solution.quand, solution.delai]
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
        VStack(spacing: Theme.spacingSM) {
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
            .font(Theme.captionFont)
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
        let rows = VStack(alignment: .leading, spacing: Theme.spacingSM) {
            if let hack {
                premiumRow(icon: "lightbulb.fill", tint: Color.accentSky, label: "Astuce", text: hack)
            }

            if hack != nil && synergie != nil {
                Divider()
            }

            if let synergie {
                premiumRow(icon: "arrow.triangle.merge", tint: Color.accentIndigo, label: "Synergie", text: synergie)
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)

        if subscriptionService.isPremium {
            // (solution est nil en premium : la garde d'entrée vaut hack/synergie)
            return AnyView(rows.cardStyle())
        }

        let gatedContent = VStack(spacing: Theme.spacingSM) {
            if let solution {
                solutionCard(solution)
            }
            if hack != nil || synergie != nil {
                rows.cardStyle()
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
            VStack(spacing: Theme.spacingSM) {
                GatedOverlay(intensity: .teaser) { gatedContent }
                UnlockDoor(icon: "lock.fill", title: doorTitle, subtitle: doorSubtitle, zone: "fiche_apport")
            }
        )
    }

    /// Ligne premium (hack ou synergie) — texte libre IA : 3 lignes max
    /// (loi 9), borné même flouté.
    private func premiumRow(icon: String, tint: Color, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                // Titre de section : plus petit que ce qu'il annonce. La
                // couleur du domaine reste portée par l'icône : `accentSky`
                // (#5AC8FA) ne tient pas 4,5:1 sur blanc à 11,5 pt, et
                // l'accessibilité passe avant la règle de couleur.
                Text(label)
                    .font(Theme.subLabelFont)
                    .foregroundStyle(Color.dsTexte)

                Text(text)
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.dsSecondaire)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 4b. Recherche approfondie (validate-hypotheses + recherche web)
    // Bouton à la demande : appelle l'Edge Function avec webSearch:true, qui
    // arbitre les hypothèses v1 du nutriment ET ramène des sources scientifiques
    // RÉELLES (PubMed, EFSA, Cochrane…). Résultat affiché EN PLACE (sheet
    // terminale niveau 2, jamais de niveau 3). Absent si aucune hypothèse v1.
    @ViewBuilder
    private var deepSearchSection: some View {
        if let hypotheses = nutrient.hypotheses, !hypotheses.isEmpty {
            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                switch deepState {
                case .idle:
                    deepSearchButton(title: "Recherche approfondie",
                                     subtitle: "Croise tes données avec des articles scientifiques")
                case .loading:
                    HStack(spacing: Theme.spacingSM) {
                        ProgressView()
                        Text("Recherche en cours\u{2026} environ une minute")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.dsSecondaire)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                case .loaded(let result):
                    deepResult(result)
                case .failed(let message):
                    VStack(alignment: .leading, spacing: Theme.spacingSM) {
                        Text(message)
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                        deepSearchButton(title: "Réessayer", subtitle: nil)
                    }
                }
            }
            .padding(Theme.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    private func deepSearchButton(title: String, subtitle: String?) -> some View {
        Button {
            runDeepSearch()
        } label: {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .opacity(0.9)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(Theme.spacingMD)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                    .fill(Color.dsAccent)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
    }

    private func deepResult(_ result: ValidateHypothesesResponse) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.dsAccent)
                    .accessibilityHidden(true)
                Text("Recherche approfondie")
                    .font(Theme.subLabelFont)
                    .foregroundStyle(Color.dsAccent)
                Spacer()
                if let n = result.meta?.webResults, n > 0 {
                    Text("\(n) sources")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsSecondaire)
                }
            }

            if let confirmed = result.confirmedHypothesis, let label = confirmed.label, !label.isEmpty {
                HStack(alignment: .top, spacing: Theme.spacingXS) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.scoreExcellent)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)
                        if let reason = confirmed.reason, !reason.isEmpty {
                            Text(reason)
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.dsSecondaire)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let synthesis = result.synthesis, !synthesis.isEmpty {
                Text(synthesis)
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let evidence = result.webEvidence, !evidence.isEmpty {
                Divider()
                HStack(spacing: Theme.spacingXS) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsAccent)
                        .accessibilityHidden(true)
                    Text("Sources scientifiques")
                        .font(Theme.subLabelFont)
                        .foregroundStyle(Color.dsAccent)
                }
                ForEach(evidence.prefix(6)) { source in
                    sourceRow(source)
                }
            }

            Text("Informatif\u{202F}: ne remplace pas un avis médical.")
                .font(.system(size: 10))
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
            VStack(alignment: .leading, spacing: 1) {
                Text(source.title ?? source.host)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsAccent)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text(source.host)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.dsSecondaire)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.dsAccent)
                        .accessibilityHidden(true)
                }
            }
            .padding(Theme.spacingSM)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.dsRemplissage)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
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
/// Repliable fermé par défaut : header 44 pt réels dans le label (loi 20),
/// chevron, expansion EN PLACE avec `.healthMapSpring` gelée si Reduce
/// Motion (loi 17), haptic léger au toggle (loi 18). Réutilisé pour
/// « Comprendre le mécanisme » et « Symptômes possibles » (loi 22).
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
                withAnimation(reduceMotion ? .none : .healthMapSpring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.dsAccent)
                        .accessibilityHidden(true)

                    // Titre de section : teinté comme son icône, jamais neutre.
                    Text(title)
                        .font(Theme.subLabelFont)
                        .foregroundStyle(Color.dsAccent)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.dsSecondaire)
                        .accessibilityHidden(true)
                }
                // Zone tactile ≥ 44 pt RÉELLE dans le label (loi 20).
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityValue(isExpanded ? "déplié" : "replié")
            .accessibilityHint("Touche deux fois pour \(isExpanded ? "replier" : "déplier") la section.")

            if isExpanded {
                content()
                    .padding(.bottom, Theme.spacingSM)
            }
        }
        .padding(.horizontal, Theme.spacingMD)
        .cardStyle()
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
