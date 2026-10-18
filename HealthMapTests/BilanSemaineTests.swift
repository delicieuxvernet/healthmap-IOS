import XCTest
@testable import HealthMap

/// Bilan de la semaine : ce que l'app envoie (des faits calculés, rien
/// d'inventé), quand elle le propose, et ce qu'elle sait relire.
final class BilanSemaineTests: XCTestCase {

    private let calendrier = Calendar(identifier: .gregorian)
    private lazy var maintenant: Date = calendrier.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 20))!

    private func jour(_ decalage: Int, heure: Int = 12) -> Date {
        let base = calendrier.startOfDay(for: maintenant)
        return calendrier.date(byAdding: .hour, value: heure, to: calendrier.date(byAdding: .day, value: decalage, to: base)!)!
    }

    private func repas(_ decalage: Int, _ slot: MealJournalService.MealSlot, _ aliments: [String],
                       kcal: Int = 600, proteines: Double = 30, glucides: Double = 70, lipides: Double = 20) -> MealJournalService.MealRecord {
        MealJournalService.MealRecord(
            id: UUID().uuidString,
            consumedAt: jour(decalage, heure: slot == .breakfast ? 8 : slot == .lunch ? 12 : slot == .snack ? 16 : 20),
            slot: slot,
            items: aliments.map { MealJournalService.FoodEntry(name: $0, portionG: 150) },
            macros: MealJournalService.MealMacros(calories: kcal, proteins: proteines, carbs: glucides, fats: lipides, fiber: 6)
        )
    }

    /// Quatre jours, trois repas par jour : 12 repas notés.
    private var semaine: [MealJournalService.MealRecord] {
        (-3...0).flatMap { d in
            [repas(d, .breakfast, ["Café noir"], kcal: 10, proteines: 0, glucides: 0, lipides: 0),
             repas(d, .lunch, ["Poulet rôti", "Riz blanc"]),
             repas(d, .dinner, ["Pâtes", "Café noir"])]
        }
    }

    private func ligne(_ id: String, niveau: Int, statut: StatutApport?, bas: Int) -> LigneMicro {
        LigneMicro(
            id: id, nom: id == "vitD" ? "Vitamine D" : id, unite: "", famille: .vitamines, sens: .besoin,
            niveau: niveau, partDuQuestionnaire: true, besoin: 100, quantiteDuJour: nil, rapport: nil,
            semaine: (0..<7).map { JourMicro(jour: jour(-$0), couverture: $0 < bas ? 20 : 90) },
            statut: .normal, faits: [], contributeurs: [ContributeurMicro(nom: "Œufs", part: 40)],
            role: "", sources: [], statutApport: statut
        )
    }

    func testUnRepasEstUnCreneauPasUneLigne() {
        let midi = (0..<4).map { _ in repas(0, .lunch, ["Un aliment"]) }
        XCTAssertEqual(BilanSemaineBuilder.repasDistincts(midi, calendrier: calendrier), 1)
    }

    func testLaFenetreFaitSeptJoursSansFutur() {
        let tous = [repas(-7, .lunch, ["Trop vieux"]), repas(-6, .lunch, ["Gardé"]), repas(1, .lunch, ["Demain"])]
        let gardes = BilanSemaineBuilder.repasDeLaSemaine(tous, maintenant: maintenant, calendrier: calendrier)
        XCTAssertEqual(gardes.flatMap(\.foods), ["Gardé"])
    }

    func testPasDEntreeSousDixRepasOuTroisJours() {
        let peu = Array(semaine.prefix(9))
        XCTAssertNil(BilanSemaineBuilder.construire(
            repas: peu, tableau: .vide, metrics: PhysicalMetrics(profile: .empty), profil: .empty,
            compositions: [:], profilAlimentaire: .inconnu, maintenant: maintenant, calendrier: calendrier))
        let unJour = (0..<12).map { _ in repas(0, .snack, ["Encas"]) } + [repas(0, .lunch, ["A"]), repas(0, .dinner, ["B"])]
        XCTAssertNil(BilanSemaineBuilder.construire(
            repas: unJour, tableau: .vide, metrics: PhysicalMetrics(profile: .empty), profil: .empty,
            compositions: [:], profilAlimentaire: .inconnu, maintenant: maintenant, calendrier: calendrier))
    }

    func testLEntreeReprendLesFaitsDeLaSemaine() throws {
        let tableau = TableauMicros(priorites: [], toutes: [
            ligne("vitD", niveau: 21, statut: .aSurveiller, bas: 6),
            ligne("iron", niveau: 100, statut: .couvert, bas: 0),
        ])
        let entree = try XCTUnwrap(BilanSemaineBuilder.construire(
            repas: semaine, tableau: tableau, metrics: PhysicalMetrics(profile: .empty), profil: .empty,
            compositions: [:], profilAlimentaire: .inconnu, maintenant: maintenant, calendrier: calendrier))
        XCTAssertEqual(entree.periode.debut, "2026-10-08")
        XCTAssertEqual(entree.periode.fin, "2026-10-14")
        XCTAssertEqual(entree.repasNotes, 12)
        XCTAssertEqual(entree.joursNotes, 4)
        XCTAssertEqual(entree.jours.count, 7)
        XCTAssertNil(entree.jours[0].kcal, "un jour sans repas n'est pas un jour à 0 kcal")
        XCTAssertEqual(entree.jours[6].kcal, 1210)
        XCTAssertEqual(entree.apports.map(\.id), ["vitD", "iron"])
        XCTAssertEqual(entree.apports[0].moyennePct, 21, "le chiffre envoyé est celui que l'app affiche")
        XCTAssertEqual(entree.apports[0].statut, "a_surveiller")
        XCTAssertEqual(entree.apports[0].joursBas, 6)
        XCTAssertEqual(entree.frequences.first?.nom, "Café noir")
        XCTAssertEqual(entree.frequences.first?.fois, 8)
    }

    func testLesMacrosNeComptentQueLesJourneesAssezNotees() {
        let objectifs = BilanSemaineEntree.Objectifs(kcal: 2000, proteines_g: 100, glucides_g: 250, lipides_g: 70, fibres_g: 30)
        let jours = [
            BilanSemaineEntree.Jour(date: "2026-10-13", repas: 3, kcal: 1800, proteines_g: 90, glucides_g: 125, lipides_g: 70, fibres_g: 20, aliments: []),
            BilanSemaineEntree.Jour(date: "2026-10-14", repas: 1, kcal: 400, proteines_g: 10, glucides_g: 20, lipides_g: 5, fibres_g: 2, aliments: []),
        ]
        let macros = BilanSemaineBuilder.macros(jours: jours, objectifs: objectifs, depense: 2000)
        let glucides = macros.first { $0.id == "glucides" }
        XCTAssertEqual(glucides?.joursMesures, 1, "la journée à 400 kcal n'est pas assez notée")
        XCTAssertEqual(glucides?.moyennePct, 50)
        XCTAssertEqual(glucides?.joursAtteints, 0)
        XCTAssertEqual(macros.first { $0.id == "proteines" }?.joursAtteints, 1)
        XCTAssertFalse(macros.contains { $0.id == "fibres" }, "les fibres se lisent comme un apport")
    }

    func testLesCandidatsRespectentLeRegimeEtLesStatuts() {
        let apports = [
            BilanSemaineEntree.Apport(id: "vitD", nom: "Vitamine D", moyennePct: 21, joursBas: 6, joursMesures: 6, statut: "a_surveiller", sources: []),
            BilanSemaineEntree.Apport(id: "iron", nom: "Fer", moyennePct: 40, joursBas: 3, joursMesures: 6, statut: "a_affiner", sources: []),
        ]
        let compositions: Compositions = [
            "ciqual:26038": CompositionAliment(estime: false, apports: ["vitD": 500, "iron": 1]),   // saumon
            "ciqual:22010": CompositionAliment(estime: false, apports: ["vitD": 80, "iron": 1.8]),  // œufs
            "ciqual:20505": CompositionAliment(estime: false, apports: ["iron": 3.3]),              // lentilles
        ]
        let omnivore = BilanSemaineBuilder.suggestions(apports: apports, compositions: compositions, profil: .inconnu)
        XCTAssertEqual(omnivore.map(\.apport), ["vitD"], "« à affiner » n'est pas un manque : pas de candidat")
        XCTAssertEqual(omnivore.first?.aliments.first?.nom, "Saumon")
        let vegetarien = BilanSemaineBuilder.suggestions(apports: apports, compositions: compositions,
                                                         profil: ProfilAlimentaire(regime: "vegetarien"))
        XCTAssertEqual(vegetarien.first?.aliments.map(\.nom), ["Œufs"])
    }

    func testLaCarteSuitLaRegle() throws {
        XCTAssertEqual(BilanSemaineRegle.etat(repas: 6, jours: 3, dernier: nil), .enCours(repas: 6))
        XCTAssertEqual(BilanSemaineRegle.etat(repas: 10, jours: 2, dernier: nil), .enCours(repas: 10))
        XCTAssertEqual(BilanSemaineRegle.etat(repas: 10, jours: 3, dernier: nil), .aPreparer(repas: 10))
        let bilan = try XCTUnwrap(JSONDecoder().decode(BilanSemaine.self, from: Data(Self.reponse.utf8)))
        let lendemain = BilanSemaineRegle.date("2026-10-15")!
        XCTAssertEqual(BilanSemaineRegle.etat(repas: 14, jours: 6, dernier: bilan, maintenant: lendemain), .pret(bilan))
        let semaineSuivante = BilanSemaineRegle.date("2026-10-21")!
        XCTAssertEqual(BilanSemaineRegle.etat(repas: 14, jours: 6, dernier: bilan, maintenant: semaineSuivante), .aPreparer(repas: 14))
    }

    func testLaReponseDuServeurSeRelitEtSeGarde() throws {
        let bilan = try JSONDecoder().decode(BilanSemaine.self, from: Data(Self.reponse.utf8))
        XCTAssertEqual(bilan.titre, "Tu manges varié, mais le poisson a disparu")
        XCTAssertEqual(bilan.recommandations.first?.gainPct, 33)
        XCTAssertEqual(bilan.recommandations.first?.verbe, "AJOUTE")
        XCTAssertEqual(bilan.periodeLisible, "8 – 14 oct.")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "BilanSemaineTests"))
        defaults.removePersistentDomain(forName: "BilanSemaineTests")
        BilanSemaineStore.enregistrer(bilan, defaults: defaults)
        XCTAssertEqual(BilanSemaineStore.dernier(defaults: defaults), bilan)
    }

    func testLEntreeSEncodeAvecLesClesDuServeur() throws {
        let tableau = TableauMicros(priorites: [], toutes: [ligne("vitD", niveau: 21, statut: .aSurveiller, bas: 6)])
        let entree = try XCTUnwrap(BilanSemaineBuilder.construire(
            repas: semaine, tableau: tableau, metrics: PhysicalMetrics(profile: .empty), profil: .empty,
            compositions: [:], profilAlimentaire: .inconnu, maintenant: maintenant, calendrier: calendrier))
        let json = String(decoding: try JSONEncoder().encode(entree), as: UTF8.self)
        for cle in ["\"periode\"", "\"repasNotes\"", "\"proteines_g\"", "\"moyennePct\"", "\"joursBas\"", "\"suggestions\"", "\"version\":1"] {
            XCTAssertTrue(json.contains(cle), cle)
        }
        XCTAssertFalse(json.contains("eau"), "l'eau ne quitte pas le téléphone")
    }

    #if DEBUG
    /// Le bilan d'exemple des captures se termine aujourd'hui : la carte de
    /// Progrès le montre « prêt », jamais un ancien bilan périmé.
    func testLExempleDesCapturesEstPret() {
        let exemple = BilanSemaineExemple.exemple()
        XCTAssertEqual(BilanSemaineRegle.etat(repas: 0, jours: 0, dernier: exemple), .pret(exemple))
        XCTAssertEqual(exemple.recommandations.count, 3)
        XCTAssertNil(BilanSemaineExemple.depuisLesArguments(["HealthMap"]))
    }
    #endif

    private static let reponse = """
    {"version":1,"periode":{"debut":"2026-10-08","fin":"2026-10-14"},"repasNotes":12,"joursNotes":4,
     "titre":"Tu manges varié, mais le poisson a disparu","resume":"Tes repas montrent de bonnes bases.",
     "manques":[{"id":"vitD","nom":"Vitamine D","moyennePct":21,"joursBas":6,"joursMesures":6,"explication":"Aucun poisson gras cette semaine.","type":"apport"}],
     "habitudes":[{"type":"frein","titre":"Aucun poisson en 7 jours","constat":"Tes protéines viennent du poulet.","apports":["vitD"],"illustration":"poisson"}],
     "recommandations":[{"action":"ajouter","titre":"Des sardines, 2 fois","detail":"Une boîte au déjeuner.","apports":["vitD"],"aliment":"Sardines","portion":"1 boîte","gainPct":33,"illustration":"poisson"}],
     "objectif":{"titre":"2 repas de poisson gras","detail":"On le vérifie dimanche prochain."},
     "meta":{"modele":"claude-opus-5-5","genere_le":"2026-10-14T19:00:00Z"}}
    """
}
