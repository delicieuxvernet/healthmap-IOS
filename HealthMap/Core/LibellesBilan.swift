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
            "equilibre": ("🥗", String(localized: "Manger équilibré")),
        ],
        "symptoms": [
            "none": ("✨", String(localized: "Rien de tout ça")),
            "fatigue_chronic": ("😴", String(localized: "Fatigue")),
            "hair_loss": ("💇", String(localized: "Chute de cheveux")),
            "muscle_cramps": ("🦵", String(localized: "Crampes")),
            "bleeding_gums": ("🩸", String(localized: "Gencives qui saignent")),
            "mouth_ulcers": ("😣", String(localized: "Aphtes")),
            "bloating_frequent": ("🎈", String(localized: "Ballonnements")),
            "low_mood": ("😔", String(localized: "Moral en baisse")),
            "low_motivation": ("🪫", String(localized: "Manque d'entrain")),
            "skin_breakouts": ("😬", String(localized: "Acné")),
            "digestive_bleeding": ("🩸", String(localized: "Sang ou selles noires")),
        ],
        "strengthTraining": [
            "light": ("🚶", String(localized: "1-2 fois")),
            "moderate": ("🏃", String(localized: "3-4 fois")),
            "regular": ("🏋️", String(localized: "4-5 fois")),
            "intense": ("🔥", String(localized: "6 et +")),
        ],
        "caffeineIntake": [
            "none": ("🚫", String(localized: "Aucun")),
            "light": ("☕", String(localized: "1 à 2")),
            "moderate": ("☕", String(localized: "3 à 4")),
            "heavy": ("☕", String(localized: "5 et +")),
        ],
        "caffeineTiming": [
            "with_meals": ("", String(localized: "Pendant les repas")),
            "between": ("", String(localized: "Entre les repas")),
        ],
        "waterIntake": [
            "0.75": ("💧", String(localized: "Moins de 3")),
            "1.25": ("💧", String(localized: "3 à 5")),
            "1.75": ("💧", String(localized: "6 à 7")),
            "2.25": ("💧", String(localized: "8 à 9")),
            "3": ("💧", String(localized: "10 et +")),
        ],
        "alcohol": [
            "none": ("🚫", String(localized: "Jamais")),
            "rarely": ("🥂", String(localized: "Rarement")),
            "moderate": ("🍷", String(localized: "Modéré")),
            "regular": ("🍷", String(localized: "Régulier")),
            "heavy": ("🍺", String(localized: "Important")),
        ],
        "screenBeforeBed": [
            "none": ("📵", String(localized: "Aucun")),
            "short": ("📱", String(localized: "Moins de 30 min")),
            "moderate": ("📱", String(localized: "30 à 60 min")),
            "long": ("📱", String(localized: "1 à 2 h")),
            "very_long": ("📱", String(localized: "Plus de 2 h")),
        ],
        "sleepHours": [
            "4": ("😵", String(localized: "Moins de 5 h")),
            "5.5": ("🥱", String(localized: "5 à 6 h")),
            "6.5": ("😐", String(localized: "6 à 7 h")),
            "7.5": ("🙂", String(localized: "7 à 8 h")),
            "8.5": ("😴", String(localized: "8 à 9 h")),
            "10": ("🛌", String(localized: "Plus de 9 h")),
        ],
        "periodFlow": [
            "light": ("🩸", String(localized: "Légères")),
            "normal": ("🩸", String(localized: "Normales")),
            "heavy": ("🩸", String(localized: "Abondantes")),
            "very_heavy": ("🩸", String(localized: "Très abondantes")),
            "na": ("➖", String(localized: "Non concernée")),
        ],
        "pregnancyStatus": [
            "na": ("➖", String(localized: "Non concernée")),
            "trying_to_conceive": ("💭", String(localized: "Projet de grossesse")),
            "pregnant": ("🤰", String(localized: "Enceinte")),
            "breastfeeding": ("🤱", String(localized: "Allaitement")),
        ],
        "allergies": [
            "none": ("✨", String(localized: "Je mange de tout")),
            "nuts": ("🌰", String(localized: "Fruits à coque")),
            "peanut": ("🥜", String(localized: "Arachide")),
            "fish_shellfish": ("🐟", String(localized: "Poisson, crustacés")),
            "milk": ("🥛", String(localized: "Lait de vache")),
            "egg": ("🥚", String(localized: "Œuf")),
            "soy": ("🌱", String(localized: "Soja")),
            "wheat_gluten": ("🌾", String(localized: "Blé ou gluten")),
            "sesame": ("⚪", String(localized: "Sésame")),
            "sulfites": ("🍷", String(localized: "Sulfites")),
        ],
        "mealsPerDay": [
            "5+": ("", String(localized: "5 et +")),
        ],
        "homeCookedPct": [
            "almost_all": ("", String(localized: "Presque tout")),
            "mostly": ("", String(localized: "La plupart")),
            "half": ("", String(localized: "La moitié")),
            "mostly_out": ("", String(localized: "Peu")),
            "rarely": ("", String(localized: "Presque jamais")),
        ],
        "cookingMethod": [
            "sauteed": ("", String(localized: "Poêle")),
            "boiled": ("", String(localized: "À l'eau")),
        ],
        "breadType": [
            "none": ("", String(localized: "Aucun")),
        ],
        "ultraProcessedFrequency": [
            "daily": ("", String(localized: "Tous les jours")),
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
            case .baisse: return String(localized: "En baisse")
            case .stable: return String(localized: "Stable")
            case .hausse: return String(localized: "En hausse")
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
