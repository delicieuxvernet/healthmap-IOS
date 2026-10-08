import XCTest
@testable import HealthMap

/// L'estimateur Swift doit égaler, à 0,1 % près, l'implémentation de référence
/// Python (`estimateur_reference.py`) validée sur INCA 3 : 200 profils figés
/// dans `Fixtures/estimateur-vecteurs.json` (graine 20261008, sexes, âges,
/// grossesse, végétariens, caddies vides ou complets, réponses illisibles,
/// compléments, médicaments, 0 à 16 journées notées). Un seul écart = une CI
/// rouge : on ne corrige jamais le fixture pour faire passer un test, on
/// corrige d'abord la référence Python puis on régénère.
final class EstimateurApportsTests: XCTestCase {

    private static var vecteurs: [String: Any] = {
        let bundle = Bundle(for: EstimateurApportsTests.self)
        guard let url = bundle.url(forResource: "estimateur-vecteurs", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "estimateur-vecteurs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return objet
    }()

    private var estimateur: EstimateurApports {
        get throws { try XCTUnwrap(EstimateurApports.partage, "referentiel-apports.json doit être embarqué dans l'app") }
    }

    // MARK: - Outils

    private func profil(_ d: [String: Any]) -> ProfilEstimation {
        var p = ProfilEstimation()
        func s(_ k: String, _ defaut: String) -> String { d[k] as? String ?? defaut }
        p.gender = s("gender", "homme")
        p.age = s("age", ""); p.weight = s("weight", ""); p.height = s("height", "")
        p.strengthTraining = s("strengthTraining", ""); p.dietType = s("dietType", "omnivore")
        p.caffeineIntake = s("caffeineIntake", ""); p.waterIntake = s("waterIntake", ""); p.alcohol = s("alcohol", "")
        p.mealsPerDay = s("mealsPerDay", ""); p.mealFrequency = s("mealFrequency", "")
        p.pregnancyStatus = s("pregnancyStatus", "na"); p.periodFlow = s("periodFlow", "na")
        p.groceries = (d["groceries"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.intValue }
        p.supplementsCurrent = d["supplementsCurrent"] as? [String] ?? []
        p.medications = d["medications"] as? [String] ?? []
        return p
    }

    private func journees(_ liste: [[String: Any]]) -> [JourneeNotee] {
        liste.map { j in
            let apports = (j["apports"] as? [String: Any] ?? [:]).compactMapValues { v -> Double? in
                v is NSNull ? nil : (v as? NSNumber)?.doubleValue
            }
            return JourneeNotee(kcal: (j["kcal"] as? NSNumber)?.doubleValue ?? 0, apports: apports)
        }
    }

    private func proche(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool {
        abs(a - b) <= tolerance * max(abs(a), abs(b)) + 1e-9
    }

    private func nombre(_ v: Any?) -> Double? { v is NSNull ? nil : (v as? NSNumber)?.doubleValue }

    // MARK: - Les 200 vecteurs

    func testLeReferentielEmbarqueEstCeluiDesVecteurs() throws {
        XCTAssertFalse(Self.vecteurs.isEmpty, "Fixtures/estimateur-vecteurs.json introuvable")
        XCTAssertEqual(try estimateur.version, Self.vecteurs["version_referentiel"] as? String)
    }

    func testLesDeuxCentsVecteursDeReference() throws {
        let e = try estimateur
        let tolerance = nombre(Self.vecteurs["tolerance_relative"]) ?? 0.001
        let liste = Self.vecteurs["vecteurs"] as? [[String: Any]] ?? []
        XCTAssertEqual(liste.count, 200)

        var ecarts: [String] = []
        for v in liste {
            let nom = v["nom"] as? String ?? "?"
            let attendu = v["attendu"] as? [String: Any] ?? [:]
            let r = e.estimer(profil(v["profil"] as? [String: Any] ?? [:]),
                              journees: journees(v["journees"] as? [[String: Any]] ?? []))

            if r.horsPerimetre != (attendu["hors_perimetre"] as? Bool) { ecarts.append("\(nom) hors_perimetre") }
            if r.journeesRetenues != (attendu["journees_retenues"] as? NSNumber)?.intValue { ecarts.append("\(nom) journees_retenues") }
            if r.alimentsInconnus != (attendu["aliments_inconnus"] as? [String] ?? []) { ecarts.append("\(nom) aliments_inconnus") }
            if Set(r.signaux.map(\.id)) != Set(attendu["signaux"] as? [String] ?? []) { ecarts.append("\(nom) signaux") }
            if r.alimentsCoches != (attendu["aliments_coches"] as? NSNumber)?.intValue { ecarts.append("\(nom) aliments cochés") }
            if r.caddieSuffisant != (attendu["caddie_suffisant"] as? Bool) { ecarts.append("\(nom) caddie suffisant") }
            if !proche(r.poidsRemplissage, nombre(attendu["poids_remplissage"]) ?? .nan, tolerance) { ecarts.append("\(nom) poids du remplissage") }

            for (n, x) in attendu["apports"] as? [String: [String: Any]] ?? [:] {
                guard let a = r.apports[n] else { ecarts.append("\(nom).\(n) absent"); continue }
                let ou = "\(nom).\(n)"
                if !proche(a.apportEstime, nombre(x["apport_estime"]) ?? .nan, tolerance) {
                    ecarts.append("\(ou) apport \(a.apportEstime) ≠ \(x["apport_estime"] ?? "nil")")
                }
                switch (a.probabiliteAdequation, nombre(x["probabilite_adequation"])) {
                case (nil, nil): break
                case let (p?, q?) where proche(p, q, tolerance): break
                default: ecarts.append("\(ou) probabilité \(String(describing: a.probabiliteAdequation))")
                }
                if a.statut.rawValue != x["statut"] as? String { ecarts.append("\(ou) statut \(a.statut.rawValue) ≠ \(x["statut"] ?? "")") }
                if a.categorieAlerte != x["categorie_alerte"] as? String { ecarts.append("\(ou) catégorie") }
                if a.alerteOuverte != x["alerte_ouverte"] as? Bool { ecarts.append("\(ou) alerte ouverte") }
                if a.confiance.rawValue != x["confiance"] as? String { ecarts.append("\(ou) confiance") }
                if a.joursJournalRetenus != (x["jours"] as? NSNumber)?.intValue { ecarts.append("\(ou) jours") }

                let ref = x["reference"] as? [String: Any] ?? [:]
                if a.reference.type != ref["type"] as? String { ecarts.append("\(ou) type de référence") }
                for (cle, valeur) in [("bnm", a.reference.bnm), ("rnp", a.reference.rnp),
                                      ("as_", a.reference.apportSatisfaisant), ("lss", a.reference.limite)] {
                    switch (valeur, nombre(ref[cle])) {
                    case (nil, nil): break
                    case let (p?, q?) where proche(p, q, tolerance): break
                    default: ecarts.append("\(ou) référence \(cle)")
                    }
                }

                let d = a.decomposition
                let attenduD = (x["decomposition"] as? [Any] ?? []).map { nombre($0) ?? .nan }
                for (i, valeur) in [d.courses, d.caddieNonRenseigne, d.cafeThe, d.eau, d.alcool, d.reste, d.repasNotes].enumerated()
                where i < attenduD.count && !proche(valeur, attenduD[i], tolerance) {
                    ecarts.append("\(ou) décomposition[\(i)] \(valeur) ≠ \(attenduD[i])")
                }
            }
        }
        XCTAssertTrue(ecarts.isEmpty, "\(ecarts.count) écarts, dont : \(ecarts.prefix(15).joined(separator: " | "))")
    }

    // MARK: - Les cas qui ont motivé l'audit, lisibles

    /// Le testeur du 7 oct. 2026 : « magnésium bas » alors que sa prise de
    /// sang était normale. Neuf aliments cochés : le caddie ne suffit pas,
    /// l'app n'affirme rien (ni alerte ni « couvert ») et compte les aliments
    /// non cochés à leur moyenne française, poids dégressif.
    func testLeCasDeLAuditNAlertePlusSurLeMagnesium() throws {
        var p = ProfilEstimation(gender: "homme", age: "28", weight: "75", height: "178", strengthTraining: "moderate",
                                 caffeineIntake: "moderate", waterIntake: "1.75", alcohol: "rarely", mealsPerDay: "3")
        p.groceries = Dictionary(uniqueKeysWithValues: ["baguette", "pates", "steak_hache", "escalopes_poulet",
                                                        "yaourt_nature", "pommes", "oeufs", "tomates", "courgettes"].map { ($0, 3) })
        let r = try estimateur.estimer(p)
        XCTAssertEqual(r.alimentsCoches, 9)
        XCTAssertFalse(r.caddieSuffisant)
        XCTAssertEqual(r.poidsRemplissage, 6.0 / 15, accuracy: 1e-9)
        let mg = try XCTUnwrap(r.apports["magnesium"])
        XCTAssertEqual(mg.apportEstime, 385, accuracy: 1)  // référentiel 2026-10-08.12
        XCTAssertEqual(mg.statut, .peuPrecise)
        XCTAssertEqual(mg.confiance, .faible)
        XCTAssertGreaterThan(mg.decomposition.cafeThe, 100, "le café APPORTE du magnésium (Ciqual), il n'en retire pas")
        for (id, e) in r.apports {
            XCTAssertNotEqual(e.statut, .aRenforcer, "caddie insuffisant sans journal : aucune alerte (\(id))")
            XCTAssertNotEqual(e.statut, .couvert, "caddie insuffisant sans journal : rien d'affirmé (\(id))")
        }
    }

    /// Règle B : la vitamine D n'est jamais « à surveiller » — 100 % des
    /// adultes INCA 3 sont sous l'AS par l'alimentation.
    func testLaVitamineDNEstJamaisASurveiller() throws {
        let e = try estimateur
        var p = ProfilEstimation(gender: "femme", age: "40", weight: "62", height: "166")
        p.groceries = Dictionary(uniqueKeysWithValues: GroceryCatalog.allItems.prefix(30).map { ($0.id, 3) })
        let vitD = try XCTUnwrap(e.estimer(p).apports["vitD"])
        XCTAssertNotEqual(vitD.statut, .aSurveiller)
    }

    /// Le café est une source, pas une pénalité.
    func testPlusDeCafeCEstPlusDeMagnesium() throws {
        let e = try estimateur
        var sans = ProfilEstimation(gender: "homme", age: "30", weight: "75", height: "178")
        sans.caffeineIntake = "none"
        var beaucoup = sans
        beaucoup.caffeineIntake = "heavy"
        let a = try XCTUnwrap(e.estimer(sans).apports["magnesium"]?.apportEstime)
        let b = try XCTUnwrap(e.estimer(beaucoup).apports["magnesium"]?.apportEstime)
        XCTAssertGreaterThan(b, a)
    }

    /// Végan : pas de viande, de poisson, de laitages ni d'œufs dans le socle.
    func testUnRegimeVeganBaisseLaB12DuSocle() throws {
        let e = try estimateur
        let omnivore = ProfilEstimation(gender: "femme", age: "35", weight: "60", height: "165")
        var vegan = omnivore
        vegan.dietType = "vegan"
        let a = try XCTUnwrap(e.estimer(omnivore).apports["vitB12"]?.apportEstime)
        let b = try XCTUnwrap(e.estimer(vegan).apports["vitB12"]?.apportEstime)
        XCTAssertLessThan(b, a)
    }

    /// Un complément déclaré couvre l'apport, sans jamais parler de dose, et
    /// le chiffre reste celui de l'assiette.
    func testUnComplementCouvreSansChangerLeChiffre() throws {
        let e = try estimateur
        let sans = ProfilEstimation(gender: "homme", age: "40", weight: "80", height: "180")
        var avec = sans
        avec.supplementsCurrent = ["magnesium"]
        let a = try XCTUnwrap(e.estimer(sans).apports["magnesium"])
        let b = try XCTUnwrap(e.estimer(avec).apports["magnesium"])
        XCTAssertEqual(b.statut, .couvertParComplement)
        XCTAssertEqual(a.apportEstime, b.apportEstime, accuracy: 1e-9)
    }

    /// Les médicaments sont des signaux séparés, jamais des points retirés.
    func testLesMedicamentsNeTouchentPasAuxChiffres() throws {
        let e = try estimateur
        let sans = ProfilEstimation(gender: "homme", age: "67", weight: "80", height: "172")
        var avec = sans
        avec.medications = ["ppi", "metformin"]
        let a = e.estimer(sans), b = e.estimer(avec)
        for n in ApportsSuivis.ids {
            XCTAssertEqual(a.apports[n]?.apportEstime ?? -1, b.apports[n]?.apportEstime ?? -2, accuracy: 1e-9, n)
        }
        XCTAssertTrue(b.signaux.map(\.id).contains("medicament_ipp"))
        XCTAssertTrue(b.signaux.map(\.id).contains("medicament_metformine"))
    }
}
