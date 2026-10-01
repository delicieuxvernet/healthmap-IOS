import Foundation

/// Value type that computes BMI, BMR, TDEE, and macros from a `UserProfile`.
///
/// Replaces the 5 scattered computed properties that were duplicated between
/// `DashboardViewModel` and `RecommendationsView`. Both now delegate to a
/// single `PhysicalMetrics` instance, keeping health calculations DRY and
/// trivially testable.
struct PhysicalMetrics {
    let bmi: Double?
    let bmiCategory: (label: String, color: String)
    let bmr: Int?
    let tdee: Int?
    let macros: (calories: Int, protein: Int, carbs: Int, fat: Int)?
    /// Ce que le poids souhaité change aux cibles du jour ; nil tant qu'aucun
    /// poids souhaité n'est réglé.
    let objectifPoids: ObjectifPoids?

    init(profile: UserProfile) {
        let computedBMI = HealthCalculator.calculateBMI(
            weightKg: profile.weightDouble,
            heightCm: profile.heightDouble
        )
        self.bmi = computedBMI
        self.bmiCategory = HealthCalculator.getBMICategory(computedBMI)

        let computedBMR = HealthCalculator.calculateBMR(
            gender: profile.gender.rawValue,
            weightKg: profile.weightDouble,
            heightCm: profile.heightDouble,
            age: profile.ageInt
        )
        self.bmr = computedBMR

        let computedTDEE = HealthCalculator.calculateTDEE(
            bmr: computedBMR,
            strengthTraining: profile.strengthTraining
        )
        self.tdee = computedTDEE

        // Un poids souhaité réglé donne le sens de l'objectif (perdre, prendre,
        // maintenir) ; sans lui, le premier objectif du questionnaire, comme
        // avant. Les formules, elles, ne changent pas.
        let objectifPoids = ObjectifPoids(profile: profile)
        self.objectifPoids = objectifPoids
        let objectifDeCalcul: String?
        if let objectifPoids {
            objectifDeCalcul = objectifPoids.objectifDeCalcul(principal: profile.goals.first)
        } else {
            objectifDeCalcul = profile.goals.first
        }

        self.macros = HealthCalculator.calculateMacros(
            tdee: computedTDEE,
            goal: objectifDeCalcul,
            weightKg: profile.weightDouble
        )
    }
}
