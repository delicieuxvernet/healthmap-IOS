import SwiftUI

// MARK: - Compléments « v4 » (refonte 3D — direction validée juin 2026)
//
// Sous-vues de l'onglet « Mes compléments » dans le langage v4 : fond crème,
// cartes blanches arrondies (`kiwiCard`), pastilles teintées avec SF Symbol
// (pas d'illustration 3D Fluent ici — choix de la maquette « Compléments v4 »),
// pop-up bottom-sheet « Pourquoi ce complément ». Couleur = sens partout
// (échelle unique HealthScale). Gating premium conservé.
//
// Logique inchangée : on consomme `SupplementRecommendation` / `CostSummary` /
// `InteractionWarning` du `SupplementEngine` ; aucun nouvel appel service.

// MARK: - Carte compacte d'un complément recommandé (cliquable → pop-up)
struct SupplementV4Card: View {
    let rec: SupplementRecommendation
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var barFill: CGFloat = 0

    private var color: Color { Color.scoreColor(for: rec.score) }
    private var statusLabel: String { HealthScale.nutrientLabel(for: rec.score) }
    private var essential: Bool { rec.score < 45 }

    /// Part déjà couverte par l'alimentation (le score) vs. part que le
    /// complément vient compléter. On borne pour rester lisible.
    private var foodPct: CGFloat { CGFloat(max(0, min(100, rec.score))) / 100 }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    // Pastille teintée + pilule SF Symbol (pas de 3D Fluent ici).
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(color.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: "pills.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(color)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(rec.nutrientLabel)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.kiwiCharcoal)
                                .lineLimit(1)
                            Text(essential ? "Essentiel" : "Utile")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(essential ? Color.kiwiGreenInk : Color.healthMapSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(essential
                                        ? Color.kiwiGreenSoft
                                        : Color.healthMapMuted.opacity(0.14))
                                )
                        }
                        if let product = rec.bestProduct {
                            Text("\(product.dosage) · \(product.timing.displayGroup.lowercased())")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.healthMapSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                        .accessibilityHidden(true)
                }

                // Barre « couvre ton besoin » : part alimentation (gris) + part
                // que le complément vient combler (vert).
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.kiwiCharcoal.opacity(0.08))
                                .frame(height: 8)
                            HStack(spacing: 0) {
                                Capsule()
                                    .fill(Color.healthMapMuted.opacity(0.55))
                                    .frame(width: geo.size.width * foodPct, height: 8)
                                Capsule()
                                    .fill(Color.kiwiGreen)
                                    .frame(width: geo.size.width * (1 - foodPct) * barFill, height: 8)
                            }
                        }
                    }
                    .frame(height: 8)

                    Text("Couvre ton besoin · alimentation + complément")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.healthMapMuted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .kiwiCard(radius: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(rec.nutrientLabel), \(essential ? "essentiel" : "utile"), \(statusLabel). Touche pour le détail.")
        .onAppear {
            if reduceMotion { barFill = 1 }
            else { withAnimation(.easeOut(duration: 1.0).delay(0.3)) { barFill = 1 } }
        }
    }
}

// MARK: - Carte « À savoir » (interactions, sécurité — toujours visible)
struct SupplementWarningsV4Card: View {
    let warnings: [InteractionWarning]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.scoreLow.opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: "clock.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.scoreLow)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("À savoir")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                ForEach(warnings) { warning in
                    Text(warning.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 20)
    }
}

// MARK: - Carte « Ta cure Kiwio » (coût mensuel — version éco / premium)
/// Reprend le « coffret » de la maquette. Données réelles = `CostSummary` du
/// moteur (total premium vs. économique). Pas de bouton de commande : aucun
/// service de commande n'existe dans le VM — on reste informatif.
struct SupplementCureV4Card: View {
    let cost: CostSummary

    var body: some View {
        VStack(spacing: 0) {
            // Aplat crème + 3 pastilles teintées (pilules SF Symbol).
            HStack(spacing: 16) {
                pill(color: .nutrientVitB12, symbol: "pills.fill")
                pill(color: .nutrientZinc, symbol: "capsule.fill")
                pill(color: .scoreLow, symbol: "pill.fill")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.kiwiCream)
            )

            VStack(spacing: 4) {
                Text("Ta cure Kiwio")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text("Compléments personnalisés selon ton bilan")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 16)

            HStack(alignment: .bottom, spacing: 24) {
                priceColumn(title: "Économique", value: cost.valueTotal, color: .kiwiCharcoal)
                Rectangle()
                    .fill(Color.kiwiCharcoal.opacity(0.10))
                    .frame(width: 1, height: 48)
                priceColumn(title: "Premium", value: cost.premiumTotal, color: .kiwiGreenInk)
            }
            .padding(.top, 18)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .kiwiCard()
        .accessibilityElement(children: .contain)
    }

    private func priceColumn(title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.healthMapSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.0f €", value))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text("/ mois")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) : \(Int(value)) euros par mois.")
    }

    private func pill(color: Color, symbol: String) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: 46, height: 46)
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(color)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Pop-up « Pourquoi ce complément » (bottom sheet)
/// Fiche détaillée d'un complément : dose + moment, « Pourquoi pour toi »
/// (causal, `whyText`), comparatif Premium / Économique (formes + prix réels du
/// catalogue), comment le prendre / durée / sources (guide curé). CTA non
/// fonctionnel volontairement (pas de service de panier).
struct SupplementDetailSheet: View {
    let rec: SupplementRecommendation
    @Environment(\.dismiss) private var dismiss

    private var color: Color { Color.scoreColor(for: rec.score) }
    private var statusLabel: String { HealthScale.nutrientLabel(for: rec.score) }
    private var essential: Bool { rec.score < 45 }
    private var guide: SupplementGuideInfo? { SupplementGuide.info(for: rec.nutrientID.rawValue) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                // Dose / Quand
                HStack(spacing: 8) {
                    if let product = rec.bestProduct {
                        infoChip(label: "Dose", value: product.dosage)
                        infoChip(label: "Quand", value: product.timing.displayGroup)
                    }
                }
                .padding(.top, 16)

                // Pourquoi pour toi (causal)
                sectionTitle("Pourquoi pour toi")
                Text(rec.whyText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Premium / Économique
                if rec.premiumProduct != nil || rec.valueProduct != nil {
                    sectionTitle("Premium ou économique")
                    HStack(spacing: 10) {
                        if let premium = rec.premiumProduct {
                            tierCard(
                                icon: "crown.fill",
                                accent: .kiwiGreen,
                                title: "Premium",
                                titleColor: .kiwiGreenInk,
                                form: premium.dosage,
                                price: premium.monthlyCost,
                                priceColor: .kiwiGreenInk,
                                highlighted: true
                            )
                        }
                        if let value = rec.valueProduct {
                            tierCard(
                                icon: "leaf.fill",
                                accent: .healthMapSecondary,
                                title: "Économique",
                                titleColor: .healthMapSecondary,
                                form: value.dosage,
                                price: value.monthlyCost,
                                priceColor: .kiwiCharcoal,
                                highlighted: false
                            )
                        }
                    }
                }

                // Guide curé (comment le prendre / durée / sources)
                if let guide {
                    sectionTitle("Comment en profiter")
                    guideRow(icon: "pills", text: guide.howToTake)
                    guideRow(icon: "calendar", text: guide.cureDuration)
                    guideRow(icon: "leaf", tint: .kiwiGreen, text: guide.foodSources)
                }

                // CTA (visuel — pas de service de commande)
                Button { dismiss() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Ajouter à ma cure")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kiwiGreen))
                    .shadow(color: Color.kiwiGreen.opacity(0.34), radius: 12, x: 0, y: 8)
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.kiwiCream)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 56, height: 56)
                Image(systemName: "pills.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(color)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(rec.nutrientLabel)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(essential ? "Essentiel" : "Utile")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(essential ? Color.kiwiGreenInk : Color.healthMapSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(essential ? Color.kiwiGreenSoft : Color.healthMapMuted.opacity(0.14)))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.healthMapSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.kiwiCharcoal.opacity(0.06)))
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("Fermer")
        }
    }

    private func infoChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.healthMapMuted)
            Text(value)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.healthMapCard))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.kiwiCharcoal.opacity(0.05), lineWidth: 1))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.kiwiCharcoal)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    private func tierCard(icon: String, accent: Color, title: String, titleColor: Color,
                          form: String, price: Double, priceColor: Color, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(titleColor)
            }
            Text(form)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.healthMapSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.0f €", price))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(priceColor)
                Text("/mois")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.healthMapMuted)
            }
            .padding(.top, 3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.healthMapCard))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(highlighted ? Color.kiwiGreen : Color.kiwiCharcoal.opacity(0.08),
                        lineWidth: highlighted ? 1.5 : 1)
        )
        .shadow(color: highlighted ? Color.kiwiGreen.opacity(0.12) : .clear, radius: 16, x: 0, y: 6)
    }

    private func guideRow(icon: String, tint: Color = .healthMapBlue, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}
