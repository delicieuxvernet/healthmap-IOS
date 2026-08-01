import SwiftUI

// MARK: - Compléments : socle partagé (données de précaution + feuille)
//
// Ce qui reste de commun à l'onglet Compléments une fois la refonte v6 en
// place (`SupplementsChainV6.swift` porte l'écran) :
//   • `SupplementPrecaution` : modèle d'affichage d'une précaution ;
//   • `SupplementsV4` : les helpers de mapping moteur → affichage ;
//   • `SupplementPrecautionsSheet` : la feuille ouverte par la carte ambre.
//
// Les composants de l'ancien écran v4 (carte de complément, encart de
// transparence, toggle Premium/Éco, panier, pop-up « Pourquoi pour toi ») ont
// été supprimés le 1er août 2026 : plus rendus depuis la v6.
//
// ⚠️ L'enum garde le nom historique `SupplementsV4` : il est appelé depuis
// l'écran et le renommer est un refactor à part entière, pas du nettoyage.
//
// On consomme `SupplementRecommendation` et `InteractionWarning` du
// `SupplementEngine` ; aucun appel service ici.

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
