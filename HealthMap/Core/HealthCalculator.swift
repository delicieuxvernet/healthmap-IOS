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
        // Caddie rempli ("Faites vos courses") -> nouveau moteur de couverture.
        // Sinon, calcul historique ci-dessous (transition sûre, parité web).
        if !profile.groceries.isEmpty { return NutrientEngine.nutrientScores(profile: profile) }

        // Input validation: reject manifestly invalid profiles
        let w = profile.weightDouble
        let h = profile.heightDouble
        let a = profile.ageInt
        guard w >= 20, w <= 300, h >= 80, h <= 250, a >= 1, a <= 120 else {
            return [:]
        }

        var scores: [String: Int] = [:]
        for n in NutrientData.all { scores[n.id.rawValue] = 70 }

        let p = profile
        let age = p.ageInt
        let meat = p.meatPoultryInt
        let eggs = p.eggsPerWeekInt
        let fish = p.fattyFishInt
        let dairy = p.dairyServingsInt
        let fruit = p.fruitServingsInt
        let vegs = p.vegetableServingsInt
        let nuts = p.nutsPerWeekInt
        let seeds = p.seedsPerDayInt
        let legumes = p.legumesPerWeekInt
        let wholegrain = p.wholegrainPerWeekInt
        let isActive = p.isActive
        let isSmoker = p.isSmoker
        let sleepHours = p.sleepHoursDouble
        let waterL = p.waterLiters
        let bmi = calculateBMI(weightKg: p.weightDouble, heightCm: p.heightDouble)

        let caffeine = p.caffeineIntake.isEmpty ? "none" : p.caffeineIntake
        let caffeineWithMeals = p.caffeineWithMeals
        let screenBed = p.screenBeforeBed.isEmpty ? "short" : p.screenBeforeBed
        let snacking = p.snacking.isEmpty ? "sometimes" : p.snacking
        let ultraProcessed = p.ultraProcessedFrequency.isEmpty ? "sometimes" : p.ultraProcessedFrequency
        let hasReflux = p.digestiveConditions.contains("acid_reflux") || p.digestiveIssues.contains("acid_reflux")

        let medications = p.medications
        let conditions = p.digestiveConditions
        let periodFlow = p.periodFlow
        let pregnancyStatus = p.pregnancyStatus
        let cookingMethod = p.cookingMethod.isEmpty ? "mixed" : p.cookingMethod
        let homeCookedPct = p.homeCookedPct.isEmpty ? "mostly" : p.homeCookedPct
        let fermented = p.fermentedFoods.isEmpty ? "sometimes" : p.fermentedFoods
        let currentSupps = p.supplementsCurrent

        // ═══════ VITAMIN D ═══════
        if p.indoorWork == "yes" { scores["vitD", default: 70] -= 25 }
        let sun = ["none": -30, "very_little": -20, "some": -5, "moderate": 5, "plenty": 15]
        scores["vitD", default: 70] += sun[p.sunExposure] ?? 0
        if age > 70 { scores["vitD", default: 70] -= 15 }
        else if age > 50 { scores["vitD", default: 70] -= 10 }
        let skinPenalty = ["very_fair": 0, "fair": -3, "medium": -8, "olive": -15, "dark": -22]
        scores["vitD", default: 70] += skinPenalty[p.skinType] ?? 0
        if fish >= 3 { scores["vitD", default: 70] += 8 }
        if dairy >= 10 { scores["vitD", default: 70] += 5 }
        if let bmi, bmi > 30 { scores["vitD", default: 70] -= 8 }
        if sleepHours < 6 { scores["vitD", default: 70] -= 5 }

        // ═══════ VITAMIN B12 ═══════
        if meat == 0 && eggs == 0 && fish == 0 { scores["vitB12", default: 70] -= 45 }
        else if meat <= 2 && eggs <= 2 && fish == 0 { scores["vitB12", default: 70] -= 20 }
        else if meat >= 5 && eggs >= 3 { scores["vitB12", default: 70] += 10 }
        let alcoholB12 = ["none": 0, "rarely": 0, "moderate": -5, "regular": -15, "heavy": -25]
        scores["vitB12", default: 70] += alcoholB12[p.alcohol] ?? 0
        if p.eatLiver == "yes" { scores["vitB12", default: 70] += 15 }
        if age > 60 { scores["vitB12", default: 70] -= 10 }
        else if age > 50 { scores["vitB12", default: 70] -= 5 }
        if p.antibiotics == "yes" { scores["vitB12", default: 70] -= 5 }

        // ═══════ IRON ═══════
        if meat == 0 { scores["iron", default: 70] -= 30 }
        else if meat <= 3 { scores["iron", default: 70] -= 10 }
        else if meat >= 7 { scores["iron", default: 70] += 8 }
        if p.gender == .femme {
            if age < 50 { scores["iron", default: 70] -= 15 }
            else { scores["iron", default: 70] -= 5 }
        }
        if isActive { scores["iron", default: 70] -= 5 }
        if fruit >= 14 || vegs >= 5 { scores["iron", default: 70] += 5 }
        if caffeine == "heavy" { scores["iron", default: 70] -= 12 }
        else if caffeine == "moderate" { scores["iron", default: 70] -= 5 }
        if caffeineWithMeals && caffeine != "none" { scores["iron", default: 70] -= 10 }
        if hasReflux { scores["iron", default: 70] -= 8 }
        if legumes >= 3 { scores["iron", default: 70] += 5 }
        if p.eatLiver == "yes" { scores["iron", default: 70] += 10 }
        if let bmi, bmi < 18.5 { scores["iron", default: 70] -= 8 }
        if p.alcohol == "heavy" { scores["iron", default: 70] -= 8 }

        // ═══════ MAGNESIUM ═══════
        let stressMg = ["zen": 5, "relaxed": 0, "somewhat": -8, "very": -15, "explode": -20]
        scores["magnesium", default: 70] += stressMg[p.stressLevel] ?? 0
        if isActive { scores["magnesium", default: 70] -= 10 }
        if nuts >= 7 { scores["magnesium", default: 70] += 12 }
        else if nuts >= 3 { scores["magnesium", default: 70] += 5 }
        if p.breadType == "whole_grain" || p.breadType == "sourdough" { scores["magnesium", default: 70] += 10 }
        if sleepHours < 6 { scores["magnesium", default: 70] -= 8 }
        if caffeine == "heavy" { scores["magnesium", default: 70] -= 10 }
        else if caffeine == "moderate" { scores["magnesium", default: 70] -= 4 }
        // Triple Mg drain: stress + short sleep + screens
        if ["very", "explode"].contains(p.stressLevel) && sleepHours < 7 && ["long", "very_long"].contains(screenBed) {
            scores["magnesium", default: 70] -= 8
        }
        if p.lowCarbDiet == "yes" { scores["magnesium", default: 70] -= 8 }
        if legumes >= 3 { scores["magnesium", default: 70] += 5 }
        if wholegrain >= 5 { scores["magnesium", default: 70] += 5 }
        if ["regular", "heavy"].contains(p.alcohol) { scores["magnesium", default: 70] -= 8 }
        if waterL < 1 { scores["magnesium", default: 70] -= 5 }
        if age > 70 { scores["magnesium", default: 70] -= 8 }

        // ═══════ OMEGA-3 ═══════
        if fish >= 3 { scores["omega3", default: 70] += 20 }
        else if fish >= 2 { scores["omega3", default: 70] += 10 }
        else if fish == 1 { scores["omega3", default: 70] += 3 }
        else if fish == 0 { scores["omega3", default: 70] -= 25 }
        if seeds >= 2 { scores["omega3", default: 70] += 8 }
        else if seeds >= 1 { scores["omega3", default: 70] += 3 }
        if nuts >= 5 { scores["omega3", default: 70] += 4 }
        if ["souvent", "often", "constant"].contains(snacking) { scores["omega3", default: 70] -= 5 }
        if isSmoker { scores["omega3", default: 70] -= 8 }

        // ═══════ VITAMIN C ═══════
        if fruit >= 14 { scores["vitC", default: 70] += 20 }
        else if fruit >= 7 { scores["vitC", default: 70] += 5 }
        else if fruit < 4 { scores["vitC", default: 70] -= 20 }
        if vegs >= 5 { scores["vitC", default: 70] += 12 }
        else if vegs >= 3 { scores["vitC", default: 70] += 5 }
        else if vegs < 2 { scores["vitC", default: 70] -= 10 }
        if isSmoker { scores["vitC", default: 70] -= 25 }
        if ["very", "explode"].contains(p.stressLevel) { scores["vitC", default: 70] -= 5 }
        if ["regular", "heavy"].contains(p.alcohol) { scores["vitC", default: 70] -= 5 }
        if age > 65 { scores["vitC", default: 70] -= 5 }

        // ═══════ CALCIUM ═══════
        if dairy >= 14 { scores["calcium", default: 70] += 20 }
        else if dairy >= 7 { scores["calcium", default: 70] += 5 }
        else if dairy < 3 { scores["calcium", default: 70] -= 25 }
        if vegs >= 5 { scores["calcium", default: 70] += 5 }
        if legumes >= 3 { scores["calcium", default: 70] += 3 }
        if age > 50 { scores["calcium", default: 70] -= 8 }
        if p.lowCarbDiet == "yes" { scores["calcium", default: 70] -= 5 }
        if isSmoker { scores["calcium", default: 70] -= 5 }
        if let bmi, bmi < 18.5 { scores["calcium", default: 70] -= 8 }
        if isActive { scores["calcium", default: 70] += 5 }

        // ═══════ ZINC ═══════
        if meat == 0 { scores["zinc", default: 70] -= 25 }
        else if meat <= 3 { scores["zinc", default: 70] -= 10 }
        else if meat >= 7 { scores["zinc", default: 70] += 8 }
        if isActive { scores["zinc", default: 70] -= 5 }
        if nuts >= 5 { scores["zinc", default: 70] += 8 }
        if eggs >= 5 { scores["zinc", default: 70] += 5 }
        if legumes >= 3 { scores["zinc", default: 70] += 3 }
        if p.breadType == "sourdough" { scores["zinc", default: 70] += 5 }
        if age > 65 { scores["zinc", default: 70] -= 5 }
        if ["regular", "heavy"].contains(p.alcohol) { scores["zinc", default: 70] -= 5 }
        if p.bloating == "yes" { scores["zinc", default: 70] -= 3 }

        // ═══════ IODINE ═══════
        // mirror health.js:473 — undefined/non renseigné = neutre, pas de penalite
        // (isEmpty traite auparavant a tort comme "no", trouve par le test de
        // parite cross-repo du 2026-07-05)
        if p.iodizedSalt == "no" {
            scores["iodine", default: 70] -= 12
        } else if p.iodizedSalt == "yes" && p.saltLevel == "none" {
            scores["iodine", default: 70] -= 8
        } else if p.iodizedSalt == "yes" && ["moderate", "a_lot"].contains(p.saltLevel) {
            scores["iodine", default: 70] += 8
        }
        if fish >= 2 { scores["iodine", default: 70] += 12 }
        else if fish >= 1 { scores["iodine", default: 70] += 5 }
        if dairy >= 7 { scores["iodine", default: 70] += 10 }
        else if dairy >= 3 { scores["iodine", default: 70] += 5 }
        if eggs >= 3 { scores["iodine", default: 70] += 5 }
        if p.dietType == "sans_gluten" { scores["iodine", default: 70] -= 5 }

        // ═══════ FIBER ═══════
        if p.breadType == "white" { scores["fiber", default: 70] -= 15 }
        else if p.breadType == "whole_grain" || p.breadType == "sourdough" { scores["fiber", default: 70] += 10 }
        if fruit >= 14 { scores["fiber", default: 70] += 15 }
        else if fruit >= 7 { scores["fiber", default: 70] += 5 }
        else if fruit < 4 { scores["fiber", default: 70] -= 10 }
        if vegs >= 5 { scores["fiber", default: 70] += 12 }
        else if vegs >= 3 { scores["fiber", default: 70] += 5 }
        else if vegs < 2 { scores["fiber", default: 70] -= 10 }
        if legumes >= 5 { scores["fiber", default: 70] += 12 }
        else if legumes >= 2 { scores["fiber", default: 70] += 5 }
        if wholegrain >= 7 { scores["fiber", default: 70] += 10 }
        else if wholegrain >= 3 { scores["fiber", default: 70] += 5 }
        if p.lowCarbDiet == "yes" { scores["fiber", default: 70] -= 10 }
        if seeds >= 2 { scores["fiber", default: 70] += 8 }
        else if seeds >= 1 { scores["fiber", default: 70] += 3 }
        if p.bloating == "yes" && p.antibiotics == "yes" { scores["fiber", default: 70] -= 5 }
        if ["often", "constant", "souvent"].contains(snacking) { scores["fiber", default: 70] -= 5 }
        if ["often", "daily"].contains(ultraProcessed) {
            scores["fiber", default: 70] -= 8
            scores["zinc", default: 70] -= 5
        }
        if waterL < 1 { scores["fiber", default: 70] -= 5 }
        if nuts >= 5 { scores["fiber", default: 70] += 3 }

        // ═══════ MEDICATION INTERACTIONS ═══════
        if medications.contains("ppi") {
            scores["magnesium", default: 70] -= 10; scores["vitB12", default: 70] -= 12; scores["iron", default: 70] -= 8; scores["calcium", default: 70] -= 8
        }
        if medications.contains("metformin") { scores["vitB12", default: 70] -= 15 }
        if medications.contains("oral_contraceptive") { scores["magnesium", default: 70] -= 5; scores["zinc", default: 70] -= 5 }
        if medications.contains("diuretics") { scores["magnesium", default: 70] -= 10; scores["zinc", default: 70] -= 5 }

        // ═══════ COOKING & LIFESTYLE ═══════
        if cookingMethod == "boiled" { scores["vitC", default: 70] -= 10; scores["fiber", default: 70] -= 3 }
        if ["mostly_out", "rarely"].contains(homeCookedPct) {
            scores["fiber", default: 70] -= 8; scores["zinc", default: 70] -= 5; scores["magnesium", default: 70] -= 5
        }
        if fermented == "never" { scores["calcium", default: 70] -= 3 }

        // Period flow
        if periodFlow == "very_heavy" { scores["iron", default: 70] -= 15 }
        else if periodFlow == "heavy" { scores["iron", default: 70] -= 8 }

        // Pregnancy
        if pregnancyStatus == "pregnant" {
            scores["iron", default: 70] -= 15; scores["iodine", default: 70] -= 10; scores["calcium", default: 70] -= 5
        } else if pregnancyStatus == "breastfeeding" {
            scores["iodine", default: 70] -= 8; scores["calcium", default: 70] -= 5
        }

        // Malabsorption conditions
        if conditions.contains(where: { ["celiac", "crohns_uc"].contains($0) }) {
            scores["iron", default: 70] -= 15; scores["vitB12", default: 70] -= 10; scores["calcium", default: 70] -= 10
            scores["zinc", default: 70] -= 10; scores["vitD", default: 70] -= 10
        }

        // ═══════ SUPPLEMENT BOOST ═══════
        if currentSupps.contains("vitD") { scores["vitD", default: 70] += 25 }
        if currentSupps.contains("omega3") { scores["omega3", default: 70] += 20 }
        if currentSupps.contains("magnesium") { scores["magnesium", default: 70] += 20 }
        if currentSupps.contains("iron") { scores["iron", default: 70] += 15 }
        if currentSupps.contains("b12") { scores["vitB12", default: 70] += 20 }
        if currentSupps.contains("zinc") { scores["zinc", default: 70] += 15 }
        if currentSupps.contains("folate") { scores["fiber", default: 70] += 3 }
        if currentSupps.contains("probiotics") { scores["fiber", default: 70] += 5 }
        if currentSupps.contains("multivitamin") {
            scores["vitD", default: 70] += 10; scores["vitB12", default: 70] += 15; scores["iron", default: 70] += 8
            scores["zinc", default: 70] += 8; scores["vitC", default: 70] += 10; scores["iodine", default: 70] += 10
        }

        // ═══════ DIET TYPE CORRECTIONS ═══════
        if p.dietType == "vegan" {
            scores["vitB12", default: 70] -= 30; scores["iron", default: 70] -= 15; scores["zinc", default: 70] -= 15
            scores["omega3", default: 70] -= 10; scores["calcium", default: 70] -= 10; scores["iodine", default: 70] -= 8
        } else if p.dietType == "vegetarien" {
            scores["vitB12", default: 70] -= 15; scores["iron", default: 70] -= 8; scores["zinc", default: 70] -= 8
        }

        // ═══════ CLAMP ALL 0-100 ═══════
        for key in scores.keys {
            scores[key] = max(0, min(100, scores[key]!))
        }

        return scores
    }
}
