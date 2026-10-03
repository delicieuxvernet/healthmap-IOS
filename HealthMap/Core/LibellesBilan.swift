import Foundation

// MARK: - Les mots du nouveau questionnaire (1er octobre 2026)
//
// Les écrans à thème posent les mêmes questions avec d'autres mots : le libellé
// de groupe porte l'unité (« Verres d'eau, par jour »), la réponse devient
// courte (« 3 à 5 »). Ce fichier ne contient QUE ces mots.
//
// ⚠️ Les VALEURS ne sont pas ici. `choix(_:)` part toujours des options de
// `QuestionnaireSection`, dans leur ordre, et ne fait qu'en changer l'emoji ou
// le titre : il est donc impossible d'afficher une réponse que le moteur de
// score ne connaît pas, ou d'en oublier une. `LibellesBilanTests` vérifie que
// chaque surcharge désigne une option qui existe.

/// Une réponse possible, telle qu'elle s'affiche.
struct ChoixBilan: Identifiable, Equatable {
    /// La valeur enregistrée : celle de `QuestionOption.id`.
    let id: String
    /// Vide quand la réponse se dit sans image.
    let emoji: String
    let titre: String
}

enum LibellesBilan {

    /// Les réponses d'une question, prêtes à afficher. « Aucun » passe en
    /// dernier dans les listes à cocher : on lit ce qui existe avant de dire
    /// qu'on n'a rien.
    static func choix(_ question: String) -> [ChoixBilan] {
        guard let definition = QuestionnaireSection.question(id: question),
              let options = definition.options else { return [] }
        let surcharge = surcharges[question] ?? [:]
        var sortie = options.map { option -> ChoixBilan in
            if let (emoji, titre) = surcharge[option.id] {
                return ChoixBilan(id: option.id, emoji: emoji, titre: titre)
            }
            return ChoixBilan(id: option.id, emoji: option.emoji ?? "", titre: option.label)
        }
        if case .multiChoice = definition.type, let index = sortie.firstIndex(where: { $0.id == "none" }) {
            sortie.append(sortie.remove(at: index))
        }
        return sortie
    }

    /// Le titre d'une réponse, ou la valeur brute si elle est inconnue.
    static func titre(_ question: String, _ valeur: String) -> String {
        choix(question).first { $0.id == valeur }?.titre ?? valeur
    }

    /// question → valeur → (emoji, titre). Seulement ce qui diffère de
    /// `QuestionnaireSection`.
    static let surcharges: [String: [String: (String, String)]] = [
        "goals": [
            "equilibre": ("🥗", "Manger équilibré"),
        ],
        "symptoms": [
            "none": ("✨", "Rien de tout ça"),
            "fatigue_chronic": ("😴", "Fatigue"),
            "hair_loss": ("💇", "Chute de cheveux"),
            "muscle_cramps": ("🦵", "Crampes"),
            "bleeding_gums": ("🩸", "Gencives qui saignent"),
            "mouth_ulcers": ("😣", "Aphtes"),
            "bloating_frequent": ("🎈", "Ballonnements"),
            "low_mood": ("😔", "Moral en baisse"),
            "low_motivation": ("🪫", "Manque d'entrain"),
            "skin_breakouts": ("😬", "Acné"),
            "digestive_bleeding": ("🩸", "Sang ou selles noires"),
        ],
        "strengthTraining": [
            "light": ("🚶", "1-2 fois"),
            "moderate": ("🏃", "3-4 fois"),
            "regular": ("🏋️", "4-5 fois"),
            "intense": ("🔥", "6 et +"),
        ],
        "caffeineIntake": [
            "none": ("🚫", "Aucun"),
            "light": ("☕", "1 à 2"),
            "moderate": ("☕", "3 à 4"),
            "heavy": ("☕", "5 et +"),
        ],
        "caffeineTiming": [
            "with_meals": ("", "Pendant les repas"),
            "between": ("", "Entre les repas"),
        ],
        "waterIntake": [
            "0.75": ("💧", "Moins de 3"),
            "1.25": ("💧", "3 à 5"),
            "1.75": ("💧", "6 à 7"),
            "2.25": ("💧", "8 à 9"),
            "3": ("💧", "10 et +"),
        ],
        "alcohol": [
            "none": ("🚫", "Jamais"),
            "rarely": ("🥂", "Rarement"),
            "moderate": ("🍷", "Modéré"),
            "regular": ("🍷", "Régulier"),
            "heavy": ("🍺", "Important"),
        ],
        "screenBeforeBed": [
            "none": ("📵", "Aucun"),
            "short": ("📱", "Moins de 30 min"),
            "moderate": ("📱", "30 à 60 min"),
            "long": ("📱", "1 à 2 h"),
            "very_long": ("📱", "Plus de 2 h"),
        ],
        "sleepHours": [
            "4": ("😵", "Moins de 5 h"),
            "5.5": ("🥱", "5 à 6 h"),
            "6.5": ("😐", "6 à 7 h"),
            "7.5": ("🙂", "7 à 8 h"),
            "8.5": ("😴", "8 à 9 h"),
            "10": ("🛌", "Plus de 9 h"),
        ],
        "periodFlow": [
            "light": ("🩸", "Légères"),
            "normal": ("🩸", "Normales"),
            "heavy": ("🩸", "Abondantes"),
            "very_heavy": ("🩸", "Très abondantes"),
            "na": ("➖", "Non concernée"),
        ],
        "pregnancyStatus": [
            "na": ("➖", "Non concernée"),
            "trying_to_conceive": ("💭", "Projet de grossesse"),
            "pregnant": ("🤰", "Enceinte"),
            "breastfeeding": ("🤱", "Allaitement"),
        ],
        "allergies": [
            "none": ("✨", "Je mange de tout"),
            "nuts": ("🌰", "Fruits à coque"),
            "peanut": ("🥜", "Arachide"),
            "fish_shellfish": ("🐟", "Poisson, crustacés"),
            "milk": ("🥛", "Lait de vache"),
            "egg": ("🥚", "Œuf"),
            "soy": ("🌱", "Soja"),
            "wheat_gluten": ("🌾", "Blé ou gluten"),
            "sesame": ("⚪", "Sésame"),
            "sulfites": ("🍷", "Sulfites"),
        ],
        "mealsPerDay": [
            "5+": ("", "5 et +"),
        ],
        "homeCookedPct": [
            "almost_all": ("", "Presque tout"),
            "mostly": ("", "La plupart"),
            "half": ("", "La moitié"),
            "mostly_out": ("", "Peu"),
            "rarely": ("", "Presque jamais"),
        ],
        "cookingMethod": [
            "sauteed": ("", "Poêle"),
            "boiled": ("", "À l'eau"),
        ],
        "breadType": [
            "none": ("", "Aucun"),
        ],
        "ultraProcessedFrequency": [
            "daily": ("", "Tous les jours"),
        ],
    ]

    // MARK: Le poids, ces derniers mois

    /// La question `weightTrend` a cinq réponses ; l'écran les demande en deux
    /// temps (dans quel sens, puis « c'était voulu ? »). Les valeurs écrites
    /// restent les cinq d'origine.
    enum SensDuPoids: String, CaseIterable, Identifiable {
        case baisse
        case stable
        case hausse

        var id: String { rawValue }

        var emoji: String {
            switch self {
            case .baisse: return "↘️"
            case .stable: return "➡️"
            case .hausse: return "↗️"
            }
        }

        var titre: String {
            switch self {
            case .baisse: return "En baisse"
            case .stable: return "Stable"
            case .hausse: return "En hausse"
            }
        }
    }

    /// La valeur de `weightTrend` pour ce sens. `nil` tant qu'il manque la
    /// réponse à « c'était voulu ? ».
    static func tendance(_ sens: SensDuPoids, voulu: Bool?) -> String? {
        switch sens {
        case .stable:
            return "stable"
        case .baisse:
            guard let voulu else { return nil }
            return voulu ? "losing_intentionally" : "losing_unintentionally"
        case .hausse:
            guard let voulu else { return nil }
            return voulu ? "gaining_intentionally" : "gaining_unintentionally"
        }
    }

    /// Le sens que dit une valeur de `weightTrend` déjà enregistrée.
    static func sens(de tendance: String) -> SensDuPoids? {
        switch tendance {
        case "stable": return .stable
        case "losing_intentionally", "losing_unintentionally": return .baisse
        case "gaining_intentionally", "gaining_unintentionally": return .hausse
        default: return nil
        }
    }

    /// « C'était voulu ? » pour une valeur déjà enregistrée.
    static func voulu(de tendance: String) -> Bool? {
        switch tendance {
        case "losing_intentionally", "gaining_intentionally": return true
        case "losing_unintentionally", "gaining_unintentionally": return false
        default: return nil
        }
    }

    // MARK: La peau

    /// La couleur de chaque nuance du nuancier, en hexadécimal. Les valeurs
    /// sont celles de la question `skinType`.
    static let nuancesDePeau: [String: String] = [
        "very_fair": "F6DDC8",
        "fair": "EBC3A0",
        "medium": "C99873",
        "olive": "9A6A45",
        "dark": "5C3B25",
    ]
}
