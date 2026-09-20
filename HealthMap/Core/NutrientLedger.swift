import Foundation

// MARK: - Registre des apports — « d'où sort ce chiffre ? »
//
// Le moteur de score calculait déjà, pour chaque apport, une suite de
// pénalités et de bonus nommés — puis n'en gardait que la somme. Ce fichier
// garde les lignes, avec la section du questionnaire d'où chacune vient.
//
// C'est la MÊME arithmétique qu'avant, à la ligne près : `analyzeNutrientScores`
// n'est plus qu'une projection de ce registre (`registreApports().mapValues(\.score)`).
// Il n'existe donc pas deux implémentations à tenir synchronisées, et
// `CrossRepoParityTests` (3 profils × 10 apports, valeurs figées depuis
// health.js) verrouille le tout : la moindre dérive d'un point casse la CI.
//
// Deux invariants portent l'affichage (maquette « anneau de cause », 20 sept. 2026) :
//
//   • la cascade part de `depart` (70) et retombe sur `brut` ; quand `brut`
//     sort de l'échelle 0-100, `score` le ramène et `estBorne` le dit plutôt
//     que de mentir sur le total ;
//   • l'anneau (`parts`) ferme TOUJOURS à 100 : la part couverte vaut le score,
//     chaque frein prend ses points tant qu'il reste de la place dans l'arc
//     manquant, et « autres facteurs » prend le reste — jamais redistribué.
//
// Le caddie « Faites vos courses » (`NutrientEngine`) n'a pas de registre :
// ces profils reçoivent un détail sans facteur nommé, l'anneau se réduit alors
// à « couvert » + « autres facteurs » et la fiche masque son bloc 02. Aucun
// chiffre inventé pour combler le trou.

/// Les six familles du questionnaire — la provenance affichée sous chaque
/// ligne de la cascade (« déclaré dans Santé »).
enum SectionQuestionnaire: String, CaseIterable {
    case profil = "Profil"
    case modeDeVie = "Mode de vie"
    case sante = "Santé"
    case nutrition = "Nutrition"
    case symptomes = "Symptômes"
    case medical = "Médical"
}

/// Un facteur nommé et son poids, en points d'apport.
struct ContributionApport: Equatable, Identifiable {
    /// Libellé lisible par la personne, tel qu'il s'affiche dans la fiche.
    let libelle: String
    /// Poids en points — négatif quand le facteur pèse sur l'apport.
    let delta: Int
    /// Où la personne l'a déclaré.
    let section: SectionQuestionnaire

    var id: String { "\(libelle)#\(delta)" }

    /// « déclaré dans Mode de vie » — le sous-texte de la ligne.
    var provenance: String { "déclaré dans \(section.rawValue)" }
}

/// Une part de l'anneau. Les parts d'un apport somment toujours à 100.
struct PartAnneau: Equatable, Identifiable {
    enum Genre: Equatable {
        case couvert
        /// Frein nommé, `rang` 0 = le plus lourd.
        case cause(rang: Int)
        case innomme
    }

    let id: String
    let libelle: String
    let valeur: Int
    let genre: Genre
}

/// Le détail d'un apport : point de départ, facteurs nommés, score final.
struct DetailApport: Equatable {

    /// Point de départ commun à tous les apports, avant le moindre facteur.
    static let pointDeDepart = 70

    /// Identifiant stable de la part « autres facteurs ».
    static let idInnomme = "innomme"
    /// Identifiant stable de la part couverte.
    static let idCouvert = "couvert"

    /// Facteurs nommés, dans l'ordre où le moteur les applique.
    let contributions: [ContributionApport]
    /// Score final borné 0-100 — identique à `analyzeNutrientScores`.
    let score: Int

    var depart: Int { Self.pointDeDepart }

    /// Total avant bornage : `depart` + tous les deltas.
    var brut: Int { depart + contributions.reduce(0) { $0 + $1.delta } }

    /// Vrai quand le bornage 0-100 a dû intervenir : la cascade ne retombe
    /// alors pas sur `score`, et la fiche doit le dire.
    var estBorne: Bool { brut != score }

    /// L'écart signé entre le total brut et le score affiché (`score - brut`).
    var correctionBornage: Int { score - brut }

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
    /// Règle de la maquette : la part couverte vaut le score ; chaque frein
    /// prend ses points tant que l'arc manquant en offre ; « autres facteurs »
    /// prend ce qui reste. Une part peut valoir 0 (l'anneau ne la dessine pas),
    /// jamais moins.
    var parts: [PartAnneau] {
        var sortie = [PartAnneau(id: Self.idCouvert, libelle: "Couvert", valeur: score, genre: .couvert)]
        var utilise = score
        for (rang, frein) in freins.enumerated() {
            let valeur = min(abs(frein.delta), max(0, 100 - utilise))
            sortie.append(PartAnneau(id: frein.id, libelle: frein.libelle, valeur: valeur, genre: .cause(rang: rang)))
            utilise += valeur
        }
        sortie.append(PartAnneau(
            id: Self.idInnomme,
            libelle: "Autres facteurs",
            valeur: max(0, 100 - utilise),
            genre: .innomme
        ))
        return sortie
    }
}

// MARK: - Le registre

extension HealthCalculator {

    /// Accumulateur : une ligne nommée par facteur appliqué.
    private struct Registre {
        private var lignes: [String: [ContributionApport]] = [:]

        mutating func add(_ id: String, _ delta: Int, _ libelle: String, _ section: SectionQuestionnaire) {
            guard delta != 0 else { return }
            lignes[id, default: []].append(ContributionApport(libelle: libelle, delta: delta, section: section))
        }

        /// Même facteur, même provenance, sur plusieurs apports à la fois.
        mutating func add(_ ids: [String], _ deltas: [Int], _ libelle: String, _ section: SectionQuestionnaire) {
            for (id, delta) in zip(ids, deltas) { add(id, delta, libelle, section) }
        }

        /// Facteur piloté par une table clé → poids, avec sa table de libellés.
        mutating func addTable(
            _ id: String,
            _ poids: [String: Int],
            _ libelles: [String: String],
            _ cle: String,
            _ section: SectionQuestionnaire
        ) {
            guard let delta = poids[cle], let libelle = libelles[cle] else { return }
            add(id, delta, libelle, section)
        }

        func detail(_ id: String) -> DetailApport {
            let contributions = lignes[id] ?? []
            let brut = DetailApport.pointDeDepart + contributions.reduce(0) { $0 + $1.delta }
            return DetailApport(contributions: contributions, score: max(0, min(100, brut)))
        }
    }

    /// Le détail de chaque apport — même arithmétique que `analyzeNutrientScores`.
    ///
    /// Renvoie un dictionnaire vide pour un profil hors bornes, exactement
    /// comme le calcul de score.
    static func registreApports(profile: UserProfile) -> [String: DetailApport] {
        // Caddie rempli : le score vient de NutrientEngine, qui ne tient pas
        // de registre. On rend le score sans facteur nommé plutôt que d'en
        // inventer.
        if !profile.groceries.isEmpty {
            return NutrientEngine.nutrientScores(profile: profile).mapValues {
                DetailApport(contributions: [], score: $0)
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
        if p.indoorWork == "yes" { r.add("vitD", -25, "Travail en intérieur", .modeDeVie) }
        let sun = ["none": -30, "very_little": -20, "some": -5, "moderate": 5, "plenty": 15]
        let sunLib = [
            "none": "Jamais au soleil",
            "very_little": "Très peu de soleil",
            "some": "Un peu de soleil",
            "moderate": "Soleil régulier",
            "plenty": "Beaucoup de soleil",
        ]
        r.addTable("vitD", sun, sunLib, p.sunExposure, .modeDeVie)
        if age > 70 { r.add("vitD", -15, "Plus de 70 ans", .profil) }
        else if age > 50 { r.add("vitD", -10, "Plus de 50 ans", .profil) }
        let skinPenalty = ["very_fair": 0, "fair": -3, "medium": -8, "olive": -15, "dark": -22]
        let skinLib = [
            "very_fair": "Peau très claire",
            "fair": "Peau claire",
            "medium": "Peau intermédiaire",
            "olive": "Peau mate",
            "dark": "Peau foncée",
        ]
        r.addTable("vitD", skinPenalty, skinLib, p.skinType, .profil)
        if fish >= 3 { r.add("vitD", 8, "Poisson gras au moins 3 fois par semaine", .nutrition) }
        if dairy >= 10 { r.add("vitD", 5, "Produits laitiers quotidiens", .nutrition) }
        if let bmi, bmi > 30 { r.add("vitD", -8, "IMC supérieur à 30", .profil) }
        if sleepHours < 6 { r.add("vitD", -5, libNuitsCourtes, .modeDeVie) }

        // ═══════ VITAMINE B12 ═══════
        if meat == 0 && eggs == 0 && fish == 0 { r.add("vitB12", -45, "Ni viande, ni œufs, ni poisson", .nutrition) }
        else if meat <= 2 && eggs <= 2 && fish == 0 { r.add("vitB12", -20, "Très peu de produits animaux", .nutrition) }
        else if meat >= 5 && eggs >= 3 { r.add("vitB12", 10, "Viande et œufs réguliers", .nutrition) }
        let alcoholB12 = ["none": 0, "rarely": 0, "moderate": -5, "regular": -15, "heavy": -25]
        let alcoholLib = [
            "none": "Pas d'alcool",
            "rarely": "Alcool rare",
            "moderate": "Alcool modéré",
            "regular": libAlcoolRegulier,
            "heavy": "Alcool fréquent",
        ]
        r.addTable("vitB12", alcoholB12, alcoholLib, p.alcohol, .modeDeVie)
        if p.eatLiver == "yes" { r.add("vitB12", 15, libAbats, .nutrition) }
        if age > 60 { r.add("vitB12", -10, "Plus de 60 ans", .profil) }
        else if age > 50 { r.add("vitB12", -5, "Plus de 50 ans", .profil) }
        if p.antibiotics == "yes" { r.add("vitB12", -5, "Antibiotiques récents", .sante) }

        // ═══════ FER ═══════
        if meat == 0 { r.add("iron", -30, libPasViande, .nutrition) }
        else if meat <= 3 { r.add("iron", -10, libViandeRare, .nutrition) }
        else if meat >= 7 { r.add("iron", 8, libViandeQuotidienne, .nutrition) }
        if p.gender == .femme {
            if age < 50 { r.add("iron", -15, "Femme de moins de 50 ans", .profil) }
            else { r.add("iron", -5, "Femme de plus de 50 ans", .profil) }
        }
        if isActive { r.add("iron", -5, libSport, .modeDeVie) }
        if fruit >= 14 || vegs >= 5 { r.add("iron", 5, "Fruits et légumes riches en vitamine C", .nutrition) }
        if caffeine == "heavy" { r.add("iron", -12, libCafeBeaucoup, .modeDeVie) }
        else if caffeine == "moderate" { r.add("iron", -5, libCafeModere, .modeDeVie) }
        if caffeineWithMeals && caffeine != "none" { r.add("iron", -10, "Café ou thé pendant les repas", .nutrition) }
        if hasReflux { r.add("iron", -8, "Remontées acides déclarées", .sante) }
        if legumes >= 3 { r.add("iron", 5, libLegumineuses, .nutrition) }
        if p.eatLiver == "yes" { r.add("iron", 10, libAbats, .nutrition) }
        if let bmi, bmi < 18.5 { r.add("iron", -8, "IMC inférieur à 18,5", .profil) }
        if p.alcohol == "heavy" { r.add("iron", -8, "Alcool fréquent", .modeDeVie) }

        // ═══════ MAGNÉSIUM ═══════
        let stressMg = ["zen": 5, "relaxed": 0, "somewhat": -8, "very": -15, "explode": -20]
        let stressLib = [
            "zen": "Stress très bas",
            "relaxed": "Stress bas",
            "somewhat": "Stress modéré",
            "very": "Stress élevé",
            "explode": "Stress très élevé",
        ]
        r.addTable("magnesium", stressMg, stressLib, p.stressLevel, .modeDeVie)
        if isActive { r.add("magnesium", -10, libSport, .modeDeVie) }
        if nuts >= 7 { r.add("magnesium", 12, "Oléagineux quotidiens", .nutrition) }
        else if nuts >= 3 { r.add("magnesium", 5, libOleagineux, .nutrition) }
        if p.breadType == "whole_grain" || p.breadType == "sourdough" { r.add("magnesium", 10, libPainComplet, .nutrition) }
        if sleepHours < 6 { r.add("magnesium", -8, libNuitsCourtes, .modeDeVie) }
        if caffeine == "heavy" { r.add("magnesium", -10, libCafeBeaucoup, .modeDeVie) }
        else if caffeine == "moderate" { r.add("magnesium", -4, libCafeModere, .modeDeVie) }
        if ["very", "explode"].contains(p.stressLevel) && sleepHours < 7 && ["long", "very_long"].contains(screenBed) {
            r.add("magnesium", -8, "Stress, nuits courtes et écrans le soir", .modeDeVie)
        }
        if p.lowCarbDiet == "yes" { r.add("magnesium", -8, libPeuGlucides, .nutrition) }
        if legumes >= 3 { r.add("magnesium", 5, libLegumineuses, .nutrition) }
        if wholegrain >= 5 { r.add("magnesium", 5, "Céréales complètes régulières", .nutrition) }
        if ["regular", "heavy"].contains(p.alcohol) { r.add("magnesium", -8, libAlcoolRegulier, .modeDeVie) }
        if waterL < 1 { r.add("magnesium", -5, libPeuEau, .modeDeVie) }
        if age > 70 { r.add("magnesium", -8, "Plus de 70 ans", .profil) }

        // ═══════ OMÉGA-3 ═══════
        if fish >= 3 { r.add("omega3", 20, "Poisson gras au moins 3 fois par semaine", .nutrition) }
        else if fish >= 2 { r.add("omega3", 10, "Poisson gras 2 fois par semaine", .nutrition) }
        else if fish == 1 { r.add("omega3", 3, "Poisson gras une fois par semaine", .nutrition) }
        else if fish == 0 { r.add("omega3", -25, "Pas de poisson gras", .nutrition) }
        if seeds >= 2 { r.add("omega3", 8, libGrainesQuotidiennes, .nutrition) }
        else if seeds >= 1 { r.add("omega3", 3, libGrainesPresque, .nutrition) }
        if nuts >= 5 { r.add("omega3", 4, libOleagineux, .nutrition) }
        if ["souvent", "often", "constant"].contains(snacking) { r.add("omega3", -5, libGrignotage, .nutrition) }
        if isSmoker { r.add("omega3", -8, libTabac, .modeDeVie) }

        // ═══════ VITAMINE C ═══════
        if fruit >= 14 { r.add("vitC", 20, libFruitsQuotidiens, .nutrition) }
        else if fruit >= 7 { r.add("vitC", 5, libFruitsReguliers, .nutrition) }
        else if fruit < 4 { r.add("vitC", -20, libPeuFruits, .nutrition) }
        if vegs >= 5 { r.add("vitC", 12, libLegumesQuotidiens, .nutrition) }
        else if vegs >= 3 { r.add("vitC", 5, libLegumesReguliers, .nutrition) }
        else if vegs < 2 { r.add("vitC", -10, libPeuLegumes, .nutrition) }
        if isSmoker { r.add("vitC", -25, libTabac, .modeDeVie) }
        if ["very", "explode"].contains(p.stressLevel) { r.add("vitC", -5, "Stress élevé", .modeDeVie) }
        if ["regular", "heavy"].contains(p.alcohol) { r.add("vitC", -5, libAlcoolRegulier, .modeDeVie) }
        if age > 65 { r.add("vitC", -5, "Plus de 65 ans", .profil) }

        // ═══════ CALCIUM ═══════
        if dairy >= 14 { r.add("calcium", 20, "Produits laitiers quotidiens", .nutrition) }
        else if dairy >= 7 { r.add("calcium", 5, "Produits laitiers réguliers", .nutrition) }
        else if dairy < 3 { r.add("calcium", -25, "Très peu de produits laitiers", .nutrition) }
        if vegs >= 5 { r.add("calcium", 5, libLegumesQuotidiens, .nutrition) }
        if legumes >= 3 { r.add("calcium", 3, libLegumineuses, .nutrition) }
        if age > 50 { r.add("calcium", -8, "Plus de 50 ans", .profil) }
        if p.lowCarbDiet == "yes" { r.add("calcium", -5, libPeuGlucides, .nutrition) }
        if isSmoker { r.add("calcium", -5, libTabac, .modeDeVie) }
        if let bmi, bmi < 18.5 { r.add("calcium", -8, "IMC inférieur à 18,5", .profil) }
        if isActive { r.add("calcium", 5, libSport, .modeDeVie) }

        // ═══════ ZINC ═══════
        if meat == 0 { r.add("zinc", -25, libPasViande, .nutrition) }
        else if meat <= 3 { r.add("zinc", -10, libViandeRare, .nutrition) }
        else if meat >= 7 { r.add("zinc", 8, libViandeQuotidienne, .nutrition) }
        if isActive { r.add("zinc", -5, libSport, .modeDeVie) }
        if nuts >= 5 { r.add("zinc", 8, libOleagineux, .nutrition) }
        if eggs >= 5 { r.add("zinc", 5, libOeufsReguliers, .nutrition) }
        if legumes >= 3 { r.add("zinc", 3, libLegumineuses, .nutrition) }
        if p.breadType == "sourdough" { r.add("zinc", 5, "Pain au levain", .nutrition) }
        if age > 65 { r.add("zinc", -5, "Plus de 65 ans", .profil) }
        if ["regular", "heavy"].contains(p.alcohol) { r.add("zinc", -5, libAlcoolRegulier, .modeDeVie) }
        if p.bloating == "yes" { r.add("zinc", -3, "Ballonnements fréquents", .sante) }

        // ═══════ IODE ═══════
        if p.iodizedSalt == "no" {
            r.add("iodine", -12, "Sel non iodé", .nutrition)
        } else if p.iodizedSalt == "yes" && p.saltLevel == "none" {
            r.add("iodine", -8, "Sel iodé mais très peu de sel", .nutrition)
        } else if p.iodizedSalt == "yes" && ["moderate", "a_lot"].contains(p.saltLevel) {
            r.add("iodine", 8, "Sel iodé au quotidien", .nutrition)
        }
        if fish >= 2 { r.add("iodine", 12, "Poisson 2 fois par semaine", .nutrition) }
        else if fish >= 1 { r.add("iodine", 5, "Poisson une fois par semaine", .nutrition) }
        if dairy >= 7 { r.add("iodine", 10, "Produits laitiers réguliers", .nutrition) }
        else if dairy >= 3 { r.add("iodine", 5, "Quelques produits laitiers", .nutrition) }
        if eggs >= 3 { r.add("iodine", 5, libOeufsReguliers, .nutrition) }
        if p.dietType == "sans_gluten" { r.add("iodine", -5, "Alimentation sans gluten", .nutrition) }

        // ═══════ FIBRES ═══════
        if p.breadType == "white" { r.add("fiber", -15, "Pain blanc", .nutrition) }
        else if p.breadType == "whole_grain" || p.breadType == "sourdough" { r.add("fiber", 10, libPainComplet, .nutrition) }
        if fruit >= 14 { r.add("fiber", 15, libFruitsQuotidiens, .nutrition) }
        else if fruit >= 7 { r.add("fiber", 5, libFruitsReguliers, .nutrition) }
        else if fruit < 4 { r.add("fiber", -10, libPeuFruits, .nutrition) }
        if vegs >= 5 { r.add("fiber", 12, libLegumesQuotidiens, .nutrition) }
        else if vegs >= 3 { r.add("fiber", 5, libLegumesReguliers, .nutrition) }
        else if vegs < 2 { r.add("fiber", -10, libPeuLegumes, .nutrition) }
        if legumes >= 5 { r.add("fiber", 12, "Légumineuses plusieurs fois par semaine", .nutrition) }
        else if legumes >= 2 { r.add("fiber", 5, libLegumineuses, .nutrition) }
        if wholegrain >= 7 { r.add("fiber", 10, "Céréales complètes quotidiennes", .nutrition) }
        else if wholegrain >= 3 { r.add("fiber", 5, "Céréales complètes régulières", .nutrition) }
        if p.lowCarbDiet == "yes" { r.add("fiber", -10, libPeuGlucides, .nutrition) }
        if seeds >= 2 { r.add("fiber", 8, libGrainesQuotidiennes, .nutrition) }
        else if seeds >= 1 { r.add("fiber", 3, libGrainesPresque, .nutrition) }
        if p.bloating == "yes" && p.antibiotics == "yes" { r.add("fiber", -5, "Ballonnements après antibiotiques", .sante) }
        if ["often", "constant", "souvent"].contains(snacking) { r.add("fiber", -5, libGrignotage, .nutrition) }
        if ["often", "daily"].contains(ultraProcessed) {
            r.add(["fiber", "zinc"], [-8, -5], libUltraTransformes, .nutrition)
        }
        if waterL < 1 { r.add("fiber", -5, libPeuEau, .modeDeVie) }
        if nuts >= 5 { r.add("fiber", 3, libOleagineux, .nutrition) }

        // ═══════ INTERACTIONS AVEC LES TRAITEMENTS ═══════
        if medications.contains("ppi") {
            r.add(["magnesium", "vitB12", "iron", "calcium"], [-10, -12, -8, -8], "Traitement contre les remontées acides", .medical)
        }
        if medications.contains("metformin") { r.add("vitB12", -15, "Metformine", .medical) }
        if medications.contains("oral_contraceptive") {
            r.add(["magnesium", "zinc"], [-5, -5], "Contraceptif oral", .medical)
        }
        if medications.contains("diuretics") {
            r.add(["magnesium", "zinc"], [-10, -5], "Diurétiques", .medical)
        }

        // ═══════ CUISSON & MODE DE VIE ═══════
        if cookingMethod == "boiled" {
            r.add(["vitC", "fiber"], [-10, -3], "Cuisson à l'eau", .nutrition)
        }
        if ["mostly_out", "rarely"].contains(homeCookedPct) {
            r.add(["fiber", "zinc", "magnesium"], [-8, -5, -5], "Repas surtout pris dehors", .nutrition)
        }
        if fermented == "never" { r.add("calcium", -3, "Jamais d'aliments fermentés", .nutrition) }

        // Règles
        if periodFlow == "very_heavy" { r.add("iron", -15, "Règles très abondantes", .sante) }
        else if periodFlow == "heavy" { r.add("iron", -8, "Règles abondantes", .sante) }

        // Grossesse
        if pregnancyStatus == "pregnant" {
            r.add(["iron", "iodine", "calcium"], [-15, -10, -5], "Grossesse", .sante)
        } else if pregnancyStatus == "breastfeeding" {
            r.add(["iodine", "calcium"], [-8, -5], "Allaitement", .sante)
        }

        // Absorption intestinale
        if conditions.contains(where: { ["celiac", "crohns_uc"].contains($0) }) {
            r.add(
                ["iron", "vitB12", "calcium", "zinc", "vitD"],
                [-15, -10, -10, -10, -10],
                "Condition digestive déclarée",
                .sante
            )
        }

        // Opérations, antécédents et allergies : bloc PARTAGÉ avec NutrientEngine
        // (`applyMedicalHistoryPenalties`), qu'il ne faut surtout pas recopier —
        // c'est ainsi que les deux moteurs ont divergé par le passé. On l'exécute
        // donc tel quel sur une ardoise à zéro, et on lit son effet par apport :
        // une ligne agrégée, exacte au point près. Le jour où ce bloc saura nommer
        // chacune de ses pénalités, la cascade pourra les détailler.
        var ardoise: [String: Int] = [:]
        for n in NutrientData.all { ardoise[n.id.rawValue] = 0 }
        NutrientEngine.applyMedicalHistoryPenalties(&ardoise, profile: p)
        for n in NutrientData.all {
            r.add(n.id.rawValue, ardoise[n.id.rawValue] ?? 0, "Antécédents, opérations et allergies", .medical)
        }

        // ═══════ COMPLÉMENTS DÉJÀ PRIS ═══════
        if currentSupps.contains("vitD") { r.add("vitD", 25, "Tu prends déjà de la vitamine D", .medical) }
        if currentSupps.contains("omega3") { r.add("omega3", 20, "Tu prends déjà des oméga-3", .medical) }
        if currentSupps.contains("magnesium") { r.add("magnesium", 20, "Tu prends déjà du magnésium", .medical) }
        if currentSupps.contains("iron") { r.add("iron", 15, "Tu prends déjà du fer", .medical) }
        if currentSupps.contains("b12") { r.add("vitB12", 20, "Tu prends déjà de la B12", .medical) }
        if currentSupps.contains("zinc") { r.add("zinc", 15, "Tu prends déjà du zinc", .medical) }
        if currentSupps.contains("folate") { r.add("fiber", 3, "Tu prends déjà des folates", .medical) }
        if currentSupps.contains("probiotics") { r.add("fiber", 5, "Tu prends déjà des probiotiques", .medical) }
        if currentSupps.contains("multivitamin") {
            r.add(
                ["vitD", "vitB12", "iron", "zinc", "vitC", "iodine"],
                [10, 15, 8, 8, 10, 10],
                "Tu prends déjà un multivitamines",
                .medical
            )
        }

        // ═══════ TYPE D'ALIMENTATION ═══════
        if p.dietType == "vegan" {
            r.add(
                ["vitB12", "iron", "zinc", "omega3", "calcium", "iodine"],
                [-30, -15, -15, -10, -10, -8],
                "Alimentation végétalienne",
                .nutrition
            )
        } else if p.dietType == "vegetarien" {
            r.add(["vitB12", "iron", "zinc"], [-15, -8, -8], "Alimentation végétarienne", .nutrition)
        }

        var detail: [String: DetailApport] = [:]
        for n in NutrientData.all { detail[n.id.rawValue] = r.detail(n.id.rawValue) }
        return detail
    }
}
