import Foundation

// MARK: - Estimateur des apports — vraies quantités, vraies références
//
// Audit de fiabilité du 7-8 oct. 2026 : le score d'apport partait de 70 pour
// tout le monde, retirait des points arbitraires (stress, écrans, café…) et
// affichait des milligrammes fabriqués à partir de ce score. Ici, chaque
// apport est une QUANTITÉ estimée :
//
//   courses cochées  = Σ teneur Ciqual 2020 × portion médiane INCA 3 × prises
//                      par semaine du mot choisi (calées sur INCA 3) ÷ 7
// + socle            = ce que les Français du même sexe et de la même classe
//                      d'âge mangent HORS caddie (INCA 3), personnalisé par les
//                      réponses déjà posées qui améliorent la validation
//                      (café et thé, eau, repas par jour, alcool) ; végétariens
//                      et végans : sans viande ni poisson (et sans laitages ni
//                      œufs pour les végans)
// puis, si des journées de repas sont notées : n/(n+k) × leur moyenne
// + k/(n+k) × l'estimation, avec un k propre à chaque apport.
//
// La quantité est comparée à la référence ANSES 2021 de la personne (sexe,
// âge, grossesse, allaitement, règles, régime). Le statut ne vient JAMAIS d'un
// seuil sur un score : une alerte « à renforcer » n'existe que pour les
// apports où la validation sur 616 adultes INCA 3 jamais vus garde moins de
// 10 % de fausses alertes ; sinon « estimation peu précise » jusqu'à ce que
// des repas notés ou une prise de sang l'ouvrent.
//
// Toutes les données viennent de `referentiel-apports.json` (sources,
// méthode et validation : dossier kiwio-donnees-reference, RAPPORT-REFERENTIEL.md
// et SPEC-ESTIMATEUR.md). L'implémentation de référence est
// `estimateur_reference.py` : `EstimateurApportsTests` rejoue ses 200 vecteurs
// à 0,1 % près. Toute correction du calcul se fait d'abord en Python, puis ici.

/// Les apports suivis, dans l'ordre du référentiel.
enum ApportsSuivis {
    static let ids = [
        "vitD", "vitB12", "iron", "magnesium", "omega3", "vitC", "calcium", "zinc", "iodine", "fiber",
        "vitB9", "vitA", "vitE", "vitK", "vitB1", "vitB2", "vitB5", "vitB6", "potassium", "selenium",
        "phosphorus", "copper", "sodium", "epaDha", "ala", "omega6", "omega9",
    ]
}

/// Ce que l'app peut affirmer d'un apport.
enum StatutApport: String, Equatable {
    case couvert = "couvert"
    case aSurveiller = "à surveiller"
    case aRenforcer = "à renforcer"
    /// L'estimation est basse, mais la validation ne permet pas d'alerter sur
    /// le questionnaire seul : on le dit, sans alarmer.
    case peuPrecise = "estimation peu précise"
    case auDessusDeLaLimite = "au-dessus de la limite"
    case sousLaLimite = "sous la limite"
    /// Un complément déclaré couvre l'apport (aucune dose nulle part).
    case couvertParComplement = "couvert par ton complément"
}

enum ConfianceEstimation: String, Equatable {
    case bonne, moyenne, faible
}

/// Les réponses que l'estimateur lit, telles que l'app les stocke.
struct ProfilEstimation: Equatable {
    var gender = "homme"
    var age = ""
    var weight = ""
    var height = ""
    var strengthTraining = ""
    var dietType = "omnivore"
    var caffeineIntake = ""
    var waterIntake = ""
    var alcohol = ""
    var mealsPerDay = ""
    var mealFrequency = ""
    var pregnancyStatus = "na"
    var periodFlow = "na"
    var groceries: [String: Int] = [:]
    var supplementsCurrent: [String] = []
    var medications: [String] = []
}

extension ProfilEstimation {
    init(profile p: UserProfile) {
        self.init(
            gender: p.gender.rawValue, age: p.age, weight: p.weight, height: p.height,
            strengthTraining: p.strengthTraining, dietType: p.dietType,
            caffeineIntake: p.caffeineIntake, waterIntake: p.waterIntake, alcohol: p.alcohol,
            mealsPerDay: p.mealsPerDay, mealFrequency: p.mealFrequency,
            pregnancyStatus: p.pregnancyStatus, periodFlow: p.periodFlow,
            groceries: p.groceries, supplementsCurrent: p.supplementsCurrent, medications: p.medications
        )
    }
}

/// Une journée de repas notés : son énergie et ses apports (nil = la journée
/// ne renseigne pas cet apport, ce n'est pas un zéro).
struct JourneeNotee: Equatable {
    var kcal: Double
    var apports: [String: Double]
}

struct ReferenceApport: Equatable {
    /// BNM, AS, ANC ou LSS (ANSES 2021, Afssa 2010 pour les acides gras).
    let type: String
    let bnm: Double?
    let rnp: Double?
    let apportSatisfaisant: Double?
    let limite: Double?
    let situation: String?

    /// La valeur à laquelle on compare la quantité, pour l'affichage.
    var valeurRepere: Double? {
        switch type {
        case "BNM": return rnp
        case "LSS": return limite
        default: return apportSatisfaisant
        }
    }
}

/// D'où vient la quantité estimée, dans son unité.
struct DecompositionApport: Equatable {
    var courses: Double
    var cafeThe: Double
    var eau: Double
    var alcool: Double
    var reste: Double
    var repasNotes: Double
}

struct ContributionAliment: Equatable {
    let libelle: String
    let apport: Double
}

struct EstimationApport: Equatable {
    let id: String
    let apportEstime: Double
    let unite: String
    let reference: ReferenceApport
    let probabiliteAdequation: Double?
    let statut: StatutApport
    /// Le statut avant un éventuel complément déclaré.
    let statutAlimentsSeuls: StatutApport
    let categorieAlerte: String
    let alerteOuverte: Bool
    let joursJournalRetenus: Int
    let k: Double
    let confiance: ConfianceEstimation
    let decomposition: DecompositionApport
    let topCourses: [ContributionAliment]
}

struct SignalApport: Equatable {
    let id: String
    let message: String
}

struct ResultatEstimation: Equatable {
    let versionReferentiel: String
    let horsPerimetre: Bool
    let alimentsInconnus: [String]
    let journeesRetenues: Int
    let apports: [String: EstimationApport]
    let signaux: [SignalApport]
}

enum ErreurReferentiel: Error {
    case introuvable
    case illisible(String)
}

final class EstimateurApports {

    /// Le référentiel embarqué dans l'app (`referentiel-apports.json`).
    static let partage: EstimateurApports? = {
        guard let url = Bundle.main.url(forResource: "referentiel-apports", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? EstimateurApports(donnees: data)
    }()

    let version: String
    private let racine: [String: Any]

    init(donnees: Data) throws {
        guard let objet = try JSONSerialization.jsonObject(with: donnees) as? [String: Any] else {
            throw ErreurReferentiel.illisible("racine")
        }
        racine = objet
        version = objet["version"] as? String ?? ""
        guard objet["parametres_estimateur"] is [String: Any], objet["aliments"] is [String: Any] else {
            throw ErreurReferentiel.illisible("parametres_estimateur / aliments")
        }
    }

    // MARK: Lecture du JSON

    private func dico(_ v: Any?) -> [String: Any] { v as? [String: Any] ?? [:] }
    private func nombre(_ v: Any?) -> Double? {
        if v is NSNull { return nil }
        return (v as? NSNumber)?.doubleValue
    }
    private var P: [String: Any] { dico(racine["parametres_estimateur"]) }
    private var SP: [String: Any] { dico(racine["socle_personnalise"]) }

    // MARK: 1. Contexte

    struct Contexte: Equatable {
        let sexe: Int
        let age: Int
        let classe: String
        let kcal: Double
        let femme: Bool
        let enceinte: Bool
        let allaitante: Bool
        let projet: Bool
        let menopause: Bool
        let pertesElevees: Bool
        let vegetarien: Bool
        let vegan: Bool
        let regime: String
        let horsPerimetre: Bool
    }

    func contexte(_ p: ProfilEstimation) -> Contexte {
        let defauts = dico(P["profil_defauts"])
        let sexe = p.gender == "femme" ? 2 : 1
        let age = Int(p.age) ?? Int(nombre(defauts["age"]) ?? 30)
        let poids = Double(p.weight) ?? (nombre(defauts["poids_kg"]) ?? 70)
        let taille = Double(p.height) ?? (nombre(defauts["taille_cm"]) ?? 170)
        let depense = dico(P["depense"])
        let mult = nombre(dico(depense["multiplicateurs_strengthTraining"])[p.strengthTraining])
            ?? nombre(depense["defaut_multiplicateur"]) ?? 1.2
        let kcal: Double
        if poids > 0, taille > 0, age > 0 {
            // Comme HealthCalculator.calculateBMR / calculateTDEE.
            let bmr = (10 * poids + 6.25 * taille - 5 * Double(age) + (sexe == 1 ? 5 : -161)).rounded()
            kcal = (bmr * mult).rounded()
        } else {
            kcal = nombre(depense["repli_kcal"]) ?? 2000
        }
        let classes = (P["classes_age"] as? [[String: Any]]) ?? []
        let ageBorne = max(0, age)
        let classe = (classes.first { c in
            Int(nombre(c["de"]) ?? 0) <= ageBorne && ageBorne <= Int(nombre(c["a"]) ?? 0)
        } ?? classes.last)?["cle"] as? String ?? "18-44"
        let femme = sexe == 2
        let enceinte = femme && p.pregnancyStatus == "pregnant"
        let allaitante = femme && p.pregnancyStatus == "breastfeeding"
        let projet = femme && p.pregnancyStatus == "trying_to_conceive"
        let regle = p.periodFlow
        let menopause = femme && !(enceinte || allaitante) && (age >= 55 || (age >= 45 && (regle == "na" || regle.isEmpty)))
        let alias = dico(P["regles_alias"])
        let vegetariens = alias["dietType_vegetarien"] as? [String] ?? []
        let vegans = alias["dietType_vegan"] as? [String] ?? []
        return Contexte(
            sexe: sexe, age: age, classe: classe, kcal: kcal, femme: femme,
            enceinte: enceinte, allaitante: allaitante, projet: projet, menopause: menopause,
            pertesElevees: !(regle == "light" || regle == "normal"),
            vegetarien: vegetariens.contains(p.dietType) || vegans.contains(p.dietType),
            vegan: vegans.contains(p.dietType),
            regime: p.dietType, horsPerimetre: age < 18
        )
    }

    // MARK: 2. Courses

    /// Apport quotidien de chaque aliment coché, par apport. Ordre des ids trié
    /// (même ordre de sommation que la référence Python).
    private func courses(_ p: ProfilEstimation, _ c: Contexte) -> (parAliment: [(id: String, apports: [String: Double])], inconnus: [String]) {
        let aliments = dico(racine["aliments"])
        let sx = c.sexe == 1 ? "homme" : "femme"
        var parAliment: [(id: String, apports: [String: Double])] = []
        var inconnus: [String] = []
        for id in p.groceries.keys.sorted() {
            guard let v = p.groceries[id], v > 0 else { continue }
            guard let a = aliments[id] as? [String: Any] else { inconnus.append(id); continue }
            let mot = v <= 1 ? "pasBeaucoup" : (v >= 7 ? "beaucoup" : "moderement")
            let portions = dico(a["portion_g"])
            let g = nombre(portions[sx]) ?? nombre(portions["homme"]) ?? 0
            let prises = nombre(dico(a["prises_par_semaine"])[mot]) ?? 0
            let pour100 = dico(a["pour_100g"])
            var apports: [String: Double] = [:]
            for n in ApportsSuivis.ids {
                apports[n] = (nombre(pour100[n]) ?? 0) * g / 100 * prises / 7
            }
            parAliment.append((id: id, apports: apports))
        }
        return (parAliment, inconnus)
    }

    // MARK: 3. Socle hors caddie personnalisé

    private struct Socle {
        let total: Double
        let cafeThe: Double
        let eau: Double
        let alcool: Double
    }

    private func socle(_ p: ProfilEstimation, _ c: Contexte, _ n: String) -> Socle {
        let sx = String(c.sexe)
        let base = dico(dico(dico(racine["socle_hors_caddie"])["valeurs"])["\(sx)|\(c.classe)"])
        guard let depart = nombre(base[n]) else { return Socle(total: 0, cafeThe: 0, eau: 0, alcool: 0) }
        var s = depart
        let composantes = dico(SP["composantes"])
        let retenues = SP["reponses_retenues"] as? [String] ?? []
        func valeur(_ composante: String) -> Double { nombre(dico(dico(composantes[composante])[sx])[n]) ?? 0 }

        var parts: [String: Double] = [:]
        for (reponse, composante, cle) in [
            ("caffeineIntake", "cafe_the", p.caffeineIntake),
            ("waterIntake", "eau", p.waterIntake),
            ("alcohol", "alcool", p.alcohol),
        ] {
            let population = valeur(composante)
            var perso = population
            if retenues.contains(reponse), let ligne = dico(SP[reponse])["\(sx)|\(cle)"] as? [String: Any] {
                perso = nombre(ligne[n]) ?? population
            }
            s += perso - population
            parts[composante] = perso
        }

        var f = 1.0
        if retenues.contains("mealsPerDay") {
            let alias = dico(P["regles_alias"])
            var niveau = p.mealsPerDay
            if niveau.isEmpty {
                niveau = dico(alias["mealsPerDay_depuis_mealFrequency"])[p.mealFrequency] as? String ?? ""
            }
            if niveau == "5+" { niveau = alias["mealsPerDay_5plus"] as? String ?? niveau }
            if let ligne = dico(SP["mealsPerDay"])["\(sx)|\(niveau)"] as? [String: Any], let facteur = nombre(ligne[n]) {
                f = facteur
            }
        }
        s += valeur("reste") * (f - 1)

        // Végétarien / végan : décision produit du 8 oct. 2026.
        for composante in dico(SP["regimes"])[c.regime] as? [String] ?? [] {
            s -= valeur(composante) * f
        }
        return Socle(total: max(0, s), cafeThe: parts["cafe_the"] ?? 0, eau: parts["eau"] ?? 0, alcool: parts["alcool"] ?? 0)
    }

    // MARK: 4. Référence

    func reference(_ n: String, _ c: Contexte) -> ReferenceApport {
        let regle = dico(dico(racine["references_regles"])[n])
        let mj = c.kcal * 0.004184
        if n == "vitB1" {
            return ReferenceApport(type: "BNM", bnm: (nombre(regle["bnm_mg_par_MJ"]) ?? 0) * mj,
                                   rnp: (nombre(regle["rnp_mg_par_MJ"]) ?? 0) * mj,
                                   apportSatisfaisant: nil, limite: nil, situation: nil)
        }
        if ["ala", "omega6", "omega9"].contains(n) {
            let v = (nombre(regle["part_energie"]) ?? 0) * c.kcal / (nombre(regle["kcal_par_g"]) ?? 9)
            return ReferenceApport(type: "ANC", bnm: nil, rnp: nil, apportSatisfaisant: v, limite: nil, situation: nil)
        }
        if n == "omega3" {
            let v = (nombre(regle["part_energie_ala"]) ?? 0) * c.kcal / (nombre(regle["kcal_par_g"]) ?? 9)
                + (nombre(regle["epa_dha_g"]) ?? 0)
            return ReferenceApport(type: "ANC", bnm: nil, rnp: nil, apportSatisfaisant: v, limite: nil, situation: nil)
        }
        let situations = dico(regle["situations"])
        var situation: String
        if c.enceinte { situation = "enceinte" }
        else if c.allaitante { situation = "allaitante" }
        else if c.projet && situations["projet_grossesse"] != nil { situation = "projet_grossesse" }
        else if n == "iron" && c.femme {
            situation = c.menopause ? "femme_menopausee" : (c.pertesElevees ? "femme_pertes_elevees" : "femme")
        }
        else if n == "calcium" && c.age < 25 { situation = "moins_de_25_ans" }
        else { situation = c.femme ? "femme" : "homme" }
        if n == "zinc" && c.vegetarien { situation += "_vegetarien" }

        let r = dico(situations[situation])
        let type = r["type"] as? String ?? (regle["type"] as? String ?? "")
        var bnm = nombre(r["bnm"])
        var rnp = nombre(r["rnp"])
        if type == "BNM" {
            if bnm == nil, let rnp { bnm = rnp / 1.2 }
            if n == "iron" && c.vegetarien, let facteur = nombre(regle["facteur_vegetarien"]) {
                bnm = bnm.map { $0 * facteur }
                rnp = rnp.map { $0 * facteur }
            }
        }
        return ReferenceApport(type: type, bnm: bnm, rnp: rnp, apportSatisfaisant: nombre(r["as_"]),
                               limite: nombre(r["lss"]), situation: situation)
    }

    /// Probabilité que l'apport couvre le besoin (IOM 2000). Fer des femmes
    /// réglées : besoin log-normal (médiane BNM, 95e centile RNP).
    func probabilite(_ n: String, _ y: Double, _ r: ReferenceApport, _ c: Contexte) -> Double {
        let bnm = r.bnm ?? 0, rnp = r.rnp ?? 0
        if n == "iron" && c.femme && !(c.menopause || c.enceinte || c.allaitante) {
            let s = log(rnp / bnm) / 1.645
            return Self.phi((log(max(y, 1e-6)) - log(bnm)) / s)
        }
        return Self.phi((y - bnm) / ((rnp - bnm) / 2))
    }

    static func phi(_ x: Double) -> Double { 0.5 * (1 + erf(x / 2.0.squareRoot())) }

    // MARK: 5. Estimation complète

    func estimer(_ p: ProfilEstimation, journees: [JourneeNotee] = []) -> ResultatEstimation {
        let c = contexte(p)
        let (parAliment, inconnus) = courses(p, c)
        let journal = dico(P["journal"])
        let fenetre = Int(nombre(journal["fenetre_jours"]) ?? 14)
        let jours = journees.suffix(fenetre)
        let seuilKcal = (nombre(journal["part_minimale_depense"]) ?? 0.6) * c.kcal
        let retenus = jours.filter { $0.kcal > 0 && $0.kcal >= seuilKcal }
        let caddieVide = parAliment.isEmpty
        let kParDefaut = nombre(journal["k_par_defaut"]) ?? 4

        let carteComplements = dico(P["complements"])
        var couverts = Set<String>()
        for s in p.supplementsCurrent { couverts.formUnion(carteComplements[s] as? [String] ?? []) }

        let alertes = dico(dico(racine["alertes"])["par_apport"])
        let statuts = dico(P["statuts"])
        let couvertSiP = nombre(statuts["bnm_couvert_si_P_au_moins"]) ?? 0.8
        let basSiP = nombre(statuts["bnm_bas_si_P_inferieur_a"]) ?? 0.5
        let seuilsBas = dico(dico(racine["statuts"])["seuils_bas_AS"])
        let unites = dico(racine["unites"])
        let aliments = dico(racine["aliments"])

        var sortie: [String: EstimationApport] = [:]
        for n in ApportsSuivis.ids {
            let coursesN = parAliment.reduce(0.0) { $0 + ($1.apports[n] ?? 0) }
            let soc = socle(p, c, n)
            let q = coursesN + soc.total
            let valeurs = retenus.compactMap { $0.apports[n] }
            let nj = valeurs.count
            let alerte = dico(alertes[n])
            let categorie = alerte["categorie"] as? String ?? "pas d'alerte sur questionnaire seul"
            let journalAlerte = dico(alerte["journal"])
            var k = nombre(journalAlerte["k_recommande"]) ?? 0
            if k == 0 { k = kParDefaut }
            let wj = nj > 0 ? Double(nj) / (Double(nj) + k) : 0
            let y = nj > 0 ? wj * (valeurs.reduce(0, +) / Double(nj)) + (1 - wj) * q : q
            let wq = 1 - wj

            let r = reference(n, c)
            let joursConseilles = nombre(journalAlerte["jours_notes_conseilles_avant_alerte"]).map { Int($0) }
            let ouverte = categorie == "alerte possible" || (joursConseilles.map { nj >= $0 } ?? false)
            var pAdequation: Double?
            let statut: StatutApport
            let regleAlerte = dico(alerte["regle"])

            if r.type == "LSS" {
                if y > (r.limite ?? .infinity) { statut = ouverte ? .auDessusDeLaLimite : .peuPrecise }
                else { statut = .sousLaLimite }
            } else if r.type == "BNM" {
                let pr = probabilite(n, y, r, c)
                pAdequation = pr
                let seuil = categorie == "alerte possible" ? (nombre(regleAlerte["valeur"]) ?? basSiP) : basSiP
                if pr >= couvertSiP { statut = .couvert }
                else if ouverte && pr < seuil { statut = .aRenforcer }
                else if pr < basSiP { statut = .peuPrecise }
                else { statut = .aSurveiller }
            } else {
                let repere = r.apportSatisfaisant ?? 0
                let bas = nombre(seuilsBas["\(n)|\(c.sexe)"])
                let seuil = categorie == "alerte possible"
                    ? nombre(dico(regleAlerte["seuils_par_sexe"])[String(c.sexe)])
                    : bas
                if y >= repere { statut = .couvert }
                else if ouverte, let seuil, y < seuil { statut = .aRenforcer }
                else if bas == nil || y < (bas ?? 0) { statut = .peuPrecise }
                else { statut = .aSurveiller }
            }

            var final = statut
            if couverts.contains(n) && statut != .auDessusDeLaLimite && statut != .sousLaLimite {
                final = .couvertParComplement
            }
            let confiance: ConfianceEstimation =
                (n == "vitK" || (caddieVide && nj == 0)) ? .faible : (ouverte ? .bonne : .moyenne)

            let top = parAliment
                .compactMap { item -> ContributionAliment? in
                    let v = item.apports[n] ?? 0
                    guard v > 0 else { return nil }
                    let libelle = dico(aliments[item.id])["libelle"] as? String ?? item.id
                    return ContributionAliment(libelle: libelle, apport: v * wq)
                }
                .sorted { $0.apport != $1.apport ? $0.apport > $1.apport : $0.libelle < $1.libelle }
                .prefix(3)

            sortie[n] = EstimationApport(
                id: n, apportEstime: y, unite: unites[n] as? String ?? "",
                reference: r, probabiliteAdequation: pAdequation,
                statut: final, statutAlimentsSeuls: statut,
                categorieAlerte: categorie, alerteOuverte: ouverte,
                joursJournalRetenus: nj, k: k, confiance: confiance,
                decomposition: DecompositionApport(
                    courses: coursesN * wq, cafeThe: soc.cafeThe * wq, eau: soc.eau * wq, alcool: soc.alcool * wq,
                    reste: (soc.total - soc.cafeThe - soc.eau - soc.alcool) * wq,
                    repasNotes: y - q * wq
                ),
                topCourses: Array(top)
            )
        }

        // Signaux séparés : jamais un chiffre, toujours « à évoquer avec un médecin ».
        let signaux = dico(P["signaux"])
        // Ordre stable : celui des médicaments déclarés (la référence Python suit
        // l'ordre du JSON ; les tests comparent l'ensemble).
        let parMedicament = dico(signaux["medications"])
        var ids: [String] = []
        for medicament in p.medications {
            if let id = parMedicament[medicament] as? String, !ids.contains(id) { ids.append(id) }
        }
        if let id = dico(signaux["alcohol"])[p.alcohol] as? String { ids.append(id) }
        ids += signaux["toujours"] as? [String] ?? []
        let messages = (dico(racine["ajustements"])["signaux_separes"] as? [[String: Any]] ?? [])
            .reduce(into: [String: String]()) { acc, s in
                if let id = s["id"] as? String { acc[id] = s["message"] as? String ?? "" }
            }

        return ResultatEstimation(
            versionReferentiel: version, horsPerimetre: c.horsPerimetre,
            alimentsInconnus: inconnus, journeesRetenues: retenus.count,
            apports: sortie,
            signaux: ids.map { SignalApport(id: $0, message: messages[$0] ?? "") }
        )
    }
}
