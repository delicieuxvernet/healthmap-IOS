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
        app.swipeDown()
        sleep(1)
        snap("10-journal")
        app.swipeUp()
        sleep(1)
        snap("11-journal-bas")
        app.swipeDown()

        // Saisie dépliée : Écrire · Rechercher · Code-barres.
        if app.buttons["journal.autres"].waitForExistence(timeout: 5) {
            if !app.buttons["Rechercher"].exists { taper(app.buttons["journal.autres"]) }
            sleep(1)
            snap("12-ajout")
        }

        // Recherche → fiche portion d'un aliment qui se compte (œuf) : la
        // quantité se saisit en unités (Petit / Moyen / Gros, « 1 œuf »).
        if app.buttons["journal.autres"].waitForExistence(timeout: 5) {
            if !app.buttons["Rechercher"].exists { app.buttons["journal.autres"].tap() }
            if app.buttons["Rechercher"].waitForExistence(timeout: 5) {
                app.buttons["Rechercher"].tap()
                let champ = app.textFields["recherche.champ"]
                if champ.waitForExistence(timeout: 8) {
                    champ.tap()
                    fermerTutorielClavier()
                    champ.clearAndType("oeuf")
                    sleep(4)
                    snap("15-recherche")
                    // Seconde requête, riche en produits de marque (photos,
                    // Nutri-Score), photographiée clavier rentré.
                    champ.clearAndType("pates")
                    sleep(5)
                    champ.typeText(XCUIKeyboardKey.return.rawValue)
                    sleep(2)
                    snap("17-recherche-photos")
                    champ.tap()
                    champ.clearAndType("oeuf")
                    sleep(4)
                    let resultat = app.buttons.matching(NSPredicate(
                        format: "(label CONTAINS[c] %@ OR label CONTAINS[c] %@) AND label CONTAINS %@ AND NOT (label BEGINSWITH %@)",
                        "oeuf", "œuf", "kcal", "Ajouter")).firstMatch
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

        // Fiche apport (premier anneau de « Apports à renforcer »). La section
        // est sous la ligne de saisie : on la fait monter à l'écran d'abord,
        // sinon le tap par coordonnées tombe sur « Écrire » ou « Code-barres ».
        app.swipeUp()
        sleep(1)
        let apport = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "pour cent de tes besoins")).firstMatch
        if apport.waitForExistence(timeout: 5) {
            apport.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
            sleep(2)
            snap("13-fiche-apport")
            fermerFeuille()
        }

        // Bilan complet (« Tout afficher »).
        if app.buttons["Tout afficher"].waitForExistence(timeout: 5) {
            app.buttons["Tout afficher"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            sleep(2)
            snap("14-bilan-complet")
            fermerFeuille()
        }

        // Progrès (le check-in du jour s'ouvre à la première visite : plus tard).
        app.buttons["tab.progres"].tap()
        sleep(2)
        let passer = app.buttons["Passer pour aujourd'hui"]
        if passer.waitForExistence(timeout: 4) {
            snap("19-checkin-popup")
            taper(passer)
            sleep(2)
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
        let noeud = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@", "Symptôme", "Apport à renforcer")).firstMatch
        if noeud.waitForExistence(timeout: 5) {
            noeud.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            sleep(2)
            snap("31-plan-noeud")
            fermerFeuille()
        }

        // Compléments.
        app.buttons["tab.complements"].tap()
        sleep(3)
        snap("40-complements")
        let tuile = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "sur 100")).firstMatch
        if tuile.waitForExistence(timeout: 4) {
            taper(tuile)
            sleep(2)
            snap("42-complements-fiche")
            fermerFeuille()
        }
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
        for (identifiant, capture) in [("reglages.abonnement", "52-abonnement"),
                                       ("reglages.compte", "53-compte"),
                                       ("reglages.objectifs", "54-objectifs"),
                                       ("reglages.questionnaire", "55-questionnaire"),
                                       ("reglages.methode", "55b-methode")] {
            let ligne = app.buttons[identifiant].firstMatch
            if ligne.waitForExistence(timeout: 5) {
                taper(ligne)
                sleep(2)
                snap(capture)
                retour()
            }
        }
        // Paywall depuis la carte Premium (gratuit) ou l'abonnement.
        if app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Essayer")).firstMatch.exists {
            taper(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Essayer")).firstMatch)
            sleep(3)
            snap("56-paywall")
            fermerFeuille()
        }

        // Récap animé, rejoué depuis les Réglages (lecture seule : sa fin ne
        // marque que le brief du jour comme vu, sur le simulateur).
        app.buttons["tab.reglages"].tap()
        sleep(1)
        let rejouer = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "bilan animé")).firstMatch
        for _ in 0..<4 where !rejouer.exists {
            app.swipeUp()
            sleep(1)
        }
        if rejouer.waitForExistence(timeout: 5) {
            taper(rejouer)
            sleep(3)
            snap("57-recap")
            let fermer = app.buttons["Fermer le bilan animé"]
            if fermer.waitForExistence(timeout: 3) {
                fermer.tap()
                sleep(1)
                let sortie = app.buttons["Aller à mon bilan"]
                if sortie.waitForExistence(timeout: 3) { sortie.tap() }
                sleep(1)
            }
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
            // Refonte du 1er octobre 2026 : l'accueil du parcours, puis ses écrans.
            if app.buttons["Commencer"].firstMatch.waitForExistence(timeout: 5) {
                app.buttons["Commencer"].firstMatch.tap()
                sleep(1)
                snap("71-questionnaire-question")
                // « Qu'est-ce qui t'amène ? » ne bloque pas : un écran de plus.
                // Les suivants attendent une réponse, le bouton y reste éteint.
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
            // La feuille ne se ferme plus en glissant : la croix, puis sa confirmation.
            if app.buttons["Fermer"].firstMatch.exists {
                app.buttons["Fermer"].firstMatch.tap()
                let plusTard = app.buttons["Reprendre plus tard"].firstMatch
                if plusTard.waitForExistence(timeout: 3) { plusTard.tap() }
                sleep(1)
            }
        }
    }

    // MARK: - 4. Tutoriel du premier lancement (hook DEBUG `-captureTutoriel`)

    func test04_Tutoriel() throws {
        app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES", "-hasSeenTabTour", "YES", "-hasSeenScanTour", "YES", "-kiwioCaptures", "YES", "-captureTutoriel", "YES"]
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["SCREENSHOT_EMAIL"] = env["SCREENSHOT_EMAIL"] ?? ""
        app.launchEnvironment["SCREENSHOT_PASSWORD"] = env["SCREENSHOT_PASSWORD"] ?? ""
        app.launch()

        connecterSiBesoin()
        XCTAssertTrue(app.buttons["tab.progres"].waitForExistence(timeout: 120))

        // Étape 1 : la carte de bienvenue.
        if app.buttons["Commencer"].waitForExistence(timeout: 15) {
            snap("80-tutoriel-bienvenue")
            taper(app.buttons["Commencer"])
            sleep(1)
            // Étape 2 : découpe sur le bouton « Dicter » du Journal. On ne le
            // touche pas (la dictée demanderait le micro du simulateur) : la
            // capture faite, on passe.
            _ = app.buttons["journal.dicter"].waitForExistence(timeout: 6)
            snap("81-tutoriel-bouton")
            if app.buttons["Passer"].firstMatch.exists {
                taper(app.buttons["Passer"].firstMatch)
                sleep(1)
            }
        }
    }

    // MARK: - 7. Conformité (9 octobre 2026) : avant / après
    //
    // Les écrans touchés par le lot 1 de l'audit de conformité, photographiés
    // de la même façon sur le code d'avant et sur celui d'après : prise de
    // sang, fiche complément, Réglages (bas, licences, abonnement), paywall
    // (deux ouvertures), molette d'âge réglée sous 16 ans.
    // ⚠️ Rien n'est envoyé : ni achat, ni « Voir mon bilan » (audit-b est le
    // compte de démonstration d'App Review). Les réponses du questionnaire
    // restent dans le brouillon local du simulateur.

    func test07_Conformite() throws {
        app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES", "-hasSeenTabTour", "YES", "-hasSeenScanTour", "YES", "-kiwioCaptures", "YES"]
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["SCREENSHOT_EMAIL"] = env["SCREENSHOT_EMAIL"] ?? ""
        app.launchEnvironment["SCREENSHOT_PASSWORD"] = env["SCREENSHOT_PASSWORD"] ?? ""
        app.launch()

        connecterSiBesoin()
        XCTAssertTrue(app.buttons["tab.progres"].waitForExistence(timeout: 120), "Barre d'onglets absente")
        attendreChargement()
        // L'écran d'accord (après) : on le photographie s'il est là, sans y
        // répondre, et le test s'arrête (rien ne doit s'écrire en base).
        if app.staticTexts["Avant de commencer, j'ai besoin de ton accord."].waitForExistence(timeout: 3) {
            snap("00-consentement")
        }

        // Prise de sang : la carte du Journal, puis sa feuille.
        let sang = app.buttons["journal.priseDeSang"].firstMatch
        var defilements = 0
        while !(sang.exists && sang.isHittable) && defilements < 4 {
            app.swipeUp()
            sleep(1)
            defilements += 1
        }
        if sang.waitForExistence(timeout: 5) {
            snap("01-journal-carte-sang")
            taper(sang)
            sleep(2)
            snap("02-sang-feuille")
            app.swipeUp()
            sleep(1)
            snap("03-sang-feuille-bas")
            fermerFeuille()
        }

        // Compléments : la fiche d'un apport (le « pourquoi cette forme »).
        app.buttons["tab.complements"].tap()
        sleep(3)
        let tuile = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "sur 100")).firstMatch
        if tuile.waitForExistence(timeout: 4) {
            taper(tuile)
            sleep(2)
            snap("04-complements-fiche")
            app.swipeUp()
            sleep(1)
            snap("05-complements-fiche-bas")
            fermerFeuille()
        }

        // Réglages : le haut (carte Premium, essai), le bas (liens légaux),
        // les licences, l'abonnement (remboursement).
        app.buttons["tab.reglages"].tap()
        sleep(2)
        snap("06-reglages")
        app.swipeUp()
        sleep(1)
        snap("07-reglages-bas")
        let licences = app.buttons["reglages.licences"].firstMatch
        if licences.waitForExistence(timeout: 3) {
            taper(licences)
            sleep(2)
            snap("08-licences")
            retour()
        }
        app.swipeDown()
        sleep(1)
        let abonnement = app.buttons["reglages.abonnement"].firstMatch
        if abonnement.waitForExistence(timeout: 4) {
            taper(abonnement)
            sleep(2)
            snap("09-abonnement")
            retour()
        }

        // Paywall depuis la carte Premium, deux fois : le comparatif ne revient
        // qu'une fois par semaine (après).
        let carte = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Essayer", "Découvrir Kiwio Premium")).firstMatch
        if carte.waitForExistence(timeout: 5) {
            taper(carte)
            sleep(3)
            snap("10-paywall-1re-ouverture")
            let passer = app.buttons["Passer à Premium"].firstMatch
            if passer.waitForExistence(timeout: 4) {
                taper(passer)
                sleep(2)
            }
            snap("11-paywall-formules")
            app.swipeUp()
            sleep(1)
            snap("12-paywall-formules-bas")
            fermerFeuille()
            sleep(2)
            if carte.waitForExistence(timeout: 5) {
                taper(carte)
                sleep(3)
                snap("13-paywall-2e-ouverture")
                fermerFeuille()
            }
        }

        // La molette d'âge réglée sous 16 ans, dans le questionnaire d'un
        // compte « sans bilan » (en mémoire seulement).
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES", "-hasSeenTabTour", "YES", "-hasSeenScanTour", "YES", "-kiwioCaptures", "YES", "-captureDecouverte", "YES"]
        app.launchEnvironment["SCREENSHOT_EMAIL"] = env["SCREENSHOT_EMAIL"] ?? ""
        app.launchEnvironment["SCREENSHOT_PASSWORD"] = env["SCREENSHOT_PASSWORD"] ?? ""
        app.launch()
        connecterSiBesoin()
        XCTAssertTrue(app.buttons["tab.progres"].waitForExistence(timeout: 120))
        attendreChargement()
        let porte = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "questionnaire")).firstMatch
        guard porte.waitForExistence(timeout: 10) else { return }
        taper(porte)
        sleep(2)
        guard bilanSuite("Commencer") else { return quitterLeBilan() }
        bilanToucher("Fatigue")
        guard bilanSuite() else { return quitterLeBilan() }
        let prenom = app.textFields["Ton prénom"]
        if prenom.waitForExistence(timeout: 2) {
            prenom.tap()
            prenom.typeText("Léa")
            guard bilanSuite() else { return quitterLeBilan() }
        }
        bilanToucher("Femme")
        let age = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Âge")).firstMatch
        if age.waitForExistence(timeout: 3) {
            let debut = age.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            debut.press(forDuration: 0.1, thenDragTo: debut.withOffset(CGVector(dx: 0, dy: 240)))
            sleep(2)
            snap("14-age-sous-16")
        }
        quitterLeBilan()
    }

    // MARK: - 8. Grande taille de texte : les onglets, sans aucune saisie
    //
    // Audit d'accessibilité (9 oct. 2026) : comparer chaque écran principal
    // à la taille par défaut et à une taille d'accessibilité (entrée
    // `taille_texte` du workflow). Lecture seule : on ne fait que changer
    // d'onglet, défiler et ouvrir puis fermer le paywall et le Récap. Rien
    // n'est ajouté au journal du compte d'audit.

    func test08_GrandeTaille() throws {
        app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES", "-hasSeenTabTour", "YES", "-hasSeenScanTour", "YES", "-kiwioCaptures", "YES"]
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["SCREENSHOT_EMAIL"] = env["SCREENSHOT_EMAIL"] ?? ""
        app.launchEnvironment["SCREENSHOT_PASSWORD"] = env["SCREENSHOT_PASSWORD"] ?? ""
        app.launch()

        connecterSiBesoin()
        XCTAssertTrue(app.buttons["tab.progres"].waitForExistence(timeout: 120), "Barre d'onglets absente : connexion ou chargement du profil en échec")
        attendreChargement()

        for (onglet, nom) in [("tab.journal", "journal"), ("tab.progres", "progres"), ("tab.plan", "plan"),
                              ("tab.complements", "complements"), ("tab.reglages", "reglages")] {
            app.buttons[onglet].tap()
            sleep(2)
            // Le check-in du jour peut s'ouvrir sur Progrès : on le passe.
            let passer = app.buttons["Passer pour aujourd'hui"]
            if passer.waitForExistence(timeout: 2) {
                taper(passer)
                sleep(1)
            }
            snap("20-\(nom)-haut")
            app.swipeUp()
            sleep(1)
            snap("21-\(nom)-milieu")
            app.swipeUp()
            sleep(1)
            snap("22-\(nom)-bas")
            app.swipeDown()
            app.swipeDown()
            app.swipeDown()
            sleep(1)
        }

        // Paywall, depuis la carte Premium des Réglages.
        app.buttons["tab.reglages"].tap()
        sleep(1)
        // La carte s'annonce « Essayer 7 jours gratuits » ou « Découvrir
        // Kiwio Premium » selon l'éligibilité à l'essai.
        let essai = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label == %@",
                                                     "Essayer", "Découvrir Kiwio Premium")).firstMatch
        if essai.waitForExistence(timeout: 4) {
            taper(essai)
            sleep(3)
            snap("30-paywall-haut")
            app.swipeUp()
            sleep(1)
            snap("31-paywall-bas")
            fermerFeuille()
            sleep(1)
        }
        // Une page poussée par erreur masquerait la ligne du Récap.
        if app.navigationBars.buttons.element(boundBy: 0).exists { retour() }

        // Récap animé, rejoué depuis les Réglages.
        let rejouer = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "bilan animé")).firstMatch
        for _ in 0..<5 where !(rejouer.exists && rejouer.isHittable) {
            app.swipeUp()
            sleep(1)
        }
        if rejouer.waitForExistence(timeout: 4) {
            taper(rejouer)
            sleep(3)
            snap("40-recap")
            let fermer = app.buttons["Fermer le bilan animé"]
            if fermer.waitForExistence(timeout: 3) {
                fermer.tap()
                sleep(1)
                let sortie = app.buttons["Aller à mon bilan"]
                if sortie.waitForExistence(timeout: 3) { sortie.tap() }
            }
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
        guard app.buttons["journal.autres"].waitForExistence(timeout: 5) else { return }
        if !app.buttons["Rechercher"].exists { taper(app.buttons["journal.autres"]) }
        guard app.buttons["Rechercher"].waitForExistence(timeout: 5) else { return }
        app.buttons["Rechercher"].tap()
        let champ = app.textFields["recherche.champ"]
        guard champ.waitForExistence(timeout: 8) else { fermerFeuille(); return }
        champ.tap()
        fermerTutorielClavier()
        champ.clearAndType(aliment)
        sleep(4)
        // Première ligne de résultats → fiche portion → « Ajouter au … ».
        let premier = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ AND label CONTAINS %@ AND NOT (label BEGINSWITH %@)", aliment, "kcal", "Ajouter")).firstMatch
        if premier.waitForExistence(timeout: 5) {
            premier.tap()
            // CTA de la fiche portion (« Ajouter le midi »…) par identifiant :
            // « Ajouter une unité » (le + du compteur) et « Ajouter un repas »
            // (le bouton flottant) commencent pareil.
            let ajouter = app.buttons["portion.valider"]
            if ajouter.waitForExistence(timeout: 6) {
                ajouter.tap()
                // L'ajout est réseau : la fiche ne se referme qu'une fois
                // l'écriture faite. Fermer la recherche avant, c'est taper
                // dans le vide sous la fiche encore ouverte.
                _ = ajouter.waitForNonExistence(timeout: 20)
                sleep(1)
            } else {
                app.swipeDown(velocity: .fast)
            }
        }
        fermerFeuille()
        sleep(1)
        // La carte « Bien joué » monte une fois la recherche refermée : on la
        // photographie (une fois), puis « Continuer ».
        let continuer = app.buttons["Continuer"]
        if continuer.waitForExistence(timeout: 8) {
            if !gratificationPhotographiee {
                snap("18-gratification")
                gratificationPhotographiee = true
            }
            taper(continuer)
            sleep(1)
        }
    }

    private var gratificationPhotographiee = false

    // MARK: - 5. Le questionnaire en quatre étapes, écran par écran (hook DEBUG `-captureDecouverte`)
    //
    // Parcourt le bilan du premier au dernier écran et photographie chacun.
    // ⚠️ Ne touche JAMAIS « Voir mon bilan » : le compte d'audit est aussi le
    // compte de démonstration d'App Review, son questionnaire en base ne doit
    // pas être réécrit. Tout ce que ce test répond reste dans le brouillon
    // local du simulateur.

    func test05_QuestionnaireEnQuatreEtapes() throws {
        app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES", "-hasSeenTabTour", "YES", "-hasSeenScanTour", "YES", "-kiwioCaptures", "YES", "-captureDecouverte", "YES"]
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["SCREENSHOT_EMAIL"] = env["SCREENSHOT_EMAIL"] ?? ""
        app.launchEnvironment["SCREENSHOT_PASSWORD"] = env["SCREENSHOT_PASSWORD"] ?? ""
        app.launch()

        connecterSiBesoin()
        XCTAssertTrue(app.buttons["tab.progres"].waitForExistence(timeout: 120))
        attendreChargement()

        let porte = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "questionnaire")).firstMatch
        guard porte.waitForExistence(timeout: 10) else {
            XCTFail("La porte vers le questionnaire est introuvable sur le Journal.")
            return
        }
        taper(porte)
        sleep(2)

        // Accueil
        snap("80-bilan-accueil")
        guard bilanSuite("Commencer") else { return quitterLeBilan() }

        // Étape 1 · Toi
        bilanToucher("Fatigue")
        bilanToucher("Chute de cheveux")
        bilanToucher("Plus d'énergie")
        snap("81-bilan-motif")
        guard bilanSuite() else { return quitterLeBilan() }

        // Le prénom n'est demandé que si le compte ne le connaît pas.
        let prenom = app.textFields["Ton prénom"]
        if prenom.waitForExistence(timeout: 2) {
            prenom.tap()
            prenom.typeText("Léa")
            snap("81-bilan-prenom")
            guard bilanSuite() else { return quitterLeBilan() }
        }

        bilanToucher("Femme")
        for molette in ["Âge", "Taille", "Poids"] { bilanToucherElement(molette) }
        snap("82-bilan-reperes")
        guard bilanSuite() else { return quitterLeBilan() }

        snap("83-bilan-fin-etape-1")
        guard bilanSuite() else { return quitterLeBilan() }

        // Étape 2 · Ton quotidien
        bilanToucher("Surtout en intérieur")
        bilanToucher("Très peu")
        bilanToucher("Claire")
        snap("84-bilan-soleil")
        guard bilanSuite() else { return quitterLeBilan() }

        bilanToucher("4-5 fois")
        bilanToucher("Stable")
        snap("85-bilan-bouger")
        guard bilanSuite() else { return quitterLeBilan() }

        bilanToucher("5 et +")
        bilanToucher("Pendant les repas")
        bilanToucher("3 à 5")
        snap("86-bilan-boire")
        guard bilanSuite() else { return quitterLeBilan() }

        bilanToucher("Rarement")
        snap("87-bilan-alcool-tabac")
        guard bilanSuite() else { return quitterLeBilan() }

        snap("88-bilan-fin-etape-2")
        guard bilanSuite() else { return quitterLeBilan() }

        // Étape 3 · Ta forme
        bilanGlisser("Ton stress", 0.8)
        bilanGlisser("Au réveil", 0.7)
        snap("89-bilan-ressenti")
        guard bilanSuite() else { return quitterLeBilan() }

        bilanGlisser("Écrans avant de dormir", 0.75)
        bilanGlisser("Tu dors", 0.2)
        snap("90-bilan-nuits")
        guard bilanSuite() else { return quitterLeBilan() }

        bilanToucher("Oui, souvent")
        snap("91-bilan-ventre")
        guard bilanSuite() else { return quitterLeBilan() }

        bilanToucher("Abondantes")
        // Une question à la fois : on laisse « Tes règles » se ranger avant
        // de répondre à la suivante, qui a aussi un « Non concernée ».
        sleep(1)
        bilanToucher("Non concernée")
        snap("92-bilan-cycle")
        guard bilanSuite() else { return quitterLeBilan() }

        snap("93-bilan-fin-etape-3")
        guard bilanSuite() else { return quitterLeBilan() }

        // Étape 4 · Ton assiette
        bilanToucher("Végétarien")
        snap("94-bilan-regime")
        guard bilanSuite() else { return quitterLeBilan() }

        snap("95-bilan-provisoire")
        guard bilanSuite("Passer à table") else { return quitterLeBilan() }

        bilanToucher("Pain complet")
        bilanToucher("Beaucoup")
        bilanToucher("Kiwis")
        snap("96-bilan-repas-a-petit-dej")
        guard bilanSuite("Repas suivant : Midi") else { return quitterLeBilan() }

        bilanToucher("Lentilles")
        snap("96-bilan-repas-b-midi")
        bilanToucher("Chercher un autre aliment")
        sleep(1)
        snap("96-bilan-repas-c-catalogue")
        bilanToucher("Terminé")
        sleep(1)
        guard bilanSuite("Repas suivant : Goûter") else { return quitterLeBilan() }

        bilanToucher("Amandes")
        snap("96-bilan-repas-d-gouter")
        guard bilanSuite("Repas suivant : Soir") else { return quitterLeBilan() }

        bilanToucher("Épinards")
        bilanToucher("Pas beaucoup")
        snap("96-bilan-repas-e-soir")
        guard bilanSuite("J'ai fini ma journée") else { return quitterLeBilan() }

        bilanToucher("Poisson, crustacés")
        snap("97-bilan-jamais")
        guard bilanSuite("Terminer") else { return quitterLeBilan() }

        // Fin : on photographie, on n'envoie pas.
        sleep(2)
        snap("98-bilan-fin")

        // Pour affiner : les deux premiers écrans.
        bilanToucher("Affiner d'abord")
        sleep(1)
        snap("99-bilan-affiner-a-table")

        quitterLeBilan()
        sleep(2)
        // La carte « Ton bilan t'attend » est plus bas dans le Journal.
        let reprendre = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reprendre mon bilan")).firstMatch
        var glissements = 0
        while reprendre.exists && !reprendre.isHittable && glissements < 4 {
            app.swipeUp(velocity: .slow)
            glissements += 1
        }
        sleep(1)
        snap("99-bilan-journal-reprise")
    }

    /// Touche un bouton du questionnaire par son libellé, s'il est là.
    private func bilanToucher(_ libelle: String) {
        let bouton = app.buttons[libelle].firstMatch
        guard bouton.waitForExistence(timeout: 3) else {
            NSLog("captures: bouton introuvable « %@ »", libelle)
            return
        }
        taper(bouton)
        usleep(350_000)
    }

    /// Touche un élément qui n'est pas un bouton (une molette).
    private func bilanToucherElement(_ libelle: String) {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", libelle)).firstMatch
        guard element.waitForExistence(timeout: 3) else {
            NSLog("captures: élément introuvable « %@ »", libelle)
            return
        }
        taper(element)
        usleep(350_000)
    }

    /// Règle un curseur.
    private func bilanGlisser(_ libelle: String, _ position: CGFloat) {
        let curseur = app.sliders[libelle].firstMatch
        guard curseur.waitForExistence(timeout: 3) else {
            NSLog("captures: curseur introuvable « %@ »", libelle)
            return
        }
        curseur.adjust(toNormalizedSliderPosition: position)
        usleep(350_000)
    }

    /// Touche le bouton du bas. Faux s'il est absent ou éteint : l'écran
    /// attend une réponse que le test n'a pas su donner, on le photographie.
    private func bilanSuite(_ libelle: String = "Continuer") -> Bool {
        let bouton = app.buttons[libelle].firstMatch
        guard bouton.waitForExistence(timeout: 4), bouton.isEnabled else {
            snap("79-bilan-bloque")
            XCTFail("Le bouton « \(libelle) » est absent ou éteint : le parcours s'arrête ici.")
            return false
        }
        taper(bouton)
        sleep(1)
        return true
    }

    /// Referme le questionnaire par sa croix, sans rien envoyer.
    private func quitterLeBilan() {
        let croix = app.buttons["Fermer"].firstMatch
        guard croix.waitForExistence(timeout: 3) else { return }
        croix.tap()
        let plusTard = app.buttons["Reprendre plus tard"].firstMatch
        if plusTard.waitForExistence(timeout: 3) { plusTard.tap() }
        sleep(1)
    }

    // MARK: - 6. Micronutriments en gratuit + « Écrire » (7 octobre 2026)
    //
    // Le compte d'audit est gratuit avec un bilan fait : la carte des
    // micronutriments s'affiche verrouillée (noms nets, « Débloquer avec
    // Premium » sur chaque ligne). Puis « Écrire » : un texte tapé, puis
    // « Effacer ». ⚠️ Ne touche JAMAIS « Lancer l'analyse » ni « Ajouter » :
    // rien n'est envoyé ni enregistré.

    func test06_MicrosGratuitEtEcrire() throws {
        app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES", "-hasSeenTabTour", "YES", "-hasSeenScanTour", "YES", "-kiwioCaptures", "YES"]
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["SCREENSHOT_EMAIL"] = env["SCREENSHOT_EMAIL"] ?? ""
        app.launchEnvironment["SCREENSHOT_PASSWORD"] = env["SCREENSHOT_PASSWORD"] ?? ""
        app.launch()

        connecterSiBesoin()
        XCTAssertTrue(app.buttons["tab.progres"].waitForExistence(timeout: 120), "Barre d'onglets absente : connexion ou chargement du profil en échec")
        attendreChargement()
        sleep(3)

        // Descendre jusqu'à la carte (son bouton d'essai en bas).
        let essai = app.buttons["journal.micros.debloquer"]
        for _ in 0..<10 where !(essai.exists && essai.isHittable) {
            app.swipeUp(velocity: .slow)
            sleep(1)
        }
        let voirLes = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Voir les")).firstMatch
        // Le haut de la carte : on remonte d'un cran pour voir l'en-tête.
        app.swipeDown(velocity: .slow)
        sleep(1)
        snap("01-micros-gratuit-haut")
        app.swipeUp(velocity: .slow)
        sleep(1)
        snap("02-micros-gratuit-bas")

        if voirLes.waitForExistence(timeout: 3) {
            taper(voirLes)
            sleep(2)
            snap("03-micros-deplie")
            app.swipeUp(velocity: .slow)
            sleep(1)
            snap("04-micros-deplie-suite")
        }
        let mineraux = app.buttons["Minéraux"].firstMatch
        if mineraux.exists {
            for _ in 0..<4 where !mineraux.isHittable { app.swipeDown(velocity: .slow); sleep(1) }
            taper(mineraux)
            sleep(1)
            snap("05-micros-filtre-mineraux")
        }

        // « Écrire » : remonter en haut du Journal, ouvrir la saisie.
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
        sleep(1)
        if app.buttons["journal.autres"].waitForExistence(timeout: 5) {
            if !app.buttons["Écrire"].exists { taper(app.buttons["journal.autres"]) }
            let ecrire = app.buttons["Écrire"].firstMatch
            if ecrire.waitForExistence(timeout: 5) {
                taper(ecrire)
                sleep(2)
                snap("06-ecrire-vide")
                let champ = app.textFields["journal.texte"].exists ? app.textFields["journal.texte"] : app.textViews["journal.texte"]
                if champ.waitForExistence(timeout: 5) {
                    fermerTutorielClavier()
                    champ.typeText("150 g de pâtes, du poulet et une cuillère d'huile d'olive")
                    sleep(1)
                    snap("07-ecrire-texte")
                    let effacer = app.buttons["journal.texte.effacer"]
                    if effacer.waitForExistence(timeout: 3) {
                        taper(effacer)
                        sleep(1)
                        snap("08-ecrire-efface")
                    }
                }
                fermerFeuille()
            }
        }
    }

    // MARK: - 7. Réglages › Exporter mes données (audit de conformité, 9 oct. 2026)

    /// Le fichier part dans la feuille de partage : son nom et son poids s'y
    /// lisent, de quoi comparer avant / après. Lecture seule pour le compte :
    /// l'export n'écrit qu'une trace dans le journal de sécurité (`audit_log`),
    /// aucune donnée de la personne. Le bouton est cherché par son libellé
    /// (pas d'identifiant d'accessibilité sur cette ligne).
    func test07_ExporterMesDonnees() throws {
        app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES", "-hasSeenTabTour", "YES", "-hasSeenScanTour", "YES", "-kiwioCaptures", "YES"]
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["SCREENSHOT_EMAIL"] = env["SCREENSHOT_EMAIL"] ?? ""
        app.launchEnvironment["SCREENSHOT_PASSWORD"] = env["SCREENSHOT_PASSWORD"] ?? ""
        app.launch()

        connecterSiBesoin()
        XCTAssertTrue(app.buttons["tab.progres"].waitForExistence(timeout: 120), "Barre d'onglets absente : connexion ou chargement du profil en échec")
        attendreChargement()

        app.buttons["tab.reglages"].tap()
        sleep(2)
        let exporter = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Exporter mes données")).firstMatch
        for _ in 0..<8 where !(exporter.exists && exporter.isHittable) {
            app.swipeUp(velocity: .slow)
            sleep(1)
        }
        snap("01-reglages-exporter")
        guard exporter.exists else { return }
        taper(exporter)

        // L'export appelle le serveur avant d'ouvrir la feuille de partage.
        let fichier = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "healthmap-export")).firstMatch
        _ = fichier.waitForExistence(timeout: 45)
        sleep(2)
        snap("02-export-feuille-de-partage")
        fermerFeuille()
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

    /// Tap par coordonnées : XCUITest déclare « non touchable » des boutons
    /// pourtant visibles et actifs (cartes SwiftUI sous le bouton flottant,
    /// overlays), et refuse alors le tap classique.
    private func taper(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func snap(_ name: String) {
        NSLog("captures: %@", name)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    /// Efface le texte du champ puis tape `texte`.
    func clearAndType(_ texte: String) {
        let actuel = (value as? String) ?? ""
        if !actuel.isEmpty, actuel != (placeholderValue ?? "") {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: actuel.count))
        }
        typeText(texte)
    }
}
