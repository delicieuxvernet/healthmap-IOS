import SwiftUI

// MARK: - Compléments « v4 » (refonte 3D — direction validée juin 2026)
//
// Sous-vues de l'onglet « Mes compléments » FINAL : fond crème, encart de
// transparence, toggle Premium / Éco, cartes blanches par complément (pastille
// SF Symbol, tag Essentiel/Utile, jauge « couvre ton besoin », bouton « Je le
// prends » + lien « Par l'assiette »), panier dynamique, et deux pop-up
// (détail « Pourquoi pour toi » + « Précautions »). Couleur = sens partout
// (échelle unique HealthScale). Gating premium = toggle local.
//
// Logique inchangée : on consomme `SupplementRecommendation` / `CostSummary` /
// `InteractionWarning` du `SupplementEngine` ; aucun nouvel appel service.

// MARK: - Modèle d'affichage d'une précaution (dérivé des données moteur)
struct SupplementPrecaution: Identifiable {
    let id = UUID()
    let icon: String      // SF Symbol
    let bg: Color
    let color: Color
    let title: String
    let note: String
}

// MARK: - Helpers de mapping (markup → données réelles)
enum SupplementsV4 {

    /// Produit affiché selon le mode Premium / Éco choisi (avec repli sur l'autre tier).
    static func product(_ rec: SupplementRecommendation, premium: Bool) -> SupplementProduct? {
        premium
            ? (rec.premiumProduct ?? rec.valueProduct)
            : (rec.valueProduct ?? rec.premiumProduct)
    }

    /// Prix mensuel affiché selon le mode Premium / Éco choisi.
    static func monthlyPrice(_ rec: SupplementRecommendation, premium: Bool) -> Double {
        product(rec, premium: premium)?.monthlyCost ?? 0
    }

    static func priceLabel(_ rec: SupplementRecommendation, premium: Bool) -> String {
        let v = monthlyPrice(rec, premium: premium)
        return String(format: "%.0f €", v)
    }

    /// Précautions du profil concernant ce complément : on agrège les
    /// `InteractionWarning` du moteur qui citent ce nutriment + les
    /// anti-interactions / contre-indications du produit retenu.
    static func precautions(for rec: SupplementRecommendation,
                            warnings: [InteractionWarning]) -> [SupplementPrecaution] {
        var items: [SupplementPrecaution] = []

        // 1) Interactions détectées par le moteur impliquant ce nutriment.
        for w in warnings where w.nutrients.contains(rec.nutrientID.rawValue) {
            let critical = w.severity == .critical
            items.append(SupplementPrecaution(
                icon: critical ? "exclamationmark.octagon.fill" : "arrow.left.arrow.right",
                bg: critical ? Color.scoreDeficient.opacity(0.14) : Color.scoreLow.opacity(0.16),
                color: critical ? Color.scoreDeficient : Color.scoreLow,
                title: precautionTitle(w, nutrientID: rec.nutrientID),
                note: w.message
            ))
        }

        // 2) Anti-interactions du produit retenu non déjà couvertes.
        if let product = rec.bestProduct {
            for anti in product.antiInteractions {
                let antiLabel = NutrientID(rawValue: anti).map { SupplementEngine.nutrientLabel(for: $0) } ?? anti
                let already = items.contains { $0.note.lowercased().contains(antiLabel.lowercased()) }
                if !already && NutrientID(rawValue: anti) != nil {
                    items.append(SupplementPrecaution(
                        icon: "clock.fill",
                        bg: Color.scoreLow.opacity(0.16),
                        color: Color.scoreLow,
                        title: "À distance de \(antiLabel)",
                        note: "Sépare les prises de 2 h pour ne pas gêner l'absorption."
                    ))
                }
            }

            // 3) Contre-indications du produit (affichées, jamais masquées).
            for ci in product.contraindications {
                items.append(SupplementPrecaution(
                    icon: "cross.case.fill",
                    bg: Color.scoreLow.opacity(0.16),
                    color: Color.scoreLow,
                    title: ci.title,
                    note: ci.warningLabel
                ))
            }
        }

        return items
    }

    private static func precautionTitle(_ w: InteractionWarning, nutrientID: NutrientID) -> String {
        // Le « partenaire » de l'interaction (l'autre nutriment ou le médicament).
        let other = w.nutrients.first { $0 != nutrientID.rawValue } ?? ""
        if let n = NutrientID(rawValue: other) {
            return "Avec \(SupplementEngine.nutrientLabel(for: n))"
        }
        switch other {
        case "anticoagulant": return "Avec ton anticoagulant"
        case "ppi": return "Avec ton IPP"
        case "metformin": return "Avec la metformine"
        case "grossesse": return "Grossesse"
        default: return w.severity == .critical ? "À surveiller de près" : "Bon à savoir"
        }
    }

    static func tip(for items: [SupplementPrecaution]) -> String {
        if items.contains(where: { $0.color == Color.scoreDeficient }) {
            return "Parles-en à ton médecin avant de commencer cette cure."
        }
        return "Décale simplement les prises dans la journée, c'est suffisant."
    }
}

// MARK: - Choix utilisateur pour un complément
enum SupplementChoice { case none, complement, assiette }

// MARK: - Carte d'un complément recommandé (FINAL)
struct SupplementCardV4: View {
    let rec: SupplementRecommendation
    let premium: Bool
    let interCount: Int
    /// Choix courant : panier (complément) ou couverture par l'assiette.
    let choice: SupplementChoice
    let onCapsule: () -> Void       // ouvre le détail
    let onInteractions: () -> Void  // ouvre les précautions
    let onComplement: () -> Void    // « Je le prends » (panier)
    let onAssiette: () -> Void      // « Par l'assiette » (mode assiette)
    let onSeeFoodPlan: () -> Void   // CTA assiette → Plan

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var suppFill: CGFloat = 0

    /// Produit effectivement affiché (selon le toggle Premium / Éco).
    private var shownProduct: SupplementProduct? { SupplementsV4.product(rec, premium: premium) }

    private var color: Color { Color.scoreColor(for: rec.score) }
    private var essential: Bool { rec.score < 45 }
    private var foodPct: CGFloat { CGFloat(max(0, min(100, rec.score))) / 100 }
    private var isComplement: Bool { choice == .complement }
    private var isAssiette: Bool { choice == .assiette }

    var body: some View {
        VStack(spacing: 0) {
            // En-tête : pastille + nom/tag/dose + compteur d'interactions
            HStack(spacing: 12) {
                Button(action: onCapsule) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(color.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: "pills.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(color)
                    }
                }
                .buttonStyle(.healthMapPressed)
                .accessibilityLabel("Détail \(rec.nutrientLabel)")

                Button(action: onCapsule) {
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
                        if let product = shownProduct {
                            Text("\(product.dosage) · \(product.timing.displayGroup.lowercased())")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.healthMapSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.healthMapPressed)

                if interCount > 0 {
                    Button(action: onInteractions) {
                        ZStack(alignment: .topTrailing) {
                            ZStack {
                                Circle()
                                    .fill(Color.scoreDeficient.opacity(0.12))
                                    .frame(width: 42, height: 42)
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.scoreDeficient)
                            }
                            Text("\(interCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(
                                    Capsule()
                                        .fill(Color.scoreDeficient)
                                        .overlay(Capsule().stroke(Color.healthMapCard, lineWidth: 2))
                                )
                                .offset(x: 5, y: -5)
                        }
                        .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel("\(interCount) précautions pour \(rec.nutrientLabel)")
                }
            }

            // Marque + lien vers la fiche officielle (option a : site de la marque).
            if let product = shownProduct {
                HStack(spacing: 10) {
                    Text(String(product.brand.prefix(1)))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.kiwiCharcoal))
                        .accessibilityHidden(true)
                    Text(product.brand)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button {
                        if let url = URL(string: product.productURL) { openURL(url) }
                    } label: {
                        HStack(spacing: 5) {
                            Text("Voir le produit")
                                .font(.system(size: 12, weight: .bold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Color.kiwiGreenInk)
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel("Voir \(product.name) chez \(product.brand)")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color(hex: "FAF8F3")))
                .padding(.top, 13)
            }

            // Jauge « couvre ton besoin » : alimentation (gris) + complément (vert).
            Button(action: onCapsule) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 12) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(hex: "EEE9DF"))
                                    .frame(height: 8)
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Color(hex: "C9C3B6"))
                                        .frame(width: geo.size.width * foodPct, height: 8)
                                    Rectangle()
                                        .fill(Color.kiwiGreen)
                                        .frame(width: geo.size.width * (1 - foodPct) * suppFill, height: 8)
                                }
                                .clipShape(Capsule())
                            }
                        }
                        .frame(height: 8)

                        Text("100%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.kiwiGreenInk)
                    }

                    HStack(spacing: 0) {
                        Text("Couvre ton besoin · ")
                        Text("\(rec.score)% ")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text("assiette + complément")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.healthMapMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.healthMapPressed)
            .padding(.top, 14)

            // Choix : « Je le prends » (panier) OU « Par l'assiette » (mode).
            // Vrai toggle : un seul actif à la fois, re-tap = on désélectionne.
            HStack(spacing: 3) {
                Button(action: onComplement) {
                    VStack(spacing: 1) {
                        Text("Je le prends")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isComplement ? .white : Color.kiwiCharcoal)
                        Text("\(SupplementsV4.priceLabel(rec, premium: premium))/mois")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(isComplement ? Color.white.opacity(0.85) : Color.healthMapSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isComplement ? Color.kiwiGreen : Color.clear)
                            .shadow(color: isComplement ? Color.kiwiGreen.opacity(0.3) : .clear,
                                    radius: 6, x: 0, y: 3)
                    )
                }
                .buttonStyle(.healthMapPressed)

                Button(action: onAssiette) {
                    HStack(spacing: 5) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 13))
                        Text("Par l'assiette")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(isAssiette ? .white : Color.kiwiGreenInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isAssiette ? Color.kiwiGreenInk : Color.white)
                            .shadow(color: Color.kiwiCharcoal.opacity(0.05), radius: 4, x: 0, y: 2)
                    )
                }
                .buttonStyle(.healthMapPressed)
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(hex: "F4F1EA"))
            )
            .padding(.top, 14)

            // Lien « Voir comment le couvrir par l'assiette » → Plan :
            // visible UNIQUEMENT quand on a choisi « Par l'assiette ».
            if isAssiette {
                Button(action: onSeeFoodPlan) {
                    HStack(spacing: 11) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.kiwiGreenInk)
                        Text("Voir comment le couvrir par l'assiette")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "27510A"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ZStack {
                            Circle().fill(Color.kiwiGreen).frame(width: 30, height: 30)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.kiwiGreenSoft)
                    )
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 10)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 20)
        .onAppear {
            if reduceMotion { suppFill = 1 }
            else { withAnimation(.easeOut(duration: 1.0).delay(0.4)) { suppFill = 1 } }
        }
    }
}

// MARK: - Encart de transparence (bleu doux)
struct SupplementTransparencyCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 40, height: 40)
                    .shadow(color: Color.kiwiCharcoal.opacity(0.06), radius: 3, x: 0, y: 1)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: "2F6FE0"))
            }
            .accessibilityHidden(true)
            Text("Kiwio ne gagne rien sur ces compléments. C'est juste la voie la plus simple pour combler tes apports — tu peux tout faire par l'alimentation.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "1F4F9E"))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "EAF0FB"))
        )
    }
}

// MARK: - Toggle Premium / Éco
struct SupplementQualityToggle: View {
    @Binding var premium: Bool

    var body: some View {
        HStack(spacing: 2) {
            Button { withAnimation(.easeOut(duration: 0.2)) { premium = true } } label: {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill").font(.system(size: 12))
                    Text("Premium").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(premium ? Color.kiwiGreenInk : Color.healthMapSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(premium ? Color.white : Color.clear)
                        .shadow(color: premium ? Color.kiwiCharcoal.opacity(0.08) : .clear,
                                radius: 3, x: 0, y: 1)
                )
            }
            .buttonStyle(.healthMapPressed)

            Button { withAnimation(.easeOut(duration: 0.2)) { premium = false } } label: {
                Text("Éco")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(!premium ? Color.kiwiCharcoal : Color.healthMapSecondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(!premium ? Color.white : Color.clear)
                            .shadow(color: !premium ? Color.kiwiCharcoal.opacity(0.08) : .clear,
                                    radius: 3, x: 0, y: 1)
                    )
            }
            .buttonStyle(.healthMapPressed)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(hex: "EFEBE2"))
        )
    }
}

// MARK: - Panier dynamique « D'après tes choix »
struct SupplementCartCard: View {
    let taken: [SupplementRecommendation]
    let premium: Bool
    let totalLabel: String
    let onOrder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "bag.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.kiwiGreenInk)
                Text("D'après tes choix")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
            }

            VStack(spacing: 10) {
                if taken.isEmpty {
                    Text("Coche « Je le prends » sur les compléments que tu veux ajouter à ta sélection.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(taken) { rec in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.scoreColor(for: rec.score).opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "pills.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.scoreColor(for: rec.score))
                            }
                            Text(rec.nutrientLabel)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.kiwiCharcoal)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(SupplementsV4.priceLabel(rec, premium: premium))/mois")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.kiwiGreenInk)
                        }
                    }
                }
            }
            .padding(.top, 14)

            if !taken.isEmpty {
                Button(action: onOrder) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right.square.fill").font(.system(size: 17))
                        Text("Voir mes produits · \(totalLabel)/mois")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.kiwiGreen)
                    )
                    .shadow(color: Color.kiwiGreen.opacity(0.3), radius: 9, x: 0, y: 8)
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 18)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 24)
    }
}

// MARK: - Pop-up détail « Pourquoi pour toi »
struct SupplementWhySheet: View {
    let rec: SupplementRecommendation
    let onChoose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var color: Color { Color.scoreColor(for: rec.score) }
    private var essential: Bool { rec.score < 45 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // En-tête
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

                    VStack(alignment: .leading, spacing: 4) {
                        Text(rec.nutrientLabel)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.kiwiCharcoal)
                        Text(essential ? "Essentiel" : "Utile")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(essential ? Color.kiwiGreenInk : Color.healthMapSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(essential
                                ? Color.kiwiGreenSoft
                                : Color.healthMapMuted.opacity(0.14)))
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.healthMapSecondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color(hex: "EFEBE2")))
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel("Fermer")
                }

                // Dose / Quand
                if let product = rec.bestProduct {
                    HStack(spacing: 8) {
                        infoChip(label: "Dose", value: product.dosage, fill: true)
                        infoChip(label: "Quand", value: product.timing.displayGroup, fill: false)
                    }
                    .padding(.top, 16)
                }

                sectionTitle("Pourquoi pour toi")
                Text(rec.whyText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color(hex: "3A3833"))
                    .fixedSize(horizontal: false, vertical: true)

                sectionTitle("Premium ou économique")
                HStack(spacing: 10) {
                    if let premiumProduct = rec.premiumProduct {
                        tierCard(icon: "crown.fill", title: "Premium", titleColor: .kiwiGreenInk,
                                 brand: premiumProduct.brand, form: premiumProduct.dosage,
                                 price: premiumProduct.monthlyCost, url: premiumProduct.productURL,
                                 priceColor: .kiwiGreenInk, highlighted: true)
                    }
                    if let value = rec.valueProduct {
                        tierCard(icon: "leaf.fill", title: "Économique", titleColor: .healthMapSecondary,
                                 brand: value.brand, form: value.dosage,
                                 price: value.monthlyCost, url: value.productURL,
                                 priceColor: Color(hex: "3A3833"), highlighted: false)
                    }
                }

                Button {
                    onChoose()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                        Text("Choisir ce complément").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kiwiGreen))
                    .shadow(color: Color.kiwiGreen.opacity(0.34), radius: 12, x: 0, y: 10)
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .background(Color.kiwiCream)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    private func infoChip(label: String, value: String, fill: Bool) -> some View {
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
        .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        .shadow(color: Color.kiwiCharcoal.opacity(0.04), radius: 1, x: 0, y: 1)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.kiwiCharcoal)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    private func tierCard(icon: String, title: String, titleColor: Color,
                          brand: String, form: String, price: Double, url: String,
                          priceColor: Color, highlighted: Bool) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(highlighted ? Color.kiwiGreen : Color(hex: "928C7E"))
                    Text(title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(titleColor)
                }
                Text(brand)
                    .font(.system(size: 12.5, weight: .heavy))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .lineLimit(1)
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
                HStack(spacing: 4) {
                    Text("Voir le produit")
                        .font(.system(size: 11, weight: .bold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.kiwiGreenInk)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(highlighted ? Color.kiwiGreen : Color.kiwiCharcoal.opacity(0.08),
                            lineWidth: highlighted ? 1.5 : 1)
            )
            .shadow(color: highlighted ? Color.kiwiGreen.opacity(0.12) : .clear, radius: 16, x: 0, y: 6)
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(title), \(brand), \(String(format: "%.0f €", price)) par mois. Voir le produit.")
    }
}

// MARK: - Pop-up « Précautions »
struct SupplementPrecautionsSheet: View {
    let rec: SupplementRecommendation
    let items: [SupplementPrecaution]
    let tip: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.scoreDeficient.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.scoreDeficient)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PRÉCAUTIONS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(Color(hex: "C0322A"))
                        Text(rec.nutrientLabel)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color.kiwiCharcoal)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.healthMapSecondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color(hex: "EFEBE2")))
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel("Fermer")
                }

                Text("Interactions détectées sur ton profil")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .padding(.top, 18)
                    .padding(.bottom, 11)

                VStack(spacing: 10) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(item.bg)
                                    .frame(width: 34, height: 34)
                                Image(systemName: item.icon)
                                    .font(.system(size: 17))
                                    .foregroundStyle(item.color)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundStyle(Color.kiwiCharcoal)
                                Text(item.note)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.healthMapSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.kiwiCharcoal.opacity(0.04), lineWidth: 1))
                        .shadow(color: Color.kiwiCharcoal.opacity(0.05), radius: 3, x: 0, y: 1)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.kiwiGreenInk)
                    Text(tip)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.kiwiGreenInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kiwiGreenSoft))
                .padding(.top, 16)

                Button { dismiss() } label: {
                    Text("J'ai compris")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kiwiCharcoal))
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 20)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .background(Color.kiwiCream)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }
}
