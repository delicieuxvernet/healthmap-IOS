import SwiftUI

// MARK: - Compléments : socle partagé (précautions et choix du produit)
//
//   • `SupplementPrecaution` : modèle d'affichage d'une précaution ;
//   • `SupplementsV4` : les helpers de mapping moteur → affichage.
//
// Les précautions s'affichent dans le bloc 05 de la fiche d'un apport
// (`FicheApport.swift`) : plus de feuille dédiée depuis le 20 septembre 2026.
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
    /// Interaction critique : la seule précaution qui garde une couleur
    /// d'alerte dans la fiche (une sécurité ne se fond pas dans le gris).
    let critique: Bool
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
                critique: critical,
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
                        critique: false,
                        title: "À distance de \(antiLabel)",
                        note: "Sépare les prises de 2 h pour ne pas gêner l'absorption."
                    ))
                }
            }

            // 3) Contre-indications du produit (affichées, jamais masquées).
            for ci in product.contraindications {
                items.append(SupplementPrecaution(
                    icon: "cross.case.fill",
                    critique: false,
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
        if items.contains(where: \.critique) {
            return "Parles-en à ton médecin avant de commencer cette cure."
        }
        return "Décale simplement les prises dans la journée, c'est suffisant."
    }
}
