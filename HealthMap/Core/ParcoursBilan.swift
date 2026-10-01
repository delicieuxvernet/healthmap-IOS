import Foundation

// MARK: - Le parcours du bilan (refonte du questionnaire, 1er octobre 2026)
//
// Le questionnaire posait une question par écran, vingt-cinq écrans d'affilée,
// avec une barre qui repartait de zéro à chaque section : on ne savait ni où on
// en était, ni à quoi servait la question (retour d'Arthur). Il devient un
// parcours en QUATRE ÉTAPES, faites d'écrans à thème qui regroupent les
// questions qui vont ensemble.
//
// ⚠️ Ce fichier ne change AUCUNE donnée. Les questions, leurs identifiants et
// leurs valeurs restent ceux de `QuestionnaireSection` : ce que reçoivent le
// moteur de score et `generate-analysis` est identique. Il ne décide que de
// l'ordre, du regroupement, et de ce qu'il faut avoir répondu pour avancer.
// `ParcoursBilanTests` vérifie qu'aucune question n'est perdue en route.
//
// Logique pure, sans interface : l'état vit dans `QuestionnaireViewModel`.

/// Les quatre étapes annoncées dès l'accueil.
enum EtapeBilan: Int, CaseIterable, Identifiable {
    case toi
    case quotidien
    case forme
    case assiette

    var id: Int { rawValue }

    /// 1 à 4, tel qu'on le dit à la personne.
    var numero: Int { rawValue + 1 }

    var titre: String {
        switch self {
        case .toi: return "Toi"
        case .quotidien: return "Ton quotidien"
        case .forme: return "Ta forme"
        case .assiette: return "Ton assiette"
        }
    }

    var emoji: String {
        switch self {
        case .toi: return "👋"
        case .quotidien: return "☀️"
        case .forme: return "🌙"
        case .assiette: return "🍽️"
        }
    }
}

/// Un écran du parcours. L'ordre des cas EST l'ordre du parcours.
enum EcranBilan: String, CaseIterable, Codable, Identifiable {
    case accueil

    // Étape 1 · Toi
    case motif
    case prenom
    case reperes
    case finToi

    // Étape 2 · Ton quotidien
    case soleil
    case bouger
    case boire
    case alcoolTabac
    case finQuotidien

    // Étape 3 · Ta forme
    case ressenti
    case nuits
    case ventre
    case cycle
    case finForme

    // Étape 4 · Ton assiette
    case regime
    case provisoire
    case petitDej
    case midi
    case gouter
    case soir
    case jamais

    // Pour affiner (seulement si la personne le demande, à la fin)
    case aTable
    case placard
    case ecarts
    case complements
    case traitements
    case digestion
    case antecedents

    case fin

    var id: String { rawValue }

    /// L'étape à laquelle l'écran appartient. `nil` pour l'accueil, la fin et
    /// les écrans d'affinage, qui ne comptent dans aucune des quatre.
    var etape: EtapeBilan? {
        switch self {
        case .motif, .prenom, .reperes, .finToi: return .toi
        case .soleil, .bouger, .boire, .alcoolTabac, .finQuotidien: return .quotidien
        case .ressenti, .nuits, .ventre, .cycle, .finForme: return .forme
        case .regime, .provisoire, .petitDej, .midi, .gouter, .soir, .jamais: return .assiette
        case .accueil, .aTable, .placard, .ecarts, .complements, .traitements, .digestion, .antecedents, .fin:
            return nil
        }
    }

    /// Écran de récapitulation qui clôt une étape.
    var estFinDEtape: Bool {
        self == .finToi || self == .finQuotidien || self == .finForme
    }

    /// Écran proposé seulement après « Affiner d'abord ».
    var estAffinage: Bool {
        switch self {
        case .aTable, .placard, .ecarts, .complements, .traitements, .digestion, .antecedents: return true
        default: return false
        }
    }

    /// Le repas que l'écran présente, s'il en présente un.
    var repas: RepasBilan? {
        switch self {
        case .petitDej: return .petitDej
        case .midi: return .midi
        case .gouter: return .gouter
        case .soir: return .soir
        default: return nil
        }
    }

    /// Vrai une fois les repas passés : l'assiette a parlé, on ne peut plus
    /// écrire « ton assiette dira si elle compense ».
    var estApresLesRepas: Bool {
        self == .jamais || self == .fin || estAffinage
    }

    /// Les questions de `QuestionnaireSection` auxquelles l'écran répond.
    var questions: [String] {
        switch self {
        case .motif: return ["goals", "symptoms"]
        case .prenom: return ["firstName"]
        case .reperes: return ["gender", "age", "height", "weight"]
        case .soleil: return ["indoorWork", "sunExposure", "skinType"]
        case .bouger: return ["strengthTraining", "weightTrend"]
        case .boire: return ["caffeineIntake", "caffeineTiming", "waterIntake"]
        case .alcoolTabac: return ["alcohol", "smoking"]
        case .ressenti: return ["stressLevel", "wakeFeeling"]
        case .nuits: return ["screenBeforeBed", "sleepHours"]
        case .ventre: return ["bloating", "antibiotics"]
        case .cycle: return ["periodFlow", "pregnancyStatus"]
        case .regime: return ["dietType"]
        case .petitDej, .midi, .gouter, .soir: return ["groceries"]
        case .jamais: return ["allergies"]
        case .aTable: return ["mealsPerDay", "homeCookedPct", "cookingMethod"]
        case .placard: return ["breadType", "saltLevel", "iodizedSalt", "eatLiver", "lowCarbDiet"]
        case .ecarts: return ["fermentedFoods", "ultraProcessedFrequency", "snacking"]
        case .complements: return ["supplementsCurrent"]
        case .traitements: return ["medications"]
        case .digestion: return ["digestiveConditions", "surgicalHistory"]
        case .antecedents: return ["medicalHistory"]
        case .accueil, .finToi, .finQuotidien, .finForme, .provisoire, .fin: return []
        }
    }

    /// Temps que l'écran prend, en secondes. Une ESTIMATION, qui ne sert qu'à
    /// dire « encore ~2 min ». Elle est calée pour que le tronc tienne dans la
    /// durée médiane mesurée sur l'ancien questionnaire (3 min 24, le
    /// 1er octobre 2026) et dans la promesse des portes de l'app (« bilan
    /// 3 min ») ; à recaler sur le nouveau parcours dès qu'il est mesuré.
    var duree: Int {
        switch self {
        case .accueil, .fin: return 0
        case .placard: return 18
        case .motif, .reperes, .petitDej, .midi, .gouter, .soir, .aTable, .digestion: return 15
        case .soleil: return 14
        case .bouger, .boire, .ecarts, .complements: return 12
        case .ressenti, .nuits, .cycle, .traitements, .antecedents: return 10
        case .prenom, .alcoolTabac, .regime, .jamais: return 8
        case .ventre, .provisoire: return 6
        case .finToi, .finQuotidien, .finForme: return 4
        }
    }
}

/// Ce dont le parcours a besoin pour se décider.
struct ContexteBilan {
    /// Les réponses données jusqu'ici.
    var profil: UserProfile
    /// Les questions auxquelles la personne a répondu d'un geste. Un champ qui
    /// porte une valeur par défaut (sexe, régime, règles) ne compte que s'il
    /// est ici.
    var renseignees: Set<String>
    /// Le compte connaît déjà le prénom : l'écran ne se montre pas.
    var prenomConnu: Bool
    /// La personne a demandé à affiner son bilan.
    var approfondi: Bool
}

/// Ce que le Journal montre quand un bilan est en cours.
struct RepriseBilan: Equatable {
    /// « Étape 2 sur 4 : Ton quotidien ».
    let titre: String
    /// Remplissage des quatre segments, de 0 à 1.
    let avancements: [Double]
    /// « Encore ~3 min. », ou vide quand il ne reste qu'à lire le bilan.
    let reste: String
}

enum ParcoursBilan {

    // MARK: Les écrans à montrer

    /// Vrai si l'écran a sa place dans le parcours de cette personne.
    static func visible(_ ecran: EcranBilan, _ c: ContexteBilan) -> Bool {
        if ecran == .prenom { return !c.prenomConnu }
        if ecran == .cycle { return c.profil.gender == .femme }
        if ecran.estAffinage { return c.approfondi }
        return true
    }

    /// Les écrans du parcours, dans l'ordre.
    static func ecrans(_ c: ContexteBilan) -> [EcranBilan] {
        EcranBilan.allCases.filter { visible($0, c) }
    }

    private static func rang(_ ecran: EcranBilan) -> Int {
        EcranBilan.allCases.firstIndex(of: ecran) ?? 0
    }

    /// L'écran qui suit, ou `nil` au bout du parcours. Tient même si l'écran
    /// courant vient de sortir du parcours (le sexe a changé, par exemple).
    static func suivant(apres ecran: EcranBilan, _ c: ContexteBilan) -> EcranBilan? {
        let ici = rang(ecran)
        return ecrans(c).first { rang($0) > ici }
    }

    /// L'écran qui précède, ou `nil` sur l'accueil.
    static func precedent(avant ecran: EcranBilan, _ c: ContexteBilan) -> EcranBilan? {
        let ici = rang(ecran)
        return ecrans(c).last { rang($0) < ici }
    }

    // MARK: Ce qu'il faut avoir répondu pour avancer

    /// Le moment du café n'est demandé qu'à partir de trois par jour (c'est le
    /// `showIf` de la question `caffeineTiming`).
    static func cafeDemandeLeMoment(_ p: UserProfile) -> Bool {
        ["moderate", "heavy"].contains(p.caffeineIntake)
    }

    /// Vrai quand tout ce que l'écran demande a reçu une réponse.
    ///
    /// Les bascules (intérieur, tabac, ballonnements, antibiotiques, abats,
    /// peu de glucides) ne bloquent jamais : laissées éteintes, elles valent
    /// « non », écrit au moment de continuer. Les listes à cocher non plus :
    /// ne rien cocher, c'est répondre « rien ».
    static func estComplet(_ ecran: EcranBilan, _ c: ContexteBilan) -> Bool {
        let p = c.profil
        func dit(_ id: String) -> Bool { c.renseignees.contains(id) }

        switch ecran {
        case .prenom:
            return !Prenom.affichable(p.firstName).isEmpty
        case .reperes:
            return dit("gender") && !p.age.isEmpty && !p.height.isEmpty && !p.weight.isEmpty
        case .soleil:
            return !p.sunExposure.isEmpty && !p.skinType.isEmpty
        case .bouger:
            return !p.strengthTraining.isEmpty && !p.weightTrend.isEmpty
        case .boire:
            guard !p.caffeineIntake.isEmpty, !p.waterIntake.isEmpty else { return false }
            return !cafeDemandeLeMoment(p) || !p.caffeineTiming.isEmpty
        case .alcoolTabac:
            return !p.alcohol.isEmpty
        case .ressenti:
            return !p.stressLevel.isEmpty && !p.wakeFeeling.isEmpty
        case .nuits:
            return !p.screenBeforeBed.isEmpty && !p.sleepHours.isEmpty
        case .cycle:
            return dit("periodFlow") && dit("pregnancyStatus")
        case .regime:
            return dit("dietType")
        case .aTable:
            return !p.mealsPerDay.isEmpty && !p.homeCookedPct.isEmpty && !p.cookingMethod.isEmpty
        case .placard:
            return !p.breadType.isEmpty && !p.saltLevel.isEmpty && !p.iodizedSalt.isEmpty
        case .ecarts:
            return !p.fermentedFoods.isEmpty && !p.ultraProcessedFrequency.isEmpty && !p.snacking.isEmpty
        default:
            return true
        }
    }

    // MARK: Où reprendre

    /// L'écran sur lequel rouvrir un bilan interrompu : là où la personne
    /// s'est arrêtée, sans jamais sauter un écran qu'elle n'a pas terminé.
    ///
    /// Remplace la décision du 6 juillet 2026 (« reprise au début ») : avec
    /// une question par écran, repartir de zéro coûtait vingt-cinq appuis ;
    /// c'est devenu le premier frein à la reprise (maquette validée le
    /// 1er octobre 2026).
    static func ecranDeReprise(enregistre: EcranBilan?, _ c: ContexteBilan) -> EcranBilan {
        let liste = ecrans(c)
        let premierIncomplet = liste.first { !estComplet($0, c) }

        guard let enregistre, liste.contains(enregistre) else {
            // Brouillon d'avant la refonte, ou écran sorti du parcours.
            if rienDeRepondu(c) { return .accueil }
            if let premierIncomplet { return premierIncomplet }
            return c.profil.groceries.isEmpty ? .petitDej : .fin
        }
        if let premierIncomplet, rang(premierIncomplet) < rang(enregistre) {
            return premierIncomplet
        }
        return enregistre
    }

    /// Vrai tant que la personne n'a encore rien dit.
    static func rienDeRepondu(_ c: ContexteBilan) -> Bool {
        c.renseignees.isEmpty
            && c.profil.symptoms.isEmpty
            && c.profil.goals.isEmpty
            && c.profil.groceries.isEmpty
    }

    // MARK: Où on en est

    /// −1 sur l'accueil, 0 à 3 pendant les étapes, 4 ensuite.
    static func rangEtape(_ ecran: EcranBilan) -> Int {
        if ecran == .accueil { return -1 }
        return ecran.etape?.rawValue ?? EtapeBilan.allCases.count
    }

    /// Remplissage du segment d'une étape, de 0 à 1. La barre ne repart
    /// jamais de zéro : une étape finie reste pleine.
    static func avancement(_ etape: EtapeBilan, ecran: EcranBilan, _ c: ContexteBilan) -> Double {
        let courante = rangEtape(ecran)
        if courante > etape.rawValue { return 1 }
        if courante < etape.rawValue { return 0 }
        if ecran.estFinDEtape { return 1 }
        let deLEtape = ecrans(c).filter { $0.etape == etape }
        guard !deLEtape.isEmpty, let position = deLEtape.firstIndex(of: ecran) else { return 0 }
        return max(0.08, Double(position) / Double(deLEtape.count))
    }

    /// Les quatre segments d'un coup.
    static func avancements(ecran: EcranBilan, _ c: ContexteBilan) -> [Double] {
        EtapeBilan.allCases.map { avancement($0, ecran: ecran, c) }
    }

    // MARK: Combien de temps encore

    /// Secondes restantes à partir de cet écran, lui compris.
    static func secondesRestantes(depuis ecran: EcranBilan, _ c: ContexteBilan) -> Int {
        let ici = rang(ecran)
        return ecrans(c).filter { rang($0) >= ici }.reduce(0) { $0 + $1.duree }
    }

    /// « encore ~2 min 30 », à la demi-minute. Vide quand il ne reste rien.
    static func texteReste(secondes: Int) -> String {
        guard secondes > 0 else { return "" }
        if secondes < 50 { return "encore moins d'une minute" }
        let demiMinutes = Int((Double(secondes) / 30).rounded())
        let minutes = demiMinutes / 2
        return demiMinutes % 2 == 1 ? "encore ~\(minutes) min 30" : "encore ~\(minutes) min"
    }

    /// Le même temps restant, pour VoiceOver : « ~2 min 30 » se lit mal.
    static func texteResteVocal(secondes: Int) -> String {
        guard secondes > 0 else { return "" }
        if secondes < 50 { return "encore moins d'une minute" }
        let demiMinutes = Int((Double(secondes) / 30).rounded())
        let minutes = demiMinutes / 2
        let mot = minutes > 1 ? "minutes" : "minute"
        return demiMinutes % 2 == 1
            ? "encore environ \(minutes) \(mot) 30"
            : "encore environ \(minutes) \(mot)"
    }

    /// Durée du parcours entier, arrondie à la minute : « Environ 3 minutes ».
    static func minutesAnnoncees(_ c: ContexteBilan) -> Int {
        let total = ecrans(c).filter { !$0.estAffinage }.reduce(0) { $0 + $1.duree }
        return max(1, Int((Double(total) / 60).rounded()))
    }

    /// Durée d'une étape telle qu'on l'annonce sur l'accueil : « 50 s », « 2 min ».
    static func dureeAnnoncee(_ etape: EtapeBilan, _ c: ContexteBilan) -> String {
        let secondes = ecrans(c).filter { $0.etape == etape }.reduce(0) { $0 + $1.duree }
        if secondes < 60 {
            let arrondi = max(5, Int((Double(secondes) / 5).rounded()) * 5)
            return "\(arrondi) s"
        }
        let demiMinutes = Int((Double(secondes) / 30).rounded())
        let minutes = demiMinutes / 2
        return demiMinutes % 2 == 1 ? "\(minutes) min 30" : "\(minutes) min"
    }

    // MARK: La carte du Journal

    /// Ce que le Journal affiche pendant qu'un bilan attend. `nil` tant que
    /// rien n'a été commencé : la porte habituelle suffit.
    static func reprise(ecran: EcranBilan, _ c: ContexteBilan) -> RepriseBilan? {
        if ecran == .accueil && rienDeRepondu(c) { return nil }

        let titre: String
        if let etape = ecran.etape {
            titre = "Étape \(etape.numero) sur \(EtapeBilan.allCases.count) : \(etape.titre)"
        } else if ecran == .accueil {
            titre = "Prêt à reprendre"
        } else if ecran.estAffinage {
            titre = "Tu étais en train de l'affiner"
        } else {
            titre = "Il ne reste qu'à le lire"
        }

        let reste = texteReste(secondes: secondesRestantes(depuis: ecran, c))
        return RepriseBilan(
            titre: titre,
            avancements: avancements(ecran: ecran, c),
            reste: reste.isEmpty ? "" : majusculeInitiale(reste) + "."
        )
    }

    private static func majusculeInitiale(_ texte: String) -> String {
        guard let premiere = texte.first else { return texte }
        return premiere.uppercased() + texte.dropFirst()
    }
}
