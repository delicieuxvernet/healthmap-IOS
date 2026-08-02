import Foundation
import SwiftUI

// MARK: - Supplement Models (extracted from SupplementEngine)
// Model structs used by the Supplement Engine for recommendations,
// scheduling, interactions, and cost calculation.

// MARK: - Timing Slot
enum TimingSlot: String, CaseIterable, Identifiable {
    case matinAJeun = "matin_a_jeun"
    case matinRepas = "matin_repas"
    case midiRepas = "midi_repas"
    case soirRepas = "soir_repas"
    case coucher = "coucher"
    case entreRepas = "entre_repas"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .matinAJeun: return "Matin à jeun"
        case .matinRepas: return "Matin avec le petit-déjeuner"
        case .midiRepas: return "Midi avec le repas"
        case .soirRepas: return "Soir avec le dîner"
        case .coucher: return "Au coucher"
        case .entreRepas: return "Entre les repas"
        }
    }

    var emoji: String {
        switch self {
        case .matinAJeun: return "🌅"
        case .matinRepas: return "☀️"
        case .midiRepas: return "🌞"
        case .soirRepas: return "🌆"
        case .coucher: return "🌙"
        case .entreRepas: return "⏳"
        }
    }

    var order: Int {
        switch self {
        case .matinAJeun: return 0
        case .matinRepas: return 1
        case .midiRepas: return 2
        case .soirRepas: return 3
        case .coucher: return 4
        case .entreRepas: return 5
        }
    }

    /// Grouped display slot (matin / midi / soir)
    var displayGroup: String {
        switch self {
        case .matinAJeun, .matinRepas: return "Matin"
        case .midiRepas, .entreRepas: return "Midi"
        case .soirRepas, .coucher: return "Soir"
        }
    }

    var displayGroupIcon: String {
        switch self {
        case .matinAJeun, .matinRepas: return "sunrise.fill"
        case .midiRepas, .entreRepas: return "sun.max.fill"
        case .soirRepas, .coucher: return "moon.fill"
        }
    }

    var displayGroupColor: Color {
        switch self {
        case .matinAJeun, .matinRepas: return .accentSky
        case .midiRepas, .entreRepas: return .healthMapBlue
        case .soirRepas, .coucher: return .accentIndigo
        }
    }
}

// MARK: - Contre-indication (affichée en précaution, jamais un filtre silencieux)
/// Le profil ne capte pas la plupart de ces conditions (allergie, thyroïde,
/// hémochromatose…). Plutôt que masquer un produit, on affiche l'avertissement
/// et on laisse l'utilisateur / son médecin trancher.
enum Contraindication: String, CaseIterable, Equatable {
    case grossesse
    case allaitement
    case hemochromatose
    case hyperthyroidie
    case hypercalcemie
    case insuffisanceRenaleSevere = "insuffisance_renale_severe"
    case allergiePoisson = "allergie_poisson"

    /// Titre court de la précaution.
    var title: String {
        switch self {
        case .grossesse: return "Grossesse"
        case .allaitement: return "Allaitement"
        case .hemochromatose: return "Hémochromatose"
        case .hyperthyroidie: return "Thyroïde"
        case .hypercalcemie: return "Hypercalcémie"
        case .insuffisanceRenaleSevere: return "Reins"
        case .allergiePoisson: return "Allergie poisson"
        }
    }

    /// Message affiché à l'utilisateur.
    var warningLabel: String {
        switch self {
        case .grossesse: return "Demande l'avis de ton médecin ou ta sage-femme avant de te supplémenter."
        case .allaitement: return "Demande l'avis de ton médecin avant de te supplémenter pendant l'allaitement."
        case .hemochromatose: return "Déconseillé en cas d'hémochromatose (surcharge en fer)."
        case .hyperthyroidie: return "Déconseillé en cas d'hyperthyroïdie. Demande l'avis de ton médecin."
        case .hypercalcemie: return "Déconseillé en cas d'hypercalcémie."
        case .insuffisanceRenaleSevere: return "Prudence en cas d'insuffisance rénale sévère. Demande l'avis de ton médecin."
        case .allergiePoisson: return "Contient de l'huile de poisson. À éviter en cas d'allergie, préfère la version à base d'algues."
        }
    }
}

// MARK: - Supplement Product
struct SupplementProduct: Identifiable, Equatable {
    let id: String           // slug
    let name: String
    let nutrientID: NutrientID
    let brand: String
    let dosage: String
    /// Nombre de prises par jour (gélules/gouttes/dosettes). Sert au calcul de coût.
    let unitsPerDay: Int
    let timing: TimingSlot
    let price: Double         // EUR (prix de référence, hors promo)
    let unitsPerPackage: Int
    /// Fiche produit officielle de la marque (source « lien direct », option a).
    let productURL: String
    let isVegan: Bool
    let contraindications: [Contraindication]
    let antiInteractions: [String]
    let tier: ProductTier
    let whyBrand: String
    /// Date du dernier audit web du catalogue (prix / dosage / disponibilité).
    /// Tous les produits sont vérifiés en une passe → source unique dans
    /// `SupplementEngine.catalogVerifiedAt`. Exclu de l'init memberwise (défaut).
    let verifiedAt: String = SupplementEngine.catalogVerifiedAt

    /// Nombre de jours couverts par une boîte, en tenant compte des prises/jour.
    var daysPerPackage: Int {
        max(1, unitsPerPackage / max(1, unitsPerDay))
    }

    /// Coût journalier réel = prix × prises par jour / unités par boîte.
    var dailyCost: Double {
        price * Double(max(1, unitsPerDay)) / Double(max(1, unitsPerPackage))
    }

    var monthlyCost: Double {
        dailyCost * 30
    }

    enum ProductTier: String {
        case premium
        case value
    }
}

// MARK: - Recommendation
struct SupplementRecommendation: Identifiable {
    let id: String           // nutrient raw value
    let nutrientID: NutrientID
    let score: Int
    let priorityScore: Double
    let dietDifficulty: Int
    let whyText: String
    let premiumProduct: SupplementProduct?
    let valueProduct: SupplementProduct?

    var bestProduct: SupplementProduct? {
        premiumProduct ?? valueProduct
    }

    var nutrientLabel: String {
        SupplementEngine.nutrientLabel(for: nutrientID)
    }

    var nutrientEmoji: String {
        SupplementEngine.nutrientEmoji(for: nutrientID)
    }

    var nutrientColor: Color {
        Color.nutrientColor(for: nutrientID.rawValue)
    }
}

// MARK: - Interaction Warning
struct InteractionWarning: Identifiable {
    let id = UUID()
    let emoji: String
    let message: String
    let nutrients: [String]
    let severity: Severity

    enum Severity: String {
        case moderate
        case critical
    }
}

// MARK: - Cost Summary
struct CostSummary {
    let premiumTotal: Double
    let valueTotal: Double

    var minEstimate: Double { min(premiumTotal, valueTotal) }
    var maxEstimate: Double { max(premiumTotal, valueTotal) }

    var displayRange: String {
        let minStr = String(format: "%.0f", minEstimate)
        let maxStr = String(format: "%.0f", maxEstimate)
        if minStr == maxStr {
            return "\(minStr) EUR/mois"
        }
        return "\(minStr) - \(maxStr) EUR/mois"
    }
}

// MARK: - Schedule Group
struct ScheduleGroup: Identifiable {
    let id: String
    let label: String
    let icon: String
    let color: Color
    let products: [SupplementProduct]
}

// MARK: - Engine Result
struct SupplementEngineResult {
    let topRecommendations: [SupplementRecommendation]
    let schedule: [ScheduleGroup]
    let warnings: [InteractionWarning]
    let cost: CostSummary
}
