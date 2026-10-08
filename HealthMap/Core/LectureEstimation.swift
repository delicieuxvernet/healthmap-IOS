import Foundation

// MARK: - Lire un apport ESTIMÉ (audit de fiabilité, 8 oct. 2026)
//
// Fiche validée par Arthur le 8 oct. 2026 : le verdict parle d'un APPORT
// (« Ton apport en magnésium semble proche de la référence »), jamais d'un
// taux ; la quantité est une vraie quantité (« ≈ 332 sur 380 mg par jour ») ;
// l'anneau et la liste disent d'où elle vient (courses, café et thé, eau,
// reste de l'alimentation, repas notés) ; une ligne rappelle que c'est une
// estimation, pas un résultat d'analyse. Pur, testable phrase par phrase.

extension StatutApport {

    /// Le mot de la pastille.
    var libelleCourt: String {
        switch self {
        case .couvert: return "Couvert"
        case .aSurveiller: return "À surveiller"
        case .aRenforcer: return "À renforcer"
        case .peuPrecise: return "À affiner"
        case .auDessusDeLaLimite: return "Au-dessus de la limite"
        case .sousLaLimite: return "Sous la limite"
        case .couvertParComplement: return "Couvert par ton complément"
        }
    }

    /// Le statut du contrat du bilan (couleurs et libellés des écrans qui le
    /// lisent) : orange pour « à surveiller », rouge seulement pour une alerte
    /// sûre, gris pour une estimation à affiner.
    var statutV2: StatutV2 {
        switch self {
        case .couvert, .couvertParComplement, .sousLaLimite: return .couvre
        case .aSurveiller: return .aRenforcer
        case .aRenforcer, .auDessusDeLaLimite: return .aCombler
        case .peuPrecise: return .neutre
        }
    }

    /// Ce que reçoit `generate-analysis` pour choisir les trois apports du
    /// bilan : les alertes sûres d'abord, puis « à surveiller », puis « à
    /// affiner », puis le reste.
    var codeServeur: String {
        switch self {
        case .couvert, .couvertParComplement, .sousLaLimite: return "couvert"
        case .aSurveiller: return "a_surveiller"
        case .aRenforcer, .auDessusDeLaLimite: return "a_renforcer"
        case .peuPrecise: return "a_affiner"
        }
    }

    /// Une alerte que la validation permet d'affirmer.
    var estUneAlerte: Bool { self == .aRenforcer || self == .auDessusDeLaLimite }

    /// « À renforcer » ou « à surveiller » : l'apport semble sous sa référence
    /// et l'estimation permet de le dire (pas « à affiner »).
    var estASuivre: Bool { self == .aRenforcer || self == .aSurveiller }

    /// L'apport semble sous sa référence, avec ou sans certitude.
    var estSousLaReference: Bool { self == .aSurveiller || self == .aRenforcer || self == .peuPrecise }
}

enum LectureEstimation {

    // MARK: Les unités affichées

    /// La vitamine D s'affiche en UI dans l'app ; le référentiel est en µg.
    static func facteurAffichage(_ id: String) -> Double { id == "vitD" ? 40 : 1 }

    static func uniteAffichage(_ id: String, estimation: EstimationApport) -> String {
        if id == "vitD" { return "UI" }
        switch estimation.unite {
        case "µg ER", "µg (K1)": return "µg"
        default: return estimation.unite
        }
    }

    /// L'apport estimé, dans l'unité affichée.
    static func quantiteAffichee(_ id: String, _ e: EstimationApport) -> Double {
        e.apportEstime * facteurAffichage(id)
    }

    /// Part de la référence couverte, bornée 0-100 : le chiffre des anneaux et
    /// des jauges. Une limite (sodium) n'est pas un objectif : 0.
    static func couverture(_ e: EstimationApport) -> Int {
        guard e.reference.type != "LSS", let repere = e.reference.valeurRepere, repere > 0 else { return 0 }
        return max(0, min(100, Int((e.apportEstime / repere * 100).rounded())))
    }

    // MARK: Le verdict

    /// « magnésium », « vitamine D », « oméga-3 EPA et DHA ».
    static func enMinuscule(_ nom: String) -> String {
        let debut = nom.prefix(2)
        guard debut.count == 2, debut.last?.isUppercase == false else { return nom }
        return nom.prefix(1).lowercased() + nom.dropFirst()
    }

    /// `statut` : celui que l'app retient (une prise de sang récente prime
    /// sur l'estimation) ; à défaut, celui de l'estimation.
    static func verdict(nom: String, estimation e: EstimationApport, statut: StatutApport? = nil) -> String {
        let x = enMinuscule(nom)
        switch statut ?? e.statut {
        case .couvert: return "Ton apport en \(x) semble couvrir la référence."
        case .aSurveiller: return "Ton apport en \(x) semble proche de la référence."
        case .aRenforcer: return "Ton apport en \(x) semble bas."
        case .peuPrecise: return "Ton apport en \(x) reste à préciser : on ne peut rien t'affirmer pour l'instant."
        case .couvertParComplement: return "Ton complément couvre ton apport en \(x)."
        case .auDessusDeLaLimite: return "Ton apport en \(x) semble dépasser la limite conseillée."
        case .sousLaLimite: return "Ton apport en \(x) reste sous la limite conseillée."
        }
    }

    /// « ≈ 332 sur 380 mg par jour » ; sans référence : « ≈ 332 mg par jour ».
    static func quantite(_ id: String, _ e: EstimationApport) -> String {
        let facteur = facteurAffichage(id)
        let unite = uniteAffichage(id, estimation: e)
        let valeur = DS.decimal(arrondiLisible(e.apportEstime * facteur))
        if e.reference.type != "LSS", let repere = e.reference.valeurRepere, repere > 0 {
            return "≈ \(valeur) sur \(DS.decimal(arrondiLisible(repere * facteur)))\(DS.fine)\(unite) par jour"
        }
        if e.reference.type == "LSS", let limite = e.reference.limite {
            return "≈ \(valeur)\(DS.fine)\(unite) par jour, limite \(DS.decimal(arrondiLisible(limite)))\(DS.fine)\(unite)"
        }
        return "≈ \(valeur)\(DS.fine)\(unite) par jour"
    }

    /// Pas de fausse précision : trois chiffres significatifs au plus.
    static func arrondiLisible(_ x: Double) -> Double {
        let a = abs(x)
        if a >= 100 { return x.rounded() }
        if a >= 10 { return (x * 10).rounded() / 10 }
        return (x * 100).rounded() / 100
    }

    /// La ligne sous le verdict : ce que le chiffre est, et ce qu'il n'est pas.
    static func provenance(_ e: EstimationApport) -> String {
        let jours = e.joursJournalRetenus
        let base = jours > 0
            ? "Apport estimé d'après ton questionnaire et \(jours == 1 ? "ta journée notée" : "tes \(jours) journées notées")"
            : "Apport estimé d'après ton questionnaire"
        return base + ", pas un résultat d'analyse."
    }

    /// Les journées de repas qu'il reste à noter avant que l'app puisse
    /// affirmer quelque chose sur cet apport ; nil quand elle le peut déjà, ou
    /// quand seule une prise de sang le permettrait.
    static func journeesAvantFiabilite(_ e: EstimationApport) -> (notees: Int, conseillees: Int)? {
        guard !e.alerteOuverte, let conseillees = e.joursConseilles, conseillees > e.joursJournalRetenus else { return nil }
        return (e.joursJournalRetenus, conseillees)
    }

    /// Caddie insuffisant : combien d'aliments il reste à cocher pour que
    /// l'app puisse affirmer quelque chose. nil quand il suffit.
    static func alimentsACocher(_ r: ResultatEstimation) -> (coches: Int, minimum: Int)? {
        guard !r.caddieSuffisant else { return nil }
        return (r.alimentsCoches, r.alimentsCochesMinimum)
    }

    /// Calcium et magnésium : le corps tient leur taux sanguin serré.
    static let marqueursRegules: Set<String> = PriseDeSangApports.marqueursRegules

    static func notePriseDeSang(_ id: String) -> String? {
        guard marqueursRegules.contains(id) else { return nil }
        let x = id == "calcium" ? "calcium" : "magnésium"
        return "Un \(x) sanguin normal écarte un manque sévère, mais reflète peu ce que tu manges : les deux peuvent être vrais à la fois."
    }

    // MARK: D'où vient l'apport

    struct Source: Identifiable, Equatable {
        let id: String
        let libelle: String
        let detail: String?
        /// Dans l'unité affichée.
        let valeur: Double
        let section: SectionQuestionnaire
    }

    static func libelleCafe(_ reponse: String) -> String? {
        switch reponse {
        case "none": return "Pas de café ni de thé"
        case "light": return "1 à 2 tasses par jour"
        case "moderate": return "3 à 4 tasses par jour"
        case "heavy": return "5 tasses ou plus par jour"
        default: return nil
        }
    }

    static func libelleEau(_ reponse: String) -> String? {
        guard let litres = Double(reponse) else { return nil }
        return "\(DS.decimal(litres))\(DS.fine)L par jour"
    }

    /// Les sources de l'apport, de la plus grosse à la plus petite. Une source
    /// nulle n'est pas listée.
    static func sources(_ id: String, _ e: EstimationApport, profil: ProfilEstimation) -> [Source] {
        let f = facteurAffichage(id)
        let d = e.decomposition
        let courses = e.topCourses.map { enMinuscule($0.libelle) }
        var liste: [Source] = [
            Source(id: "reste", libelle: "Le reste de ton alimentation",
                   detail: "moyenne des Français de ton âge", valeur: d.reste * f, section: .profil),
            Source(id: "cafe", libelle: "Ton café et ton thé",
                   detail: libelleCafe(profil.caffeineIntake) ?? "moyenne des Français", valeur: d.cafeThe * f, section: .modeDeVie),
            Source(id: "courses", libelle: "Tes courses",
                   detail: courses.isEmpty ? nil : courses.joined(separator: ", "), valeur: d.courses * f, section: .nutrition),
            Source(id: "non_coches", libelle: "Les aliments que tu n'as pas cochés",
                   detail: "moyenne des Français", valeur: d.caddieNonRenseigne * f, section: .profil),
            Source(id: "eau", libelle: "Ton eau",
                   detail: libelleEau(profil.waterIntake) ?? "moyenne des Français", valeur: d.eau * f, section: .modeDeVie),
            Source(id: "alcool", libelle: "Tes boissons alcoolisées",
                   detail: nil, valeur: d.alcool * f, section: .modeDeVie),
        ]
        if e.joursJournalRetenus > 0 {
            let n = e.joursJournalRetenus
            liste.append(Source(id: "repas", libelle: "Tes repas notés",
                                detail: n == 1 ? "1 journée notée" : "\(n) journées notées",
                                valeur: d.repasNotes * f, section: .journal))
        }
        let total = liste.reduce(0) { $0 + max(0, $1.valeur) }
        // Une source sous 1 % du total ne dit rien d'utile.
        return liste
            .filter { $0.valeur > 0 && $0.valeur >= total * 0.01 }
            .sorted { $0.valeur > $1.valeur }
    }

    /// Le détail d'un apport estimé, au format du registre : les sources sont
    /// ses contributions, en points de la référence, à partir de 0.
    static func detail(_ id: String, _ e: EstimationApport, profil: ProfilEstimation) -> DetailApport {
        let repere = e.reference.type == "LSS" ? nil : e.reference.valeurRepere
        let contributions: [ContributionApport] = sources(id, e, profil: profil).compactMap { s in
            guard let repere, repere > 0 else { return nil }
            let points = Int((s.valeur / facteurAffichage(id) / repere * 100).rounded())
            guard points > 0 else { return nil }
            return ContributionApport(libelle: s.libelle, delta: points, section: s.section)
        }
        return DetailApport(contributions: contributions, score: couverture(e), depart: 0, estimation: e)
    }

    // MARK: Les journées notées, pour l'estimateur

    /// Les journées du journal, au format de l'estimateur : énergie notée et
    /// quantité de chaque apport, ramenée à la journée entière quand les
    /// aliments qui le renseignent portent au moins la moitié des calories
    /// (sinon : non renseigné, jamais zéro). Ordre chronologique.
    static func journees(_ mesurees: [Date: JourneeMesuree]) -> [JourneeNotee] {
        mesurees.keys.sorted().compactMap { jour -> JourneeNotee? in
            guard let j = mesurees[jour], j.kcal > 0 else { return nil }
            var apports: [String: Double] = [:]
            for n in ApportsSuivis.ids {
                guard let quantite = j.quantites[n],
                      let renseignees = j.kcalRenseignees[n], renseignees > 0,
                      renseignees >= j.kcal * JournalApports.partMinimaleRenseignee else { continue }
                apports[n] = max(0, quantite) * (j.kcal / renseignees) / facteurAffichage(n)
            }
            return JourneeNotee(kcal: j.kcal, apports: apports)
        }
    }
}
