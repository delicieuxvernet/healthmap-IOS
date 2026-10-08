import Foundation

// MARK: - Les pistes du questionnaire (1er octobre 2026)
//
// Pendant qu'elle répond, la personne voit ce que ses réponses nous apprennent :
// « grâce à ces réponses, on soupçonne telle ou telle chose » (demande
// d'Arthur). C'est ce qui donne une raison de répondre à la question suivante.
//
// TROIS RÈGLES, à ne pas assouplir :
//
//   1. Une piste vient de l'ESTIMATION des apports (`EstimateurApports`,
//      Ciqual × INCA 3 × ANSES 2021, audit de fiabilité du 8 oct. 2026),
//      jamais d'un symptôme ni d'une habitude sans effet démontré : le stress,
//      les écrans, le sommeil ou le sport ne font plus de piste.
//
//   2. Aucune table n'est recopiée. Ce qu'un écran a appris se lit par
//      DIFFÉRENCE : la part de la référence couverte pour le profil, moins
//      celle du même profil privé des réponses de cet écran. Si l'estimateur
//      change, les pistes suivent.
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

    /// En dessous de cet écart de couverture (en points de la référence), les
    /// habitudes déclarées font une piste.
    static let seuilPiste = -15
    /// À partir de cet écart, l'apport est « bien parti ».
    static let seuilBienParti = 5

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

    // MARK: L'estimation

    /// Sous ce nombre de points de couverture, une différence ne fait pas un fait.
    static let seuilFait = 3
    /// Part de la référence que les courses doivent couvrir pour qu'un apport
    /// soit « bien servi par ton assiette ».
    static let partBienServi = 30

    private static func estimer(_ profil: UserProfile) -> ResultatEstimation? {
        EstimateurApports.partage?.estimer(ProfilEstimation(profile: profil))
    }

    /// La part de la référence couverte, apport par apport (0-100).
    private static func couvertures(_ r: ResultatEstimation?) -> [NutrientID: Int] {
        var sortie: [NutrientID: Int] = [:]
        for id in NutrientID.allCases {
            guard let e = r?.apports[id.rawValue] else { continue }
            sortie[id] = LectureEstimation.couverture(e)
        }
        return sortie
    }

    /// Ce que l'écran a déclaré, en mots de la personne.
    static func libelle(de ecran: EcranBilan, profil: UserProfile) -> String {
        switch ecran {
        case .boire: return "Ton café, ton thé et ton eau"
        case .alcoolTabac: return "Tes boissons alcoolisées"
        case .aTable: return "Tes repas de la journée"
        case .complements: return "Tes compléments"
        case .regime:
            switch profil.dietType {
            case "vegetarien", "vegetarian": return "Alimentation végétarienne"
            case "vegan": return "Alimentation végane"
            default: return "Ton alimentation"
            }
        case .cycle:
            switch profil.pregnancyStatus {
            case "pregnant": return "Grossesse"
            case "breastfeeding": return "Allaitement"
            case "trying_to_conceive": return "Projet de grossesse"
            default: return ["heavy", "very_heavy"].contains(profil.periodFlow) ? "Règles abondantes" : "Ton cycle"
            }
        default: return "Tes réponses"
        }
    }

    // MARK: Ce qu'un écran a appris

    /// Ce que les réponses de cet écran changent à la part de la référence
    /// couverte : l'estimation du profil, moins celle du profil sans elles.
    static func faits(de ecran: EcranBilan, profil: UserProfile) -> [FaitBilan] {
        // Repères et activité physique ne règlent que la dépense, donc les
        // références qui en dépendent (acides gras) : ce n'est pas une piste.
        guard !ecran.questions.isEmpty, ecran.repas == nil, ecran != .reperes, ecran != .bouger else { return [] }
        let avec = couvertures(estimer(profil))
        let sans = couvertures(estimer(sansReponses(de: ecran, profil)))
        let texte = libelle(de: ecran, profil: profil)
        var sortie: [FaitBilan] = []
        for id in NutrientID.allCases {
            guard let a = avec[id], let b = sans[id] else { continue }
            let delta = a - b
            if abs(delta) >= seuilFait {
                sortie.append(FaitBilan(nutriment: id, libelle: texte, delta: delta))
            }
        }
        return sortie
    }

    // MARK: L'état de chaque apport

    /// Les écrans dont les réponses changent l'estimation avant l'assiette.
    static let ecransQuiComptent: [EcranBilan] = [.boire, .alcoolTabac, .regime, .aTable, .cycle]

    /// Ce que les habitudes déclarées disent de chaque apport, assiette mise à
    /// part : l'estimation sans les courses, comparée à celle d'une personne
    /// du même sexe et du même âge qui n'aurait rien déclaré.
    static func lecture(profil: UserProfile) -> LectureBilan {
        var horsAssiette = profil
        horsAssiette.groceries = [:]
        var typique = horsAssiette
        for ecran in ecransQuiComptent { typique = sansReponses(de: ecran, typique) }

        let declare = couvertures(estimer(horsAssiette))
        let reference = couvertures(estimer(typique))

        var etats: [NutrientID: EtatApport] = [:]
        var sommes: [NutrientID: Int] = [:]
        for id in NutrientID.allCases {
            guard let a = declare[id], let b = reference[id] else {
                etats[id] = .enAttente
                continue
            }
            let somme = a - b
            sommes[id] = somme
            if somme <= seuilPiste {
                etats[id] = .aSurveiller
            } else if somme >= seuilBienParti {
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
        if ecran == .complements { return carteDesComplements(profil) }

        let appris = faits(de: ecran, profil: profil)
        let freins = appris.filter { $0.delta < 0 }

        if let cible = apportLePlusTouche(freins) {
            let estPiste = lecture(profil: profil).etats[cible] == .aSurveiller
            let nom = NutrientData.definition(for: cible).label
            let raisons = freins.filter { $0.nutriment == cible }.map(\.libelle)
            return CartePiste(
                genre: estPiste ? .piste : .note,
                nutriment: cible,
                surtitre: estPiste ? "Piste repérée" : "C'est noté",
                titre: estPiste ? "\(nom) : à surveiller" : "\(nom) : ça compte",
                raisons: raisons,
                texte: ecran.estApresLesRepas ? "Ton bilan en tient compte." : "Ton assiette dira si elle compense."
            )
        }

        // Rien ne pèse : s'il y a un fait qui aide franchement, on le dit.
        let appuis = appris
            .filter { $0.delta >= seuilBienParti }
            .sorted { a, b in a.delta != b.delta ? a.delta > b.delta : rang(a.nutriment) < rang(b.nutriment) }
        guard let appui = appuis.first else { return nil }
        return CartePiste(
            genre: .bonPoint,
            nutriment: appui.nutriment,
            surtitre: "Bon point",
            titre: "\(appui.libelle) : un bon point pour \(possessif(appui.nutriment))",
            raisons: [],
            texte: nil
        )
    }

    /// Un complément déclaré couvre son apport : on le dit, sans dose.
    static func carteDesComplements(_ profil: UserProfile) -> CartePiste? {
        guard let r = estimer(profil),
              let couvert = NutrientID.allCases.first(where: { r.apports[$0.rawValue]?.statut == .couvertParComplement })
        else { return nil }
        return CartePiste(
            genre: .bonPoint,
            nutriment: couvert,
            surtitre: "Bon point",
            titre: "Tes compléments : c'est compté",
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

    /// « Tes besoins sont calculés » : les références ANSES 2021 de cette
    /// personne, celles de l'estimateur.
    static func carteDesBesoins(_ profil: UserProfile) -> CartePiste {
        let r = estimer(profil)
        func besoin(_ id: NutrientID) -> Int {
            if let repere = r?.apports[id.rawValue]?.reference.valeurRepere { return Int(repere.rounded()) }
            return Int(BesoinsDeReference.besoin(id, profil: profil).rounded())
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

    /// La part de la référence que les courses couvrent, de 0 à 1.
    private static func partDesCourses(_ e: EstimationApport) -> Double {
        guard e.reference.type != "LSS", let repere = e.reference.valeurRepere, repere > 0 else { return 0 }
        return e.decomposition.courses / repere
    }

    /// Remplissage de la jauge de chaque apport pendant qu'on coche ses
    /// aliments, de 0 à 1 : la part de la référence que les courses couvrent.
    static func jauges(profil: UserProfile) -> [NutrientID: Double] {
        let r = estimer(profil)
        var sortie: [NutrientID: Double] = [:]
        for id in NutrientID.allCases {
            guard let e = r?.apports[id.rawValue] else { continue }
            sortie[id] = min(1, max(0, partDesCourses(e)))
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

    /// Le bilan en une phrase et trois lignes, sur les VRAIS statuts : ceux
    /// que la personne retrouvera dans son bilan une minute plus tard. Une
    /// estimation « à affiner » n'est pas comptée : on ne l'affirme pas.
    static func synthese(profil: UserProfile) -> SyntheseBilan {
        let r = estimer(profil)
        let assietteConnue = !profil.groceries.isEmpty

        func priorite(_ s: StatutApport?) -> Int { s == .aRenforcer ? 0 : 1 }
        var bas: [NutrientID] = NutrientID.allCases.filter {
            let s = r?.apports[$0.rawValue]?.statut
            return s == .aRenforcer || s == .aSurveiller
        }
        let couverture = couvertures(r)
        bas.sort { a, b in
            let pa = priorite(r?.apports[a.rawValue]?.statut), pb = priorite(r?.apports[b.rawValue]?.statut)
            if pa != pb { return pa < pb }
            let sa = couverture[a] ?? 0, sb = couverture[b] ?? 0
            return sa != sb ? sa < sb : rang(a) < rang(b)
        }

        var bienServis: [NutrientID] = []
        if assietteConnue {
            for id in NutrientID.allCases {
                guard let e = r?.apports[id.rawValue], partDesCourses(e) * 100 >= Double(partBienServi) else { continue }
                bienServis.append(id)
            }
        }

        var lignes: [SyntheseBilan.Ligne] = []
        for id in bas.prefix(3) {
            let mention = r?.apports[id.rawValue]?.statut == .aRenforcer ? "à renforcer" : "à surveiller"
            lignes.append(SyntheseBilan.Ligne(nutriment: id, mention: mention, aSurveiller: true))
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
