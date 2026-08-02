import Foundation

// MARK: - Nutrient Engine — scoring depuis le caddie "Faites vos courses"
//
// Nouveau moteur de score (PR 2). Il REMPLACE la partie alimentaire du calcul
// quand l'utilisateur a rempli son caddie (`profile.groceries` non vide) :
//
//   • Couverture alimentaire GRADUÉE et PLAFONNÉE par nutriment, calculée à
//     partir des portions/semaine des aliments du caddie qui sont une source
//     notable de ce nutriment (catalogue GroceryCatalog, tags vérifiés Ciqual).
//     -> corrige le "100/100" : l'ancien calcul empilait des bonus fixes
//        (fruit+20, légumes+12, …) jusqu'au plafond. Ici la contribution
//        alimentaire est bornée à [-30 ; +18] et suit une courbe saturante.
//
//   • TOUS les modificateurs NON alimentaires sains sont conservés à
//     l'identique de HealthCalculator (soleil/âge/peau/IMC -> vitD, règles/
//     grossesse -> fer, IPP/metformine -> B12, tabac -> vitC, compléments,
//     véganisme, sel iodé, cuisson, etc.).
//
// Tant que le caddie est vide (tous les profils actuels), HealthCalculator
// garde son calcul historique : aucune divergence, parité web préservée.

enum NutrientEngine {

    // MARK: Entrées publiques (mêmes signatures que HealthCalculator)

    /// Scores par nutriment (0-100), déterministes, à partir du caddie.
    static func nutrientScores(profile p: UserProfile) -> [String: Int] {
        // Mêmes garde-fous que HealthCalculator.
        let w = p.weightDouble, h = p.heightDouble, a = p.ageInt
        guard w >= 20, w <= 300, h >= 80, h <= 250, a >= 1, a <= 120 else { return [:] }

        var scores: [String: Int] = [:]
        for n in GroceryNutrient.allCases { scores[n.rawValue] = 70 }

        // ── 1. Contribution alimentaire (caddie), bornée ──
        for n in GroceryNutrient.allCases {
            scores[n.rawValue, default: 70] += foodDelta(p, n)
        }

        // ── 2. Modificateurs NON alimentaires (portés de HealthCalculator) ──
        applyNonFoodModifiers(&scores, profile: p)

        // ── 3. Clamp ──
        for key in scores.keys { scores[key] = max(0, min(100, scores[key]!)) }
        return scores
    }

    /// Score de bien-être global (0-100), depuis le caddie + le mode de vie.
    static func wellnessScore(profile p: UserProfile) -> Int {
        let w = p.weightDouble, h = p.heightDouble, a = p.ageInt
        guard w >= 20, w <= 300, h >= 80, h <= 250, a >= 1, a <= 120 else { return 0 }

        var score = 50

        // Activité
        let activityScores = ["none": 0, "light": 5, "moderate": 15, "regular": 20, "intense": 20]
        score += activityScores[p.strengthTraining] ?? 0

        // IMC
        if let bmi = HealthCalculator.calculateBMI(weightKg: w, heightCm: h) {
            if bmi >= 18.5 && bmi < 25 { score += 15 }
            else if bmi >= 25 && bmi < 30 { score += 5 }
            else if bmi < 18.5 { score -= 5 }
        }

        // Stress / réveil / sommeil / eau (clés mode de vie inchangées)
        score += ["zen": 5, "relaxed": 3, "somewhat": 0, "very": -5, "explode": -10][p.stressLevel] ?? 0
        score += ["great": 10, "good": 7, "ok": 3, "bad": -2, "terrible": -5][p.wakeFeeling] ?? 0
        score += ["4": -8, "5.5": -4, "6.5": 0, "7.5": 5, "8.5": 5, "10": 0][p.sleepHours] ?? 0
        score += ["0.75": -5, "1.25": -2, "1.75": 2, "2.25": 4, "3": 4][p.waterIntake] ?? 0

        if p.isSmoker { score -= 10 }
        if p.bloating == "yes" { score -= 3 }
        if p.antibiotics == "yes" { score -= 3 }

        // Légumes & fruits — désormais DÉRIVÉS du caddie
        let vegs = aisleServings(p, "legumes")
        if vegs >= 5 { score += 5 } else if vegs < 2 { score -= 5 }
        let fruits = aisleServings(p, "fruits")
        if fruits >= 14 { score += 3 } else if fruits < 4 { score -= 3 }

        score += ["none": 3, "rarely": 0, "moderate": -3, "regular": -7, "heavy": -12][p.alcohol] ?? 0
        score += ["2": 0, "3": 3, "4": 2, "5+": 1][p.mealsPerDay] ?? 0
        score += ["never": 3, "jamais": 3, "sometimes": 0, "parfois": 0, "often": -4, "souvent": -4, "constant": -6][p.snacking] ?? 0
        score += ["none": 2, "light": 0, "moderate": -2, "heavy": -5][p.caffeineIntake] ?? 0
        score += ["none": 3, "short": 1, "moderate": -1, "long": -3, "very_long": -5][p.screenBeforeBed] ?? 0

        // `sleepDuration` (clé v6) n'est scorée QUE si `sleepHours` est vide,
        // sinon le sommeil compte deux fois : la table ci-dessus donne déjà
        // +5 pour « 7.5 », et ce bonus en rajoutait 5. Pire, `sleepHoursDouble`
        // vaut 7 par défaut, donc un sommeil NON renseigné offrait +5 gratuits.
        // Garde identique à HealthCalculator (mirror health.js:148-154).
        if p.sleepHours.isEmpty {
            // `Double(sleepDuration) ?? 0` et NON `sleepHoursDouble`, qui
            // retourne 7 par défaut : un sommeil jamais déclaré décrochait
            // alors le bonus « 7 à 9 h » sans que l'utilisateur ait rien dit.
            let sd = Double(p.sleepDuration) ?? 0
            if sd >= 7 && sd <= 9 { score += 5 } else if sd >= 6 { score += 2 } else if sd > 0 && sd < 6 { score -= 5 }
        }

        score += ["never": 5, "rarely": 2, "sometimes": 0, "often": -5, "daily": -8][p.ultraProcessedFrequency] ?? 0
        // Même garde : `mealFrequency` est la clé v6 de `mealsPerDay`.
        if p.mealsPerDay.isEmpty {
            score += ["one": -5, "two": -2, "three": 3, "four_plus": 2, "irregular": -4][p.mealFrequency] ?? 0
        }

        // Diversité alimentaire — dérivée du caddie (8 groupes)
        let diversity = diversityGroupCount(p)
        if diversity >= 7 { score += 5 } else if diversity >= 5 { score += 3 } else if diversity <= 2 { score -= 5 }

        return max(0, min(100, score))
    }

    // MARK: - Couverture alimentaire (caddie)

    /// Cible de portions/semaine d'aliments-sources pour une "bonne" couverture.
    private static let targets: [GroceryNutrient: Int] = [
        .vitD: 3, .vitB12: 5, .iron: 7, .magnesium: 7, .omega3: 3,
        .vitC: 7, .calcium: 10, .zinc: 5, .iodine: 5, .fiber: 14,
    ]

    /// Portions/semaine cumulées des aliments du caddie sources de ce nutriment.
    private static func weeklyServings(_ p: UserProfile, _ nutrient: GroceryNutrient) -> Int {
        GroceryCatalog.items(providing: nutrient).reduce(0) { $0 + (p.groceries[$1.id] ?? 0) }
    }

    /// Nombre d'aliments-sources DISTINCTS effectivement cochés (variété).
    private static func distinctSources(_ p: UserProfile, _ nutrient: GroceryNutrient) -> Int {
        GroceryCatalog.items(providing: nutrient).reduce(0) { $0 + ((p.groceries[$1.id] ?? 0) > 0 ? 1 : 0) }
    }

    /// Contribution alimentaire bornée [-30 ; +18], courbe saturante vs cible.
    private static func foodDelta(_ p: UserProfile, _ nutrient: GroceryNutrient) -> Int {
        let servings = weeklyServings(p, nutrient)
        if servings == 0 { return -30 }
        let target = Double(max(1, targets[nutrient] ?? 5))
        let ratio = Double(servings) / target
        var delta: Int
        switch ratio {
        case ..<0.5: delta = -15
        case ..<1.0: delta = -5
        case ..<1.5: delta = 5
        case ..<2.5: delta = 12
        default:     delta = 18
        }
        // Petit bonus de variété (sources multiples), plafond conservé.
        if distinctSources(p, nutrient) >= 3 { delta = min(18, delta + 2) }
        return delta
    }

    /// Portions/semaine cumulées d'un rayon.
    private static func aisleServings(_ p: UserProfile, _ aisleId: String) -> Int {
        (GroceryCatalog.aisles.first { $0.id == aisleId }?.items ?? [])
            .reduce(0) { $0 + (p.groceries[$1.id] ?? 0) }
    }

    /// Compte les groupes alimentaires présents dans le caddie (diversité).
    private static func diversityGroupCount(_ p: UserProfile) -> Int {
        func has(_ ids: [String]) -> Bool { ids.contains { (p.groceries[$0] ?? 0) > 0 } }
        let groups: [Bool] = [
            aisleServings(p, "poissons") > 0,                                   // poisson
            aisleServings(p, "viandes") > 0,                                    // viande
            (p.groceries["oeufs"] ?? 0) > 0,                                    // œufs
            has(["lait", "yaourt_nature", "yaourt_grec", "fromage_blanc",
                 "petits_suisses", "emmental", "camembert", "comte",
                 "mozzarella", "buche_chevre", "boisson_soja"]),               // laitages
            has(["lentilles", "pois_chiches", "haricots_rouges",
                 "haricots_blancs", "tofu"]),                                   // légumes secs
            aisleServings(p, "secs") > 0,                                       // oléagineux/graines
            has(["pain_complet", "riz_complet", "flocons_avoine", "quinoa"]),   // céréales complètes
            has(["graines_courge", "graines_tournesol", "graines_chia"]),       // graines
        ]
        return groups.filter { $0 }.count
    }

    // MARK: - Modificateurs non alimentaires (miroir de HealthCalculator)
    //
    // ⚠️ Ces blocs reproduisent FIDÈLEMENT la logique non alimentaire de
    // HealthCalculator.analyzeNutrientScores. Les SEULES lignes volontairement
    // omises sont celles pilotées par les quantités d'aliments (poisson, viande,
    // fruits, légumes, laitages, noix, graines, légumineuses, complet) + breadType
    // + eatLiver : elles sont désormais portées par le caddie (foodDelta).
    private static func applyNonFoodModifiers(_ scores: inout [String: Int], profile p: UserProfile) {
        let age = p.ageInt
        let isActive = p.isActive
        let isSmoker = p.isSmoker
        let sleepHours = p.sleepHoursDouble
        let waterL = p.waterLiters
        let bmi = HealthCalculator.calculateBMI(weightKg: p.weightDouble, heightCm: p.heightDouble)
        let caffeine = p.caffeineIntake.isEmpty ? "none" : p.caffeineIntake
        let caffeineWithMeals = p.caffeineWithMeals
        let screenBed = p.screenBeforeBed.isEmpty ? "short" : p.screenBeforeBed
        let snacking = p.snacking.isEmpty ? "sometimes" : p.snacking
        let ultraProcessed = p.ultraProcessedFrequency.isEmpty ? "sometimes" : p.ultraProcessedFrequency
        let hasReflux = p.digestiveConditions.contains("acid_reflux") || p.digestiveIssues.contains("acid_reflux")
        let cookingMethod = p.cookingMethod.isEmpty ? "mixed" : p.cookingMethod
        let homeCookedPct = p.homeCookedPct.isEmpty ? "mostly" : p.homeCookedPct
        let fermented = p.fermentedFoods.isEmpty ? "sometimes" : p.fermentedFoods

        // ═══════ VITAMIN D ═══════
        if p.indoorWork == "yes" { scores["vitD", default: 70] -= 25 }
        scores["vitD", default: 70] += ["none": -30, "very_little": -20, "some": -5, "moderate": 5, "plenty": 15][p.sunExposure] ?? 0
        if age > 70 { scores["vitD", default: 70] -= 15 } else if age > 50 { scores["vitD", default: 70] -= 10 }
        scores["vitD", default: 70] += ["very_fair": 0, "fair": -3, "medium": -8, "olive": -15, "dark": -22][p.skinType] ?? 0
        if let bmi, bmi > 30 { scores["vitD", default: 70] -= 8 }
        if sleepHours < 6 { scores["vitD", default: 70] -= 5 }

        // ═══════ VITAMIN B12 ═══════
        scores["vitB12", default: 70] += ["none": 0, "rarely": 0, "moderate": -5, "regular": -15, "heavy": -25][p.alcohol] ?? 0
        if age > 60 { scores["vitB12", default: 70] -= 10 } else if age > 50 { scores["vitB12", default: 70] -= 5 }
        if p.antibiotics == "yes" { scores["vitB12", default: 70] -= 5 }

        // ═══════ IRON ═══════
        if p.gender == .femme {
            if age < 50 { scores["iron", default: 70] -= 15 } else { scores["iron", default: 70] -= 5 }
        }
        if isActive { scores["iron", default: 70] -= 5 }
        if caffeine == "heavy" { scores["iron", default: 70] -= 12 } else if caffeine == "moderate" { scores["iron", default: 70] -= 5 }
        if caffeineWithMeals && caffeine != "none" { scores["iron", default: 70] -= 10 }
        if hasReflux { scores["iron", default: 70] -= 8 }
        if let bmi, bmi < 18.5 { scores["iron", default: 70] -= 8 }
        if p.alcohol == "heavy" { scores["iron", default: 70] -= 8 }

        // ═══════ MAGNESIUM ═══════
        scores["magnesium", default: 70] += ["zen": 5, "relaxed": 0, "somewhat": -8, "very": -15, "explode": -20][p.stressLevel] ?? 0
        if isActive { scores["magnesium", default: 70] -= 10 }
        if sleepHours < 6 { scores["magnesium", default: 70] -= 8 }
        if caffeine == "heavy" { scores["magnesium", default: 70] -= 10 } else if caffeine == "moderate" { scores["magnesium", default: 70] -= 4 }
        if ["very", "explode"].contains(p.stressLevel) && sleepHours < 7 && ["long", "very_long"].contains(screenBed) {
            scores["magnesium", default: 70] -= 8
        }
        if p.lowCarbDiet == "yes" { scores["magnesium", default: 70] -= 8 }
        if ["regular", "heavy"].contains(p.alcohol) { scores["magnesium", default: 70] -= 8 }
        if waterL < 1 { scores["magnesium", default: 70] -= 5 }
        if age > 70 { scores["magnesium", default: 70] -= 8 }

        // ═══════ OMEGA-3 ═══════
        if ["souvent", "often", "constant"].contains(snacking) { scores["omega3", default: 70] -= 5 }
        if isSmoker { scores["omega3", default: 70] -= 8 }

        // ═══════ VITAMIN C ═══════
        if isSmoker { scores["vitC", default: 70] -= 25 }
        if ["very", "explode"].contains(p.stressLevel) { scores["vitC", default: 70] -= 5 }
        if ["regular", "heavy"].contains(p.alcohol) { scores["vitC", default: 70] -= 5 }
        if age > 65 { scores["vitC", default: 70] -= 5 }

        // ═══════ CALCIUM ═══════
        if age > 50 { scores["calcium", default: 70] -= 8 }
        if p.lowCarbDiet == "yes" { scores["calcium", default: 70] -= 5 }
        if isSmoker { scores["calcium", default: 70] -= 5 }
        if let bmi, bmi < 18.5 { scores["calcium", default: 70] -= 8 }
        if isActive { scores["calcium", default: 70] += 5 }

        // ═══════ ZINC ═══════
        if isActive { scores["zinc", default: 70] -= 5 }
        if age > 65 { scores["zinc", default: 70] -= 5 }
        if ["regular", "heavy"].contains(p.alcohol) { scores["zinc", default: 70] -= 5 }
        if p.bloating == "yes" { scores["zinc", default: 70] -= 3 }

        // ═══════ IODINE ═══════ (sel iodé = question conservée)
        // Non renseigné = neutre, PAS une pénalité : `iodizedSalt` est une
        // question du parcours Complet, jamais posée en Express. La traiter
        // comme « no » retirait 12 points d'iode à tout utilisateur Express
        // pour une question qu'il n'a jamais vue. Correctif du 2026-07-05
        // appliqué à HealthCalculator, jamais répercuté ici jusqu'au 2 août.
        if p.iodizedSalt == "no" {
            scores["iodine", default: 70] -= 12
        } else if p.iodizedSalt == "yes" && p.saltLevel == "none" {
            scores["iodine", default: 70] -= 8
        } else if p.iodizedSalt == "yes" && ["moderate", "a_lot"].contains(p.saltLevel) {
            scores["iodine", default: 70] += 8
        }
        if p.dietType == "sans_gluten" { scores["iodine", default: 70] -= 5 }

        // ═══════ FIBER ═══════
        if p.lowCarbDiet == "yes" { scores["fiber", default: 70] -= 10 }
        if p.bloating == "yes" && p.antibiotics == "yes" { scores["fiber", default: 70] -= 5 }
        if ["often", "constant", "souvent"].contains(snacking) { scores["fiber", default: 70] -= 5 }
        if waterL < 1 { scores["fiber", default: 70] -= 5 }

        // ═══════ ULTRA-TRANSFORMÉS (habitude) ═══════
        if ["often", "daily"].contains(ultraProcessed) {
            scores["fiber", default: 70] -= 8
            scores["zinc", default: 70] -= 5
        }

        // ═══════ CUISSON & MODE DE VIE ═══════
        if cookingMethod == "boiled" { scores["vitC", default: 70] -= 10; scores["fiber", default: 70] -= 3 }
        if ["mostly_out", "rarely"].contains(homeCookedPct) {
            scores["fiber", default: 70] -= 8; scores["zinc", default: 70] -= 5; scores["magnesium", default: 70] -= 5
        }
        if fermented == "never" { scores["calcium", default: 70] -= 3 }

        // ═══════ RÈGLES ═══════
        if p.periodFlow == "very_heavy" { scores["iron", default: 70] -= 15 }
        else if p.periodFlow == "heavy" { scores["iron", default: 70] -= 8 }

        // ═══════ GROSSESSE ═══════
        if p.pregnancyStatus == "pregnant" {
            scores["iron", default: 70] -= 15; scores["iodine", default: 70] -= 10; scores["calcium", default: 70] -= 5
        } else if p.pregnancyStatus == "breastfeeding" {
            scores["iodine", default: 70] -= 8; scores["calcium", default: 70] -= 5
        }

        // ═══════ MALABSORPTION ═══════
        if p.digestiveConditions.contains(where: { ["celiac", "crohns_uc"].contains($0) }) {
            scores["iron", default: 70] -= 15; scores["vitB12", default: 70] -= 10; scores["calcium", default: 70] -= 10
            scores["zinc", default: 70] -= 10; scores["vitD", default: 70] -= 10
        }

        // ═══════ MÉDICAMENTS ═══════
        if p.medications.contains("ppi") {
            scores["magnesium", default: 70] -= 10; scores["vitB12", default: 70] -= 12; scores["iron", default: 70] -= 8; scores["calcium", default: 70] -= 8
        }
        if p.medications.contains("metformin") { scores["vitB12", default: 70] -= 15 }
        if p.medications.contains("oral_contraceptive") { scores["magnesium", default: 70] -= 5; scores["zinc", default: 70] -= 5 }
        if p.medications.contains("diuretics") { scores["magnesium", default: 70] -= 10; scores["zinc", default: 70] -= 5 }

        // ═══════ COMPLÉMENTS ═══════
        let supps = p.supplementsCurrent
        if supps.contains("vitD") { scores["vitD", default: 70] += 25 }
        if supps.contains("omega3") { scores["omega3", default: 70] += 20 }
        if supps.contains("magnesium") { scores["magnesium", default: 70] += 20 }
        if supps.contains("iron") { scores["iron", default: 70] += 15 }
        if supps.contains("b12") { scores["vitB12", default: 70] += 20 }
        if supps.contains("zinc") { scores["zinc", default: 70] += 15 }
        if supps.contains("folate") { scores["fiber", default: 70] += 3 }
        if supps.contains("probiotics") { scores["fiber", default: 70] += 5 }
        if supps.contains("multivitamin") {
            scores["vitD", default: 70] += 10; scores["vitB12", default: 70] += 15; scores["iron", default: 70] += 8
            scores["zinc", default: 70] += 8; scores["vitC", default: 70] += 10; scores["iodine", default: 70] += 10
        }

        // ═══════ TYPE DE RÉGIME ═══════
        if p.dietType == "vegan" {
            scores["vitB12", default: 70] -= 30; scores["iron", default: 70] -= 15; scores["zinc", default: 70] -= 15
            scores["omega3", default: 70] -= 10; scores["calcium", default: 70] -= 10; scores["iodine", default: 70] -= 8
        } else if p.dietType == "vegetarien" {
            scores["vitB12", default: 70] -= 15; scores["iron", default: 70] -= 8; scores["zinc", default: 70] -= 8
        }
    }
}
