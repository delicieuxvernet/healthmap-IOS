import XCTest
import SwiftUI
import UIKit
@testable import HealthMap

/// Les widgets vivent hors de l'app : tout ce qu'ils affichent passe par la
/// boîte commune. Ces tests tiennent ses règles, sans trousseau ni extension :
///
///   • un instantané de la veille ne ment pas sur aujourd'hui ;
///   • ce qu'on touche sur un widget se voit tout de suite, et l'app retire de
///     l'attente exactement ce qu'elle a appliqué ;
///   • le conseil du jour change à minuit, et sa coche avec lui ;
///   • un lien de widget ouvre le bon écran, et rien d'autre ne passe pour un
///     lien de widget ;
///   • l'activité en direct ne revient pas sur l'écran verrouillé d'une
///     personne qui vient de l'écarter, et tient dans ce qu'iOS lui accorde.
///
/// Ils rendent enfin chaque widget en image : la seule preuve visuelle sans
/// appareil.
final class WidgetsPartageTests: XCTestCase {

    private final class StockageMemoire: StockagePartage {
        var contenu: [String: Data] = [:]
        func lire(_ cle: String) -> Data? { contenu[cle] }
        func ecrire(_ donnees: Data?, cle: String) { contenu[cle] = donnees }
    }

    /// Grégorien en UTC : les heures des tests ne dépendent pas du fuseau du
    /// runner.
    private static let utc: Calendar = {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendrier
    }()

    override func setUp() {
        super.setUp()
        BoiteCommune.stockage = StockageMemoire()
    }

    override func tearDown() {
        BoiteCommune.stockage = StockageTrousseau()
        super.tearDown()
    }

    private func journee(jour: String) -> InstantaneJour {
        InstantaneJour(
            jour: jour, connecte: true, bilanFait: true, kcalObjectif: 2100,
            kcalParCreneau: ["breakfast": 420, "lunch": 820], serie: 4,
            eau: InstantaneJour.Eau(verres: 3, objectif: 8, centilitres: 25),
            rituel: [
                .init(id: "iron", nom: "Fer", moment: "matin", fait: true),
                .init(id: "vitD", nom: "Vitamine D", moment: "matin", fait: false),
                .init(id: "magnesium", nom: "Magnésium", moment: "soir", fait: false),
            ]
        )
    }

    private func conseil(_ id: String, points: Int = 5) -> ConseilW {
        ConseilW(id: id, texte: "Le geste \(id), en entier.", court: "Le geste \(id)",
                 apport: "vitD", apportNom: "Vitamine D", apportCourt: "Vit. D", points: points)
    }

    // MARK: - Le jour qui change

    func testUnInstantaneDeLaVeilleRepartDeZero() {
        let hier = journee(jour: "2026-10-01")
        let affiche = hier.affiche(pour: "2026-10-02", attente: nil)

        XCTAssertEqual(affiche.jour, "2026-10-02")
        XCTAssertEqual(affiche.kcalConsommees, 0, "Les calories d'hier ne sont pas celles d'aujourd'hui")
        XCTAssertEqual(affiche.eau, InstantaneJour.Eau(verres: 0, objectif: 8, centilitres: 25),
                       "L'eau repart de zéro, l'objectif reste")
        XCTAssertTrue(affiche.rituel.allSatisfy { !$0.fait }, "Le rituel se décoche chaque matin")
        XCTAssertEqual(affiche.rituel.map(\.id), ["iron", "vitD", "magnesium"], "Sa composition ne change pas à minuit")
        XCTAssertEqual(affiche.kcalObjectif, 2100)
        XCTAssertEqual(affiche.serie, 4)
    }

    func testLeMemeJourResteTelQuel() {
        let aujourdhui = journee(jour: "2026-10-01")
        XCTAssertEqual(aujourdhui.affiche(pour: "2026-10-01", attente: nil), aujourdhui)
    }

    // MARK: - Ce qu'on a touché sur un widget

    func testLAttenteSAjouteALInstantane() {
        var attente = ActionsEnAttente(jour: "2026-10-01")
        attente.verres = 2
        attente.prisesBasculees = ["vitD", "iron"]

        let affiche = journee(jour: "2026-10-01").affiche(pour: "2026-10-01", attente: attente)

        XCTAssertEqual(affiche.eau?.verres, 5)
        XCTAssertEqual(affiche.rituel.first { $0.id == "vitD" }?.fait, true, "Cochée depuis le widget")
        XCTAssertEqual(affiche.rituel.first { $0.id == "iron" }?.fait, false, "Décochée depuis le widget")
    }

    func testUneAttenteDUnAutreJourEstIgnoree() {
        var attente = ActionsEnAttente(jour: "2026-09-30")
        attente.verres = 4
        let affiche = journee(jour: "2026-10-01").affiche(pour: "2026-10-01", attente: attente)
        XCTAssertEqual(affiche.eau?.verres, 3)
    }

    func testSansSuiviDEauLesVerresNeCreentPasDeCompteur() {
        var sansEau = journee(jour: "2026-10-01")
        sansEau.eau = nil
        var attente = ActionsEnAttente(jour: "2026-10-01")
        attente.verres = 1
        XCTAssertNil(sansEau.affiche(pour: "2026-10-01", attente: attente).eau)
    }

    func testLAppRetireCeQuElleAAppliqueEtRienDePlus() {
        // L'app a lu une attente, l'a appliquée ; entre-temps un doigt a ajouté
        // un verre et coché une prise sur le widget.
        var lue = ActionsEnAttente(jour: "2026-10-01")
        lue.verres = 2
        lue.prisesBasculees = ["vitD"]

        var courante = lue
        courante.verres = 3
        courante.prisesBasculees = ["vitD", "magnesium"]

        let reste = courante.moins(lue)
        XCTAssertEqual(reste.verres, 1)
        XCTAssertEqual(reste.prisesBasculees, ["magnesium"])
        XCTAssertFalse(reste.estVide)
        XCTAssertTrue(lue.moins(lue).estVide)
    }

    func testUneAttenteDeLaVersionPrecedenteSeLitEncore() throws {
        // Écrite avant le conseil du jour : pas de `conseilsBascules`.
        let json = #"{"jour":"2026-10-01","verres":2,"prisesBasculees":["vitD"]}"#
        let attente = try JSONDecoder().decode(ActionsEnAttente.self, from: Data(json.utf8))
        XCTAssertEqual(attente.verres, 2)
        XCTAssertEqual(attente.prisesBasculees, ["vitD"])
        XCTAssertNil(attente.conseilsBascules)
        XCTAssertFalse(attente.estVide)
    }

    // MARK: - Les gestes, de bout en bout (stockage en mémoire)

    func testUnVerreAjouteSeVoitToutDeSuite() {
        BoiteCommune.ecrireInstantane(journee(jour: BoiteCommune.cleDuJour()))
        BoiteCommune.ajouterVerre()
        BoiteCommune.ajouterVerre()
        XCTAssertEqual(BoiteCommune.etatAffiche()?.eau?.verres, 5)
        XCTAssertEqual(BoiteCommune.lireInstantane()?.eau?.verres, 3,
                       "Le widget n'écrit jamais l'instantané : il appartient à l'app")
    }

    func testCocherUnMomentCocheCeQuiResteEtLeRetoucherDecocheTout() {
        BoiteCommune.ecrireInstantane(journee(jour: BoiteCommune.cleDuJour()))

        // Matin : le fer est déjà pris, il reste la vitamine D.
        BoiteCommune.basculerMoment(.matin)
        var matin = BoiteCommune.etatAffiche()?.prises(du: .matin) ?? []
        XCTAssertEqual(matin.count, 2)
        XCTAssertTrue(matin.allSatisfy(\.fait), "Le fer déjà pris ne doit pas se décocher")

        // Le même geste sur un moment complet le décoche en entier.
        BoiteCommune.basculerMoment(.matin)
        matin = BoiteCommune.etatAffiche()?.prises(du: .matin) ?? []
        XCTAssertTrue(matin.allSatisfy { !$0.fait })
    }

    func testUnMomentSansPriseNeFaitRien() {
        BoiteCommune.ecrireInstantane(journee(jour: BoiteCommune.cleDuJour()))
        BoiteCommune.basculerMoment(.midi)
        XCTAssertNil(BoiteCommune.lireAttente())
    }

    func testLeBoutonUniqueAvanceDeMomentEnMoment() {
        BoiteCommune.ecrireInstantane(journee(jour: BoiteCommune.cleDuJour()))
        XCTAssertEqual(BoiteCommune.etatAffiche()?.prochainMoment, .matin)

        BoiteCommune.cocherProchainMoment()
        XCTAssertEqual(BoiteCommune.etatAffiche()?.prochainMoment, .soir)

        BoiteCommune.cocherProchainMoment()
        XCTAssertNil(BoiteCommune.etatAffiche()?.prochainMoment, "Rituel complet")
        XCTAssertEqual(BoiteCommune.etatAffiche()?.prisesFaites, 3)

        // Complet : le bouton ne décoche rien.
        BoiteCommune.cocherProchainMoment()
        XCTAssertEqual(BoiteCommune.etatAffiche()?.prisesFaites, 3)
    }

    func testOnNeNotePasAuDelaDeLObjectif() {
        // Comme le Journal : huit verres, pas neuf.
        var pleine = journee(jour: BoiteCommune.cleDuJour())
        pleine.eau = InstantaneJour.Eau(verres: 7, objectif: 8, centilitres: 25)
        BoiteCommune.ecrireInstantane(pleine)

        BoiteCommune.ajouterVerre()
        BoiteCommune.ajouterVerre()
        BoiteCommune.ajouterVerre()

        XCTAssertEqual(BoiteCommune.etatAffiche()?.eau?.verres, 8)
        XCTAssertEqual(BoiteCommune.lireAttente()?.verres, 1, "Les touchers en trop ne s'empilent pas dans l'attente")
        XCTAssertEqual(BoiteCommune.etatAffiche()?.eau?.atteint, true)
    }

    func testLesLitresSEcriventCommeDansLeJournal() {
        XCTAssertEqual(FormatW.litres(centilitres: 75), "0,75")
        XCTAssertEqual(FormatW.litres(centilitres: 50), "0,5")
        XCTAssertEqual(FormatW.litres(centilitres: 200), "2")
        XCTAssertEqual(FormatW.litres(centilitres: 125), "1,25")
        XCTAssertEqual(FormatW.litres(centilitres: 0), "0")

        let eau = InstantaneJour.Eau(verres: 3, objectif: 8, centilitres: 25)
        XCTAssertEqual(FormatW.litresBus(eau), "0,75")
        XCTAssertEqual(FormatW.litresObjectif(eau), "2")
    }

    func testLaDeconnexionVideLaBoite() {
        BoiteCommune.ecrireInstantane(journee(jour: BoiteCommune.cleDuJour()))
        BoiteCommune.ajouterVerre()
        BoiteCommune.toutEffacer()
        XCTAssertNil(BoiteCommune.etatAffiche())
        XCTAssertNil(BoiteCommune.lireAttente())
    }

    // MARK: - Le conseil du jour

    func testLeRangDuJourCompteLesJoursDepuis2001() {
        XCTAssertEqual(BoiteCommune.rangDuJour("2001-01-01"), 0)
        XCTAssertEqual(BoiteCommune.rangDuJour("2001-01-02"), 1)
        XCTAssertEqual(BoiteCommune.rangDuJour("2001-02-01"), 31)
        XCTAssertEqual(BoiteCommune.rangDuJour("2026-10-03"), 9406)
        // Le 29 février compte : le conseil ne saute ni ne double un jour.
        XCTAssertEqual(BoiteCommune.rangDuJour("2028-02-29") - BoiteCommune.rangDuJour("2028-02-28"), 1)
        XCTAssertEqual(BoiteCommune.rangDuJour("2028-03-01") - BoiteCommune.rangDuJour("2028-02-29"), 1)
        // Une clé illisible ou antérieure donne 0 : jamais de rang négatif
        // sous le modulo du conseil.
        XCTAssertEqual(BoiteCommune.rangDuJour("n'importe quoi"), 0)
        XCTAssertEqual(BoiteCommune.rangDuJour("2026-10"), 0)
        XCTAssertEqual(BoiteCommune.rangDuJour("2000-12-31"), 0)
    }

    func testLeConseilChangeChaqueJour() {
        var etat = journee(jour: "2026-10-01")
        etat.conseils = [conseil("a"), conseil("b"), conseil("c")]

        // Rangs 9404, 9405, 9406 : modulo 3, on tourne sur les trois gestes.
        let suite = ["2026-10-01", "2026-10-02", "2026-10-03"].map {
            etat.affiche(pour: $0, attente: nil).conseilDuJour?.id
        }
        XCTAssertEqual(suite, ["c", "a", "b"], "Demain, un autre conseil")

        etat.conseils = [conseil("seul")]
        XCTAssertEqual(etat.affiche(pour: "2026-10-02", attente: nil).conseilDuJour?.id, "seul")

        etat.conseils = []
        XCTAssertNil(etat.conseilDuJour)
        etat.conseils = nil
        XCTAssertNil(etat.conseilDuJour)
        XCTAssertFalse(etat.conseilDuJourFait)
    }

    func testLeConseilCocheSeDecocheAMinuit() {
        var hier = journee(jour: "2026-10-01")
        hier.apports = InstantaneJour.exemple.apports
        hier.conseils = [conseil("a")]
        hier.conseilFait = "a"
        XCTAssertTrue(hier.conseilDuJourFait)
        XCTAssertTrue(hier.affiche(pour: "2026-10-01", attente: nil).conseilDuJourFait, "Le même jour, la coche reste")

        let aujourdhui = hier.affiche(pour: "2026-10-02", attente: nil)
        XCTAssertNil(aujourdhui.conseilFait)
        XCTAssertFalse(aujourdhui.conseilDuJourFait)
        XCTAssertEqual(aujourdhui.conseils, hier.conseils, "Les candidats, eux, restent")
        XCTAssertEqual(aujourdhui.apports, hier.apports, "Les apports sont ceux du registre : minuit n'y change rien")
    }

    func testLAttenteDesConseilsGardeLOrdreEtLesDoublons() {
        var etat = journee(jour: "2026-10-01")
        etat.conseils = [conseil("a")]

        var attente = ActionsEnAttente(jour: "2026-10-01")
        XCTAssertTrue(attente.estVide)
        attente.conseilsBascules = []
        XCTAssertTrue(attente.estVide, "Une liste vide n'est pas un geste")

        attente.conseilsBascules = ["a"]
        XCTAssertFalse(attente.estVide)
        XCTAssertEqual(etat.affiche(pour: "2026-10-01", attente: attente).conseilFait, "a")

        attente.conseilsBascules = ["a", "a"]
        XCTAssertNil(etat.affiche(pour: "2026-10-01", attente: attente).conseilFait, "Coché puis décoché")

        attente.conseilsBascules = ["a", "a", "a"]
        XCTAssertEqual(etat.affiche(pour: "2026-10-01", attente: attente).conseilFait, "a", "Chaque toucher compte")

        // L'app a lu et appliqué le premier toucher ; deux autres sont arrivés
        // pendant la synchro : ils restent.
        var lue = ActionsEnAttente(jour: "2026-10-01")
        lue.conseilsBascules = ["a"]
        let reste = attente.moins(lue)
        XCTAssertEqual(reste.conseilsBascules, ["a", "a"])
        XCTAssertFalse(reste.estVide)

        let toutApplique = attente.moins(attente)
        XCTAssertNil(toutApplique.conseilsBascules, "Plus rien à appliquer : la clé disparaît")
        XCTAssertTrue(toutApplique.estVide)
    }

    func testCestFaitSeVoitToutDeSuiteEtSeDefait() {
        var etat = journee(jour: BoiteCommune.cleDuJour())
        etat.conseils = [conseil("a")]
        BoiteCommune.ecrireInstantane(etat)

        BoiteCommune.basculerConseil()
        XCTAssertEqual(BoiteCommune.etatAffiche()?.conseilDuJourFait, true)
        XCTAssertEqual(BoiteCommune.lireAttente()?.conseilsBascules, ["a"])
        XCTAssertNil(BoiteCommune.lireInstantane()?.conseilFait,
                     "Le widget n'écrit jamais l'instantané : il appartient à l'app")

        BoiteCommune.basculerConseil()
        XCTAssertEqual(BoiteCommune.etatAffiche()?.conseilDuJourFait, false, "Le retoucher le décoche")
        XCTAssertEqual(BoiteCommune.lireAttente()?.conseilsBascules, ["a", "a"])
    }

    func testSansConseilCestFaitNeFaitRien() {
        BoiteCommune.ecrireInstantane(journee(jour: BoiteCommune.cleDuJour()))
        BoiteCommune.basculerConseil()
        XCTAssertNil(BoiteCommune.lireAttente())
    }

    func testLeBadgeNAnnonceQueDesPointsReels() {
        XCTAssertEqual(FormatW.badgePoints(conseil("a", points: 5)), "+5 Vit. D")
        XCTAssertNil(FormatW.badgePoints(conseil("a", points: 0)), "Aucun chiffre inventé")
    }

    // MARK: - Les liens

    func testChaqueLienFaitLAllerRetour() {
        let liens: [LienKiwio] = [.journal, .dicter, .photo, .rechercher, .complements,
                                  .repas("breakfast"), .repas("lunch"), .repas("dinner"), .repas("snack"),
                                  .apport("vitD"), .apport("fiber")]
        for lien in liens {
            XCTAssertEqual(LienKiwio(url: lien.url), lien, "\(lien.url)")
            XCTAssertEqual(LienKiwio(code: lien.code), lien)
        }
        XCTAssertEqual(LienKiwio.repas("lunch").url.absoluteString, "healthmap://widget/repas/lunch")
    }

    func testCeQuiNEstPasUnLienDeWidgetNEnEstPasUn() {
        // Le retour de connexion Google emprunte le même schéma.
        XCTAssertNil(LienKiwio(url: URL(string: "healthmap://auth/callback?code=abc")!))
        XCTAssertNil(LienKiwio(url: URL(string: "https://healthmap.fr/widget/dicter")!))
        XCTAssertNil(LienKiwio(url: URL(string: "healthmap://widget/repas/brunch")!), "Créneau inconnu")
        XCTAssertNil(LienKiwio(url: URL(string: "healthmap://widget/inconnu")!))
    }

    func testLaFicheDUnApportSOuvreEtRienDAutre() {
        XCTAssertEqual(LienKiwio.apport("vitD").url.absoluteString, "healthmap://widget/apport/vitD")
        for id in LienKiwio.apportsConnus {
            XCTAssertEqual(LienKiwio(url: LienKiwio.apport(id).url), .apport(id), id)
        }
        XCTAssertNil(LienKiwio(url: URL(string: "healthmap://widget/apport/vitamineZ")!), "Apport inconnu")
        XCTAssertNil(LienKiwio(url: URL(string: "healthmap://widget/apport")!), "Sans apport")
        XCTAssertNil(LienKiwio(url: URL(string: "healthmap://widget/apport/vitD/plus")!))
        XCTAssertNil(LienKiwio(code: "apport/"))
    }

    /// L'extension ne voit pas `NutrientID` : elle en garde un miroir. Un
    /// apport ajouté au registre sans le miroir ferait un lien mort.
    func testLesApportsDesLiensSontCeuxDuRegistre() {
        XCTAssertEqual(LienKiwio.apportsConnus, Set(NutrientID.allCases.map(\.rawValue)))
    }

    func testLesCreneauxDuWidgetSontCeuxDuJournal() {
        XCTAssertEqual(CreneauWidget.allCases.map(\.rawValue),
                       MealJournalService.MealSlot.ordreJournal.map(\.rawValue))
        for creneau in CreneauWidget.allCases {
            let slot = MealJournalService.MealSlot(rawValue: creneau.rawValue)
            XCTAssertEqual(creneau.libelle, slot?.label)
            XCTAssertEqual(creneau.symbole, slot?.symboleJournal)
        }
    }

    // MARK: - Le repas à venir

    func testLeRepasDeLHeureEstCeluiDuJournal() throws {
        for heure in 0...23 {
            let date = try XCTUnwrap(Self.utc.date(from: DateComponents(year: 2026, month: 10, day: 3,
                                                                        hour: heure, minute: 30)))
            XCTAssertEqual(CreneauWidget.deLHeure(heure).rawValue,
                           MealJournalService.MealSlot.from(date: date, calendar: Self.utc).rawValue,
                           "\(heure) h")
        }
    }

    /// La frise des widgets se redessine aux heures de bascule : il en faut
    /// une à chaque changement de repas, et aucune de trop.
    func testLaFriseSeRedessineQuandLeRepasChange() {
        let changements = (1...23).filter { CreneauWidget.deLHeure($0) != CreneauWidget.deLHeure($0 - 1) }
        XCTAssertEqual(changements, CreneauWidget.heuresDeBascule)
        XCTAssertEqual(CreneauWidget.deLHeure(0), CreneauWidget.deLHeure(23), "Minuit ne change pas de repas")
    }

    func testLeRepasAVenirSuitLHeureEtCeQuiEstNote() {
        let calendrier = Self.utc
        func a(_ heure: Int) -> Date {
            calendrier.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: heure, minute: 15))!
        }

        var etat = InstantaneJour.vide(jour: "2026-10-03", connecte: true)
        XCTAssertEqual(etat.repasAVenir(a(8), calendrier: calendrier), .breakfast)
        XCTAssertEqual(etat.repasAVenir(a(12), calendrier: calendrier), .lunch)
        XCTAssertEqual(etat.repasAVenir(a(16), calendrier: calendrier), .snack, "L'encas, pendant sa plage")
        XCTAssertEqual(etat.repasAVenir(a(20), calendrier: calendrier), .dinner)
        XCTAssertEqual(etat.repasAVenir(a(2), calendrier: calendrier), .dinner, "La nuit est du côté du soir")

        etat.kcalParCreneau = ["breakfast": 400]
        XCTAssertEqual(etat.repasAVenir(a(8), calendrier: calendrier), .lunch, "Petit-déj noté : on propose le midi")
        etat.kcalParCreneau["lunch"] = 700
        XCTAssertEqual(etat.repasAVenir(a(9), calendrier: calendrier), .dinner)
        XCTAssertEqual(etat.repasAVenir(a(13), calendrier: calendrier), .dinner, "Midi noté : le soir")
        etat.kcalParCreneau["snack"] = 200
        XCTAssertEqual(etat.repasAVenir(a(16), calendrier: calendrier), .dinner, "Encas noté : le soir")
        etat.kcalParCreneau["dinner"] = 800
        XCTAssertEqual(etat.repasAVenir(a(21), calendrier: calendrier), .dinner, "Le soir reste le soir")
        XCTAssertEqual(etat.repasAVenir(a(21), calendrier: calendrier).question, "Ton soir ?")
    }

    // MARK: - Le rituel en avant

    func testLeMomentEnAvantEstLeProchainACocherPuisLeDernier() {
        var etat = journee(jour: "2026-10-01")
        XCTAssertEqual(etat.momentEnAvant, .matin, "Le fer est pris, la vitamine D reste")
        etat.rituel[1].fait = true
        XCTAssertEqual(etat.momentEnAvant, .soir)
        etat.rituel[2].fait = true
        XCTAssertNil(etat.prochainMoment)
        XCTAssertEqual(etat.momentEnAvant, .soir, "Rituel complet : le dernier moment reste, pour pouvoir le décocher")
        etat.rituel = []
        XCTAssertNil(etat.momentEnAvant)
    }

    // MARK: - Les calories par repas

    func testLesCaloriesSontCellesDuJourRangeesParCreneau() {
        let calendrier = Calendar(identifier: .gregorian)
        let jour = calendrier.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
        let veille = calendrier.date(byAdding: .day, value: -1, to: jour)!
        func repas(_ id: String, _ date: Date, _ slot: MealJournalService.MealSlot, _ kcal: Int)
            -> MealJournalService.MealRecord {
            MealJournalService.MealRecord(id: id, consumedAt: date, slot: slot, items: [],
                                          macros: .init(calories: kcal))
        }
        let total = SynchroWidgets.kcalParCreneau(
            [repas("a", jour, .breakfast, 300), repas("b", jour, .breakfast, 120),
             repas("c", jour, .lunch, 820), repas("d", veille, .dinner, 900)],
            jour: jour, calendrier: calendrier
        )
        XCTAssertEqual(total, ["breakfast": 420, "lunch": 820])
    }

    // MARK: - L'activité en direct

    func testLActiviteNeRevientPasAvantHuitHeures() {
        let calendrier = Calendar(identifier: .gregorian)
        let matin = calendrier.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 8))!
        func plus(_ heures: Double) -> Date { matin.addingTimeInterval(heures * 3600) }

        XCTAssertTrue(ActiviteJournee.doitDemarrer(activitePresente: false, dernierDemarrage: nil,
                                                   maintenant: matin, calendrier: calendrier),
                      "Jamais démarrée : on la lance")
        XCTAssertFalse(ActiviteJournee.doitDemarrer(activitePresente: true, dernierDemarrage: matin,
                                                    maintenant: plus(1), calendrier: calendrier),
                       "Une carte est déjà là")
        XCTAssertFalse(ActiviteJournee.doitDemarrer(activitePresente: false, dernierDemarrage: matin,
                                                    maintenant: plus(2), calendrier: calendrier),
                       "Écartée il y a deux heures : on ne la ramène pas")
        XCTAssertTrue(ActiviteJournee.doitDemarrer(activitePresente: false, dernierDemarrage: matin,
                                                   maintenant: plus(9), calendrier: calendrier),
                      "iOS l'a arrêtée au bout de huit heures : elle peut revenir pour le dîner")
        XCTAssertTrue(ActiviteJournee.doitDemarrer(activitePresente: false, dernierDemarrage: matin,
                                                   maintenant: plus(24), calendrier: calendrier),
                      "Nouveau jour, nouvelle carte")
    }

    func testPasDeCarteSansJourneeAMontrer() {
        var etat = InstantaneJour.vide(jour: "2026-10-01", connecte: true)
        XCTAssertFalse(ActiviteJournee.aMontrer(etat), "Ni bilan ni repas : rien à mettre sur l'écran verrouillé")
        etat.kcalParCreneau = ["lunch": 500]
        XCTAssertTrue(ActiviteJournee.aMontrer(etat))
        etat.connecte = false
        XCTAssertFalse(ActiviteJournee.aMontrer(etat))
    }

    /// ActivityKit refuse une activité dont attributs + état dépassent 4 Ko :
    /// les apports et les conseils restent dans le trousseau, pas dans la carte.
    func testLActiviteNEmporteNiApportsNiConseils() throws {
        let complet = InstantaneJour.exemple
        let leger = complet.pourActivite
        XCTAssertNil(leger.apports)
        XCTAssertNil(leger.conseils)

        var attendu = complet
        attendu.apports = nil
        attendu.conseils = nil
        XCTAssertEqual(leger, attendu, "Tout le reste passe tel quel : calories, eau, rituel, série, coche")

        let encodeur = JSONEncoder()
        let etat = try encodeur.encode(JourneeAttributes.ContentState(etat: leger))
        let attributs = try encodeur.encode(JourneeAttributes(jour: complet.jour))
        let lourd = try encodeur.encode(JourneeAttributes.ContentState(etat: complet))
        XCTAssertLessThan(etat.count + attributs.count, 4096, "\(etat.count + attributs.count) octets")
        XCTAssertLessThan(etat.count, lourd.count)
    }

    /// iOS coupe une activité plus haute que 160 pt sur l'écran verrouillé :
    /// la carte, marges comprises (16 sur les côtés, 14 en haut et en bas),
    /// doit y tenir dans tous ses états.
    @MainActor
    func testLaCarteDeLActiviteTientSurLEcranVerrouille() throws {
        let etats: [(String, InstantaneJour)] = [
            ("maquette", PlancheEtats.maquette),
            ("tout fait", PlancheEtats.toutFait),
            ("au-dessus du budget", PlancheEtats.auDessus),
            ("sans eau ni rituel", PlancheEtats.sansEauNiRituel),
            ("sans objectif", PlancheEtats.sansObjectif),
        ]
        for (nom, etat) in etats {
            let carte = VueActiviteJournee(etat: etat, maintenant: PlancheEtats.soir)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(width: 364)
                .fixedSize(horizontal: false, vertical: true)
            let rendu = ImageRenderer(content: carte)
            let image = try XCTUnwrap(rendu.uiImage, "La carte « \(nom) » ne se rend pas")
            XCTAssertLessThanOrEqual(image.size.height, 160, "Carte « \(nom) » : \(image.size.height) pt de haut")
        }
    }

    // MARK: - Les instantanés d'avant

    /// Un instantané écrit par la version précédente (trousseau, activité en
    /// cours) doit se lire après la mise à jour : sinon tous les widgets
    /// tombent sur l'invitation jusqu'à la prochaine ouverture de l'app.
    func testUnInstantaneDeLaVersionPrecedenteSeLitEncore() throws {
        let json = #"""
        {"jour":"2026-10-01","connecte":true,"bilanFait":true,"kcalObjectif":2100,
         "kcalParCreneau":{"breakfast":420,"lunch":820},"serie":4,
         "eau":{"verres":3,"objectif":8,"centilitres":25},
         "rituel":[{"id":"iron","nom":"Fer","moment":"matin","fait":true}]}
        """#
        let etat = try JSONDecoder().decode(InstantaneJour.self, from: Data(json.utf8))
        XCTAssertEqual(etat.kcalConsommees, 1240)
        XCTAssertEqual(etat.eau?.verres, 3)
        XCTAssertNil(etat.apports)
        XCTAssertNil(etat.conseils)
        XCTAssertNil(etat.conseilFait)
        XCTAssertNil(etat.premium)
        XCTAssertNil(etat.conseilDuJour)
        XCTAssertFalse(etat.conseilDuJourFait)

        let relu = try JSONDecoder().decode(InstantaneJour.self, from: JSONEncoder().encode(InstantaneJour.exemple))
        XCTAssertEqual(relu, InstantaneJour.exemple, "Le nouvel instantané fait l'aller-retour, apports et conseils compris")
    }

    // MARK: - Les chiffres

    func testLesMilliersPrennentUneEspaceFine() {
        XCTAssertEqual(FormatW.entier(860), "860")
        XCTAssertEqual(FormatW.entier(1240), "1\u{202F}240")
        XCTAssertEqual(FormatW.entier(-12500), "-12\u{202F}500")
        XCTAssertEqual(FormatW.entier(0), "0")
    }

    func testLaLigneDeCaloriesDitCeQuilReste() {
        var etat = journee(jour: "2026-10-01")
        XCTAssertEqual(FormatW.ligneCalories(etat).nombre, "860")
        XCTAssertEqual(FormatW.ligneCalories(etat).legende, "kcal restantes")

        etat.kcalParCreneau["dinner"] = 1000
        XCTAssertEqual(FormatW.ligneCalories(etat).nombre, "140")
        XCTAssertEqual(FormatW.ligneCalories(etat).legende, "kcal au-dessus")

        etat.kcalObjectif = nil
        XCTAssertEqual(FormatW.ligneCalories(etat).legende, "kcal aujourd'hui",
                       "Sans objectif : le consommé seul, jamais une cible inventée")
        XCTAssertEqual(FormatW.fractionCalories(etat), 0)
    }

    func testLAnneauDuJourEstTronqueCommeLaMaquette() {
        // 2 027 kcal sur 2 455 : 82,57 %, affiché 82.
        XCTAssertEqual(FormatW.pourcentCalories(PlancheEtats.maquette), 82)
        XCTAssertEqual(FormatW.ligneCalories(PlancheEtats.maquette).nombre, "428")
        XCTAssertNil(FormatW.pourcentCalories(PlancheEtats.sansObjectif), "Sans objectif, pas de pourcentage")
    }

    func testUnePriseNePorteJamaisDeDose() {
        // Décision produit : aucune dose de complément, nulle part. Une prise
        // n'a pour champs qu'un identifiant, un nom, un moment et une coche.
        let champs = Mirror(reflecting: InstantaneJour.exemple.rituel[0]).children.compactMap(\.label)
        XCTAssertEqual(Set(champs), ["id", "nom", "moment", "fait"])
    }

    // MARK: - Le projet

    /// Apple refuse une extension dont la version ou le numéro de build diffère
    /// de ceux de l'app. Les deux cibles portent chacune leur ligne dans
    /// `project.yml` : ce test échoue si on en bumpe une sans l'autre, ou si
    /// l'indentation ne laisse plus le `sed` de la CI réécrire les deux builds.
    func testLAppEtLExtensionPortentLaMemeVersion() throws {
        let racine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projet = try String(contentsOf: racine.appendingPathComponent("project.yml"), encoding: .utf8)
        let lignes = projet.components(separatedBy: .newlines)

        let versions = lignes
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("MARKETING_VERSION:") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(versions.count, 2, "Une ligne pour l'app, une pour l'extension")
        XCTAssertEqual(Set(versions).count, 1, "Versions divergentes : \(versions)")

        let builds = lignes.filter { $0.hasPrefix("        CURRENT_PROJECT_VERSION: ") }
        XCTAssertEqual(builds.count, 2, "Le sed de la CI vise huit espaces d'indentation, pour les deux cibles")
    }

    // MARK: - Aperçus (la seule preuve visuelle sans appareil)

    /// Rend les vraies vues des widgets en image et les dépose dans
    /// `build/apercus-widgets/` : la CI les publie en artefact. Une planche par
    /// widget (`widgets-W1.png` … `widgets-W7.png`, `widgets-journee.png`), à
    /// 2 px par point comme les captures de la maquette, pour les comparer
    /// côte à côte ; et la planche complète, `widgets-clair.png`.
    ///
    /// Plus de variante sombre : le verre est le même dans les deux modes
    /// (encre blanche explicite, `TeinteW`). Le test ne juge pas l'image ; il
    /// vérifie qu'elle se rend.
    @MainActor
    func testLesWidgetsSeRendentEnImage() throws {
        let racine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dossier = racine.appendingPathComponent("build/apercus-widgets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)

        // La planche complète est grande (deux colonnes, plus de 5 000 pt de
        // haut) : 1,5 px par point suffit à la lire.
        let planches: [(nom: String, echelle: CGFloat, vue: AnyView)] = [
            ("widgets-clair", 1.5, AnyView(PlancheWidgets())),
            ("widgets-W1", 2, AnyView(PlancheW1())),
            ("widgets-W2", 2, AnyView(PlancheW2())),
            ("widgets-W3", 2, AnyView(PlancheW3())),
            ("widgets-W4", 2, AnyView(PlancheW4())),
            ("widgets-W5", 2, AnyView(PlancheW5())),
            ("widgets-W6", 2, AnyView(PlancheW6())),
            ("widgets-W7", 2, AnyView(PlancheW7())),
            ("widgets-journee", 2, AnyView(PlancheJournee())),
        ]
        for planche in planches {
            let image = try XCTUnwrap(rendre(planche.vue, echelle: planche.echelle),
                                      "La planche \(planche.nom) ne se rend pas")
            XCTAssertGreaterThan(image.size.width, 300)
            let png = try XCTUnwrap(image.pngData())
            try? png.write(to: dossier.appendingPathComponent("\(planche.nom).png"))

            let piece = XCTAttachment(image: image)
            piece.name = planche.nom
            piece.lifetime = .keepAlways
            add(piece)
        }
    }

    /// Une image trop grande pour le moteur de rendu retombe à 1 px par point
    /// plutôt que de ne rien donner du tout.
    @MainActor
    private func rendre(_ vue: AnyView, echelle: CGFloat) -> UIImage? {
        let rendu = ImageRenderer(content: vue.environment(\.colorScheme, .light))
        for essai in [echelle, 1] {
            rendu.scale = essai
            if let image = rendu.uiImage { return image }
        }
        return nil
    }
}

// MARK: - Les journées de la planche

/// Ce que la planche dessine. `maquette` reprend les chiffres de la maquette
/// « Kiwio - Widgets », pour comparer les deux images ; les variantes en
/// changent une chose à la fois.
private enum PlancheEtats {
    static let jour = "2026-10-03"

    /// Les vues lisent l'heure avec le calendrier courant : 12 h 30 et 19 h 30
    /// dans le fuseau du simulateur.
    static let midi = aujourdhui(12, 30)
    static let soir = aujourdhui(19, 30)

    private static func aujourdhui(_ heure: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: heure, minute: minute)) ?? Date()
    }

    /// 412 + 688 + 702 + 225 = 2 027 kcal sur 2 455 (428 restantes, anneau à
    /// 82 %), série 3, trois verres de 25 cl sur huit, la vitamine D du matin
    /// à prendre ; vitamine D 58, magnésium 74, fer 79 (ceux de l'exemple).
    static let maquette = InstantaneJour(
        jour: jour, connecte: true, bilanFait: true, kcalObjectif: 2455,
        kcalParCreneau: ["breakfast": 412, "lunch": 688, "dinner": 702, "snack": 225],
        serie: 3,
        eau: InstantaneJour.Eau(verres: 3, objectif: 8, centilitres: 25),
        rituel: [InstantaneJour.Prise(id: "vitD", nom: "Vitamine D", moment: "matin", fait: false)],
        apports: InstantaneJour.exemple.apports,
        conseils: InstantaneJour.exemple.conseils,
        conseilFait: nil,
        premium: true
    )

    /// Un geste sans chiffre annoncé, au texte long : pas de badge, et « Tu le
    /// refais demain ? » une fois fait.
    static let gesteSansPoints = ConseilW(
        id: "fiber-legumes",
        texte: "Une portion de légumes ou de légumineuses à chaque repas principal, midi et soir.",
        court: "Des légumes midi et soir",
        apport: "fiber", apportNom: "Fibres", apportCourt: "Fibres", points: 0)

    private static func variante(_ changement: (inout InstantaneJour) -> Void) -> InstantaneJour {
        var etat = maquette
        changement(&etat)
        return etat
    }

    private static func tousPris(_ rituel: [InstantaneJour.Prise]) -> [InstantaneJour.Prise] {
        rituel.map { prise in
            var prise = prise
            prise.fait = true
            return prise
        }
    }

    // Calories
    /// Rien de noté encore : « Ton midi ? », « Dicte-le en 5 secondes ».
    static let rienNote = variante { $0.kcalParCreneau = [:] }
    /// 2 505 kcal : 50 au-dessus du budget.
    static let auDessus = variante { $0.kcalParCreneau["dinner"] = 1180 }
    static let sansObjectif = variante { $0.kcalObjectif = nil }

    // Conseil du jour
    static let conseilFait = variante { $0.conseilFait = $0.conseilDuJour?.id }
    static let sansPremium = variante { $0.premium = false }
    /// Un bilan, mais aucun geste à proposer : « Rien à rattraper aujourd'hui ».
    static let sansConseil = variante { $0.conseils = [] }
    static let sansPoints = variante { $0.conseils = [PlancheEtats.gesteSansPoints] }
    static let sansPointsFait = variante {
        $0.conseils = [PlancheEtats.gesteSansPoints]
        $0.conseilFait = PlancheEtats.gesteSansPoints.id
    }

    // Eau
    static let eauAtteinte = variante { $0.eau = InstantaneJour.Eau(verres: 8, objectif: 8, centilitres: 25) }
    static let eauVide = variante { $0.eau = InstantaneJour.Eau(verres: 0, objectif: 8, centilitres: 25) }
    static let sansEau = variante { $0.eau = nil }

    // Rituel
    static let rituelPris = variante { $0.rituel = PlancheEtats.tousPris($0.rituel) }
    /// Le rituel de l'exemple : fer le matin et vitamine D à midi pris, le
    /// magnésium du soir à prendre.
    static let troisMoments = variante { $0.rituel = InstantaneJour.exemple.rituel }
    static let rituelComplet = variante { $0.rituel = PlancheEtats.tousPris(InstantaneJour.exemple.rituel) }
    static let sansRituel = variante { $0.rituel = [] }

    // Eau et rituel ensemble (ajout rapide, activité en direct)
    static let toutFait = variante {
        $0.eau = InstantaneJour.Eau(verres: 8, objectif: 8, centilitres: 25)
        $0.rituel = PlancheEtats.tousPris($0.rituel)
    }
    static let sansEauNiRituel = variante {
        $0.eau = nil
        $0.rituel = []
    }

    // Apports
    static let unSeulApport = variante {
        $0.apports = LectureApportsW(
            apports: [ApportW(id: "vitD", nom: "Vitamine D", court: "Vit. D", score: 58)],
            verdict: "Ta vitamine D est un peu juste.",
            autres: nil,
            statut: "un peu juste",
            cause: "Première cause : tes repas notés ces 14 derniers jours.",
            titreAliments: "Ce qui la remonte",
            aliments: [AlimentW(nom: "Sardines", illustration: "fluent_fish")]
        )
    }
    /// Tout est couvert : « Le plus bas » plutôt que « À renforcer », et pas de
    /// cause à montrer.
    static let toutCouvert = variante {
        $0.apports = LectureApportsW(
            apports: [ApportW(id: "iron", nom: "Fer", court: "Fer", score: 81),
                      ApportW(id: "magnesium", nom: "Magnésium", court: "Mg", score: 86),
                      ApportW(id: "vitD", nom: "Vitamine D", court: "Vit. D", score: 92)],
            verdict: "Ton fer est couvert.",
            autres: "Magnésium et vitamine D sont couverts.",
            statut: "couvert",
            cause: nil,
            titreAliments: "Ce qui le remonte",
            aliments: [AlimentW(nom: "Moules", illustration: "fluent_oyster"),
                       AlimentW(nom: "Bœuf", illustration: "fluent_meat"),
                       AlimentW(nom: "Épinards", illustration: "fluent_leafygreen")]
        )
    }

    /// Connecté, sans bilan : ni apports, ni conseil, ni rituel, ni eau.
    static let sansBilan = InstantaneJour.vide(jour: jour, connecte: true)
}

// MARK: - La planche des aperçus

private enum PlancheMesures {
    /// Largeur du fond d'écran : deux widgets moyens côte à côte (338 + 20 +
    /// 338), plus ses marges de 22.
    static let largeurFond: CGFloat = 760
    /// Le papier autour des planches de la maquette.
    static let papier = Color(red: 0.945, green: 0.933, blue: 0.91)
}

/// Les tailles réelles sur un iPhone 16 (393 pt de large) : celles que les
/// widgets reçoivent, et non les 170 / 364 / 382 de la maquette.
private enum FormatPlanche {
    case petit, moyen, grand
    case rond, rectangulaire, enLigne
    case activite, ileEtendue, ileCompacte, ileMinimale
    case libre(CGFloat)

    var largeur: CGFloat {
        switch self {
        case .petit: return 158
        case .moyen, .grand: return 338
        case .rond: return 72
        case .rectangulaire: return 160
        case .enLigne: return 234
        case .activite: return 364
        case .ileEtendue: return 371
        case .ileCompacte: return 250
        case .ileMinimale: return 37
        case .libre(let largeur): return largeur
        }
    }
}

/// Le fond d'écran de la maquette (section 0.10 de la spec) : quatre taches
/// elliptiques sur un dégradé vert. C'est sur lui que le verre a été réglé.
private struct FondEcranMaquette: View {
    /// `radial-gradient(rx ry at x y, couleur 0 %, transparent fin)`, en
    /// fractions de la taille du fond.
    private struct Tache {
        let couleur: Color
        let x: CGFloat
        let y: CGFloat
        let rx: CGFloat
        let ry: CGFloat
        let fin: CGFloat
    }

    /// Dans l'ordre du CSS : la première tache est peinte au-dessus des autres.
    /// Statique : la vue n'a aucune propriété stockée, son `init()` reste
    /// accessible au reste du fichier.
    private static let taches: [Tache] = [
        Tache(couleur: Color(hex: "A9DB78"), x: 0, y: 0, rx: 1.2, ry: 0.7, fin: 0.55),
        Tache(couleur: Color(hex: "2E9C86"), x: 1, y: 0.35, rx: 0.9, ry: 0.6, fin: 0.62),
        Tache(couleur: Color(hex: "F4A86E"), x: 0.2, y: 1, rx: 1.2, ry: 0.7, fin: 0.6),
        Tache(couleur: Color(hex: "7B6CC4"), x: 0.9, y: 0.95, rx: 0.8, ry: 0.5, fin: 0.6),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(hex: "4C8A4E"), Color(hex: "22574B")],
                               startPoint: .top, endPoint: .bottom)
                ForEach(Array(Self.taches.indices.reversed()), id: \.self) { index in
                    tache(Self.taches[index], dans: geo.size)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// Une ellipse de rayons `rx × largeur` et `ry × hauteur`, centrée sur
    /// son point, qui s'efface vers le transparent.
    private func tache(_ tache: Tache, dans taille: CGSize) -> some View {
        EllipticalGradient(
            stops: [.init(color: tache.couleur, location: 0),
                    .init(color: tache.couleur.opacity(0), location: tache.fin)],
            center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5
        )
        .frame(width: 2 * tache.rx * taille.width, height: 2 * tache.ry * taille.height)
        .position(x: tache.x * taille.width, y: tache.y * taille.height)
    }
}

/// Une planche comme celles de la maquette : un titre sur le papier, puis le
/// fond d'écran (rayon 28, marges 22, 20 entre deux rangées).
private struct SectionPlanche<Contenu: View>: View {
    let code: String
    let titre: String
    let detail: String
    @ViewBuilder var contenu: () -> Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(code)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(white: 0.11)))
                Text(titre)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(white: 0.06))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.42))
            }
            VStack(spacing: 20) {
                contenu()
            }
            .padding(22)
            .frame(width: PlancheMesures.largeurFond)
            .background(FondEcranMaquette())
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .padding(24)
        .background(PlancheMesures.papier)
    }
}

/// Une rangée de widgets, alignés par le haut.
private struct RangeePlanche<Contenu: View>: View {
    @ViewBuilder var contenu: () -> Contenu

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            contenu()
        }
    }
}

/// Un widget à sa taille réelle, dans le cadre que le système lui donne, avec
/// sa légende dessous.
///
///   • accueil : le bundle pose `.padding(14)` et `FondVerreW` en
///     `containerBackground` ; les coins sont ceux d'un iPhone 16 (22) ;
///   • accessoires : la plaque blanche à 16 % de l'écran verrouillé ;
///   • activité en direct : la teinte de `activityBackgroundTint`, marges
///     16 / 14 ; Dynamic Island : du noir.
private struct CasePlanche<Vue: View>: View {
    let format: FormatPlanche
    let legende: String
    @ViewBuilder var vue: () -> Vue

    var body: some View {
        VStack(spacing: 6) {
            cadre
            Text(legende)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: max(format.largeur, 90))
        }
    }

    @ViewBuilder
    private var cadre: some View {
        switch format {
        case .petit, .moyen:
            accueil(hauteur: 158)
        case .grand:
            accueil(hauteur: 354)
        case .rond:
            vue()
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.white.opacity(0.16)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))
        case .rectangulaire:
            vue()
                .frame(width: 160, height: 72)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))
        case .enLigne:
            // iOS impose sa police à la ligne de l'écran verrouillé : on
            // l'approche, la vue garde la main si elle en pose une.
            vue()
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .frame(width: 234, height: 26)
        case .activite:
            vue()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(width: 364)
                .fixedSize(horizontal: false, vertical: true)
                .background(FondActiviteW.teinte)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        case .ileEtendue:
            vue()
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .frame(width: 371)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        case .ileCompacte:
            vue()
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .frame(width: 250, height: 37)
                .background(Capsule().fill(Color.black))
        case .ileMinimale:
            vue()
                .frame(width: 37, height: 37)
                .background(Circle().fill(Color.black))
        case .libre(let largeur):
            vue()
                .frame(width: largeur)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `containerShape` : le liseré de `FondVerreW` (un `ContainerRelativeShape`)
    /// suit les coins arrondis comme dans un vrai widget.
    private func accueil(hauteur: CGFloat) -> some View {
        let coins = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return vue()
            .padding(14)
            .frame(width: format.largeur, height: hauteur)
            .background(FondVerreW())
            .containerShape(coins)
            .clipShape(coins)
    }
}

/// La Dynamic Island étendue telle que `JourneeActivite` l'assemble : le signe
/// et « Ta journée » à gauche, la série à droite, puis `VueIleEtendue`.
private struct IleEtenduePlanche: View {
    let etat: InstantaneJour

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                SigneW(taille: 18)
                Text("Ta journée")
                    .font(.texteW(14, .bold))
                    .foregroundStyle(TeinteW.encre())
                Spacer(minLength: 0)
                SerieW(serie: etat.serie)
            }
            VueIleEtendue(etat: etat, maintenant: PlancheEtats.soir)
        }
    }
}

// MARK: - Une planche par widget

/// W1 « Tes apports ».
private struct PlancheW1: View {
    var body: some View {
        SectionPlanche(code: "W1", titre: "Tes apports", detail: "petit, moyen, grand") {
            paire("maquette, 19 h 30", PlancheEtats.maquette, PlancheEtats.soir)
            RangeePlanche {
                grand("Grand · maquette", PlancheEtats.maquette)
                grand("Grand · un seul apport", PlancheEtats.unSeulApport)
            }
            paire("tout couvert", PlancheEtats.toutCouvert, PlancheEtats.soir)
            paire("un seul apport, 12 h 30", PlancheEtats.unSeulApport, PlancheEtats.midi)
            RangeePlanche {
                grand("Grand · tout couvert, sans cause", PlancheEtats.toutCouvert)
                grand("Grand · sans bilan", PlancheEtats.sansBilan)
            }
            RangeePlanche {
                petit("Sans bilan", PlancheEtats.sansBilan, PlancheEtats.midi)
                moyen("Moyen · sans bilan", PlancheEtats.sansBilan)
                petit("Déconnecté", nil, PlancheEtats.midi)
            }
        }
    }

    private func paire(_ legende: String, _ etat: InstantaneJour?, _ maintenant: Date) -> some View {
        RangeePlanche {
            petit("Petit · \(legende)", etat, maintenant)
            moyen("Moyen · \(legende)", etat)
        }
    }

    private func petit(_ legende: String, _ etat: InstantaneJour?, _ maintenant: Date) -> some View {
        CasePlanche(format: .petit, legende: legende) { VueApportsPetite(etat: etat, maintenant: maintenant) }
    }

    private func moyen(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .moyen, legende: legende) { VueApportsMoyenne(etat: etat) }
    }

    private func grand(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .grand, legende: legende) { VueApportsGrande(etat: etat) }
    }
}

/// W2 « Conseil du jour ».
private struct PlancheW2: View {
    var body: some View {
        SectionPlanche(code: "W2", titre: "Conseil du jour", detail: "petit, moyen, écran verrouillé") {
            paire("à faire", PlancheEtats.maquette)
            paire("c'est fait", PlancheEtats.conseilFait)
            paire("sans Premium", PlancheEtats.sansPremium)
            paire("rien à rattraper", PlancheEtats.sansConseil)
            RangeePlanche {
                moyen("Moyen · sans points annoncés", PlancheEtats.sansPoints)
                moyen("Moyen · sans points, fait", PlancheEtats.sansPointsFait)
            }
            RangeePlanche {
                petit("Sans bilan", PlancheEtats.sansBilan)
                moyen("Moyen · sans bilan", PlancheEtats.sansBilan)
                petit("Déconnecté", nil)
            }
            RangeePlanche {
                rectangulaire("Écran verrouillé", PlancheEtats.maquette)
                rectangulaire("Sans Premium", PlancheEtats.sansPremium)
                rectangulaire("Rien à rattraper", PlancheEtats.sansConseil)
                rectangulaire("Sans bilan", PlancheEtats.sansBilan)
            }
            RangeePlanche {
                moyen("Moyen · déconnecté", nil)
                rectangulaire("Déconnecté", nil)
                petit("Sans points annoncés", PlancheEtats.sansPoints)
            }
        }
    }

    private func paire(_ legende: String, _ etat: InstantaneJour?) -> some View {
        RangeePlanche {
            petit("Petit · \(legende)", etat)
            moyen("Moyen · \(legende)", etat)
        }
    }

    private func petit(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .petit, legende: legende) { VueConseilPetite(etat: etat) }
    }

    private func moyen(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .moyen, legende: legende) { VueConseilMoyenne(etat: etat) }
    }

    private func rectangulaire(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .rectangulaire, legende: legende) { VueConseilRectangulaire(etat: etat) }
    }
}

/// W3 « Ajout rapide ».
private struct PlancheW3: View {
    var body: some View {
        SectionPlanche(code: "W3", titre: "Ajout rapide", detail: "petit, moyen, écran verrouillé") {
            RangeePlanche {
                petit("Petit · 12 h 30, rien de noté", PlancheEtats.rienNote, PlancheEtats.midi)
                petit("Petit · 19 h 30", PlancheEtats.maquette, PlancheEtats.soir)
                petit("Déconnecté", nil, PlancheEtats.midi)
                CasePlanche(format: .rond, legende: "Rond") { VueDicterRonde() }
            }
            RangeePlanche {
                moyen("Moyen · 12 h 30", PlancheEtats.rienNote, PlancheEtats.midi)
                moyen("Moyen · eau atteinte, rituel pris", PlancheEtats.toutFait, PlancheEtats.soir)
            }
            RangeePlanche {
                moyen("Moyen · sans eau ni rituel", PlancheEtats.sansEauNiRituel, PlancheEtats.soir)
                moyen("Moyen · eau non suivie", PlancheEtats.sansEau, PlancheEtats.soir)
            }
            RangeePlanche {
                moyen("Moyen · sans rituel", PlancheEtats.sansRituel, PlancheEtats.soir)
                moyen("Moyen · déconnecté", nil, PlancheEtats.midi)
            }
            RangeePlanche {
                petit("Sans bilan", PlancheEtats.sansBilan, PlancheEtats.midi)
                moyen("Moyen · sans bilan", PlancheEtats.sansBilan, PlancheEtats.midi)
            }
        }
    }

    private func petit(_ legende: String, _ etat: InstantaneJour?, _ maintenant: Date) -> some View {
        CasePlanche(format: .petit, legende: legende) { VueAjoutPetite(etat: etat, maintenant: maintenant) }
    }

    private func moyen(_ legende: String, _ etat: InstantaneJour?, _ maintenant: Date) -> some View {
        CasePlanche(format: .moyen, legende: legende) { VueAjoutMoyenne(etat: etat, maintenant: maintenant) }
    }
}

/// W4 « Eau ».
private struct PlancheW4: View {
    var body: some View {
        SectionPlanche(code: "W4", titre: "Eau", detail: "petit, écran verrouillé") {
            RangeePlanche {
                petit("3 verres sur 8", PlancheEtats.maquette)
                petit("Objectif atteint", PlancheEtats.eauAtteinte)
                petit("Rien bu encore", PlancheEtats.eauVide)
                rond("Rond · 3 verres", PlancheEtats.maquette)
            }
            RangeePlanche {
                petit("Eau non suivie", PlancheEtats.sansEau)
                petit("Déconnecté", nil)
                rond("Rond · atteint", PlancheEtats.eauAtteinte)
                rond("Rond · vide", PlancheEtats.eauVide)
                rond("Rond · non suivie", PlancheEtats.sansEau)
            }
        }
    }

    private func petit(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .petit, legende: legende) { VueEauPetite(etat: etat) }
    }

    private func rond(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .rond, legende: legende) { VueEauRonde(etat: etat) }
    }
}

/// W5 « Rituel ».
private struct PlancheW5: View {
    var body: some View {
        SectionPlanche(code: "W5", titre: "Rituel", detail: "petit, moyen") {
            paire("à prendre", PlancheEtats.maquette)
            paire("pris", PlancheEtats.rituelPris)
            paire("trois moments, deux pris", PlancheEtats.troisMoments)
            paire("rituel complet", PlancheEtats.rituelComplet)
            paire("sans rituel", PlancheEtats.sansRituel)
            paire("déconnecté", nil)
        }
    }

    private func paire(_ legende: String, _ etat: InstantaneJour?) -> some View {
        RangeePlanche {
            CasePlanche(format: .petit, legende: "Petit · \(legende)") { VueRituelPetite(etat: etat) }
            CasePlanche(format: .moyen, legende: "Moyen · \(legende)") { VueRituelMoyenne(etat: etat) }
        }
    }
}

/// W6, l'écran verrouillé : les accessoires de la maquette, puis les états de
/// « Tes apports » (ceux du conseil et de l'eau sont sur W2 et W4).
private struct PlancheW6: View {
    var body: some View {
        SectionPlanche(code: "W6", titre: "Écran verrouillé", detail: "rond, rectangulaire, en ligne") {
            RangeePlanche {
                CasePlanche(format: .rond, legende: "Eau") { VueEauRonde(etat: PlancheEtats.maquette) }
                rond("Vitamine D", PlancheEtats.maquette)
                CasePlanche(format: .rond, legende: "Dicter") { VueDicterRonde() }
                CasePlanche(format: .rectangulaire, legende: "Conseil") {
                    VueConseilRectangulaire(etat: PlancheEtats.maquette)
                }
                rectangulaire("Trois apports", PlancheEtats.maquette)
            }
            RangeePlanche {
                enLigne("En ligne", PlancheEtats.maquette)
                enLigne("En ligne · eau non suivie", PlancheEtats.sansEau)
                rectangulaire("Un seul apport", PlancheEtats.unSeulApport)
            }
            RangeePlanche {
                rond("Tout couvert", PlancheEtats.toutCouvert)
                rectangulaire("Tout couvert", PlancheEtats.toutCouvert)
                enLigne("En ligne · tout couvert", PlancheEtats.toutCouvert)
                rond("Sans bilan", PlancheEtats.sansBilan)
            }
            RangeePlanche {
                rectangulaire("Sans bilan", PlancheEtats.sansBilan)
                enLigne("En ligne · sans bilan", PlancheEtats.sansBilan)
                rond("Déconnecté", nil)
                rectangulaire("Déconnecté", nil)
            }
        }
    }

    private func rond(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .rond, legende: legende) { VueApportsRonde(etat: etat) }
    }

    private func rectangulaire(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .rectangulaire, legende: legende) { VueApportsRectangulaire(etat: etat) }
    }

    private func enLigne(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .enLigne, legende: legende) { VueApportsEnLigne(etat: etat) }
    }
}

/// W7, l'activité en direct et la Dynamic Island.
private struct PlancheW7: View {
    var body: some View {
        SectionPlanche(code: "W7", titre: "Activité en direct", detail: "verrouillé, Dynamic Island") {
            cartes
            iles
            compactes
            barres
        }
    }

    private var cartes: some View {
        VStack(spacing: 20) {
            carte("Écran verrouillé · 19 h 30", PlancheEtats.maquette)
            carte("Eau atteinte, rituel pris", PlancheEtats.toutFait)
            carte("Au-dessus du budget", PlancheEtats.auDessus)
            carte("Sans eau ni rituel", PlancheEtats.sansEauNiRituel)
            carte("Sans objectif", PlancheEtats.sansObjectif)
        }
    }

    private var iles: some View {
        VStack(spacing: 20) {
            ile("Dynamic Island étendue", PlancheEtats.maquette)
            ile("Étendue · au-dessus du budget", PlancheEtats.auDessus)
            ile("Étendue · sans objectif", PlancheEtats.sansObjectif)
        }
    }

    private var compactes: some View {
        VStack(spacing: 20) {
            RangeePlanche {
                compacte("Compacte", PlancheEtats.maquette)
                minimale("Minimale", PlancheEtats.maquette)
                compacte("Compacte · au-dessus", PlancheEtats.auDessus)
            }
            RangeePlanche {
                minimale("Minimale · au-dessus", PlancheEtats.auDessus)
                compacte("Compacte · sans objectif", PlancheEtats.sansObjectif)
                minimale("Minimale · sans objectif", PlancheEtats.sansObjectif)
            }
        }
    }

    private var barres: some View {
        RangeePlanche {
            barre("Barre · au-dessus du budget", PlancheEtats.auDessus)
            barre("Barre · sans objectif", PlancheEtats.sansObjectif)
        }
    }

    private func carte(_ legende: String, _ etat: InstantaneJour) -> some View {
        CasePlanche(format: .activite, legende: legende) {
            VueActiviteJournee(etat: etat, maintenant: PlancheEtats.soir)
        }
    }

    private func ile(_ legende: String, _ etat: InstantaneJour) -> some View {
        CasePlanche(format: .ileEtendue, legende: legende) { IleEtenduePlanche(etat: etat) }
    }

    /// Les deux zones de part et d'autre de la caméra, dessinées comme une
    /// seule pilule (comme la maquette).
    private func compacte(_ legende: String, _ etat: InstantaneJour) -> some View {
        CasePlanche(format: .ileCompacte, legende: legende) {
            HStack(spacing: 0) {
                VueIleCompacteGauche()
                Spacer(minLength: 8)
                VueIleCompacteDroite(etat: etat)
            }
        }
    }

    private func minimale(_ legende: String, _ etat: InstantaneJour) -> some View {
        CasePlanche(format: .ileMinimale, legende: legende) { VueIleMinimale(etat: etat) }
    }

    private func barre(_ legende: String, _ etat: InstantaneJour) -> some View {
        CasePlanche(format: .libre(310), legende: legende) {
            VStack(spacing: 5) {
                BarreJourneeW(etat: etat)
                LegendeJourneeW(etat: etat)
            }
        }
    }
}

/// « Ma journée », absent de la maquette : habillé comme W7.
private struct PlancheJournee: View {
    var body: some View {
        SectionPlanche(code: "J", titre: "Ma journée", detail: "petit, moyen, écran verrouillé") {
            paire("maquette", PlancheEtats.maquette)
            paire("au-dessus du budget", PlancheEtats.auDessus)
            paire("sans objectif", PlancheEtats.sansObjectif)
            paire("rien de noté", PlancheEtats.rienNote)
            RangeePlanche {
                petit("Sans bilan", PlancheEtats.sansBilan)
                moyen("Moyen · sans bilan", PlancheEtats.sansBilan)
                petit("Déconnecté", nil)
            }
            RangeePlanche {
                rectangulaire("Rectangulaire", PlancheEtats.maquette)
                rectangulaire("Au-dessus du budget", PlancheEtats.auDessus)
                rectangulaire("Sans bilan", PlancheEtats.sansBilan)
                rectangulaire("Déconnecté", nil)
            }
        }
    }

    private func paire(_ legende: String, _ etat: InstantaneJour?) -> some View {
        RangeePlanche {
            petit("Petit · \(legende)", etat)
            moyen("Moyen · \(legende)", etat)
        }
    }

    private func petit(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .petit, legende: legende) { VueJourneePetite(etat: etat) }
    }

    private func moyen(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .moyen, legende: legende) { VueJourneeMoyenne(etat: etat) }
    }

    private func rectangulaire(_ legende: String, _ etat: InstantaneJour?) -> some View {
        CasePlanche(format: .rectangulaire, legende: legende) { VueJourneeRectangulaire(etat: etat) }
    }
}

/// Toutes les planches sur une seule image (`widgets-clair.png`), en deux
/// colonnes de hauteurs voisines.
private struct PlancheWidgets: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                PlancheW1()
                PlancheW2()
                PlancheW3()
                PlancheW4()
            }
            VStack(spacing: 0) {
                PlancheW5()
                PlancheW6()
                PlancheW7()
                PlancheJournee()
            }
        }
        .background(PlancheMesures.papier)
    }
}
