import SwiftUI

// MARK: - Pop-up « Point d'attention » (maquette validée, V2a)
//
// Ouvert au tap d'un point d'attention du Bilan (Z3b) — remplace l'ancienne
// bascule sèche vers l'onglet Plan. Ordre de la maquette :
//   1. header : pastille warning + kicker « Point d'attention » + « Détecté
//      dans tes réponses » + chip du nutriment concerné (couleur du nutriment)
//   2. teasing TOUJOURS en clair : le QUOI est nommé, pas l'habitude — c'est
//      la CONCLUSION de la feuille, donc son plus gros texte (17 / heavy)
//   3. schéma du mécanisme en 3 étapes (habitude → mécanisme → impact chiffré)
//   4. carte « Ta solution » (fond kiwiTint, ampoule, phrase actionnable)
//   5. gating (variante B, 18 août 2026) : en gratuit, 2 + 3 + 4 deviennent UN
//      écrin `PremiumTeaseCard` (zone "point_attention") — le teasing en est
//      le titre, le mécanisme / la solution / l'effet n'y passent que floutés
//   6. bouton secondaire « Voir dans mon plan » → bascule vers l'onglet Plan.
//
// Données 100 % déterministes : le schéma et la solution viennent du catalogue
// code-side `AttentionMechanismCatalog`. Interaction hors catalogue → repli
// sans schéma : teasing + texte existant du contrat (tipBold/tipRest) gaté.
// Jamais de coquille vide (le Bilan ne liste que des interactions avec texte).
struct AttentionDetailSheet: View {
    let interaction: InteractionV2
    let onSeePlan: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// Source unique premium (loi 11), OBSERVÉE : un achat depuis le pop-up
    /// défloute le mécanisme en direct, sans réouverture.
    @ObservedObject private var subscriptionService = SubscriptionService.shared

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
                    // texte de la page (17 / heavy), jamais tronqué.
                    Text(teasing)
                        .font(Theme.conclusionFont)
                        .tracking(Theme.conclusionTracking)
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
            .padding(.horizontal, 22)
            // Marge haute commune aux fiches en bottom sheet (cf. ApportV2DetailSheet).
            .padding(.top, Theme.spacingLG)
            .padding(.bottom, 30)
        }
        .background(Color.dsFond)
    }

    // MARK: - 1 · Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(BilanV7.alertInk.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 21))
                    .foregroundStyle(BilanV7.alertInk)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                // Libellé générique : il annonce, il ne rivalise pas. Il
                // passe donc en kicker teinté (11.5 / bold) — la conclusion
                // de la feuille est le teasing, pas ce mot-là.
                Text("Point d'attention")
                    .font(Theme.subLabelFont)
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .foregroundStyle(BilanV7.alertInk)
                Text("Détecté dans tes réponses")
                    .font(Theme.dataSecondaryFont)
                    .foregroundStyle(Color.dsSecondaire)
                if let nutrient {
                    Text(nutrient.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(nutrient.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(nutrient.color.opacity(0.14)))
                        .padding(.top, 2)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaire)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.dsTexte.opacity(0.06)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("Fermer")
        }
    }

    // MARK: - 3 + 4 · Contenu gaté (schéma + solution, ou repli texte)

    @ViewBuilder
    private var detailContent: some View {
        if let mechanism {
            schemaView(mechanism)
                .padding(.top, 18)
            solutionCard(text: mechanism.solution)
                .padding(.top, 14)
        } else {
            // Repli hors catalogue : pas de schéma, le texte EXISTANT du
            // contrat fait l'explication et la solution. Jamais inventé.
            if let rest = interaction.tipRest, !rest.isEmpty {
                Text(rest)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dsTexte.opacity(0.85))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            if let bold = interaction.tipBold, !bold.isEmpty {
                solutionCard(text: bold)
                    .padding(.top, 14)
            }
        }
    }

    private func schemaView(_ mechanism: AttentionMechanism) -> some View {
        HStack(alignment: .top, spacing: 4) {
            stepView(mechanism.habit, tint: Color.dsTexte)
            arrow
            stepView(mechanism.mechanism, tint: BilanV7.warnInk)
            arrow
            stepView(mechanism.impact, tint: BilanV7.alertInk)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(mechanism.habit.line1) \(mechanism.habit.line2), donc \(mechanism.mechanism.line1) \(mechanism.mechanism.line2). Résultat : \(mechanism.impact.line1) \(mechanism.impact.line2)."
        )
    }

    private func stepView(_ step: AttentionMechanism.Step, tint: Color) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: step.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(spacing: 1) {
                Text(step.line1)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.dsTexte)
                Text(step.line2)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsSecondaire)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.dsSecondaire)
            .frame(height: 44)
            .accessibilityHidden(true)
    }

    private func solutionCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.dsTexte)
                    .accessibilityHidden(true)
                // Titre de section : teinté, et rangé SOUS son contenu.
                Text("Ta solution")
                    .font(Theme.subLabelFont)
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .foregroundStyle(Color.dsTexte)
            }
            // Le geste : c'est la réponse de la carte, donc son pic.
            Text(text)
                .font(Theme.insightFont)
                .foregroundStyle(Color.dsTexte)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.dsRemplissage))
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

    private var seePlanButton: some View {
        Button {
            onSeePlan()
        } label: {
            HStack(spacing: 7) {
                Text("Voir dans mon plan")
                    .font(.system(size: 14, weight: .bold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.dsTexte)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.dsTexte.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
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
