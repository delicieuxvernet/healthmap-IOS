import Foundation

// MARK: - Red Flag (code-side, deterministic)
struct RedFlag: Identifiable, Equatable {
    let id: RedFlagID
    let urgency: Urgency
    let message: String
    let disclaimer: String

    /// Global disclaimer shown alongside any red flag display.
    static let disclaimer = "Ces signaux sont générés automatiquement à partir de tes réponses et ne constituent en aucun cas un diagnostic médical. Consulte un professionnel de santé pour toute décision médicale."

    init(id: RedFlagID, urgency: Urgency, message: String, disclaimer: String = "Information générale, ne remplace pas un avis médical") {
        self.id = id
        self.urgency = urgency
        self.message = message
        self.disclaimer = disclaimer
    }

    enum RedFlagID: String {
        case veganNoB12 = "vegan_no_b12"
        case pregnantNoFolate = "pregnant_no_folate"
        case pregnantSmoking = "pregnant_smoking"
        case tryingConceiveNoFolate = "trying_conceive_no_folate"
        case heavyPeriodsNoIron = "heavy_periods_no_iron"
        case heavyPeriodsPlantBased = "heavy_periods_plant_based"
        case unintentionalWeightLoss = "unintentional_weight_loss"
        case malabsorptionCondition = "malabsorption_condition"
        case ppiMetforminB12 = "ppi_metformin_b12"
        case elderlyPolypharmacy = "elderly_polypharmacy"
        case tinglingB12Risk = "tingling_b12_risk"
        case hairLossIronRisk = "hair_loss_iron_risk"
        case digestiveBleeding = "digestive_bleeding"
    }

    enum Urgency: String {
        case immediate
        case soon
        case routine
    }
}
