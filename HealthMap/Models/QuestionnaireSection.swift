import Foundation

// MARK: - Questionnaire Sections (6 sections, mirrors Home.jsx)
enum QuestionnaireSection: Int, CaseIterable, Identifiable {
    case profil = 0
    case modeDeVie = 1
    case sante = 2
    case nutrition = 3
    case symptomes = 4
    case medical = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .profil: return "Profil"
        case .modeDeVie: return "Mode de vie"
        case .sante: return "Sante"
        case .nutrition: return "Nutrition"
        case .symptomes: return "Symptomes"
        case .medical: return "Medical"
        }
    }

    var emoji: String {
        switch self {
        case .profil: return "👤"
        case .modeDeVie: return "☀️"
        case .sante: return "❤️"
        case .nutrition: return "🥝"
        case .symptomes: return "🔍"
        case .medical: return "💊"
        }
    }

    var questions: [Question] {
        switch self {
        case .profil: return Self.profilQuestions
        case .modeDeVie: return Self.modeDeVieQuestions
        case .sante: return Self.santeQuestions
        case .nutrition: return Self.nutritionQuestions
        case .symptomes: return Self.symptomesQuestions
        case .medical: return Self.medicalQuestions
        }
    }

    /// Express pathway keys (21 questions)
    static let expressKeys: Set<String> = [
        "goals", "firstName", "age", "gender", "height", "weight",
        "indoorWork", "sunExposure", "strengthTraining",
        "stressLevel", "sleepHours", "wakeFeeling", "caffeineIntake", "waterIntake", "smoking",
        "dietType", "vegetableServings", "fruitServings", "fattyFish", "meatPoultry", "dairyServings",
    ]
}

// MARK: - Question Model
struct Question: Identifiable {
    let id: String           // key in UserProfile
    let text: String
    let type: QuestionType
    let options: [QuestionOption]?
    let showIf: ((UserProfile) -> Bool)?
    let isExpressOnly: Bool

    init(
        id: String,
        text: String,
        type: QuestionType,
        options: [QuestionOption]? = nil,
        showIf: ((UserProfile) -> Bool)? = nil,
        isExpressOnly: Bool = false
    ) {
        self.id = id
        self.text = text
        self.type = type
        self.options = options
        self.showIf = showIf
        self.isExpressOnly = isExpressOnly
    }
}

enum QuestionType {
    case singleChoice
    case multiChoice
    case textInput(placeholder: String)
    case numericInput(placeholder: String, suffix: String?)
}

struct QuestionOption: Identifiable {
    let id: String
    let label: String
    let emoji: String?

    init(_ id: String, _ label: String, emoji: String? = nil) {
        self.id = id
        self.label = label
        self.emoji = emoji
    }
}

// MARK: - Section 1: Profil
extension QuestionnaireSection {
    static let profilQuestions: [Question] = [
        Question(
            id: "goals",
            text: "Qu'est-ce qui t'amene ?",
            type: .multiChoice,
            options: [
                .init("sleep", "Mieux dormir", emoji: "😴"),
                .init("energie", "Plus d'energie", emoji: "⚡"),
                .init("stress", "Gerer mon stress", emoji: "🧘"),
                .init("perte_poids", "Perdre du poids", emoji: "🎯"),
                .init("muscle", "Prendre du muscle", emoji: "💪"),
                .init("equilibre", "Equilibre nutritionnel", emoji: "🥗"),
            ]
        ),
        Question(id: "firstName", text: "Comment tu t'appelles ?", type: .textInput(placeholder: "Prenom")),
        Question(id: "age", text: "Quel age as-tu ?", type: .numericInput(placeholder: "25", suffix: "ans")),
        Question(
            id: "gender",
            text: "Tu es...",
            type: .singleChoice,
            options: [.init("homme", "Homme", emoji: "👨"), .init("femme", "Femme", emoji: "👩")]
        ),
        Question(id: "height", text: "Ta taille", type: .numericInput(placeholder: "175", suffix: "cm")),
        Question(id: "weight", text: "Ton poids", type: .numericInput(placeholder: "70", suffix: "kg")),
        Question(
            id: "weightTrend",
            text: "Tendance de ton poids ces derniers mois ?",
            type: .singleChoice,
            options: [
                .init("stable", "Stable"),
                .init("gaining_intentionally", "En hausse (voulu)"),
                .init("gaining_unintentionally", "En hausse (involontaire)"),
                .init("losing_intentionally", "En baisse (voulu)"),
                .init("losing_unintentionally", "En baisse (involontaire)"),
            ]
        ),
    ]
}

// MARK: - Section 2: Mode de vie
extension QuestionnaireSection {
    static let modeDeVieQuestions: [Question] = [
        Question(
            id: "indoorWork",
            text: "Tu travailles principalement en interieur ?",
            type: .singleChoice,
            options: [.init("yes", "Oui"), .init("no", "Non")]
        ),
        Question(
            id: "sunExposure",
            text: "Ton exposition au soleil ?",
            type: .singleChoice,
            options: [
                .init("none", "Quasi nulle", emoji: "🌑"),
                .init("very_little", "Tres peu", emoji: "🌥️"),
                .init("some", "Un peu", emoji: "⛅"),
                .init("moderate", "Moderee", emoji: "🌤️"),
                .init("plenty", "Beaucoup", emoji: "☀️"),
            ]
        ),
        Question(
            id: "skinType",
            text: "Ton type de peau ?",
            type: .singleChoice,
            options: [
                .init("very_fair", "Tres claire"),
                .init("fair", "Claire"),
                .init("medium", "Moyenne"),
                .init("olive", "Mate"),
                .init("dark", "Foncee"),
            ]
        ),
        Question(
            id: "strengthTraining",
            text: "Ton niveau d'activite physique ?",
            type: .singleChoice,
            options: [
                .init("none", "Sedentaire", emoji: "🛋️"),
                .init("light", "Leger (1-2x/sem)", emoji: "🚶"),
                .init("moderate", "Modere (3-4x/sem)", emoji: "🏃"),
                .init("regular", "Regulier (4-5x/sem)", emoji: "🏋️"),
                .init("intense", "Intense (6+/sem)", emoji: "🔥"),
            ]
        ),
    ]
}

// MARK: - Section 3: Sante
extension QuestionnaireSection {
    static let santeQuestions: [Question] = [
        Question(
            id: "stressLevel",
            text: "Ton niveau de stress ?",
            type: .singleChoice,
            options: [
                .init("zen", "Zen", emoji: "🧘"),
                .init("relaxed", "Detendu", emoji: "😌"),
                .init("somewhat", "Moyen", emoji: "😐"),
                .init("very", "Stresse", emoji: "😰"),
                .init("explode", "Au max", emoji: "🤯"),
            ]
        ),
        Question(
            id: "sleepHours",
            text: "Combien d'heures tu dors ?",
            type: .singleChoice,
            options: [
                .init("4", "< 5h"), .init("5.5", "5-6h"), .init("6.5", "6-7h"),
                .init("7.5", "7-8h"), .init("8.5", "8-9h"), .init("10", "9h+"),
            ]
        ),
        Question(
            id: "wakeFeeling",
            text: "Comment tu te sens au reveil ?",
            type: .singleChoice,
            options: [
                .init("great", "En pleine forme", emoji: "💪"),
                .init("good", "Bien", emoji: "😊"),
                .init("ok", "Moyen", emoji: "😐"),
                .init("bad", "Fatigue", emoji: "😩"),
                .init("terrible", "Epuise", emoji: "😵"),
            ]
        ),
        Question(
            id: "screenBeforeBed",
            text: "Ecrans avant de dormir ?",
            type: .singleChoice,
            options: [
                .init("none", "Aucun"), .init("short", "< 30 min"),
                .init("moderate", "30-60 min"), .init("long", "1-2h"), .init("very_long", "2h+"),
            ]
        ),
        Question(
            id: "caffeineIntake",
            text: "Ta consommation de cafeine ?",
            type: .singleChoice,
            options: [
                .init("none", "Aucune", emoji: "🚫"),
                .init("light", "1-2 cafes/jour", emoji: "☕"),
                .init("moderate", "3-4 cafes/jour", emoji: "☕☕"),
                .init("heavy", "5+ cafes/jour", emoji: "☕☕☕"),
            ]
        ),
        Question(
            id: "caffeineTiming",
            text: "Tu bois ton cafe pendant les repas ?",
            type: .singleChoice,
            options: [.init("with_meals", "Oui, pendant les repas"), .init("between", "Non, entre les repas"), .init("both", "Les deux")],
            showIf: { ["moderate", "heavy"].contains($0.caffeineIntake) }
        ),
        Question(
            id: "waterIntake",
            text: "Combien de verres d'eau par jour ?",
            type: .singleChoice,
            options: [
                .init("0.75", "< 3 verres"), .init("1.25", "3-5 verres"),
                .init("1.75", "6-7 verres"), .init("2.25", "8-9 verres"), .init("3", "10+ verres"),
            ]
        ),
        Question(
            id: "smoking",
            text: "Tu fumes ?",
            type: .singleChoice,
            options: [.init("no", "Non"), .init("yes", "Oui")]
        ),
        Question(
            id: "alcohol",
            text: "Ta consommation d'alcool ?",
            type: .singleChoice,
            options: [
                .init("none", "Jamais"), .init("rarely", "Rarement"),
                .init("moderate", "Moderee"), .init("regular", "Reguliere"), .init("heavy", "Importante"),
            ]
        ),
        Question(
            id: "bloating",
            text: "Tu as des ballonnements ?",
            type: .singleChoice,
            options: [.init("no", "Non"), .init("yes", "Oui")]
        ),
        Question(
            id: "antibiotics",
            text: "As-tu pris des antibiotiques recemment ?",
            type: .singleChoice,
            options: [.init("no", "Non"), .init("yes", "Oui")]
        ),
    ]
}

// MARK: - Section 4: Nutrition
extension QuestionnaireSection {
    static let nutritionQuestions: [Question] = [
        Question(
            id: "dietType",
            text: "Ton regime alimentaire ?",
            type: .singleChoice,
            options: [
                .init("omnivore", "Omnivore", emoji: "🥩"),
                .init("flexitarian", "Flexitarien", emoji: "🥗"),
                .init("vegetarien", "Vegetarien", emoji: "🥚"),
                .init("vegan", "Vegan", emoji: "🌱"),
                .init("sans_gluten", "Sans gluten", emoji: "🌾"),
                .init("halal", "Halal", emoji: "🍖"),
                .init("autre", "Autre", emoji: "🍽️"),
            ]
        ),
        Question(
            id: "mealsPerDay",
            text: "Combien de repas par jour ?",
            type: .singleChoice,
            options: [.init("2", "2"), .init("3", "3"), .init("4", "4"), .init("5+", "5+")]
        ),
        Question(
            id: "homeCookedPct",
            text: "Quelle part de fait maison ?",
            type: .singleChoice,
            options: [
                .init("almost_all", "100%"), .init("mostly", "Majoritairement"),
                .init("half", "50/50"), .init("mostly_out", "Surtout exterieur"),
                .init("rarely", "Rarement"),
            ]
        ),
        Question(
            id: "cookingMethod",
            text: "Ton mode de cuisson principal ?",
            type: .singleChoice,
            options: [
                .init("raw", "Cru"), .init("steamed", "Vapeur"),
                .init("sauteed", "Poele/saute"), .init("boiled", "Bouilli"),
                .init("mixed", "Varie"),
            ]
        ),
        Question(id: "vegetableServings", text: "Portions de legumes par semaine ?", type: .numericInput(placeholder: "10", suffix: "/sem")),
        Question(id: "fruitServings", text: "Portions de fruits par semaine ?", type: .numericInput(placeholder: "7", suffix: "/sem")),
        Question(id: "fattyFish", text: "Poisson gras par semaine ?", type: .numericInput(placeholder: "2", suffix: "/sem")),
        Question(id: "meatPoultry", text: "Viande/volaille par semaine ?", type: .numericInput(placeholder: "4", suffix: "/sem")),
        Question(id: "eggsPerWeek", text: "Oeufs par semaine ?", type: .numericInput(placeholder: "4", suffix: "/sem")),
        Question(id: "dairyServings", text: "Produits laitiers par semaine ?", type: .numericInput(placeholder: "7", suffix: "/sem")),
        Question(id: "legumesPerWeek", text: "Legumineuses par semaine ?", type: .numericInput(placeholder: "2", suffix: "/sem")),
        Question(id: "nutsPerWeek", text: "Fruits a coque par semaine ?", type: .numericInput(placeholder: "3", suffix: "/sem")),
        Question(id: "seedsPerDay", text: "Cuilleres de graines par semaine ?", type: .numericInput(placeholder: "3", suffix: "c.a.s/sem")),
        Question(id: "wholegrainPerWeek", text: "Cereales completes par semaine ?", type: .numericInput(placeholder: "5", suffix: "/sem")),
        Question(
            id: "breadType",
            text: "Quel type de pain ?",
            type: .singleChoice,
            options: [
                .init("white", "Blanc"), .init("whole_grain", "Complet"),
                .init("sourdough", "Levain"), .init("none", "Pas de pain"),
            ]
        ),
        Question(
            id: "fermentedFoods",
            text: "Aliments fermentes ?",
            type: .singleChoice,
            options: [
                .init("never", "Jamais"), .init("rarely", "Rarement"),
                .init("sometimes", "Parfois"), .init("often", "Souvent"),
            ]
        ),
        Question(
            id: "ultraProcessedFrequency",
            text: "Aliments ultra-transformes ?",
            type: .singleChoice,
            options: [
                .init("never", "Jamais"), .init("rarely", "Rarement"),
                .init("sometimes", "Parfois"), .init("often", "Souvent"), .init("daily", "Quotidien"),
            ]
        ),
        Question(
            id: "snacking",
            text: "Tu grignotes ?",
            type: .singleChoice,
            options: [
                .init("jamais", "Jamais"), .init("parfois", "Parfois"),
                .init("souvent", "Souvent"), .init("constant", "Tout le temps"),
            ]
        ),
        Question(
            id: "saltLevel",
            text: "Ton niveau de sel ?",
            type: .singleChoice,
            options: [.init("none", "Aucun"), .init("little", "Peu"), .init("moderate", "Modere"), .init("a_lot", "Beaucoup")]
        ),
        Question(
            id: "iodizedSalt",
            text: "Tu utilises du sel iode ?",
            type: .singleChoice,
            options: [.init("yes", "Oui"), .init("no", "Non"), .init("unknown", "Je ne sais pas")]
        ),
        Question(
            id: "eatLiver",
            text: "Tu manges du foie (abats) ?",
            type: .singleChoice,
            options: [.init("yes", "Oui"), .init("no", "Non")]
        ),
        Question(
            id: "lowCarbDiet",
            text: "Regime pauvre en glucides ?",
            type: .singleChoice,
            options: [.init("yes", "Oui"), .init("no", "Non")]
        ),
        Question(
            id: "supplementsCurrent",
            text: "Complements que tu prends actuellement ?",
            type: .multiChoice,
            options: [
                .init("none", "Aucun"), .init("vitD", "Vitamine D", emoji: "☀️"),
                .init("omega3", "Omega-3", emoji: "🐟"), .init("magnesium", "Magnesium", emoji: "⚡"),
                .init("iron", "Fer", emoji: "🩸"), .init("b12", "Vitamine B12", emoji: "🔴"),
                .init("zinc", "Zinc", emoji: "🛡️"), .init("folate", "Folate", emoji: "🧬"),
                .init("probiotics", "Probiotiques", emoji: "🦠"), .init("multivitamin", "Multivitamine", emoji: "💊"),
            ]
        ),
    ]
}

// MARK: - Section 5: Symptomes
extension QuestionnaireSection {
    static let symptomesQuestions: [Question] = [
        Question(
            id: "symptoms",
            text: "As-tu certains de ces symptomes ?",
            type: .multiChoice,
            options: [
                .init("none", "Aucun"),
                .init("fatigue_chronic", "Fatigue chronique", emoji: "😴"),
                .init("hair_loss", "Perte de cheveux", emoji: "💇"),
                .init("brittle_nails", "Ongles cassants", emoji: "💅"),
                .init("muscle_cramps", "Crampes musculaires", emoji: "🦵"),
                .init("tingling", "Fourmillements", emoji: "⚡"),
                .init("brain_fog", "Brouillard mental", emoji: "🌫️"),
                .init("bleeding_gums", "Saignement des gencives", emoji: "🩸"),
                .init("feeling_cold", "Toujours froid", emoji: "🥶"),
                .init("mouth_ulcers", "Aphtes frequents", emoji: "😣"),
                .init("dry_skin", "Peau seche", emoji: "🏜️"),
            ]
        ),
    ]
}

// MARK: - Section 6: Medical
extension QuestionnaireSection {
    static let medicalQuestions: [Question] = [
        Question(
            id: "medications",
            text: "Prends-tu des medicaments ?",
            type: .multiChoice,
            options: [
                .init("none", "Aucun"),
                .init("ppi", "IPP (anti-acide)", emoji: "💊"),
                .init("metformin", "Metformine", emoji: "💉"),
                .init("oral_contraceptive", "Contraceptif oral", emoji: "💊"),
                .init("diuretics", "Diuretiques", emoji: "💧"),
                .init("statins", "Statines", emoji: "❤️"),
                .init("anticoagulant", "Anticoagulant", emoji: "🩸"),
                .init("thyroid_med", "Thyroide", emoji: "🦋"),
            ]
        ),
        Question(
            id: "digestiveConditions",
            text: "Conditions digestives diagnostiquees ?",
            type: .multiChoice,
            options: [
                .init("none", "Aucune"),
                .init("celiac", "Maladie coeliaque"),
                .init("crohns_uc", "Crohn / RCH"),
                .init("ibs", "Syndrome de l'intestin irritable"),
                .init("acid_reflux", "Reflux gastrique"),
            ]
        ),
        // These questions already have "Non concerne" as an option,
        // so they are shown to all users regardless of gender.
        Question(
            id: "periodFlow",
            text: "Abondance de tes regles ?",
            type: .singleChoice,
            options: [
                .init("light", "Legeres"), .init("normal", "Normales"),
                .init("heavy", "Abondantes"), .init("very_heavy", "Tres abondantes"),
                .init("na", "Non concerne"),
            ]
        ),
        Question(
            id: "pregnancyStatus",
            text: "Situation de grossesse ?",
            type: .singleChoice,
            options: [
                .init("na", "Non concerne"),
                .init("trying_to_conceive", "Projet de grossesse"),
                .init("pregnant", "Enceinte"),
                .init("breastfeeding", "Allaitement"),
            ]
        ),
    ]
}
