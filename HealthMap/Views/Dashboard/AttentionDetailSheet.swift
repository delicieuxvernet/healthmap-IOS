import SwiftUI

// MARK: - Pop-up « Point d'attention » (maquette validée, V2a)
//
// Ouvert au tap d'un point d'attention du Bilan (Z3b) — remplace l'ancienne
// bascule sèche vers l'onglet Plan. Ordre de la maquette :
//   1. header : pastille warning + libellé « Point d'attention » + « Détecté
//      dans tes réponses » + chip du nutriment concerné (teinte du nutriment)
//   2. teasing TOUJOURS en clair : le QUOI est nommé, pas l'habitude — c'est
//      la CONCLUSION de la feuille, donc son plus gros texte (17 / 600)
//   3. schéma du mécanisme en 3 étapes (habitude → mécanisme → impact chiffré)
//   4. carte « Ta solution » (verre teinté kiwi, ampoule, phrase actionnable)
//   5. gating (variante B, 18 août 2026) : en gratuit, 2 + 3 + 4 deviennent UN
//      écrin `PremiumTeaseCard` (zone "point_attention") — le teasing en est
//      le titre, le mécanisme / la solution / l'effet n'y passent que floutés
//   6. bouton secondaire « Voir dans mon plan » → bascule vers l'onglet Plan.
//
// Données 100 % déterministes : le schéma et la solution viennent du catalogue
// code-side `AttentionMechanismCatalog`. Interaction hors catalogue → repli
// sans schéma : teasing + texte existant du contrat (tipBold/tipRest) gaté.
// Jamais de coquille vide (le Bilan ne liste que des interactions avec texte).
//
// Verre liquide (2 octobre 2026) : feuille de verre, schéma et solution sur
// des cartes de verre, pastilles rondes à 12 % de leur teinte (habitude
// neutre, mécanisme ambre, impact énergie), les trois étapes arrivent en
// cascade, le bouton secondaire est en verre clair.
struct AttentionDetailSheet: View {
    let interaction: InteractionV2
    let onSeePlan: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// Source unique premium (loi 11), OBSERVÉE : un achat depuis le pop-up
    /// défloute le mécanisme en direct, sans réouverture.
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    /// Les étapes du schéma arrivent en cascade une fois la feuille ouverte.
    @State private var arrive = false

    private var mechanism: AttentionMechanism? {
        AttentionMechanismCatalog.entry(for: interaction)
    }

    /// Nutriment de la chip : celui du catalogue, sinon celui reconnu dans le
    /// texte du contrat. Introuvable → pas de chip (on n'invente rien).
    private var nutrient: NutrientDefinition? {
        let id = mechanism?.nutrientId
            ?? AttentionMechanismCatalog.inferredNutrientId(from: interaction)
        return id.flatMap { NutrientData.definition(for: $0) }
    }

    /// Teasing en clair : phrase du catalogue, sinon phrase générique qui
    /// nomme le(s) nutriment(s) reconnus, jamais l'habitude ni le geste.
    /// Même chaîne déterministe que le titre gratuit de la carte du Bilan
    /// (`AttentionMechanismCatalog.freeTitle`) — la carte et le pop-up
    /// racontent le même problème. Seul le repli neutre diffère : le header
    /// dit déjà « Détecté dans tes réponses », on ne le répète pas.
    private var teasing: String {
        AttentionMechanismCatalog.freeTitle(
            for: interaction,
            neutral: "Une de tes habitudes du quotidien influence directement tes apports."
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if subscriptionService.isPremium {
                    // 2 · Teasing = la CONCLUSION de la feuille : le plus gros
                    // texte de la page (17 / 600), jamais tronqué.
                    Text(teasing)
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)

                    // 3 + 4 · Le COMMENT (schéma + solution).
                    detailContent
                } else {
                    // Gratuit : le même problème, dans l'écrin premium. Le
                    // titre de l'écrin EST le teasing (donc on ne le répète
                    // pas au-dessus) ; le mécanisme, la solution et l'effet
                    // n'apparaissent que floutés (variante B, 18 août 2026).
                    PremiumTeaseCard(
                        title: teasing,
                        promises: teasePromises,
                        zone: "point_attention"
                    )
                    .padding(.top, 18)
                }

                seePlanButton
            }
            .padding(.horizontal, DS.marge)
            // Marge haute commune aux fiches en bottom sheet (cf. ApportV2DetailSheet).
            .padding(.top, Theme.spacingLG)
            .padding(.bottom, 30)
        }
        // La feuille ne peint plus d'aplat : fond de verre et coins de 38.
        .verreFeuille()
        .onAppear { arrive = true }
    }

    // MARK: - 1 · Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VerrePastilleIcone(
                symbole: "exclamationmark.triangle.fill",
                teinte: Color.teinteEnergie,
                taille: 44,
                tailleIcone: 20
            )

            VStack(alignment: .leading, spacing: 3) {
                // Libellé de catégorie : il annonce, il ne rivalise pas. La
                // conclusion de la feuille est le teasing, pas ce mot-là.
                Text("Point d'attention")
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.teinteEnergieTexte)
                Text("Détecté dans tes réponses")
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                if let nutrient {
                    // Étiquette à la teinte de l'apport : fond à 14 %, texte
                    // dans sa version foncée.
                    Text(nutrient.label)
                        .font(.dsLegende.weight(.semibold))
                        .foregroundStyle(Color.teinteApportTexte(for: nutrient.id.rawValue))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.nutrientColor(for: nutrient.id.rawValue).opacity(0.14))
                        )
                        .padding(.top, 3)
                }
            }

            Spacer(minLength: 8)

            DSCloseButton { dismiss() }
        }
    }

    // MARK: - 3 + 4 · Contenu gaté (schéma + solution, ou repli texte)

    @ViewBuilder
    private var detailContent: some View {
        if let mechanism {
            schemaView(mechanism)
                .padding(.top, 18)
            // Un chiffre d'effet s'affiche avec sa source (audit de
            // conformité du 9 octobre 2026).
            if let source = mechanism.source {
                Text("Source : \(source)")
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                    .verreCascade(arrive, delai: 0.4, decalage: 10)
            }
            solutionCard(text: mechanism.solution)
                .padding(.top, DS.interCarte)
                .verreCascade(arrive, delai: 0.45, decalage: 10)
        } else {
            // Repli hors catalogue : pas de schéma, le texte EXISTANT du
            // contrat fait l'explication et la solution. Jamais inventé.
            if let rest = interaction.tipRest, !rest.isEmpty {
                Text(rest)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            if let bold = interaction.tipBold, !bold.isEmpty {
                solutionCard(text: bold)
                    .padding(.top, 14)
                    .verreCascade(arrive, delai: 0.2, decalage: 10)
            }
        }
    }

    private func schemaView(_ mechanism: AttentionMechanism) -> some View {
        HStack(alignment: .top, spacing: 4) {
            stepView(mechanism.habit, teinte: nil)
                .verreCascade(arrive, delai: 0.2, decalage: 10)
            arrow
                .verreCascade(arrive, delai: 0.24, decalage: 10)
            stepView(mechanism.mechanism, teinte: Color.teinteVitamineD)
                .verreCascade(arrive, delai: 0.28, decalage: 10)
            arrow
                .verreCascade(arrive, delai: 0.32, decalage: 10)
            stepView(mechanism.impact, teinte: Color.teinteEnergie)
                .verreCascade(arrive, delai: 0.36, decalage: 10)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .dsCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(mechanism.habit.line1) \(mechanism.habit.line2), donc \(mechanism.mechanism.line1) \(mechanism.mechanism.line2). Résultat : \(mechanism.impact.line1) \(mechanism.impact.line2)."
        )
    }

    private func stepView(_ step: AttentionMechanism.Step, teinte: Color?) -> some View {
        VStack(spacing: 7) {
            VerrePastilleIcone(symbole: step.icon, teinte: teinte, taille: 44, tailleIcone: 18)
            VStack(spacing: 1) {
                Text(step.line1)
                    .font(.system(.caption, design: .default).weight(.semibold))
                    .foregroundStyle(Color.dsTexte)
                Text(step.line2)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(Color.dsSecondaire)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.dsTertiaire)
            .frame(height: 44)
            .accessibilityHidden(true)
    }

    private func solutionCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.teinteKiwi)
                    .accessibilityHidden(true)
                // Libellé de catégorie : le vert foncé du kiwi.
                Text("Ta solution")
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.teinteKiwiTexte)
            }
            // Le geste : c'est la réponse de la carte, donc son pic.
            Text(text)
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .verreCarte(teinte: Color.teinteKiwi)
    }

    // MARK: - Promesses de l'écrin (contenu premium RÉEL, toujours flouté)

    /// Les trois promesses de l'analyse, chacune adossée à une vraie ligne du
    /// contenu premium — jamais lisible en gratuit (flou, interaction coupée,
    /// masquée à VoiceOver). Hors catalogue, on ne garde que les promesses
    /// réellement alimentées : jamais de coquille vide, jamais de texte inventé.
    private var teasePromises: [PremiumTeasePromise] {
        if let mechanism {
            return [
                PremiumTeasePromise(
                    id: "mecanisme",
                    emoji: "🔍",
                    label: "Le mécanisme",
                    blurred: "\(mechanism.mechanism.line1) \(mechanism.mechanism.line2)"
                ),
                PremiumTeasePromise(
                    id: "solution",
                    emoji: "💡",
                    label: "Ta solution",
                    blurred: mechanism.solution
                ),
                PremiumTeasePromise(
                    id: "effet",
                    emoji: "📈",
                    label: "L'effet",
                    blurred: "\(mechanism.impact.line1) \(mechanism.impact.line2)"
                ),
            ]
        }

        var promises: [PremiumTeasePromise] = []
        if let rest = interaction.tipRest, !rest.isEmpty {
            promises.append(
                PremiumTeasePromise(id: "mecanisme", emoji: "🔍", label: "Le mécanisme", blurred: rest)
            )
        }
        if let bold = interaction.tipBold, !bold.isEmpty {
            promises.append(
                PremiumTeasePromise(id: "solution", emoji: "💡", label: "Ta solution", blurred: bold)
            )
        }
        return promises
    }

    // MARK: - 6 · Bouton secondaire « Voir dans mon plan »

    /// Action secondaire : capsule de verre clair, encre du texte.
    private var seePlanButton: some View {
        Button {
            onSeePlan()
        } label: {
            HStack(spacing: 7) {
                Text("Voir dans mon plan")
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.dsTexte)
            .frame(maxWidth: .infinity, minHeight: DS.hauteurBouton)
            .verreClair()
            .contentShape(Capsule())
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("Voir dans mon plan")
        .padding(.top, 18)
    }
}

#Preview("Catalogue : café + fer") {
    AttentionDetailSheet(
        interaction: InteractionV2(
            tipBold: "Garde le café à 1 h de tes repas",
            tipRest: "il bloque le fer de ton assiette.",
            icone: "coffee"
        ),
        onSeePlan: {}
    )
}

#Preview("Repli hors catalogue") {
    AttentionDetailSheet(
        interaction: InteractionV2(
            tipBold: "Bois un grand verre d'eau au réveil",
            tipRest: "ton hydratation démarre la journée.",
            icone: "droplet"
        ),
        onSeePlan: {}
    )
}
