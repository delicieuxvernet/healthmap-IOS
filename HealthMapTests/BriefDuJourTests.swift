import XCTest
@testable import HealthMap

// MARK: - Brief du jour + rappels personnalisés (11 sept. 2026)
//
// Moteurs purs : aucune I/O, aucun StoreKit, aucune notification réelle. On
// fixe « maintenant » et on construit repas et apports à la main.

@MainActor
final class BriefDuJourTests: XCTestCase {

    private let cal = Calendar.current

    /// Jeudi 10 septembre 2026, à l'heure donnée (calendrier courant).
    private func date(jour: Int = 10, heure: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = jour; c.hour = heure; c.minute = minute
        return cal.date(from: c)!
    }

    private func repas(
        jour: Int,
        heure: Int = 12,
        slot: MealJournalService.MealSlot = .lunch,
        micros: [(String, Int)] = []
    ) -> MealJournalService.MealRecord {
        MealJournalService.MealRecord(
            id: UUID().uuidString,
            consumedAt: date(jour: jour, heure: heure),
            slot: slot,
            foods: ["repas"],
            macros: MealJournalService.MealMacros(calories: 500),
            micros: micros.map { MealJournalService.MicroPct(id: $0.0, pctRDA: $0.1) }
        )
    }

    private func apport(
        _ id: String,
        _ statut: StatutV2,
        pct: Int? = nil,
        aliments: [String] = [],
        conseil: String? = nil
    ) -> ApportV2 {
        ApportV2(
            id: id,
            nom: "nom venu de l'IA",
            statut: statut,
            pctBesoin: pct,
            tipBold: conseil,
            aliments: aliments.map { AlimentV2(nom: $0, icone: nil) }
        )
    }

    // MARK: - Grammaire

    func testPossessif_accordeLeNomDuNutriment() {
        XCTAssertEqual(NomNutriment.possessif(id: "iron", nom: "Fer"), "ton fer")
        XCTAssertEqual(NomNutriment.possessif(id: "vitC", nom: "Vitamine C"), "ta vitamine C")
        XCTAssertEqual(NomNutriment.possessif(id: "vitD", nom: "Vitamine D"), "ta vitamine D")
        XCTAssertEqual(NomNutriment.possessif(id: "omega3", nom: "Oméga-3"), "tes oméga-3")
        XCTAssertEqual(NomNutriment.possessif(id: "fiber", nom: "Fibres"), "tes fibres")
        XCTAssertEqual(NomNutriment.complement(id: "magnesium", nom: "Magnésium"), "de ton magnésium")
    }

    func testEnumeration_seDitCommeUneListe() {
        XCTAssertEqual(NomNutriment.enumeration(["Lentilles", "Boudin noir", "Épinards"]),
                       "Lentilles, boudin noir ou épinards")
        XCTAssertEqual(NomNutriment.enumeration(["lentilles", "Épinards"]), "Lentilles ou épinards")
        XCTAssertEqual(NomNutriment.enumeration(["kiwi"]), "Kiwi")
        XCTAssertEqual(NomNutriment.enumeration(["  ", ""]), "")
    }

    // MARK: - Cibles tirées du bilan

    func testCibles_aCombler_avant_aRenforcer_puisLePlusBas() {
        let cibles = BriefDuJourBuilder.cibles(depuis: [
            apport("vitC", .aRenforcer, pct: 40),
            apport("zinc", .couvre, pct: 90),
            apport("iron", .aCombler, pct: 30),
            apport("vitD", .aRenforcer, pct: 20),
        ])
        XCTAssertEqual(cibles.map(\.id), ["iron", "vitD", "vitC"])
    }

    func testCibles_libellesCanoniques_idInconnuEcarte_alimentsBornes() {
        let cibles = BriefDuJourBuilder.cibles(depuis: [
            apport("iron", .aCombler, aliments: ["Lentilles", "Boudin", "Épinards", "Foie"], conseil: "  "),
            apport("inconnu", .aCombler),
        ])
        XCTAssertEqual(cibles.count, 1)
        // Le libellé vient de NutrientData, jamais de l'IA.
        XCTAssertEqual(cibles.first?.nom, "Fer")
        XCTAssertEqual(cibles.first?.aliments, ["Lentilles", "Boudin", "Épinards"])
        XCTAssertNil(cibles.first?.conseil, "un conseil vide ne s'affiche pas")
    }

    // MARK: - Couverture d'un jour

    func testCouverture_sommeLesRepasDuJourSeulement_plafonneeA100() {
        let meals = [
            repas(jour: 9, micros: [("iron", 30), ("vitC", 80)]),
            repas(jour: 9, heure: 20, slot: .dinner, micros: [("iron", 25), ("vitC", 60)]),
            repas(jour: 8, micros: [("iron", 90)]),
        ]
        let hier = BriefDuJourBuilder.couverture(jour: date(jour: 9, heure: 0), repas: meals)
        XCTAssertEqual(hier["iron"], 55)
        XCTAssertEqual(hier["vitC"], 100)
    }

    // MARK: - Construction

    func testConstruire_hierAssezNote_nommeLePlusBasEtEnFaitLaCible() {
        let apports = [
            apport("iron", .aCombler, aliments: ["Lentilles"]),
            apport("vitD", .aRenforcer),
            apport("vitC", .aRenforcer),
        ]
        let meals = [
            repas(jour: 9, micros: [("iron", 40), ("vitD", 70), ("vitC", 90), ("calcium", 80)]),
            repas(jour: 9, heure: 20, slot: .dinner, micros: [("iron", 18)]),
        ]
        let brief = BriefDuJourBuilder.construire(
            prenom: " Léa ", apports: apports, repas: meals, maintenant: date(heure: 8)
        )
        XCTAssertEqual(brief.prenom, "Léa")
        XCTAssertEqual(brief.repasHier, 2)
        // vitD 70, vitC 90, calcium 80 → 3 besoins couverts (fer à 58).
        XCTAssertEqual(brief.besoinsCouvertsHier, 3)
        XCTAssertEqual(brief.manquesHier.map(\.id), ["iron", "vitD", "vitC"])
        XCTAssertEqual(brief.manquesHier.first?.pourcent, 58)
        XCTAssertEqual(brief.cible?.id, "iron")
    }

    func testConstruire_hierTropPeuNote_neChiffrePasEtProposeDeCompleter() {
        let brief = BriefDuJourBuilder.construire(
            prenom: nil,
            apports: [apport("vitD", .aRenforcer), apport("iron", .aCombler)],
            repas: [repas(jour: 9, micros: [("iron", 20)])],
            maintenant: date(heure: 8)
        )
        XCTAssertNil(brief.besoinsCouvertsHier, "un seul repas ne décrit pas une journée")
        XCTAssertTrue(brief.manquesHier.isEmpty)
        // Sans données d'hier : la priorité du bilan (à combler d'abord).
        XCTAssertEqual(brief.cible?.id, "iron")
        XCTAssertTrue(BriefDuJourBuilder.aDeQuoiParler(brief), "le récap propose de rattraper la veille")
    }

    // MARK: - Récap du jour (refonte du 7 oct. 2026)

    private func repasNomme(
        jour: Int,
        heure: Int = 12,
        aliments: [String],
        micros: [(String, Int)] = []
    ) -> MealJournalService.MealRecord {
        MealJournalService.MealRecord(
            id: UUID().uuidString,
            consumedAt: date(jour: jour, heure: heure),
            slot: heure < 16 ? .lunch : .dinner,
            foods: aliments,
            macros: MealJournalService.MealMacros(calories: 500),
            micros: micros.map { MealJournalService.MicroPct(id: $0.0, pctRDA: $0.1) }
        )
    }

    func testRecap_deuxApportsLesPlusBasHier_chacunAvecSonAliment() {
        let brief = BriefDuJourBuilder.construire(
            prenom: "Léa",
            apports: [
                apport("vitC", .aRenforcer, aliments: ["Kiwi"]),
                apport("iron", .aCombler, aliments: ["Lentilles", "Épinards"]),
                apport("vitD", .aRenforcer, aliments: ["Sardines"]),
            ],
            repas: [
                repasNomme(jour: 9, aliments: ["Pâtes", "Salade"], micros: [("iron", 20), ("vitC", 50), ("vitD", 10)]),
                repasNomme(jour: 9, heure: 20, aliments: ["pâtes", "Yaourt"], micros: [("iron", 10), ("vitC", 40)]),
            ],
            maintenant: date(heure: 8)
        )
        // Hier : vitD 10, fer 30, vitC 90 (couverte, jamais citée).
        XCTAssertEqual(brief.priorites.map(\.id), ["vitD", "iron"])
        XCTAssertEqual(brief.priorites.map(\.pourcent), [10, 30])
        XCTAssertEqual(brief.priorites.map(\.aliment), ["Sardines", "Lentilles"])
        XCTAssertTrue(brief.priorites.allSatisfy { $0.periode == .hier })
        // Ce qui a été noté, sans doublon (« Pâtes » et « pâtes »).
        XCTAssertEqual(brief.alimentsHier, ["Pâtes", "Salade", "Yaourt"])
    }

    func testRecap_neProposePasUnAlimentDejaMangeHier_niDeuxFoisLeMeme() {
        XCTAssertEqual(
            BriefDuJourBuilder.choisirAliment(
                parmi: ["Lentilles", "Épinards"],
                mangesHier: ["Salade de lentilles"],
                dejaProposes: []
            ),
            "Épinards"
        )
        XCTAssertEqual(
            BriefDuJourBuilder.choisirAliment(
                parmi: ["Amandes", "Yaourt"],
                mangesHier: [],
                dejaProposes: ["amandes"]
            ),
            "Yaourt"
        )
        // Tout a été mangé : on garde la meilleure piste plutôt que rien.
        XCTAssertEqual(
            BriefDuJourBuilder.choisirAliment(parmi: ["Kiwi"], mangesHier: ["kiwi"], dejaProposes: []),
            "Kiwi"
        )
        XCTAssertNil(BriefDuJourBuilder.choisirAliment(parmi: [" "], mangesHier: [], dejaProposes: []))
    }

    func testRecap_hierTropPeuNote_lisLesJoursPrecedents_puisLeBilan() {
        let apports = [apport("iron", .aCombler), apport("vitD", .aRenforcer)]
        // Avant-hier bien noté, hier non : moyenne des jours précédents.
        let precedents = BriefDuJourBuilder.construire(
            prenom: nil,
            apports: apports,
            repas: [
                repas(jour: 8, micros: [("iron", 20), ("vitD", 30)]),
                repas(jour: 8, heure: 20, slot: .dinner, micros: [("iron", 20)]),
            ],
            maintenant: date(heure: 8)
        )
        XCTAssertEqual(precedents.priorites.map(\.id), ["vitD", "iron"])
        XCTAssertEqual(precedents.priorites.map(\.pourcent), [30, 40])
        XCTAssertTrue(precedents.priorites.allSatisfy { $0.periode == .joursPrecedents })

        // Rien d'exploitable : l'ordre du bilan, sans chiffre inventé.
        let bilan = BriefDuJourBuilder.priorites(
            cibles: BriefDuJourBuilder.cibles(depuis: apports),
            repas: [],
            aujourdhui: date(heure: 8)
        )
        XCTAssertEqual(bilan.map(\.id), ["iron", "vitD"])
        XCTAssertTrue(bilan.allSatisfy { $0.pourcent == nil && $0.periode == .bilan })
        // Repli écrit à la main : jamais d'apport sans aliment.
        XCTAssertEqual(bilan.first?.aliment, "Lentilles")
    }

    func testRecap_toutCouvert_neCiteAucunManque() {
        let brief = BriefDuJourBuilder.construire(
            prenom: nil,
            apports: [apport("iron", .aCombler)],
            repas: [
                repas(jour: 9, micros: NutrientData.all.map { ($0.id.rawValue, 50) }),
                repas(jour: 9, heure: 20, slot: .dinner, micros: NutrientData.all.map { ($0.id.rawValue, 40) }),
            ],
            maintenant: date(heure: 8)
        )
        XCTAssertTrue(brief.priorites.isEmpty, "rien sous 70 % : on n'invente pas de manque")
    }

    func testRecap_completeAvecLApportLePlusBasHorsBilan() {
        let brief = BriefDuJourBuilder.construire(
            prenom: nil,
            apports: [apport("iron", .aCombler)],
            repas: [
                repas(jour: 9, micros: NutrientData.all.map { ($0.id.rawValue, $0.id.rawValue == "omega3" ? 5 : 80) }),
                repas(jour: 9, heure: 20, slot: .dinner, micros: [("iron", 0)]),
            ],
            maintenant: date(heure: 8)
        )
        // Le fer du bilan est couvert (80) ; les oméga-3 (5) prennent la place.
        XCTAssertEqual(brief.priorites.map(\.id), ["omega3"])
        XCTAssertEqual(brief.priorites.first?.nom, "Oméga-3")
    }

    func testAccroche_compteARebours_puisEffort_serie_stat_phrase() {
        let cibles = BriefDuJourBuilder.cibles(depuis: [apport("omega3", .aCombler)])
        let aujourdhui = date(heure: 8)

        // Un seul jour noté sur sept : plus que 2 avant que Progrès compare.
        let unJour = BriefDuJourBuilder.accroche(
            repas: [repas(jour: 9)], aujourdhui: aujourdhui, effort: nil, priorites: []
        )
        XCTAssertEqual(unJour.genre, .apportsBientot)
        XCTAssertEqual(unJour.chiffre, "2")
        XCTAssertEqual(unJour.unite, "jours")
        XCTAssertEqual(unJour.phrase, "Plus que 2 jours de repas notés avant de voir tes apports évoluer dans Progrès.")

        let quatreJours = [repas(jour: 6), repas(jour: 7), repas(jour: 8), repas(jour: 9)]
        let effort = BriefDuJour.Effort(id: "iron", nom: "Fer", points: 12)
        let avecEffort = BriefDuJourBuilder.accroche(
            repas: quatreJours, aujourdhui: aujourdhui, effort: effort, priorites: []
        )
        XCTAssertEqual(avecEffort.genre, .effort)
        XCTAssertEqual(avecEffort.chiffre, "+12")
        XCTAssertTrue(avecEffort.texte.contains("ton fer"))

        let serie = BriefDuJourBuilder.accroche(
            repas: quatreJours, aujourdhui: aujourdhui, effort: nil, priorites: []
        )
        XCTAssertEqual(serie.genre, .serie)
        XCTAssertEqual(serie.chiffre, "4")

        // Trois jours notés mais pas d'affilée jusqu'à hier : la stat publique.
        let troue = [repas(jour: 4), repas(jour: 5), repas(jour: 6)]
        let priorites = BriefDuJourBuilder.priorites(cibles: cibles, repas: [], aujourdhui: aujourdhui)
        let stat = BriefDuJourBuilder.accroche(
            repas: troue, aujourdhui: aujourdhui, effort: nil, priorites: priorites
        )
        XCTAssertEqual(stat.genre, .stat)
        XCTAssertEqual(stat.chiffre, TeaserStatsCatalog.stat(for: "omega3").fraction)
        XCTAssertEqual(stat.source, "INCA3")

        // Un apport sans chiffre national : une phrase, sans chiffre.
        let sansStat = BriefDuJourBuilder.accroche(
            repas: troue, aujourdhui: aujourdhui, effort: nil,
            priorites: BriefDuJourBuilder.priorites(
                cibles: BriefDuJourBuilder.cibles(depuis: [apport("zinc", .aCombler)]),
                repas: [], aujourdhui: aujourdhui
            )
        )
        XCTAssertEqual(sansStat.genre, .phrase)
        XCTAssertNil(sansStat.chiffre)
        XCTAssertTrue(BriefDuJourBuilder.phrasesDeMotivation.contains(sansStat.texte))
    }

    func testRecap_textes() {
        XCTAssertEqual(BriefDuJourView.ligneBesoins(couverts: 6, avantHier: 5),
                       "6 besoins sur 10 couverts hier. Un de plus qu'avant-hier.")
        XCTAssertEqual(BriefDuJourView.ligneBesoins(couverts: 1, avantHier: nil),
                       "1 besoin sur 10 couverts hier.")
        let priorite = BriefDuJour.Priorite(id: "iron", nom: "Fer", pourcent: 30, periode: .hier, aliment: "Lentilles")
        XCTAssertEqual(BriefDuJourView.phraseAccessible(priorite),
                       "Hier, il te manquait : Fer, couvert à 30 %. Ajoute aujourd'hui : Lentilles.")
        XCTAssertTrue(BriefDuJourView.surTitre(prenom: "Léa", maintenant: date(heure: 8))
            .hasPrefix("Bonjour Léa · jeudi 10 septembre"))
    }

    func testComparaison_jamaisCulpabilisante() {
        XCTAssertEqual(BriefDuJourView.comparaison(couverts: 6, avantHier: 5), "Un de plus qu'avant-hier.")
        XCTAssertEqual(BriefDuJourView.comparaison(couverts: 6, avantHier: 3), "3 de plus qu'avant-hier.")
        XCTAssertEqual(BriefDuJourView.comparaison(couverts: 4, avantHier: 4), "Autant qu'avant-hier.")
        XCTAssertEqual(BriefDuJourView.comparaison(couverts: 3, avantHier: 5),
                       "2 de moins qu'avant-hier : aujourd'hui, on remonte.")
        XCTAssertNil(BriefDuJourView.comparaison(couverts: 3, avantHier: nil))
    }

    // MARK: - Mémoire du brief

    func testStore_uneFoisParJour_etInvitationRepousseeTroisJours() {
        let suite = "brief-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let jeudi = date(heure: 8)
        XCTAssertFalse(BriefDuJourStore.dejaVuAujourdhui(maintenant: jeudi, defaults: defaults))
        BriefDuJourStore.marquerVu(maintenant: jeudi, defaults: defaults)
        XCTAssertTrue(BriefDuJourStore.dejaVuAujourdhui(maintenant: date(heure: 22), defaults: defaults))
        XCTAssertFalse(BriefDuJourStore.dejaVuAujourdhui(maintenant: date(jour: 11, heure: 7), defaults: defaults))

        XCTAssertTrue(BriefDuJourStore.invitationAProposer(maintenant: jeudi, defaults: defaults))
        BriefDuJourStore.repousserInvitation(maintenant: jeudi, defaults: defaults)
        XCTAssertFalse(BriefDuJourStore.invitationAProposer(maintenant: date(jour: 12, heure: 8), defaults: defaults))
        XCTAssertTrue(BriefDuJourStore.invitationAProposer(maintenant: date(jour: 13, heure: 9), defaults: defaults))
    }

    // MARK: - Rappels personnalisés (refonte « factuelle » du 1er oct. 2026)

    private let fer = CibleNutritionnelle(
        id: "iron", nom: "Fer", aliments: ["Lentilles", "Boudin noir", "Épinards"], conseil: nil,
        freins: [FreinCible(libelle: "Café ou thé pendant les repas", points: 10)]
    )
    private let vitamineC = CibleNutritionnelle(
        id: "vitC", nom: "Vitamine C", aliments: ["Kiwi"], conseil: "Un kiwi au dessert aide ton fer à passer.",
        freins: [FreinCible(libelle: "Très peu de fruits", points: 20)]
    )
    private var cibles: [CibleNutritionnelle] { [fer, vitamineC] }

    private func contexte(
        cibles: [CibleNutritionnelle]? = nil,
        repas: [MealJournalService.MealRecord] = [],
        maintenant: Date
    ) -> ContexteRappels {
        ContexteRappels.construire(cibles: cibles ?? self.cibles, repas: repas, maintenant: maintenant, calendar: cal)
    }

    private func rappel(_ type: String, _ jour: Int, dans rappels: [RappelPlanifie]) -> RappelPlanifie? {
        rappels.first { $0.id == "\(RappelsPersonnalises.prefixe)\(type).\(jour)" }
    }

    /// Les rappels d'un jour de l'horizon (0 = aujourd'hui).
    private func duJour(_ jour: Int, _ rappels: [RappelPlanifie]) -> [RappelPlanifie] {
        rappels.filter { $0.id.hasSuffix(".\(jour)") }
    }

    /// Deux repas la veille (mercredi 9) : fer à 58 %, vitamine C à 90 %.
    private var veilleNotee: [MealJournalService.MealRecord] {
        [
            repas(jour: 9, micros: [("iron", 40), ("vitC", 90)]),
            repas(jour: 9, heure: 20, slot: .dinner, micros: [("iron", 18)]),
        ]
    }

    /// Petit-déjeuner et déjeuner d'aujourd'hui : fer à 35 %, vitamine C à 70 %.
    private var matineeNotee: [MealJournalService.MealRecord] {
        [
            repas(jour: 10, heure: 8, slot: .breakfast, micros: [("iron", 20), ("vitC", 60)]),
            repas(jour: 10, heure: 12, slot: .lunch, micros: [("iron", 15), ("vitC", 10)]),
        ]
    }

    func testRappels_journeePleineDeuxJours_puisTroisParJour() {
        let maintenant = date(heure: 6)
        let rappels = RappelsPersonnalises.planifier(
            contexte: contexte(maintenant: maintenant), maintenant: maintenant, calendar: cal
        )
        XCTAssertEqual(Set(rappels.map(\.id)).count, rappels.count, "identifiants uniques")
        XCTAssertLessThanOrEqual(rappels.count, 64, "plafond iOS des notifications en attente")
        XCTAssertTrue(rappels.allSatisfy { $0.date > maintenant })
        XCTAssertEqual(rappels.map(\.date), rappels.map(\.date).sorted(), "dans l'ordre où ils sonnent")
        XCTAssertEqual(rappels.last?.id, "\(RappelsPersonnalises.prefixe)retour")

        // Aujourd'hui : l'app est ouverte, pas de brief. Rien n'est noté, donc
        // pas de dernier appel non plus.
        XCTAssertNil(rappel("brief", 0, dans: rappels))
        XCTAssertNil(rappel("appel", 0, dans: rappels))
        for type in ["midi", "encas", "soir"] {
            XCTAssertNotNil(rappel(type, 0, dans: rappels), "\(type) aujourd'hui")
            XCTAssertNotNil(rappel(type, 1, dans: rappels), "\(type) demain")
        }
        XCTAssertNotNil(rappel("brief", 1, dans: rappels))

        // Au-delà de demain : trois par jour, jamais d'encas.
        for jour in 2..<RappelsPersonnalises.horizonJours {
            XCTAssertEqual(duJour(jour, rappels).count, 3, "jour \(jour)")
            XCTAssertNil(rappel("encas", jour, dans: rappels))
            XCTAssertNotNil(rappel("midi", jour, dans: rappels))
            XCTAssertNotNil(rappel("soir", jour, dans: rappels))
            // Le matin : le déclic quand il y en a un, le brief sinon.
            XCTAssertNotEqual(rappel("declic", jour, dans: rappels) == nil,
                              rappel("brief", jour, dans: rappels) == nil, "jour \(jour)")
        }
    }

    func testRappels_creneauPasseOuDejaNote_estSaute() {
        let apresMidi = date(heure: 13)
        let tard = RappelsPersonnalises.planifier(
            contexte: contexte(maintenant: apresMidi), maintenant: apresMidi, calendar: cal
        )
        XCTAssertNil(rappel("midi", 0, dans: tard))

        let matin = date(heure: 9)
        let dejaNote = RappelsPersonnalises.planifier(
            contexte: contexte(repas: [repas(jour: 10, heure: 8, slot: .lunch)], maintenant: matin),
            maintenant: matin, calendar: cal
        )
        XCTAssertNil(rappel("midi", 0, dans: dejaNote))
        XCTAssertNotNil(rappel("midi", 1, dans: dejaNote))

        // Un déjeuner préparé d'avance pour demain : on ne le réclame pas.
        let prepare = RappelsPersonnalises.planifier(
            contexte: contexte(repas: [repas(jour: 11, heure: 12, slot: .lunch)], maintenant: matin),
            maintenant: matin, calendar: cal
        )
        XCTAssertNil(rappel("midi", 1, dans: prepare))
        XCTAssertNotNil(rappel("midi", 0, dans: prepare))
    }

    func testRappels_midi_citeLeChiffreDeLaVeille_etRienQuandElleEstVide() {
        let maintenant = date(heure: 9)
        let rappels = RappelsPersonnalises.planifier(
            contexte: contexte(repas: veilleNotee, maintenant: maintenant), maintenant: maintenant, calendar: cal
        )
        // Le plus bas hier parmi les apports à travailler : le fer, à 58 %.
        let midi0 = rappel("midi", 0, dans: rappels)
        XCTAssertEqual(midi0?.titre, "Ton fer : 58 % hier 🩸")
        XCTAssertTrue(midi0?.corps.lowercased().contains("lentilles, boudin noir ou épinards") ?? false)
        XCTAssertEqual(midi0?.ecran, "meal_scan")

        // Demain, « hier » sera aujourd'hui — où rien n'est noté : pas de chiffre.
        let midi1 = rappel("midi", 1, dans: rappels)
        XCTAssertTrue(midi1?.titre.hasPrefix("Ce midi, mise sur ") ?? false)
        XCTAssertFalse(midi1?.titre.contains("%") ?? true)

        // Et le brief de demain le dit tel quel, en ouvrant sur l'ajout d'un repas.
        let brief1 = rappel("brief", 1, dans: rappels)
        XCTAssertEqual(brief1?.titre, "Ton brief attend tes repas")
        XCTAssertEqual(brief1?.ecran, "meal_scan")
    }

    func testRappels_apresMidi_citeLeChiffreDuJour() {
        let maintenant = date(heure: 14)
        let rappels = RappelsPersonnalises.planifier(
            contexte: contexte(repas: matineeNotee, maintenant: maintenant), maintenant: maintenant, calendar: cal
        )
        // Le soir prend l'apport le plus bas du jour ; l'encas, le suivant.
        XCTAssertEqual(rappel("soir", 0, dans: rappels)?.titre, "Ce soir : ton fer est à 35 % 🩸")
        XCTAssertEqual(rappel("encas", 0, dans: rappels)?.titre, "Un encas ? Ta vitamine C est à 70 % 🍊")

        // La journée est commencée, le dîner manque : dernier appel, chiffré.
        let appel = rappel("appel", 0, dans: rappels)
        XCTAssertEqual(appel?.titre, "Il manque ton dîner 🌙")
        XCTAssertTrue(appel?.corps.hasPrefix("2 repas notés et 1 besoin sur 10 couvert aujourd'hui.") ?? false,
                      appel?.corps ?? "pas de dernier appel")

        // Demain matin, aujourd'hui sera « hier » : le brief et le midi le chiffrent.
        let brief1 = rappel("brief", 1, dans: rappels)
        XCTAssertEqual(brief1?.titre, "Hier : 1 besoin sur 10 couvert 📊")
        XCTAssertTrue(brief1?.corps.hasPrefix("Le plus bas : ton fer, à 35 %.") ?? false)
        XCTAssertEqual(brief1?.ecran, "dashboard")
        XCTAssertEqual(rappel("midi", 1, dans: rappels)?.titre, "Ton fer : 35 % hier 🩸")

        // Le dîner noté : ni rappel du soir, ni dernier appel.
        let avecDiner = matineeNotee + [repas(jour: 10, heure: 13, slot: .dinner, micros: [("iron", 5)])]
        let boucle = RappelsPersonnalises.planifier(
            contexte: contexte(repas: avecDiner, maintenant: maintenant), maintenant: maintenant, calendar: cal
        )
        XCTAssertNil(rappel("soir", 0, dans: boucle))
        XCTAssertNil(rappel("appel", 0, dans: boucle))
    }

    func testRappels_laSerieDeLApp_prendLeTitreDuBrief() {
        let maintenant = date(heure: 14)
        var avecSerie = contexte(repas: matineeNotee, maintenant: maintenant)
        avecSerie.serieDuJour = 5
        let brief = rappel("brief", 1, dans: RappelsPersonnalises.planifier(
            contexte: avecSerie, maintenant: maintenant, calendar: cal
        ))
        XCTAssertEqual(brief?.titre, "5 jours d'affilée 🔥")
        XCTAssertTrue(brief?.corps.hasPrefix("Hier : 1 besoin sur 10 couvert. Le plus bas : ton fer, à 35 %.") ?? false)

        // Deux jours ne font pas encore une habitude.
        avecSerie.serieDuJour = 2
        let sans = rappel("brief", 1, dans: RappelsPersonnalises.planifier(
            contexte: avecSerie, maintenant: maintenant, calendar: cal
        ))
        XCTAssertEqual(sans?.titre, "Hier : 1 besoin sur 10 couvert 📊")
    }

    func testEnrichir_neGardeQueLesHabitudesAlimentaires() {
        let registre = [
            "iron": DetailApport(
                contributions: [
                    ContributionApport(libelle: "Règles très abondantes", delta: -15, section: .sante),
                    ContributionApport(libelle: "Café ou thé pendant les repas", delta: -10, section: .nutrition),
                    ContributionApport(libelle: "Sport régulier", delta: -5, section: .modeDeVie),
                    ContributionApport(libelle: "Légumineuses régulières", delta: 5, section: .nutrition),
                    ContributionApport(libelle: "Poids plume", delta: -3, section: .nutrition),
                ],
                score: 42
            ),
        ]
        let nue = CibleNutritionnelle(id: "iron", nom: "Fer", aliments: [], conseil: nil)
        let enrichies = BriefDuJourBuilder.enrichir([nue], registre: registre)
        // Ni la santé, ni le mode de vie, ni un bonus, ni un frein de 3 points.
        XCTAssertEqual(enrichies.first?.freins,
                       [FreinCible(libelle: "Café ou thé pendant les repas", points: 10)])
        // Un apport absent du registre n'a pas de frein — et pas de déclic.
        XCTAssertEqual(BriefDuJourBuilder.enrichir([nue], registre: [:]).first?.freins, [])
    }

    func testRappels_declic_unJourSurDeux_etSeulementSIlYAUnFrein() {
        let maintenant = date(heure: 6)
        let rappels = RappelsPersonnalises.planifier(
            contexte: contexte(maintenant: maintenant), maintenant: maintenant, calendar: cal
        )
        let declics = rappels.filter { $0.type == "declic" }
        XCTAssertGreaterThanOrEqual(declics.count, 3)
        for jour in 0..<(RappelsPersonnalises.horizonJours - 1) {
            XCTAssertFalse(rappel("declic", jour, dans: rappels) != nil && rappel("declic", jour + 1, dans: rappels) != nil,
                           "deux déclics de suite (jours \(jour) et \(jour + 1))")
        }
        for declic in declics {
            XCTAssertTrue(declic.titre.hasPrefix("Ce qui freine "), declic.titre)
            XCTAssertTrue(declic.corps.contains("points"), declic.corps)
            XCTAssertEqual(declic.ecran, "recommendations")
        }

        // Sans frein alimentaire déclaré : aucun déclic, le brief garde son matin.
        let sansFrein = [CibleNutritionnelle(id: "iron", nom: "Fer", aliments: [], conseil: nil)]
        let sans = RappelsPersonnalises.planifier(
            contexte: contexte(cibles: sansFrein, maintenant: maintenant), maintenant: maintenant, calendar: cal
        )
        XCTAssertTrue(sans.allSatisfy { $0.type != "declic" })
        for jour in 1..<RappelsPersonnalises.horizonJours {
            XCTAssertNotNil(rappel("brief", jour, dans: sans), "brief du jour \(jour)")
        }
    }

    func testRappels_dimanche_laSemaineEnChiffres() {
        // Lundi 7, mardi 8 et mercredi 9 : trois repas sur trois jours.
        let troisJours = [repas(jour: 7), repas(jour: 8), repas(jour: 9)]
        let maintenant = date(heure: 9)
        let rappels = RappelsPersonnalises.planifier(
            contexte: contexte(repas: troisJours, maintenant: maintenant), maintenant: maintenant, calendar: cal
        )
        // Dimanche 13 septembre = jour 3 de l'horizon.
        let semaine = rappel("semaine", 3, dans: rappels)
        XCTAssertEqual(semaine?.titre, "Ta semaine en chiffres 📈")
        XCTAssertTrue(semaine?.corps.hasPrefix("3 repas notés sur 3 jours") ?? false, semaine?.corps ?? "absent")
        XCTAssertEqual(semaine?.ecran, "checkin")
        XCTAssertEqual(rappels.filter { $0.type == "semaine" }.count, 1)

        // Deux repas dans la semaine : rien à chiffrer, on se tait.
        let peu = RappelsPersonnalises.planifier(
            contexte: contexte(repas: [repas(jour: 8), repas(jour: 9)], maintenant: maintenant),
            maintenant: maintenant, calendar: cal
        )
        XCTAssertTrue(peu.allSatisfy { $0.type != "semaine" })
    }

    func testRappels_journalIllisible_nAffirmeRien() {
        let maintenant = date(heure: 6)
        // Hors-ligne au moment de planifier : on a les cibles, pas le journal.
        let rappels = RappelsPersonnalises.planifier(
            contexte: ContexteRappels(cibles: cibles), maintenant: maintenant, calendar: cal
        )
        XCTAssertEqual(rappel("brief", 1, dans: rappels)?.titre, "Ton brief du jour est prêt")
        for type in ["encas", "appel", "semaine"] {
            XCTAssertTrue(rappels.allSatisfy { $0.type != type }, "\(type) affirme un fait du journal")
        }
        for r in rappels where r.type != "declic" {
            let texte = r.titre + " " + r.corps
            XCTAssertFalse(texte.contains("%"), "chiffre sans journal dans \(r.id)")
            XCTAssertFalse(texte.contains("noté hier"), "affirmation sur la veille dans \(r.id)")
            XCTAssertFalse(texte.contains("Rien de noté"), "affirmation sur le journal dans \(r.id)")
        }
    }

    func testRappels_sansBilan_restentUtilesEtGeneriques() {
        let maintenant = date(heure: 9)
        let rappels = RappelsPersonnalises.planifier(
            contexte: contexte(cibles: [], maintenant: maintenant), maintenant: maintenant, calendar: cal
        )
        XCTAssertEqual(rappel("midi", 0, dans: rappels)?.titre, "Photographie ton repas")
        XCTAssertNil(rappel("encas", 0, dans: rappels))
        XCTAssertEqual(rappels.last?.titre, "Ton suivi t'attend")
    }

    func testRappels_tiennentLePlancher_etLeVocabulaire() {
        let proscrits = ["carence", "diagnostic", "patient", "maladie"]
        let situations: [(Date, [MealJournalService.MealRecord])] = [
            (date(heure: 6), []),
            (date(heure: 9), veilleNotee),
            (date(heure: 14), veilleNotee + matineeNotee),
        ]
        for (maintenant, notes) in situations {
            var ctx = contexte(repas: notes, maintenant: maintenant)
            ctx.serieDuJour = 12
            for r in RappelsPersonnalises.planifier(contexte: ctx, maintenant: maintenant, calendar: cal) {
                XCTAssertLessThanOrEqual(r.titre.count, 48, "titre trop long : « \(r.titre) »")
                XCTAssertLessThanOrEqual(r.corps.count, FormulationsRappel.corpsMax, "corps trop long : « \(r.corps) »")
                XCTAssertGreaterThanOrEqual(r.corps.count, 30, "corps trop maigre : « \(r.corps) »")
                let texte = (r.titre + " " + r.corps).lowercased()
                for mot in proscrits {
                    XCTAssertFalse(texte.contains(mot), "« \(mot) » dans \(r.id)")
                }
            }
        }
    }

    func testRappel_type_seLitDansLIdentifiant() {
        func typeDe(_ id: String) -> String {
            RappelPlanifie(id: id, date: date(heure: 9), titre: "", corps: "", ecran: "").type
        }
        XCTAssertEqual(typeDe("\(RappelsPersonnalises.prefixe)midi.3"), "midi")
        XCTAssertEqual(typeDe("\(RappelsPersonnalises.prefixe)retour"), "retour")
    }
}
