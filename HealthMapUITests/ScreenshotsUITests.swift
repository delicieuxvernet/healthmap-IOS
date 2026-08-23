import XCTest

// MARK: - Captures d'écran automatisées (audit visuel + fiche App Store)
//
// Tourne sur simulateur, dans le workflow `screenshots.yml` : l'app est
// lancée, connectée avec le compte d'audit fourni par l'environnement
// (`SCREENSHOT_EMAIL` / `SCREENSHOT_PASSWORD`), puis chaque écran de la
// refonte est photographié en pleine résolution (`XCUIScreen.main`). Les
// captures sont attachées au `.xcresult` (`lifetime: .keepAlways`) et
// extraites par le workflow avec `xcresulttool export attachments`.
//
// Chaque capture est nommée `NN-ecran` : le numéro fixe l'ordre de lecture.
// Un écran introuvable n'échoue pas le test : la capture manque, l'audit le
// voit, l'app n'est pas bloquée pour autant.
final class ScreenshotsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - 1. Page de garde, onboarding, connexion (compte neuf)

    func test01_AccueilEtConnexion() throws {
        app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "NO", "-hasSeenTabTour", "YES", "-hasSeenScanTour", "YES", "-kiwioCaptures", "YES"]
        app.launch()

        // Onboarding : page de garde + première page feature.
        if app.buttons["Passer"].waitForExistence(timeout: 15) {
            snap("01-onboarding-garde")
            app.buttons["C'est parti"].firstMatch.tap()
            sleep(1)
            snap("02-onboarding-page")
            app.buttons["Passer"].firstMatch.tap()
        }

        // Page de garde non connecté.
        if app.buttons["J'ai déjà un compte"].waitForExistence(timeout: 15) {
            snap("03-page-de-garde")
            app.buttons["J'ai déjà un compte"].tap()
            sleep(1)
            snap("04-connexion")
            // On ne se connecte pas ici : la feuille se referme, test suivant.
            app.swipeDown(velocity: .fast)
        }
    }

    // MARK: - 2. Parcours connecté : les cinq onglets et leurs feuilles

    func test02_ParcoursConnecte() throws {
        app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES", "-hasSeenTabTour", "YES", "-hasSeenScanTour", "YES", "-kiwioCaptures", "YES"]
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["SCREENSHOT_EMAIL"] = env["SCREENSHOT_EMAIL"] ?? ""
        app.launchEnvironment["SCREENSHOT_PASSWORD"] = env["SCREENSHOT_PASSWORD"] ?? ""
        app.launch()

        connecterSiBesoin()

        // Journal : le premier onglet, une fois le profil chargé.
        XCTAssertTrue(app.buttons["Progrès"].waitForExistence(timeout: 120), "Barre d'onglets absente : connexion ou chargement du profil en échec")
        attendreChargement()
        snap("10-journal")
        app.swipeUp()
        sleep(1)
        snap("11-journal-bas")
        app.swipeDown()

        // Feuille d'ajout.
        if app.buttons["Ajouter un repas"].waitForExistence(timeout: 5) {
            app.buttons["Ajouter un repas"].tap()
            sleep(1)
            snap("12-ajout")
            fermerFeuille()
        }

        // Fiche apport (première ligne de « Apports à renforcer »).
        let apport = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "pour cent de tes besoins")).firstMatch
        if apport.waitForExistence(timeout: 5) {
            apport.tap()
            sleep(2)
            snap("13-fiche-apport")
            fermerFeuille()
        }

        // Bilan complet (« Tout afficher »).
        if app.buttons["Tout afficher"].waitForExistence(timeout: 5) {
            app.buttons["Tout afficher"].tap()
            sleep(2)
            snap("14-bilan-complet")
            fermerFeuille()
        }

        // Progrès.
        app.buttons["Progrès"].tap()
        sleep(2)
        snap("20-progres")
        app.swipeUp()
        sleep(1)
        snap("21-progres-bas")
        app.swipeDown()

        // Plan + feuille d'un nœud.
        app.buttons["Plan"].tap()
        sleep(3)
        snap("30-plan")
        let noeud = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@", "symptôme", "objectif", "apport")).firstMatch
        if noeud.waitForExistence(timeout: 5) {
            noeud.tap()
            sleep(2)
            snap("31-plan-noeud")
            fermerFeuille()
        }

        // Compléments.
        app.buttons["Compléments"].tap()
        sleep(3)
        snap("40-complements")
        app.swipeUp()
        sleep(1)
        snap("41-complements-bas")
        app.swipeDown()

        // Réglages + sous-pages.
        app.buttons["Réglages"].tap()
        sleep(2)
        snap("50-reglages")
        app.swipeUp()
        sleep(1)
        snap("51-reglages-bas")
        app.swipeDown()
        if app.buttons["Mon abonnement"].firstMatch.waitForExistence(timeout: 5) {
            app.buttons["Mon abonnement"].firstMatch.tap()
            sleep(2)
            snap("52-abonnement")
            retour()
        }
        if app.buttons["Mes données et confidentialité"].firstMatch.waitForExistence(timeout: 5) {
            app.buttons["Mes données et confidentialité"].firstMatch.tap()
            sleep(2)
            snap("53-donnees")
            retour()
        }
        if app.buttons["Mon profil et mes objectifs"].firstMatch.waitForExistence(timeout: 5) {
            app.buttons["Mon profil et mes objectifs"].firstMatch.tap()
            sleep(2)
            snap("54-profil")
            retour()
        }
        if app.buttons["Notre méthode et nos sources"].firstMatch.waitForExistence(timeout: 5) {
            app.buttons["Notre méthode et nos sources"].firstMatch.tap()
            sleep(2)
            snap("55-methode")
            retour()
        }
        // Paywall depuis la carte Premium (gratuit) ou l'abonnement.
        if app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Essayer")).firstMatch.exists {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Essayer")).firstMatch.tap()
            sleep(3)
            snap("56-paywall")
            fermerFeuille()
        }
    }

    // MARK: - 3. Avant le questionnaire + questionnaire (hook DEBUG `-captureDecouverte`)

    func test03_AvantQuestionnaireEtQuestionnaire() throws {
        app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES", "-hasSeenTabTour", "YES", "-hasSeenScanTour", "YES", "-kiwioCaptures", "YES", "-captureDecouverte", "YES"]
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["SCREENSHOT_EMAIL"] = env["SCREENSHOT_EMAIL"] ?? ""
        app.launchEnvironment["SCREENSHOT_PASSWORD"] = env["SCREENSHOT_PASSWORD"] ?? ""
        app.launch()

        connecterSiBesoin()
        XCTAssertTrue(app.buttons["Progrès"].waitForExistence(timeout: 120))
        attendreChargement()
        snap("60-journal-avant-questionnaire")

        // Progrès / Plan / Compléments en découverte.
        app.buttons["Progrès"].tap(); sleep(2); snap("61-progres-decouverte")
        app.buttons["Plan"].tap(); sleep(3); snap("62-plan-decouverte")
        app.buttons["Compléments"].tap(); sleep(2); snap("63-complements-decouverte")
        app.buttons["Journal"].tap(); sleep(1)

        // Le questionnaire : porte « Répondre au questionnaire ».
        let porte = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "questionnaire")).firstMatch
        if porte.waitForExistence(timeout: 5) {
            porte.tap()
            sleep(2)
            snap("70-questionnaire-intro")
            if app.buttons["C'est parti"].firstMatch.waitForExistence(timeout: 5) {
                app.buttons["C'est parti"].firstMatch.tap()
                sleep(1)
                snap("71-questionnaire-question")
                // Quelques écrans de plus pour voir les types de réponse.
                for i in 0..<3 {
                    let continuer = app.buttons["Continuer"].firstMatch
                    if continuer.waitForExistence(timeout: 3), continuer.isEnabled {
                        continuer.tap()
                        sleep(1)
                        snap("7\(2 + i)-questionnaire")
                    } else {
                        break
                    }
                }
            }
            app.swipeDown(velocity: .fast)
        }
    }

    // MARK: - Outils

    /// Se connecte si la page de garde est affichée (session absente).
    private func connecterSiBesoin() {
        guard app.buttons["J'ai déjà un compte"].waitForExistence(timeout: 20) else { return }
        app.buttons["J'ai déjà un compte"].tap()
        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10), "Champ email introuvable")
        email.tap()
        email.typeText(app.launchEnvironment["SCREENSHOT_EMAIL"] ?? "")
        let password = app.secureTextFields["auth.password"]
        password.tap()
        password.typeText(app.launchEnvironment["SCREENSHOT_PASSWORD"] ?? "")
        app.buttons["Se connecter"].firstMatch.tap()
    }

    /// Laisse le temps au Journal de charger ses données (journal, bilan).
    private func attendreChargement() {
        sleep(4)
    }

    private func fermerFeuille() {
        if app.buttons["Fermer"].firstMatch.exists {
            app.buttons["Fermer"].firstMatch.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        sleep(1)
    }

    private func retour() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() } else { app.swipeRight() }
        sleep(1)
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
