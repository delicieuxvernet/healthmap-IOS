import XCTest
import SwiftUI
@testable import HealthMap

/// Les widgets vivent hors de l'app : tout ce qu'ils affichent passe par la
/// boîte commune. Ces tests tiennent ses règles, sans trousseau ni extension :
///
///   • un instantané de la veille ne ment pas sur aujourd'hui ;
///   • ce qu'on touche sur un widget se voit tout de suite, et l'app retire de
///     l'attente exactement ce qu'elle a appliqué ;
///   • un lien de widget ouvre le bon écran, et rien d'autre ne passe pour un
///     lien de widget ;
///   • l'activité en direct ne revient pas sur l'écran verrouillé d'une
///     personne qui vient de l'écarter.
final class WidgetsPartageTests: XCTestCase {

    private final class StockageMemoire: StockagePartage {
        var contenu: [String: Data] = [:]
        func lire(_ cle: String) -> Data? { contenu[cle] }
        func ecrire(_ donnees: Data?, cle: String) { contenu[cle] = donnees }
    }

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
    }

    func testLaDeconnexionVideLaBoite() {
        BoiteCommune.ecrireInstantane(journee(jour: BoiteCommune.cleDuJour()))
        BoiteCommune.ajouterVerre()
        BoiteCommune.toutEffacer()
        XCTAssertNil(BoiteCommune.etatAffiche())
        XCTAssertNil(BoiteCommune.lireAttente())
    }

    // MARK: - Les liens

    func testChaqueLienFaitLAllerRetour() {
        let liens: [LienKiwio] = [.journal, .dicter, .photo, .rechercher, .complements,
                                  .repas("breakfast"), .repas("lunch"), .repas("dinner"), .repas("snack")]
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

    func testLesCreneauxDuWidgetSontCeuxDuJournal() {
        XCTAssertEqual(CreneauWidget.allCases.map(\.rawValue),
                       MealJournalService.MealSlot.ordreJournal.map(\.rawValue))
        for creneau in CreneauWidget.allCases {
            let slot = MealJournalService.MealSlot(rawValue: creneau.rawValue)
            XCTAssertEqual(creneau.libelle, slot?.label)
            XCTAssertEqual(creneau.symbole, slot?.symboleJournal)
        }
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

    /// Rend les vraies vues des widgets en image, en clair et en sombre, et
    /// les dépose dans `build/apercus-widgets/` : la CI les publie en artefact.
    /// Le test ne juge pas l'image ; il vérifie qu'elle se rend.
    @MainActor
    func testLesWidgetsSeRendentEnImage() throws {
        let racine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dossier = racine.appendingPathComponent("build/apercus-widgets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)

        let jour = journee(jour: "2026-10-01")
        var debut = InstantaneJour.vide(jour: "2026-10-01", connecte: true)
        debut.bilanFait = false

        for (nom, schema) in [("clair", ColorScheme.light), ("sombre", ColorScheme.dark)] {
            let planche = PlancheWidgets(etat: jour, sansBilan: debut)
                .environment(\.colorScheme, schema)
            let rendu = ImageRenderer(content: planche)
            rendu.scale = 3
            let image = try XCTUnwrap(rendu.uiImage, "La planche \(nom) ne se rend pas")
            XCTAssertGreaterThan(image.size.width, 300)
            let png = try XCTUnwrap(image.pngData())
            try? png.write(to: dossier.appendingPathComponent("widgets-\(nom).png"))

            let piece = XCTAttachment(image: image)
            piece.name = "widgets-\(nom)"
            piece.lifetime = .keepAlways
            add(piece)
        }
    }
}

// MARK: - La planche des aperçus

/// Tous les widgets, à leur taille réelle, sur un fond d'écran d'accueil.
private struct PlancheWidgets: View {
    @Environment(\.colorScheme) private var schema
    let etat: InstantaneJour
    let sansBilan: InstantaneJour

    private var fondWidget: Color { schema == .dark ? Color(white: 0.11) : .white }
    private var fondEcran: Color { schema == .dark ? Color(white: 0.02) : Color(white: 0.90) }

    private func widget<Contenu: View>(_ titre: String, largeur: CGFloat, hauteur: CGFloat,
                                       @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(spacing: 6) {
            contenu()
                .padding(16)
                .frame(width: largeur, height: hauteur)
                .background(fondWidget)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(titre)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            widget("Activité en direct (écran verrouillé)", largeur: 362, hauteur: 164) {
                VueActiviteJournee(etat: etat)
            }
            widget("Ma journée · moyen", largeur: 338, hauteur: 158) { VueJourneeMoyenne(etat: etat) }
            widget("Ajout rapide · moyen", largeur: 338, hauteur: 158) { VueAjoutRapide(etat: etat) }
            HStack(spacing: 22) {
                widget("Ma journée · petit", largeur: 158, hauteur: 158) { VueJourneePetite(etat: etat) }
                widget("Eau · petit", largeur: 158, hauteur: 158) { VueEauPetite(etat: etat) }
            }
            HStack(spacing: 22) {
                widget("Rituel · petit", largeur: 158, hauteur: 158) { VueRituel(etat: etat, detail: false) }
                widget("Dicter · petit", largeur: 158, hauteur: 158) { VueDicterPetite() }
            }
            widget("Rituel · moyen", largeur: 338, hauteur: 158) { VueRituel(etat: etat) }
            widget("Avant le bilan · Ajout rapide", largeur: 338, hauteur: 158) { VueAjoutRapide(etat: sansBilan) }
            widget("Avant le bilan · Ma journée", largeur: 338, hauteur: 158) { VueJourneeMoyenne(etat: sansBilan) }
            widget("Personne de connecté", largeur: 338, hauteur: 158) { VueJourneeMoyenne(etat: nil) }
            HStack(spacing: 22) {
                VueDicterRonde().frame(width: 58, height: 58)
                VueEauRonde(etat: etat).frame(width: 58, height: 58)
                VueJourneeRectangulaire(etat: etat).frame(width: 160, height: 58)
            }
        }
        .padding(24)
        .background(fondEcran)
    }
}
