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

        let slides = BriefDuJourBuilder.slides(brief: brief, proposerInvitation: false)
        XCTAssertEqual(slides.map(\.id), ["intro", "rien-hier", "cible"])
    }

    func testSlides_ordre_et_invitationEnDernier() {
        let brief = BriefDuJourBuilder.construire(
            prenom: "Léa",
            apports: [apport("iron", .aCombler)],
            repas: [
                repas(jour: 9, micros: [("iron", 40)]),
                repas(jour: 9, heure: 20, slot: .dinner, micros: [("iron", 10)]),
            ],
            maintenant: date(heure: 8)
        )
        let slides = BriefDuJourBuilder.slides(brief: brief, proposerInvitation: true)
        XCTAssertEqual(slides.first?.id, "intro")
        XCTAssertEqual(slides.last?.id, "invitation")
        XCTAssertTrue(slides.map(\.id).contains("hier"))
        XCTAssertTrue(slides.map(\.id).contains("manques"))
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

    // MARK: - Rappels personnalisés

    private var cibles: [CibleNutritionnelle] {
        [
            CibleNutritionnelle(id: "iron", nom: "Fer", aliments: ["Lentilles", "Boudin noir", "Épinards"], conseil: nil),
            CibleNutritionnelle(id: "vitC", nom: "Vitamine C", aliments: ["Kiwi"], conseil: "Un kiwi au dessert aide ton fer à passer."),
        ]
    }

    func testRappels_troisParJour_auPlus_etRetourAuSeptiemeJour() {
        let rappels = RappelsPersonnalises.planifier(
            cibles: cibles, couvertureHier: [:], creneauxDejaNotes: [], maintenant: date(heure: 9)
        )
        // Aujourd'hui : midi + soir (le brief du matin est déjà passé).
        // Jours 1 à 6 : brief + midi + soir. Puis le retour du 7e jour.
        XCTAssertEqual(rappels.count, 2 + 6 * 3 + 1)
        XCTAssertEqual(Set(rappels.map(\.id)).count, rappels.count, "identifiants uniques")
        XCTAssertLessThanOrEqual(rappels.count, 64, "plafond iOS des notifications en attente")
        XCTAssertTrue(rappels.allSatisfy { $0.date > date(heure: 9) })
        XCTAssertEqual(rappels.last?.titre, "Ton fer t'attend")
    }

    func testRappels_midiPasseOuDejaNote_estSauteAujourdhui() {
        let apresMidi = RappelsPersonnalises.planifier(
            cibles: cibles, couvertureHier: [:], creneauxDejaNotes: [], maintenant: date(heure: 13)
        )
        XCTAssertFalse(apresMidi.contains { $0.id == "\(RappelsPersonnalises.prefixe)midi.0" })

        let dejaNote = RappelsPersonnalises.planifier(
            cibles: cibles, couvertureHier: [:], creneauxDejaNotes: [.lunch], maintenant: date(heure: 9)
        )
        XCTAssertFalse(dejaNote.contains { $0.id == "\(RappelsPersonnalises.prefixe)midi.0" })
        XCTAssertTrue(dejaNote.contains { $0.id == "\(RappelsPersonnalises.prefixe)midi.1" })
    }

    func testRappels_personnalises_chiffreDHierSeulementAujourdhui() {
        let rappels = RappelsPersonnalises.planifier(
            cibles: cibles, couvertureHier: ["iron": 58], creneauxDejaNotes: [], maintenant: date(heure: 9)
        )
        let midi0 = rappels.first { $0.id == "\(RappelsPersonnalises.prefixe)midi.0" }
        XCTAssertEqual(midi0?.titre, "C'est le moment de renforcer ton fer")
        XCTAssertEqual(midi0?.corps, "Hier, il t'en a manqué 42 %. Lentilles, boudin noir ou épinards ce midi ? Scanne ton assiette.")

        // Demain, « hier » n'est pas encore écrit : pas de chiffre, et on alterne.
        let midi1 = rappels.first { $0.id == "\(RappelsPersonnalises.prefixe)midi.1" }
        XCTAssertEqual(midi1?.titre, "C'est le moment de renforcer ta vitamine C")
        XCTAssertFalse(midi1?.corps.contains("Hier") ?? true)

        // Le soir reprend le conseil du bilan quand il existe.
        let soir0 = rappels.first { $0.id == "\(RappelsPersonnalises.prefixe)soir.0" }
        XCTAssertEqual(soir0?.titre, "Ce soir, pense à ta vitamine C")
        XCTAssertEqual(soir0?.corps, "Un kiwi au dessert aide ton fer à passer.")
    }

    func testRappels_sansBilan_restentUtilesEtGeneriques() {
        let rappels = RappelsPersonnalises.planifier(
            cibles: [], couvertureHier: [:], creneauxDejaNotes: [], maintenant: date(heure: 9)
        )
        XCTAssertEqual(rappels.first { $0.id.hasSuffix("midi.0") }?.titre, "Photographie ton repas")
        XCTAssertEqual(rappels.last?.titre, "Ton suivi t'attend")
    }

    func testRappels_vocabulaire_jamaisDeMotProscrit() {
        let rappels = RappelsPersonnalises.planifier(
            cibles: cibles, couvertureHier: ["iron": 10, "vitC": 5], creneauxDejaNotes: [], maintenant: date(heure: 6)
        )
        let proscrits = ["carence", "diagnostic", "patient", "maladie"]
        for rappel in rappels {
            let texte = (rappel.titre + " " + rappel.corps).lowercased()
            for mot in proscrits {
                XCTAssertFalse(texte.contains(mot), "« \(mot) » dans \(rappel.id)")
            }
        }
    }
}
