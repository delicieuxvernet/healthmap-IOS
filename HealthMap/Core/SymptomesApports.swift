import Foundation

// MARK: - Table symptôme → apport (validée par Arthur, 20 septembre 2026)
//
// PRINCIPE, à ne jamais inverser : c'est le SCORE, calculé sur l'alimentation
// déclarée, qui décide si un apport est à renforcer. Le symptôme ne décide de
// rien — il explique pourquoi ça peut compter pour cette personne, et il
// arrive APRÈS.
//
// On n'écrit jamais « tu perds tes cheveux, donc ton fer est bas ».
// On écrit « ton apport en fer est bas, et la perte de cheveux fait partie de
// ce que ça peut refléter ». C'est ce qui nous garde dans l'explication et
// hors de l'interprétation — et c'est ce qui borne notre responsabilité.
//
// Quatre symptômes sur dix-huit ne déclenchent rien, et c'est voulu : une
// table qui trouve toujours quelque chose à dire n'est pas une table.

/// Force du lien entre un symptôme déclaré et un apport.
enum NiveauDeLien {
    /// Lien spécifique et bien établi : on peut le nommer seul.
    case fort
    /// Établi mais peu spécifique : nommé quand le score est bas — ce qui est
    /// toujours le cas ici, puisqu'on ne parle que d'apports à renforcer.
    case modere
    /// Croyance répandue, preuve mince : JAMAIS seul. Il faut qu'un autre
    /// symptôme déclaré pointe déjà le même apport.
    case faible
}

/// Un lien de la table. `formulation` est un groupe nominal qui s'insère dans
/// « Tu as signalé … » — donc sans participe, pour éviter tout accord.
struct LienSymptome {
    let symptome: String
    let nutriment: NutrientID
    let niveau: NiveauDeLien
    let formulation: String
}

enum SymptomesApports {

    /// Nombre de symptômes cités au maximum : au-delà, la phrase devient une
    /// liste et le « pourquoi » du bilan est déjà long.
    static let maxSymptomesCites = 2

    /// La table, dans l'ordre de force. Les symptômes absents de cette liste
    /// ne déclenchent rien, volontairement :
    ///
    /// - `low_mood`, `low_motivation` : aucune allégation n'est autorisée sur
    ///   l'humeur, et les liens nutritionnels sont trop minces pour être écrits.
    /// - `digestive_bleeding` : le seul symptôme qui COUPE la chaîne au lieu de
    ///   l'alimenter. Renvoi médical immédiat (`RedFlagDetector`), aucune
    ///   recommandation de complément ne doit s'y accrocher.
    /// - `bloating_frequent`, `slow_digestion`, `acid_reflux_feeling` : ils
    ///   orientent une FORME de prise, pas un besoin. Depuis la doctrine du
    ///   20 septembre, la forme ne varie plus selon le profil — on retient
    ///   toujours la mieux tolérée — donc ils ne disent plus rien ici.
    /// - `none` : le bilan explique alors l'apport par l'alimentation seule.
    static let liens: [LienSymptome] = [
        // — Liens forts : spécifiques, bien établis.
        LienSymptome(symptome: "tingling", nutriment: .vitB12, niveau: .fort,
                     formulation: "des fourmillements"),
        LienSymptome(symptome: "bleeding_gums", nutriment: .vitC, niveau: .fort,
                     formulation: "des saignements des gencives"),

        // — Liens modérés : établis, peu spécifiques.
        LienSymptome(symptome: "mouth_ulcers", nutriment: .vitB12, niveau: .modere,
                     formulation: "des aphtes fréquents"),
        LienSymptome(symptome: "mouth_ulcers", nutriment: .iron, niveau: .modere,
                     formulation: "des aphtes fréquents"),
        LienSymptome(symptome: "mouth_ulcers", nutriment: .zinc, niveau: .modere,
                     formulation: "des aphtes fréquents"),
        LienSymptome(symptome: "hair_loss", nutriment: .iron, niveau: .modere,
                     formulation: "une perte de cheveux"),
        LienSymptome(symptome: "fatigue_chronic", nutriment: .iron, niveau: .modere,
                     formulation: "une fatigue qui dure"),
        LienSymptome(symptome: "fatigue_chronic", nutriment: .vitB12, niveau: .modere,
                     formulation: "une fatigue qui dure"),
        LienSymptome(symptome: "feeling_cold", nutriment: .iron, niveau: .modere,
                     formulation: "une frilosité"),
        // L'iode n'a pas besoin de condition supplémentaire : son score tient
        // déjà compte du sel iodé et du poisson. On ne parle jamais de thyroïde.
        LienSymptome(symptome: "feeling_cold", nutriment: .iodine, niveau: .modere,
                     formulation: "une frilosité"),
        LienSymptome(symptome: "skin_breakouts", nutriment: .zinc, niveau: .modere,
                     formulation: "des poussées d'acné"),
        LienSymptome(symptome: "brain_fog", nutriment: .vitB12, niveau: .modere,
                     formulation: "un brouillard mental"),

        // — Liens faibles : croyance répandue, preuve mince. Jamais seuls.
        LienSymptome(symptome: "muscle_cramps", nutriment: .magnesium, niveau: .faible,
                     formulation: "des crampes"),
        LienSymptome(symptome: "brittle_nails", nutriment: .iron, niveau: .faible,
                     formulation: "des ongles cassants"),
        LienSymptome(symptome: "brittle_nails", nutriment: .zinc, niveau: .faible,
                     formulation: "des ongles cassants"),
        LienSymptome(symptome: "dry_skin", nutriment: .omega3, niveau: .faible,
                     formulation: "une peau sèche"),
        LienSymptome(symptome: "dry_skin", nutriment: .zinc, niveau: .faible,
                     formulation: "une peau sèche"),
        LienSymptome(symptome: "brain_fog", nutriment: .iron, niveau: .faible,
                     formulation: "un brouillard mental"),
        LienSymptome(symptome: "hair_loss", nutriment: .zinc, niveau: .faible,
                     formulation: "une perte de cheveux"),
    ]

    /// Ce que les symptômes déclarés permettent de dire sur un apport bas —
    /// ou `nil` quand rien de solide ne se dit.
    ///
    /// L'appelant a déjà établi que l'apport est à renforcer : cette phrase ne
    /// justifie pas la recommandation, elle l'éclaire.
    static func explication(pour nutriment: NutrientID, symptomes: [String]) -> String? {
        let declares = Set(symptomes)
        let retenus = liens.filter { $0.nutriment == nutriment && declares.contains($0.symptome) }
        guard !retenus.isEmpty else { return nil }

        let solides = retenus.filter { $0.niveau != .faible }
        // « Jamais seul » : un lien faible ne parle que si un lien solide parle
        // déjà pour le même apport.
        guard !solides.isEmpty else { return nil }

        var formulations: [String] = []
        for lien in solides + retenus.filter({ $0.niveau == .faible }) {
            guard !formulations.contains(lien.formulation) else { continue }
            formulations.append(lien.formulation)
            if formulations.count == maxSymptomesCites { break }
        }

        let enumeration: String
        if formulations.count > 1 {
            enumeration = formulations.dropLast().joined(separator: ", ") + " et " + formulations[formulations.count - 1]
        } else {
            enumeration = formulations[0]
        }

        let label = SupplementEngine.nutrientLabel(for: nutriment)
        return "Tu as signalé \(enumeration) — cela fait partie de ce qu'un apport bas en \(label) peut expliquer."
    }
}
