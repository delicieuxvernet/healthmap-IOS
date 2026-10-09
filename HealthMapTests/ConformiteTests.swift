import XCTest
@testable import HealthMap

// MARK: - Audit de conformité du 9 octobre 2026
//
// Ce que l'app promet à l'écran doit rester vrai : l'essai gratuit seulement
// à qui y a droit, l'âge minimum, des relances plafonnées, une fréquence de
// rappels annoncée qui ne ment pas, et aucun bienfait prêté à un complément.

@MainActor
final class ConformiteTests: XCTestCase {

    // MARK: Essai gratuit (App Store 3.1.2)

    func testSansReponseDApple_aucunEssaiNEstPromis() {
        let droit = DroitEssaiGratuit()
        XCTAssertFalse(droit.autorise("healthmap_annual"))
        droit.remplacer(par: ["healthmap_annual": true, "healthmap_weekly": false])
        XCTAssertTrue(droit.autorise("healthmap_annual"))
        XCTAssertFalse(droit.autorise("healthmap_weekly"))
        XCTAssertFalse(droit.autorise("inconnu"))
    }

    func testSansRemise_pasDEssaiMemeAvecLeDroit() {
        XCTAssertNil(SubscriptionService.essaiGratuit(de: nil, autorise: true))
        XCTAssertNil(SubscriptionService.essaiGratuit(de: nil, autorise: false))
    }

    // MARK: Âge minimum

    func testSeizeAnsMinimum() {
        XCTAssertEqual(AgeMinimum.ans, 16)
        XCTAssertFalse(AgeMinimum.estAtteint(15))
        XCTAssertTrue(AgeMinimum.estAtteint(16))
        // La molette laisse dire un âge plus jeune, pour pouvoir l'expliquer.
        XCTAssertTrue(AgeMinimum.plageMolette.contains(15))
    }

    func testSousSeizeAns_lAgeNEstPasGarde() {
        let vm = QuestionnaireViewModel()
        vm.choisirAge(30)
        XCTAssertEqual(vm.profile.age, "30")
        vm.choisirAge(14)
        XCTAssertEqual(vm.profile.age, "")
        XCTAssertTrue(vm.sousAgeMinimum)
        vm.choisirAge(17)
        XCTAssertEqual(vm.profile.age, "17")
        XCTAssertFalse(vm.sousAgeMinimum)
    }

    // MARK: Relances

    func testLeComparatif_auPlusUneFoisParSemaine() {
        let maintenant = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(RythmeComparatif.peutMontrer(derniere: nil, maintenant: maintenant))
        XCTAssertFalse(RythmeComparatif.peutMontrer(derniere: maintenant.addingTimeInterval(-3 * 86_400), maintenant: maintenant))
        XCTAssertTrue(RythmeComparatif.peutMontrer(derniere: maintenant.addingTimeInterval(-7 * 86_400), maintenant: maintenant))
    }

    func testLaCarteDOffre_estPlafonnee() {
        let maintenant = Date(timeIntervalSince1970: 1_800_000_000)
        let premier = maintenant.addingTimeInterval(-120 * 86_400)
        let derniere = maintenant.addingTimeInterval(-30 * 86_400)
        XCTAssertTrue(RythmeOffre.peutProposer(premierPassage: premier, derniere: derniere,
                                               vues: RythmeOffre.vuesMax - 1, maintenant: maintenant))
        XCTAssertFalse(RythmeOffre.peutProposer(premierPassage: premier, derniere: derniere,
                                                vues: RythmeOffre.vuesMax, maintenant: maintenant))
    }

    func testNePlusMeProposer_arreteLaCarte() async {
        let defaults = UserDefaults(suiteName: "ConformiteTests.offre")!
        defaults.removePersistentDomain(forName: "ConformiteTests.offre")
        let centre = OffreCentre(defaults: defaults)
        centre.nePlusProposer()
        await centre.proposer(maintenant: Date().addingTimeInterval(365 * 86_400))
        XCTAssertNil(centre.courante)
    }

    // MARK: Fréquence des rappels annoncée

    func testLaFrequenceAnnoncee_nEstJamaisDepassee() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        // Un jeudi à 7 h : toute la journée est encore à venir.
        let maintenant = cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 7))!
        let fer = CibleNutritionnelle(id: "iron", nom: "Fer", aliments: ["Lentilles"], conseil: nil)
        // Le contexte qui sonne le plus : un repas déjà noté chaque jour, ni
        // encas ni dîner, assez de repas dans la semaine pour le dimanche.
        var contexte = ContexteRappels(cibles: [fer])
        contexte.journalConnu = true
        contexte.repasSemaine = 9
        contexte.joursNotesSemaine = 4
        for jour in 0..<RappelsPersonnalises.horizonJours {
            contexte.jours[jour] = JourNote(repas: 1, creneaux: [.breakfast], couverture: [:])
        }

        let rappels = RappelsPersonnalises.planifier(contexte: contexte, maintenant: maintenant, calendar: cal)
            .filter { $0.type != "retour" && $0.type != "sang" }
        let parJour = Dictionary(grouping: rappels) { cal.startOfDay(for: $0.date) }
        XCTAssertFalse(parJour.isEmpty)

        for (jour, duJour) in parJour {
            let decalage = cal.dateComponents([.day], from: cal.startOfDay(for: maintenant), to: jour).day ?? 0
            let plafond = decalage < RappelsPersonnalises.joursPleins
                ? RappelsPersonnalises.maxParJourPlein
                : RappelsPersonnalises.maxParJourAllege
            XCTAssertLessThanOrEqual(duJour.count, plafond, "jour +\(decalage) : \(duJour.map(\.type))")
        }
        XCTAssertTrue(RappelsPersonnalises.frequenceAnnoncee.contains("\(RappelsPersonnalises.maxParJourPlein) rappels"))
        XCTAssertTrue(InvitationNotificationsContenu.explication(cible: nil)
            .contains(RappelsPersonnalises.frequenceAnnoncee))
    }

    // MARK: Compléments : composition et forme, aucun bienfait

    func testLePourquoiDUnComplement_neVanteAucunEffet() {
        let motsInterdits = [
            "aide", "aider", "favorise", "contribue", "santé", "immunit", "os\\b", "cerveau",
            "cognit", "transit", "absorption", "biodisponib", "toléran", "intestin",
            "fatigue", "énergie", "inflamm", "contamination", "sommeil", "stress",
        ]
        for produit in SupplementEngine.catalog {
            let texte = produit.whyBrand.lowercased()
            for mot in motsInterdits {
                XCTAssertNil(texte.range(of: "\\b\(mot)", options: .regularExpression),
                             "\(produit.id) : « \(produit.whyBrand) » contient « \(mot) »")
            }
        }
    }
}
