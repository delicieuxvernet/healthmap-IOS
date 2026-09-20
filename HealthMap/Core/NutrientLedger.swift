import Foundation

// MARK: - Registre des apports — « d'où sort ce chiffre ? »
//
// Le moteur de score calculait déjà, pour chaque apport, une suite de
// pénalités et de bonus nommés — puis n'en gardait que la somme. Ce fichier
// garde les lignes.
//
// C'est la MÊME arithmétique qu'avant, à la ligne près : `analyzeNutrientScores`
// n'est plus qu'une projection de ce registre (`registre().mapValues(\.score)`).
// Il n'existe donc pas deux implémentations à tenir synchronisées, et
// `CrossRepoParityTests` (3 profils × 10 apports, valeurs figées depuis
// health.js) verrouille le tout : la moindre dérive d'un point casse la CI.
//
// Deux invariants portent l'affichage :
//
//   • la cascade (`contributionsTriees`) part de `depart` et retombe sur
//     `brut` ; quand `brut` sort de l'échelle 0-100, `score` le ramène et
//     `estBorne` le signale plutôt que de mentir sur le total ;
//   • l'anneau (`segments`) ferme TOUJOURS à 100, quel que soit le profil.
//
// Le caddie « Faites vos courses » (`NutrientEngine`) n'a pas encore de
// registre : ces profils reçoivent un détail sans facteur nommé, l'anneau se
// réduit alors à « couvert » + « autres facteurs » et la fiche masque son
// bloc 02. Aucun chiffre inventé pour combler le trou.

/// Un facteur nommé et son poids, en points d'apport.
struct ContributionApport: Equatable, Identifiable {
    /// Libellé lisible par la personne, tel qu'il s'affiche dans la fiche.
    let libelle: String
    /// Poids en points — négatif quand le facteur pèse sur l'apport.
    let delta: Int

    var id: String { "\(libelle)#\(delta)" }
}

/// Le détail d'un apport : point de départ, facteurs nommés, score final.
struct DetailApport: Equatable {

    /// Point de départ commun à tous les apports, avant le moindre facteur.
    let depart: Int
    /// Facteurs nommés, dans l'ordre où le moteur les applique.
    let contributions: [ContributionApport]
    /// Score final borné 0-100 — identique à `analyzeNutrientScores`.
    let score: Int

    /// Total avant bornage : `depart` + tous les deltas.
    var brut: Int { depart + contributions.reduce(0) { $0 + $1.delta } }

    /// Vrai quand le bornage 0-100 a dû intervenir : la cascade ne retombe
    /// alors pas sur `score`, et la fiche doit le dire.
    var estBorne: Bool { brut != score }

    /// Facteurs qui pèsent, du plus lourd au plus léger.
    var freins: [ContributionApport] {
        contributions.filter { $0.delta < 0 }.sorted { $0.delta < $1.delta }
    }

    /// Facteurs qui jouent en ta faveur, du plus fort au plus faible.
    var appuis: [ContributionApport] {
        contributions.filter { $0.delta > 0 }.sorted { $0.delta > $1.delta }
    }

    /// Ordre d'affichage de la cascade : ce qui pèse d'abord, ce qui aide ensuite.
    var contributionsTriees: [ContributionApport] { freins + appuis }

    /// Découpage de l'anneau, en parts qui somment TOUJOURS à 100.
    ///
    /// La part couverte vaut le score. L'arc manquant (`100 - score`) est
    /// réparti entre les freins nommés puis « autres facteurs ». Tant que les
    /// freins tiennent dans l'arc — le cas courant — chaque part vaut
    /// exactement son poids en points. S'ils débordent (profil très
    /// supplémenté, où les appuis ont regonflé le score), ils sont comprimés
    /// au prorata : l'anneau reste juste dans ses proportions, et la fiche
    /// continue d'afficher les points exacts.
    var segments: [(libelle: String, valeur: Int)] {
        let manque = max(0, 100 - score)
        let poids = freins.map { abs($0.delta) }
        let total = poids.reduce(0, +)

        var parts: [(libelle: String, valeur: Int)] = [("Couvert", score)]

        if total > 0 {
            let place = min(total, manque)
            var distribue = 0
            for (index, frein) in freins.enumerated() {
                let valeur: Int
                if index == freins.count - 1 {
                    valeur = place - distribue
                } else {
                    valeur = Int((Double(poids[index]) / Double(total) * Double(place)).rounded())
                }
                if valeur > 0 {
                    parts.append((frein.libelle, valeur))
                    distribue += valeur
                }
            }
            if distribue != place, let dernier = parts.indices.last, parts.count > 1 {
                parts[dernier].valeur += place - distribue
            }
        }

        let reste = 100 - parts.reduce(0) { $0 + $1.valeur }
        if reste > 0 { parts.append(("Autres facteurs", reste)) }
        return parts.filter { $0.valeur > 0 }
    }
}

// MARK: - Le registre

extension HealthCalculator {

    /// Accumulateur : une ligne nommée par facteur appliqué.
    private struct Registre {
        static let depart = 70

        private var lignes: [String: [ContributionApport]] = [:]

        mutating func add(_ id: String, _ delta: Int, _ libelle: String) {
            guard delta != 0 else { return }
            lignes[id, default: []].append(ContributionApport(libelle: libelle, delta: delta))
        }

        /// Même facteur, même poids, sur plusieurs apports à la fois.
        mutating func add(_ ids: [String], _ deltas: [Int], _ libelle: String) {
            for (id, delta) in zip(ids, deltas) { add(id, delta, libelle) }
        }

        /// Facteur piloté par une table clé → poids, avec sa table de libellés.
        mutating func addTable(_ id: String, _ poids: [String: Int], _ libelles: [String: String], _ cle: String) {
            guard let delta = poids[cle], let libelle = libelles[cle] else { return }
            add(id, delta, libelle)
        }

        func detail(_ id: String) -> DetailApport {
            let contributions = lignes[id] ?? []
            let brut = Self.depart + contributions.reduce(0) { $0 + $1.delta }
            return DetailApport(
                depart: Self.depart,
                contributions: contributions,
                score: max(0, min(100, brut))
            )
        }
    }

    /// Le détail de chaque apport — même arithmétique que `analyzeNutrientScores`.
    ///
    /// Renvoie un dictionnaire vide pour un profil hors bornes, exactement
    /// comme le calcul de score.
    static func registreApports(profile: UserProfile) -> [String: DetailApport] {
        // Caddie rempli : le score vient de NutrientEngine, qui ne tient pas
        // encore de registre. On rend le score sans facteur nommé plutôt que
        // d'en inventer.
        if !profile.groceries.isEmpty {
            return NutrientEngine.nutrientScores(profile: profile).mapValues {
                DetailApport(depart: Registre.depart, contributions: [], score: $0)
            }
        }

        let w = profile.weightDouble
        let h = profile.heightDouble
        let a = profile.ageInt
        guard w >= 20, w <= 300, h >= 80, h <= 250, a >= 1, a <= 120 else { return [:] }

        var r = Registre()

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

        let libTabac = "Tabac"
        let libSport = "Sport régulier"
        let libNuitsCourtes = "Nuits de moins de 6 h"
        let libPeuEau = "Moins d'un litre d'eau par jour"
        let libGrignotage = "Grignotage fréquent"
        let libOleagineux = "Oléagineux réguliers"
        let libLegumineuses = "Légumineuses régulières"
        let libPainComplet = "Pain complet ou au levain"
        let libPeuGlucides = "Alimentation pauvre en glucides"
        let libAlcoolRegulier = "Alcool régulier"
        let libFruitsQuotidiens = "Fruits tous les jours"
        let libFruitsReguliers = "Fruits réguliers"
        let libPeuFruits = "Très peu de fruits"
        let libLegumesQuotidiens = "Légumes tous les jours"
        let libLegumesReguliers = "Légumes réguliers"
        let libPeuLegumes = "Très peu de légumes"
        let libGrainesQuotidiennes = "Graines tous les jours"
        let libGrainesPresque = "Graines presque tous les jours"
        let libViandeRare = "Viande 3 fois par semaine ou moins"
        let libPasViande = "Pas de viande"
        let libViandeQuotidienne = "Viande quasi quotidienne"
        let libAbats = "Abats au menu"
        let libCafeBeaucoup = "Café ou thé en grande quantité"
        let libCafeModere = "Café ou thé modéré"
        let libOeufsReguliers = "Œufs réguliers"
        let libUltraTransformes = "Ultra-transformés fréquents"

        // ═══════ VITAMINE D ═══════
        if p.indoorWork == "yes" { r.add("vitD", -25, "Travail en intérieur") }
        let sun = ["none": -30, "very_little": -20, "some": -5, "moderate": 5, "plenty": 15]
        let sunLib = [
            "none": "Jamais au soleil",
            "very_little": "Très peu de soleil",
            "some": "Un peu de soleil",
            "moderate": "Soleil régulier",
            "plenty": "Beaucoup de soleil",
        ]
        r.addTable("vitD", sun, sunLib, p.sunExposure)
        if age > 70 { r.add("vitD", -15, "Plus de 70 ans") }
        else if age > 50 { r.add("vitD", -10, "Plus de 50 ans") }
        let skinPenalty = ["very_fair": 0, "fair": -3, "medium": -8, "olive": -15, "dark": -22]
        let skinLib = [
            "very_fair": "Peau très claire",
            "fair": "Peau claire",
            "medium": "Peau intermédiaire",
            "olive": "Peau mate",
            "dark": "Peau foncée",
        ]
        r.addTable("vitD", skinPenalty, skinLib, p.skinType)
        if fish >= 3 { r.add("vitD", 8, "Poisson gras au moins 3 fois par semaine") }
        if dairy >= 10 { r.add("vitD", 5, "Produits laitiers quotidiens") }
        if let bmi, bmi > 30 { r.add("vitD", -8, "IMC supérieur à 30") }
        if sleepHours < 6 { r.add("vitD", -5, libNuitsCourtes) }

        // ═══════ VITAMINE B12 ═══════
        if meat == 0 && eggs == 0 && fish == 0 { r.add("vitB12", -45, "Ni viande, ni œufs, ni poisson") }
        else if meat <= 2 && eggs <= 2 && fish == 0 { r.add("vitB12", -20, "Très peu de produits animaux") }
        else if meat >= 5 && eggs >= 3 { r.add("vitB12", 10, "Viande et œufs réguliers") }
        let alcoholB12 = ["none": 0, "rarely": 0, "moderate": -5, "regular": -15, "heavy": -25]
        let alcoholLib = [
            "none": "Pas d'alcool",
            "rarely": "Alcool rare",
            "moderate": "Alcool modéré",
            "regular": libAlcoolRegulier,
            "heavy": "Alcool fréquent",
        ]
        r.addTable("vitB12", alcoholB12, alcoholLib, p.alcohol)
        if p.eatLiver == "yes" { r.add("vitB12", 15, libAbats) }
        if age > 60 { r.add("vitB12", -10, "Plus de 60 ans") }
        else if age > 50 { r.add("vitB12", -5, "Plus de 50 ans") }
        if p.antibiotics == "yes" { r.add("vitB12", -5, "Antibiotiques récents") }

        // ═══════ FER ═══════
        if meat == 0 { r.add("iron", -30, libPasViande) }
        else if meat <= 3 { r.add("iron", -10, libViandeRare) }
        else if meat >= 7 { r.add("iron", 8, libViandeQuotidienne) }
        if p.gender == .femme {
            if age < 50 { r.add("iron", -15, "Femme de moins de 50 ans") }
            else { r.add("iron", -5, "Femme de plus de 50 ans") }
        }
        if isActive { r.add("iron", -5, libSport) }
        if fruit >= 14 || vegs >= 5 { r.add("iron", 5, "Fruits et légumes riches en vitamine C") }
        if caffeine == "heavy" { r.add("iron", -12, libCafeBeaucoup) }
        else if caffeine == "moderate" { r.add("iron", -5, libCafeModere) }
        if caffeineWithMeals && caffeine != "none" { r.add("iron", -10, "Café ou thé pendant les repas") }
        if hasReflux { r.add("iron", -8, "Remontées acides déclarées") }
        if legumes >= 3 { r.add("iron", 5, libLegumineuses) }
        if p.eatLiver == "yes" { r.add("iron", 10, libAbats) }
        if let bmi, bmi < 18.5 { r.add("iron", -8, "IMC inférieur à 18,5") }
        if p.alcohol == "heavy" { r.add("iron", -8, "Alcool fréquent") }

        // ═══════ MAGNÉSIUM ═══════
        let stressMg = ["zen": 5, "relaxed": 0, "somewhat": -8, "very": -15, "explode": -20]
        let stressLib = [
            "zen": "Stress très bas",
            "relaxed": "Stress bas",
            "somewhat": "Stress modéré",
            "very": "Stress élevé",
            "explode": "Stress très élevé",
        ]
        r.addTable("magnesium", stressMg, stressLib, p.stressLevel)
        if isActive { r.add("magnesium", -10, libSport) }
        if nuts >= 7 { r.add("magnesium", 12, "Oléagineux quotidiens") }
        else if nuts >= 3 { r.add("magnesium", 5, libOleagineux) }
        if p.breadType == "whole_grain" || p.breadType == "sourdough" { r.add("magnesium", 10, libPainComplet) }
        if sleepHours < 6 { r.add("magnesium", -8, libNuitsCourtes) }
        if caffeine == "heavy" { r.add("magnesium", -10, libCafeBeaucoup) }
        else if caffeine == "moderate" { r.add("magnesium", -4, libCafeModere) }
        if ["very", "explode"].contains(p.stressLevel) && sleepHours < 7 && ["long", "very_long"].contains(screenBed) {
            r.add("magnesium", -8, "Stress, nuits courtes et écrans le soir")
        }
        if p.lowCarbDiet == "yes" { r.add("magnesium", -8, libPeuGlucides) }
        if legumes >= 3 { r.add("magnesium", 5, libLegumineuses) }
        if wholegrain >= 5 { r.add("magnesium", 5, "Céréales complètes régulières") }
        if ["regular", "heavy"].contains(p.alcohol) { r.add("magnesium", -8, libAlcoolRegulier) }
        if waterL < 1 { r.add("magnesium", -5, libPeuEau) }
        if age > 70 { r.add("magnesium", -8, "Plus de 70 ans") }

        // ═══════ OMÉGA-3 ═══════
        if fish >= 3 { r.add("omega3", 20, "Poisson gras au moins 3 fois par semaine") }
        else if fish >= 2 { r.add("omega3", 10, "Poisson gras 2 fois par semaine") }
        else if fish == 1 { r.add("omega3", 3, "Poisson gras une fois par semaine") }
        else if fish == 0 { r.add("omega3", -25, "Pas de poisson gras") }
        if seeds >= 2 { r.add("omega3", 8, libGrainesQuotidiennes) }
        else if seeds >= 1 { r.add("omega3", 3, libGrainesPresque) }
        if nuts >= 5 { r.add("omega3", 4, libOleagineux) }
        if ["souvent", "often", "constant"].contains(snacking) { r.add("omega3", -5, libGrignotage) }
        if isSmoker { r.add("omega3", -8, libTabac) }

        // ═══════ VITAMINE C ═══════
        if fruit >= 14 { r.add("vitC", 20, libFruitsQuotidiens) }
        else if fruit >= 7 { r.add("vitC", 5, libFruitsReguliers) }
        else if fruit < 4 { r.add("vitC", -20, libPeuFruits) }
        if vegs >= 5 { r.add("vitC", 12, libLegumesQuotidiens) }
        else if vegs >= 3 { r.add("vitC", 5, libLegumesReguliers) }
        else if vegs < 2 { r.add("vitC", -10, libPeuLegumes) }
        if isSmoker { r.add("vitC", -25, libTabac) }
        if ["very", "explode"].contains(p.stressLevel) { r.add("vitC", -5, "Stress élevé") }
        if ["regular", "heavy"].contains(p.alcohol) { r.add("vitC", -5, libAlcoolRegulier) }
        if age > 65 { r.add("vitC", -5, "Plus de 65 ans") }

        // ═══════ CALCIUM ═══════
        if dairy >= 14 { r.add("calcium", 20, "Produits laitiers quotidiens") }
        else if dairy >= 7 { r.add("calcium", 5, "Produits laitiers réguliers") }
        else if dairy < 3 { r.add("calcium", -25, "Très peu de produits laitiers") }
        if vegs >= 5 { r.add("calcium", 5, libLegumesQuotidiens) }
        if legumes >= 3 { r.add("calcium", 3, libLegumineuses) }
        if age > 50 { r.add("calcium", -8, "Plus de 50 ans") }
        if p.lowCarbDiet == "yes" { r.add("calcium", -5, libPeuGlucides) }
        if isSmoker { r.add("calcium", -5, libTabac) }
        if let bmi, bmi < 18.5 { r.add("calcium", -8, "IMC inférieur à 18,5") }
        if isActive { r.add("calcium", 5, libSport) }

        // ═══════ ZINC ═══════
        if meat == 0 { r.add("zinc", -25, libPasViande) }
        else if meat <= 3 { r.add("zinc", -10, libViandeRare) }
        else if meat >= 7 { r.add("zinc", 8, libViandeQuotidienne) }
        if isActive { r.add("zinc", -5, libSport) }
        if nuts >= 5 { r.add("zinc", 8, libOleagineux) }
        if eggs >= 5 { r.add("zinc", 5, libOeufsReguliers) }
        if legumes >= 3 { r.add("zinc", 3, libLegumineuses) }
        if p.breadType == "sourdough" { r.add("zinc", 5, "Pain au levain") }
        if age > 65 { r.add("zinc", -5, "Plus de 65 ans") }
        if ["regular", "heavy"].contains(p.alcohol) { r.add("zinc", -5, libAlcoolRegulier) }
        if p.bloating == "yes" { r.add("zinc", -3, "Ballonnements fréquents") }

        // ═══════ IODE ═══════
        if p.iodizedSalt == "no" {
            r.add("iodine", -12, "Sel non iodé")
        } else if p.iodizedSalt == "yes" && p.saltLevel == "none" {
            r.add("iodine", -8, "Sel iodé mais très peu de sel")
        } else if p.iodizedSalt == "yes" && ["moderate", "a_lot"].contains(p.saltLevel) {
            r.add("iodine", 8, "Sel iodé au quotidien")
        }
        if fish >= 2 { r.add("iodine", 12, "Poisson 2 fois par semaine") }
        else if fish >= 1 { r.add("iodine", 5, "Poisson une fois par semaine") }
        if dairy >= 7 { r.add("iodine", 10, "Produits laitiers réguliers") }
        else if dairy >= 3 { r.add("iodine", 5, "Quelques produits laitiers") }
        if eggs >= 3 { r.add("iodine", 5, libOeufsReguliers) }
        if p.dietType == "sans_gluten" { r.add("iodine", -5, "Alimentation sans gluten") }

        // ═══════ FIBRES ═══════
        if p.breadType == "white" { r.add("fiber", -15, "Pain blanc") }
        else if p.breadType == "whole_grain" || p.breadType == "sourdough" { r.add("fiber", 10, libPainComplet) }
        if fruit >= 14 { r.add("fiber", 15, libFruitsQuotidiens) }
        else if fruit >= 7 { r.add("fiber", 5, libFruitsReguliers) }
        else if fruit < 4 { r.add("fiber", -10, libPeuFruits) }
        if vegs >= 5 { r.add("fiber", 12, libLegumesQuotidiens) }
        else if vegs >= 3 { r.add("fiber", 5, libLegumesReguliers) }
        else if vegs < 2 { r.add("fiber", -10, libPeuLegumes) }
        if legumes >= 5 { r.add("fiber", 12, "Légumineuses plusieurs fois par semaine") }
        else if legumes >= 2 { r.add("fiber", 5, libLegumineuses) }
        if wholegrain >= 7 { r.add("fiber", 10, "Céréales complètes quotidiennes") }
        else if wholegrain >= 3 { r.add("fiber", 5, "Céréales complètes régulières") }
        if p.lowCarbDiet == "yes" { r.add("fiber", -10, libPeuGlucides) }
        if seeds >= 2 { r.add("fiber", 8, libGrainesQuotidiennes) }
        else if seeds >= 1 { r.add("fiber", 3, libGrainesPresque) }
        if p.bloating == "yes" && p.antibiotics == "yes" { r.add("fiber", -5, "Ballonnements après antibiotiques") }
        if ["often", "constant", "souvent"].contains(snacking) { r.add("fiber", -5, libGrignotage) }
        if ["often", "daily"].contains(ultraProcessed) {
            r.add(["fiber", "zinc"], [-8, -5], libUltraTransformes)
        }
        if waterL < 1 { r.add("fiber", -5, libPeuEau) }
        if nuts >= 5 { r.add("fiber", 3, libOleagineux) }

        // ═══════ INTERACTIONS AVEC LES TRAITEMENTS ═══════
        if medications.contains("ppi") {
            r.add(["magnesium", "vitB12", "iron", "calcium"], [-10, -12, -8, -8], "Traitement contre les remontées acides")
        }
        if medications.contains("metformin") { r.add("vitB12", -15, "Metformine") }
        if medications.contains("oral_contraceptive") {
            r.add(["magnesium", "zinc"], [-5, -5], "Contraceptif oral")
        }
        if medications.contains("diuretics") {
            r.add(["magnesium", "zinc"], [-10, -5], "Diurétiques")
        }

        // ═══════ CUISSON & MODE DE VIE ═══════
        if cookingMethod == "boiled" {
            r.add(["vitC", "fiber"], [-10, -3], "Cuisson à l'eau")
        }
        if ["mostly_out", "rarely"].contains(homeCookedPct) {
            r.add(["fiber", "zinc", "magnesium"], [-8, -5, -5], "Repas surtout pris dehors")
        }
        if fermented == "never" { r.add("calcium", -3, "Jamais d'aliments fermentés") }

        // Règles
        if periodFlow == "very_heavy" { r.add("iron", -15, "Règles très abondantes") }
        else if periodFlow == "heavy" { r.add("iron", -8, "Règles abondantes") }

        // Grossesse
        if pregnancyStatus == "pregnant" {
            r.add(["iron", "iodine", "calcium"], [-15, -10, -5], "Grossesse")
        } else if pregnancyStatus == "breastfeeding" {
            r.add(["iodine", "calcium"], [-8, -5], "Allaitement")
        }

        // Absorption intestinale
        if conditions.contains(where: { ["celiac", "crohns_uc"].contains($0) }) {
            r.add(
                ["iron", "vitB12", "calcium", "zinc", "vitD"],
                [-15, -10, -10, -10, -10],
                "Condition digestive déclarée"
            )
        }

        // ═══════ COMPLÉMENTS DÉJÀ PRIS ═══════
        if currentSupps.contains("vitD") { r.add("vitD", 25, "Tu prends déjà de la vitamine D") }
        if currentSupps.contains("omega3") { r.add("omega3", 20, "Tu prends déjà des oméga-3") }
        if currentSupps.contains("magnesium") { r.add("magnesium", 20, "Tu prends déjà du magnésium") }
        if currentSupps.contains("iron") { r.add("iron", 15, "Tu prends déjà du fer") }
        if currentSupps.contains("b12") { r.add("vitB12", 20, "Tu prends déjà de la B12") }
        if currentSupps.contains("zinc") { r.add("zinc", 15, "Tu prends déjà du zinc") }
        if currentSupps.contains("folate") { r.add("fiber", 3, "Tu prends déjà des folates") }
        if currentSupps.contains("probiotics") { r.add("fiber", 5, "Tu prends déjà des probiotiques") }
        if currentSupps.contains("multivitamin") {
            r.add(
                ["vitD", "vitB12", "iron", "zinc", "vitC", "iodine"],
                [10, 15, 8, 8, 10, 10],
                "Tu prends déjà un multivitamines"
            )
        }

        // ═══════ TYPE D'ALIMENTATION ═══════
        if p.dietType == "vegan" {
            r.add(
                ["vitB12", "iron", "zinc", "omega3", "calcium", "iodine"],
                [-30, -15, -15, -10, -10, -8],
                "Alimentation végétalienne"
            )
        } else if p.dietType == "vegetarien" {
            r.add(["vitB12", "iron", "zinc"], [-15, -8, -8], "Alimentation végétarienne")
        }

        var detail: [String: DetailApport] = [:]
        for n in NutrientData.all { detail[n.id.rawValue] = r.detail(n.id.rawValue) }
        return detail
    }
}
