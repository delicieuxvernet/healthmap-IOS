import Foundation

// MARK: - Health Calculator (EXACT translation of health.js)
// Every penalty, bonus, and formula is identical to the web version.
// Scores are DETERMINISTIC — same profile = same scores, always.

enum HealthCalculator {

    // MARK: - BMI (Mifflin-St Jeor)
    static func calculateBMI(weightKg: Double, heightCm: Double) -> Double? {
        guard weightKg > 0, heightCm > 0 else { return nil }
        let heightM = heightCm / 100
        return (weightKg / (heightM * heightM) * 10).rounded() / 10
    }

    static func getBMICategory(_ bmi: Double?) -> (label: String, color: String) {
        guard let bmi else { return ("-", "text-ink-muted") }
        if bmi < 18.5 { return ("Insuffisance pondérale", "text-accent-blue") }
        if bmi < 25 { return ("Poids normal", "text-brand-500") }
        if bmi < 30 { return ("Surpoids", "text-amber-500") }
        return ("Obésité", "text-red-500")
    }

    // MARK: - BMR (Mifflin-St Jeor)
    static func calculateBMR(gender: String, weightKg: Double, heightCm: Double, age: Int) -> Int? {
        guard weightKg > 0, heightCm > 0, age > 0 else { return nil }
        if gender == "homme" {
            return Int((10 * weightKg + 6.25 * heightCm - 5 * Double(age) + 5).rounded())
        }
        return Int((10 * weightKg + 6.25 * heightCm - 5 * Double(age) - 161).rounded())
    }

    // MARK: - TDEE
    private static let activityMultipliers: [String: Double] = [
        "none": 1.2, "light": 1.375, "moderate": 1.55, "regular": 1.725, "intense": 1.9,
    ]

    static func calculateTDEE(bmr: Int?, strengthTraining: String) -> Int? {
        guard let bmr else { return nil }
        let mult = activityMultipliers[strengthTraining] ?? 1.2
        return Int((Double(bmr) * mult).rounded())
    }

    // MARK: - Macros
    static func calculateMacros(tdee: Int?, goal: String?, weightKg: Double) -> (calories: Int, protein: Int, carbs: Int, fat: Int)? {
        guard let tdee else { return nil }
        let w = weightKg > 0 ? weightKg : 70
        var adjustedTdee = tdee

        let proteinPerKg: Double
        if goal == "prise_masse" || goal == "muscle" {
            adjustedTdee = tdee + 300
            proteinPerKg = 1.8
        } else if goal == "perte_poids" {
            adjustedTdee = tdee - 400
            proteinPerKg = 1.6
        } else if goal == "performance" {
            proteinPerKg = 1.4
        } else {
            proteinPerKg = 1.0
        }

        let protein = Int((w * proteinPerKg).rounded())
        let proteinCals = protein * 4
        let fatCals = Int((Double(adjustedTdee) * 0.28).rounded())
        let fat = Int((Double(fatCals) / 9).rounded())
        let carbs = max(0, Int((Double(adjustedTdee - proteinCals - fatCals) / 4).rounded()))

        return (calories: adjustedTdee, protein: protein, carbs: carbs, fat: fat)
    }

    // MARK: - Health Score (0-100)
    static func calculateHealthScore(profile: UserProfile) -> Int {
        // Caddie rempli ("Faites vos courses") -> nouveau moteur. Sinon, calcul
        // historique ci-dessous (transition sûre, parité web préservée).
        if !profile.groceries.isEmpty { return NutrientEngine.wellnessScore(profile: profile) }

        // Input validation: reject manifestly invalid profiles
        let w = profile.weightDouble
        let h = profile.heightDouble
        let a = profile.ageInt
        guard w >= 20, w <= 300, h >= 80, h <= 250, a >= 1, a <= 120 else {
            return 0
        }

        var score = 50

        // Activity
        let activityScores = ["none": 0, "light": 5, "moderate": 15, "regular": 20, "intense": 20]
        score += activityScores[profile.strengthTraining] ?? 0

        // BMI
        if let bmi = calculateBMI(weightKg: profile.weightDouble, heightCm: profile.heightDouble) {
            if bmi >= 18.5 && bmi < 25 { score += 15 }
            else if bmi >= 25 && bmi < 30 { score += 5 }
            else if bmi < 18.5 { score -= 5 }
        }

        // Stress
        let stressScores = ["zen": 5, "relaxed": 3, "somewhat": 0, "very": -5, "explode": -10]
        score += stressScores[profile.stressLevel] ?? 0

        // Wake feeling
        let wakeScores = ["great": 10, "good": 7, "ok": 3, "bad": -2, "terrible": -5]
        score += wakeScores[profile.wakeFeeling] ?? 0

        // Sleep hours
        let sleepScores = ["4": -8, "5.5": -4, "6.5": 0, "7.5": 5, "8.5": 5, "10": 0]
        score += sleepScores[profile.sleepHours] ?? 0

        // Water
        let waterScores = ["0.75": -5, "1.25": -2, "1.75": 2, "2.25": 4, "3": 4]
        score += waterScores[profile.waterIntake] ?? 0

        // Smoking & bloating
        if profile.isSmoker { score -= 10 }
        if profile.bloating == "yes" { score -= 3 }
        if profile.antibiotics == "yes" { score -= 3 }

        // Vegetables
        let vegs = profile.vegetableServingsInt
        if vegs >= 5 { score += 5 } else if vegs < 2 { score -= 5 }

        // Fruits
        let fruits = profile.fruitServingsInt
        if fruits >= 14 { score += 3 } else if fruits < 4 { score -= 3 }

        // Alcohol
        let alcoholScores = ["none": 3, "rarely": 0, "moderate": -3, "regular": -7, "heavy": -12]
        score += alcoholScores[profile.alcohol] ?? 0

        // Meals per day
        let mealScores = ["2": 0, "3": 3, "4": 2, "5+": 1]
        score += mealScores[profile.mealsPerDay] ?? 0

        // Snacking
        let snackScores = ["never": 3, "jamais": 3, "sometimes": 0, "parfois": 0, "often": -4, "souvent": -4, "constant": -6]
        score += snackScores[profile.snacking] ?? 0

        // Caffeine
        let cafScores = ["none": 2, "light": 0, "moderate": -2, "heavy": -5]
        score += cafScores[profile.caffeineIntake] ?? 0

        // Screen before bed
        let screenScores = ["none": 3, "short": 1, "moderate": -1, "long": -3, "very_long": -5]
        score += screenScores[profile.screenBeforeBed] ?? 0

        // Sleep duration (v6 key, scored only if sleepHours was not set — avoids double-scoring, mirror health.js:148-154)
        if profile.sleepHours.isEmpty {
            let sd = Double(profile.sleepDuration) ?? 0
            if sd >= 7 && sd <= 9 { score += 5 }
            else if sd >= 6 { score += 2 }
            else if sd > 0 && sd < 6 { score -= 5 }
        }

        // Ultra-processed
        let upfScores = ["never": 5, "rarely": 2, "sometimes": 0, "often": -5, "daily": -8]
        score += upfScores[profile.ultraProcessedFrequency] ?? 0

        // Meal frequency (v6 key, scored only if mealsPerDay was not set — avoids double-scoring, mirror health.js:160-164)
        if profile.mealsPerDay.isEmpty {
            let mealNewScores = ["one": -5, "two": -2, "three": 3, "four_plus": 2, "irregular": -4]
            score += mealNewScores[profile.mealFrequency] ?? 0
        }

        // Diet diversity
        let diversityItems: [Bool] = [
            profile.fattyFishInt > 0, profile.meatPoultryInt > 0,
            profile.eggsPerWeekInt > 0, profile.legumesPerWeekInt > 0,
            profile.nutsPerWeekInt > 0, profile.dairyServingsInt > 0,
            profile.wholegrainPerWeekInt > 0, profile.seedsPerDayInt > 0,
        ]
        let diversityCount = diversityItems.filter { $0 }.count
        if diversityCount >= 7 { score += 5 }
        else if diversityCount >= 5 { score += 3 }
        else if diversityCount <= 2 { score -= 5 }

        return max(0, min(100, score))
    }

    // MARK: - Nutrient Scores (0-100 per nutrient)
    /// Returns a dictionary of [nutrientID: score] — DETERMINISTIC
    /// Returns empty dictionary for manifestly invalid profiles.
    static func analyzeNutrientScores(profile: UserProfile) -> [String: Int] {
        // Une seule arithmetique dans le projet : le registre porte le calcul
        // ET le nom de chaque facteur (NutrientLedger.swift), le score n'en
        // est que la somme bornee. Le caddie et les gardes de profil sont
        // traites la-bas, a l'identique de ce que cette fonction faisait.
        registreApports(profile: profile).mapValues(\.score)
    }
}
