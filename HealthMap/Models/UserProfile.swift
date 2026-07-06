import Foundation

// MARK: - User Profile (mirrors questionnaire_data JSONB in Supabase)
struct UserProfile: Codable, Equatable {
    // Pathway
    var pathway: Pathway = .express
    var completed: Bool = false

    // Section 1: Profil
    var goals: [String] = []
    var firstName: String = ""
    var age: String = ""
    var gender: Gender = .homme
    var height: String = ""
    var weight: String = ""
    var weightTrend: String = ""
    /// Morphology avatar chosen by the user, e.g. "av_m_w45_m55".
    /// Empty until the user picks one in the avatar selection step.
    var avatarKey: String = ""

    // Section 2: Mode de vie
    var indoorWork: String = ""
    var sunExposure: String = ""
    var skinType: String = ""
    var strengthTraining: String = ""

    // Section 3: Sante
    var stressLevel: String = ""
    var sleepHours: String = ""
    var sleepDuration: String = ""
    var wakeFeeling: String = ""
    var screenBeforeBed: String = ""
    var caffeineIntake: String = ""
    var caffeineTiming: String = ""
    var waterIntake: String = ""
    var smoking: SmokingValue = .no
    var alcohol: String = ""
    var bloating: String = ""
    var antibiotics: String = ""

    // Section 4: Nutrition
    var dietType: String = "omnivore"
    var mealsPerDay: String = ""
    var mealFrequency: String = ""
    var homeCookedPct: String = ""
    var cookingMethod: String = ""
    var vegetableServings: String = ""
    var fruitServings: String = ""
    var fattyFish: String = ""
    var meatPoultry: String = ""
    var eggsPerWeek: String = ""
    var dairyServings: String = ""
    var legumesPerWeek: String = ""
    var nutsPerWeek: String = ""
    var seedsPerDay: String = ""
    var wholegrainPerWeek: String = ""
    var breadType: String = ""
    var fermentedFoods: String = ""
    var ultraProcessedFrequency: String = ""
    var snacking: String = ""
    var saltLevel: String = ""
    var iodizedSalt: String = ""
    var eatLiver: String = ""
    var lowCarbDiet: String = ""
    var supplementsCurrent: [String] = []

    /// "Faites vos courses" — caddie de l'utilisateur : id d'aliment (voir
    /// `GroceryCatalog`) -> nombre de portions par semaine. Source détaillée qui
    /// remplacera à terme les quantités chiffrées (fruitServings, fattyFish, …).
    /// Alimente le moteur de score et le prompt IA. Vide tant que le flux caddie
    /// n'est pas rempli.
    var groceries: [String: Int] = [:]

    /// Photo « départ » des 10 scores nutriments (0-100) figée au tout premier
    /// bilan. Décodée de la colonne jsonb `baseline_nutrient_scores`. `nil` tant
    /// qu'aucune baseline n'a encore été capturée (capture one-time côté
    /// DashboardViewModel). Sert de socle « départ » à la barre de couverture.
    var baselineNutrientScores: [String: Int]? = nil

    // Section 5: Symptomes
    var symptoms: [String] = []

    // Section 6: Medical
    var medications: [String] = []
    var digestiveConditions: [String] = []
    var digestiveIssues: [String] = []
    var periodFlow: String = "na"
    var pregnancyStatus: String = "na"

    // Precisions (optional detail questions)
    var precisions: Precisions?

    // MARK: - Nested Types

    enum Pathway: String, Codable {
        case express
        case complet
    }

    enum Gender: String, Codable {
        case homme
        case femme
    }

    /// SmokingValue handles dual encoding from web and iOS:
    /// - Web app stores smoking as a boolean (`true`/`false`) in older profiles
    ///   and as a string (`"yes"`/`"no"`) in newer ones.
    /// - iOS always writes string values (`"yes"`/`"no"`).
    /// The custom Codable implementation decodes both formats transparently
    /// so profiles from either platform are handled correctly.
    enum SmokingValue: Codable, Equatable {
        case bool(Bool)
        case string(String)

        var isSmoker: Bool {
            switch self {
            case .bool(let v): return v
            case .string(let v): return v == "yes" || v == "true"
            }
        }

        static let no = SmokingValue.bool(false)
        static let yes = SmokingValue.bool(true)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let boolVal = try? container.decode(Bool.self) {
                self = .bool(boolVal)
            } else if let strVal = try? container.decode(String.self) {
                self = .string(strVal)
            } else {
                self = .bool(false)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .bool(let v): try container.encode(v)
            case .string(let v): try container.encode(v)
            }
        }
    }

    struct Precisions: Codable, Equatable {
        var caffeineTiming: [String]?
        // Mirrors web Home.jsx precisions.* keys.
        // The Edge Function (generate-analysis) already accepts these under
        // `precisions.vegetables`, `precisions.fruits`, etc.
        var vegetables: [String]?
        var fruits: [String]?
        var meat: [String]?
        var dairy: [String]?
        var grains: [String]?

        // Legacy aliases kept for backward compatibility with older payloads.
        var vegetableDetails: [String]?
        var fruitDetails: [String]?
        var meatDetails: [String]?

        enum CodingKeys: String, CodingKey {
            case caffeineTiming = "caffeine_timing"
            case vegetables
            case fruits
            case meat
            case dairy
            case grains
            case vegetableDetails = "vegetable_details"
            case fruitDetails = "fruit_details"
            case meatDetails = "meat_details"
        }
    }

    // MARK: - Helpers

    var ageInt: Int { Int(age) ?? 30 }
    var weightDouble: Double { Double(weight) ?? 70 }
    var heightDouble: Double { Double(height) ?? 170 }

    var fattyFishInt: Int { Int(fattyFish) ?? 0 }
    var meatPoultryInt: Int { Int(meatPoultry) ?? 0 }
    var eggsPerWeekInt: Int { Int(eggsPerWeek) ?? 0 }
    var dairyServingsInt: Int { Int(dairyServings) ?? 0 }
    var fruitServingsInt: Int { Int(fruitServings) ?? 0 }
    var vegetableServingsInt: Int { Int(vegetableServings) ?? 0 }
    var nutsPerWeekInt: Int { Int(nutsPerWeek) ?? 0 }
    var seedsPerDayInt: Int { Int(seedsPerDay) ?? 0 }
    var legumesPerWeekInt: Int { Int(legumesPerWeek) ?? 0 }
    var wholegrainPerWeekInt: Int { Int(wholegrainPerWeek) ?? 0 }

    var isSmoker: Bool { smoking.isSmoker }
    var isActive: Bool { ["regular", "intense"].contains(strengthTraining) }
    var isVegan: Bool { dietType == "vegan" }
    var isVegetarian: Bool { ["vegetarien", "vegetarian", "vegan"].contains(dietType) }

    var sleepHoursDouble: Double {
        Double(sleepDuration) ?? Double(sleepHours) ?? 7
    }

    var waterLiters: Double {
        Double(waterIntake) ?? 1.5
    }

    var caffeineWithMeals: Bool {
        // Check simple caffeineTiming field first (iOS questionnaire)
        if caffeineTiming == "with_meals" || caffeineTiming == "both" { return true }
        // Fallback to web-style precisions
        let timing = precisions?.caffeineTiming ?? []
        return timing.contains("with_breakfast") || timing.contains("with_lunch")
    }

    // MARK: - Default empty profile
    static let empty = UserProfile()

    // MARK: - Codable (with legacy field migration)
    // Custom init supports backward compatibility with older payloads where
    // `supplementsCurrent` was stored under the legacy key `supplements`.
    // All fields use `decodeIfPresent` with safe defaults so partial payloads
    // from older schema versions still decode successfully.

    init() {}

    private enum CodingKeys: String, CodingKey {
        case pathway, completed
        case goals, firstName, age, gender, height, weight, weightTrend, avatarKey
        case indoorWork, sunExposure, skinType, strengthTraining
        case stressLevel, sleepHours, sleepDuration, wakeFeeling, screenBeforeBed
        case caffeineIntake, caffeineTiming, waterIntake, smoking, alcohol, bloating, antibiotics
        case dietType, mealsPerDay, mealFrequency, homeCookedPct, cookingMethod
        case vegetableServings, fruitServings, fattyFish, meatPoultry, eggsPerWeek
        case dairyServings, legumesPerWeek, nutsPerWeek, seedsPerDay, wholegrainPerWeek
        case breadType, fermentedFoods, ultraProcessedFrequency, snacking, saltLevel
        case iodizedSalt, eatLiver, lowCarbDiet, supplementsCurrent, groceries
        case symptoms, medications, digestiveConditions, digestiveIssues
        case periodFlow, pregnancyStatus, precisions
        // Legacy field (decoded only — never encoded)
        case supplementsLegacy = "supplements"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        pathway = (try? c.decode(Pathway.self, forKey: .pathway)) ?? .express
        completed = (try? c.decode(Bool.self, forKey: .completed)) ?? false

        goals = (try? c.decode([String].self, forKey: .goals)) ?? []
        firstName = (try? c.decode(String.self, forKey: .firstName)) ?? ""
        age = (try? c.decode(String.self, forKey: .age)) ?? ""
        gender = (try? c.decode(Gender.self, forKey: .gender)) ?? .homme
        height = (try? c.decode(String.self, forKey: .height)) ?? ""
        weight = (try? c.decode(String.self, forKey: .weight)) ?? ""
        weightTrend = (try? c.decode(String.self, forKey: .weightTrend)) ?? ""
        avatarKey = (try? c.decode(String.self, forKey: .avatarKey)) ?? ""

        indoorWork = (try? c.decode(String.self, forKey: .indoorWork)) ?? ""
        sunExposure = (try? c.decode(String.self, forKey: .sunExposure)) ?? ""
        skinType = (try? c.decode(String.self, forKey: .skinType)) ?? ""
        strengthTraining = (try? c.decode(String.self, forKey: .strengthTraining)) ?? ""

        stressLevel = (try? c.decode(String.self, forKey: .stressLevel)) ?? ""
        sleepHours = (try? c.decode(String.self, forKey: .sleepHours)) ?? ""
        sleepDuration = (try? c.decode(String.self, forKey: .sleepDuration)) ?? ""
        wakeFeeling = (try? c.decode(String.self, forKey: .wakeFeeling)) ?? ""
        screenBeforeBed = (try? c.decode(String.self, forKey: .screenBeforeBed)) ?? ""
        caffeineIntake = (try? c.decode(String.self, forKey: .caffeineIntake)) ?? ""
        caffeineTiming = (try? c.decode(String.self, forKey: .caffeineTiming)) ?? ""
        waterIntake = (try? c.decode(String.self, forKey: .waterIntake)) ?? ""
        smoking = (try? c.decode(SmokingValue.self, forKey: .smoking)) ?? .no
        alcohol = (try? c.decode(String.self, forKey: .alcohol)) ?? ""
        bloating = (try? c.decode(String.self, forKey: .bloating)) ?? ""
        antibiotics = (try? c.decode(String.self, forKey: .antibiotics)) ?? ""

        dietType = (try? c.decode(String.self, forKey: .dietType)) ?? "omnivore"
        mealsPerDay = (try? c.decode(String.self, forKey: .mealsPerDay)) ?? ""
        mealFrequency = (try? c.decode(String.self, forKey: .mealFrequency)) ?? ""
        homeCookedPct = (try? c.decode(String.self, forKey: .homeCookedPct)) ?? ""
        cookingMethod = (try? c.decode(String.self, forKey: .cookingMethod)) ?? ""
        vegetableServings = (try? c.decode(String.self, forKey: .vegetableServings)) ?? ""
        fruitServings = (try? c.decode(String.self, forKey: .fruitServings)) ?? ""
        fattyFish = (try? c.decode(String.self, forKey: .fattyFish)) ?? ""
        meatPoultry = (try? c.decode(String.self, forKey: .meatPoultry)) ?? ""
        eggsPerWeek = (try? c.decode(String.self, forKey: .eggsPerWeek)) ?? ""
        dairyServings = (try? c.decode(String.self, forKey: .dairyServings)) ?? ""
        legumesPerWeek = (try? c.decode(String.self, forKey: .legumesPerWeek)) ?? ""
        nutsPerWeek = (try? c.decode(String.self, forKey: .nutsPerWeek)) ?? ""
        seedsPerDay = (try? c.decode(String.self, forKey: .seedsPerDay)) ?? ""
        wholegrainPerWeek = (try? c.decode(String.self, forKey: .wholegrainPerWeek)) ?? ""
        breadType = (try? c.decode(String.self, forKey: .breadType)) ?? ""
        fermentedFoods = (try? c.decode(String.self, forKey: .fermentedFoods)) ?? ""
        ultraProcessedFrequency = (try? c.decode(String.self, forKey: .ultraProcessedFrequency)) ?? ""
        snacking = (try? c.decode(String.self, forKey: .snacking)) ?? ""
        saltLevel = (try? c.decode(String.self, forKey: .saltLevel)) ?? ""
        iodizedSalt = (try? c.decode(String.self, forKey: .iodizedSalt)) ?? ""
        eatLiver = (try? c.decode(String.self, forKey: .eatLiver)) ?? ""
        lowCarbDiet = (try? c.decode(String.self, forKey: .lowCarbDiet)) ?? ""

        // Supplements — migrate legacy `supplements` key if present and
        // new `supplementsCurrent` is empty/absent.
        let current = (try? c.decode([String].self, forKey: .supplementsCurrent)) ?? []
        if !current.isEmpty {
            supplementsCurrent = current
        } else {
            supplementsCurrent = (try? c.decode([String].self, forKey: .supplementsLegacy)) ?? []
        }

        groceries = (try? c.decode([String: Int].self, forKey: .groceries)) ?? [:]

        symptoms = (try? c.decode([String].self, forKey: .symptoms)) ?? []
        medications = (try? c.decode([String].self, forKey: .medications)) ?? []
        digestiveConditions = (try? c.decode([String].self, forKey: .digestiveConditions)) ?? []
        digestiveIssues = (try? c.decode([String].self, forKey: .digestiveIssues)) ?? []
        periodFlow = (try? c.decode(String.self, forKey: .periodFlow)) ?? "na"
        pregnancyStatus = (try? c.decode(String.self, forKey: .pregnancyStatus)) ?? "na"
        precisions = try? c.decode(Precisions.self, forKey: .precisions)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(pathway, forKey: .pathway)
        try c.encode(completed, forKey: .completed)

        try c.encode(goals, forKey: .goals)
        try c.encode(firstName, forKey: .firstName)
        try c.encode(age, forKey: .age)
        try c.encode(gender, forKey: .gender)
        try c.encode(height, forKey: .height)
        try c.encode(weight, forKey: .weight)
        try c.encode(weightTrend, forKey: .weightTrend)
        try c.encode(avatarKey, forKey: .avatarKey)

        try c.encode(indoorWork, forKey: .indoorWork)
        try c.encode(sunExposure, forKey: .sunExposure)
        try c.encode(skinType, forKey: .skinType)
        try c.encode(strengthTraining, forKey: .strengthTraining)

        try c.encode(stressLevel, forKey: .stressLevel)
        try c.encode(sleepHours, forKey: .sleepHours)
        try c.encode(sleepDuration, forKey: .sleepDuration)
        try c.encode(wakeFeeling, forKey: .wakeFeeling)
        try c.encode(screenBeforeBed, forKey: .screenBeforeBed)
        try c.encode(caffeineIntake, forKey: .caffeineIntake)
        try c.encode(caffeineTiming, forKey: .caffeineTiming)
        try c.encode(waterIntake, forKey: .waterIntake)
        try c.encode(smoking, forKey: .smoking)
        try c.encode(alcohol, forKey: .alcohol)
        try c.encode(bloating, forKey: .bloating)
        try c.encode(antibiotics, forKey: .antibiotics)

        try c.encode(dietType, forKey: .dietType)
        try c.encode(mealsPerDay, forKey: .mealsPerDay)
        try c.encode(mealFrequency, forKey: .mealFrequency)
        try c.encode(homeCookedPct, forKey: .homeCookedPct)
        try c.encode(cookingMethod, forKey: .cookingMethod)
        try c.encode(vegetableServings, forKey: .vegetableServings)
        try c.encode(fruitServings, forKey: .fruitServings)
        try c.encode(fattyFish, forKey: .fattyFish)
        try c.encode(meatPoultry, forKey: .meatPoultry)
        try c.encode(eggsPerWeek, forKey: .eggsPerWeek)
        try c.encode(dairyServings, forKey: .dairyServings)
        try c.encode(legumesPerWeek, forKey: .legumesPerWeek)
        try c.encode(nutsPerWeek, forKey: .nutsPerWeek)
        try c.encode(seedsPerDay, forKey: .seedsPerDay)
        try c.encode(wholegrainPerWeek, forKey: .wholegrainPerWeek)
        try c.encode(breadType, forKey: .breadType)
        try c.encode(fermentedFoods, forKey: .fermentedFoods)
        try c.encode(ultraProcessedFrequency, forKey: .ultraProcessedFrequency)
        try c.encode(snacking, forKey: .snacking)
        try c.encode(saltLevel, forKey: .saltLevel)
        try c.encode(iodizedSalt, forKey: .iodizedSalt)
        try c.encode(eatLiver, forKey: .eatLiver)
        try c.encode(lowCarbDiet, forKey: .lowCarbDiet)
        try c.encode(supplementsCurrent, forKey: .supplementsCurrent)
        try c.encode(groceries, forKey: .groceries)

        try c.encode(symptoms, forKey: .symptoms)
        try c.encode(medications, forKey: .medications)
        try c.encode(digestiveConditions, forKey: .digestiveConditions)
        try c.encode(digestiveIssues, forKey: .digestiveIssues)
        try c.encode(periodFlow, forKey: .periodFlow)
        try c.encode(pregnancyStatus, forKey: .pregnancyStatus)
        try c.encodeIfPresent(precisions, forKey: .precisions)
    }
}

// MARK: - Supabase Profile Row
struct ProfileRow: Codable {
    let id: String
    var email: String?
    var firstName: String?
    var questionnaireData: UserProfile?
    var aiAnalysis: AIAnalysisResponse?
    /// Colonne jsonb `baseline_nutrient_scores` (sœur de `questionnaire_data`,
    /// pas imbriquée dedans). Photo « départ » des scores nutriments figée au
    /// 1er bilan. Fusionnée dans `UserProfile.baselineNutrientScores` au chargement.
    var baselineNutrientScores: [String: Int]?
    var tier: String?
    var subscriptionStatus: String?
    var cancelAtPeriodEnd: Bool?
    var currentPeriodEnd: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case firstName = "first_name"
        case questionnaireData = "questionnaire_data"
        case aiAnalysis = "ai_analysis"
        case baselineNutrientScores = "baseline_nutrient_scores"
        case tier
        case subscriptionStatus = "subscription_status"
        case cancelAtPeriodEnd = "cancel_at_period_end"
        case currentPeriodEnd = "current_period_end"
        case createdAt = "created_at"
    }
}
