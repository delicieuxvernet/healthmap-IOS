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

        self.macros = HealthCalculator.calculateMacros(
            tdee: computedTDEE,
            goal: profile.goals.first,
            weightKg: profile.weightDouble
        )
    }
}
