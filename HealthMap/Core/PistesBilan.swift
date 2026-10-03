import Foundation

// MARK: - Les pistes du questionnaire (1er octobre 2026)
//
// Pendant qu'elle répond, la personne voit ce que ses réponses nous apprennent :
// « grâce à ces réponses, on soupçonne telle ou telle chose » (demande
// d'Arthur). C'est ce qui donne une raison de répondre à la question suivante.
//
// TROIS RÈGLES, à ne pas assouplir :
//
//   1. Une piste vient d'un FAIT du registre (`HealthCalculator.registreApports`),
//      jamais d'un symptôme. C'est la doctrine de `SymptomesApports` : le score
//      décide, le symptôme explique, après. Cocher « fatigue » n'affiche rien.
//
//   2. Aucune table n'est recopiée. Ce qu'un écran a appris se lit par
//      DIFFÉRENCE : le registre du profil, moins le registre du même profil
//      privé des réponses de cet écran. Si le moteur change, les pistes suivent.
//
//   3. Un fait qui ne dépend pas de la vie de la personne (son sexe, son âge)
//      ne fait pas une piste à lui seul : il règle ses besoins
//      (`BesoinsDeReference`), il n'annonce rien.
//
// Le vocabulaire reste celui de l'app : « piste », « à surveiller », « ton
// assiette dira si elle compense ».

/// Un fait que la personne vient de déclarer, et ce qu'il pèse sur un apport.
struct FaitBilan: Equatable {
    let nutriment: NutrientID
    let libelle: String
    let delta: Int
}

/// Ce que l'on sait d'un apport avant que l'assiette ait parlé.
enum EtatApport: Equatable {
    /// Le mode de vie pèse assez pour qu'on le dise.
    case aSurveiller
    /// Rien ne pèse, et quelque chose aide.
    case bienParti
    /// On ne sait pas encore : l'assiette tranchera.
    case enAttente

    /// Le mot affiché sous le nom de l'apport.
    var mention: String {
        switch self {
        case .aSurveiller: return "à surveiller"
        case .bienParti: return "bien parti"
        case .enAttente: return "en attente"
        }
    }
}

/// La lecture du profil à un instant du questionnaire.
struct LectureBilan: Equatable {
    let etats: [NutrientID: EtatApport]
    /// Les apports à surveiller, du plus touché au moins touché.
    let pistes: [NutrientID]
}

/// La carte qui s'affiche sous les réponses d'un écran.
struct CartePiste: Equatable {
    enum Genre: Equatable {
        /// L'apport est à surveiller.
        case piste
        /// Le fait compte, sans suffire à faire une piste.
        case note
        /// Le fait joue en faveur de la personne.
        case bonPoint
        /// Ses besoins viennent d'être calculés.
        case besoins
    }

    let genre: Genre
    /// L'apport concerné. `nil` pour la carte des besoins.
    let nutriment: NutrientID?
    let surtitre: String
    let titre: String
    /// Les faits déclarés qui mènent là, tels que le registre les nomme.
    let raisons: [String]
    let texte: String?
}

/// Ce que dit l'écran de fin, une fois l'assiette connue.
struct SyntheseBilan: Equatable {
    struct Ligne: Equatable, Identifiable {
        let nutriment: NutrientID
        let mention: String
        /// Faux quand l'assiette compense : la ligne se lit en vert.
        let aSurveiller: Bool
        var id: String { nutriment.rawValue }
    }

    /// Nombre d'apports dont le score reste sous le seuil.
    let aSurveiller: Int
    /// Nombre d'apports que l'assiette sert bien.
    let bienServis: Int
    /// Faux si la personne n'a coché aucun aliment.
    let assietteConnue: Bool
    /// Trois lignes au plus.
    let lignes: [Ligne]

    /// « 3 apports à surveiller, 4 bien servis par ton assiette. »
    var phrase: String {
        let surveilles: String
        switch aSurveiller {
        case 0: surveilles = "Aucun apport à surveiller"
        case 1: surveilles = "1 apport à surveiller"
        default: surveilles = "\(aSurveiller) apports à surveiller"
        }
        guard assietteConnue else {
            return surveilles + ". Ton assiette n'a pas encore parlé."
        }
        let servis: String
        switch bienServis {
        case 0: servis = "aucun bien servi par ton assiette"
        case 1: servis = "1 bien servi par ton assiette"
        default: servis = "\(bienServis) bien servis par ton assiette"
        }
        return surveilles + ", " + servis + "."
    }
}

enum PistesBilan {

    /// En dessous de ce total de points, le mode de vie fait une piste.
    static let seuilPiste = -15
    /// À partir de ce total, sans rien qui pèse, l'apport est « bien parti ».
    static let seuilBienParti = 5
    /// Le seuil de l'app : sous 60, un apport est à renforcer.
    static let seuilScore = 60

    // MARK: Le profil sans les réponses d'un écran

    /// Le même profil, comme si la personne n'avait pas répondu à cet écran.
    static func sansReponses(de ecran: EcranBilan, _ profil: UserProfile) -> UserProfile {
        var p = profil
        let vierge = UserProfile.empty
        for id in ecran.questions { effacer(id, dans: &p, vierge) }
        return p
    }

    /// Remet un champ à sa valeur « jamais répondu ». Toutes les questions du
    /// questionnaire y sont : `PistesBilanTests` le vérifie.
    static func effacer(_ id: String, dans p: inout UserProfile, _ v: UserProfile) {
        switch id {
        case "goals": p.goals = v.goals
        case "symptoms": p.symptoms = v.symptoms
        case "firstName": p.firstName = v.firstName
        case "gender": p.gender = v.gender
        case "age": p.age = v.age
        case "height": p.height = v.height
        case "weight": p.weight = v.weight
        case "weightTrend": p.weightTrend = v.weightTrend
        case "indoorWork": p.indoorWork = v.indoorWork
        case "sunExposure": p.sunExposure = v.sunExposure
        case "skinType": p.skinType = v.skinType
        case "strengthTraining": p.strengthTraining = v.strengthTraining
        case "stressLevel": p.stressLevel = v.stressLevel
        case "sleepHours": p.sleepHours = v.sleepHours
        case "wakeFeeling": p.wakeFeeling = v.wakeFeeling
        case "screenBeforeBed": p.screenBeforeBed = v.screenBeforeBed
        case "caffeineIntake": p.caffeineIntake = v.caffeineIntake
        case "caffeineTiming": p.caffeineTiming = v.caffeineTiming
        case "waterIntake": p.waterIntake = v.waterIntake
        case "smoking": p.smoking = v.smoking
        case "alcohol": p.alcohol = v.alcohol
        case "bloating": p.bloating = v.bloating
        case "antibiotics": p.antibiotics = v.antibiotics
        case "dietType": p.dietType = v.dietType
        case "mealsPerDay": p.mealsPerDay = v.mealsPerDay
        case "homeCookedPct": p.homeCookedPct = v.homeCookedPct
        case "cookingMethod": p.cookingMethod = v.cookingMethod
        case "breadType": p.breadType = v.breadType
        case "fermentedFoods": p.fermentedFoods = v.fermentedFoods
        case "ultraProcessedFrequency": p.ultraProcessedFrequency = v.ultraProcessedFrequency
        case "snacking": p.snacking = v.snacking
        case "saltLevel": p.saltLevel = v.saltLevel
        case "iodizedSalt": p.iodizedSalt = v.iodizedSalt
        case "eatLiver": p.eatLiver = v.eatLiver
        case "lowCarbDiet": p.lowCarbDiet = v.lowCarbDiet
        case "supplementsCurrent": p.supplementsCurrent = v.supplementsCurrent
        case "groceries": p.groceries = v.groceries
        case "medications": p.medications = v.medications
        case "digestiveConditions": p.digestiveConditions = v.digestiveConditions
        case "surgicalHistory": p.surgicalHistory = v.surgicalHistory
        case "medicalHistory": p.medicalHistory = v.medicalHistory
        case "allergies": p.allergies = v.allergies
        case "periodFlow": p.periodFlow = v.periodFlow
        case "pregnancyStatus": p.pregnancyStatus = v.pregnancyStatus
        default: break
        }
    }

    /// Les questions que `effacer` sait remettre à zéro.
    static let champsEffacables: Set<String> = [
        "goals", "symptoms", "firstName", "gender", "age", "height", "weight", "weightTrend",
        "indoorWork", "sunExposure", "skinType", "strengthTraining",
        "stressLevel", "sleepHours", "wakeFeeling", "screenBeforeBed",
        "caffeineIntake", "caffeineTiming", "waterIntake", "smoking", "alcohol", "bloating", "antibiotics",
        "dietType", "mealsPerDay", "homeCookedPct", "cookingMethod", "breadType", "fermentedFoods",
        "ultraProcessedFrequency", "snacking", "saltLevel", "iodizedSalt", "eatLiver", "lowCarbDiet",
        "supplementsCurrent", "groceries",
        "medications", "digestiveConditions", "surgicalHistory", "medicalHistory", "allergies",
        "periodFlow", "pregnancyStatus",
    ]

    // MARK: Ce qu'un écran a appris

    /// Les faits que les réponses de cet écran ont fait entrer dans le
    /// registre : ses lignes, moins celles qui y seraient sans cet écran.
    static func faits(de ecran: EcranBilan, profil: UserProfile) -> [FaitBilan] {
        if ecran == .jamais { return faitsJamais(profil) }
        guard !ecran.questions.isEmpty, ecran.repas == nil else { return [] }

        let avec = HealthCalculator.registreApports(profile: profil)
        let sans = HealthCalculator.registreApports(profile: sansReponses(de: ecran, profil))

        var sortie: [FaitBilan] = []
        for id in NutrientID.allCases {
            var dejaLa = sans[id.rawValue]?.contributions ?? []
            for ligne in avec[id.rawValue]?.contributions ?? [] {
                if let index = dejaLa.firstIndex(of: ligne) {
                    dejaLa.remove(at: index)
                } else {
                    sortie.append(FaitBilan(nutriment: id, libelle: ligne.libelle, delta: ligne.delta))
                }
            }
        }
        return sortie
    }

    /// Le libellé d'un aliment que la personne ne mange jamais. Seuls ceux qui
    /// pèsent sur un apport en ont un : les autres ne font pas de fait.
    static let libellesJamais: [String: String] = [
        "nuts": "Jamais de fruits à coque",
        "fish_shellfish": "Jamais de poisson ni de crustacés",
        "milk": "Jamais de lait de vache",
        "egg": "Jamais d'œuf",
        "wheat_gluten": "Jamais de blé ni de gluten",
    ]

    /// Les évictions pèsent dans le registre sous une seule ligne (« antécédents,
    /// opérations et allergies »). Ici on les nomme une par une, en exécutant
    /// le bloc partagé du moteur sur une ardoise à zéro : aucun poids recopié.
    static func faitsJamais(_ profil: UserProfile) -> [FaitBilan] {
        var sortie: [FaitBilan] = []
        for eviction in profil.allergies {
            guard let libelle = libellesJamais[eviction] else { continue }
            var seule = UserProfile.empty
            seule.allergies = [eviction]
            // Le régime « sans gluten » retire déjà l'iode : le moteur ne le
            // compte qu'une fois, il lui faut donc le régime déclaré.
            seule.dietType = profil.dietType

            var ardoise: [String: Int] = [:]
            for id in NutrientID.allCases { ardoise[id.rawValue] = 0 }
            NutrientEngine.applyMedicalHistoryPenalties(&ardoise, profile: seule)

            for id in NutrientID.allCases {
                let delta = ardoise[id.rawValue] ?? 0
                if delta != 0 {
                    sortie.append(FaitBilan(nutriment: id, libelle: libelle, delta: delta))
                }
            }
        }
        return sortie
    }

    // MARK: L'état de chaque apport

    /// Ce que le mode de vie dit de chaque apport, assiette mise à part.
    static func lecture(profil: UserProfile) -> LectureBilan {
        // Sans les courses : le registre ne garde que ce que la personne a
        // déclaré de sa vie et de ses habitudes.
        var horsAssiette = profil
        horsAssiette.groceries = [:]

        let registre = HealthCalculator.registreApports(profile: horsAssiette)
        let sansReperes = HealthCalculator.registreApports(
            profile: sansReponses(de: .reperes, horsAssiette)
        )

        var etats: [NutrientID: EtatApport] = [:]
        var sommes: [NutrientID: Int] = [:]
        for id in NutrientID.allCases {
            guard let detail = registre[id.rawValue] else {
                etats[id] = .enAttente
                continue
            }
            let somme = detail.brut - detail.depart
            sommes[id] = somme
            // Un frein qui tient encore une fois le sexe, l'âge et le poids
            // retirés : c'est un frein vécu.
            let freinVecu = !(sansReperes[id.rawValue]?.freins.isEmpty ?? true)
            if somme <= seuilPiste && freinVecu {
                etats[id] = .aSurveiller
            } else if somme >= seuilBienParti && detail.freins.isEmpty {
                etats[id] = .bienParti
            } else {
                etats[id] = .enAttente
            }
        }

        let pistes = NutrientID.allCases
            .filter { etats[$0] == .aSurveiller }
            .sorted { a, b in
                let sa = sommes[a] ?? 0
                let sb = sommes[b] ?? 0
                return sa != sb ? sa < sb : rang(a) < rang(b)
            }
        return LectureBilan(etats: etats, pistes: pistes)
    }

    private static func rang(_ id: NutrientID) -> Int {
        NutrientID.allCases.firstIndex(of: id) ?? 0
    }

    // MARK: La carte d'un écran

    /// La carte à montrer sous les réponses de cet écran, ou `nil` s'il n'y a
    /// rien à dire. Rien n'est jamais inventé pour remplir la place.
    static func carte(pour ecran: EcranBilan, profil: UserProfile) -> CartePiste? {
        if ecran == .reperes { return carteDesBesoins(profil) }

        let appris = faits(de: ecran, profil: profil)
        let freins = appris.filter { $0.delta < 0 }

        if let cible = apportLePlusTouche(freins) {
            let estPiste = lecture(profil: profil).etats[cible] == .aSurveiller
            let nom = NutrientData.definition(for: cible).label
            let raisons = freins.filter { $0.nutriment == cible }.map(\.libelle)

            var titre = estPiste ? "\(nom) : à surveiller" : "\(nom) : ça compte"
            var texte = ecran.estApresLesRepas
                ? "Ton bilan en tient compte."
                : "Ton assiette dira si elle compense."
            // Le sport ne retire rien : il augmente ce dont le corps a besoin.
            if ecran == .bouger && profil.isActive {
                titre = "Sport régulier : besoins un peu plus hauts"
                texte = "Magnésium, fer et zinc partent plus vite. Ton assiette dira si elle suit."
            }
            return CartePiste(
                genre: estPiste ? .piste : .note,
                nutriment: cible,
                surtitre: estPiste ? "Piste repérée" : "C'est noté",
                titre: titre,
                raisons: raisons,
                texte: texte
            )
        }

        // Rien ne pèse : s'il y a un fait qui aide franchement, on le dit.
        let appuis = appris
            .filter { $0.delta >= seuilBienParti }
            .sorted { a, b in a.delta != b.delta ? a.delta > b.delta : rang(a.nutriment) < rang(b.nutriment) }
        guard let appui = appuis.first else { return nil }

        let titre = appui.libelle.hasPrefix("Tu prends déjà")
            ? "\(appui.libelle) : c'est compté"
            : "\(appui.libelle) : un bon point pour \(possessif(appui.nutriment))"
        return CartePiste(
            genre: .bonPoint,
            nutriment: appui.nutriment,
            surtitre: "Bon point",
            titre: titre,
            raisons: [],
            texte: nil
        )
    }

    /// L'apport sur lequel ces freins pèsent le plus ; à égalité, le premier
    /// dans l'ordre de l'app.
    static func apportLePlusTouche(_ freins: [FaitBilan]) -> NutrientID? {
        var totaux: [NutrientID: Int] = [:]
        for frein in freins { totaux[frein.nutriment, default: 0] += frein.delta }
        return totaux.keys.min { a, b in
            let ta = totaux[a] ?? 0
            let tb = totaux[b] ?? 0
            return ta != tb ? ta < tb : rang(a) < rang(b)
        }
    }

    /// « Tes besoins sont calculés » : les vrais chiffres de cette personne,
    /// ceux de `BesoinsDeReference`.
    static func carteDesBesoins(_ profil: UserProfile) -> CartePiste {
        func besoin(_ id: NutrientID) -> Int {
            Int(BesoinsDeReference.besoin(id, profil: profil).rounded())
        }
        return CartePiste(
            genre: .besoins,
            nutriment: nil,
            surtitre: "On vient de l'apprendre",
            titre: "Tes besoins sont calculés",
            raisons: [],
            texte: "Fer \(besoin(.iron)) mg, magnésium \(besoin(.magnesium)) mg, calcium \(besoin(.calcium)) mg par jour."
        )
    }

    // MARK: L'assiette

    /// Remplissage de la jauge de chaque apport pendant qu'on coche ses
    /// aliments, de 0 à 1 : la part de la cible de la semaine déjà atteinte.
    static func jauges(profil: UserProfile) -> [NutrientID: Double] {
        var sortie: [NutrientID: Double] = [:]
        for apport in GroceryNutrient.allCases {
            guard let id = NutrientID(rawValue: apport.rawValue) else { continue }
            sortie[id] = NutrientEngine.couvertureDesCourses(profil, apport)
        }
        return sortie
    }

    /// « Apporte fer, magnésium, fibres. »
    static func apports(de aliment: GroceryItem) -> String {
        let noms = aliment.nutrients.compactMap { NutrientID(rawValue: $0.rawValue) }.map(nomCourant)
        guard !noms.isEmpty else { return "Rien de notable parmi les 10 apports suivis." }
        return "Apporte " + noms.joined(separator: ", ") + "."
    }

    // MARK: L'écran de fin

    /// Le bilan en une phrase et trois lignes, sur les VRAIS scores : ceux que
    /// la personne retrouvera dans son bilan une minute plus tard.
    static func synthese(profil: UserProfile) -> SyntheseBilan {
        let registre = HealthCalculator.registreApports(profile: profil)
        let assietteConnue = !profil.groceries.isEmpty

        // Les apports sous le seuil, du plus bas au plus haut.
        var bas: [NutrientID] = []
        var scores: [NutrientID: Int] = [:]
        for id in NutrientID.allCases {
            guard let detail = registre[id.rawValue] else { continue }
            scores[id] = detail.score
            if detail.score < seuilScore { bas.append(id) }
        }
        bas.sort { a, b in
            let sa = scores[a] ?? 0
            let sb = scores[b] ?? 0
            return sa != sb ? sa < sb : rang(a) < rang(b)
        }

        var bienServis: [NutrientID] = []
        if assietteConnue {
            for apport in GroceryNutrient.allCases {
                guard NutrientEngine.foodDeltaBrut(profil, apport) >= seuilBienParti,
                      let id = NutrientID(rawValue: apport.rawValue) else { continue }
                bienServis.append(id)
            }
        }

        var lignes: [SyntheseBilan.Ligne] = []
        for id in bas.prefix(3) {
            lignes.append(SyntheseBilan.Ligne(nutriment: id, mention: "à surveiller", aSurveiller: true))
        }
        // S'il reste de la place : les pistes que l'assiette a rattrapées.
        for piste in lecture(profil: profil).pistes {
            guard lignes.count < 3 else { break }
            guard !bas.contains(piste), bienServis.contains(piste) else { continue }
            lignes.append(SyntheseBilan.Ligne(nutriment: piste, mention: "ton assiette compense", aSurveiller: false))
        }

        return SyntheseBilan(
            aSurveiller: bas.count,
            bienServis: bienServis.count,
            assietteConnue: assietteConnue,
            lignes: lignes
        )
    }

    // MARK: Les mots

    /// Le nom de l'apport au milieu d'une phrase.
    static func nomCourant(_ id: NutrientID) -> String {
        switch id {
        case .vitD: return "vitamine D"
        case .vitB12: return "vitamine B12"
        case .iron: return "fer"
        case .magnesium: return "magnésium"
        case .omega3: return "oméga-3"
        case .vitC: return "vitamine C"
        case .calcium: return "calcium"
        case .zinc: return "zinc"
        case .iodine: return "iode"
        case .fiber: return "fibres"
        }
    }

    /// « ta vitamine D », « ton fer », « tes fibres ».
    static func possessif(_ id: NutrientID) -> String {
        switch id {
        case .vitD, .vitB12, .vitC: return "ta \(nomCourant(id))"
        case .omega3, .fiber: return "tes \(nomCourant(id))"
        case .iron, .magnesium, .calcium, .zinc, .iodine: return "ton \(nomCourant(id))"
        }
    }
}
