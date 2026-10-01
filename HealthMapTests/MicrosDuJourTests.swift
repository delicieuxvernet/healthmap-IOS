import XCTest
@testable import HealthMap

// MARK: - Les micronutriments du Journal (1er octobre 2026)
//
// Ce que ces tests tiennent :
//   · un apport NON RENSEIGNÉ dans Ciqual n'est jamais lu comme un zéro ;
//   · une journée ne parle que si elle est assez notée ;
//   · le chiffre d'un apport du bilan EST le score du registre (le même que
//     dans Progrès et dans la fiche), celui des autres vient des seuls repas ;
//   · l'alerte suit la règle validée : sous 60 %, trois jours sur sept ;
//   · les priorités ne contiennent ni limite, ni détail d'un autre apport ;
//   · chaque raison affichée cite un fait de la personne.

final class MicrosDuJourTests: XCTestCase {

    private typealias S = MealJournalService

    private let calendrier: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    private lazy var maintenant: Date = calendrier.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 18))!

    /// Deux aliments : le premier renseigne tout, le second ignore la vitamine E.
    private let compositions: Compositions = [
        "ciqual:1": CompositionAliment(estime: false, apports: ["vitE": 10, "vitD": 400, "sodium": 100]),
        "ciqual:2": CompositionAliment(estime: false, apports: ["vitD": 0, "sodium": 100]),
        "ciqual:3": CompositionAliment(estime: false, apports: ["vitD": 100, "vitE": 1]),
    ]

    private func item(_ code: Int, grammes: Double, kcal: Int, nom: String = "Aliment") throws -> S.FoodEntry {
        let json = """
        {"name_fr":"\(nom) \(code)","portion_g":\(grammes),"ciqual_code":\(code),
         "macros":{"calories":\(kcal),"proteins":0,"carbs":0,"fats":0,"fiber":0}}
        """
        return try JSONDecoder().decode(S.FoodEntry.self, from: Data(json.utf8))
    }

    private func repas(_ joursAvant: Int, _ items: [S.FoodEntry]) -> S.MealRecord {
        let jour = calendrier.date(byAdding: .day, value: -joursAvant, to: calendrier.startOfDay(for: maintenant))!
        let midi = calendrier.date(byAdding: .hour, value: 12, to: jour)!
        let kcal = items.reduce(0) { $0 + ($1.macros?.calories ?? 0) }
        return S.MealRecord(id: UUID().uuidString, consumedAt: midi, slot: .lunch,
                            items: items, macros: S.MealMacros(calories: kcal))
    }

    private func contexte(scores: [String: Int] = [:], symptomes: [String] = [],
                          couvertureJournal: [String: Int] = [:],
                          joursJournal: [String: Int] = [:]) -> ContexteMicros {
        var besoins: [String: Double] = [:]
        for micro in Micronutriments.tous { besoins[micro.id] = 100 }
        besoins["vitE"] = 10
        besoins["vitD"] = 600
        besoins["sodium"] = 2300
        return ContexteMicros(besoins: besoins, depense: 2000, scores: scores,
                              couvertureJournal: couvertureJournal, joursJournal: joursJournal,
                              symptomes: symptomes)
    }

    private func tableau(_ repas: [S.MealRecord], contexte: ContexteMicros,
                         registre: [String: DetailApport] = [:]) -> TableauMicros {
        MicrosDuJour.tableau(repas: repas, jourAffiche: maintenant, compositions: compositions,
                             contexte: contexte, registre: registre,
                             maintenant: maintenant, calendar: calendrier)
    }

    private func ligne(_ id: String, dans tableau: TableauMicros) throws -> LigneMicro {
        try XCTUnwrap(tableau.toutes.first { $0.id == id })
    }

    // MARK: - L'aliment tel que la base le connaît

    func testIdentifiantDeLAliment() throws {
        XCTAssertEqual(try item(26038, grammes: 100, kcal: 200).foodId, "ciqual:26038")

        let recherche = #"{"name_fr":"Yaourt","portion_g":125,"food_id":"off:3033490004743","macros":{"calories":80}}"#
        XCTAssertEqual(try JSONDecoder().decode(S.FoodEntry.self, from: Data(recherche.utf8)).foodId, "off:3033490004743")

        // Saisie libre, aliment non reconnu par la photo : rien à demander à la base.
        XCTAssertNil(S.FoodEntry(name: "Soupe maison").foodId)
        let nonReconnu = #"{"name_fr":"Plat inconnu","portion_g":200,"ciqual_code":null,"macros":{"calories":300}}"#
        XCTAssertNil(try JSONDecoder().decode(S.FoodEntry.self, from: Data(nonReconnu.utf8)).foodId)
    }

    func testUnAlimentAjouteDepuisLaRechercheGardeSonIdentifiant() throws {
        let fiche = S.FoodDetail(id: "ciqual:19024", source: "ciqual", name: "Lait entier", kcal100g: 65)
        let entree = try XCTUnwrap(S.entry(for: fiche, grams: 200))
        XCTAssertEqual(entree.foodId, "ciqual:19024")
        // … et le garde après un aller-retour par la base.
        let relu = try JSONDecoder().decode(S.FoodEntry.self, from: JSONEncoder().encode(entree))
        XCTAssertEqual(relu.foodId, "ciqual:19024")
        XCTAssertEqual(relu.portionG, 200)
    }

    // MARK: - Non renseigné n'est pas zéro

    func testUnApportNonRenseigneNEstPasUnZero() throws {
        let jour = repas(1, [try item(1, grammes: 100, kcal: 1500), try item(2, grammes: 100, kcal: 500)])
        let journees = MesuresRepas.journees(repas: [jour], compositions: compositions, calendar: calendrier)
        let journee = try XCTUnwrap(journees.values.first)

        // Vitamine E : seul le premier aliment la renseigne (1 500 kcal sur 2 000).
        // Le second est supposé à l'image du premier : 10 × 2000 / 1500.
        let vitE = try XCTUnwrap(MesuresRepas.couverture("vitE", journee: journee, besoin: 10, depense: 2000))
        XCTAssertEqual(vitE, 133.3, accuracy: 0.1)

        // Vitamine D : le second aliment dit VRAIMENT zéro, il compte pour zéro.
        let vitD = try XCTUnwrap(MesuresRepas.couverture("vitD", journee: journee, besoin: 600, depense: 2000))
        XCTAssertEqual(vitD, 66.7, accuracy: 0.1)

        // Vitamine K : personne ne la renseigne, on ne dit rien.
        XCTAssertNil(MesuresRepas.couverture("vitK", journee: journee, besoin: 79, depense: 2000))
    }

    func testUneJourneeTropPeuNoteeNeDitRien() throws {
        let jour = repas(1, [try item(1, grammes: 100, kcal: 800)])
        let journee = try XCTUnwrap(MesuresRepas.journees(repas: [jour], compositions: compositions, calendar: calendrier).values.first)
        XCTAssertNil(MesuresRepas.couverture("vitE", journee: journee, besoin: 10, depense: 2000))
    }

    func testTropPeuDAlimentsRenseignesNeDitRien() throws {
        // La vitamine E n'est connue que pour 400 kcal sur 2 000 : pas assez.
        let jour = repas(1, [try item(1, grammes: 100, kcal: 400), try item(2, grammes: 100, kcal: 1600)])
        let journee = try XCTUnwrap(MesuresRepas.journees(repas: [jour], compositions: compositions, calendar: calendrier).values.first)
        XCTAssertNil(MesuresRepas.couverture("vitE", journee: journee, besoin: 10, depense: 2000))
        XCTAssertNotNil(MesuresRepas.couverture("vitD", journee: journee, besoin: 600, depense: 2000))
    }

    func testUnRepasAncienGardeCeQuIlAvaitEnregistre() {
        let midi = calendrier.date(byAdding: .hour, value: -30, to: maintenant)!
        let ancien = S.MealRecord(id: "a", consumedAt: midi, slot: .lunch, foods: ["Repas"],
                                  macros: S.MealMacros(calories: 700),
                                  micros: [S.MicroPct(id: "vitD", pctRDA: 50), S.MicroPct(id: "fiber", pctRDA: 40)])
        let parts = MesuresRepas.bouchees(repas: ancien, compositions: compositions)
        XCTAssertEqual(parts.count, 1)
        XCTAssertNil(parts[0].nom)
        XCTAssertEqual(parts[0].quantites["vitD"] ?? 0, 500, accuracy: 0.01)   // 50 % de 1 000 UI
        XCTAssertNil(parts[0].quantites["fiber"])   // les fibres vivent dans les macros
        XCTAssertNil(parts[0].quantites["vitE"])
    }

    // MARK: - Le chiffre

    func testLeChiffreDUnApportDuBilanEstLeScoreDuRegistre() throws {
        // Même avec des repas notés, la ligne affiche le score : c'est lui que
        // les repas corrigent, et c'est lui qu'affichent Progrès et la fiche.
        let jours = try (1...3).map { repas($0, [try item(1, grammes: 100, kcal: 2000)]) }
        let vitD = try ligne("vitD", dans: tableau(jours, contexte: contexte(scores: ["vitD": 42])))
        XCTAssertEqual(vitD.niveau, 42)
        XCTAssertTrue(vitD.partDuQuestionnaire)
    }

    func testLeChiffreDesAutresVientDesRepasDesLaPremiereJournee() throws {
        XCTAssertNil(try ligne("vitE", dans: tableau([], contexte: contexte())).niveau)

        let une = [repas(1, [try item(3, grammes: 100, kcal: 2000)])]
        let vitE = try ligne("vitE", dans: tableau(une, contexte: contexte()))
        XCTAssertEqual(vitE.niveau, 10)   // 1 mg sur 10
        XCTAssertFalse(vitE.partDuQuestionnaire)
        XCTAssertTrue(vitE.faits.contains { $0.texte.contains("1 journée") })
    }

    func testLaJourneeEnCoursCompteDesQuElleEstAssezNotee() throws {
        let complete = [repas(0, [try item(3, grammes: 100, kcal: 2000)])]
        XCTAssertEqual(try ligne("vitE", dans: tableau(complete, contexte: contexte())).niveau, 10)

        // Le matin, 300 kcal notées : pas encore de chiffre…
        let matin = [repas(0, [try item(3, grammes: 100, kcal: 300)])]
        let vitE = try ligne("vitE", dans: tableau(matin, contexte: contexte()))
        XCTAssertNil(vitE.niveau)
        // … mais la journée affichée montre bien ce qui a été noté.
        XCTAssertEqual(vitE.quantiteDuJour ?? 0, 1, accuracy: 0.001)
    }

    func testLeSodiumEstUneLimiteSansChiffreNiPriorite() throws {
        let jours = try (1...3).map { repas($0, [try item(1, grammes: 3000, kcal: 2000)]) }   // 3 000 mg par jour
        let resultat = tableau(jours, contexte: contexte(scores: ["vitD": 90]))
        let sodium = try ligne("sodium", dans: resultat)
        XCTAssertNil(sodium.niveau)
        XCTAssertEqual(sodium.statut, .auDessusDeLaLimite(jours: 3))
        XCTAssertFalse(resultat.priorites.contains { $0.id == "sodium" })
        XCTAssertFalse(resultat.alertes.contains { $0.id == "sodium" })
    }

    // MARK: - L'alerte

    func testBasTroisJoursSurSeptDeclencheLAlerte() throws {
        // 100 UI de vitamine D par jour sur un besoin de 600 : 17 %.
        let trois = try (1...3).map { repas($0, [try item(3, grammes: 100, kcal: 2000)]) }
        let resultat = tableau(trois, contexte: contexte(scores: ["vitD": 55]))
        XCTAssertEqual(try ligne("vitD", dans: resultat).statut, .basProlonge(jours: 3))
        XCTAssertEqual(resultat.alertes.map(\.id).first, "vitD")

        let deux = try (1...2).map { repas($0, [try item(3, grammes: 100, kcal: 2000)]) }
        XCTAssertEqual(try ligne("vitD", dans: tableau(deux, contexte: contexte(scores: ["vitD": 55]))).statut, .normal)
    }

    func testBasSurLaJourneeAfficheeSeulement() throws {
        let aujourdhui = [repas(0, [try item(3, grammes: 100, kcal: 2000)])]
        XCTAssertEqual(try ligne("vitD", dans: tableau(aujourdhui, contexte: contexte(scores: ["vitD": 55]))).statut, .basCeJour)
    }

    func testUneJourneeEnCoursNEstPasBasse() throws {
        // Le matin, 300 kcal notées : on ne colore rien.
        let matin = [repas(0, [try item(3, grammes: 100, kcal: 300)])]
        XCTAssertEqual(try ligne("vitD", dans: tableau(matin, contexte: contexte(scores: ["vitD": 55]))).statut, .normal)
    }

    // MARK: - Les priorités

    func testLesPrioritesSontLesApportsLesPlusBas() {
        let scores = ["vitD": 30, "iron": 40, "magnesium": 50, "omega3": 20, "calcium": 90]
        let resultat = tableau([], contexte: contexte(scores: scores))
        XCTAssertEqual(resultat.priorites.map(\.id), ["omega3", "vitD", "iron"])
    }

    func testUnSymptomeDeclareFaitRemonterUnApportBas() {
        let scores = ["vitD": 50, "iron": 55, "magnesium": 52, "zinc": 54]
        let sans = tableau([], contexte: contexte(scores: scores))
        XCTAssertEqual(sans.priorites.first?.id, "vitD")

        let avec = tableau([], contexte: contexte(scores: scores, symptomes: ["fatigue_chronic"]))
        XCTAssertEqual(avec.priorites.first?.id, "iron")
    }

    func testLeDetailDesOmega3NEntrePasDansLesPriorites() throws {
        let compos: Compositions = ["ciqual:9": CompositionAliment(estime: false, apports: ["ala": 0.01, "epaDha": 0.01, "vitE": 9])]
        let jours = try (1...3).map { repas($0, [try item(9, grammes: 100, kcal: 2000)]) }
        let resultat = MicrosDuJour.tableau(repas: jours, jourAffiche: maintenant, compositions: compos,
                                            contexte: contexte(), registre: [:],
                                            maintenant: maintenant, calendar: calendrier)
        XCTAssertNotNil(try ligne("ala", dans: resultat).niveau)
        XCTAssertEqual(resultat.priorites.map(\.id), ["vitE"])
    }

    // MARK: - Les faits

    func testChaqueLigneCiteCeQueLaPersonneARepondu() throws {
        let detail = DetailApport(
            contributions: [
                ContributionApport(libelle: "Travail en intérieur", delta: -25, section: .modeDeVie),
                ContributionApport(libelle: "Produits laitiers quotidiens", delta: 5, section: .nutrition),
            ],
            score: 50
        )
        let vitD = try ligne("vitD", dans: tableau([], contexte: contexte(scores: ["vitD": 50]), registre: ["vitD": detail]))
        let questionnaire = try XCTUnwrap(vitD.faits.first { $0.genre == .questionnaire })
        XCTAssertTrue(questionnaire.texte.contains("Travail en intérieur"))
        XCTAssertTrue(questionnaire.texte.contains("25 points"))
        // Sans repas notés, on le dit : aucun chiffre inventé.
        let repas = try XCTUnwrap(vitD.faits.first { $0.genre == .repas })
        XCTAssertTrue(repas.texte.contains("Pas encore"))
        XCTAssertTrue(vitD.faits.contains { $0.genre == .jour })
    }

    func testLeFaitDesRepasCiteLaCouvertureEtSonEffet() throws {
        let detail = DetailApport(
            contributions: [
                ContributionApport(libelle: "Travail en intérieur", delta: -25, section: .modeDeVie),
                ContributionApport(libelle: JournalApports.libelle, delta: -13, section: .journal),
            ],
            score: 32
        )
        let vitD = try ligne("vitD", dans: tableau(
            [], contexte: contexte(scores: ["vitD": 32], couvertureJournal: ["vitD": 11], joursJournal: ["vitD": 6]),
            registre: ["vitD": detail]
        ))
        let repas = try XCTUnwrap(vitD.faits.first { $0.genre == .repas })
        XCTAssertTrue(repas.texte.contains("11"))
        XCTAssertTrue(repas.texte.contains("13 points"))
        XCTAssertTrue(repas.texte.contains("6 journées"))
        // Le questionnaire ne cite pas la ligne du journal comme une réponse.
        let questionnaire = try XCTUnwrap(vitD.faits.first { $0.genre == .questionnaire })
        XCTAssertFalse(questionnaire.texte.contains(JournalApports.libelle))
    }

    func testUnSymptomeNEstCiteQueSurUnApportBas() throws {
        let bas = try ligne("iron", dans: tableau([], contexte: contexte(scores: ["iron": 40], symptomes: ["fatigue_chronic"])))
        XCTAssertTrue(bas.faits.contains { $0.genre == .symptome })
        let couvert = try ligne("iron", dans: tableau([], contexte: contexte(scores: ["iron": 85], symptomes: ["fatigue_chronic"])))
        XCTAssertFalse(couvert.faits.contains { $0.genre == .symptome })
    }

    // MARK: - Les repas relus pour le bilan

    func testLesRepasConnusSontRecalculesDepuisLaComposition() throws {
        let connu = repas(1, [try item(1, grammes: 100, kcal: 1500), try item(2, grammes: 100, kcal: 500)])
        let precis = try XCTUnwrap(MesuresRepas.repasPrecises([connu], compositions: compositions).first)
        // 400 UI sur la référence générique de 1 000 UI.
        XCTAssertEqual(precis.micros.first { $0.id == "vitD" }?.pctRDA, 40)
        // Aucun des deux aliments ne renseigne le fer : il reste absent.
        XCTAssertNil(precis.micros.first { $0.id == "iron" })
        XCTAssertEqual(precis.items, connu.items)
    }

    func testUnRepasDontUnAlimentManqueResteTelQuel() throws {
        let partiel = repas(1, [try item(1, grammes: 100, kcal: 1500), try item(77, grammes: 100, kcal: 500)])
        XCTAssertEqual(MesuresRepas.repasPrecises([partiel], compositions: compositions), [partiel])
        XCTAssertEqual(MesuresRepas.repasPrecises([partiel], compositions: [:]), [partiel])
    }

    // MARK: - Le catalogue et les besoins

    func testLeCatalogueEstCoherent() {
        let ids = Micronutriments.tous.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertFalse(ids.contains("fiber"))
        let besoins = BesoinsMicros.tous(profil: UserProfile.empty, depense: 2000)
        for micro in Micronutriments.tous {
            XCTAssertGreaterThan(besoins[micro.id] ?? 0, 0, "besoin manquant pour \(micro.id)")
            XCTAssertFalse(micro.role.isEmpty)
            XCTAssertEqual(micro.sources.count, 3, "trois aliments pour \(micro.id)")
            if let parent = micro.detailDe { XCTAssertTrue(ids.contains(parent)) }
        }
        // Les neuf apports du bilan hors fibres y sont tous.
        for apport in NutrientID.allCases where apport != .fiber {
            XCTAssertTrue(ids.contains(apport.rawValue), "apport du bilan absent : \(apport.rawValue)")
        }
    }

    func testLesBesoinsSuiventLesReferencesDeLANSES() {
        var homme = UserProfile.empty
        homme.gender = .homme
        var femme = UserProfile.empty
        femme.gender = .femme
        var enceinte = femme
        enceinte.pregnancyStatus = "pregnant"

        XCTAssertEqual(BesoinsMicros.besoin("vitA", profil: homme, depense: 2000), 750)
        XCTAssertEqual(BesoinsMicros.besoin("vitA", profil: femme, depense: 2000), 650)
        XCTAssertEqual(BesoinsMicros.besoin("vitB9", profil: femme, depense: 2000), 330)
        XCTAssertEqual(BesoinsMicros.besoin("vitB9", profil: enceinte, depense: 2000), 600)
        XCTAssertEqual(BesoinsMicros.besoin("copper", profil: homme, depense: 2000), 1.9)
        XCTAssertEqual(BesoinsMicros.besoin("sodium", profil: homme, depense: 2000), 2300)
        // Acides gras : une part de l'énergie, ramenée en grammes.
        XCTAssertEqual(BesoinsMicros.besoin("omega6", profil: homme, depense: 2250), 10, accuracy: 0.001)
        XCTAssertEqual(BesoinsMicros.besoin("ala", profil: homme, depense: 2250), 2.5, accuracy: 0.001)
        // Thiamine : 0,1 mg par mégajoule.
        XCTAssertEqual(BesoinsMicros.besoin("vitB1", profil: homme, depense: 2390), 1.0, accuracy: 0.01)
        // Un apport du bilan garde le besoin de la fiche.
        XCTAssertEqual(BesoinsMicros.besoin("vitD", profil: homme, depense: 2000),
                       BesoinsDeReference.besoin(.vitD, profil: homme))
    }

    func testLaPrecisionDesQuantitesSuitLOrdreDeGrandeur() {
        XCTAssertEqual(MicrosDuJour.quantite(120.4), "120")
        XCTAssertEqual(MicrosDuJour.quantite(4.24), "4,2")
        XCTAssertEqual(MicrosDuJour.quantite(0.254), "0,25")
        XCTAssertEqual(MicrosDuJour.quantite(0), "0")
    }
}
