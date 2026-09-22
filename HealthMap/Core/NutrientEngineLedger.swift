import Foundation

// MARK: - Le registre du moteur « caddie » (22 septembre 2026)
//
// Quand la personne a rempli ses courses, le score vient de `NutrientEngine`.
// Jusqu'ici ce moteur ne nommait rien : l'anneau de cause se réduisait à
// « couvert / reste », SANS zones grises, et « Comment on l'a vu » disparaissait
// — pour la plupart des comptes récents (retour d'Arthur du 22 sept.).
//
// Ici, les mêmes points que `NutrientEngine.scoresBruts`, nommés un par un :
// ce que les courses apportent, puis chaque facteur non alimentaire.
//
// GARDE-FOU : ce registre est un MIROIR de `applyNonFoodModifiers`, pas sa
// source. S'il dérive (une pénalité ajoutée d'un côté seulement), l'écart n'est
// jamais caché : il apparaît comme une ligne « Autres facteurs de ton profil »,
// et `NutrientEngineLedgerTests` échoue tant qu'il existe. Le score affiché
// reste, dans tous les cas, exactement celui du moteur.

extension NutrientEngine {

    static let libelleEcart = "Autres facteurs de ton profil"

    /// Un carnet : une ligne nommée par facteur appliqué.
    private struct Carnet {
        var lignes: [String: [ContributionApport]] = [:]

        mutating func note(_ id: String, _ delta: Int, _ libelle: String, _ section: SectionQuestionnaire) {
            guard delta != 0 else { return }
            lignes[id, default: []].append(ContributionApport(libelle: libelle, delta: delta, section: section))
        }

        /// Le même facteur sur plusieurs apports à la fois.
        mutating func note(_ effets: [(String, Int)], _ libelle: String, _ section: SectionQuestionnaire) {
            for (id, delta) in effets { note(id, delta, libelle, section) }
        }
    }

    /// Ce que disent les courses, selon ce qu'elles pèsent.
    static func libelleDesCourses(delta: Int) -> String {
        switch delta {
        case ...(-30): return "Aucune source dans tes courses"
        case ...(-15): return "Très peu de sources dans tes courses"
        case ..<0: return "Peu de sources dans tes courses"
        case ..<12: return "Tes courses en apportent"
        default: return "Tes courses en apportent beaucoup"
        }
    }

    static func registreApports(profile p: UserProfile) -> [String: DetailApport] {
        let bruts = scoresBruts(profile: p)
        guard !bruts.isEmpty else { return [:] }

        var c = Carnet()

        // ── 1. Les courses ──
        // Le libellé suit ce que disent les courses (avant le poids de
        // l'assiette) : sans poisson ni œufs, c'est « Aucune source » même si la
        // vitamine D n'en perd que la moitié des points.
        for n in GroceryNutrient.allCases {
            c.note(n.rawValue, foodDelta(p, n), libelleDesCourses(delta: foodDeltaBrut(p, n)), .nutrition)
        }

        // ── 2. Les facteurs non alimentaires (miroir de `applyNonFoodModifiers`) ──
        let age = p.ageInt
        let actif = p.isActive
        let fume = p.isSmoker
        let sommeil = p.sleepHoursDouble
        let eau = p.waterLiters
        let imc = HealthCalculator.calculateBMI(weightKg: p.weightDouble, heightCm: p.heightDouble)
        let cafeine = p.caffeineIntake.isEmpty ? "none" : p.caffeineIntake
        let ecrans = p.screenBeforeBed.isEmpty ? "short" : p.screenBeforeBed
        let grignotage = p.snacking.isEmpty ? "sometimes" : p.snacking
        let transformes = p.ultraProcessedFrequency.isEmpty ? "sometimes" : p.ultraProcessedFrequency
        let reflux = p.digestiveConditions.contains("acid_reflux") || p.digestiveIssues.contains("acid_reflux")
        let cuisson = p.cookingMethod.isEmpty ? "mixed" : p.cookingMethod
        let faitMaison = p.homeCookedPct.isEmpty ? "mostly" : p.homeCookedPct
        let fermentes = p.fermentedFoods.isEmpty ? "sometimes" : p.fermentedFoods
        let alcoolFrequent = ["regular", "heavy"].contains(p.alcohol)
        let stressEleve = ["very", "explode"].contains(p.stressLevel)
        let grignote = ["souvent", "often", "constant"].contains(grignotage)

        let activite = "Activité physique soutenue"
        let tabac = "Tabac"
        let alcool = "Alcool fréquent"
        let peuDeGlucides = "Alimentation pauvre en glucides"
        let peuDEau = "Moins d'un litre d'eau par jour"
        let nuitsCourtes = "Nuits de moins de 6 heures"

        // Vitamine D (le soleil ne se compte qu'une fois : `soleilRenseigne`)
        if p.indoorWork == "yes" && !soleilRenseigne(p) { c.note("vitD", -25, "Travail en intérieur", .modeDeVie) }
        let soleil: [String: (Int, String)] = [
            "none": (-30, "Aucune exposition au soleil"), "very_little": (-20, "Très peu de soleil"),
            "some": (-5, "Un peu de soleil"), "moderate": (5, "Du soleil régulièrement"),
            "plenty": (15, "Beaucoup de soleil"),
        ]
        if let effet = soleil[p.sunExposure] { c.note("vitD", effet.0, effet.1, .modeDeVie) }
        if age > 70 { c.note("vitD", -15, "Plus de 70 ans", .profil) }
        else if age > 50 { c.note("vitD", -10, "Plus de 50 ans", .profil) }
        let peau: [String: (Int, String)] = [
            "fair": (-3, "Peau claire"), "medium": (-8, "Peau intermédiaire"),
            "olive": (-15, "Peau mate"), "dark": (-22, "Peau foncée"),
        ]
        if let effet = peau[p.skinType] { c.note("vitD", effet.0, effet.1, .profil) }
        if let imc, imc > 30 { c.note("vitD", -8, "IMC supérieur à 30", .profil) }
        if sommeil < 6 { c.note("vitD", -5, nuitsCourtes, .modeDeVie) }

        // Vitamine B12
        let alcoolB12: [String: (Int, String)] = [
            "moderate": (-5, "Alcool modéré"), "regular": (-15, alcool), "heavy": (-25, "Alcool très fréquent"),
        ]
        if let effet = alcoolB12[p.alcohol] { c.note("vitB12", effet.0, effet.1, .modeDeVie) }
        if age > 60 { c.note("vitB12", -10, "Plus de 60 ans", .profil) }
        else if age > 50 { c.note("vitB12", -5, "Plus de 50 ans", .profil) }
        if p.antibiotics == "yes" { c.note("vitB12", -5, "Antibiotiques récents", .sante) }

        // Fer
        if p.gender == .femme {
            if age < 50 { c.note("iron", -15, "Femme de moins de 50 ans", .profil) }
            else { c.note("iron", -5, "Femme de plus de 50 ans", .profil) }
        }
        if actif { c.note("iron", -5, activite, .modeDeVie) }
        if cafeine == "heavy" { c.note("iron", -12, "Beaucoup de café ou de thé", .nutrition) }
        else if cafeine == "moderate" { c.note("iron", -5, "Café ou thé modéré", .nutrition) }
        if p.caffeineWithMeals && cafeine != "none" { c.note("iron", -10, "Café ou thé pendant les repas", .nutrition) }
        if reflux { c.note("iron", -8, "Remontées acides déclarées", .sante) }
        if let imc, imc < 18.5 { c.note("iron", -8, "IMC inférieur à 18,5", .profil) }
        if p.alcohol == "heavy" { c.note("iron", -8, "Alcool très fréquent", .modeDeVie) }

        // Magnésium
        let stress: [String: (Int, String)] = [
            "zen": (5, "Peu de stress"), "somewhat": (-8, "Stress modéré"),
            "very": (-15, "Stress élevé"), "explode": (-20, "Stress très élevé"),
        ]
        if let effet = stress[p.stressLevel] { c.note("magnesium", effet.0, effet.1, .modeDeVie) }
        if actif { c.note("magnesium", -10, activite, .modeDeVie) }
        if sommeil < 6 { c.note("magnesium", -8, nuitsCourtes, .modeDeVie) }
        if cafeine == "heavy" { c.note("magnesium", -10, "Beaucoup de café ou de thé", .nutrition) }
        else if cafeine == "moderate" { c.note("magnesium", -4, "Café ou thé modéré", .nutrition) }
        if stressEleve && sommeil < 7 && ["long", "very_long"].contains(ecrans) {
            c.note("magnesium", -8, "Stress, nuits courtes et écrans le soir", .modeDeVie)
        }
        if p.lowCarbDiet == "yes" { c.note("magnesium", -8, peuDeGlucides, .nutrition) }
        if alcoolFrequent { c.note("magnesium", -8, alcool, .modeDeVie) }
        if eau < 1 { c.note("magnesium", -5, peuDEau, .modeDeVie) }
        if age > 70 { c.note("magnesium", -8, "Plus de 70 ans", .profil) }

        // Oméga-3
        if grignote { c.note("omega3", -5, "Grignotage fréquent", .nutrition) }
        if fume { c.note("omega3", -8, tabac, .modeDeVie) }

        // Vitamine C
        if fume { c.note("vitC", -25, tabac, .modeDeVie) }
        if stressEleve { c.note("vitC", -5, "Stress élevé", .modeDeVie) }
        if alcoolFrequent { c.note("vitC", -5, alcool, .modeDeVie) }
        if age > 65 { c.note("vitC", -5, "Plus de 65 ans", .profil) }

        // Calcium
        if age > 50 { c.note("calcium", -8, "Plus de 50 ans", .profil) }
        if p.lowCarbDiet == "yes" { c.note("calcium", -5, peuDeGlucides, .nutrition) }
        if fume { c.note("calcium", -5, tabac, .modeDeVie) }
        if let imc, imc < 18.5 { c.note("calcium", -8, "IMC inférieur à 18,5", .profil) }
        if actif { c.note("calcium", 5, activite, .modeDeVie) }

        // Zinc
        if actif { c.note("zinc", -5, activite, .modeDeVie) }
        if age > 65 { c.note("zinc", -5, "Plus de 65 ans", .profil) }
        if alcoolFrequent { c.note("zinc", -5, alcool, .modeDeVie) }
        if p.bloating == "yes" { c.note("zinc", -3, "Ballonnements fréquents", .sante) }

        // Iode
        if p.iodizedSalt == "no" {
            c.note("iodine", -12, "Sel non iodé", .nutrition)
        } else if p.iodizedSalt == "yes" && p.saltLevel == "none" {
            c.note("iodine", -8, "Sel iodé mais très peu de sel", .nutrition)
        } else if p.iodizedSalt == "yes" && ["moderate", "a_lot"].contains(p.saltLevel) {
            c.note("iodine", 8, "Sel iodé au quotidien", .nutrition)
        }
        if p.dietType == "sans_gluten" { c.note("iodine", -5, "Alimentation sans gluten", .nutrition) }

        // Fibres
        if p.lowCarbDiet == "yes" { c.note("fiber", -10, peuDeGlucides, .nutrition) }
        if p.bloating == "yes" && p.antibiotics == "yes" { c.note("fiber", -5, "Ballonnements après antibiotiques", .sante) }
        if grignote { c.note("fiber", -5, "Grignotage fréquent", .nutrition) }
        if eau < 1 { c.note("fiber", -5, peuDEau, .modeDeVie) }

        // Ce que le caddie ne dit pas (miroir exact de `applyNonFoodModifiers`)
        if !caddieContient(p, painsDuCaddie) {
            if p.breadType == "white" {
                c.note("fiber", -15, "Pain blanc", .nutrition)
            } else if ["whole_grain", "sourdough"].contains(p.breadType) {
                c.note([("fiber", 10), ("magnesium", 10)], "Pain complet ou au levain", .nutrition)
                if p.breadType == "sourdough" { c.note("zinc", 5, "Pain au levain", .nutrition) }
            }
        }
        if p.eatLiver == "yes" && !caddieContient(p, abatsDuCaddie) {
            c.note([("vitB12", 15), ("iron", 10)], "Abats au menu", .nutrition)
        }
        if vitamineCAideLeFer(p) { c.note("iron", 5, "Fruits et légumes riches en vitamine C", .nutrition) }

        // Habitudes d'assiette
        if ["often", "daily"].contains(transformes) {
            c.note([("fiber", -8), ("zinc", -5)], "Produits ultra-transformés fréquents", .nutrition)
        }
        if cuisson == "boiled" { c.note([("vitC", -10), ("fiber", -3)], "Cuisson à l'eau", .nutrition) }
        if ["mostly_out", "rarely"].contains(faitMaison) {
            c.note([("fiber", -8), ("zinc", -5), ("magnesium", -5)], "Repas surtout pris dehors", .nutrition)
        }
        if fermentes == "never" { c.note("calcium", -3, "Jamais d'aliments fermentés", .nutrition) }

        // Santé
        if p.periodFlow == "very_heavy" { c.note("iron", -15, "Règles très abondantes", .sante) }
        else if p.periodFlow == "heavy" { c.note("iron", -8, "Règles abondantes", .sante) }
        if p.pregnancyStatus == "pregnant" {
            c.note([("iron", -15), ("iodine", -10), ("calcium", -5)], "Grossesse", .sante)
        } else if p.pregnancyStatus == "breastfeeding" {
            c.note([("iodine", -8), ("calcium", -5)], "Allaitement", .sante)
        }
        if p.digestiveConditions.contains(where: { ["celiac", "crohns_uc"].contains($0) }) {
            c.note([("iron", -15), ("vitB12", -10), ("calcium", -10), ("zinc", -10), ("vitD", -10)],
                   "Absorption digestive réduite", .medical)
        }

        // Antécédents : le bloc partagé, exécuté sur une ardoise à zéro — jamais recopié.
        var ardoise: [String: Int] = [:]
        for n in GroceryNutrient.allCases { ardoise[n.rawValue] = 0 }
        applyMedicalHistoryPenalties(&ardoise, profile: p)
        for (id, delta) in ardoise { c.note(id, delta, "Antécédents, opérations et allergies", .medical) }

        // Traitements
        if p.medications.contains("ppi") {
            c.note([("magnesium", -10), ("vitB12", -12), ("iron", -8), ("calcium", -8)],
                   "Traitement contre les remontées acides", .medical)
        }
        if p.medications.contains("metformin") { c.note("vitB12", -15, "Metformine", .medical) }
        if p.medications.contains("oral_contraceptive") {
            c.note([("magnesium", -5), ("zinc", -5)], "Contraceptif oral", .medical)
        }
        if p.medications.contains("diuretics") { c.note([("magnesium", -10), ("zinc", -5)], "Diurétiques", .medical) }

        // Ce que la personne prend déjà
        let prises = p.supplementsCurrent
        if prises.contains("vitD") { c.note("vitD", 25, "Tu prends déjà de la vitamine D", .medical) }
        if prises.contains("omega3") { c.note("omega3", 20, "Tu prends déjà des oméga-3", .medical) }
        if prises.contains("magnesium") { c.note("magnesium", 20, "Tu prends déjà du magnésium", .medical) }
        if prises.contains("iron") { c.note("iron", 15, "Tu prends déjà du fer", .medical) }
        if prises.contains("b12") { c.note("vitB12", 20, "Tu prends déjà de la B12", .medical) }
        if prises.contains("zinc") { c.note("zinc", 15, "Tu prends déjà du zinc", .medical) }
        if prises.contains("folate") { c.note("fiber", 3, "Tu prends déjà des folates", .medical) }
        if prises.contains("probiotics") { c.note("fiber", 5, "Tu prends déjà des probiotiques", .medical) }
        if prises.contains("multivitamin") {
            c.note([("vitD", 10), ("vitB12", 15), ("iron", 8), ("zinc", 8), ("vitC", 10), ("iodine", 10)],
                   "Tu prends déjà un multivitamines", .medical)
        }

        // Régime
        if p.dietType == "vegan" {
            c.note([("vitB12", -30), ("iron", -15), ("zinc", -15), ("omega3", -10), ("calcium", -10), ("iodine", -8)],
                   "Alimentation végétalienne", .nutrition)
        } else if p.dietType == "vegetarien" {
            c.note([("vitB12", -15), ("iron", -8), ("zinc", -8)], "Alimentation végétarienne", .nutrition)
        }

        // ── 3. Le garde-fou : le total nommé DOIT retomber sur le score du moteur ──
        var sortie: [String: DetailApport] = [:]
        for (id, brut) in bruts {
            var contributions = c.lignes[id] ?? []
            let nomme = DetailApport.pointDeDepart + contributions.reduce(0) { $0 + $1.delta }
            if nomme != brut {
                contributions.append(ContributionApport(libelle: libelleEcart, delta: brut - nomme, section: .profil))
            }
            sortie[id] = DetailApport(contributions: contributions, score: max(0, min(100, brut)))
        }
        return sortie
    }
}
