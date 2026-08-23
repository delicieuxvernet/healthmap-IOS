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
        // Sur simulateur, StoreKit (RevenueCat) déclenche une alerte Springboard
        // « Sign in to Apple Account » au premier chargement des offres. On la
        // ferme tout de suite plutôt que de laisser le gestionnaire par défaut
        // la chercher pendant de longues secondes.
        addUIInterruptionMonitor(withDescription: "Apple Account") { alerte in
            for titre in ["Not Now", "Cancel", "Plus tard", "Annuler"] {
                let bouton = alerte.buttons[titre]
                if bouton.exists { bouton.tap(); return true }
            }
            return false
        }
    }

    // MARK: - 1. Page de garde, onboarding, connexion (compte neuf)

    func test01_AccueilEtConnexion() throws {
        app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "NO", "-hasSeenTabTour", "YES", "-hasSeenScanTour", "YES", "-kiwioCaptures", "YES"]
        app.launch()

        fermerAlerteApple()

        // Onboarding : page de garde + première page feature.
        if app.buttons["Passer"].waitForExistence(timeout: 15) {
            snap("01-onboarding-garde")
            app.buttons["C'est parti"].firstMatch.tap()
            sleep(1)
            snap("02-onboarding-page")
            app.buttons["Passer"].firstMatch.tap()
        }

        // Page de garde non connecté.
        if app.buttons["J'ai déjà un compte"].waitForExistence(timeout: 30) {
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
        XCTAssertTrue(app.buttons["tab.progres"].waitForExistence(timeout: 120), "Barre d'onglets absente : connexion ou chargement du profil en échec")
        attendreChargement()

        // Deux aliments dans la journée (yaourt, banane) : les cartes calories
        // et macros de la capture ne sont pas à zéro.
        for aliment in ["Yaourt nature", "Banane"] { ajouterRapide(aliment) }
        sleep(2)
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

        // Recherche → fiche portion d'un aliment qui se compte (œuf) : la
        // quantité se saisit en unités (Petit / Moyen / Gros, « 1 œuf »).
        if app.buttons["Ajouter un repas"].waitForExistence(timeout: 5) {
            app.buttons["Ajouter un repas"].tap()
            if app.buttons["Rechercher"].waitForExistence(timeout: 5) {
                app.buttons["Rechercher"].tap()
                let champ = app.textFields["recherche.champ"]
                if champ.waitForExistence(timeout: 8) {
                    champ.tap()
                    fermerTutorielClavier()
                    champ.typeText("oeuf")
                    sleep(4)
                    snap("15-recherche")
                    let resultat = app.buttons.matching(NSPredicate(
                        format: "(label CONTAINS[c] %@ OR label CONTAINS[c] %@) AND NOT (label BEGINSWITH %@)",
                        "oeuf", "œuf", "Ajouter")).firstMatch
                    if resultat.waitForExistence(timeout: 5) {
                        resultat.tap()
                        sleep(3)
                        snap("16-fiche-portion-unites")
                        app.swipeDown(velocity: .fast)
                        sleep(1)
                    }
                }
                fermerFeuille()
            } else {
                fermerFeuille()
            }
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

        // Progrès (le check-in du jour s'ouvre à la première visite : plus tard).
        app.buttons["tab.progres"].tap()
        sleep(2)
        if app.buttons["Plus tard"].waitForExistence(timeout: 3) {
            app.buttons["Plus tard"].tap()
            sleep(1)
        }
        snap("20-progres")
        app.swipeUp()
        sleep(1)
        snap("21-progres-bas")
        app.swipeDown()

        // Plan + feuille d'un nœud.
        app.buttons["tab.plan"].tap()
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
        app.buttons["tab.complements"].tap()
        sleep(3)
        snap("40-complements")
        app.swipeUp()
        sleep(1)
        snap("41-complements-bas")
        app.swipeDown()

        // Réglages + sous-pages.
        app.buttons["tab.reglages"].tap()
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
        XCTAssertTrue(app.buttons["tab.progres"].waitForExistence(timeout: 120))
        attendreChargement()
        snap("60-journal-avant-questionnaire")

        // Progrès / Plan / Compléments en découverte.
        app.buttons["tab.progres"].tap(); sleep(2); snap("61-progres-decouverte")
        app.buttons["tab.plan"].tap(); sleep(3); snap("62-plan-decouverte")
        app.buttons["tab.complements"].tap(); sleep(2); snap("63-complements-decouverte")
        app.buttons["tab.journal"].tap(); sleep(1)

        // Le questionnaire : porte « Répondre au questionnaire ».
        let porte = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "questionnaire")).firstMatch
        if porte.waitForExistence(timeout: 5) {
            porte.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
    ///
    /// L'app se connecte d'elle-même (hook DEBUG `SCREENSHOT_EMAIL` /
    /// `SCREENSHOT_PASSWORD` dans AuthViewModel) : on attend d'abord la barre
    /// d'onglets. La saisie au clavier n'est qu'un repli.
    private func connecterSiBesoin() {
        let identifiant = app.launchEnvironment["SCREENSHOT_EMAIL"] ?? ""
        let motDePasse = app.launchEnvironment["SCREENSHOT_PASSWORD"] ?? ""
        NSLog("captures: identifiants transmis à l'app — email %d caractères, mot de passe %d caractères", identifiant.count, motDePasse.count)
        fermerAlerteApple()
        if app.buttons["tab.progres"].waitForExistence(timeout: 45) { autoriserSante(); return }
        guard app.buttons["J'ai déjà un compte"].waitForExistence(timeout: 10) else { return }
        app.buttons["J'ai déjà un compte"].tap()
        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10), "Champ email introuvable")
        email.tap()
        email.typeText(app.launchEnvironment["SCREENSHOT_EMAIL"] ?? "")
        let oeil = app.buttons["auth.togglePassword"]
        if oeil.waitForExistence(timeout: 3) { oeil.tap() }
        let password = app.textFields["auth.password"].exists
            ? app.textFields["auth.password"] : app.secureTextFields["auth.password"]
        password.tap()
        password.typeText(motDePasse)
        sleep(1)
        app.buttons["Se connecter"].firstMatch.tap()
    }

    /// Ajoute un aliment à la journée par la recherche et le « + » rapide de
    /// la première ligne de résultats (1 unité pour un aliment qui se compte,
    /// 100 g sinon). Sans effet si la recherche ne répond pas.
    private func ajouterRapide(_ aliment: String) {
        guard app.buttons["Ajouter un repas"].waitForExistence(timeout: 5) else { return }
        app.buttons["Ajouter un repas"].tap()
        guard app.buttons["Rechercher"].waitForExistence(timeout: 5) else { fermerFeuille(); return }
        app.buttons["Rechercher"].tap()
        let champ = app.textFields["recherche.champ"]
        guard champ.waitForExistence(timeout: 8) else { fermerFeuille(); return }
        champ.tap()
        fermerTutorielClavier()
        champ.typeText(aliment)
        sleep(4)
        let plus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ajouter ")).firstMatch
        if plus.waitForExistence(timeout: 5) {
            plus.tap()
            sleep(3)
        }
        fermerFeuille()
        sleep(1)
    }

    /// Laisse le temps au Journal de charger ses données (journal, bilan).
    private func attendreChargement() {
        autoriserSante()
        sleep(4)
    }

    /// Première ouverture du Journal : iOS présente la feuille « Health
    /// Access » (Apple Santé). On autorise tout, comme le ferait une personne
    /// qui installe l'app, pour que les captures montrent l'état connecté.
    /// La feuille est hébergée par un autre processus : on interroge l'app
    /// ET Springboard.
    private func autoriserSante() {
        let hotes = [app!]
        guard hotes.contains(where: { $0.staticTexts["Health Access"].waitForExistence(timeout: 2) }) else { return }
        for hote in hotes {
            for element in [hote.buttons["Turn On All"], hote.cells["Turn On All"],
                            hote.staticTexts["Turn On All"], hote.buttons["Tout activer"]] where element.exists {
                element.tap()
                sleep(1)
                break
            }
        }
        for hote in hotes {
            for bouton in [hote.buttons["Allow"], hote.buttons["Autoriser"]] where bouton.exists && bouton.isEnabled {
                bouton.tap()
                sleep(2)
                return
            }
        }
        // Rien d'activable : on refuse plutôt que de rester bloqué.
        for hote in hotes {
            for bouton in [hote.buttons["Don't Allow"], hote.buttons["Ne pas autoriser"]] where bouton.exists {
                bouton.tap()
                sleep(1)
                return
            }
        }
    }

    /// Sur simulateur, StoreKit déclenche au lancement l'alerte Springboard
    /// « Sign in to Apple Account ». Elle resterait sur les captures : on la
    /// ferme tout de suite (le moniteur d'interruption ne joue qu'au premier
    /// geste, pas pendant une simple attente).
    private func fermerAlerteApple() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alerte = springboard.alerts.firstMatch
        guard alerte.waitForExistence(timeout: 8) else { return }
        for titre in ["Not Now", "Cancel", "Plus tard", "Annuler"] {
            let bouton = alerte.buttons[titre]
            if bouton.exists { bouton.tap(); sleep(1); return }
        }
    }

    /// Tutoriel clavier du simulateur (« Speed up your typing… », bouton
    /// Continue) : il recouvre le clavier à la première saisie.
    private func fermerTutorielClavier() {
        for application in [app!, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            let continuer = application.buttons["Continue"]
            if continuer.waitForExistence(timeout: 2) { continuer.tap(); sleep(1); return }
        }
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
