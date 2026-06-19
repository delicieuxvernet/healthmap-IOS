import SwiftUI

// MARK: - Nutrient Detail Sheet (fiche nutriment — DESIGN-PAGES §2)
// Sheet TERMINALE (niveau 2, jamais de niveau 3) : X visible 44 pt réels.
// Ordre des blocs imposé par le template §2 :
//   1. Header : emoji + nom + état FR (HealthScale) + MiniScoreRing
//      (couleur = échelle score, plus jamais la couleur d'identité)
//   2. « Détecté dans tes réponses » : signals en chips + badge fiabilité
//   3. Comparaison en citation discrète (barre latérale fine + italique)
//   4. « Ta solution » d'abord (carte teintée verte douce)
//   5. Repliables fermés : mécanisme / symptômes (UN composant réutilisé)
//   6. Hack + synergie : premium via BlurredSection partagée (loi 11)
struct NutrientDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let nutrient: EnrichedNutrient
    /// Conservé pour les call-sites ; le gating premium est délégué à la
    /// BlurredSection partagée (SubscriptionService = source unique — loi 11,
    /// politique premium identique partout).
    let isPremium: Bool

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
                    // 1. Header
                    headerSection

                    // 2. « Détecté dans tes réponses » — absente si signals vide
                    if let signals = nutrient.signals, !signals.isEmpty {
                        signalsSection(signals)
                    }

                    // 3. Comparaison en citation discrète
                    if let comparaison = nutrient.comparaison, !comparaison.isEmpty {
                        comparisonQuote(comparaison)
                    }

                    // 4. « Ta solution » d'abord
                    if let solution = nutrient.solution, hasSolutionContent(solution) {
                        solutionCard(solution)
                    }

                    // 4b. Recherche approfondie (validate-hypotheses + web) —
                    // présente seulement si le nutriment a des hypothèses v1.
                    deepSearchSection

                    // 5. Repliables fermés (un seul composant réutilisé)
                    if hasMechanism || hasSymptoms {
                        collapsibleGroup
                    }

                    // 6. Hack + synergie — LA case premium floutée de la fiche
                    if let premium = premiumSection {
                        premium
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.vertical, Theme.spacingMD)
            }
            .background(Color.healthMapBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.healthMapMuted)
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

    // MARK: - 1. Header (bloc 1)
    // Sources : NutrientData (emoji, label canonique) + score local.
    // Statut TOUJOURS en français via HealthScale.nutrientLabel (lois 3 & 4) ;
    // l'anneau prend la couleur d'état Color.scoreColor(for:).
    private var headerSection: some View {
        HStack(spacing: Theme.spacingMD) {
            Text(nutrient.emoji)
                .font(.system(size: 40))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text(nutrient.label)
                    .font(Theme.headlineFont)
                    .foregroundStyle(Color.healthMapText)

                Text(HealthScale.nutrientLabel(for: nutrient.score))
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            MiniScoreRing(score: nutrient.score, color: statusColor, size: 52)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nutrient.label), \(HealthScale.nutrientLabel(for: nutrient.score)), score \(nutrient.score) sur 100")
    }

    // MARK: - 2. « Détecté dans tes réponses » (bloc 2)
    // Source : nutrient.signals[] — LA preuve de personnalisation. Chips à
    // fond doux, 1 ligne chacune, 4 max ; badge fiabilité depuis confidence
    // (vocabulaire contrôlé — loi 8). Section absente si signals vide
    // (vérifié au call-site).
    private func signalsSection(_ signals: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.healthMapBlue)
                    .accessibilityHidden(true)

                Text("Détecté dans tes réponses")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapText)

                Spacer()

                if let fiabilite = reliabilityBadge {
                    Text(fiabilite)
                        .pillStyle(color: Color.healthMapBlue)
                }
            }

            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                ForEach(Array(signals.prefix(4).enumerated()), id: \.offset) { _, signal in
                    // Signal — texte libre IA : 1 ligne max (loi 9)
                    Text(signal)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, Theme.pillPaddingH)
                        .padding(.vertical, Theme.pillPaddingV)
                        .background(Color.healthMapBlueLight)
                        .clipShape(Capsule())
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
                .fill(Color.healthMapBlue.opacity(Theme.opacityOverlay))
                .frame(width: 3)
                .accessibilityHidden(true)

            Text(comparaison)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(Color.healthMapSecondary)
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
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.scoreExcellent)
            }

            if let action = solution.action, !action.isEmpty {
                Text(action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let dosage = solution.dosage, !dosage.isEmpty {
                Text(dosage)
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let quand = solution.quand, !quand.isEmpty {
                Text(quand)
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
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
                        .font(Theme.captionBoldFont)
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
    // « Comprendre le mécanisme » (mecanisme + pourquoiCeScore si dispo) /
    // « Symptômes possibles » (signe_manque) — UN composant repliable
    // réutilisé (loi 22), fermé par défaut.
    private var hasMechanism: Bool {
        nutrient.mecanisme?.isEmpty == false || nutrient.pourquoiCeScore?.isEmpty == false
    }

    private var hasSymptoms: Bool {
        nutrient.signeManque?.isEmpty == false
    }

    private var collapsibleGroup: some View {
        VStack(spacing: Theme.spacingSM) {
            if hasMechanism {
                FicheCollapsible(title: "Comprendre le mécanisme", icon: "gearshape.2") {
                    VStack(alignment: .leading, spacing: Theme.spacingSM) {
                        if let mecanisme = nutrient.mecanisme, !mecanisme.isEmpty {
                            collapsibleBody(mecanisme)
                        }
                        if let pourquoi = nutrient.pourquoiCeScore, !pourquoi.isEmpty {
                            collapsibleBody(pourquoi)
                        }
                    }
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
            .foregroundStyle(Color.healthMapSecondary)
            .lineLimit(4)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 6. Hack + synergie (bloc 6)
    // Sources : nutrient.hack / nutrient.synergie — LA case premium floutée
    // de la fiche (loi 11), via la BlurredSection PARTAGÉE (politique premium
    // identique partout). Textes bornés 3 lignes même floutés. Rien de
    // disponible → pas de case (jamais de coquille vide).
    private var premiumSection: AnyView? {
        let hack = nutrient.hack?.isEmpty == false ? nutrient.hack : nil
        let synergie = nutrient.synergie?.isEmpty == false ? nutrient.synergie : nil
        guard hack != nil || synergie != nil else { return nil }

        let title = hack != nil ? "Le hack \(nutrient.label)" : "La synergie \(nutrient.label)"

        return AnyView(
            BlurredSection(isPremium: true, title: title) {
                VStack(alignment: .leading, spacing: Theme.spacingSM) {
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
                .cardStyle()
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
                Text(label)
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapText)

                Text(text)
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
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
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                case .loaded(let result):
                    deepResult(result)
                case .failed(let message):
                    VStack(alignment: .leading, spacing: Theme.spacingSM) {
                        Text(message)
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapSecondary)
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
                    .fill(Color.healthMapBlue)
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
                    .foregroundStyle(Color.healthMapBlue)
                    .accessibilityHidden(true)
                Text("Recherche approfondie")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapText)
                Spacer()
                if let n = result.meta?.webResults, n > 0 {
                    Text("\(n) sources")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.healthMapMuted)
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
                            .foregroundStyle(Color.healthMapText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let reason = confirmed.reason, !reason.isEmpty {
                            Text(reason)
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.healthMapSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let synthesis = result.synthesis, !synthesis.isEmpty {
                Text(synthesis)
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let evidence = result.webEvidence, !evidence.isEmpty {
                Divider()
                HStack(spacing: Theme.spacingXS) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.healthMapBlue)
                        .accessibilityHidden(true)
                    Text("Sources scientifiques")
                        .font(Theme.captionBoldFont)
                        .foregroundStyle(Color.healthMapText)
                }
                ForEach(evidence.prefix(6)) { source in
                    sourceRow(source)
                }
            }

            Text("Informatif\u{202F}: ne remplace pas un avis médical.")
                .font(.system(size: 10))
                .foregroundStyle(Color.healthMapMuted)
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
                    .foregroundStyle(Color.healthMapBlue)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text(source.host)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.healthMapMuted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.healthMapBlue)
                        .accessibilityHidden(true)
                }
            }
            .padding(Theme.spacingSM)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.healthMapBlueLight)
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
                        .foregroundStyle(Color.healthMapBlue)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(Theme.captionBoldFont)
                        .foregroundStyle(Color.healthMapText)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
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
            verdict: nil,
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
        ),
        isPremium: false
    )
}
