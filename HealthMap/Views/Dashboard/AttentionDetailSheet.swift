import SwiftUI

// MARK: - Pop-up « Point d'attention » (maquette validée, V2a)
//
// Ouvert au tap d'un point d'attention du Bilan (Z3b) — remplace l'ancienne
// bascule sèche vers l'onglet Plan. Ordre de la maquette :
//   1. header : pastille warning + « Point d'attention » + « Détecté dans tes
//      réponses » + chip du nutriment concerné (couleur du nutriment)
//   2. teasing TOUJOURS en clair : le QUOI est nommé, pas l'habitude
//   3. schéma du mécanisme en 3 étapes (habitude → mécanisme → impact chiffré)
//   4. carte « Ta solution » (fond kiwiTint, ampoule, phrase actionnable)
//   5. gating : 3 + 4 sous UN SEUL GatedOverlay(.teaser) + UNE SEULE
//      UnlockDoor (zone "point_attention") — patron ApportV2DetailSheet #207
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
    /// nomme le nutriment quand il est reconnu, jamais l'habitude.
    private var teasing: String {
        if let mechanism { return mechanism.teasing }
        if let nutrient {
            return "Une de tes habitudes du quotidien influence directement ton apport en \(nutrient.label.lowercased())."
        }
        return "Une de tes habitudes du quotidien influence directement tes apports."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                // 2 · Teasing — reste net pour tout le monde.
                Text(teasing)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                // 3 + 4 · Le COMMENT (schéma + solution), réservé au premium :
                // un seul voile, une seule porte (patron fiche apport #207).
                if subscriptionService.isPremium {
                    detailContent
                } else {
                    VStack(spacing: Theme.spacingSM) {
                        GatedOverlay(intensity: .teaser) { detailContent }
                        UnlockDoor(
                            icon: "lock.fill",
                            title: doorTitle,
                            subtitle: doorSubtitle,
                            zone: "point_attention"
                        )
                    }
                    .padding(.top, 4)
                }

                seePlanButton
            }
            .padding(.horizontal, 22)
            // Marge haute commune aux fiches en bottom sheet (cf. ApportV2DetailSheet).
            .padding(.top, Theme.spacingLG)
            .padding(.bottom, 30)
        }
        .background(Color.kiwiCream)
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
                Text("Point d'attention")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text("Détecté dans tes réponses")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
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
                    .foregroundStyle(Color.healthMapSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.kiwiCharcoal.opacity(0.06)))
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
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.kiwiCharcoal.opacity(0.85))
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
            stepView(mechanism.habit, tint: Color.kiwiCharcoal)
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
                    .foregroundStyle(Color.kiwiCharcoal)
                Text(step.line2)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.healthMapMuted)
            .frame(height: 44)
            .accessibilityHidden(true)
    }

    private func solutionCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.kiwiInk)
                    .accessibilityHidden(true)
                Text("Ta solution")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiInk)
            }
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color.kiwiCharcoal)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.kiwiTint))
    }

    // MARK: - Porte (wording : bénéfice spécifique, jamais générique)

    private var doorTitle: String {
        if let nutrient {
            return "Débloque le mécanisme \(nutrient.label.lowercased())"
        }
        return "Débloque le mécanisme complet"
    }

    private var doorSubtitle: String {
        mechanism != nil
            ? "Le schéma complet + le geste qui change tout"
            : "L'explication + le geste qui change tout"
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
            .foregroundStyle(Color.kiwiInk)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.kiwiCharcoal.opacity(0.05))
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
